/* =========================================================
   Procedure_Customer_Update.sql
   sp_Customer_Update
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Customer can update only own Customer record.
   - Effective Employee/Admin/HighAdmin can update any customer.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Customer_Update', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_Update;
GO

CREATE PROCEDURE dbo.sp_Customer_Update
(
    @CustomerID     INT,
    @FirstName      NVARCHAR(50),
    @LastName       NVARCHAR(50),
    @Phone          NVARCHAR(20),
    @Email          NVARCHAR(100),
    @Address        NVARCHAR(200) = NULL,
    @UserID         INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE @CallerCustomerID INT;
        SELECT @CallerCustomerID = CustomerID
        FROM dbo.Users
        WHERE UserID = @UserID AND IsActive = 1;

        IF @UserID IS NULL OR dbo.fn_UserHasEffectiveRole(@UserID, N'Customer') = 0
        BEGIN RAISERROR('A valid authenticated user is required.', 16, 1); RETURN; END;

        IF dbo.fn_UserHasEffectiveRole(@UserID, N'Employee') = 0
           AND dbo.fn_UserHasEffectiveRole(@UserID, N'Admin') = 0
           AND dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin') = 0
           AND @CallerCustomerID <> @CustomerID
        BEGIN
            RAISERROR('Customer users can update only their own customer record.', 16, 1);
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID AND IsActive = 1)
        BEGIN RAISERROR('Customer does not exist or is not active.', 16, 1); RETURN; END;
        IF @FirstName IS NULL OR LEN(LTRIM(RTRIM(@FirstName))) = 0
        BEGIN RAISERROR('First name is required.', 16, 1); RETURN; END;
        IF @LastName IS NULL OR LEN(LTRIM(RTRIM(@LastName))) = 0
        BEGIN RAISERROR('Last name is required.', 16, 1); RETURN; END;
        IF @Phone IS NULL OR LEN(LTRIM(RTRIM(@Phone))) = 0
        BEGIN RAISERROR('Phone number is required.', 16, 1); RETURN; END;
        IF @Email IS NULL OR LEN(LTRIM(RTRIM(@Email))) = 0
        BEGIN RAISERROR('Email is required.', 16, 1); RETURN; END;

        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Customer WHERE Phone = @Phone AND CustomerID <> @CustomerID)
        BEGIN RAISERROR('Another customer already uses this phone number.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS (SELECT 1 FROM dbo.Customer WHERE Email = @Email AND CustomerID <> @CustomerID)
        BEGIN RAISERROR('Another customer already uses this email.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        UPDATE dbo.Customer
        SET FirstName = LTRIM(RTRIM(@FirstName)),
            LastName  = LTRIM(RTRIM(@LastName)),
            Phone     = LTRIM(RTRIM(@Phone)),
            Email     = LTRIM(RTRIM(@Email)),
            Address   = @Address
        WHERE CustomerID = @CustomerID;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@UserID, 'CustomerUpdated', 'Customer', @CustomerID, 'Customer contact details updated.');

        COMMIT TRANSACTION;
        SELECT @CustomerID AS CustomerID, 'Updated' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN;
    END CATCH
END;
GO
