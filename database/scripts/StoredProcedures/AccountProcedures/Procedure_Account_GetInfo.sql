/* =========================================================
   Procedure_Account_GetInfo_HIGHADMIN_FINAL.sql
   sp_Account_GetInfo
   ---------------------------------------------------------
   PURPOSE:
   Retrieves account details with final application-level
   authorization for Customer, Employee, Admin, and HighAdmin.

   FINAL ACCESS RULES:
   - Customer:
       Can view only accounts owned by their linked CustomerID.
       Customer can pass no filters to list own accounts.

   - Active Employee:
       Can view accounts globally.

   - Effective Admin:
       Can view accounts globally.

   - HighAdmin:
       Can view every account globally, including accounts owned
       by every customer/employee/manager/HighAdmin.

   IMPORTANT:
   - @UserID is the authenticated application user.
   - @CustomerID is only a filter. It is not trusted for Customer
     authorization.
   - MonthlyFee is intentionally ignored.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Account_GetInfo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_GetInfo;
GO

CREATE PROCEDURE dbo.sp_Account_GetInfo
(
    @UserID        INT,
    @AccountID     INT = NULL,
    @AccountNumber NVARCHAR(30) = NULL,
    @CustomerID    INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CallerCustomerID INT,
        @CallerEmployeeID INT,
        @EmployeeStatus NVARCHAR(20),
        @JobTitle NVARCHAR(100),
        @CanAccessAdmin BIT,
        @HasCustomer BIT,
        @HasEmployee BIT,
        @HasAdmin BIT,
        @HasHighAdmin BIT,
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
    SET @AccessMode = N'None';

    ------------------------------------------------------------
    -- 1. Resolve active application user.
    ------------------------------------------------------------
    SELECT
        @CallerCustomerID = U.CustomerID,
        @CallerEmployeeID = U.EmployeeID
    FROM dbo.Users AS U
    WHERE U.UserID = @UserID
      AND U.IsActive = 1;

    IF @CallerCustomerID IS NULL
    BEGIN
        RAISERROR('Invalid or inactive user, or user has no CustomerID.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Customer AS C
        WHERE C.CustomerID = @CallerCustomerID
          AND C.IsActive = 1
    )
    BEGIN
        RAISERROR('Linked customer profile is inactive or missing.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 2. Resolve raw application roles.
    ------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Customer') SET @HasCustomer = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Employee') SET @HasEmployee = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'Admin') SET @HasAdmin = 1;
    IF EXISTS (SELECT 1 FROM dbo.UserRoles UR INNER JOIN dbo.Roles R ON R.RoleID = UR.RoleID WHERE UR.UserID = @UserID AND R.RoleName = N'HighAdmin') SET @HasHighAdmin = 1;

    IF @HasCustomer = 0
    BEGIN
        RAISERROR('User must have Customer role.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- 3. Calculate effective HighAdmin / Employee / Admin access.
    ------------------------------------------------------------
    IF @HasHighAdmin = 1
    BEGIN
        IF @CallerEmployeeID IS NOT NULL OR @HasEmployee = 1 OR @HasAdmin = 1
        BEGIN
            RAISERROR('Invalid HighAdmin configuration.', 16, 1);
            RETURN;
        END;

        SET @IsHighAdminEffective = 1;
        SET @AccessMode = N'HighAdminAllAccounts';
    END;

    IF @CallerEmployeeID IS NOT NULL
    BEGIN
        SELECT
            @EmployeeStatus = E.EmpStatus,
            @JobTitle = E.JobTitle,
            @CanAccessAdmin = E.CanAccessAdmin
        FROM dbo.Employee AS E
        WHERE E.EmployeeID = @CallerEmployeeID;

        IF @HasEmployee = 1 AND @EmployeeStatus = N'Active'
            SET @IsEmployeeEffective = 1;

        IF @HasAdmin = 1
           AND @EmployeeStatus = N'Active'
           AND @CanAccessAdmin = 1
           AND @JobTitle IN (N'Branch Manager', N'Vice Manager')
            SET @IsAdminEffective = 1;
    END;

    IF @IsHighAdminEffective = 0 AND (@IsEmployeeEffective = 1 OR @IsAdminEffective = 1)
        SET @AccessMode = N'EmployeeOrAdminAllAccounts';

    ------------------------------------------------------------
    -- 4. Customer-only users are restricted to their own accounts.
    ------------------------------------------------------------
    IF @IsHighAdminEffective = 0
       AND @IsEmployeeEffective = 0
       AND @IsAdminEffective = 0
    BEGIN
        IF @HasCustomer = 0
        BEGIN
            RAISERROR('User does not have permission to view account information.', 16, 1);
            RETURN;
        END;

        IF @CustomerID IS NOT NULL AND @CustomerID <> @CallerCustomerID
        BEGIN
            RAISERROR('Customer users can view only their own account information.', 16, 1);
            RETURN;
        END;

        SET @CustomerID = @CallerCustomerID;
        SET @AccessMode = N'CustomerOwnAccounts';
    END;

    IF @IsHighAdminEffective = 0
       AND @IsEmployeeEffective = 0
       AND @IsAdminEffective = 0
    BEGIN
        IF @HasCustomer = 0
        BEGIN
            RAISERROR(
                'User does not have permission to view account information.',
                16,
                1
            );
            RETURN;
        END;

        IF @CustomerID IS NOT NULL
           AND @CustomerID <> @CallerCustomerID
        BEGIN
            RAISERROR(
                'Customer users can view only their own account information.',
                16,
                1
            );
            RETURN;
        END;

        IF @AccountID IS NOT NULL
           AND EXISTS
           (
               SELECT 1
               FROM dbo.Account
               WHERE AccountID = @AccountID
                 AND CustomerID <> @CallerCustomerID
           )
        BEGIN
            RAISERROR(
                'Customer users can view only their own account information.',
                16,
                1
            );
            RETURN;
        END;

        IF @AccountNumber IS NOT NULL
           AND EXISTS
           (
               SELECT 1
               FROM dbo.Account
               WHERE AccountNumber = LTRIM(RTRIM(@AccountNumber))
                 AND CustomerID <> @CallerCustomerID
           )
        BEGIN
            RAISERROR(
                'Customer users can view only their own account information.',
                16,
                1
            );
            RETURN;
        END;

        SET @CustomerID = @CallerCustomerID;
        SET @AccessMode = N'CustomerOwnAccounts';
    END;

    ------------------------------------------------------------
    -- 5. Return authorized account details.
    --    Interest is excluded from LastCustomerActivityAt.
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
        A.FrozenPreviousStatus,
        LastAct.LastCustomerActivityAt
    FROM dbo.Account AS A
    INNER JOIN dbo.Customer AS C
        ON C.CustomerID = A.CustomerID
    INNER JOIN dbo.Branch AS B
        ON B.BranchID = A.BranchID
    INNER JOIN dbo.AccountType AS AT
        ON AT.AccountTypeID = A.AccountTypeID
    LEFT JOIN dbo.vw_AccountPendingOutgoing AS P
        ON P.AccountID = A.AccountID
    OUTER APPLY
    (
        SELECT MAX(COALESCE(TR.CompletedAt, TR.TransactionDate)) AS LastCustomerActivityAt
        FROM dbo.Transactions AS TR
        INNER JOIN dbo.TransactionType AS TT
            ON TT.TransactionTypeID = TR.TransactionTypeID
        WHERE TR.TransactionStatus = N'Completed'
          AND TT.TypeName IN (N'Deposit', N'Withdrawal', N'Transfer')
          AND (TR.FromAccountID = A.AccountID OR TR.ToAccountID = A.AccountID)
    ) AS LastAct
    WHERE (@AccountID IS NULL OR A.AccountID = @AccountID)
      AND (@AccountNumber IS NULL OR A.AccountNumber = LTRIM(RTRIM(@AccountNumber)))
      AND (@CustomerID IS NULL OR A.CustomerID = @CustomerID)
    ORDER BY A.AccountID;

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
        N'ACCOUNT_VIEW',
        N'Account',
        @AccountID,
        GETDATE(),
        CONCAT(
            'AccountID=', ISNULL(CONVERT(NVARCHAR(30), @AccountID), N'NULL'),
            '; AccountNumber=', ISNULL(@AccountNumber, N'NULL'),
            '; CustomerFilter=', ISNULL(CONVERT(NVARCHAR(30), @CustomerID), N'NULL'),
            '; AccessMode=', @AccessMode
        )
    );
END;
GO
