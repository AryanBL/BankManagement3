/* =========================================================
   Procedure_HighAdmin_UnsuspendManager.sql
   sp_HighAdmin_UnsuspendManager
   ---------------------------------------------------------
   Restores a suspended Branch Manager or Vice Manager from
   OnLeave to Active. Only the same HighAdmin user who recorded
   the latest manager suspension may reverse it.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_HighAdmin_UnsuspendManager
(
    @HighAdminUserID INT,
    @ManagerEmployeeID INT,
    @Reason NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @JobTitle NVARCHAR(100) = NULL,
            @EmpStatus NVARCHAR(20) = NULL,
            @BranchID INT = NULL,
            @LatestSuspensionAuditID INT = NULL,
            @LatestSuspendedByUserID INT = NULL,
            @AdminRoleID INT = NULL;

        IF dbo.fn_UserHasEffectiveRole(@HighAdminUserID, N'HighAdmin') = 0
        BEGIN
            RAISERROR('Only an effective HighAdmin can reactivate managers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT
            @JobTitle = E.JobTitle,
            @EmpStatus = E.EmpStatus
        FROM dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
        WHERE E.EmployeeID = @ManagerEmployeeID;

        IF @JobTitle IS NULL
        BEGIN
            RAISERROR('Target manager does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @JobTitle NOT IN (N'Branch Manager', N'Vice Manager')
        BEGIN
            RAISERROR('Target employee is not manager-level.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @EmpStatus <> N'OnLeave'
        BEGIN
            RAISERROR('Only managers with OnLeave status can be reactivated.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1)
            @BranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @ManagerEmployeeID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

        IF @BranchID IS NULL
        BEGIN
            RAISERROR('The target manager has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1)
            @LatestSuspensionAuditID = A.AuditID,
            @LatestSuspendedByUserID = A.UserID
        FROM dbo.AuditLog AS A WITH (UPDLOCK, HOLDLOCK)
        WHERE A.TableName = N'Employee'
          AND A.RecordID = @ManagerEmployeeID
          AND A.ActionType = N'ManagerSuspended'
        ORDER BY A.ActionDate DESC, A.AuditID DESC;

        IF @LatestSuspensionAuditID IS NULL
        BEGIN
            RAISERROR('No manager suspension record exists for this employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @LatestSuspendedByUserID <> @HighAdminUserID
        BEGIN
            RAISERROR('Only the HighAdmin user who performed the latest suspension can reverse it.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @JobTitle = N'Branch Manager'
           AND EXISTS
           (
               SELECT 1
               FROM dbo.EMPB AS EB
               INNER JOIN dbo.Employee AS E
                   ON E.EmployeeID = EB.EmployeeID
               WHERE EB.BranchID = @BranchID
                 AND EB.WorkingStatus = N'Working'
                 AND EB.EndDate IS NULL
                 AND E.EmpStatus = N'Active'
                 AND E.JobTitle = N'Branch Manager'
                 AND E.EmployeeID <> @ManagerEmployeeID
           )
        BEGIN
            RAISERROR('This Branch Manager cannot be reactivated because the branch already has another active Branch Manager.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        UPDATE dbo.Employee
        SET EmpStatus = N'Active'
        WHERE EmployeeID = @ManagerEmployeeID;

        SELECT @AdminRoleID = R.RoleID
        FROM dbo.Roles AS R
        WHERE R.RoleName = N'Admin';

        IF @AdminRoleID IS NULL
        BEGIN
            RAISERROR('Admin role is missing from the role catalogue.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        INSERT INTO dbo.UserRoles (UserID, RoleID)
        SELECT U.UserID, @AdminRoleID
        FROM dbo.Users AS U
        WHERE U.EmployeeID = @ManagerEmployeeID
          AND U.IsActive = 1
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.UserRoles AS UR
              WHERE UR.UserID = U.UserID
                AND UR.RoleID = @AdminRoleID
          );

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Users AS U
            INNER JOIN dbo.UserRoles AS UR
                ON UR.UserID = U.UserID
               AND UR.RoleID = @AdminRoleID
            WHERE U.EmployeeID = @ManagerEmployeeID
              AND U.IsActive = 1
        )
        BEGIN
            RAISERROR('The manager has no active application user to restore the Admin role.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

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
            @HighAdminUserID,
            N'ManagerUnsuspended',
            N'Employee',
            @ManagerEmployeeID,
            CONCAT(
                N'JobTitle=', @JobTitle,
                N'; BranchID=', @BranchID,
                N'; RestoredStatus=Active',
                N'; RestoredAdminRole=1',
                N'; ReversedSuspensionAuditID=', @LatestSuspensionAuditID,
                N'; Reason=', ISNULL(NULLIF(LTRIM(RTRIM(@Reason)), N''), N'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @ManagerEmployeeID AS EmployeeID,
            @BranchID AS BranchID,
            @JobTitle AS JobTitle,
            N'Active' AS NewStatus,
            CAST(1 AS BIT) AS AdminRoleRestored,
            @HighAdminUserID AS ReactivatedByUserID,
            @LatestSuspensionAuditID AS ReversedSuspensionAuditID;
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
