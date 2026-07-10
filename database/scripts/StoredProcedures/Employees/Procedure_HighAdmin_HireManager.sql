/* =========================================================
   Procedure_HighAdmin_HireManager.sql
   sp_HighAdmin_HireManager
   ---------------------------------------------------------
   FINAL VERSION:
   - HighAdmin hires a new Branch Manager or Vice Manager.
   - Creates or reuses Customer and the existing Customer login.
   - Ensures roles: Customer + Employee + Admin.
   ========================================================= */

IF OBJECT_ID('dbo.sp_HighAdmin_HireManager','P') IS NOT NULL DROP PROCEDURE dbo.sp_HighAdmin_HireManager;
GO
CREATE PROCEDURE dbo.sp_HighAdmin_HireManager
(
    @HighAdminUserID INT,@BranchID INT,@Username NVARCHAR(50),@Password NVARCHAR(4000),@NationalID NVARCHAR(20),@FirstName NVARCHAR(50),@LastName NVARCHAR(50),@BirthDate DATE,@HireDate DATE=NULL,@JobTitle NVARCHAR(100),@Salary DECIMAL(18,2),@Phone NVARCHAR(20),@Email NVARCHAR(100),@Address NVARCHAR(200)=NULL,@EmployeeID INT OUTPUT,@CustomerID INT OUTPUT,@UserID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET @EmployeeID=NULL; SET @CustomerID=NULL; SET @UserID=NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF dbo.fn_UserHasEffectiveRole(@HighAdminUserID,N'HighAdmin')=0 BEGIN RAISERROR('Only an active HighAdmin can hire managers.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @JobTitle NOT IN ('Branch Manager','Vice Manager') BEGIN RAISERROR('HighAdmin_HireManager can hire only Branch Manager or Vice Manager.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @HireDate IS NULL SET @HireDate=CAST(GETDATE() AS DATE);
        IF NOT EXISTS(SELECT 1 FROM dbo.Branch WHERE BranchID=@BranchID) BEGIN RAISERROR('Branch does not exist.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @JobTitle='Branch Manager' AND EXISTS(SELECT 1 FROM dbo.EMPB EB JOIN dbo.Employee E ON E.EmployeeID=EB.EmployeeID WHERE EB.BranchID=@BranchID AND EB.WorkingStatus='Working' AND EB.EndDate IS NULL AND E.EmpStatus='Active' AND E.JobTitle='Branch Manager') BEGIN RAISERROR('This branch already has an active Branch Manager.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS(SELECT 1 FROM dbo.Employee WHERE NationalID=@NationalID) BEGIN RAISERROR('An employee with this NationalID already exists.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @Password IS NULL OR LEN(@Password)<6 BEGIN RAISERROR('Password must be at least 6 characters.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS(SELECT 1 FROM dbo.Users WHERE Username=@Username AND CustomerID <> ISNULL((SELECT CustomerID FROM dbo.Customer WHERE NationalID=@NationalID),-1)) BEGIN RAISERROR('Username already exists.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @CustomerID=CustomerID FROM dbo.Customer WHERE NationalID=@NationalID;
        IF @CustomerID IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.Customer WHERE CustomerID=@CustomerID AND IsActive=0) BEGIN RAISERROR('Matching customer exists but is inactive.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CustomerID IS NULL BEGIN EXEC dbo.sp_Customer_Create @FirstName=@FirstName,@LastName=@LastName,@NationalID=@NationalID,@BirthDate=@BirthDate,@Phone=@Phone,@Email=@Email,@Address=@Address,@CustomerID=@CustomerID OUTPUT,@CreatedByUserID=@HighAdminUserID; END;
        INSERT INTO dbo.Employee(NationalID,FirstName,LastName,HireDate,JobTitle,Salary,Phone,Email,EmpStatus) VALUES(@NationalID,@FirstName,@LastName,@HireDate,@JobTitle,@Salary,@Phone,@Email,'Active');
        SET @EmployeeID=CONVERT(INT,SCOPE_IDENTITY());
        INSERT INTO dbo.EMPB(EmployeeID,BranchID,StartDate,EndDate,WorkingStatus) VALUES(@EmployeeID,@BranchID,@HireDate,NULL,'Working');
        SELECT @UserID=UserID FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE CustomerID=@CustomerID;
        IF @UserID IS NULL BEGIN INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(@Username,dbo.fn_HashPassword(@Password),@EmployeeID,@CustomerID,1); SET @UserID=CONVERT(INT,SCOPE_IDENTITY()); END
        ELSE BEGIN IF EXISTS(SELECT 1 FROM dbo.Users WHERE UserID=@UserID AND EmployeeID IS NOT NULL) BEGIN RAISERROR('Existing customer login is already linked to another employee.',16,1); ROLLBACK TRANSACTION; RETURN; END; IF EXISTS(SELECT 1 FROM dbo.Users WHERE Username=@Username AND UserID<>@UserID) BEGIN RAISERROR('Username already exists.',16,1); ROLLBACK TRANSACTION; RETURN; END; UPDATE dbo.Users SET Username=@Username,PasswordHash=dbo.fn_HashPassword(@Password),EmployeeID=@EmployeeID,IsActive=1 WHERE UserID=@UserID; END;
        IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID WHERE UR.UserID=@UserID AND R.RoleName='Customer') INSERT INTO dbo.UserRoles(UserID,RoleID) SELECT @UserID,RoleID FROM dbo.Roles WHERE RoleName='Customer';
        IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID WHERE UR.UserID=@UserID AND R.RoleName='Employee') INSERT INTO dbo.UserRoles(UserID,RoleID) SELECT @UserID,RoleID FROM dbo.Roles WHERE RoleName='Employee';
        IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles UR JOIN dbo.Roles R ON R.RoleID=UR.RoleID WHERE UR.UserID=@UserID AND R.RoleName='Admin') INSERT INTO dbo.UserRoles(UserID,RoleID) SELECT @UserID,RoleID FROM dbo.Roles WHERE RoleName='Admin';
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details) VALUES(@HighAdminUserID,'ManagerHired','Employee',@EmployeeID,CONCAT('Manager hired. JobTitle=',@JobTitle,'; BranchID=',@BranchID,'; UserID=',@UserID,'; CustomerID=',@CustomerID));
        COMMIT TRANSACTION;
        SELECT @EmployeeID AS EmployeeID,@CustomerID AS CustomerID,@UserID AS UserID,@JobTitle AS JobTitle,@BranchID AS BranchID;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO
