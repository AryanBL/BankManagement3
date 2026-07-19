/* =========================================================
   Procedure_Employee_Unsuspend.sql
   sp_Employee_Unsuspend
   ---------------------------------------------------------
   Restores an ordinary suspended employee from OnLeave to
   Active. Only the same manager or HighAdmin user who recorded
   the latest suspension may reverse it.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Employee_Unsuspend
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
            @TargetStatus NVARCHAR(20) = NULL,
            @TargetJobTitle NVARCHAR(100) = NULL,
            @TargetCanAccessAdmin BIT = 0,
            @LatestSuspensionAuditID INT = NULL,
            @LatestSuspendedByUserID INT = NULL;

        SET @IsHighAdmin = dbo.fn_UserHasEffectiveRole(@ManagerUserID, N'HighAdmin');
        SET @IsAdmin = dbo.fn_UserHasEffectiveRole(@ManagerUserID, N'Admin');

        IF @IsHighAdmin = 0 AND @IsAdmin = 0
        BEGIN
            RAISERROR('Only an effective branch manager/Admin or HighAdmin can reactivate an employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT
            @TargetStatus = E.EmpStatus,
            @TargetJobTitle = E.JobTitle,
            @TargetCanAccessAdmin = E.CanAccessAdmin
        FROM dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
        WHERE E.EmployeeID = @EmployeeID;

        IF @TargetStatus IS NULL
        BEGIN
            RAISERROR('Target employee does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetStatus <> N'OnLeave'
        BEGIN
            RAISERROR('Only employees with OnLeave status can be reactivated.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TargetJobTitle IN (N'Branch Manager', N'Vice Manager') OR @TargetCanAccessAdmin = 1
        BEGIN
            RAISERROR('Manager-level employees must be reactivated through the HighAdmin manager endpoint.', 16, 1);
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

        SELECT TOP (1)
            @LatestSuspensionAuditID = A.AuditID,
            @LatestSuspendedByUserID = A.UserID
        FROM dbo.AuditLog AS A WITH (UPDLOCK, HOLDLOCK)
        WHERE A.TableName = N'Employee'
          AND A.RecordID = @EmployeeID
          AND A.ActionType = N'EmployeeSuspended'
        ORDER BY A.ActionDate DESC, A.AuditID DESC;

        IF @LatestSuspensionAuditID IS NULL
        BEGIN
            RAISERROR('No suspension record exists for this employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @LatestSuspendedByUserID <> @ManagerUserID
        BEGIN
            RAISERROR('Only the manager or HighAdmin user who performed the latest suspension can reverse it.', 16, 1);
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

            IF @ManagerEmployeeID IS NULL OR @ManagerEmployeeID = @EmployeeID
            BEGIN
                RAISERROR('Invalid manager identity for employee reactivation.', 16, 1);
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
                RAISERROR('Only an active Branch Manager or Vice Manager can reactivate branch employees.', 16, 1);
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

            IF @ManagerBranchID IS NULL OR @ManagerBranchID <> @TargetBranchID
            BEGIN
                RAISERROR('A manager can reactivate only employees in the manager''s current branch.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;
        END;

        UPDATE dbo.Employee
        SET EmpStatus = N'Active'
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
            N'EmployeeUnsuspended',
            N'Employee',
            @EmployeeID,
            CONCAT(
                N'Employee restored to Active in BranchID=', @TargetBranchID,
                N'; ReversedSuspensionAuditID=', @LatestSuspensionAuditID,
                N'; Reason=', ISNULL(NULLIF(LTRIM(RTRIM(@Reason)), N''), N'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @EmployeeID AS EmployeeID,
            @TargetBranchID AS BranchID,
            N'Active' AS EmpStatus,
            @ManagerUserID AS ReactivatedByUserID,
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
