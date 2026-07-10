/* =========================================================
   Trigger_Customer_PreventDeactivateWithPending.sql
   TR_Customer_PreventDeactivateWithPending

   Blocks any UPDATE that transitions a customer's IsActive flag
   from 1 to 0 (i.e. sp_Customer_Delete's soft delete, or any
   other code path) while ANY account belonging to that customer
   still has a 'Pending' transaction on either side.

   Must run AFTER TableCreation.sql and
   Schema_CustomerAccessAndBranchLedger.sql (needs Customer.IsActive).
   ========================================================= */

CREATE OR ALTER TRIGGER dbo.TR_Customer_PreventDeactivateWithPending
ON dbo.Customer
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT UPDATE(IsActive)
            RETURN;

        IF EXISTS (
            SELECT 1
            FROM inserted i
            INNER JOIN deleted d ON i.CustomerID = d.CustomerID
            WHERE i.IsActive = 0
              AND d.IsActive = 1
              AND EXISTS (
                    SELECT 1
                    FROM dbo.Account a
                    INNER JOIN dbo.Transactions tr
                        ON (tr.FromAccountID = a.AccountID OR tr.ToAccountID = a.AccountID)
                    WHERE a.CustomerID = i.CustomerID
                      AND tr.TransactionStatus = 'Pending'
              )
        )
        BEGIN
            RAISERROR('Cannot deactivate a customer who has an account with a Pending transaction in flight.', 16, 1);
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
