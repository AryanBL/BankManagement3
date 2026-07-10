
/* =========================================================
   Procedure_HighAdmin_DowngradeManager.sql
   sp_HighAdmin_DowngradeManager
   ---------------------------------------------------------
   HighAdmin downgrades a Branch Manager or Vice Manager to a
   normal employee title and removes manager-specific privilege.
   ========================================================= */

IF OBJECT_ID('dbo.sp_HighAdmin_DowngradeManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_HighAdmin_DowngradeManager;
GO

CREATE PROCEDURE dbo.sp_HighAdmin_DowngradeManager
(
    @HighAdminUserID INT,
    @ManagerEmployeeID INT,
    @NewJobTitle NVARCHAR(100),
    @Reason NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @TargetUserID INT, @OldJobTitle NVARCHAR(100);

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
            RAISERROR('Only HighAdmin can downgrade managers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @NewJobTitle IS NULL OR LEN(LTRIM(RTRIM(@NewJobTitle))) = 0
           OR @NewJobTitle IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('NewJobTitle must be a normal non-manager title.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @OldJobTitle = JobTitle
        FROM dbo.Employee
        WHERE EmployeeID = @ManagerEmployeeID;

        IF @OldJobTitle NOT IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('Target employee is not a manager-level employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @TargetUserID = UserID
        FROM dbo.Users
        WHERE EmployeeID = @ManagerEmployeeID;

        UPDATE dbo.Employee
        SET JobTitle = @NewJobTitle,
            CanAccessAdmin = 0
        WHERE EmployeeID = @ManagerEmployeeID;

        IF @TargetUserID IS NOT NULL
        BEGIN
            DELETE UR
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @TargetUserID
              AND R.RoleName = 'Admin';
        END;

        INSERT INTO dbo.AuditLog(UserID, ActionType, TableName, RecordID, Details)
        VALUES(@HighAdminUserID, 'ManagerDowngraded', 'Employee', @ManagerEmployeeID,
               CONCAT('OldJobTitle=', @OldJobTitle, '; NewJobTitle=', @NewJobTitle, '; Reason=', ISNULL(@Reason, 'not provided')));

        COMMIT TRANSACTION;

        SELECT @ManagerEmployeeID AS EmployeeID, @OldJobTitle AS OldJobTitle, @NewJobTitle AS NewJobTitle;
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
