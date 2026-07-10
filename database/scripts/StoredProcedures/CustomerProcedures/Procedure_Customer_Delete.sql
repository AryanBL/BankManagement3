/* =========================================================
   Procedure_Customer_Delete.sql
   sp_Customer_Delete
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Only effective Employee/Admin/HighAdmin can deactivate a
     customer record.
   - Customer self-deactivation is intentionally not allowed here.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Customer_Delete', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_Delete;
GO

CREATE PROCEDURE dbo.sp_Customer_Delete
(
    @CustomerID INT,
    @UserID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF @UserID IS NULL
           OR (dbo.fn_UserHasEffectiveRole(@UserID, N'Employee') = 0
           AND dbo.fn_UserHasEffectiveRole(@UserID, N'Admin') = 0
           AND dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin') = 0)
        BEGIN
            RAISERROR('Only an effective Employee, Admin, or HighAdmin can deactivate customers.', 16, 1);
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
        BEGIN RAISERROR('Customer does not exist.', 16, 1); RETURN; END;
        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID AND IsActive = 1)
        BEGIN RAISERROR('Customer is already inactive.', 16, 1); RETURN; END;

        IF EXISTS (
            SELECT 1
            FROM dbo.Account a
            INNER JOIN dbo.Transactions tr
                ON (tr.FromAccountID = a.AccountID OR tr.ToAccountID = a.AccountID)
            WHERE a.CustomerID = @CustomerID
              AND tr.TransactionStatus = 'Pending'
        )
        BEGIN
            RAISERROR('Cannot deactivate this customer: at least one account has a Pending transaction.', 16, 1);
            RETURN;
        END;

        BEGIN TRANSACTION;

        UPDATE dbo.Customer
        SET IsActive = 0
        WHERE CustomerID = @CustomerID;

        DECLARE @DeactivatedUsers TABLE(UserID INT PRIMARY KEY);

        UPDATE dbo.Users
        SET IsActive = 0
        OUTPUT inserted.UserID INTO @DeactivatedUsers(UserID)
        WHERE CustomerID = @CustomerID
          AND IsActive = 1;

        UPDATE S
        SET IsActive = 0,
            LogoutTime = GETDATE()
        FROM dbo.Sessions AS S
        INNER JOIN @DeactivatedUsers AS DU ON DU.UserID = S.UserID
        WHERE S.IsActive = 1;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@UserID, 'CustomerDeactivated', 'Customer', @CustomerID,
                'Customer soft-deactivated; linked user account(s) deactivated and active sessions ended.');

        COMMIT TRANSACTION;
        SELECT @CustomerID AS CustomerID, 'Deactivated' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN;
    END CATCH
END;
GO
