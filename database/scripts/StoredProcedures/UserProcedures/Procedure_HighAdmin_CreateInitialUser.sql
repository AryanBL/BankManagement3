/* =========================================================
   Procedure_HighAdmin_CreateInitialUser.sql
   sp_HighAdmin_CreateInitialUser
   ---------------------------------------------------------
   FINAL VERSION:
   - Creates the one active HighAdmin.
   - Reuses an existing customer-only Users row when the
     NationalID already belongs to a Customer with a login.
   - Rejects if the existing customer login is already linked to
     EmployeeID, because HighAdmin must not be an Employee.
   ========================================================= */

IF OBJECT_ID('dbo.sp_HighAdmin_CreateInitialUser','P') IS NOT NULL DROP PROCEDURE dbo.sp_HighAdmin_CreateInitialUser;
GO
CREATE PROCEDURE dbo.sp_HighAdmin_CreateInitialUser
(
    @Username NVARCHAR(50),@Password NVARCHAR(4000),@FirstName NVARCHAR(50),@LastName NVARCHAR(50),@NationalID NVARCHAR(20),@BirthDate DATE,@Phone NVARCHAR(20),@Email NVARCHAR(100),@Address NVARCHAR(200)=NULL,@UserID INT OUTPUT,@CustomerID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET @UserID=NULL; SET @CustomerID=NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID JOIN dbo.Users U ON U.UserID=UR.UserID WHERE R.RoleName='HighAdmin' AND U.IsActive=1) BEGIN RAISERROR('An active HighAdmin user already exists.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @Password IS NULL OR LEN(@Password)<6 BEGIN RAISERROR('Password must be at least 6 characters.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS(SELECT 1 FROM dbo.Users WHERE Username=@Username AND CustomerID <> ISNULL((SELECT CustomerID FROM dbo.Customer WHERE NationalID=@NationalID),-1)) BEGIN RAISERROR('Username already exists.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @CustomerID=CustomerID FROM dbo.Customer WHERE NationalID=@NationalID;
        IF @CustomerID IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.Customer WHERE CustomerID=@CustomerID AND IsActive=0) BEGIN RAISERROR('A customer with this NationalID exists but is inactive.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CustomerID IS NULL
        BEGIN
            EXEC dbo.sp_Customer_Create @FirstName=@FirstName,@LastName=@LastName,@NationalID=@NationalID,@BirthDate=@BirthDate,@Phone=@Phone,@Email=@Email,@Address=@Address,@CustomerID=@CustomerID OUTPUT,@CreatedByUserID=NULL;
        END;
        SELECT @UserID=UserID FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE CustomerID=@CustomerID;
        IF @UserID IS NULL
        BEGIN
            INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(@Username,dbo.fn_HashPassword(@Password),NULL,@CustomerID,1);
            SET @UserID=CONVERT(INT,SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            IF EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND EmployeeID IS NOT NULL) BEGIN RAISERROR('Existing customer login is linked to EmployeeID and cannot become HighAdmin.',16,1); ROLLBACK TRANSACTION; RETURN; END;
            IF EXISTS(SELECT 1 FROM dbo.Users WHERE Username=@Username AND UserID<>@UserID) BEGIN RAISERROR('Username already exists.',16,1); ROLLBACK TRANSACTION; RETURN; END;
            UPDATE dbo.Users SET Username=@Username,PasswordHash=dbo.fn_HashPassword(@Password),EmployeeID=NULL,IsActive=1 WHERE UserID=@UserID;
        END;
        IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID WHERE UR.UserID=@UserID AND R.RoleName='Customer') INSERT INTO dbo.UserRoles(UserID,RoleID) SELECT @UserID,RoleID FROM dbo.Roles WHERE RoleName='Customer';
        IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID WHERE UR.UserID=@UserID AND R.RoleName='HighAdmin') INSERT INTO dbo.UserRoles(UserID,RoleID) SELECT @UserID,RoleID FROM dbo.Roles WHERE RoleName='HighAdmin';
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details) VALUES(@UserID,'HighAdminCreated','Users',@UserID,CONCAT('HighAdmin user created/reused. CustomerID=',@CustomerID));
        COMMIT TRANSACTION;
        SELECT @UserID AS UserID,@CustomerID AS CustomerID,'HighAdmin' AS RoleName;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO
