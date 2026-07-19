/* =========================================================
   Procedure_HighAdmin_SuspendManager.sql
   sp_HighAdmin_SuspendManager
   ---------------------------------------------------------
   HighAdmin suspends an active Branch Manager or Vice Manager
   by setting EmpStatus=OnLeave. The current EMPB assignment and
   customer login remain in place.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_HighAdmin_SuspendManager
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

        DECLARE
            @JobTitle NVARCHAR(100) = NULL,
            @BranchID INT = NULL;

        IF dbo.fn_UserHasEffectiveRole(@HighAdminUserID, N'HighAdmin') = 0
        BEGIN
            RAISERROR('Only an effective HighAdmin can suspend managers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT
            @JobTitle = E.JobTitle
        FROM dbo.Employee AS E WITH (UPDLOCK, HOLDLOCK)
        WHERE E.EmployeeID = @ManagerEmployeeID
          AND E.EmpStatus = N'Active';

        IF @JobTitle NOT IN (N'Branch Manager', N'Vice Manager')
        BEGIN
            RAISERROR('Target employee is not an active manager-level employee.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT TOP (1)
            @BranchID = EB.BranchID
        FROM dbo.EMPB AS EB WITH (UPDLOCK, HOLDLOCK)
        WHERE EB.EmployeeID = @ManagerEmployeeID
          AND EB.WorkingStatus = N'Working'
          AND EB.EndDate IS NULL
        ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

        IF @BranchID IS NULL
        BEGIN
            RAISERROR('The target manager has no current branch assignment.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        UPDATE dbo.Employee
        SET EmpStatus = N'OnLeave'
        WHERE EmployeeID = @ManagerEmployeeID;

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
            @HighAdminUserID,
            N'ManagerSuspended',
            N'Employee',
            @ManagerEmployeeID,
            CONCAT(
                N'JobTitle=', @JobTitle,
                N'; BranchID=', @BranchID,
                N'; Reason=', ISNULL(NULLIF(LTRIM(RTRIM(@Reason)), N''), N'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @ManagerEmployeeID AS EmployeeID,
            @BranchID AS BranchID,
            @JobTitle AS JobTitle,
            N'OnLeave' AS NewStatus,
            @HighAdminUserID AS SuspendedByUserID;
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
