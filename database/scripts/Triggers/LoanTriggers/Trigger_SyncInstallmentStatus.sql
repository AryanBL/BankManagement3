/* =========================================================
   Trigger_SyncInstallmentStatus.sql
   TR_Transactions_SyncInstallmentStatus

   Reacts to dbo.Transactions status changes and keeps any
   linked dbo.Installment row in sync -- WITHOUT either
   sp_Transaction_Finalize or sp_Transaction_ProcessPendingBatch
   needing to know that loans/installments exist. Those two
   procedures only ever change TransactionStatus on dbo.Transactions;
   this trigger is what notices and reacts.

   Behavior:
     - A linked installment (Installment.PaymentTransactionID =
       this TransactionID) whose payment transaction just became
       'Completed' is marked 'Paid', with PaidDate = today.
     - A linked installment whose payment transaction just became
       'Failed' has its PaymentTransactionID cleared and is left
       in whatever non-Paid status it should naturally be in
       (Pending if not yet due, Late if past due), so the
       customer/employee can attempt payment again.
     - Any other status transition (e.g. into 'Pending' itself,
       which never happens after insert, or into 'Cancelled' via
       sp_Transaction_Reverse) is ignored here; a reversed/
       cancelled installment payment is handled explicitly by
       sp_Loan_PayInstallment / sp_Transaction_Reverse instead,
       not silently reinterpreted by this trigger.

   IMPORTANT: dbo.Transactions can be updated for MANY rows at
   once by sp_Transaction_ProcessPendingBatch, so this trigger
   is written as pure set-based joins against inserted/deleted --
   never assume a single-row update.

   Must run AFTER TableCreation.sql (needs Transactions and the
   Installment.PaymentTransactionID column).
   ========================================================= */

CREATE OR ALTER TRIGGER dbo.TR_Transactions_SyncInstallmentStatus
ON dbo.Transactions
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Only bother if TransactionStatus actually changed; UPDATE
        -- can fire for unrelated column changes too.
        IF NOT UPDATE(TransactionStatus)
            RETURN;

        ----------------------------------------------------
        -- Rows that just became Completed -> mark linked
        -- installment Paid.
        ----------------------------------------------------
        UPDATE i
        SET
            i.InstallmentStatus = 'Paid',
            i.PaidDate = CAST(GETDATE() AS DATE)
        FROM dbo.Installment i
        INNER JOIN inserted ins ON i.PaymentTransactionID = ins.TransactionID
        INNER JOIN deleted  del ON ins.TransactionID = del.TransactionID
        WHERE ins.TransactionStatus = 'Completed'
          AND del.TransactionStatus <> 'Completed';

        ----------------------------------------------------
        -- Rows that just became Failed -> release the link so
        -- the installment can be attempted again. Status reverts
        -- to 'Late' if past due, otherwise stays 'Pending'.
        ----------------------------------------------------
        UPDATE i
        SET
            i.PaymentTransactionID = NULL,
            i.InstallmentStatus = CASE
                WHEN i.DueDate < CAST(GETDATE() AS DATE) THEN 'Late'
                ELSE 'Pending'
            END
        FROM dbo.Installment i
        INNER JOIN inserted ins ON i.PaymentTransactionID = ins.TransactionID
        INNER JOIN deleted  del ON ins.TransactionID = del.TransactionID
        WHERE ins.TransactionStatus = 'Failed'
          AND del.TransactionStatus <> 'Failed'
          AND i.InstallmentStatus <> 'Paid';  -- safety: never downgrade an already-Paid row

        ----------------------------------------------------
        -- If every installment on a loan is now Paid, mark the
        -- loan itself Paid. Scoped to only the loans actually
        -- touched by this trigger firing, not a full table scan.
        ----------------------------------------------------
        UPDATE l
        SET l.LoanStatus = 'Paid'
        FROM dbo.Loan l
        WHERE l.LoanStatus = 'Active'
          AND EXISTS (
                SELECT 1
                FROM dbo.Installment i2
                INNER JOIN inserted ins2 ON i2.PaymentTransactionID = ins2.TransactionID
                WHERE i2.LoanID = l.LoanID
          )
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.Installment i3
                WHERE i3.LoanID = l.LoanID
                  AND i3.InstallmentStatus <> 'Paid'
          );
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
