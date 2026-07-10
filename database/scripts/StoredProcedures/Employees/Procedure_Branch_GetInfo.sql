/* =========================================================
   Procedure_Branch_GetInfo_HIGHADMIN_FINAL.sql
   sp_Branch_GetInfo
   ---------------------------------------------------------
   PURPOSE:
   Returns branch details with final role-based visibility.

   ACCESS RULES:
   - HighAdmin: can view every branch and branch summary.
   - Effective Admin: can view every branch and branch summary.
   - Active Employee: can view only his/her current branch.
   - Customer-only users cannot view branch-management details.

   RETURNED DETAILS:
   - Branch information
   - Branch balance
   - Current employee count
   - Total historical employee assignments
   - Active account count
   - Total account count
   - Current Branch Manager
   - Current Vice Manager count
   ========================================================= */

IF OBJECT_ID('dbo.sp_Branch_GetInfo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Branch_GetInfo;
GO

CREATE PROCEDURE dbo.sp_Branch_GetInfo
(
    @UserID INT,
    @BranchID INT = NULL,
    @BranchCode NVARCHAR(20) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CallerCustomerID INT,
        @CallerEmployeeID INT,
        @EmployeeStatus NVARCHAR(20),
        @JobTitle NVARCHAR(100),
        @CanAccessAdmin BIT,
        @CallerCurrentBranchID INT,
        @HasCustomer BIT,
        @HasEmployee BIT,
        @HasAdmin BIT,
        @HasHighAdmin BIT,
        @IsEmployeeEffective BIT,
        @IsAdminEffective BIT,
        @IsHighAdminEffective BIT,
        @AccessMode NVARCHAR(50);

    SET @HasCustomer = 0;
    SET @HasEmployee = 0;
    SET @HasAdmin = 0;
    SET @HasHighAdmin = 0;
    SET @IsEmployeeEffective = 0;
    SET @IsAdminEffective = 0;
    SET @IsHighAdminEffective = 0;
    SET @AccessMode = N'None';

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

    IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CallerCustomerID AND IsActive = 1)
    BEGIN
        RAISERROR('Linked customer profile is inactive or missing.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Customer') SET @HasCustomer = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Employee') SET @HasEmployee = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Admin') SET @HasAdmin = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'HighAdmin') SET @HasHighAdmin = 1;

    IF @HasHighAdmin = 1
    BEGIN
        IF @CallerEmployeeID IS NOT NULL OR @HasEmployee = 1 OR @HasAdmin = 1
        BEGIN
            RAISERROR('Invalid HighAdmin configuration.', 16, 1);
            RETURN;
        END;

        SET @IsHighAdminEffective = 1;
        SET @AccessMode = N'HighAdminAllBranches';
    END;

    IF @CallerEmployeeID IS NOT NULL
    BEGIN
        SELECT
            @EmployeeStatus = E.EmpStatus,
            @JobTitle = E.JobTitle,
            @CanAccessAdmin = E.CanAccessAdmin
        FROM dbo.Employee AS E
        WHERE E.EmployeeID = @CallerEmployeeID;

        SELECT TOP (1)
            @CallerCurrentBranchID = EB.BranchID
        FROM dbo.EMPB AS EB
        WHERE EB.EmployeeID = @CallerEmployeeID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

        IF @HasEmployee = 1 AND @EmployeeStatus = N'Active'
            SET @IsEmployeeEffective = 1;

        IF @HasAdmin = 1
           AND @EmployeeStatus = N'Active'
           AND @CanAccessAdmin = 1
           AND @JobTitle IN (N'Branch Manager', N'Vice Manager')
           AND @CallerCurrentBranchID IS NOT NULL
            SET @IsAdminEffective = 1;
    END;

    IF @IsHighAdminEffective = 0 AND @IsAdminEffective = 1
        SET @AccessMode = N'AdminAllBranches';

    IF @IsHighAdminEffective = 0 AND @IsAdminEffective = 0 AND @IsEmployeeEffective = 1
    BEGIN
        IF @CallerCurrentBranchID IS NULL
        BEGIN
            RAISERROR('Employee has no current branch assignment.', 16, 1);
            RETURN;
        END;

        IF @BranchID IS NOT NULL AND @BranchID <> @CallerCurrentBranchID
        BEGIN
            RAISERROR('Normal employees can view only their current branch information.', 16, 1);
            RETURN;
        END;

        IF @BranchCode IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE BranchID = @CallerCurrentBranchID AND BranchCode = LTRIM(RTRIM(@BranchCode)))
        BEGIN
            RAISERROR('Normal employees can view only their current branch information.', 16, 1);
            RETURN;
        END;

        SET @BranchID = @CallerCurrentBranchID;
        SET @BranchCode = NULL;
        SET @AccessMode = N'EmployeeOwnBranch';
    END;

    IF @AccessMode = N'None'
    BEGIN
        RAISERROR('User does not have permission to view branch-management information.', 16, 1);
        RETURN;
    END;

    SELECT
        B.BranchID,
        B.BranchName,
        B.BranchCode,
        B.City,
        B.Address,
        B.Phone,
        B.Balance,
        ISNULL(CurrentEmployees.CurrentEmployeeCount, 0) AS CurrentEmployeeCount,
        ISNULL(HistoricalAssignments.TotalHistoricalAssignments, 0) AS TotalHistoricalAssignments,
        ISNULL(AccountCounts.ActiveAccountCount, 0) AS ActiveAccountCount,
        ISNULL(AccountCounts.TotalAccountCount, 0) AS TotalAccountCount,
        BM.EmployeeID AS CurrentBranchManagerEmployeeID,
        BM.FirstName AS CurrentBranchManagerFirstName,
        BM.LastName AS CurrentBranchManagerLastName,
        ISNULL(ViceManagers.CurrentViceManagerCount, 0) AS CurrentViceManagerCount
    FROM dbo.Branch AS B
    OUTER APPLY
    (
        SELECT COUNT(1) AS CurrentEmployeeCount
        FROM dbo.EMPB AS EB
        INNER JOIN dbo.Employee AS E ON E.EmployeeID = EB.EmployeeID
        WHERE EB.BranchID = B.BranchID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
          AND E.EmpStatus = N'Active'
    ) AS CurrentEmployees
    OUTER APPLY
    (
        SELECT COUNT(1) AS TotalHistoricalAssignments
        FROM dbo.EMPB AS EB
        WHERE EB.BranchID = B.BranchID
    ) AS HistoricalAssignments
    OUTER APPLY
    (
        SELECT
            SUM(CASE WHEN A.AccountStatus = N'Active' THEN 1 ELSE 0 END) AS ActiveAccountCount,
            COUNT(1) AS TotalAccountCount
        FROM dbo.Account AS A
        WHERE A.BranchID = B.BranchID
    ) AS AccountCounts
    OUTER APPLY
    (
        SELECT TOP (1)
            E.EmployeeID,
            E.FirstName,
            E.LastName
        FROM dbo.EMPB AS EB
        INNER JOIN dbo.Employee AS E ON E.EmployeeID = EB.EmployeeID
        WHERE EB.BranchID = B.BranchID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
          AND E.EmpStatus = N'Active'
          AND E.JobTitle = N'Branch Manager'
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC
    ) AS BM
    OUTER APPLY
    (
        SELECT COUNT(1) AS CurrentViceManagerCount
        FROM dbo.EMPB AS EB
        INNER JOIN dbo.Employee AS E ON E.EmployeeID = EB.EmployeeID
        WHERE EB.BranchID = B.BranchID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
          AND E.EmpStatus = N'Active'
          AND E.JobTitle = N'Vice Manager'
    ) AS ViceManagers
    WHERE (@BranchID IS NULL OR B.BranchID = @BranchID)
      AND (@BranchCode IS NULL OR B.BranchCode = LTRIM(RTRIM(@BranchCode)))
    ORDER BY B.BranchID;

    INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, ActionDate, Details)
    VALUES
    (
        @UserID,
        N'BranchInfoViewed',
        N'Branch',
        @BranchID,
        GETDATE(),
        CONCAT(
            'BranchID=', ISNULL(CONVERT(NVARCHAR(30), @BranchID), N'ALL'),
            '; BranchCode=', ISNULL(@BranchCode, N'ALL'),
            '; AccessMode=', @AccessMode
        )
    );
END;
GO
