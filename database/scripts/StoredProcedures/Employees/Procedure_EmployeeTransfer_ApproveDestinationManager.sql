/* =========================================================
   Procedure_EmployeeTransfer_ApproveDestinationManager.sql
   sp_EmployeeTransfer_ApproveDestinationManager
   ---------------------------------------------------------
   PURPOSE:
   Destination branch manager / vice manager approves or rejects
   a transfer request. Approval completes the actual branch transfer
   in dbo.EMPB.

   RULES:
   - Applies only to requests with status PendingDestinationManagerApproval.
   - Acting user must be Branch Manager or Vice Manager of ToBranchID.
   - Acting user must have Admin application role and CanAccessAdmin = 1.
   - If approved:
       1) current EMPB Working row for the employee is ended,
       2) new EMPB Working row is inserted for the destination branch,
       3) request status becomes Completed.
   - If rejected:
       request status becomes RejectedByDestinationManager.

   DATE MODEL:
   - EffectiveDate is CAST(GETDATE() AS DATE).
   - Existing EMPB date-overlap trigger treats EndDate as the boundary
     of the previous period. This matches the current project trigger.
   ========================================================= */

IF OBJECT_ID('dbo.sp_EmployeeTransfer_ApproveDestinationManager', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EmployeeTransfer_ApproveDestinationManager;
GO

CREATE PROCEDURE dbo.sp_EmployeeTransfer_ApproveDestinationManager
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
            @ToBranchID INT,
            @CurrentStatus NVARCHAR(50),
            @CurrentEMPBID INT,
            @EffectiveDate DATE;

        SET @EffectiveDate = CAST(GETDATE() AS DATE);

        SELECT @ManagerEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        WHERE U.UserID = @ManagerUserID
          AND U.IsActive = 1
          AND U.EmployeeID IS NOT NULL;

        IF @ManagerEmployeeID IS NULL
        BEGIN
            RAISERROR('Invalid or inactive destination manager user.', 16, 1);
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
            RAISERROR('Destination-manager approval requires Admin application role.', 16, 1);
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
            RAISERROR('Destination manager employee record is invalid or not active.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @ManagerCanAccessAdmin <> 1 OR @ManagerJobTitle NOT IN ('Branch Manager', 'Vice Manager')
        BEGIN
            RAISERROR('Only a Branch Manager or Vice Manager with admin capability can approve destination transfers.', 16, 1);
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
            @ToBranchID = TR.ToBranchID,
            @CurrentStatus = TR.TransferStatus
        FROM dbo.EmployeeTransferRequest AS TR WITH (UPDLOCK, HOLDLOCK)
        WHERE TR.TransferRequestID = @TransferRequestID;

        IF @EmployeeID IS NULL
        BEGIN
            RAISERROR('Transfer request does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @CurrentStatus <> 'PendingDestinationManagerApproval'
        BEGIN
            RAISERROR('Transfer request is not waiting for destination manager approval.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @ManagerBranchID IS NULL OR @ManagerBranchID <> @ToBranchID
        BEGIN
            RAISERROR('Destination manager can approve only requests to his/her current branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @Approve = 0
        BEGIN
            UPDATE dbo.EmployeeTransferRequest
            SET DestinationManagerUserID = @ManagerUserID,
                DestinationManagerDecision = 'Rejected',
                DestinationManagerDecisionDate = GETDATE(),
                DestinationManagerNote = @DecisionNote,
                TransferStatus = 'RejectedByDestinationManager',
                CancelledAt = GETDATE()
            WHERE TransferRequestID = @TransferRequestID;

            INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
            VALUES
            (
                @ManagerUserID,
                'EmployeeTransferRejectedByDestinationManager',
                'EmployeeTransferRequest',
                @TransferRequestID,
                CONCAT('EmployeeID=', @EmployeeID, '; ToBranchID=', @ToBranchID, '; Note=', ISNULL(@DecisionNote, 'not provided'))
            );

            COMMIT TRANSACTION;

            SELECT TransferRequestID, EmployeeID, FromBranchID, ToBranchID, TransferStatus
            FROM dbo.EmployeeTransferRequest
            WHERE TransferRequestID = @TransferRequestID;

            RETURN;
        END;

        -- Lock and validate the employee's current branch assignment.
        SELECT TOP (1)
            @CurrentEMPBID = EB.EMPBID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @EmployeeID
          AND EB.BranchID = @FromBranchID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        IF @CurrentEMPBID IS NULL
        BEGIN
            RAISERROR('Employee no longer has the expected current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
            WHERE E.EmployeeID = @EmployeeID
              AND E.EmpStatus = 'Active'
        )
        BEGIN
            RAISERROR('Employee is no longer active.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        -- End previous branch assignment first.
        UPDATE dbo.EMPB
        SET EndDate = @EffectiveDate,
            WorkingStatus = 'Transferred'
        WHERE EMPBID = @CurrentEMPBID;

        -- Start destination branch assignment.
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
            @EmployeeID,
            @ToBranchID,
            @EffectiveDate,
            NULL,
            'Working'
        );

        UPDATE dbo.EmployeeTransferRequest
        SET DestinationManagerUserID = @ManagerUserID,
            DestinationManagerDecision = 'Approved',
            DestinationManagerDecisionDate = GETDATE(),
            DestinationManagerNote = @DecisionNote,
            TransferStatus = 'Completed',
            EffectiveDate = @EffectiveDate,
            CompletedAt = GETDATE()
        WHERE TransferRequestID = @TransferRequestID;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES
        (
            @ManagerUserID,
            'EmployeeTransferCompleted',
            'EmployeeTransferRequest',
            @TransferRequestID,
            CONCAT('EmployeeID=', @EmployeeID, '; FromBranchID=', @FromBranchID, '; ToBranchID=', @ToBranchID, '; EffectiveDate=', CONVERT(VARCHAR(10), @EffectiveDate, 120))
        );

        COMMIT TRANSACTION;

        SELECT TransferRequestID, EmployeeID, FromBranchID, ToBranchID, TransferStatus, EffectiveDate
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
