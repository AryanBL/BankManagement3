/* =========================================================
   Procedure_EmployeeTransfer_ApproveCurrentManager.sql
   sp_EmployeeTransfer_ApproveCurrentManager
   ---------------------------------------------------------
   PURPOSE:
   Current branch manager / vice manager approves or rejects an
   employee-initiated transfer request.

   RULES:
   - Applies only to requests with status PendingCurrentManagerApproval.
   - Acting user must be Branch Manager or Vice Manager of FromBranchID.
   - Acting user must have Admin application role and CanAccessAdmin = 1.
   - Approve -> status becomes PendingDestinationManagerApproval.
   - Reject  -> status becomes RejectedByCurrentManager.
   ========================================================= */

IF OBJECT_ID('dbo.sp_EmployeeTransfer_ApproveCurrentManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EmployeeTransfer_ApproveCurrentManager;
GO

CREATE PROCEDURE dbo.sp_EmployeeTransfer_ApproveCurrentManager
(
    @ManagerUserID INT,
    @TransferRequestID INT,
    @Approve BIT,
    @DecisionNote NVARCHAR(500) = NULL
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
            @EmployeeID INT,
            @FromBranchID INT,
            @CurrentStatus NVARCHAR(50);

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
            RAISERROR('Current-manager approval requires Admin application role.', 16, 1);
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
            RAISERROR('Only a Branch Manager or Vice Manager with admin capability can approve current-branch transfers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1) @ManagerBranchID = EB.BranchID
        FROM dbo.EMPB AS EB
        WHERE EB.EmployeeID = @ManagerEmployeeID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        SELECT
            @EmployeeID = TR.EmployeeID,
            @FromBranchID = TR.FromBranchID,
            @CurrentStatus = TR.TransferStatus
        FROM dbo.EmployeeTransferRequest AS TR WITH (UPDLOCK, HOLDLOCK)
        WHERE TR.TransferRequestID = @TransferRequestID;

        IF @EmployeeID IS NULL
        BEGIN
            RAISERROR('Transfer request does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @CurrentStatus <> 'PendingCurrentManagerApproval'
        BEGIN
            RAISERROR('Transfer request is not waiting for current manager approval.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @ManagerBranchID IS NULL OR @ManagerBranchID <> @FromBranchID
        BEGIN
            RAISERROR('Current manager can approve only requests from his/her current branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @Approve = 1
        BEGIN
            UPDATE dbo.EmployeeTransferRequest
            SET CurrentManagerUserID = @ManagerUserID,
                CurrentManagerDecision = 'Approved',
                CurrentManagerDecisionDate = GETDATE(),
                CurrentManagerNote = @DecisionNote,
                TransferStatus = 'PendingDestinationManagerApproval'
            WHERE TransferRequestID = @TransferRequestID;

            INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
            VALUES
            (
                @ManagerUserID,
                'EmployeeTransferApprovedByCurrentManager',
                'EmployeeTransferRequest',
                @TransferRequestID,
                CONCAT('EmployeeID=', @EmployeeID, '; FromBranchID=', @FromBranchID)
            );
        END
        ELSE
        BEGIN
            UPDATE dbo.EmployeeTransferRequest
            SET CurrentManagerUserID = @ManagerUserID,
                CurrentManagerDecision = 'Rejected',
                CurrentManagerDecisionDate = GETDATE(),
                CurrentManagerNote = @DecisionNote,
                TransferStatus = 'RejectedByCurrentManager',
                CancelledAt = GETDATE()
            WHERE TransferRequestID = @TransferRequestID;

            INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
            VALUES
            (
                @ManagerUserID,
                'EmployeeTransferRejectedByCurrentManager',
                'EmployeeTransferRequest',
                @TransferRequestID,
                CONCAT('EmployeeID=', @EmployeeID, '; FromBranchID=', @FromBranchID, '; Note=', ISNULL(@DecisionNote, 'not provided'))
            );
        END;

        COMMIT TRANSACTION;

        SELECT TransferRequestID, EmployeeID, FromBranchID, ToBranchID, TransferStatus
        FROM dbo.EmployeeTransferRequest
        WHERE TransferRequestID = @TransferRequestID;
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
