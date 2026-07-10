/* =========================================================
   Procedure_EmployeeTransfer_RequestByEmployee.sql
   sp_EmployeeTransfer_RequestByEmployee
   ---------------------------------------------------------
   PURPOSE:
   Employee starts a transfer request from his/her current branch
   to a selected destination branch.

   WORKFLOW:
   Employee request -> PendingCurrentManagerApproval.

   RULES:
   - User must be an active Employee user.
   - Linked Employee must be Active.
   - Employee must have one current Working branch assignment.
   - Destination branch must be different from current branch.
   - Employee cannot already have an open transfer request.
   ========================================================= */

IF OBJECT_ID('dbo.sp_EmployeeTransfer_RequestByEmployee', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EmployeeTransfer_RequestByEmployee;
GO

CREATE PROCEDURE dbo.sp_EmployeeTransfer_RequestByEmployee
(
    @UserID INT,
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
            @EmployeeID INT,
            @FromBranchID INT;

        SELECT @EmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND U.EmployeeID IS NOT NULL;

        IF @EmployeeID IS NULL
        BEGIN
            RAISERROR('Invalid or inactive employee user.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = 'Employee'
        )
        BEGIN
            RAISERROR('Transfer request requires Employee application role.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Employee AS E
            WHERE E.EmployeeID = @EmployeeID
              AND E.EmpStatus = 'Active'
        )
        BEGIN
            RAISERROR('Linked employee record is invalid or not active.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1) @FromBranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @EmployeeID
          AND EB.WorkingStatus = 'Working'
          AND EB.EndDate IS NULL;

        IF @FromBranchID IS NULL
        BEGIN
            RAISERROR('Employee has no current branch assignment.', 16, 1);
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
            TransferStatus
        )
        VALUES
        (
            @EmployeeID,
            @FromBranchID,
            @ToBranchID,
            @UserID,
            'EmployeeRequest',
            @Reason,
            'PendingCurrentManagerApproval'
        );

        SET @TransferRequestID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES
        (
            @UserID,
            'EmployeeTransferRequestedByEmployee',
            'EmployeeTransferRequest',
            @TransferRequestID,
            CONCAT('EmployeeID=', @EmployeeID, '; FromBranchID=', @FromBranchID, '; ToBranchID=', @ToBranchID)
        );

        COMMIT TRANSACTION;

        SELECT @TransferRequestID AS TransferRequestID,
               @EmployeeID AS EmployeeID,
               @FromBranchID AS FromBranchID,
               @ToBranchID AS ToBranchID,
               'PendingCurrentManagerApproval' AS TransferStatus;
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
