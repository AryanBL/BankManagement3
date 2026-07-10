/* =========================================================
   Procedure_Loan_ProcessOverdueInstallments.sql
   sp_Loan_ProcessOverdueInstallments

   Higher-level protocol (same pattern as
   sp_Transaction_ProcessPendingBatch) that sweeps for
   installments that are seriously overdue and marks them, and
   their loan, 'Defaulted'.

   RULE: an installment becomes Defaulted when:
     - InstallmentStatus is NOT already 'Paid' or 'Defaulted', AND
     - DueDate is more than 90 days in the past, AND
     - it does NOT currently have a payment attempt in flight
       (PaymentTransactionID pointing at a still-'Pending'
       Transactions row).

   The third condition is deliberate: if a customer already
   initiated a withdrawal to pay an overdue installment, this
   sweep lets that attempt resolve first rather than yanking the
   installment into Defaulted out from under an in-progress
   payment. If that payment later succeeds, the existing
   TR_Transactions_SyncInstallmentStatus trigger marks it Paid as
   usual. If it fails, that same trigger reverts the installment
   to Late/Pending, and it becomes eligible for default again on
   a future run of this sweep if still 90+ days overdue.

   EFFECT ON THE LOAN: when ANY installment under a loan
   defaults, the WHOLE loan is marked 'Defaulted'. This has an
   immediate practical consequence with no further code needed:
   dbo.sp_Loan_PayInstallment already refuses to act on any loan
   whose LoanStatus is not 'Active' (see its
   "IF @LoanStatus <> 'Active'" check), so once a loan is
   Defaulted here, every other installment on it automatically
   becomes unpayable through the normal payment path.

   Intended caller: a SQL Server Agent job, run once daily (see
   AgentJob_ProcessOverdueInstallments.sql). Can also be run
   manually.

   Must run AFTER TableCreation.sql.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Loan_ProcessOverdueInstallments
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        ----------------------------------------------------
        -- Snapshot every installment eligible to default.
        ----------------------------------------------------
        IF OBJECT_ID('tempdb..#ToDefault') IS NOT NULL DROP TABLE #ToDefault;

        SELECT
            i.InstallmentID,
            i.LoanID,
            i.DueDate,
            i.Amount
        INTO #ToDefault
        FROM dbo.Installment i
        LEFT JOIN dbo.Transactions tr ON tr.TransactionID = i.PaymentTransactionID
        WHERE i.InstallmentStatus NOT IN ('Paid', 'Defaulted')
          AND i.DueDate < DATEADD(DAY, -90, CAST(GETDATE() AS DATE))
          AND (tr.TransactionID IS NULL OR tr.TransactionStatus <> 'Pending');

        IF NOT EXISTS (SELECT 1 FROM #ToDefault)
        BEGIN
            COMMIT TRANSACTION;

            -- Empty result set, same shape as the normal path below.
            SELECT
                CAST(NULL AS INT)          AS InstallmentID,
                CAST(NULL AS INT)          AS LoanID,
                CAST(NULL AS NVARCHAR(20)) AS Outcome
            WHERE 1 = 0;

            RETURN;
        END;

        ----------------------------------------------------
        -- Default the installments.
        ----------------------------------------------------
        UPDATE i
        SET i.InstallmentStatus = 'Defaulted'
        FROM dbo.Installment i
        INNER JOIN #ToDefault d ON i.InstallmentID = d.InstallmentID;

        ----------------------------------------------------
        -- Default every loan that has at least one defaulted
        -- installment from this sweep (only loans still Active --
        -- an already-Defaulted loan doesn't need rewriting).
        ----------------------------------------------------
        IF OBJECT_ID('tempdb..#LoansToDefault') IS NOT NULL DROP TABLE #LoansToDefault;

        SELECT DISTINCT d.LoanID
        INTO #LoansToDefault
        FROM #ToDefault d
        INNER JOIN dbo.Loan l ON l.LoanID = d.LoanID
        WHERE l.LoanStatus = 'Active';

        UPDATE l
        SET l.LoanStatus = 'Defaulted'
        FROM dbo.Loan l
        INNER JOIN #LoansToDefault ld ON l.LoanID = ld.LoanID;

        ----------------------------------------------------
        -- Audit: one row per defaulted installment, one row per
        -- defaulted loan.
        ----------------------------------------------------
        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        SELECT
            NULL,
            'InstallmentDefaulted',
            'Installment',
            d.InstallmentID,
            CONCAT('Installment for LoanID ', d.LoanID, ' (Amount ', d.Amount,
                   ') defaulted: due ', CONVERT(VARCHAR(10), d.DueDate, 120),
                   ', more than 90 days overdue with no successful payment.')
        FROM #ToDefault d;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        SELECT
            NULL,
            'LoanDefaulted',
            'Loan',
            ld.LoanID,
            'Loan marked Defaulted due to at least one installment more than 90 days overdue.'
        FROM #LoansToDefault ld;

        COMMIT TRANSACTION;

        ----------------------------------------------------
        -- Report what happened.
        ----------------------------------------------------
        SELECT
            d.InstallmentID,
            d.LoanID,
            'Defaulted' AS Outcome
        FROM #ToDefault d
        ORDER BY d.LoanID, d.InstallmentID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
