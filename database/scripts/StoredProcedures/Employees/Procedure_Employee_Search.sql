/* =========================================================
   Procedure_Employee_Search_AUTHORIZED_FINAL.sql
   sp_Employee_Search
   ---------------------------------------------------------
   PURPOSE:
   Authorized employee search module for the Bank Management
   system.

   FINAL SECURITY MODEL:
   1. Every caller must pass the authenticated @UserID.
   2. Users.IsActive controls whole application login access.
   3. Every login user must have Customer role and an active
      linked Customer record.
   4. Employee/Admin privileges are effective only when the
      linked Employee row has EmpStatus = 'Active'.
   5. Admin is effective only for Branch Manager / Vice Manager
      with CanAccessAdmin = 1.
   6. HighAdmin is effective only when the user has HighAdmin
      role and EmployeeID IS NULL.

   PRIVILEGES:
   - Effective HighAdmin may search all employees.
   - Effective Branch Manager may search all employees.
   - Effective Vice Manager may search all employees EXCEPT
     Branch Manager records.
   - Effective normal Employee may search/view only own employee
     record.
   - Customer-only / fired / suspended users cannot perform
     general employee search.

   NOTES:
   - No dynamic SQL is used.
   - Partial text searches escape %, _, and [ as literal text.
   - Search result returns one row per employee with current
     branch-assignment summary. Use sp_Employee_GetInfo or
     sp_EMPBranchHistory_Get for full EMPB history.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Employee_Search', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Employee_Search;
GO

CREATE PROCEDURE dbo.sp_Employee_Search
(
    @UserID                 INT,
    @EmployeeID             INT = NULL,
    @NameSearch             NVARCHAR(100) = NULL,
    @NationalID             NVARCHAR(20) = NULL,
    @Phone                  NVARCHAR(20) = NULL,
    @Email                  NVARCHAR(100) = NULL,
    @JobTitle               NVARCHAR(100) = NULL,
    @EmpStatus              NVARCHAR(20) = NULL,   -- Active, OnLeave, Terminated
    @BranchID               INT = NULL,
    @BranchCode             NVARCHAR(20) = NULL,
    @WorkingStatus          NVARCHAR(20) = NULL,   -- Working, Transferred, Ended
    @IncludeTerminated      BIT = 0,
    @SearchBranchHistory    BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------
        -- 1. Validate caller identity and calculate effective roles.
        ------------------------------------------------------------
        DECLARE
            @RequesterCustomerID INT,
            @RequesterEmployeeID INT,
            @CallerEmployeeStatus NVARCHAR(20),
            @CallerJobTitle NVARCHAR(100),
            @CallerCanAccessAdmin BIT,
            @CallerCurrentBranchID INT,
            @HasCustomer BIT,
            @HasEmployee BIT,
            @HasAdmin BIT,
            @HasHighAdmin BIT,
            @IsEmployeeEffective BIT,
            @IsAdminEffective BIT,
            @IsHighAdminEffective BIT,
            @AccessMode NVARCHAR(60);

        SET @HasCustomer = 0;
        SET @HasEmployee = 0;
        SET @HasAdmin = 0;
        SET @HasHighAdmin = 0;
        SET @IsEmployeeEffective = 0;
        SET @IsAdminEffective = 0;
        SET @IsHighAdminEffective = 0;
        SET @AccessMode = N'None';

        IF @UserID IS NULL
        BEGIN
            RAISERROR('UserID is required for employee search.', 16, 1);
            RETURN;
        END;

        SELECT
            @RequesterCustomerID = U.CustomerID,
            @RequesterEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        INNER JOIN dbo.Customer AS C
            ON C.CustomerID = U.CustomerID
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND C.IsActive = 1;

        IF @RequesterCustomerID IS NULL
        BEGIN
            RAISERROR('Invalid caller: user account is inactive, missing, or not linked to an active customer profile.', 16, 1);
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Customer') SET @HasCustomer = 1;
        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Employee') SET @HasEmployee = 1;
        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Admin') SET @HasAdmin = 1;
        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'HighAdmin') SET @HasHighAdmin = 1;

        IF @HasCustomer = 0
        BEGIN
            RAISERROR('Invalid caller: user must have Customer role.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND @RequesterEmployeeID IS NOT NULL
        BEGIN
            RAISERROR('Invalid caller: HighAdmin user must not be linked to an EmployeeID.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND (@HasEmployee = 1 OR @HasAdmin = 1)
        BEGIN
            RAISERROR('Invalid caller: HighAdmin role cannot be combined with Employee or Admin roles.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND @RequesterEmployeeID IS NULL
        BEGIN
            SET @IsHighAdminEffective = 1;
            SET @AccessMode = N'HighAdminAllEmployees';
        END;

        IF @RequesterEmployeeID IS NOT NULL
        BEGIN
            SELECT
                @CallerEmployeeStatus = E.EmpStatus,
                @CallerJobTitle = E.JobTitle,
                @CallerCanAccessAdmin = E.CanAccessAdmin
            FROM dbo.Employee AS E
            WHERE E.EmployeeID = @RequesterEmployeeID;

            SELECT TOP (1)
                @CallerCurrentBranchID = EB.BranchID
            FROM dbo.EMPB AS EB
            WHERE EB.EmployeeID = @RequesterEmployeeID
              AND EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
            ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

            IF @HasEmployee = 1 AND @CallerEmployeeStatus = N'Active'
                SET @IsEmployeeEffective = 1;

            IF @HasAdmin = 1
               AND @CallerEmployeeStatus = N'Active'
               AND @CallerCanAccessAdmin = 1
               AND @CallerJobTitle IN (N'Branch Manager', N'Vice Manager')
               AND @CallerCurrentBranchID IS NOT NULL
                SET @IsAdminEffective = 1;
        END;

        IF @IsHighAdminEffective = 0
           AND @IsEmployeeEffective = 0
           AND @IsAdminEffective = 0
        BEGIN
            RAISERROR('Employee search requires an effective Employee, Admin, or HighAdmin privilege.', 16, 1);
            RETURN;
        END;

        IF @IsHighAdminEffective = 0 AND @IsAdminEffective = 1
        BEGIN
            SET @AccessMode = CASE
                WHEN @CallerJobTitle = N'Branch Manager' THEN N'BranchManagerGlobalEmployees'
                WHEN @CallerJobTitle = N'Vice Manager' THEN N'ViceManagerGlobalNoBranchManager'
                ELSE N'AdminGlobalEmployees'
            END;
        END;

        IF @IsHighAdminEffective = 0 AND @IsAdminEffective = 0 AND @IsEmployeeEffective = 1
        BEGIN
            SET @AccessMode = N'EmployeeSelfOnly';

            IF @EmployeeID IS NOT NULL AND @EmployeeID <> @RequesterEmployeeID
            BEGIN
                RAISERROR('Normal employees can search only their own employee record.', 16, 1);
                RETURN;
            END;

            SET @EmployeeID = @RequesterEmployeeID;
        END;

        ------------------------------------------------------------
        -- 2. Validate and clean filters.
        ------------------------------------------------------------
        DECLARE
            @CleanNameSearch NVARCHAR(100),
            @CleanNationalID NVARCHAR(20),
            @CleanPhone NVARCHAR(20),
            @CleanEmail NVARCHAR(100),
            @CleanJobTitle NVARCHAR(100),
            @CleanEmpStatus NVARCHAR(20),
            @CleanBranchCode NVARCHAR(20),
            @CleanWorkingStatus NVARCHAR(20),
            @NamePattern NVARCHAR(310);

        SET @CleanNameSearch = NULLIF(LTRIM(RTRIM(@NameSearch)), N'');
        SET @CleanNationalID = NULLIF(LTRIM(RTRIM(@NationalID)), N'');
        SET @CleanPhone = NULLIF(LTRIM(RTRIM(@Phone)), N'');
        SET @CleanEmail = NULLIF(LTRIM(RTRIM(@Email)), N'');
        SET @CleanJobTitle = NULLIF(LTRIM(RTRIM(@JobTitle)), N'');
        SET @CleanEmpStatus = NULLIF(LTRIM(RTRIM(@EmpStatus)), N'');
        SET @CleanBranchCode = NULLIF(LTRIM(RTRIM(@BranchCode)), N'');
        SET @CleanWorkingStatus = NULLIF(LTRIM(RTRIM(@WorkingStatus)), N'');

        IF @CleanEmpStatus IS NOT NULL
           AND @CleanEmpStatus NOT IN (N'Active', N'OnLeave', N'Terminated')
        BEGIN
            RAISERROR('Invalid EmpStatus. Allowed values: Active, OnLeave, Terminated.', 16, 1);
            RETURN;
        END;

        IF @CleanWorkingStatus IS NOT NULL
           AND @CleanWorkingStatus NOT IN (N'Working', N'Transferred', N'Ended')
        BEGIN
            RAISERROR('Invalid WorkingStatus. Allowed values: Working, Transferred, Ended.', 16, 1);
            RETURN;
        END;

        IF @CleanNameSearch IS NOT NULL
        BEGIN
            SET @NamePattern = N'%' +
                REPLACE(
                    REPLACE(
                        REPLACE(@CleanNameSearch, N'[', N'[[]'),
                    N'%', N'[%]'),
                N'_', N'[_]') + N'%';
        END;

        ------------------------------------------------------------
        -- 3. Audit successful authorized search attempt.
        ------------------------------------------------------------
        INSERT INTO dbo.AuditLog
        (
            UserID,
            ActionType,
            TableName,
            RecordID,
            ActionDate,
            Details
        )
        VALUES
        (
            @UserID,
            N'EmployeeSearch',
            N'Employee',
            NULL,
            GETDATE(),
            CONCAT(
                N'Employee search executed. AccessMode=', @AccessMode,
                N'; EmployeeID=', ISNULL(CONVERT(NVARCHAR(30), @EmployeeID), N'NULL'),
                N'; BranchID=', ISNULL(CONVERT(NVARCHAR(30), @BranchID), N'NULL'),
                N'; EmpStatus=', ISNULL(@CleanEmpStatus, N'NULL'),
                N'; IncludeTerminated=', @IncludeTerminated,
                N'; SearchBranchHistory=', @SearchBranchHistory
            )
        );

        ------------------------------------------------------------
        -- 4. Return matching employee records.
        --    One row per employee, with current branch assignment.
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
            CurrentEB.EMPBID AS CurrentEMPBID,
            CurrentEB.BranchID AS CurrentBranchID,
            CurrentB.BranchName AS CurrentBranchName,
            CurrentB.BranchCode AS CurrentBranchCode,
            CurrentB.City AS CurrentBranchCity,
            CurrentEB.StartDate AS CurrentBranchStartDate,
            CurrentEB.WorkingStatus AS CurrentWorkingStatus
        FROM dbo.Employee AS E
        OUTER APPLY
        (
            SELECT TOP (1)
                EB.EMPBID,
                EB.BranchID,
                EB.StartDate,
                EB.WorkingStatus
            FROM dbo.EMPB AS EB
            WHERE EB.EmployeeID = E.EmployeeID
              AND EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
            ORDER BY EB.StartDate DESC, EB.EMPBID DESC
        ) AS CurrentEB
        LEFT JOIN dbo.Branch AS CurrentB
            ON CurrentB.BranchID = CurrentEB.BranchID
        WHERE (@EmployeeID IS NULL OR E.EmployeeID = @EmployeeID)
          AND (@CleanNameSearch IS NULL OR E.FirstName LIKE @NamePattern OR E.LastName LIKE @NamePattern)
          AND (@CleanNationalID IS NULL OR E.NationalID = @CleanNationalID)
          AND (@CleanPhone IS NULL OR E.Phone = @CleanPhone)
          AND (@CleanEmail IS NULL OR E.Email = @CleanEmail)
          AND (@CleanJobTitle IS NULL OR E.JobTitle = @CleanJobTitle)
          AND (@CleanEmpStatus IS NULL OR E.EmpStatus = @CleanEmpStatus)
          AND (@CleanEmpStatus IS NOT NULL OR @IncludeTerminated = 1 OR E.EmpStatus <> N'Terminated')
          AND
          (
              @AccessMode <> N'ViceManagerGlobalNoBranchManager'
              OR E.JobTitle <> N'Branch Manager'
          )
          AND
          (
              @BranchID IS NULL
              OR (@SearchBranchHistory = 0 AND CurrentEB.BranchID = @BranchID)
              OR (@SearchBranchHistory = 1 AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.EMPB AS EBH
                      WHERE EBH.EmployeeID = E.EmployeeID
                        AND EBH.BranchID = @BranchID
                  ))
          )
          AND
          (
              @CleanBranchCode IS NULL
              OR (@SearchBranchHistory = 0 AND CurrentB.BranchCode = @CleanBranchCode)
              OR (@SearchBranchHistory = 1 AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.EMPB AS EBH
                      INNER JOIN dbo.Branch AS BH
                          ON BH.BranchID = EBH.BranchID
                      WHERE EBH.EmployeeID = E.EmployeeID
                        AND BH.BranchCode = @CleanBranchCode
                  ))
          )
          AND
          (
              @CleanWorkingStatus IS NULL
              OR (@SearchBranchHistory = 0 AND CurrentEB.WorkingStatus = @CleanWorkingStatus)
              OR (@SearchBranchHistory = 1 AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.EMPB AS EBH
                      WHERE EBH.EmployeeID = E.EmployeeID
                        AND EBH.WorkingStatus = @CleanWorkingStatus
                  ))
          )
        ORDER BY E.LastName, E.FirstName, E.EmployeeID;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;

        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorSeverity = ERROR_SEVERITY();
        SET @ErrorState = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;
END;
GO
