/* =========================================================
   Procedure_Customer_Create.sql
   sp_Customer_Create
   ---------------------------------------------------------
   FINAL VERSION:
   - Supports public/self-signup creation when @CreatedByUserID
     is NULL.
   - If @CreatedByUserID is supplied, the caller must be an
     effective Employee, Admin, or HighAdmin.
   - AuditLog.UserID records the creator when available.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Customer_Create', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_Create;
GO

CREATE PROCEDURE dbo.sp_Customer_Create
(
    @FirstName      NVARCHAR(50),
    @LastName       NVARCHAR(50),
    @NationalID     NVARCHAR(20),
    @BirthDate      DATE,
    @Phone          NVARCHAR(20),
    @Email          NVARCHAR(100),
    @Address        NVARCHAR(200) = NULL,
    @CustomerID     INT OUTPUT,
    @CreatedByUserID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @CustomerID = NULL;

    BEGIN TRY
        IF @CreatedByUserID IS NOT NULL
           AND dbo.fn_UserHasEffectiveRole(@CreatedByUserID, N'Employee') = 0
           AND dbo.fn_UserHasEffectiveRole(@CreatedByUserID, N'Admin') = 0
           AND dbo.fn_UserHasEffectiveRole(@CreatedByUserID, N'HighAdmin') = 0
        BEGIN
            RAISERROR('Only an effective Employee, Admin, or HighAdmin can create customers on behalf of another person.', 16, 1);
            RETURN;
        END;

        IF @FirstName IS NULL OR LEN(LTRIM(RTRIM(@FirstName))) = 0
        BEGIN RAISERROR('First name is required.', 16, 1); RETURN; END;
        IF @LastName IS NULL OR LEN(LTRIM(RTRIM(@LastName))) = 0
        BEGIN RAISERROR('Last name is required.', 16, 1); RETURN; END;
        IF @Phone IS NULL OR LEN(LTRIM(RTRIM(@Phone))) = 0
        BEGIN RAISERROR('Phone number is required.', 16, 1); RETURN; END;
        IF @Email IS NULL OR LEN(LTRIM(RTRIM(@Email))) = 0
        BEGIN RAISERROR('Email is required.', 16, 1); RETURN; END;
        IF @NationalID IS NULL OR LEN(@NationalID) <> 10 OR @NationalID LIKE '%[^0-9]%'
        BEGIN RAISERROR('National ID must be exactly 10 numeric digits.', 16, 1); RETURN; END;
        IF @BirthDate IS NULL OR @BirthDate > DATEADD(YEAR, -18, CAST(GETDATE() AS DATE))
        BEGIN RAISERROR('Customer must be at least 18 years old.', 16, 1); RETURN; END;

        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Customer WHERE NationalID = @NationalID)
        BEGIN RAISERROR('A customer with this National ID already exists.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS (SELECT 1 FROM dbo.Customer WHERE Phone = @Phone)
        BEGIN RAISERROR('A customer with this phone number already exists.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS (SELECT 1 FROM dbo.Customer WHERE Email = @Email)
        BEGIN RAISERROR('A customer with this email already exists.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        INSERT INTO dbo.Customer
            (FirstName, LastName, NationalID, BirthDate, Phone, Email, Address, RegistrationDate, IsActive)
        VALUES
            (LTRIM(RTRIM(@FirstName)), LTRIM(RTRIM(@LastName)), @NationalID, @BirthDate,
             LTRIM(RTRIM(@Phone)), LTRIM(RTRIM(@Email)), @Address, CAST(GETDATE() AS DATE), 1);

        SET @CustomerID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@CreatedByUserID, 'CustomerCreated', 'Customer', @CustomerID,
                CONCAT('Customer ', @FirstName, ' ', @LastName, ' (NationalID ', @NationalID, ') registered.'));

        COMMIT TRANSACTION;

        SELECT @CustomerID AS CustomerID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE();
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END CATCH
END;
GO
