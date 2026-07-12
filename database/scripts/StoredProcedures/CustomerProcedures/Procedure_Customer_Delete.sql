/* =========================================================
   Procedure_Customer_Delete_BRANCH_SCOPED.sql
   sp_Customer_Delete
   ---------------------------------------------------------
   AUTHORIZATION:
   - Effective Employee/Admin can deactivate only customers who
     own at least one account in the caller's current branch.
   - Effective HighAdmin can deactivate any customer.
   - Customer-only self-deactivation is not provided here.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Customer_Delete', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_Delete;
GO

CREATE PROCEDURE dbo.sp_Customer_Delete
(
    @CustomerID INT,
    @UserID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @CallerEmployeeID INT,
            @CurrentBranchID INT,
            @IsEmployeeEffective BIT = 0,
            @IsAdminEffective BIT = 0,
            @IsHighAdminEffective BIT = 0;

        IF @UserID IS NULL
        BEGIN
            RAISERROR('A valid authenticated user is required.', 16, 1);
            RETURN;
        END;

        SELECT @CallerEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        INNER JOIN dbo.Customer AS C ON C.CustomerID = U.CustomerID
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND C.IsActive = 1;

        SET @IsEmployeeEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Employee');
        SET @IsAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Admin');
        SET @IsHighAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin');

        IF @IsEmployeeEffective = 0
           AND @IsAdminEffective = 0
           AND @IsHighAdminEffective = 0
        BEGIN
            RAISERROR('Only an effective Employee, Admin, or HighAdmin can deactivate customers.', 16, 1);
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
        BEGIN RAISERROR('Customer does not exist.', 16, 1); RETURN; END;
        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID AND IsActive = 1)
        BEGIN RAISERROR('Customer is already inactive.', 16, 1); RETURN; END;

        IF @IsHighAdminEffective = 0
        BEGIN
            SELECT TOP (1)
                @CurrentBranchID = EB.BranchID
            FROM dbo.EMPB AS EB
            WHERE EB.EmployeeID = @CallerEmployeeID
              AND EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
            ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

            IF @CurrentBranchID IS NULL
            BEGIN
                RAISERROR('The current employee does not have an active branch assignment.', 16, 1);
                RETURN;
            END;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.Account AS A
                WHERE A.CustomerID = @CustomerID
                  AND A.BranchID = @CurrentBranchID
            )
            BEGIN
                RAISERROR('Employees and managers can deactivate only customers corresponding to their current branch.', 16, 1);
                RETURN;
            END;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.Account AS A
            INNER JOIN dbo.Transactions AS T
                ON T.FromAccountID = A.AccountID OR T.ToAccountID = A.AccountID
            WHERE A.CustomerID = @CustomerID
              AND T.TransactionStatus = N'Pending'
        )
        BEGIN
            RAISERROR('Cannot deactivate this customer: at least one account has a Pending transaction.', 16, 1);
            RETURN;
        END;

        BEGIN TRANSACTION;

        UPDATE dbo.Customer
        SET IsActive = 0
        WHERE CustomerID = @CustomerID;

        DECLARE @DeactivatedUsers TABLE(UserID INT PRIMARY KEY);

        UPDATE dbo.Users
        SET IsActive = 0
        OUTPUT inserted.UserID INTO @DeactivatedUsers(UserID)
        WHERE CustomerID = @CustomerID
          AND IsActive = 1;

        UPDATE S
        SET IsActive = 0,
            LogoutTime = GETDATE()
        FROM dbo.Sessions AS S
        INNER JOIN @DeactivatedUsers AS DU ON DU.UserID = S.UserID
        WHERE S.IsActive = 1;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, ActionDate, Details)
        VALUES
        (
            @UserID,
            N'CustomerDeactivated',
            N'Customer',
            @CustomerID,
            GETDATE(),
            CONCAT(
                N'Customer soft-deactivated; linked users and sessions disabled. Scope=',
                CASE WHEN @IsHighAdminEffective = 1 THEN N'AllBranches' ELSE N'CurrentBranch' END,
                N'; BranchID=', COALESCE(CONVERT(NVARCHAR(20), @CurrentBranchID), N'NULL')
            )
        );

        COMMIT TRANSACTION;
        SELECT @CustomerID AS CustomerID, N'Deactivated' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END CATCH;
END;
GO
