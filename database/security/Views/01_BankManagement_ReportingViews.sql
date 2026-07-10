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
