/* =========================================================
   Procedure_Employee_Hire.sql
   sp_Employee_Hire
   ---------------------------------------------------------
   PURPOSE:
   Allows a Branch Manager or Vice Manager to hire a new employee
   into the manager's current branch.

   RULES:
   - The caller must be an active employee user.
   - The caller must have Admin application role.
   - The caller's Employee.CanAccessAdmin must be 1.
   - The caller's JobTitle must be Branch Manager or Vice Manager.
   - The caller must currently work in exactly one branch
     (Working + EndDate IS NULL).
   - The new employee is created as Active.
   - A current EMPB row is created in the manager's branch.
   - This procedure creates the Employee record and branch assignment.
     It does NOT create a login account. Employee login creation can be
     handled separately through a user-account procedure.

   NOTE:
   TR_Employee_SetAdminFlag may adjust CanAccessAdmin after insert
   based on the JobTitle.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Employee_Hire', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Employee_Hire;
GO

CREATE PROCEDURE dbo.sp_Employee_Hire
(
    @ManagerUserID INT,
    @NationalID NVARCHAR(20),
    @FirstName NVARCHAR(50),
    @LastName NVARCHAR(50),
    @HireDate DATE = NULL,
    @JobTitle NVARCHAR(100),
    @Salary DECIMAL(18,2),
    @Phone NVARCHAR(20) = NULL,
    @Email NVARCHAR(100) = NULL,
    @EmployeeID INT OUTPUT,
    @EMPBID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @EmployeeID = NULL;
    SET @EMPBID = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @ManagerEmployeeID INT,
            @ManagerBranchID INT,
            @ManagerJobTitle NVARCHAR(100),
            @ManagerCanAccessAdmin BIT;

        IF @HireDate IS NULL
            SET @HireDate = CAST(GETDATE() AS DATE);

        IF @JobTitle IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('Branch managers and vice managers cannot hire manager-level employees. Use HighAdmin manager procedures.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @Salary IS NULL OR @Salary < 0
        BEGIN
            RAISERROR('Salary must be provided and cannot be negative.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @NationalID IS NULL OR LEN(LTRIM(RTRIM(@NationalID))) = 0
        BEGIN
            RAISERROR('NationalID is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @FirstName IS NULL OR LEN(LTRIM(RTRIM(@FirstName))) = 0
           OR @LastName IS NULL OR LEN(LTRIM(RTRIM(@LastName))) = 0
           OR @JobTitle IS NULL OR LEN(LTRIM(RTRIM(@JobTitle))) = 0
        BEGIN
            RAISERROR('FirstName, LastName, and JobTitle are required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Validate manager authority and get manager branch.
        ------------------------------------------------------------
        SELECT @ManagerEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        WHERE U.UserID = @ManagerUserID
          AND U.IsActive = 1
          AND U.EmployeeID IS NOT NULL;

        IF @ManagerEmployeeID IS NULL
        BEGIN
            RAISERROR('Invalid or inactive manager user.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @ManagerUserID
              AND R.RoleName = 'Admin'
        )
        BEGIN
            RAISERROR('Hiring requires Admin application role.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT
            @ManagerJobTitle = E.JobTitle,
            @ManagerCanAccessAdmin = E.CanAccessAdmin
        FROM dbo.Employee AS E
        WHERE E.EmployeeID = @ManagerEmployeeID
          AND E.EmpStatus = 'Active';

        IF @ManagerJobTitle IS NULL
        BEGIN
            RAISERROR('Manager employee record is invalid or not active.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @ManagerCanAccessAdmin <> 1 OR @ManagerJobTitle NOT IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('Only a Branch Manager or Vice Manager with admin capability can hire employees.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1) @ManagerBranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @ManagerEmployeeID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        IF @ManagerBranchID IS NULL
        BEGIN
            RAISERROR('Manager has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM dbo.Employee WHERE NationalID = @NationalID)
        BEGIN
            RAISERROR('An employee with this NationalID already exists.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Create employee and assign to manager's current branch.
        ------------------------------------------------------------
        INSERT INTO dbo.Employee
        (
            NationalID,
            FirstName,
            LastName,
            HireDate,
            JobTitle,
            Salary,
            Phone,
            Email,
            EmpStatus
        )
        VALUES
        (
            LTRIM(RTRIM(@NationalID)),
            LTRIM(RTRIM(@FirstName)),
            LTRIM(RTRIM(@LastName)),
            @HireDate,
            LTRIM(RTRIM(@JobTitle)),
            @Salary,
            @Phone,
            @Email,
            'Active'
        );

        SET @EmployeeID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.EMPB
        (
            EmployeeID,
            BranchID,
            StartDate,
            EndDate,
            WorkingStatus
        )
        VALUES
        (
            @EmployeeID,
            @ManagerBranchID,
            @HireDate,
            NULL,
            'Working'
        );

        SET @EMPBID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES
        (
            @ManagerUserID,
            'EmployeeHired',
            'Employee',
            @EmployeeID,
            CONCAT(
                'Employee hired into BranchID=', @ManagerBranchID,
                '; EMPBID=', @EMPBID,
                '; JobTitle=', @JobTitle,
                '; HireDate=', CONVERT(NVARCHAR(30), @HireDate, 120)
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @EmployeeID AS EmployeeID,
            @EMPBID AS EMPBID,
            @ManagerBranchID AS BranchID,
            @HireDate AS HireDate;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
        RETURN;
    END CATCH;
END;
GO
