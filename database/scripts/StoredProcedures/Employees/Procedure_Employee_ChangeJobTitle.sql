/* =========================================================
   Procedure_Employee_ChangeJobTitle_FINAL.sql
   sp_Employee_ChangeJobTitle
   ---------------------------------------------------------
   PURPOSE:
   Allows a Branch Manager or Vice Manager to change the job
   title of an ordinary employee in the manager's current branch.

   FINAL BUSINESS RULES:
   1. Acting user must be an active employee user.
   2. Acting user must have Admin application role.
   3. Acting employee must have CanAccessAdmin = 1.
   4. Acting employee must be Branch Manager or Vice Manager.
   5. Acting manager must have a current EMPB branch assignment.
   6. Target employee must belong to the same current branch.
   7. Target employee must be ordinary, not manager-level.
   8. New title cannot be Branch Manager or Vice Manager.
   9. Terminated employees cannot have their title changed here.
   10. Procedure writes an AuditLog row.

   NOTE:
   - This procedure does not change UserRoles.
   - This procedure does not change CanAccessAdmin.
   - This procedure does not promote/downgrade managers.
   - Manager-level title changes must be handled by HighAdmin procedures.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Employee_ChangeJobTitle', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Employee_ChangeJobTitle;
GO

CREATE PROCEDURE dbo.sp_Employee_ChangeJobTitle
(
    @ManagerUserID INT,
    @TargetEmployeeID INT,
    @NewJobTitle NVARCHAR(100),
    @ReasonDescription NVARCHAR(500) = NULL
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
            @TargetOldJobTitle NVARCHAR(100),
            @TargetEmpStatus NVARCHAR(20),
            @TargetCanAccessAdmin BIT,
            @TargetHasAdminRole BIT,
            @CleanNewJobTitle NVARCHAR(100);

        SET @CleanNewJobTitle = LTRIM(RTRIM(ISNULL(@NewJobTitle, N'')));

        IF @ManagerUserID IS NULL
        BEGIN
            RAISERROR('ManagerUserID is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetEmployeeID IS NULL
        BEGIN
            RAISERROR('TargetEmployeeID is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF LEN(@CleanNewJobTitle) = 0
        BEGIN
            RAISERROR('New job title is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @CleanNewJobTitle IN (N'Branch Manager', N'Vice Manager')
        BEGIN
            RAISERROR('Branch Manager and Vice Manager titles can only be assigned through HighAdmin manager-control procedures.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

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
            RAISERROR('Changing employee job titles requires the Admin application role.', 16, 1);
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

        IF @ManagerCanAccessAdmin <> 1
           OR @ManagerJobTitle NOT IN (N'Branch Manager', N'Vice Manager')
        BEGIN
            RAISERROR('Only an active Branch Manager or Vice Manager with admin capability can change ordinary employee job titles.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1) @ManagerBranchID = EB.BranchID
        FROM dbo.EMPB AS EB
        WHERE EB.EmployeeID = @ManagerEmployeeID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        IF @ManagerBranchID IS NULL
        BEGIN
            RAISERROR('Manager has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetEmployeeID = @ManagerEmployeeID
        BEGIN
            RAISERROR('Managers cannot change their own job title through this procedure.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT
            @TargetOldJobTitle = E.JobTitle,
            @TargetEmpStatus = E.EmpStatus,
            @TargetCanAccessAdmin = E.CanAccessAdmin
        FROM dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
        WHERE E.EmployeeID = @TargetEmployeeID;

        IF @TargetOldJobTitle IS NULL
        BEGIN
            RAISERROR('Target employee does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetEmpStatus = 'Terminated'
        BEGIN
            RAISERROR('Cannot change job title for a terminated employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1) @TargetBranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @TargetEmployeeID
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
            RAISERROR('Managers can change job titles only for employees in their own current branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SET @TargetHasAdminRole = CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.Users AS TU
            INNER JOIN dbo.UserRoles AS TUR
                ON TUR.UserID = TU.UserID
            INNER JOIN dbo.Roles AS TR
                ON TR.RoleID = TUR.RoleID
            WHERE TU.EmployeeID = @TargetEmployeeID
              AND TR.RoleName = 'Admin'
        ) THEN 1 ELSE 0 END;

        IF @TargetCanAccessAdmin = 1
           OR @TargetOldJobTitle IN (N'Branch Manager', N'Vice Manager')
           OR @TargetHasAdminRole = 1
        BEGIN
            RAISERROR('This procedure cannot change manager-level employees. Use HighAdmin manager-control procedures.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetOldJobTitle = @CleanNewJobTitle
        BEGIN
            RAISERROR('Target employee already has this job title.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        UPDATE dbo.Employee
        SET JobTitle = @CleanNewJobTitle
        WHERE EmployeeID = @TargetEmployeeID;

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
            @ManagerUserID,
            'EmployeeJobTitleChanged',
            'Employee',
            @TargetEmployeeID,
            GETDATE(),
            CONCAT(
                'Changed by ManagerUserID=', @ManagerUserID,
                '; ManagerEmployeeID=', @ManagerEmployeeID,
                '; BranchID=', @ManagerBranchID,
                '; OldJobTitle=', ISNULL(@TargetOldJobTitle, ''),
                '; NewJobTitle=', @CleanNewJobTitle,
                '; Reason=', ISNULL(@ReasonDescription, 'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @TargetEmployeeID AS EmployeeID,
            @TargetBranchID AS BranchID,
            @TargetOldJobTitle AS OldJobTitle,
            @CleanNewJobTitle AS NewJobTitle,
            'Job title changed successfully.' AS ResultMessage;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;
END;
GO