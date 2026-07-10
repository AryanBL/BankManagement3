
/* =========================================================
   Procedure_HighAdmin_SuspendManager.sql
   sp_HighAdmin_SuspendManager
   ---------------------------------------------------------
   HighAdmin suspends a manager-level employee by setting
   EmpStatus = OnLeave. The linked user account remains active
   for Customer login.
   ========================================================= */

IF OBJECT_ID('dbo.sp_HighAdmin_SuspendManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_HighAdmin_SuspendManager;
GO

CREATE PROCEDURE dbo.sp_HighAdmin_SuspendManager
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

        DECLARE @TargetUserID INT, @JobTitle NVARCHAR(100);

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Users AS U
            INNER JOIN dbo.UserRoles AS UR ON UR.UserID = U.UserID
            INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
            WHERE U.UserID = @HighAdminUserID
              AND U.IsActive = 1
              AND R.RoleName = 'HighAdmin'
        )
        BEGIN
            RAISERROR('Only HighAdmin can suspend managers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @JobTitle = JobTitle
        FROM dbo.Employee
        WHERE EmployeeID = @ManagerEmployeeID
          AND EmpStatus = 'Active';

        IF @JobTitle NOT IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('Target employee is not an active manager-level employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @TargetUserID = UserID FROM dbo.Users WHERE EmployeeID = @ManagerEmployeeID;

        UPDATE dbo.Employee
        SET EmpStatus = 'OnLeave'
        WHERE EmployeeID = @ManagerEmployeeID;

        -- IMPORTANT: Users.IsActive is NOT changed here.
        -- The suspended manager loses employee/admin privileges through Employee.EmpStatus,
        -- but can still log in as a Customer.

        INSERT INTO dbo.AuditLog(UserID, ActionType, TableName, RecordID, Details)
        VALUES(@HighAdminUserID, 'ManagerSuspended', 'Employee', @ManagerEmployeeID,
               CONCAT('JobTitle=', @JobTitle, '; Reason=', ISNULL(@Reason, 'not provided')));

        COMMIT TRANSACTION;

        SELECT @ManagerEmployeeID AS EmployeeID, 'OnLeave' AS NewStatus;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
        RETURN;
    END CATCH
END;
GO
