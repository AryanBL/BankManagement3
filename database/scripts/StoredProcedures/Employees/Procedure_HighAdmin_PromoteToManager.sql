
/* =========================================================
   Procedure_HighAdmin_PromoteToManager.sql
   sp_HighAdmin_PromoteToManager
   ---------------------------------------------------------
   HighAdmin promotes an existing active employee to Branch
   Manager or Vice Manager, grants Admin role, and optionally
   assigns/moves the employee to the target branch.
   ========================================================= */

IF OBJECT_ID('dbo.sp_HighAdmin_PromoteToManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_HighAdmin_PromoteToManager;
GO

CREATE PROCEDURE dbo.sp_HighAdmin_PromoteToManager
(
    @HighAdminUserID INT,
    @EmployeeID INT,
    @BranchID INT,
    @ManagerJobTitle NVARCHAR(100),
    @EffectiveDate DATE = NULL,
    @Reason NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @TargetUserID INT, @CurrentBranchID INT, @CurrentEMPBID INT;

        IF @EffectiveDate IS NULL SET @EffectiveDate = CAST(GETDATE() AS DATE);

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
            RAISERROR('Only HighAdmin can promote employees to manager positions.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @ManagerJobTitle NOT IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('ManagerJobTitle must be Branch Manager or Vice Manager.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID AND EmpStatus = 'Active')
        BEGIN
            RAISERROR('Target employee does not exist or is not active.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @TargetUserID = UserID
        FROM dbo.Users
        WHERE EmployeeID = @EmployeeID
          AND IsActive = 1
          AND CustomerID IS NOT NULL;

        IF @TargetUserID IS NULL
        BEGIN
            RAISERROR('Target employee must have an active user account linked to CustomerID before promotion.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE BranchID = @BranchID)
        BEGIN
            RAISERROR('Target branch does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @ManagerJobTitle = 'Branch Manager' AND EXISTS
        (
            SELECT 1
            FROM dbo.EMPB AS EB
            INNER JOIN dbo.Employee AS E ON E.EmployeeID = EB.EmployeeID
            WHERE EB.BranchID = @BranchID
              AND EB.WorkingStatus = 'Working'
              AND EB.EndDate IS NULL
              AND E.EmpStatus = 'Active'
              AND E.JobTitle = 'Branch Manager'
              AND E.EmployeeID <> @EmployeeID
        )
        BEGIN
            RAISERROR('This branch already has an active Branch Manager. Use ReplaceBranchManager or downgrade the current one first.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1)
            @CurrentEMPBID = EMPBID,
            @CurrentBranchID = BranchID
        FROM dbo.EMPB WITH (UPDLOCK, HOLDLOCK)
        WHERE EmployeeID = @EmployeeID
          AND WorkingStatus = 'Working'
          AND EndDate IS NULL;

        IF @CurrentEMPBID IS NULL
        BEGIN
            INSERT INTO dbo.EMPB(EmployeeID, BranchID, StartDate, EndDate, WorkingStatus)
            VALUES(@EmployeeID, @BranchID, @EffectiveDate, NULL, 'Working');
        END
        ELSE IF @CurrentBranchID <> @BranchID
        BEGIN
            UPDATE dbo.EMPB
            SET EndDate = @EffectiveDate,
                WorkingStatus = 'Transferred'
            WHERE EMPBID = @CurrentEMPBID;

            INSERT INTO dbo.EMPB(EmployeeID, BranchID, StartDate, EndDate, WorkingStatus)
            VALUES(@EmployeeID, @BranchID, @EffectiveDate, NULL, 'Working');
        END;

        UPDATE dbo.Employee
        SET JobTitle = @ManagerJobTitle,
            CanAccessAdmin = 1
        WHERE EmployeeID = @EmployeeID;

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @TargetUserID AND R.RoleName = 'Customer'
        )
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @TargetUserID, RoleID FROM dbo.Roles WHERE RoleName = 'Customer';

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @TargetUserID AND R.RoleName = 'Employee'
        )
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @TargetUserID, RoleID FROM dbo.Roles WHERE RoleName = 'Employee';

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @TargetUserID AND R.RoleName = 'Admin'
        )
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @TargetUserID, RoleID FROM dbo.Roles WHERE RoleName = 'Admin';

        INSERT INTO dbo.AuditLog(UserID, ActionType, TableName, RecordID, Details)
        VALUES(@HighAdminUserID, 'EmployeePromotedToManager', 'Employee', @EmployeeID,
               CONCAT('Promoted to ', @ManagerJobTitle, '; BranchID=', @BranchID, '; Reason=', ISNULL(@Reason, 'not provided')));

        COMMIT TRANSACTION;

        SELECT @EmployeeID AS EmployeeID, @TargetUserID AS UserID, @ManagerJobTitle AS NewJobTitle, @BranchID AS BranchID;
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
