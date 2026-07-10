/* =========================================================
   Procedure_Account_Search_AUTHORIZED_FINAL.sql
   sp_Account_Search
   ---------------------------------------------------------
   PURPOSE:
   Authorized account search module for the Bank Management
   system.

   FINAL SECURITY MODEL:
   1. Every caller must pass the authenticated @UserID.
   2. Users.IsActive controls whole application login access.
   3. Every login user must have Customer role and an active
      linked Customer record.
   4. Employee/Admin privileges are effective only when the
      linked Employee row has EmpStatus = 'Active'.
   5. Admin is effective only for Branch Manager / Vice Manager
      with CanAccessAdmin = 1.
   6. HighAdmin is effective only when the user has HighAdmin
      role and EmployeeID IS NULL.

   PRIVILEGES:
   - Customer-only users may search only their own accounts.
   - Effective Employee/Admin/HighAdmin users may search all
     accounts globally.
   - Fired/suspended employees can still search only their own
     customer accounts because Employee/Admin is not effective.

   NOTES:
   - No dynamic SQL is used.
   - Partial text searches escape %, _, and [ as literal text.
   - This complements sp_Account_GetInfo; it does not replace it.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Account_Search', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_Search;
GO

CREATE PROCEDURE dbo.sp_Account_Search
(
    @UserID                 INT,
    @AccountID              INT = NULL,
    @AccountNumber          NVARCHAR(30) = NULL,   -- exact match
    @AccountNumberSearch    NVARCHAR(30) = NULL,   -- partial literal search
    @CustomerID             INT = NULL,
    @CustomerNationalID     NVARCHAR(20) = NULL,
    @CustomerNameSearch     NVARCHAR(100) = NULL,
    @BranchID               INT = NULL,
    @BranchCode             NVARCHAR(20) = NULL,
    @AccountTypeID          INT = NULL,
    @AccountTypeName        NVARCHAR(50) = NULL,
    @AccountStatus          NVARCHAR(20) = NULL,   -- Active, Closed, Frozen, Dormant
    @MinBalance             DECIMAL(18,2) = NULL,
    @MaxBalance             DECIMAL(18,2) = NULL,
    @IncludeClosed          BIT = 0
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
            @IsHighAdminEffective BIT,
            @AccessMode NVARCHAR(50);

        SET @HasCustomer = 0;
        SET @HasEmployee = 0;
        SET @HasAdmin = 0;
        SET @HasHighAdmin = 0;
        SET @IsEmployeeEffective = 0;
        SET @IsAdminEffective = 0;
        SET @IsHighAdminEffective = 0;
        SET @CanAccessAdmin = 0;
        SET @AccessMode = N'None';

        IF @UserID IS NULL
        BEGIN
            RAISERROR('UserID is required for account search.', 16, 1);
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

        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Customer') SET @HasCustomer = 1;
        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Employee') SET @HasEmployee = 1;
        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Admin') SET @HasAdmin = 1;
        IF EXISTS (SELECT 1 FROM dbo.UserRoles AS UR INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'HighAdmin') SET @HasHighAdmin = 1;

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

        IF @IsHighAdminEffective = 1
            SET @AccessMode = N'HighAdminAllAccounts';
        ELSE IF @IsEmployeeEffective = 1 OR @IsAdminEffective = 1
            SET @AccessMode = N'EmployeeOrAdminAllAccounts';
        ELSE
            SET @AccessMode = N'CustomerOwnAccounts';

        ------------------------------------------------------------
        -- 2. Validate and clean filters.
        ------------------------------------------------------------
        DECLARE
            @CleanAccountNumber NVARCHAR(30),
            @CleanAccountNumberSearch NVARCHAR(30),
            @CleanCustomerNationalID NVARCHAR(20),
            @CleanCustomerNameSearch NVARCHAR(100),
            @CleanBranchCode NVARCHAR(20),
            @CleanAccountTypeName NVARCHAR(50),
            @CleanAccountStatus NVARCHAR(20),
            @AccountNumberPattern NVARCHAR(110),
            @CustomerNamePattern NVARCHAR(310);

        SET @CleanAccountNumber = NULLIF(LTRIM(RTRIM(@AccountNumber)), N'');
        SET @CleanAccountNumberSearch = NULLIF(LTRIM(RTRIM(@AccountNumberSearch)), N'');
        SET @CleanCustomerNationalID = NULLIF(LTRIM(RTRIM(@CustomerNationalID)), N'');
        SET @CleanCustomerNameSearch = NULLIF(LTRIM(RTRIM(@CustomerNameSearch)), N'');
        SET @CleanBranchCode = NULLIF(LTRIM(RTRIM(@BranchCode)), N'');
        SET @CleanAccountTypeName = NULLIF(LTRIM(RTRIM(@AccountTypeName)), N'');
        SET @CleanAccountStatus = NULLIF(LTRIM(RTRIM(@AccountStatus)), N'');

        IF @CleanAccountStatus IS NOT NULL
           AND @CleanAccountStatus NOT IN (N'Active', N'Closed', N'Frozen', N'Dormant')
        BEGIN
            RAISERROR('Invalid AccountStatus. Allowed values: Active, Closed, Frozen, Dormant.', 16, 1);
            RETURN;
        END;

        IF @MinBalance IS NOT NULL AND @MaxBalance IS NOT NULL AND @MinBalance > @MaxBalance
        BEGIN
            RAISERROR('MinBalance cannot be greater than MaxBalance.', 16, 1);
            RETURN;
        END;

        IF @CleanAccountNumberSearch IS NOT NULL
        BEGIN
            SET @AccountNumberPattern = N'%' +
                REPLACE(
                    REPLACE(
                        REPLACE(@CleanAccountNumberSearch, N'[', N'[[]'),
                    N'%', N'[%]'),
                N'_', N'[_]') + N'%';
        END;

        IF @CleanCustomerNameSearch IS NOT NULL
        BEGIN
            SET @CustomerNamePattern = N'%' +
                REPLACE(
                    REPLACE(
                        REPLACE(@CleanCustomerNameSearch, N'[', N'[[]'),
                    N'%', N'[%]'),
                N'_', N'[_]') + N'%';
        END;

        ------------------------------------------------------------
        -- 3. Customer-only restriction.
        ------------------------------------------------------------
        IF @IsHighAdminEffective = 0
           AND @IsEmployeeEffective = 0
           AND @IsAdminEffective = 0
        BEGIN
            IF @CustomerID IS NOT NULL AND @CustomerID <> @RequesterCustomerID
            BEGIN
                RAISERROR('Customer users can search only their own accounts.', 16, 1);
                RETURN;
            END;

            SET @CustomerID = @RequesterCustomerID;
        END;

        ------------------------------------------------------------
        -- 4. Audit successful authorized search attempt.
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
            N'AccountSearch',
            N'Account',
            NULL,
            GETDATE(),
            CONCAT(
                N'Account search executed. AccessMode=', @AccessMode,
                N'; AccountID=', ISNULL(CONVERT(NVARCHAR(30), @AccountID), N'NULL'),
                N'; CustomerID=', ISNULL(CONVERT(NVARCHAR(30), @CustomerID), N'NULL'),
                N'; BranchID=', ISNULL(CONVERT(NVARCHAR(30), @BranchID), N'NULL'),
                N'; AccountStatus=', ISNULL(@CleanAccountStatus, N'NULL'),
                N'; IncludeClosed=', @IncludeClosed
            )
        );

        ------------------------------------------------------------
        -- 5. Return matching account records.
        ------------------------------------------------------------
        SELECT
            A.AccountID,
            A.AccountNumber,
            A.CustomerID,
            C.FirstName AS CustomerFirstName,
            C.LastName AS CustomerLastName,
            C.NationalID AS CustomerNationalID,
            C.Phone AS CustomerPhone,
            C.Email AS CustomerEmail,
            A.BranchID,
            B.BranchName,
            B.BranchCode,
            B.City AS BranchCity,
            A.AccountTypeID,
            AT.TypeName AS AccountTypeName,
            AT.MinBalance,
            AT.InterestRate,
            A.Balance,
            ISNULL(P.PendingOutgoingAmount, 0) AS PendingOutgoingAmount,
            A.Balance - ISNULL(P.PendingOutgoingAmount, 0) AS AvailableBalance,
            A.OpenDate,
            A.CloseDate,
            A.AccountStatus,
            A.FrozenPreviousStatus
        FROM dbo.Account AS A
        INNER JOIN dbo.Customer AS C
            ON C.CustomerID = A.CustomerID
        INNER JOIN dbo.Branch AS B
            ON B.BranchID = A.BranchID
        INNER JOIN dbo.AccountType AS AT
            ON AT.AccountTypeID = A.AccountTypeID
        LEFT JOIN dbo.vw_AccountPendingOutgoing AS P
            ON P.AccountID = A.AccountID
        WHERE (@AccountID IS NULL OR A.AccountID = @AccountID)
          AND (@CleanAccountNumber IS NULL OR A.AccountNumber = @CleanAccountNumber)
          AND (@CleanAccountNumberSearch IS NULL OR A.AccountNumber LIKE @AccountNumberPattern)
          AND (@CustomerID IS NULL OR A.CustomerID = @CustomerID)
          AND (@CleanCustomerNationalID IS NULL OR C.NationalID = @CleanCustomerNationalID)
          AND (@CleanCustomerNameSearch IS NULL OR C.FirstName LIKE @CustomerNamePattern OR C.LastName LIKE @CustomerNamePattern)
          AND (@BranchID IS NULL OR A.BranchID = @BranchID)
          AND (@CleanBranchCode IS NULL OR B.BranchCode = @CleanBranchCode)
          AND (@AccountTypeID IS NULL OR A.AccountTypeID = @AccountTypeID)
          AND (@CleanAccountTypeName IS NULL OR AT.TypeName = @CleanAccountTypeName)
          AND (@CleanAccountStatus IS NULL OR A.AccountStatus = @CleanAccountStatus)
          AND (@CleanAccountStatus IS NOT NULL OR @IncludeClosed = 1 OR A.AccountStatus <> N'Closed')
          AND (@MinBalance IS NULL OR A.Balance >= @MinBalance)
          AND (@MaxBalance IS NULL OR A.Balance <= @MaxBalance)
        ORDER BY A.AccountID;
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
