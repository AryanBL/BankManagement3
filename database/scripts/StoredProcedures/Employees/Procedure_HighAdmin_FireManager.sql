
/* =========================================================
   Procedure_HighAdmin_FireManager.sql
   sp_HighAdmin_FireManager
   ---------------------------------------------------------
   HighAdmin terminates a manager-level employee. The linked user account remains active for Customer login.
   ========================================================= */

IF OBJECT_ID('dbo.sp_HighAdmin_FireManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_HighAdmin_FireManager;
GO

CREATE PROCEDURE dbo.sp_HighAdmin_FireManager
(
    @HighAdminUserID INT,
    @ManagerEmployeeID INT,
    @TerminationDate DATE = NULL,
    @Reason NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @TargetUserID INT, @JobTitle NVARCHAR(100);

        IF @TerminationDate IS NULL SET @TerminationDate = CAST(GETDATE() AS DATE);

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
            RAISERROR('Only HighAdmin can fire managers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @JobTitle = JobTitle
        FROM dbo.Employee
        WHERE EmployeeID = @ManagerEmployeeID;

        IF @JobTitle NOT IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('Target employee is not a manager-level employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @TargetUserID = UserID FROM dbo.Users WHERE EmployeeID = @ManagerEmployeeID;

        UPDATE dbo.Employee
        SET EmpStatus = 'Terminated',
            CanAccessAdmin = 0
        WHERE EmployeeID = @ManagerEmployeeID;

        -- IMPORTANT: Users.IsActive is NOT changed here.
        -- The fired manager loses manager/employee privileges through Employee.EmpStatus
        -- and removal of Admin role, but can still log in as a Customer.

        DELETE UR
        FROM dbo.UserRoles AS UR
        INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
        WHERE UR.UserID = @TargetUserID
          AND R.RoleName = 'Admin';

        UPDATE dbo.EMPB
        SET EndDate = @TerminationDate,
            WorkingStatus = 'Ended'
        WHERE EmployeeID = @ManagerEmployeeID
          AND WorkingStatus = 'Working'
          AND EndDate IS NULL;

        INSERT INTO dbo.AuditLog(UserID, ActionType, TableName, RecordID, Details)
        VALUES(@HighAdminUserID, 'ManagerFired', 'Employee', @ManagerEmployeeID,
               CONCAT('JobTitle=', @JobTitle, '; Reason=', ISNULL(@Reason, 'not provided')));

        COMMIT TRANSACTION;

        SELECT @ManagerEmployeeID AS EmployeeID, 'Terminated' AS NewStatus;
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
