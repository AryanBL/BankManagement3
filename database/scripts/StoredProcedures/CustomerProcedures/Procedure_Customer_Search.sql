/* =========================================================
   Procedure_Customer_Search_AUTHORIZED_FINAL.sql
   sp_Customer_Search / sp_Customer_GetByID
   ---------------------------------------------------------
   PURPOSE:
   Final authorized customer lookup module for the Bank
   Management system.

   FINAL SECURITY MODEL:
   1. Every caller must pass the authenticated @UserID.
   2. Users.IsActive controls whether the login account may use
      the application.
   3. Every login user must have Customer role and an active
      linked Customer record.
   4. Employee/Admin privileges are effective only when the linked
      Employee row has EmpStatus = 'Active'.
   5. Admin is effective only for Branch Manager / Vice Manager
      with CanAccessAdmin = 1.
   6. HighAdmin is effective only when the user has HighAdmin role
      and EmployeeID IS NULL.

   PRIVILEGES:
   - sp_Customer_Search:
       Effective Employee, Admin, or HighAdmin may search all
       customer records.
       Customer-only users cannot perform general customer search.

   - sp_Customer_GetByID:
       Customer-only users may view only their own Customer record.
       Effective Employee, Admin, or HighAdmin may view any customer.

   NOTES:
   - This procedure uses parameterized predicates only.
   - No dynamic SQL is used.
   - Name search treats %, _, and [ as literal text, not wildcards.
   - Run this file instead of the old Procedure_Customer_Search.sql.

   REQUIREMENTS:
   - dbo.Users with IsActive
   - dbo.Customer with IsActive
   - dbo.Employee
   - dbo.Roles
   - dbo.UserRoles
   - dbo.AuditLog
   ========================================================= */

IF OBJECT_ID('dbo.sp_Customer_Search', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Customer_Search;
GO

CREATE PROCEDURE dbo.sp_Customer_Search
(
    @UserID             INT,
    @NameSearch         NVARCHAR(100) = NULL,   -- matches FirstName or LastName, partial literal search
    @NationalID         NVARCHAR(20)  = NULL,   -- exact match
    @Phone              NVARCHAR(20)  = NULL,   -- exact match
    @Email              NVARCHAR(100) = NULL,   -- exact match
    @IncludeInactive    BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------
        -- 1. Validate caller identity and calculate effective roles.
        ------------------------------------------------------------
        DECLARE
            @RequesterCustomerID INT,
            @RequesterEmployeeID INT,
            @HasCustomer BIT,
            @HasEmployee BIT,
            @HasAdmin BIT,
            @HasHighAdmin BIT,
            @EmployeeStatus NVARCHAR(20),
            @JobTitle NVARCHAR(100),
            @CanAccessAdmin BIT,
            @IsEmployeeEffective BIT,
            @IsAdminEffective BIT,
            @IsHighAdminEffective BIT;

        SET @HasCustomer = 0;
        SET @HasEmployee = 0;
        SET @HasAdmin = 0;
        SET @HasHighAdmin = 0;
        SET @IsEmployeeEffective = 0;
        SET @IsAdminEffective = 0;
        SET @IsHighAdminEffective = 0;
        SET @CanAccessAdmin = 0;

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
        BEGIN
            RAISERROR('Invalid caller: user account is inactive, missing, or not linked to an active customer profile.', 16, 1);
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Customer'
        )
            SET @HasCustomer = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Employee'
        )
            SET @HasEmployee = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Admin'
        )
            SET @HasAdmin = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'HighAdmin'
        )
            SET @HasHighAdmin = 1;

        IF @HasCustomer = 0
        BEGIN
            RAISERROR('Invalid caller: user must have Customer role.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND @RequesterEmployeeID IS NOT NULL
        BEGIN
            RAISERROR('Invalid caller: HighAdmin user must not be linked to an EmployeeID.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND (@HasEmployee = 1 OR @HasAdmin = 1)
        BEGIN
            RAISERROR('Invalid caller: HighAdmin role cannot be combined with Employee or Admin roles.', 16, 1);
            RETURN;
        END;

        IF @RequesterEmployeeID IS NOT NULL
        BEGIN
            SELECT
                @EmployeeStatus = E.EmpStatus,
                @JobTitle = E.JobTitle,
                @CanAccessAdmin = E.CanAccessAdmin
            FROM dbo.Employee AS E
            WHERE E.EmployeeID = @RequesterEmployeeID;
        END;

        IF @HasEmployee = 1
           AND @RequesterEmployeeID IS NOT NULL
           AND @EmployeeStatus = N'Active'
            SET @IsEmployeeEffective = 1;

        IF @HasAdmin = 1
           AND @IsEmployeeEffective = 1
           AND @CanAccessAdmin = 1
           AND @JobTitle IN (N'Branch Manager', N'Vice Manager')
            SET @IsAdminEffective = 1;

        IF @HasHighAdmin = 1
           AND @RequesterEmployeeID IS NULL
            SET @IsHighAdminEffective = 1;

        IF @IsEmployeeEffective = 0
           AND @IsAdminEffective = 0
           AND @IsHighAdminEffective = 0
        BEGIN
            RAISERROR('Customer search requires effective Employee, Admin, or HighAdmin privilege.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 2. Clean search inputs.
        ------------------------------------------------------------
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
            -- Treat LIKE wildcards as literal text.
            SET @NamePattern = N'%' +
                REPLACE(
                    REPLACE(
                        REPLACE(@CleanNameSearch, N'[', N'[[]'),
                    N'%', N'[%]'),
                N'_', N'[_]') + N'%';
        END;

        ------------------------------------------------------------
        -- 3. Audit successful authorized search attempt.
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
            @UserID,
            N'CustomerSearch',
            N'Customer',
            NULL,
            GETDATE(),
            CONCAT(
                N'Customer search executed. IncludeInactive=', @IncludeInactive,
                N'; NameSearchProvided=', CASE WHEN @CleanNameSearch IS NULL THEN N'0' ELSE N'1' END,
                N'; NationalIDProvided=', CASE WHEN @CleanNationalID IS NULL THEN N'0' ELSE N'1' END,
                N'; PhoneProvided=', CASE WHEN @CleanPhone IS NULL THEN N'0' ELSE N'1' END,
                N'; EmailProvided=', CASE WHEN @CleanEmail IS NULL THEN N'0' ELSE N'1' END,
                N'; EmployeeEffective=', @IsEmployeeEffective,
                N'; AdminEffective=', @IsAdminEffective,
                N'; HighAdminEffective=', @IsHighAdminEffective
            )
        );

        ------------------------------------------------------------
        -- 4. Return matching customer records.
        ------------------------------------------------------------
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
        ORDER BY C.LastName, C.FirstName, C.CustomerID;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;

        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorSeverity = ERROR_SEVERITY();
        SET @ErrorState = ERROR_STATE();

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
        ------------------------------------------------------------
        -- 1. Validate caller identity and calculate effective roles.
        ------------------------------------------------------------
        DECLARE
            @RequesterCustomerID INT,
            @RequesterEmployeeID INT,
            @HasCustomer BIT,
            @HasEmployee BIT,
            @HasAdmin BIT,
            @HasHighAdmin BIT,
            @EmployeeStatus NVARCHAR(20),
            @JobTitle NVARCHAR(100),
            @CanAccessAdmin BIT,
            @IsEmployeeEffective BIT,
            @IsAdminEffective BIT,
            @IsHighAdminEffective BIT;

        SET @HasCustomer = 0;
        SET @HasEmployee = 0;
        SET @HasAdmin = 0;
        SET @HasHighAdmin = 0;
        SET @IsEmployeeEffective = 0;
        SET @IsAdminEffective = 0;
        SET @IsHighAdminEffective = 0;
        SET @CanAccessAdmin = 0;

        IF @UserID IS NULL
        BEGIN
            RAISERROR('UserID is required for customer lookup.', 16, 1);
            RETURN;
        END;

        IF @CustomerID IS NULL
        BEGIN
            RAISERROR('CustomerID is required.', 16, 1);
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
        BEGIN
            RAISERROR('Invalid caller: user account is inactive, missing, or not linked to an active customer profile.', 16, 1);
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Customer'
        )
            SET @HasCustomer = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Employee'
        )
            SET @HasEmployee = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Admin'
        )
            SET @HasAdmin = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'HighAdmin'
        )
            SET @HasHighAdmin = 1;

        IF @HasCustomer = 0
        BEGIN
            RAISERROR('Invalid caller: user must have Customer role.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND @RequesterEmployeeID IS NOT NULL
        BEGIN
            RAISERROR('Invalid caller: HighAdmin user must not be linked to an EmployeeID.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND (@HasEmployee = 1 OR @HasAdmin = 1)
        BEGIN
            RAISERROR('Invalid caller: HighAdmin role cannot be combined with Employee or Admin roles.', 16, 1);
            RETURN;
        END;

        IF @RequesterEmployeeID IS NOT NULL
        BEGIN
            SELECT
                @EmployeeStatus = E.EmpStatus,
                @JobTitle = E.JobTitle,
                @CanAccessAdmin = E.CanAccessAdmin
            FROM dbo.Employee AS E
            WHERE E.EmployeeID = @RequesterEmployeeID;
        END;

        IF @HasEmployee = 1
           AND @RequesterEmployeeID IS NOT NULL
           AND @EmployeeStatus = N'Active'
            SET @IsEmployeeEffective = 1;

        IF @HasAdmin = 1
           AND @IsEmployeeEffective = 1
           AND @CanAccessAdmin = 1
           AND @JobTitle IN (N'Branch Manager', N'Vice Manager')
            SET @IsAdminEffective = 1;

        IF @HasHighAdmin = 1
           AND @RequesterEmployeeID IS NULL
            SET @IsHighAdminEffective = 1;

        ------------------------------------------------------------
        -- 2. Confirm target customer exists.
        ------------------------------------------------------------
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Customer AS C
            WHERE C.CustomerID = @CustomerID
        )
        BEGIN
            RAISERROR('Target customer does not exist.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 3. Authorization.
        --    Customer-only user can view only own customer record.
        --    Effective Employee/Admin/HighAdmin can view any record.
        ------------------------------------------------------------
        IF @CustomerID <> @RequesterCustomerID
           AND @IsEmployeeEffective = 0
           AND @IsAdminEffective = 0
           AND @IsHighAdminEffective = 0
        BEGIN
            RAISERROR('Customer users can view only their own customer record.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 4. Audit successful authorized lookup.
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
            @UserID,
            N'CustomerViewed',
            N'Customer',
            @CustomerID,
            GETDATE(),
            CONCAT(
                N'Customer lookup executed. OwnRecord=', CASE WHEN @CustomerID = @RequesterCustomerID THEN N'1' ELSE N'0' END,
                N'; EmployeeEffective=', @IsEmployeeEffective,
                N'; AdminEffective=', @IsAdminEffective,
                N'; HighAdminEffective=', @IsHighAdminEffective
            )
        );

        ------------------------------------------------------------
        -- 5. Return the customer record.
        ------------------------------------------------------------
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
        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;

        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorSeverity = ERROR_SEVERITY();
        SET @ErrorState = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;
END;
GO
