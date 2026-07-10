/* =========================================================
   Trigger_Account_SyncBranchLedger.sql
   TR_Account_SyncBranchLedger

   Fires on every INSERT/UPDATE of dbo.Account and mirrors any
   change in Balance into:
     - Branch.Balance (running total per branch), and
     - dbo.BranchLedger (one history row per account whose
       balance moved, recording the delta and the branch's
       balance after the batch).

   This is the SINGLE point where Branch.Balance is touched, so
   it stays correct no matter which procedure changed
   Account.Balance (sp_Transaction_Finalize,
   sp_Transaction_ProcessPendingBatch, sp_Transaction_Reverse,
   sp_Account_ApplyMonthlyInterest, or any future one) -- none of
   those procedures need to know Branch.Balance/BranchLedger
   exist at all.

   Handles INSERT too (a newly opened account with a non-zero
   opening balance, if that's ever allowed) by treating a
   missing `deleted` row as a prior balance of 0.

   KNOWN SIMPLIFICATION: when multiple accounts in the SAME
   branch change balance within the same statement/batch (e.g.
   sp_Transaction_ProcessPendingBatch crediting/debiting many
   accounts at once), each resulting BranchLedger row for that
   branch records the SAME BalanceAfter -- the branch's balance
   once the whole batch's deltas are applied -- rather than a
   strictly sequential running balance per individual account
   change. This mirrors the same batch-vs-per-row tradeoff
   already made in sp_Transaction_ProcessPendingBatch's own
   "KNOWN SIMPLIFICATION" note, and keeps this trigger set-based
   instead of row-by-row.

   Must run AFTER TableCreation.sql and
   Schema_CustomerAccessAndBranchLedger.sql (needs Branch.Balance
   and dbo.BranchLedger).
   ========================================================= */

CREATE OR ALTER TRIGGER dbo.TR_Account_SyncBranchLedger
ON dbo.Account
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (
            SELECT 1
            FROM inserted i
            LEFT JOIN deleted d ON i.AccountID = d.AccountID
            WHERE i.Balance <> ISNULL(d.Balance, 0)
        )
            RETURN;

        ----------------------------------------------------
        -- Per-account deltas for this batch.
        ----------------------------------------------------
        IF OBJECT_ID('tempdb..#AcctDelta') IS NOT NULL DROP TABLE #AcctDelta;

        SELECT
            i.AccountID,
            i.BranchID,
            i.Balance - ISNULL(d.Balance, 0) AS DeltaAmount
        INTO #AcctDelta
        FROM inserted i
        LEFT JOIN deleted d ON i.AccountID = d.AccountID
        WHERE i.Balance <> ISNULL(d.Balance, 0);

        ----------------------------------------------------
        -- Apply the net delta per branch to Branch.Balance.
        ----------------------------------------------------
        UPDATE b
        SET b.Balance = b.Balance + agg.NetDelta
        FROM dbo.Branch b
        INNER JOIN (
            SELECT BranchID, SUM(DeltaAmount) AS NetDelta
            FROM #AcctDelta
            GROUP BY BranchID
        ) agg ON agg.BranchID = b.BranchID;

        ----------------------------------------------------
        -- One BranchLedger row per account-level delta, stamped
        -- with that branch's balance after this batch.
        ----------------------------------------------------
        INSERT INTO dbo.BranchLedger (BranchID, TransactionID, DeltaAmount, BalanceAfter, Description)
        SELECT
            ad.BranchID,
            NULL,
            ad.DeltaAmount,
            b.Balance,
            CONCAT('Account balance change on AccountID ', ad.AccountID, ' of ', ad.DeltaAmount)
        FROM #AcctDelta ad
        INNER JOIN dbo.Branch b ON b.BranchID = ad.BranchID;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
