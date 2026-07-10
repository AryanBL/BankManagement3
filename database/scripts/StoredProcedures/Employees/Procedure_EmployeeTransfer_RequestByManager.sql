/* =========================================================
   Procedure_EmployeeTransfer_RequestByManager.sql
   sp_EmployeeTransfer_RequestByManager
   ---------------------------------------------------------
   PURPOSE:
   Branch Manager or Vice Manager requests transferring an employee
   from his/her current branch to another branch.

   WORKFLOW:
   Manager request -> PendingDestinationManagerApproval.

   RULES:
   - Requesting user must be Branch Manager or Vice Manager of the
     employee's current branch.
   - Requesting user must have Admin application role and
     CanAccessAdmin = 1.
   - Destination branch manager approval is still required before
     EMPB is changed.
   ========================================================= */

IF OBJECT_ID('dbo.sp_EmployeeTransfer_RequestByManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EmployeeTransfer_RequestByManager;
GO

CREATE PROCEDURE dbo.sp_EmployeeTransfer_RequestByManager
(
    @ManagerUserID INT,
    @EmployeeID INT,
    @ToBranchID INT,
    @Reason NVARCHAR(500) = NULL,
    @TransferRequestID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @TransferRequestID = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @ManagerEmployeeID INT,
            @ManagerBranchID INT,
            @ManagerJobTitle NVARCHAR(100),
            @ManagerCanAccessAdmin BIT,
            @FromBranchID INT;

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
            INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @ManagerUserID
              AND R.RoleName = 'Admin'
        )
        BEGIN
            RAISERROR('Manager transfer request requires Admin application role.', 16, 1);
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
            RAISERROR('Only a Branch Manager or Vice Manager with admin capability can request transfers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1) @ManagerBranchID = EB.BranchID
        FROM dbo.EMPB AS EB
        WHERE EB.EmployeeID = @ManagerEmployeeID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        SELECT TOP (1) @FromBranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @EmployeeID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        IF @ManagerBranchID IS NULL
        BEGIN
            RAISERROR('Manager has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @FromBranchID IS NULL
        BEGIN
            RAISERROR('Target employee has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @ManagerBranchID <> @FromBranchID
        BEGIN
            RAISERROR('Manager can request transfer only for employees in his/her current branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID AND EmpStatus = 'Active')
        BEGIN
            RAISERROR('Target employee does not exist or is not active.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE BranchID = @ToBranchID)
        BEGIN
            RAISERROR('Destination branch does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @FromBranchID = @ToBranchID
        BEGIN
            RAISERROR('Destination branch must be different from current branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;
        

        IF EXISTS
        (
            SELECT 1
            FROM dbo.EmployeeTransferRequest WITH (UPDLOCK, HOLDLOCK)
            WHERE EmployeeID = @EmployeeID
              AND TransferStatus IN ('PendingCurrentManagerApproval', 'PendingDestinationManagerApproval')
        )
        BEGIN
            RAISERROR('Employee already has an open transfer request.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        INSERT INTO dbo.EmployeeTransferRequest
        (
            EmployeeID,
            FromBranchID,
            ToBranchID,
            RequestedByUserID,
            RequestType,
            Reason,
            CurrentManagerUserID,
            CurrentManagerDecision,
            CurrentManagerDecisionDate,
            CurrentManagerNote,
            TransferStatus
        )
        VALUES
        (
            @EmployeeID,
            @FromBranchID,
            @ToBranchID,
            @ManagerUserID,
            'ManagerRequest',
            @Reason,
            @ManagerUserID,
            'Approved',
            GETDATE(),
            'Current branch manager initiated and approved request.',
            'PendingDestinationManagerApproval'
        );

        SET @TransferRequestID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES
        (
            @ManagerUserID,
            'EmployeeTransferRequestedByManager',
            'EmployeeTransferRequest',
            @TransferRequestID,
            CONCAT('EmployeeID=', @EmployeeID, '; FromBranchID=', @FromBranchID, '; ToBranchID=', @ToBranchID)
        );

        COMMIT TRANSACTION;

        SELECT @TransferRequestID AS TransferRequestID,
               @EmployeeID AS EmployeeID,
               @FromBranchID AS FromBranchID,
               @ToBranchID AS ToBranchID,
               'PendingDestinationManagerApproval' AS TransferStatus;
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
