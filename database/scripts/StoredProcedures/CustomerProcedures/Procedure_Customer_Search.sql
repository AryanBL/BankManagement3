/* =========================================================
   Procedure_Customer_Search_BRANCH_SCOPED.sql
   sp_Customer_Search / sp_Customer_GetByID
   ---------------------------------------------------------
   BRANCH VISIBILITY MODEL:
   - Effective Employee/Admin: customers who own at least one
     account in the caller's current active branch.
   - Effective HighAdmin: all customers.
   - Customer-only users cannot run the general directory search.
   - Every user may still retrieve their own customer profile.

   Customer-to-branch correspondence is derived through Account,
   because Customer does not contain a BranchID column.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Customer_Search', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_Search;
GO

CREATE PROCEDURE dbo.sp_Customer_Search
(
    @UserID             INT,
    @NameSearch         NVARCHAR(100) = NULL,
    @NationalID         NVARCHAR(20)  = NULL,
    @Phone              NVARCHAR(20)  = NULL,
    @Email              NVARCHAR(100) = NULL,
    @IncludeInactive    BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @RequesterCustomerID INT,
            @RequesterEmployeeID INT,
            @CurrentBranchID INT,
            @IsEmployeeEffective BIT = 0,
            @IsAdminEffective BIT = 0,
            @IsHighAdminEffective BIT = 0;

        IF @UserID IS NULL
        BEGIN
            RAISERROR('UserID is required for customer search.', 16, 1);
            RETURN;
        END;

        SELECT
            @RequesterCustomerID = U.CustomerID,
            @RequesterEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        INNER JOIN dbo.Customer AS C
            ON C.CustomerID = U.CustomerID
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND C.IsActive = 1;

        IF @RequesterCustomerID IS NULL
           OR dbo.fn_UserHasEffectiveRole(@UserID, N'Customer') = 0
        BEGIN
            RAISERROR('A valid authenticated user with an active customer profile is required.', 16, 1);
            RETURN;
        END;

        SET @IsEmployeeEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Employee');
        SET @IsAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Admin');
        SET @IsHighAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin');

        IF @IsHighAdminEffective = 0
           AND @IsEmployeeEffective = 0
           AND @IsAdminEffective = 0
        BEGIN
            RAISERROR('Customer search requires effective Employee, Admin, or HighAdmin privilege.', 16, 1);
            RETURN;
        END;

        IF @IsHighAdminEffective = 0
        BEGIN
            SELECT TOP (1)
                @CurrentBranchID = EB.BranchID
            FROM dbo.EMPB AS EB
            WHERE EB.EmployeeID = @RequesterEmployeeID
              AND EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
            ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

            IF @CurrentBranchID IS NULL
            BEGIN
                RAISERROR('The current employee does not have an active branch assignment.', 16, 1);
                RETURN;
            END;
        END;

        DECLARE
            @CleanNameSearch NVARCHAR(100),
            @CleanNationalID NVARCHAR(20),
            @CleanPhone NVARCHAR(20),
            @CleanEmail NVARCHAR(100),
            @NamePattern NVARCHAR(310);

        SET @CleanNameSearch = NULLIF(LTRIM(RTRIM(@NameSearch)), N'');
        SET @CleanNationalID = NULLIF(LTRIM(RTRIM(@NationalID)), N'');
        SET @CleanPhone = NULLIF(LTRIM(RTRIM(@Phone)), N'');
        SET @CleanEmail = NULLIF(LTRIM(RTRIM(@Email)), N'');

        IF @CleanNameSearch IS NOT NULL
        BEGIN
            SET @NamePattern = N'%' +
                REPLACE(
                    REPLACE(
                        REPLACE(@CleanNameSearch, N'[', N'[[]'),
                    N'%', N'[%]'),
                N'_', N'[_]') + N'%';
        END;

        INSERT INTO dbo.AuditLog
        (
            UserID, ActionType, TableName, RecordID, ActionDate, Details
        )
        VALUES
        (
            @UserID,
            N'CustomerSearch',
            N'Customer',
            NULL,
            GETDATE(),
            CONCAT(
                N'Customer search executed. Scope=',
                CASE WHEN @IsHighAdminEffective = 1 THEN N'AllBranches' ELSE N'CurrentBranch' END,
                N'; BranchID=', COALESCE(CONVERT(NVARCHAR(20), @CurrentBranchID), N'NULL'),
                N'; IncludeInactive=', @IncludeInactive
            )
        );

        SELECT
            C.CustomerID,
            C.FirstName,
            C.LastName,
            C.NationalID,
            C.BirthDate,
            C.Phone,
            C.Email,
            C.Address,
            C.RegistrationDate,
            C.IsActive
        FROM dbo.Customer AS C
        WHERE (@IncludeInactive = 1 OR C.IsActive = 1)
          AND (@CleanNameSearch IS NULL OR C.FirstName LIKE @NamePattern OR C.LastName LIKE @NamePattern)
          AND (@CleanNationalID IS NULL OR C.NationalID = @CleanNationalID)
          AND (@CleanPhone IS NULL OR C.Phone = @CleanPhone)
          AND (@CleanEmail IS NULL OR C.Email = @CleanEmail)
          AND
          (
              @IsHighAdminEffective = 1
              OR EXISTS
              (
                  SELECT 1
                  FROM dbo.Account AS A
                  WHERE A.CustomerID = C.CustomerID
                    AND A.BranchID = @CurrentBranchID
              )
          )
        ORDER BY C.RegistrationDate DESC, C.CustomerID DESC;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;
END;
GO

IF OBJECT_ID('dbo.sp_Customer_GetByID', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_GetByID;
GO

CREATE PROCEDURE dbo.sp_Customer_GetByID
(
    @UserID INT,
    @CustomerID INT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @RequesterCustomerID INT,
            @RequesterEmployeeID INT,
            @CurrentBranchID INT,
            @IsEmployeeEffective BIT = 0,
            @IsAdminEffective BIT = 0,
            @IsHighAdminEffective BIT = 0;

        IF @UserID IS NULL OR @CustomerID IS NULL
        BEGIN
            RAISERROR('UserID and CustomerID are required.', 16, 1);
            RETURN;
        END;

        SELECT
            @RequesterCustomerID = U.CustomerID,
            @RequesterEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        INNER JOIN dbo.Customer AS C
            ON C.CustomerID = U.CustomerID
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND C.IsActive = 1;

        IF @RequesterCustomerID IS NULL
           OR dbo.fn_UserHasEffectiveRole(@UserID, N'Customer') = 0
        BEGIN
            RAISERROR('A valid authenticated user with an active customer profile is required.', 16, 1);
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE CustomerID = @CustomerID)
        BEGIN
            RAISERROR('Target customer does not exist.', 16, 1);
            RETURN;
        END;

        SET @IsEmployeeEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Employee');
        SET @IsAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'Admin');
        SET @IsHighAdminEffective = dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin');

        IF @CustomerID <> @RequesterCustomerID
           AND @IsHighAdminEffective = 0
        BEGIN
            IF @IsEmployeeEffective = 0 AND @IsAdminEffective = 0
            BEGIN
                RAISERROR('Customer users can view only their own customer record.', 16, 1);
                RETURN;
            END;

            SELECT TOP (1)
                @CurrentBranchID = EB.BranchID
            FROM dbo.EMPB AS EB
            WHERE EB.EmployeeID = @RequesterEmployeeID
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
                RAISERROR('Employees and managers can view only customers corresponding to their current branch.', 16, 1);
                RETURN;
            END;
        END;

        INSERT INTO dbo.AuditLog
        (
            UserID, ActionType, TableName, RecordID, ActionDate, Details
        )
        VALUES
        (
            @UserID,
            N'CustomerViewed',
            N'Customer',
            @CustomerID,
            GETDATE(),
            CONCAT(
                N'Customer lookup executed. OwnRecord=',
                CASE WHEN @CustomerID = @RequesterCustomerID THEN N'1' ELSE N'0' END,
                N'; Scope=',
                CASE
                    WHEN @CustomerID = @RequesterCustomerID THEN N'OwnProfile'
                    WHEN @IsHighAdminEffective = 1 THEN N'AllBranches'
                    ELSE N'CurrentBranch'
                END,
                N'; BranchID=', COALESCE(CONVERT(NVARCHAR(20), @CurrentBranchID), N'NULL')
            )
        );

        SELECT
            C.CustomerID,
            C.FirstName,
            C.LastName,
            C.NationalID,
            C.BirthDate,
            C.Phone,
            C.Email,
            C.Address,
            C.RegistrationDate,
            C.IsActive
        FROM dbo.Customer AS C
        WHERE C.CustomerID = @CustomerID;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;
END;
GO
