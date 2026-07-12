/* =========================================================
   Procedure_Customer_Update_BRANCH_SCOPED.sql
   sp_Customer_Update
   ---------------------------------------------------------
   AUTHORIZATION:
   - Customer can update only their own Customer record.
   - Effective Employee/Admin can update only customers who own
     at least one account in the caller's current branch.
   - Effective HighAdmin can update any customer.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Customer_Update', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_Update;
GO

CREATE PROCEDURE dbo.sp_Customer_Update
(
    @CustomerID     INT,
    @FirstName      NVARCHAR(50),
    @LastName       NVARCHAR(50),
    @Phone          NVARCHAR(20),
    @Email          NVARCHAR(100),
    @Address        NVARCHAR(200) = NULL,
    @UserID         INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @CallerCustomerID INT,
            @CallerEmployeeID INT,
            @CurrentBranchID INT,
            @IsEmployeeEffective BIT = 0,
            @IsAdminEffective BIT = 0,
            @IsHighAdminEffective BIT = 0;

        SELECT
            @CallerCustomerID = U.CustomerID,
            @CallerEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        INNER JOIN dbo.Customer AS C ON C.CustomerID = U.CustomerID
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND C.IsActive = 1;

        IF @UserID IS NULL
           OR @CallerCustomerID IS NULL
           OR dbo.fn_UserHasEffectiveRole(@UserID, N'Customer') = 0
        BEGIN
            RAISERROR('A valid authenticated user is required.', 16, 1);
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID AND IsActive = 1)
        BEGIN
            RAISERROR('Customer does not exist or is not active.', 16, 1);
            RETURN;
        END;

        SET @IsEmployeeEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Employee');
        SET @IsAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Admin');
        SET @IsHighAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin');

        IF @CustomerID <> @CallerCustomerID
           AND @IsHighAdminEffective = 0
        BEGIN
            IF @IsEmployeeEffective = 0 AND @IsAdminEffective = 0
            BEGIN
                RAISERROR('Customer users can update only their own customer record.', 16, 1);
                RETURN;
            END;

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
                RAISERROR('Employees and managers can update only customers corresponding to their current branch.', 16, 1);
                RETURN;
            END;
        END;

        IF @FirstName IS NULL OR LEN(LTRIM(RTRIM(@FirstName))) = 0
        BEGIN RAISERROR('First name is required.', 16, 1); RETURN; END;
        IF @LastName IS NULL OR LEN(LTRIM(RTRIM(@LastName))) = 0
        BEGIN RAISERROR('Last name is required.', 16, 1); RETURN; END;
        IF @Phone IS NULL OR LEN(LTRIM(RTRIM(@Phone))) = 0
        BEGIN RAISERROR('Phone number is required.', 16, 1); RETURN; END;
        IF @Email IS NULL OR LEN(LTRIM(RTRIM(@Email))) = 0
        BEGIN RAISERROR('Email is required.', 16, 1); RETURN; END;

        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Customer WHERE Phone = @Phone AND CustomerID <> @CustomerID)
        BEGIN RAISERROR('Another customer already uses this phone number.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS (SELECT 1 FROM dbo.Customer WHERE Email = @Email AND CustomerID <> @CustomerID)
        BEGIN RAISERROR('Another customer already uses this email.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        UPDATE dbo.Customer
        SET FirstName = LTRIM(RTRIM(@FirstName)),
            LastName  = LTRIM(RTRIM(@LastName)),
            Phone     = LTRIM(RTRIM(@Phone)),
            Email     = LTRIM(RTRIM(@Email)),
            Address   = @Address
        WHERE CustomerID = @CustomerID;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, ActionDate, Details)
        VALUES
        (
            @UserID,
            N'CustomerUpdated',
            N'Customer',
            @CustomerID,
            GETDATE(),
            CONCAT(
                N'Customer contact details updated. Scope=',
                CASE
                    WHEN @CustomerID = @CallerCustomerID THEN N'OwnProfile'
                    WHEN @IsHighAdminEffective = 1 THEN N'AllBranches'
                    ELSE N'CurrentBranch'
                END,
                N'; BranchID=', COALESCE(CONVERT(NVARCHAR(20), @CurrentBranchID), N'NULL')
            )
        );

        COMMIT TRANSACTION;
        SELECT @CustomerID AS CustomerID, N'Updated' AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END CATCH;
END;
GO
