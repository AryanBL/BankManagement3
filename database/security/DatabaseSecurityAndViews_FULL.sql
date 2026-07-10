/* =========================================================
   01_BankManagement_ReportingViews.sql
   ---------------------------------------------------------
   Creates controlled read-only views for the BankManagement
   database. These views are intended for reporting, audit,
   operational dashboards, and database-level permission grants.

   Run AFTER:
     - TableCreation.sql
     - Schema_CustomerAccessAndBranchLedger.sql
     - Procedure_AccountHistory_FINAL_FIXED.sql is optional;
       this file creates its own reporting views and does not
       depend on account-history procedures.

   Compatibility note:
     This file does NOT use CREATE OR ALTER. It drops and creates
     each view explicitly to avoid compatibility problems.
   ========================================================= */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------
   Helper view: pending outgoing holds per account.
   Re-created here so reporting views are self-contained.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_AccountPendingOutgoing', 'V') IS NOT NULL
    DROP VIEW dbo.vw_AccountPendingOutgoing;
GO

CREATE VIEW dbo.vw_AccountPendingOutgoing
AS
SELECT
    FromAccountID AS AccountID,
    SUM(Amount) AS PendingOutgoingAmount
FROM dbo.Transactions
WHERE TransactionStatus = 'Pending'
  AND FromAccountID IS NOT NULL
GROUP BY FromAccountID;
GO

/* ---------------------------------------------------------
   Customer basic profile: no password/session data. NationalID
   is masked for safer reporting.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_CustomerBasicProfile', 'V') IS NOT NULL
    DROP VIEW dbo.vw_CustomerBasicProfile;
GO

CREATE VIEW dbo.vw_CustomerBasicProfile
AS
SELECT
    C.CustomerID,
    C.FirstName,
    C.LastName,
    (C.FirstName + N' ' + C.LastName) AS FullName,
    CASE
        WHEN C.NationalID IS NULL THEN NULL
        WHEN LEN(C.NationalID) >= 6 THEN LEFT(C.NationalID, 3) + N'****' + RIGHT(C.NationalID, 3)
        ELSE N'****'
    END AS NationalIDMasked,
    C.BirthDate,
    DATEDIFF(YEAR, C.BirthDate, CAST(GETDATE() AS DATE))
      - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, C.BirthDate, CAST(GETDATE() AS DATE)), C.BirthDate) > CAST(GETDATE() AS DATE)
             THEN 1 ELSE 0 END AS Age,
    C.Phone,
    C.Email,
    C.Address,
    C.RegistrationDate,
    C.IsActive
FROM dbo.Customer AS C;
GO

/* ---------------------------------------------------------
   Customer account summary: account-level view for dashboards.
   AvailableBalance subtracts pending outgoing holds.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_CustomerAccountSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_CustomerAccountSummary;
GO

CREATE VIEW dbo.vw_CustomerAccountSummary
AS
SELECT
    C.CustomerID,
    (C.FirstName + N' ' + C.LastName) AS CustomerName,
    A.AccountID,
    A.AccountNumber,
    A.AccountStatus,
    A.OpenDate,
    A.CloseDate,
    B.BranchID,
    B.BranchName,
    B.BranchCode,
    AT.AccountTypeID,
    AT.TypeName AS AccountTypeName,
    AT.MinBalance,
    AT.InterestRate,
    A.Balance,
    ISNULL(P.PendingOutgoingAmount, 0) AS PendingOutgoingAmount,
    A.Balance - ISNULL(P.PendingOutgoingAmount, 0) AS AvailableBalance
FROM dbo.Account AS A
INNER JOIN dbo.Customer AS C ON C.CustomerID = A.CustomerID
INNER JOIN dbo.Branch AS B ON B.BranchID = A.BranchID
INNER JOIN dbo.AccountType AS AT ON AT.AccountTypeID = A.AccountTypeID
LEFT JOIN dbo.vw_AccountPendingOutgoing AS P ON P.AccountID = A.AccountID;
GO

/* ---------------------------------------------------------
   Account operational summary: all accounts with customer,
   branch, account type, status, and available balance.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_AccountOperationalSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_AccountOperationalSummary;
GO

CREATE VIEW dbo.vw_AccountOperationalSummary
AS
SELECT
    A.AccountID,
    A.AccountNumber,
    A.CustomerID,
    (C.FirstName + N' ' + C.LastName) AS CustomerName,
    CASE
        WHEN LEN(C.NationalID) >= 6 THEN LEFT(C.NationalID, 3) + N'****' + RIGHT(C.NationalID, 3)
        ELSE N'****'
    END AS NationalIDMasked,
    A.BranchID,
    B.BranchName,
    B.BranchCode,
    A.AccountTypeID,
    AT.TypeName AS AccountTypeName,
    A.AccountStatus,
    A.FrozenPreviousStatus,
    A.OpenDate,
    A.CloseDate,
    A.Balance,
    ISNULL(P.PendingOutgoingAmount, 0) AS PendingOutgoingAmount,
    A.Balance - ISNULL(P.PendingOutgoingAmount, 0) AS AvailableBalance,
    AT.MinBalance,
    AT.InterestRate
FROM dbo.Account AS A
INNER JOIN dbo.Customer AS C ON C.CustomerID = A.CustomerID
INNER JOIN dbo.Branch AS B ON B.BranchID = A.BranchID
INNER JOIN dbo.AccountType AS AT ON AT.AccountTypeID = A.AccountTypeID
LEFT JOIN dbo.vw_AccountPendingOutgoing AS P ON P.AccountID = A.AccountID;
GO

/* ---------------------------------------------------------
   Employee directory: current branch assignment only. Salary
   is intentionally excluded from this general directory view.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_EmployeeDirectory', 'V') IS NOT NULL
    DROP VIEW dbo.vw_EmployeeDirectory;
GO

CREATE VIEW dbo.vw_EmployeeDirectory
AS
SELECT
    E.EmployeeID,
    E.FirstName,
    E.LastName,
    (E.FirstName + N' ' + E.LastName) AS EmployeeName,
    CASE
        WHEN LEN(E.NationalID) >= 6 THEN LEFT(E.NationalID, 3) + N'****' + RIGHT(E.NationalID, 3)
        ELSE N'****'
    END AS NationalIDMasked,
    E.JobTitle,
    E.EmpStatus,
    E.CanAccessAdmin,
    E.HireDate,
    E.Phone,
    E.Email,
    EB.BranchID,
    B.BranchName,
    B.BranchCode,
    EB.StartDate AS CurrentBranchStartDate,
    EB.WorkingStatus AS CurrentWorkingStatus
FROM dbo.Employee AS E
LEFT JOIN dbo.EMPB AS EB
    ON EB.EmployeeID = E.EmployeeID
   AND EB.WorkingStatus = N'Working'
   AND EB.EndDate IS NULL
LEFT JOIN dbo.Branch AS B ON B.BranchID = EB.BranchID;
GO

/* ---------------------------------------------------------
   HighAdmin employee branch overview: includes current and
   historical branch assignments.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_HighAdmin_EmployeeBranchOverview', 'V') IS NOT NULL
    DROP VIEW dbo.vw_HighAdmin_EmployeeBranchOverview;
GO

CREATE VIEW dbo.vw_HighAdmin_EmployeeBranchOverview
AS
SELECT
    E.EmployeeID,
    E.FirstName,
    E.LastName,
    (E.FirstName + N' ' + E.LastName) AS EmployeeName,
    E.NationalID,
    E.JobTitle,
    E.EmpStatus,
    E.CanAccessAdmin,
    E.HireDate,
    E.Salary,
    E.Phone,
    E.Email,
    EB.EMPBID,
    EB.BranchID,
    B.BranchName,
    B.BranchCode,
    EB.StartDate,
    EB.EndDate,
    EB.WorkingStatus
FROM dbo.Employee AS E
LEFT JOIN dbo.EMPB AS EB ON EB.EmployeeID = E.EmployeeID
LEFT JOIN dbo.Branch AS B ON B.BranchID = EB.BranchID;
GO

/* ---------------------------------------------------------
   Pending transactions: operational queue.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_PendingTransactions', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PendingTransactions;
GO

CREATE VIEW dbo.vw_PendingTransactions
AS
SELECT
    T.TransactionID,
    TT.TypeName AS TransactionType,
    T.FromAccountID,
    FA.AccountNumber AS FromAccountNumber,
    T.ToAccountID,
    TA.AccountNumber AS ToAccountNumber,
    T.Amount,
    T.TransactionDate,
    T.ReadyToCompleteAt,
    T.EmployeeID,
    (E.FirstName + N' ' + E.LastName) AS EmployeeName,
    T.Description
FROM dbo.Transactions AS T
INNER JOIN dbo.TransactionType AS TT ON TT.TransactionTypeID = T.TransactionTypeID
LEFT JOIN dbo.Account AS FA ON FA.AccountID = T.FromAccountID
LEFT JOIN dbo.Account AS TA ON TA.AccountID = T.ToAccountID
LEFT JOIN dbo.Employee AS E ON E.EmployeeID = T.EmployeeID
WHERE T.TransactionStatus = N'Pending';
GO

/* ---------------------------------------------------------
   Loan operational summary.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_LoanOperationalSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_LoanOperationalSummary;
GO

CREATE VIEW dbo.vw_LoanOperationalSummary
AS
SELECT
    L.LoanID,
    L.CustomerID,
    (C.FirstName + N' ' + C.LastName) AS CustomerName,
    L.BranchID,
    B.BranchName,
    B.BranchCode,
    L.LoanAmount,
    L.InterestRate,
    L.StartDate,
    L.EndDate,
    L.LoanStatus,
    COUNT(I.InstallmentID) AS InstallmentCount,
    SUM(CASE WHEN I.InstallmentStatus = N'Paid' THEN 1 ELSE 0 END) AS PaidInstallmentCount,
    SUM(CASE WHEN I.InstallmentStatus IN (N'Late', N'Defaulted') THEN 1 ELSE 0 END) AS ProblemInstallmentCount,
    SUM(CASE WHEN I.InstallmentStatus <> N'Paid' THEN I.Amount ELSE 0 END) AS RemainingInstallmentAmount
FROM dbo.Loan AS L
INNER JOIN dbo.Customer AS C ON C.CustomerID = L.CustomerID
INNER JOIN dbo.Branch AS B ON B.BranchID = L.BranchID
LEFT JOIN dbo.Installment AS I ON I.LoanID = L.LoanID
GROUP BY
    L.LoanID, L.CustomerID, C.FirstName, C.LastName,
    L.BranchID, B.BranchName, B.BranchCode,
    L.LoanAmount, L.InterestRate, L.StartDate, L.EndDate, L.LoanStatus;
GO

/* ---------------------------------------------------------
   Branch financial overview.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_HighAdmin_BranchFinancialOverview', 'V') IS NOT NULL
    DROP VIEW dbo.vw_HighAdmin_BranchFinancialOverview;
GO

CREATE VIEW dbo.vw_HighAdmin_BranchFinancialOverview
AS
SELECT
    B.BranchID,
    B.BranchName,
    B.BranchCode,
    B.City,
    B.Address,
    B.Phone,
    B.Balance AS RecordedBranchBalance,
    ISNULL(Agg.TotalAccountBalance, 0) AS SumOfAccountBalances,
    B.Balance - ISNULL(Agg.TotalAccountBalance, 0) AS BalanceDifference,
    ISNULL(Agg.TotalAccounts, 0) AS TotalAccounts,
    ISNULL(Agg.ActiveAccounts, 0) AS ActiveAccounts,
    ISNULL(EmpAgg.CurrentEmployeeCount, 0) AS CurrentEmployeeCount,
    ISNULL(EmpAgg.CurrentManagerCount, 0) AS CurrentManagerCount
FROM dbo.Branch AS B
LEFT JOIN
(
    SELECT
        BranchID,
        COUNT(*) AS TotalAccounts,
        SUM(CASE WHEN AccountStatus = N'Active' THEN 1 ELSE 0 END) AS ActiveAccounts,
        SUM(Balance) AS TotalAccountBalance
    FROM dbo.Account
    GROUP BY BranchID
) AS Agg ON Agg.BranchID = B.BranchID
LEFT JOIN
(
    SELECT
        EB.BranchID,
        COUNT(*) AS CurrentEmployeeCount,
        SUM(CASE WHEN E.JobTitle IN (N'Branch Manager', N'Vice Manager') THEN 1 ELSE 0 END) AS CurrentManagerCount
    FROM dbo.EMPB AS EB
    INNER JOIN dbo.Employee AS E ON E.EmployeeID = EB.EmployeeID
    WHERE EB.WorkingStatus = N'Working'
      AND EB.EndDate IS NULL
      AND E.EmpStatus = N'Active'
    GROUP BY EB.BranchID
) AS EmpAgg ON EmpAgg.BranchID = B.BranchID;
GO

/* ---------------------------------------------------------
   User access overview for HighAdmin/security review. Does
   not expose password hashes or session tokens.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_HighAdmin_UserAccessOverview', 'V') IS NOT NULL
    DROP VIEW dbo.vw_HighAdmin_UserAccessOverview;
GO

CREATE VIEW dbo.vw_HighAdmin_UserAccessOverview
AS
SELECT
    U.UserID,
    U.Username,
    U.IsActive AS UserIsActive,
    U.CustomerID,
    (C.FirstName + N' ' + C.LastName) AS CustomerName,
    C.IsActive AS CustomerIsActive,
    U.EmployeeID,
    (E.FirstName + N' ' + E.LastName) AS EmployeeName,
    E.EmpStatus,
    E.JobTitle,
    E.CanAccessAdmin,
    STUFF
    (
        (
            SELECT N',' + R2.RoleName
            FROM dbo.UserRoles AS UR2
            INNER JOIN dbo.Roles AS R2 ON R2.RoleID = UR2.RoleID
            WHERE UR2.UserID = U.UserID
            ORDER BY R2.RoleName
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'),
        1,
        1,
        N''
    ) AS AssignedRoles
FROM dbo.Users AS U
LEFT JOIN dbo.Customer AS C ON C.CustomerID = U.CustomerID
LEFT JOIN dbo.Employee AS E ON E.EmployeeID = U.EmployeeID;
GO

/* ---------------------------------------------------------
   Audit trail safe view.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_AuditTrail_Safe', 'V') IS NOT NULL
    DROP VIEW dbo.vw_AuditTrail_Safe;
GO

CREATE VIEW dbo.vw_AuditTrail_Safe
AS
SELECT
    A.AuditID,
    A.UserID,
    U.Username,
    A.ActionType,
    A.TableName,
    A.RecordID,
    A.ActionDate,
    A.Details
FROM dbo.AuditLog AS A
LEFT JOIN dbo.Users AS U ON U.UserID = A.UserID;
GO

/* ---------------------------------------------------------
   Branch ledger report.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_BranchLedgerReport', 'V') IS NOT NULL
    DROP VIEW dbo.vw_BranchLedgerReport;
GO

CREATE VIEW dbo.vw_BranchLedgerReport
AS
SELECT
    BL.BranchLedgerID,
    BL.BranchID,
    B.BranchName,
    B.BranchCode,
    BL.TransactionID,
    BL.DeltaAmount,
    BL.BalanceAfter,
    BL.EntryDate,
    BL.Description
FROM dbo.BranchLedger AS BL
INNER JOIN dbo.Branch AS B ON B.BranchID = BL.BranchID;
GO

/* ---------------------------------------------------------
   Daily transaction summary.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_DailyTransactionSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_DailyTransactionSummary;
GO

CREATE VIEW dbo.vw_DailyTransactionSummary
AS
SELECT
    CAST(T.TransactionDate AS DATE) AS TransactionDay,
    TT.TypeName AS TransactionType,
    T.TransactionStatus,
    COUNT(*) AS TransactionCount,
    SUM(T.Amount) AS TotalAmount
FROM dbo.Transactions AS T
INNER JOIN dbo.TransactionType AS TT ON TT.TransactionTypeID = T.TransactionTypeID
GROUP BY CAST(T.TransactionDate AS DATE), TT.TypeName, T.TransactionStatus;
GO

/* ---------------------------------------------------------
   Account status summary.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_AccountStatusSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_AccountStatusSummary;
GO

CREATE VIEW dbo.vw_AccountStatusSummary
AS
SELECT
    B.BranchID,
    B.BranchName,
    A.AccountStatus,
    COUNT(*) AS AccountCount,
    SUM(A.Balance) AS TotalBalance
FROM dbo.Account AS A
INNER JOIN dbo.Branch AS B ON B.BranchID = A.BranchID
GROUP BY B.BranchID, B.BranchName, A.AccountStatus;
GO

/* ---------------------------------------------------------
   Loan overdue summary.
   --------------------------------------------------------- */
IF OBJECT_ID('dbo.vw_LoanOverdueSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_LoanOverdueSummary;
GO

CREATE VIEW dbo.vw_LoanOverdueSummary
AS
SELECT
    L.LoanID,
    L.CustomerID,
    (C.FirstName + N' ' + C.LastName) AS CustomerName,
    L.BranchID,
    B.BranchName,
    L.LoanStatus,
    COUNT(I.InstallmentID) AS OverdueInstallmentCount,
    SUM(I.Amount) AS OverdueAmount,
    MIN(I.DueDate) AS OldestOverdueDueDate
FROM dbo.Loan AS L
INNER JOIN dbo.Customer AS C ON C.CustomerID = L.CustomerID
INNER JOIN dbo.Branch AS B ON B.BranchID = L.BranchID
INNER JOIN dbo.Installment AS I ON I.LoanID = L.LoanID
WHERE I.InstallmentStatus IN (N'Late', N'Defaulted')
GROUP BY L.LoanID, L.CustomerID, C.FirstName, C.LastName, L.BranchID, B.BranchName, L.LoanStatus;
GO

PRINT 'BankManagement reporting/security views created successfully.';
GO
/* =========================================================
   01_DatabaseRolesAndUsers.sql
   ---------------------------------------------------------
   Defines SQL Server database-level security personas for the
   BankManagement project.

   IMPORTANT TERMINOLOGY:
     - Application users are real bank users stored in dbo.Users.
     - Database users are SQL Server security principals used by
       the application, reporting tools, auditors, or maintenance.

   This script creates database roles and database users. By
   default, users are created WITHOUT LOGIN so the script is safe
   to run in a demo database without hard-coded passwords.

   Optional real connection logins:
     If a SQL Server login with the expected name already exists,
     this script maps the database user to that login. Otherwise,
     it creates the database user WITHOUT LOGIN.

   Optional login names expected by this script:
     - BankAppLogin
     - BankReportLogin
     - BankAuditorLogin
     - BankHighAdminReportLogin
     - BankMaintenanceLogin

   Run AFTER:
     - TableCreation.sql
     - ApplyAccessRules.sql
     - View creation module
   ========================================================= */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------
   1) Create database roles.
   --------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_app_executor' AND type = 'R')
    CREATE ROLE dbrole_bank_app_executor;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_reporting' AND type = 'R')
    CREATE ROLE dbrole_bank_reporting;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_auditor' AND type = 'R')
    CREATE ROLE dbrole_bank_auditor;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_highadmin_viewer' AND type = 'R')
    CREATE ROLE dbrole_bank_highadmin_viewer;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_maintenance' AND type = 'R')
    CREATE ROLE dbrole_bank_maintenance;
GO

/* ---------------------------------------------------------
   2) Create or map database users.
   --------------------------------------------------------- */
IF SUSER_ID(N'BankAppLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAppUser')
        EXEC(N'CREATE USER [BankAppUser] FOR LOGIN [BankAppLogin]');
    ELSE
        EXEC(N'ALTER USER [BankAppUser] WITH LOGIN = [BankAppLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAppUser')
BEGIN
    EXEC(N'CREATE USER [BankAppUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankReportLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankReportUser')
        EXEC(N'CREATE USER [BankReportUser] FOR LOGIN [BankReportLogin]');
    ELSE
        EXEC(N'ALTER USER [BankReportUser] WITH LOGIN = [BankReportLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankReportUser')
BEGIN
    EXEC(N'CREATE USER [BankReportUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankAuditorLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAuditorUser')
        EXEC(N'CREATE USER [BankAuditorUser] FOR LOGIN [BankAuditorLogin]');
    ELSE
        EXEC(N'ALTER USER [BankAuditorUser] WITH LOGIN = [BankAuditorLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAuditorUser')
BEGIN
    EXEC(N'CREATE USER [BankAuditorUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankHighAdminReportLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankHighAdminReportUser')
        EXEC(N'CREATE USER [BankHighAdminReportUser] FOR LOGIN [BankHighAdminReportLogin]');
    ELSE
        EXEC(N'ALTER USER [BankHighAdminReportUser] WITH LOGIN = [BankHighAdminReportLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankHighAdminReportUser')
BEGIN
    EXEC(N'CREATE USER [BankHighAdminReportUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankMaintenanceLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankMaintenanceUser')
        EXEC(N'CREATE USER [BankMaintenanceUser] FOR LOGIN [BankMaintenanceLogin]');
    ELSE
        EXEC(N'ALTER USER [BankMaintenanceUser] WITH LOGIN = [BankMaintenanceLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankMaintenanceUser')
BEGIN
    EXEC(N'CREATE USER [BankMaintenanceUser] WITHOUT LOGIN');
END;
GO

/* ---------------------------------------------------------
   3) Add users to roles idempotently.
   --------------------------------------------------------- */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_app_executor' AND m.name = N'BankAppUser'
)
    ALTER ROLE dbrole_bank_app_executor ADD MEMBER BankAppUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_reporting' AND m.name = N'BankReportUser'
)
    ALTER ROLE dbrole_bank_reporting ADD MEMBER BankReportUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_auditor' AND m.name = N'BankAuditorUser'
)
    ALTER ROLE dbrole_bank_auditor ADD MEMBER BankAuditorUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_highadmin_viewer' AND m.name = N'BankHighAdminReportUser'
)
    ALTER ROLE dbrole_bank_highadmin_viewer ADD MEMBER BankHighAdminReportUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_maintenance' AND m.name = N'BankMaintenanceUser'
)
    ALTER ROLE dbrole_bank_maintenance ADD MEMBER BankMaintenanceUser;
GO

/* ---------------------------------------------------------
   OPTIONAL: create SQL Server logins in master.
   ---------------------------------------------------------
   This section is intentionally commented out to avoid storing
   passwords in project source code. If you need real SQL logins,
   run the following in the master database and replace passwords:

   USE master;
   CREATE LOGIN BankAppLogin WITH PASSWORD = 'Replace_With_Strong_Password_1!';
   CREATE LOGIN BankReportLogin WITH PASSWORD = 'Replace_With_Strong_Password_2!';
   CREATE LOGIN BankAuditorLogin WITH PASSWORD = 'Replace_With_Strong_Password_3!';
   CREATE LOGIN BankHighAdminReportLogin WITH PASSWORD = 'Replace_With_Strong_Password_4!';
   CREATE LOGIN BankMaintenanceLogin WITH PASSWORD = 'Replace_With_Strong_Password_5!';

   Then return to the BankManagement database and re-run this file.
   --------------------------------------------------------- */

PRINT 'Database roles and users created/mapped successfully.';
GO
/* =========================================================
   02_DatabasePrivileges.sql
   ---------------------------------------------------------
   Grants database-level permissions for the BankManagement
   project. The design is:

     - No direct table access for application/report/audit users.
     - Application service user executes stored procedures.
     - Reporting/audit users read controlled views only.
     - Business authorization remains inside dbo.Users/dbo.Roles
       and procedure-level checks.

   Run AFTER:
     - 01_BankManagement_ReportingViews.sql
     - 01_DatabaseRolesAndUsers.sql
   ========================================================= */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------
   1) Remove accidental direct DML permissions from project roles.
   REVOKE is safe even if no permission was previously granted.
   We do not use DENY because DENY can create unnecessary conflicts
   during testing and maintenance.
   --------------------------------------------------------- */
DECLARE @RoleName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

DECLARE role_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.database_principals
WHERE name IN
(
    N'dbrole_bank_app_executor',
    N'dbrole_bank_reporting',
    N'dbrole_bank_auditor',
    N'dbrole_bank_highadmin_viewer',
    N'dbrole_bank_maintenance'
);

OPEN role_cursor;
FETCH NEXT FROM role_cursor INTO @RoleName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'';

    SELECT @Sql = @Sql +
        N'REVOKE SELECT, INSERT, UPDATE, DELETE ON OBJECT::'
        + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
        + N' TO ' + QUOTENAME(@RoleName) + N';' + CHAR(13) + CHAR(10)
    FROM sys.tables AS t
    WHERE SCHEMA_NAME(t.schema_id) = N'dbo';

    IF LEN(@Sql) > 0 EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM role_cursor INTO @RoleName;
END;
CLOSE role_cursor;
DEALLOCATE role_cursor;
GO

/* ---------------------------------------------------------
   2) BankAppUser: application backend technical user.
   It can execute procedures. The procedures themselves enforce
   application roles using @UserID/session/effective-role logic.
   --------------------------------------------------------- */
GRANT EXECUTE ON SCHEMA::dbo TO dbrole_bank_app_executor;
GO

GRANT SELECT ON dbo.vw_CustomerBasicProfile TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_CustomerAccountSummary TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_AccountOperationalSummary TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_EmployeeDirectory TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_PendingTransactions TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_LoanOperationalSummary TO dbrole_bank_app_executor;
GO

/* ---------------------------------------------------------
   3) Reporting role: aggregate and operational read-only views.
   --------------------------------------------------------- */
GRANT SELECT ON dbo.vw_CustomerBasicProfile TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_CustomerAccountSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_AccountOperationalSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_EmployeeDirectory TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_PendingTransactions TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_LoanOperationalSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_HighAdmin_BranchFinancialOverview TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_DailyTransactionSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_AccountStatusSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_LoanOverdueSummary TO dbrole_bank_reporting;
GO

/* ---------------------------------------------------------
   4) Auditor role: audit and financial trace views.
   --------------------------------------------------------- */
GRANT SELECT ON dbo.vw_AuditTrail_Safe TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_BranchLedgerReport TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_DailyTransactionSummary TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_AccountStatusSummary TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_LoanOverdueSummary TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_HighAdmin_UserAccessOverview TO dbrole_bank_auditor;
GO

/* ---------------------------------------------------------
   5) HighAdmin reporting role: full read-only oversight views.
   This is still a database-level reporting persona, not the same
   thing as the application HighAdmin stored in dbo.Users.
   --------------------------------------------------------- */
GRANT SELECT ON dbo.vw_CustomerBasicProfile TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_CustomerAccountSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_AccountOperationalSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_EmployeeDirectory TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_HighAdmin_EmployeeBranchOverview TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_HighAdmin_BranchFinancialOverview TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_HighAdmin_UserAccessOverview TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_AuditTrail_Safe TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_BranchLedgerReport TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_DailyTransactionSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_AccountStatusSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_LoanOperationalSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_LoanOverdueSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_PendingTransactions TO dbrole_bank_highadmin_viewer;
GO

/* ---------------------------------------------------------
   6) Maintenance role: metadata visibility only by default.
   Real DBA maintenance can be performed by db_owner/sysadmin.
   --------------------------------------------------------- */
GRANT VIEW DEFINITION TO dbrole_bank_maintenance;
GO

PRINT 'Database permissions granted successfully.';
GO
