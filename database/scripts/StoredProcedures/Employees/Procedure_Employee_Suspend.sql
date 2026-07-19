/* =========================================================
   Procedure_Employee_Suspend.sql
   sp_Employee_Suspend
   ---------------------------------------------------------
   Suspends an ordinary employee by setting EmpStatus=OnLeave.

   Authorized callers:
   - Effective Admin: ordinary employee in the caller's current branch.
   - Effective HighAdmin: ordinary employee in any branch.

   Manager-level employees must be suspended through
   dbo.sp_HighAdmin_SuspendManager.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Employee_Suspend
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
            @IsHighAdmin BIT = 0,
            @IsAdmin BIT = 0,
            @ManagerEmployeeID INT = NULL,
            @ManagerBranchID INT = NULL,
            @ManagerJobTitle NVARCHAR(100) = NULL,
            @ManagerCanAccessAdmin BIT = 0,
            @TargetBranchID INT = NULL,
            @OldStatus NVARCHAR(20) = NULL,
            @TargetJobTitle NVARCHAR(100) = NULL,
            @TargetCanAccessAdmin BIT = 0;

        SET @IsHighAdmin = dbo.fn_UserHasEffectiveRole(@ManagerUserID, N'HighAdmin');
        SET @IsAdmin = dbo.fn_UserHasEffectiveRole(@ManagerUserID, N'Admin');

        IF @IsHighAdmin = 0 AND @IsAdmin = 0
        BEGIN
            RAISERROR('Only an effective branch manager/Admin or HighAdmin can suspend an employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

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

        IF @OldStatus <> N'Active'
        BEGIN
            RAISERROR('Only Active employees can be suspended.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetJobTitle IN (N'Branch Manager', N'Vice Manager') OR @TargetCanAccessAdmin = 1
        BEGIN
            RAISERROR('Manager-level employees must be suspended through the HighAdmin manager endpoint.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1)
            @TargetBranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @EmployeeID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

        IF @TargetBranchID IS NULL
        BEGIN
            RAISERROR('Target employee has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @IsHighAdmin = 0
        BEGIN
            SELECT
                @ManagerEmployeeID = U.EmployeeID
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
                RAISERROR('Managers cannot suspend themselves.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;

            SELECT
                @ManagerJobTitle = E.JobTitle,
                @ManagerCanAccessAdmin = E.CanAccessAdmin
            FROM dbo.Employee AS E
            WHERE E.EmployeeID = @ManagerEmployeeID
              AND E.EmpStatus = N'Active';

            IF @ManagerCanAccessAdmin <> 1
               OR @ManagerJobTitle NOT IN (N'Branch Manager', N'Vice Manager')
            BEGIN
                RAISERROR('Only an active Branch Manager or Vice Manager can suspend branch employees.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;

            SELECT TOP (1)
                @ManagerBranchID = EB.BranchID
            FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
            WHERE EB.EmployeeID = @ManagerEmployeeID
              AND EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
            ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

            IF @ManagerBranchID IS NULL
            BEGIN
                RAISERROR('Manager has no current branch assignment.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;

            IF @TargetBranchID <> @ManagerBranchID
            BEGIN
                RAISERROR('A manager can suspend only employees in the manager''s current branch.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;
        END;

        UPDATE dbo.Employee
        SET EmpStatus = N'OnLeave'
        WHERE EmployeeID = @EmployeeID;

        INSERT INTO dbo.AuditLog
        (
            UserID,
            ActionType,
            TableName,
            RecordID,
            Details
        )
        VALUES
        (
            @ManagerUserID,
            N'EmployeeSuspended',
            N'Employee',
            @EmployeeID,
            CONCAT(
                N'Employee suspended in BranchID=', @TargetBranchID,
                N'; SuspendedBy=', CASE WHEN @IsHighAdmin = 1 THEN N'HighAdmin' ELSE N'BranchManager' END,
                N'; Reason=', ISNULL(NULLIF(LTRIM(RTRIM(@Reason)), N''), N'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @EmployeeID AS EmployeeID,
            @TargetBranchID AS BranchID,
            N'OnLeave' AS EmpStatus,
            @ManagerUserID AS SuspendedByUserID;
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
