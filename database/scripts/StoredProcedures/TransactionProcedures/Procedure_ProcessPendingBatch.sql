/* =========================================================
   Procedure_ProcessPendingBatch.sql
   sp_Transaction_ProcessPendingBatch

   Higher-level protocol that processes ALL currently-ready
   'Pending' transactions in ONE set-based pass, so they are
   genuinely handled simultaneously at the engine level -- not
   one at a time in a loop that merely looks fast.

   This intentionally does NOT call sp_Transaction_Finalize
   per row (that procedure is still kept, unchanged, for
   on-demand single-transaction finalization, e.g. "check on
   my transfer now"). This procedure reimplements the same
   validation rules as sp_Transaction_Finalize, but applies
   them to the whole ready batch as set-based operations:

     1. Snapshot every Pending row whose ReadyToCompleteAt has
        already passed (i.e. the amount-based hold from
        fn_GetCompletionDelaySeconds has elapsed).
     2. Lock every account touched by that batch up front, in
        ascending AccountID order, to avoid deadlocking against
        another run of this same procedure or against
        sp_Transaction_Finalize acting on an overlapping account.
     3. In one query, identify which rows fail re-validation
        (account no longer Active/Dormant as appropriate, or the
        source account's stored Balance can no longer cover the
        amount) and mark only those 'Failed'.
     4. Apply every surviving row's balance effect with ONE
        grouped UPDATE per direction (debits, credits) so that
        multiple ready transactions on the same account are
        summed and applied together rather than serially.
        If a Dormant destination account receives a successful
        credit, it is changed back to Active.
     5. Explicitly snapshot every Dormant account that will be
        reactivated before the credit update is applied, then
        write a dedicated AccountReactivated AuditLog row for it.
     6. Mark every surviving row 'Completed' with CompletedAt
        = GETDATE(), and write one AuditLog row per processed
        transaction (success or failure).
     7. Return a result set describing what happened to each
        transaction in the batch.

   IMPORTANT - KNOWN SIMPLIFICATION (explicitly chosen):
   Step 3's minimum-balance check for the source side compares
   each row's Amount independently against that account's
   stored Balance at the start of the batch. If TWO ready
   Pending rows draw from the SAME account in the same batch,
   each is validated against the same starting Balance, not
   against a running total. It is possible (rare in practice,
   since most accounts won't have multiple large transactions
   maturing in the same few-second window) for two transactions
   that each individually look affordable to combine and push
   the account below its minimum balance once both are applied
   in step 4. This mirrors calling sp_Transaction_Finalize twice
   in the same instant rather than sequentially, and was chosen
   over the more complex running-total check for simplicity.

   Intended caller: a SQL Server Agent job step, on a recurring
   schedule (see AgentJob_ProcessPendingTransactions.sql), so the
   whole Pending queue is swept on a fixed interval. Can also be
   run manually for testing.

   Must run AFTER TableCreation.sql.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Transaction_ProcessPendingBatch
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        ----------------------------------------------------
        -- Step 1: snapshot every Pending row that is ready now.
        -- Snapshotting first (rather than re-querying Transactions
        -- repeatedly below) means every later step in this batch
        -- works against one consistent picture of "what's due".
        ----------------------------------------------------
        IF OBJECT_ID('tempdb..#ReadyTx') IS NOT NULL DROP TABLE #ReadyTx;

        SELECT
            TransactionID,
            FromAccountID,
            ToAccountID,
            Amount,
            CAST(0 AS BIT) AS IsFailed,
            CAST(NULL AS NVARCHAR(200)) AS FailReason
        INTO #ReadyTx
        FROM dbo.Transactions
        WHERE TransactionStatus = 'Pending'
          AND ReadyToCompleteAt <= GETDATE();

        IF NOT EXISTS (SELECT 1 FROM #ReadyTx)
        BEGIN
            COMMIT TRANSACTION;

            -- Nothing was ready this cycle. Return an empty result set
            -- with the same column shape as the normal path below, so
            -- callers (the Agent job, or a human) don't need to special
            -- case "zero rows" vs "some rows processed".
            SELECT
                CAST(NULL AS INT)            AS TransactionID,
                CAST(NULL AS NVARCHAR(20))   AS Outcome,
                CAST(NULL AS NVARCHAR(400))  AS Detail
            WHERE 1 = 0;

            RETURN;
        END;

        ----------------------------------------------------
        -- Step 2: lock every account touched by this batch, in a
        -- fixed ascending order, before reading any balance used
        -- for validation. This is what makes the whole batch one
        -- atomic, consistent unit instead of a collection of
        -- separately-racing checks.
        ----------------------------------------------------
        IF OBJECT_ID('tempdb..#TouchedAccounts') IS NOT NULL DROP TABLE #TouchedAccounts;

        SELECT DISTINCT AccountID
        INTO #TouchedAccounts
        FROM (
            SELECT FromAccountID AS AccountID FROM #ReadyTx WHERE FromAccountID IS NOT NULL
            UNION
            SELECT ToAccountID   AS AccountID FROM #ReadyTx WHERE ToAccountID   IS NOT NULL
        ) x;

        DECLARE @Dummy INT;
        SELECT @Dummy = a.AccountID
        FROM dbo.Account a WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN #TouchedAccounts t ON a.AccountID = t.AccountID
        ORDER BY a.AccountID;

        ----------------------------------------------------
        -- Step 3a: mark rows that fail SOURCE-side validation
        -- (Withdrawal / outgoing leg of a Transfer).
        ----------------------------------------------------
        UPDATE r
        SET
            IsFailed   = 1,
            FailReason = CASE
                WHEN a.AccountStatus IS NULL OR a.AccountStatus <> 'Active'
                    THEN 'Source account is no longer Active.'
                ELSE 'Source account no longer has sufficient balance.'
            END
        FROM #ReadyTx r
        INNER JOIN dbo.Account a ON a.AccountID = r.FromAccountID
        INNER JOIN dbo.AccountType at ON at.AccountTypeID = a.AccountTypeID
        WHERE r.FromAccountID IS NOT NULL
          AND r.IsFailed = 0
          AND (
                a.AccountStatus <> 'Active'
                OR (a.Balance - r.Amount) < at.MinBalance
              );

        ----------------------------------------------------
        -- Step 3b: mark rows that fail DESTINATION-side validation
        -- (Deposit / incoming leg of a Transfer). Skips rows
        -- already failed on the source side, matching the
        -- single-row procedure's "first failing check wins" order.
        ----------------------------------------------------
        UPDATE r
        SET
            IsFailed   = 1,
            FailReason = 'Destination account can no longer receive funds.'
        FROM #ReadyTx r
        INNER JOIN dbo.Account a ON a.AccountID = r.ToAccountID
        WHERE r.ToAccountID IS NOT NULL
          AND r.IsFailed = 0
          AND a.AccountStatus NOT IN ('Active', 'Dormant');

        -- Destination accounts that don't exist at all would have
        -- failed FK validation back when the row was inserted, so
        -- no separate "account missing" branch is needed here.

        ----------------------------------------------------
        -- Step 4: apply balance effects for every surviving row,
        -- as ONE grouped UPDATE per direction. Grouping by account
        -- means if several ready transactions in this batch share
        -- an account, their amounts are summed and applied together
        -- in a single engine operation rather than one at a time.
        ----------------------------------------------------
        UPDATE a
        SET a.Balance = a.Balance - debit.TotalAmount
        FROM dbo.Account a
        INNER JOIN (
            SELECT FromAccountID AS AccountID, SUM(Amount) AS TotalAmount
            FROM #ReadyTx
            WHERE FromAccountID IS NOT NULL AND IsFailed = 0
            GROUP BY FromAccountID
        ) debit ON a.AccountID = debit.AccountID;

        ----------------------------------------------------
        -- Step 4b: before applying destination-side credits,
        -- snapshot the Dormant accounts that are about to become
        -- Active. This must happen BEFORE the UPDATE below because
        -- after the UPDATE we would no longer be able to tell which
        -- destination accounts were Dormant at the start of crediting.
        --
        -- One row is stored per reactivated account, not per
        -- transaction. If several successful incoming transactions
        -- credit the same Dormant account in the same batch, the
        -- account is still reactivated only once.
        ----------------------------------------------------
        IF OBJECT_ID('tempdb..#ReactivatedAccounts') IS NOT NULL DROP TABLE #ReactivatedAccounts;

        SELECT
            a.AccountID,
            a.AccountNumber,
            credit.TotalAmount,
            credit.TransactionCount
        INTO #ReactivatedAccounts
        FROM dbo.Account a
        INNER JOIN (
            SELECT
                ToAccountID AS AccountID,
                SUM(Amount) AS TotalAmount,
                COUNT(*) AS TransactionCount
            FROM #ReadyTx
            WHERE ToAccountID IS NOT NULL
              AND IsFailed = 0
            GROUP BY ToAccountID
        ) credit ON a.AccountID = credit.AccountID
        WHERE a.AccountStatus = 'Dormant';

        ----------------------------------------------------
        -- Step 4c: apply destination-side credits. Dormant
        -- destination accounts are reactivated here because a
        -- completed incoming customer-initiated transaction is the
        -- selected business event for Dormant -> Active.
        ----------------------------------------------------
        UPDATE a
        SET
            a.Balance = a.Balance + credit.TotalAmount,
            a.AccountStatus = CASE WHEN a.AccountStatus = 'Dormant' THEN 'Active' ELSE a.AccountStatus END
        FROM dbo.Account a
        INNER JOIN (
            SELECT ToAccountID AS AccountID, SUM(Amount) AS TotalAmount
            FROM #ReadyTx
            WHERE ToAccountID IS NOT NULL AND IsFailed = 0
            GROUP BY ToAccountID
        ) credit ON a.AccountID = credit.AccountID;

        ----------------------------------------------------
        -- Step 5: finalize the Transactions rows themselves.
        ----------------------------------------------------
        UPDATE tr
        SET
            TransactionStatus = 'Completed',
            CompletedAt = GETDATE()
        FROM dbo.Transactions tr
        INNER JOIN #ReadyTx r ON tr.TransactionID = r.TransactionID
        WHERE r.IsFailed = 0;

        UPDATE tr
        SET TransactionStatus = 'Failed'
        FROM dbo.Transactions tr
        INNER JOIN #ReadyTx r ON tr.TransactionID = r.TransactionID
        WHERE r.IsFailed = 1;

        ----------------------------------------------------
        -- Step 6: one AuditLog row per processed transaction,
        -- written as a single set-based INSERT ... SELECT.
        ----------------------------------------------------
        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        SELECT
            NULL,
            CASE WHEN r.IsFailed = 1 THEN 'TransactionFinalizeFailed' ELSE 'TransactionFinalized' END,
            'Transactions',
            r.TransactionID,
            CASE
                WHEN r.IsFailed = 1 THEN r.FailReason
                ELSE CONCAT(
                    'Batch-finalized amount ', r.Amount,
                    ' FromAccountID=', ISNULL(CAST(r.FromAccountID AS VARCHAR(20)), 'NULL'),
                    ' ToAccountID=', ISNULL(CAST(r.ToAccountID AS VARCHAR(20)), 'NULL')
                )
            END
        FROM #ReadyTx r;

        ----------------------------------------------------
        -- Step 6b: explicit account-reactivation AuditLog rows.
        --
        -- The transaction audit above already records that the
        -- transaction was finalized. This extra audit row records
        -- the account lifecycle change itself:
        --
        --     Dormant -> Active
        --
        -- This makes Dormant reactivation visible in reports and
        -- audit reviews without having to infer it indirectly from
        -- balance changes.
        ----------------------------------------------------
        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        SELECT
            NULL,
            'AccountReactivated',
            'Account',
            ra.AccountID,
            CONCAT(
                'Dormant account reactivated by completed incoming transaction batch. ',
                'AccountNumber=', ra.AccountNumber,
                '; TotalIncomingAmount=', ra.TotalAmount,
                '; CompletedIncomingTransactionCount=', ra.TransactionCount
            )
        FROM #ReactivatedAccounts ra;

        ----------------------------------------------------
        -- Step 7: report what happened, for the caller / Agent
        -- job history / a human watching this run manually.
        ----------------------------------------------------
        SELECT
            r.TransactionID,
            CASE WHEN r.IsFailed = 1 THEN 'Failed' ELSE 'Completed' END AS Outcome,
            ISNULL(r.FailReason, 'Transaction completed successfully.') AS Detail
        INTO #BatchResult
        FROM #ReadyTx r;

        COMMIT TRANSACTION;

        SELECT TransactionID, Outcome, Detail
        FROM #BatchResult
        ORDER BY TransactionID;

        DROP TABLE #BatchResult;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
