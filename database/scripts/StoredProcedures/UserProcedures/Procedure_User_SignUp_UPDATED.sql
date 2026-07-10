/* =========================================================
   Procedure_User_SignUp_UPDATED.sql
   sp_User_SignUp

   Customer self-sign-up flow:
     1) creates the Customer through dbo.sp_Customer_Create
     2) creates an active dbo.Users login linked to that Customer
     3) grants the Customer role

   Execute AFTER:
     - TableCreation.sql
     - PasswordHash.sql
     - ApplyAccessRules.sql
     - Schema_CustomerAccessAndBranchLedger.sql
     - Procedure_Customer_Create.sql
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_User_SignUp
(
    @Username      NVARCHAR(50),
    @Password      NVARCHAR(4000),
    @FirstName     NVARCHAR(50),
    @LastName      NVARCHAR(50),
    @NationalID    NVARCHAR(20),
    @BirthDate     DATE,
    @Phone         NVARCHAR(20),
    @Email         NVARCHAR(100),
    @Address       NVARCHAR(200) = NULL,
    @UserID        INT OUTPUT,
    @CustomerID    INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF @Username IS NULL OR LEN(LTRIM(RTRIM(@Username))) < 3
        BEGIN
            RAISERROR('Username must be at least 3 characters.', 16, 1);
            RETURN;
        END;

        IF @Password IS NULL OR LEN(@Password) < 8
        BEGIN
            RAISERROR('Password must be at least 8 characters.', 16, 1);
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM dbo.Users WHERE Username = @Username)
        BEGIN
            RAISERROR('Username is already taken.', 16, 1);
            RETURN;
        END;

        BEGIN TRANSACTION;

        EXEC dbo.sp_Customer_Create
            @FirstName  = @FirstName,
            @LastName   = @LastName,
            @NationalID = @NationalID,
            @BirthDate  = @BirthDate,
            @Phone      = @Phone,
            @Email      = @Email,
            @Address    = @Address,
            @CustomerID = @CustomerID OUTPUT;

        DECLARE @CustomerRoleID INT;
        SELECT @CustomerRoleID = RoleID
        FROM dbo.Roles
        WHERE RoleName = 'Customer';

        IF @CustomerRoleID IS NULL
        BEGIN
            RAISERROR('Customer role is not configured.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        INSERT INTO dbo.Users (Username, PasswordHash, EmployeeID, CustomerID, IsActive)
        VALUES (@Username, dbo.fn_HashPassword(@Password), NULL, @CustomerID, 1);

        SET @UserID = SCOPE_IDENTITY();

        INSERT INTO dbo.UserRoles (UserID, RoleID)
        VALUES (@UserID, @CustomerRoleID);

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@UserID, 'UserSignUp', 'Users', @UserID,
                CONCAT('Customer sign-up completed. CustomerID ', @CustomerID, ' is active.'));

        COMMIT TRANSACTION;

        SELECT @UserID AS UserID, @CustomerID AS CustomerID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
