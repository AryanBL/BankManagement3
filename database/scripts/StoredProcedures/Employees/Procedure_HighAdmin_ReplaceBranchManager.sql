/* =========================================================
   Procedure_HighAdmin_ReplaceBranchManager_CROSS_BRANCH_FINAL.sql
   sp_HighAdmin_ReplaceBranchManager
   ---------------------------------------------------------
   PURPOSE:
   Allows the single HighAdmin to replace the Branch Manager of
   a target branch. The replacement employee may be:
     - a manager from another branch,
     - a vice manager from another branch,
     - an active employee who will be promoted by this action,
     - or an active employee without a current branch assignment.

   FINAL BUSINESS RULES:
   1. Only an active HighAdmin application user can execute this.
   2. Target branch must exist.
   3. If the target branch has a current active Branch Manager,
      that manager is downgraded to an ordinary title and loses
      Admin privileges.
   4. The new manager must be an active employee with an active
      user account linked to CustomerID.
   5. If the new manager currently works in another branch, that
      current EMPB row is ended and marked Transferred.
   6. A new current EMPB row is inserted for the target branch.
   7. The new manager receives:
        - JobTitle = 'Branch Manager'
        - CanAccessAdmin = 1
        - Admin application role
   8. Only one current Branch Manager per branch remains enforced
      by ApplyAccessRules_HIGHADMIN_FINAL.sql triggers.
   9. Users.IsActive is not disabled for any downgraded/replaced
      manager because the person must still be able to log in as
      a Customer.

   IMPORTANT DATE NOTE:
   EffectiveDate is the business date of the replacement in EMPB.
   With the existing overlap trigger, old EndDate = new StartDate
   is allowed because overlap uses strict '<' comparison.
   ========================================================= */

IF OBJECT_ID('dbo.sp_HighAdmin_ReplaceBranchManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_HighAdmin_ReplaceBranchManager;
GO

CREATE PROCEDURE dbo.sp_HighAdmin_ReplaceBranchManager
(
    @HighAdminUserID INT,
    @BranchID INT,
    @NewManagerEmployeeID INT,
    @OldManagerNewJobTitle NVARCHAR(100) = N'Senior Employee',
    @EffectiveDate DATE = NULL,
    @Reason NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @OldManagerEmployeeID INT,
            @OldManagerUserID INT,
            @NewManagerUserID INT,
            @NewManagerCurrentEMPBID INT,
            @NewManagerCurrentBranchID INT,
            @NewManagerOldJobTitle NVARCHAR(100),
            @CleanOldManagerNewJobTitle NVARCHAR(100);

        IF @EffectiveDate IS NULL
            SET @EffectiveDate = CAST(GETDATE() AS DATE);

        SET @CleanOldManagerNewJobTitle = LTRIM(RTRIM(ISNULL(@OldManagerNewJobTitle, N'')));

        IF @HighAdminUserID IS NULL
        BEGIN
            RAISERROR('HighAdminUserID is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @BranchID IS NULL
        BEGIN
            RAISERROR('BranchID is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @NewManagerEmployeeID IS NULL
        BEGIN
            RAISERROR('NewManagerEmployeeID is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF LEN(@CleanOldManagerNewJobTitle) = 0
        BEGIN
            RAISERROR('Old manager new job title is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @CleanOldManagerNewJobTitle IN (N'Branch Manager', N'Vice Manager')
        BEGIN
            RAISERROR('The replaced manager must be downgraded to an ordinary non-manager title.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Validate HighAdmin user.
        ------------------------------------------------------------
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Users AS U
            INNER JOIN dbo.UserRoles AS UR
                ON UR.UserID = U.UserID
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            INNER JOIN dbo.Customer AS C
                ON C.CustomerID = U.CustomerID
            WHERE U.UserID = @HighAdminUserID
              AND U.IsActive = 1
              AND C.IsActive = 1
              AND U.EmployeeID IS NULL
              AND R.RoleName = N'HighAdmin'
        )
        BEGIN
            RAISERROR('Only an active HighAdmin user can replace branch managers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Validate target branch.
        ------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE BranchID = @BranchID)
        BEGIN
            RAISERROR('Target branch does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Locate current active Branch Manager of the target branch,
        -- if one exists. Lock the row to serialize replacement.
        ------------------------------------------------------------
        SELECT TOP (1)
            @OldManagerEmployeeID = E.EmployeeID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
            ON E.EmployeeID = EB.EmployeeID
        WHERE EB.BranchID = @BranchID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
          AND E.EmpStatus = N'Active'
          AND E.JobTitle = N'Branch Manager'
        ORDER BY E.EmployeeID;

        IF @OldManagerEmployeeID = @NewManagerEmployeeID
        BEGIN
            RAISERROR('The selected employee is already the current Branch Manager of this branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Validate replacement manager.
        ------------------------------------------------------------
        SELECT @NewManagerOldJobTitle = E.JobTitle
        FROM dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
        WHERE E.EmployeeID = @NewManagerEmployeeID
          AND E.EmpStatus = N'Active';

        IF @NewManagerOldJobTitle IS NULL
        BEGIN
            RAISERROR('New manager employee does not exist or is not active.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @NewManagerUserID = U.UserID
        FROM dbo.Users AS U WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Customer AS C
            ON C.CustomerID = U.CustomerID
        WHERE U.EmployeeID = @NewManagerEmployeeID
          AND U.IsActive = 1
          AND C.IsActive = 1
          AND U.CustomerID IS NOT NULL;

        IF @NewManagerUserID IS NULL
        BEGIN
            RAISERROR('New manager must have an active user account linked to an active CustomerID.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ------------------------------------------------------------
        -- Find replacement employee's current branch assignment.
        -- This is what allows replacing a manager with a manager from
        -- another branch. That old assignment will be closed below.
        ------------------------------------------------------------
        SELECT TOP (1)
            @NewManagerCurrentEMPBID = EB.EMPBID,
            @NewManagerCurrentBranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @NewManagerEmployeeID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

        ------------------------------------------------------------
        -- Downgrade old target branch manager, if the branch already
        -- has one. This happens before inserting/updating the new
        -- manager assignment so the one-Branch-Manager rule stays safe.
        ------------------------------------------------------------
        IF @OldManagerEmployeeID IS NOT NULL
        BEGIN
            SELECT @OldManagerUserID = U.UserID
            FROM dbo.Users AS U WITH (UPDLOCK, HOLDLOCK)
            WHERE U.EmployeeID = @OldManagerEmployeeID;

            UPDATE dbo.Employee
            SET JobTitle = @CleanOldManagerNewJobTitle,
                CanAccessAdmin = 0
            WHERE EmployeeID = @OldManagerEmployeeID;

            IF @OldManagerUserID IS NOT NULL
            BEGIN
                DELETE UR
                FROM dbo.UserRoles AS UR
                INNER JOIN dbo.Roles AS R
                    ON R.RoleID = UR.RoleID
                WHERE UR.UserID = @OldManagerUserID
                  AND R.RoleName = N'Admin';
            END;
        END;

        ------------------------------------------------------------
        -- Move the new manager from his/her current branch to the
        -- target branch when needed.
        ------------------------------------------------------------
        IF @NewManagerCurrentEMPBID IS NULL
        BEGIN
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
                @NewManagerEmployeeID,
                @BranchID,
                @EffectiveDate,
                NULL,
                N'Working'
            );
        END
        ELSE IF @NewManagerCurrentBranchID <> @BranchID
        BEGIN
            UPDATE dbo.EMPB
            SET EndDate = @EffectiveDate,
                WorkingStatus = N'Transferred'
            WHERE EMPBID = @NewManagerCurrentEMPBID;

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
                @NewManagerEmployeeID,
                @BranchID,
                @EffectiveDate,
                NULL,
                N'Working'
            );
        END;

        ------------------------------------------------------------
        -- Promote/confirm the new manager as Branch Manager.
        ------------------------------------------------------------
        UPDATE dbo.Employee
        SET JobTitle = N'Branch Manager',
            CanAccessAdmin = 1
        WHERE EmployeeID = @NewManagerEmployeeID;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @NewManagerUserID
              AND R.RoleName = N'Customer'
        )
        BEGIN
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @NewManagerUserID, R.RoleID
            FROM dbo.Roles AS R
            WHERE R.RoleName = N'Customer';
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @NewManagerUserID
              AND R.RoleName = N'Employee'
        )
        BEGIN
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @NewManagerUserID, R.RoleID
            FROM dbo.Roles AS R
            WHERE R.RoleName = N'Employee';
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @NewManagerUserID
              AND R.RoleName = N'Admin'
        )
        BEGIN
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @NewManagerUserID, R.RoleID
            FROM dbo.Roles AS R
            WHERE R.RoleName = N'Admin';
        END;

        ------------------------------------------------------------
        -- Audit.
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
            @HighAdminUserID,
            N'BranchManagerReplaced',
            N'Branch',
            @BranchID,
            GETDATE(),
            CONCAT(
                'TargetBranchID=', @BranchID,
                '; OldManagerEmployeeID=', ISNULL(CONVERT(NVARCHAR(20), @OldManagerEmployeeID), N'NULL'),
                '; OldManagerNewJobTitle=', CASE WHEN @OldManagerEmployeeID IS NULL THEN N'NULL' ELSE @CleanOldManagerNewJobTitle END,
                '; NewManagerEmployeeID=', @NewManagerEmployeeID,
                '; NewManagerOldJobTitle=', ISNULL(@NewManagerOldJobTitle, N''),
                '; NewManagerPreviousBranchID=', ISNULL(CONVERT(NVARCHAR(20), @NewManagerCurrentBranchID), N'NULL'),
                '; EffectiveDate=', CONVERT(NVARCHAR(30), @EffectiveDate, 23),
                '; Reason=', ISNULL(@Reason, N'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @BranchID AS TargetBranchID,
            @OldManagerEmployeeID AS OldManagerEmployeeID,
            @CleanOldManagerNewJobTitle AS OldManagerNewJobTitle,
            @NewManagerEmployeeID AS NewManagerEmployeeID,
            @NewManagerOldJobTitle AS NewManagerOldJobTitle,
            @NewManagerCurrentBranchID AS NewManagerPreviousBranchID,
            @EffectiveDate AS EffectiveDate,
            N'Branch manager replaced successfully.' AS ResultMessage;
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
