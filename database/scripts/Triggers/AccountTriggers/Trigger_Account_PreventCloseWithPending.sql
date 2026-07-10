/* =========================================================
   Trigger_Account_PreventCloseWithPending.sql
   TR_Account_PreventCloseWithPending

   Blocks any UPDATE that transitions an account's AccountStatus
   INTO 'Closed' while that account still has a 'Pending'
   transaction on either side (FromAccountID or ToAccountID).

   This is enforced at the trigger level (not just inside
   sp_Account_Close) so it also protects against any other code
   path that might set AccountStatus = 'Closed' directly.

   Must run AFTER TableCreation.sql.
   ========================================================= */

CREATE OR ALTER TRIGGER dbo.TR_Account_PreventCloseWithPending
ON dbo.Account
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT UPDATE(AccountStatus)
            RETURN;

        IF EXISTS (
            SELECT 1
            FROM inserted i
            INNER JOIN deleted d ON i.AccountID = d.AccountID
            WHERE i.AccountStatus = 'Closed'
              AND d.AccountStatus <> 'Closed'
              AND EXISTS (
                    SELECT 1 FROM dbo.Transactions tr
                    WHERE tr.TransactionStatus = 'Pending'
                      AND (tr.FromAccountID = i.AccountID OR tr.ToAccountID = i.AccountID)
              )
        )
        BEGIN
            RAISERROR('Cannot close an account that has a Pending transaction in flight.', 16, 1);
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
