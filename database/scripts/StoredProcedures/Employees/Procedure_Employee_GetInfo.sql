/* =========================================================
   Procedure_Employee_GetInfo_HIGHADMIN_FINAL.sql
   sp_Employee_GetInfo
   ---------------------------------------------------------
   PURPOSE:
   Returns employee details and EMPB branch-assignment history
   with the final Employee/Admin/HighAdmin visibility rules.

   FINAL ACCESS RULES:
   - Normal Employee:
       Can view only his/her own employee record.
       Can see own EMPB history with any WorkingStatus.

   - Vice Manager:
       Can view employees globally with any EmpStatus and any
       EMPB.WorkingStatus, EXCEPT Branch Manager records.
       This enforces the rule that a Vice Manager cannot see
       Branch Manager information.

   - Branch Manager:
       Can view employees globally with any EmpStatus and any
       EMPB.WorkingStatus.

   - HighAdmin:
       Can view every employee globally with any EmpStatus and
       every EMPB history row with any WorkingStatus.

   DEFINITIONS:
   - Admin role is an application role stored in dbo.Roles.
   - HighAdmin is an application role stored in dbo.Roles.
   - HighAdmin has CustomerID but no EmployeeID.
   - Employee/Admin effectiveness depends on Employee.EmpStatus.

   REQUIREMENTS:
   - dbo.Users with IsActive
   - dbo.Customer with IsActive
   - dbo.Employee
   - dbo.EMPB
   - dbo.Branch
   - dbo.Roles
   - dbo.UserRoles
   - dbo.AuditLog
   ========================================================= */

IF OBJECT_ID('dbo.sp_Employee_GetInfo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Employee_GetInfo;
GO

CREATE PROCEDURE dbo.sp_Employee_GetInfo
(
    @UserID INT,
    @EmployeeID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CallerCustomerID INT,
        @CallerEmployeeID INT,
        @CallerJobTitle NVARCHAR(100),
        @CallerCanAccessAdmin BIT,
        @CallerEmpStatus NVARCHAR(20),
        @CallerCurrentBranchID INT,
        @HasCustomerRole BIT,
        @HasEmployeeRole BIT,
        @HasAdminRole BIT,
        @HasHighAdminRole BIT,
        @IsEmployeeEffective BIT,
        @IsAdminEffective BIT,
        @IsHighAdminEffective BIT,
        @AccessMode NVARCHAR(50);

    SET @HasCustomerRole = 0;
    SET @HasEmployeeRole = 0;
    SET @HasAdminRole = 0;
    SET @HasHighAdminRole = 0;
    SET @IsEmployeeEffective = 0;
    SET @IsAdminEffective = 0;
    SET @IsHighAdminEffective = 0;
    SET @AccessMode = N'None';

    ------------------------------------------------------------
    -- 1. Resolve active application user.
    ------------------------------------------------------------
    SELECT
        @CallerCustomerID = U.CustomerID,
        @CallerEmployeeID = U.EmployeeID
    FROM dbo.Users AS U
    WHERE U.UserID = @UserID
      AND U.IsActive = 1;

    IF @CallerCustomerID IS NULL
    BEGIN
        RAISERROR('Invalid or inactive user, or user has no CustomerID.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Customer AS C
        WHERE C.CustomerID = @CallerCustomerID
          AND C.IsActive = 1
    )
    BEGIN
        RAISERROR('Linked customer profile is inactive or missing.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 2. Resolve raw application roles.
    ------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM dbo.UserRoles AS UR
        INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
        WHERE UR.UserID = @UserID AND R.RoleName = N'Customer'
    ) SET @HasCustomerRole = 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.UserRoles AS UR
        INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
        WHERE UR.UserID = @UserID AND R.RoleName = N'Employee'
    ) SET @HasEmployeeRole = 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.UserRoles AS UR
        INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
        WHERE UR.UserID = @UserID AND R.RoleName = N'Admin'
    ) SET @HasAdminRole = 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.UserRoles AS UR
        INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
        WHERE UR.UserID = @UserID AND R.RoleName = N'HighAdmin'
    ) SET @HasHighAdminRole = 1;

    IF @HasCustomerRole = 0
    BEGIN
        RAISERROR('User must have Customer role.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 3. Calculate HighAdmin effectiveness.
    ------------------------------------------------------------
    IF @HasHighAdminRole = 1
    BEGIN
        IF @CallerEmployeeID IS NOT NULL
        BEGIN
            RAISERROR('Invalid HighAdmin configuration: HighAdmin must not be linked to EmployeeID.', 16, 1);
            RETURN;
        END;

        IF @HasEmployeeRole = 1 OR @HasAdminRole = 1
        BEGIN
            RAISERROR('Invalid HighAdmin configuration: HighAdmin cannot be combined with Employee/Admin roles.', 16, 1);
            RETURN;
        END;

        SET @IsHighAdminEffective = 1;
        SET @AccessMode = N'HighAdminAll';
    END;

    ------------------------------------------------------------
    -- 4. Calculate Employee/Admin effectiveness when applicable.
    ------------------------------------------------------------
    IF @CallerEmployeeID IS NOT NULL
    BEGIN
        SELECT
            @CallerJobTitle = E.JobTitle,
            @CallerCanAccessAdmin = E.CanAccessAdmin,
            @CallerEmpStatus = E.EmpStatus
        FROM dbo.Employee AS E
        WHERE E.EmployeeID = @CallerEmployeeID;

        SELECT TOP (1)
            @CallerCurrentBranchID = EB.BranchID
        FROM dbo.EMPB AS EB
        WHERE EB.EmployeeID = @CallerEmployeeID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

        IF @HasEmployeeRole = 1 AND @CallerEmpStatus = N'Active'
            SET @IsEmployeeEffective = 1;

        IF @HasAdminRole = 1
           AND @CallerEmpStatus = N'Active'
           AND @CallerCanAccessAdmin = 1
           AND @CallerJobTitle IN (N'Branch Manager', N'Vice Manager')
           AND @CallerCurrentBranchID IS NOT NULL
            SET @IsAdminEffective = 1;
    END;

    IF @IsHighAdminEffective = 0
       AND @IsEmployeeEffective = 0
       AND @IsAdminEffective = 0
    BEGIN
        RAISERROR('User does not have an effective Employee, Admin, or HighAdmin role.', 16, 1);
        RETURN;
    END;

    IF @IsHighAdminEffective = 0 AND @IsAdminEffective = 1
    BEGIN
        SET @AccessMode = CASE
            WHEN @CallerJobTitle = N'Branch Manager' THEN N'BranchManagerGlobal'
            WHEN @CallerJobTitle = N'Vice Manager' THEN N'ViceManagerGlobalNoBranchManager'
            ELSE N'AdminGlobal'
        END;
    END;

    IF @IsHighAdminEffective = 0 AND @IsAdminEffective = 0
    BEGIN
        SET @AccessMode = N'SelfOnly';

        IF @EmployeeID IS NOT NULL AND @EmployeeID <> @CallerEmployeeID
        BEGIN
            RAISERROR('Normal employees can view only their own information.', 16, 1);
            RETURN;
        END;

        SET @EmployeeID = @CallerEmployeeID;
    END;

    IF @EmployeeID IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        RAISERROR('Employee does not exist.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 5. Vice Manager cannot view Branch Manager information.
    ------------------------------------------------------------
    IF @AccessMode = N'ViceManagerGlobalNoBranchManager'
       AND @EmployeeID IS NOT NULL
       AND EXISTS
       (
           SELECT 1
           FROM dbo.Employee
           WHERE EmployeeID = @EmployeeID
             AND JobTitle = N'Branch Manager'
       )
    BEGIN
        RAISERROR('Vice Manager cannot view Branch Manager information.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 6. Return employee details with full EMPB history.
    ------------------------------------------------------------
    SELECT
        E.EmployeeID,
        E.NationalID,
        E.FirstName,
        E.LastName,
        E.HireDate,
        E.JobTitle,
        E.Salary,
        E.Phone,
        E.Email,
        E.EmpStatus,
        E.CanAccessAdmin,
        EB.EMPBID,
        EB.BranchID,
        B.BranchName,
        B.BranchCode,
        B.City AS BranchCity,
        EB.StartDate,
        EB.EndDate,
        EB.WorkingStatus,
        CASE WHEN EB.WorkingStatus = N'Working' AND EB.EndDate IS NULL THEN 1 ELSE 0 END AS IsCurrentAssignment
    FROM dbo.Employee AS E
    LEFT JOIN dbo.EMPB AS EB
        ON EB.EmployeeID = E.EmployeeID
    LEFT JOIN dbo.Branch AS B
        ON B.BranchID = EB.BranchID
    WHERE (@EmployeeID IS NULL OR E.EmployeeID = @EmployeeID)
      AND
      (
          @AccessMode <> N'ViceManagerGlobalNoBranchManager'
          OR E.JobTitle <> N'Branch Manager'
      )
    ORDER BY
        E.EmployeeID,
        EB.StartDate DESC,
        EB.EMPBID DESC;

    INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, ActionDate, Details)
    VALUES
    (
        @UserID,
        N'EmployeeInfoViewed',
        N'Employee',
        @EmployeeID,
        GETDATE(),
        CONCAT(
            'EmployeeFilter=', ISNULL(CONVERT(NVARCHAR(30), @EmployeeID), N'ALL'),
            '; AccessMode=', @AccessMode
        )
    );
END;
GO
