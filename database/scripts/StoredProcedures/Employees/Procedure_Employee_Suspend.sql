/* =========================================================
   Procedure_Employee_Suspend.sql
   sp_Employee_Suspend
   ---------------------------------------------------------
   PURPOSE:
   Allows a Branch Manager or Vice Manager to suspend an employee
   of the manager's current branch.

   RULES:
   - Manager must be active, have Admin application role,
     CanAccessAdmin = 1, and JobTitle Branch Manager/Vice Manager.
   - Target employee must currently belong to the manager's branch.
   - Target employee cannot be the manager himself/herself.
   - Suspension uses existing Employee.EmpStatus = 'OnLeave'.
   - Linked Users rows remain active so the person can still log in as a Customer while suspended.
   - EMPB assignment remains open because the employee still belongs
     to the branch while on leave/suspension.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Employee_Suspend', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Employee_Suspend;
GO

CREATE PROCEDURE dbo.sp_Employee_Suspend
(
    @ManagerUserID INT,
    @EmployeeID INT,
    @Reason NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @ManagerEmployeeID INT,
            @ManagerBranchID INT,
            @ManagerJobTitle NVARCHAR(100),
            @ManagerCanAccessAdmin BIT,
            @TargetBranchID INT,
            @OldStatus NVARCHAR(20),
            @TargetJobTitle NVARCHAR(100),
            @TargetCanAccessAdmin BIT;

        ------------------------------------------------------------
        -- Validate manager authority.
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

        IF @ManagerEmployeeID = @EmployeeID
        BEGIN
            RAISERROR('Managers cannot suspend themselves through this procedure.', 16, 1);
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
            RAISERROR('Suspending an employee requires Admin application role.', 16, 1);
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
            RAISERROR('Only a Branch Manager or Vice Manager with admin capability can suspend employees.', 16, 1);
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

        ------------------------------------------------------------
        -- Validate target employee belongs to manager's current branch.
        ------------------------------------------------------------
        SELECT
            @OldStatus = E.EmpStatus,
            @TargetJobTitle = E.JobTitle,
            @TargetCanAccessAdmin = E.CanAccessAdmin
        FROM dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
        WHERE E.EmployeeID = @EmployeeID;

        IF @OldStatus IS NULL
        BEGIN
            RAISERROR('Target employee does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @OldStatus <> 'Active'
        BEGIN
            RAISERROR('Only Active employees can be suspended.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetJobTitle IN ('Branch Manager', 'Vice Manager') OR @TargetCanAccessAdmin = 1
        BEGIN
            RAISERROR('Branch Manager/Vice Manager cannot suspend manager-level employees. Use HighAdmin manager procedures.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1)
            @TargetBranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @EmployeeID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        IF @TargetBranchID IS NULL
        BEGIN
            RAISERROR('Target employee has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetBranchID <> @ManagerBranchID
        BEGIN
            RAISERROR('Manager can suspend only employees in his/her current branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Suspend employee. Do NOT deactivate Users; customer login remains available.
        ------------------------------------------------------------
        UPDATE dbo.Employee
        SET EmpStatus = 'OnLeave'
        WHERE EmployeeID = @EmployeeID;

        -- IMPORTANT: Users.IsActive is NOT changed here.
        -- The suspended employee loses employee privileges through Employee.EmpStatus,
        -- but can still log in as a Customer if Customer.IsActive = 1.

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES
        (
            @ManagerUserID,
            'EmployeeSuspended',
            'Employee',
            @EmployeeID,
            CONCAT(
                'Employee suspended in BranchID=', @ManagerBranchID,
                '; Reason=', ISNULL(@Reason, 'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @EmployeeID AS EmployeeID,
            @ManagerBranchID AS BranchID,
            'OnLeave' AS EmpStatus;
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
