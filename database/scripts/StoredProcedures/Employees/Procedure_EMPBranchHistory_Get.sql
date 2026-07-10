/* =========================================================
   Procedure_EMPBranchHistory_Get_HIGHADMIN_FINAL.sql
   sp_EMPBranchHistory_Get
   ---------------------------------------------------------
   PURPOSE:
   Returns EMPB employee-branch assignment history with final
   visibility rules.

   FINAL ACCESS RULES:
   - Normal Employee: own history only.
   - Vice Manager: global history except Branch Manager records.
   - Branch Manager: global history.
   - HighAdmin: global history for every employee and branch.

   NOTE:
   This procedure does NOT restrict target EMPB rows by
   WorkingStatus unless @IncludeCurrentOnly = 1 is provided.
   ========================================================= */

IF OBJECT_ID('dbo.sp_EMPBranchHistory_Get', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EMPBranchHistory_Get;
GO

CREATE PROCEDURE dbo.sp_EMPBranchHistory_Get
(
    @UserID INT,
    @EmployeeID INT = NULL,
    @BranchID INT = NULL,
    @IncludeCurrentOnly BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CallerCustomerID INT,
        @CallerEmployeeID INT,
        @CallerJobTitle NVARCHAR(100),
        @CallerEmpStatus NVARCHAR(20),
        @CallerCanAccessAdmin BIT,
        @CallerCurrentBranchID INT,
        @HasCustomerRole BIT,
        @HasEmployeeRole BIT,
        @HasAdminRole BIT,
        @HasHighAdminRole BIT,
        @AccessMode NVARCHAR(50);

    SET @HasCustomerRole = 0;
    SET @HasEmployeeRole = 0;
    SET @HasAdminRole = 0;
    SET @HasHighAdminRole = 0;
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

    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Customer') SET @HasCustomerRole = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Employee') SET @HasEmployeeRole = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Admin') SET @HasAdminRole = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'HighAdmin') SET @HasHighAdminRole = 1;

    IF @HasCustomerRole = 0
    BEGIN
        RAISERROR('User must have Customer role.', 16, 1);
        RETURN;
    END;

    IF @HasHighAdminRole = 1
    BEGIN
        IF @CallerEmployeeID IS NOT NULL OR @HasEmployeeRole = 1 OR @HasAdminRole = 1
        BEGIN
            RAISERROR('Invalid HighAdmin role configuration.', 16, 1);
            RETURN;
        END;

        SET @AccessMode = N'HighAdminAll';
    END;
    ELSE
    BEGIN
        IF @CallerEmployeeID IS NULL
        BEGIN
            RAISERROR('Employee/Admin access requires EmployeeID.', 16, 1);
            RETURN;
        END;

        SELECT
            @CallerJobTitle = E.JobTitle,
            @CallerEmpStatus = E.EmpStatus,
            @CallerCanAccessAdmin = E.CanAccessAdmin
        FROM dbo.Employee AS E
        WHERE E.EmployeeID = @CallerEmployeeID;

        SELECT TOP (1) @CallerCurrentBranchID = EB.BranchID
        FROM dbo.EMPB AS EB
        WHERE EB.EmployeeID = @CallerEmployeeID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

        IF @HasAdminRole = 1
           AND @CallerEmpStatus = N'Active'
           AND @CallerCanAccessAdmin = 1
           AND @CallerJobTitle IN (N'Branch Manager', N'Vice Manager')
           AND @CallerCurrentBranchID IS NOT NULL
        BEGIN
            SET @AccessMode = CASE
                WHEN @CallerJobTitle = N'Branch Manager' THEN N'BranchManagerGlobal'
                ELSE N'ViceManagerGlobalNoBranchManager'
            END;
        END;
        ELSE IF @HasEmployeeRole = 1 AND @CallerEmpStatus = N'Active'
        BEGIN
            SET @AccessMode = N'SelfOnly';
            IF @EmployeeID IS NOT NULL AND @EmployeeID <> @CallerEmployeeID
            BEGIN
                RAISERROR('Normal employees can view only their own branch history.', 16, 1);
                RETURN;
            END;
            SET @EmployeeID = @CallerEmployeeID;
        END;
        ELSE
        BEGIN
            RAISERROR('User does not have effective Employee/Admin/HighAdmin access.', 16, 1);
            RETURN;
        END;
    END;

    IF @AccessMode = N'ViceManagerGlobalNoBranchManager'
       AND @EmployeeID IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID AND JobTitle = N'Branch Manager')
    BEGIN
        RAISERROR('Vice Manager cannot view Branch Manager history.', 16, 1);
        RETURN;
    END;

    SELECT
        EB.EMPBID,
        EB.EmployeeID,
        E.NationalID,
        E.FirstName,
        E.LastName,
        E.JobTitle,
        E.EmpStatus,
        EB.BranchID,
        B.BranchName,
        B.BranchCode,
        B.City,
        EB.StartDate,
        EB.EndDate,
        EB.WorkingStatus,
        CASE WHEN EB.WorkingStatus = N'Working' AND EB.EndDate IS NULL THEN 1 ELSE 0 END AS IsCurrentAssignment
    FROM dbo.EMPB AS EB
    INNER JOIN dbo.Employee AS E ON E.EmployeeID = EB.EmployeeID
    INNER JOIN dbo.Branch AS B ON B.BranchID = EB.BranchID
    WHERE (@EmployeeID IS NULL OR EB.EmployeeID = @EmployeeID)
      AND (@BranchID IS NULL OR EB.BranchID = @BranchID)
      AND (@IncludeCurrentOnly = 0 OR (EB.WorkingStatus = N'Working' AND EB.EndDate IS NULL))
      AND (@AccessMode <> N'ViceManagerGlobalNoBranchManager' OR E.JobTitle <> N'Branch Manager')
    ORDER BY EB.BranchID, EB.EmployeeID, EB.StartDate DESC, EB.EMPBID DESC;

    INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, ActionDate, Details)
    VALUES
    (
        @UserID,
        N'EMPBHistoryViewed',
        N'EMPB',
        NULL,
        GETDATE(),
        CONCAT(
            'EmployeeFilter=', ISNULL(CONVERT(NVARCHAR(30), @EmployeeID), N'ALL'),
            '; BranchFilter=', ISNULL(CONVERT(NVARCHAR(30), @BranchID), N'ALL'),
            '; IncludeCurrentOnly=', @IncludeCurrentOnly,
            '; AccessMode=', @AccessMode
        )
    );
END;
GO
