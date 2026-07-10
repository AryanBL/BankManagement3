/* =========================================================
   Trigger_Transactions_EnforceTypePattern_Update.sql

   Supersedes the version of TR_Transactions_EnforceTypePattern
   originally created in TableCreation.sql, adding the 'Interest'
   pattern (same shape as Deposit: FromAccountID must be NULL,
   ToAccountID required) -- interest is money created by the bank
   and credited to a customer's account, with no internal source
   account.

   CREATE OR ALTER simply redefines the existing trigger object,
   so no DROP is needed.

   Must run AFTER TableCreation.sql and
   Schema_CustomerAccessAndBranchLedger.sql (needs the 'Interest'
   TransactionType row to exist for the pattern to ever match,
   though the trigger logic itself does not depend on row
   existence at definition time).
   ========================================================= */

CREATE OR ALTER TRIGGER dbo.TR_Transactions_EnforceTypePattern
ON dbo.Transactions
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF EXISTS (
            SELECT 1
            FROM inserted i
            INNER JOIN dbo.TransactionType t ON i.TransactionTypeID = t.TransactionTypeID
            WHERE
                (t.TypeName IN ('Deposit', 'Interest') AND (i.FromAccountID IS NOT NULL OR i.ToAccountID IS NULL))
             OR (t.TypeName = 'Withdrawal' AND (i.ToAccountID IS NOT NULL OR i.FromAccountID IS NULL))
             OR (t.TypeName = 'Transfer'   AND (i.FromAccountID IS NULL OR i.ToAccountID IS NULL))
        )
        BEGIN
            RAISERROR('FromAccountID/ToAccountID pattern does not match the transaction type.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
