/* =========================================================
   Procedure_Employee_CreateUserAccount.sql
   sp_Employee_CreateUserAccount
   ---------------------------------------------------------
   FINAL VERSION:
   - Creates or reuses the existing customer login for the
     employee's NationalID.
   - This fixes the one-login-per-CustomerID rule.
   - Roles assigned/ensured: Customer + Employee.
   - Cannot create manager/Admin accounts.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Employee_CreateUserAccount', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_Employee_CreateUserAccount;
GO
CREATE PROCEDURE dbo.sp_Employee_CreateUserAccount
(
    @ManagerUserID INT,
    @EmployeeID INT,
    @Username NVARCHAR(50),
    @Password NVARCHAR(4000),
    @BirthDate DATE,
    @Phone NVARCHAR(20) = NULL,
    @Email NVARCHAR(100) = NULL,
    @Address NVARCHAR(200) = NULL,
    @UserID INT OUTPUT,
    @CustomerID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @UserID=NULL; SET @CustomerID=NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ManagerEmployeeID INT,@ManagerBranchID INT,@ManagerJobTitle NVARCHAR(100),@ManagerCanAccessAdmin BIT,@EmpNationalID NVARCHAR(20),@EmpFirstName NVARCHAR(50),@EmpLastName NVARCHAR(50),@EmpPhone NVARCHAR(20),@EmpEmail NVARCHAR(100),@EmpJobTitle NVARCHAR(100),@EmpCanAccessAdmin BIT,@EmpStatus NVARCHAR(20),@EmployeeBranchID INT;
        IF @Password IS NULL OR LEN(@Password)<6 BEGIN RAISERROR('Password must be at least 6 characters.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @ManagerEmployeeID=U.EmployeeID FROM dbo.Users U WHERE U.UserID=@ManagerUserID AND U.IsActive=1 AND U.EmployeeID IS NOT NULL;
        IF @ManagerEmployeeID IS NULL OR dbo.fn_UserHasEffectiveRole(@ManagerUserID,N'Admin')=0 BEGIN RAISERROR('Only an effective Branch Manager or Vice Manager can create ordinary employee login accounts.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @ManagerJobTitle=E.JobTitle,@ManagerCanAccessAdmin=E.CanAccessAdmin FROM dbo.Employee E WHERE E.EmployeeID=@ManagerEmployeeID AND E.EmpStatus='Active';
        IF @ManagerCanAccessAdmin<>1 OR @ManagerJobTitle NOT IN ('Branch Manager','Vice Manager') BEGIN RAISERROR('Only an active Branch Manager or Vice Manager can create ordinary employee login accounts.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT TOP(1) @ManagerBranchID=BranchID FROM dbo.EMPB WHERE EmployeeID=@ManagerEmployeeID AND WorkingStatus='Working' AND EndDate IS NULL;
        IF @ManagerBranchID IS NULL BEGIN RAISERROR('Manager has no current branch assignment.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @EmpNationalID=NationalID,@EmpFirstName=FirstName,@EmpLastName=LastName,@EmpPhone=Phone,@EmpEmail=Email,@EmpJobTitle=JobTitle,@EmpCanAccessAdmin=CanAccessAdmin,@EmpStatus=EmpStatus FROM dbo.Employee WHERE EmployeeID=@EmployeeID;
        IF @EmpNationalID IS NULL OR @EmpStatus<>'Active' BEGIN RAISERROR('Target employee does not exist or is not active.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @EmpCanAccessAdmin=1 OR @EmpJobTitle IN ('Branch Manager','Vice Manager') BEGIN RAISERROR('This procedure cannot create manager/Admin login accounts.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT TOP(1) @EmployeeBranchID=BranchID FROM dbo.EMPB WHERE EmployeeID=@EmployeeID AND WorkingStatus='Working' AND EndDate IS NULL;
        IF @EmployeeBranchID IS NULL OR @EmployeeBranchID<>@ManagerBranchID BEGIN RAISERROR('Manager can create login accounts only for employees in his/her current branch.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @CustomerID=CustomerID FROM dbo.Customer WHERE NationalID=@EmpNationalID;
        IF @CustomerID IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.Customer WHERE CustomerID=@CustomerID AND IsActive=0) BEGIN RAISERROR('Matching customer profile exists but is inactive.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CustomerID IS NULL
        BEGIN
            IF @Phone IS NULL SET @Phone=@EmpPhone; IF @Email IS NULL SET @Email=@EmpEmail;
            EXEC dbo.sp_Customer_Create @FirstName=@EmpFirstName,@LastName=@EmpLastName,@NationalID=@EmpNationalID,@BirthDate=@BirthDate,@Phone=@Phone,@Email=@Email,@Address=@Address,@CustomerID=@CustomerID OUTPUT,@CreatedByUserID=@ManagerUserID;
        END;
        IF EXISTS(SELECT 1 FROM dbo.Users WHERE Username=@Username AND CustomerID<>@CustomerID) BEGIN RAISERROR('Username already exists.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @UserID=UserID FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE CustomerID=@CustomerID;
        IF @UserID IS NULL
        BEGIN
            INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(@Username,dbo.fn_HashPassword(@Password),@EmployeeID,@CustomerID,1);
            SET @UserID=CONVERT(INT,SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            IF EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND EmployeeID IS NOT NULL AND EmployeeID<>@EmployeeID) BEGIN RAISERROR('Existing customer login is already linked to another employee.',16,1); ROLLBACK TRANSACTION; RETURN; END;
            UPDATE dbo.Users SET Username=@Username, PasswordHash=dbo.fn_HashPassword(@Password), EmployeeID=@EmployeeID, IsActive=1 WHERE UserID=@UserID;
        END;
        IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID WHERE UR.UserID=@UserID AND R.RoleName='Customer') INSERT INTO dbo.UserRoles(UserID,RoleID) SELECT @UserID,RoleID FROM dbo.Roles WHERE RoleName='Customer';
        IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID WHERE UR.UserID=@UserID AND R.RoleName='Employee') INSERT INTO dbo.UserRoles(UserID,RoleID) SELECT @UserID,RoleID FROM dbo.Roles WHERE RoleName='Employee';
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details) VALUES(@ManagerUserID,'EmployeeUserAccountCreated','Users',@UserID,CONCAT('EmployeeID=',@EmployeeID,'; CustomerID=',@CustomerID,'; reused existing user when applicable.'));
        COMMIT TRANSACTION;
        SELECT @UserID AS UserID,@CustomerID AS CustomerID,@EmployeeID AS EmployeeID;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO
