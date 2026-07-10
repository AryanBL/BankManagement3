/* =========================================================
   SampleData_RealisticScenario_CLEANUP.sql
   ---------------------------------------------------------
   Removes records inserted by SampleData_RealisticScenario.sql.

   Purpose:
     - Use this after a partial/failed sample-data run.
     - It deletes only the deterministic sample records identified
       by the sample branch codes, sample account type names,
       sample NationalID ranges, and dependent records.

   IMPORTANT:
     - Run in the BankManagement database.
     - Review before running on any database that contains real data.
     - This script is idempotent: running it again should delete 0 rows.
   ========================================================= */

USE BankManagement;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @PreviewOnly BIT = 0;  -- 0 = delete and COMMIT, 1 = preview then ROLLBACK

IF OBJECT_ID('dbo.Users','U') IS NULL
BEGIN
    RAISERROR('BankManagement schema was not found. dbo.Users does not exist.', 16, 1);
    RETURN;
END;

/* ---------------------------------------------------------
   1) Identify sample roots
   --------------------------------------------------------- */
IF OBJECT_ID('tempdb..#SampleBranches') IS NOT NULL DROP TABLE #SampleBranches;
IF OBJECT_ID('tempdb..#SampleAccountTypes') IS NOT NULL DROP TABLE #SampleAccountTypes;
IF OBJECT_ID('tempdb..#SampleCustomers') IS NOT NULL DROP TABLE #SampleCustomers;
IF OBJECT_ID('tempdb..#SampleEmployees') IS NOT NULL DROP TABLE #SampleEmployees;
IF OBJECT_ID('tempdb..#SampleUsers') IS NOT NULL DROP TABLE #SampleUsers;
IF OBJECT_ID('tempdb..#SampleAccounts') IS NOT NULL DROP TABLE #SampleAccounts;
IF OBJECT_ID('tempdb..#SampleLoans') IS NOT NULL DROP TABLE #SampleLoans;
IF OBJECT_ID('tempdb..#SampleInstallments') IS NOT NULL DROP TABLE #SampleInstallments;
IF OBJECT_ID('tempdb..#SampleTransactions') IS NOT NULL DROP TABLE #SampleTransactions;
IF OBJECT_ID('tempdb..#SampleTransferRequests') IS NOT NULL DROP TABLE #SampleTransferRequests;

CREATE TABLE #SampleBranches (BranchID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleAccountTypes (AccountTypeID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleCustomers (CustomerID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleEmployees (EmployeeID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleUsers (UserID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleAccounts (AccountID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleLoans (LoanID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleInstallments (InstallmentID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleTransactions (TransactionID INT NOT NULL PRIMARY KEY);
CREATE TABLE #SampleTransferRequests (TransferRequestID INT NOT NULL PRIMARY KEY);

INSERT INTO #SampleBranches(BranchID)
SELECT BranchID
FROM dbo.Branch
WHERE BranchCode IN
(
    N'BB001', N'RV001', N'GD001', N'SH001',
    N'MD001', N'RH001', N'MT001', N'MW001'
);

INSERT INTO #SampleAccountTypes(AccountTypeID)
SELECT AccountTypeID
FROM dbo.AccountType
WHERE TypeName IN
(
    N'Savings Basic',
    N'Savings Premium',
    N'Current Account',
    N'Student Account',
    N'Business Account',
    N'Golden Reserve'
);

/*
   Sample customers:
     3000000001              = initial HighAdmin customer
     3100000001-3100000012   = manager customers
     3200000001-3200000025   = employee customers/logins
     4000000001-4000000032   = normal customer signups
*/
INSERT INTO #SampleCustomers(CustomerID)
SELECT CustomerID
FROM dbo.Customer
WHERE NationalID = N'3000000001'
   OR NationalID BETWEEN N'3100000001' AND N'3100000012'
   OR NationalID BETWEEN N'3200000001' AND N'3200000025'
   OR NationalID BETWEEN N'4000000001' AND N'4000000032';

/*
   Sample employees:
     3100000001-3100000012   = managers and vice managers
     3200000001-3200000025   = ordinary employees
*/
INSERT INTO #SampleEmployees(EmployeeID)
SELECT EmployeeID
FROM dbo.Employee
WHERE NationalID BETWEEN N'3100000001' AND N'3100000012'
   OR NationalID BETWEEN N'3200000001' AND N'3200000025';

INSERT INTO #SampleUsers(UserID)
SELECT DISTINCT U.UserID
FROM dbo.Users U
WHERE U.CustomerID IN (SELECT CustomerID FROM #SampleCustomers)
   OR U.EmployeeID IN (SELECT EmployeeID FROM #SampleEmployees)
   OR U.Username IN
   (
        N'gandalf.highadmin',
        N'spongebob.manager', N'squidward.vice', N'galadriel.manager', N'legolas.vice',
        N'aragorn.manager', N'faramir.vice', N'frodo.manager', N'samwise.vice',
        N'sauron.manager', N'theoden.manager', N'boromir.manager', N'thranduil.manager',
        N'patrick.teller', N'sandy.loan', N'mrkrabs.cash', N'plankton.risk', N'pearl.support',
        N'merry.accounts', N'pippin.teller', N'rosie.support', N'bilbo.archive',
        N'arwen.private', N'elrond.compliance', N'gimli.vault',
        N'eowyn.service', N'denethor.audit', N'beregond.teller',
        N'gollum.collections', N'saruman.risk', N'shelob.vault',
        N'eomer.field', N'treebeard.advisor', N'wormtongue.ops',
        N'tom.teller', N'goldberry.service', N'tauriel.private', N'bard.loan',
        N'olivia.harper', N'daniel.reed', N'maya.foster', N'noah.bennett', N'chloe.mason',
        N'ryan.brooks', N'sophia.lane', N'liam.carter', N'emma.collins', N'ethan.price',
        N'ava.morgan', N'james.parker', N'isabella.hughes', N'logan.evans', N'grace.murphy',
        N'henry.cooper', N'amelia.ross', N'lucas.ward', N'mia.richardson', N'oscar.bailey',
        N'zoe.cox', N'mason.gray', N'lily.howard', N'jack.king', N'nora.scott',
        N'leo.green', N'ella.adams', N'max.baker', N'ivy.nelson', N'adam.turner',
        N'ruby.phillips', N'finn.campbell'
   );

INSERT INTO #SampleAccounts(AccountID)
SELECT AccountID
FROM dbo.Account
WHERE CustomerID IN (SELECT CustomerID FROM #SampleCustomers);

INSERT INTO #SampleLoans(LoanID)
SELECT LoanID
FROM dbo.Loan
WHERE CustomerID IN (SELECT CustomerID FROM #SampleCustomers);

INSERT INTO #SampleInstallments(InstallmentID)
SELECT InstallmentID
FROM dbo.Installment
WHERE LoanID IN (SELECT LoanID FROM #SampleLoans);

INSERT INTO #SampleTransactions(TransactionID)
SELECT DISTINCT T.TransactionID
FROM dbo.Transactions T
WHERE T.FromAccountID IN (SELECT AccountID FROM #SampleAccounts)
   OR T.ToAccountID   IN (SELECT AccountID FROM #SampleAccounts)
   OR T.EmployeeID    IN (SELECT EmployeeID FROM #SampleEmployees)
   OR T.TransactionID IN
        (
            SELECT PaymentTransactionID
            FROM dbo.Installment
            WHERE PaymentTransactionID IS NOT NULL
              AND InstallmentID IN (SELECT InstallmentID FROM #SampleInstallments)
        );

INSERT INTO #SampleTransferRequests(TransferRequestID)
SELECT TransferRequestID
FROM dbo.EmployeeTransferRequest
WHERE EmployeeID IN (SELECT EmployeeID FROM #SampleEmployees)
   OR RequestedByUserID IN (SELECT UserID FROM #SampleUsers)
   OR CurrentManagerUserID IN (SELECT UserID FROM #SampleUsers)
   OR DestinationManagerUserID IN (SELECT UserID FROM #SampleUsers);

/* ---------------------------------------------------------
   2) Safety checks to avoid deleting non-sample data that
      manually reused the sample branches/types.
   --------------------------------------------------------- */
IF EXISTS
(
    SELECT 1
    FROM dbo.Account A
    WHERE A.BranchID IN (SELECT BranchID FROM #SampleBranches)
      AND A.CustomerID NOT IN (SELECT CustomerID FROM #SampleCustomers)
)
BEGIN
    RAISERROR('Cleanup aborted: a non-sample account references a sample branch. Move/delete that account first or do a clean rebuild.', 16, 1);
    RETURN;
END;

IF EXISTS
(
    SELECT 1
    FROM dbo.Account A
    WHERE A.AccountTypeID IN (SELECT AccountTypeID FROM #SampleAccountTypes)
      AND A.CustomerID NOT IN (SELECT CustomerID FROM #SampleCustomers)
)
BEGIN
    RAISERROR('Cleanup aborted: a non-sample account references a sample account type. Move/delete that account first or do a clean rebuild.', 16, 1);
    RETURN;
END;

IF EXISTS
(
    SELECT 1
    FROM dbo.Loan L
    WHERE L.BranchID IN (SELECT BranchID FROM #SampleBranches)
      AND L.CustomerID NOT IN (SELECT CustomerID FROM #SampleCustomers)
)
BEGIN
    RAISERROR('Cleanup aborted: a non-sample loan references a sample branch. Move/delete that loan first or do a clean rebuild.', 16, 1);
    RETURN;
END;

IF EXISTS
(
    SELECT 1
    FROM dbo.EMPB EB
    WHERE EB.BranchID IN (SELECT BranchID FROM #SampleBranches)
      AND EB.EmployeeID NOT IN (SELECT EmployeeID FROM #SampleEmployees)
)
BEGIN
    RAISERROR('Cleanup aborted: a non-sample employee-branch assignment references a sample branch. Move/delete that assignment first or do a clean rebuild.', 16, 1);
    RETURN;
END;

IF EXISTS
(
    SELECT 1
    FROM dbo.EmployeeTransferRequest TR
    WHERE (TR.FromBranchID IN (SELECT BranchID FROM #SampleBranches)
        OR TR.ToBranchID   IN (SELECT BranchID FROM #SampleBranches))
      AND TR.EmployeeID NOT IN (SELECT EmployeeID FROM #SampleEmployees)
)
BEGIN
    RAISERROR('Cleanup aborted: a non-sample employee transfer request references a sample branch. Move/delete that request first or do a clean rebuild.', 16, 1);
    RETURN;
END;

/* ---------------------------------------------------------
   3) Preview roots
   --------------------------------------------------------- */
PRINT 'Sample cleanup target counts before delete:';
SELECT 'SampleBranches' AS Entity, COUNT(*) AS RowsFound FROM #SampleBranches
UNION ALL SELECT 'SampleAccountTypes', COUNT(*) FROM #SampleAccountTypes
UNION ALL SELECT 'SampleCustomers', COUNT(*) FROM #SampleCustomers
UNION ALL SELECT 'SampleEmployees', COUNT(*) FROM #SampleEmployees
UNION ALL SELECT 'SampleUsers', COUNT(*) FROM #SampleUsers
UNION ALL SELECT 'SampleAccounts', COUNT(*) FROM #SampleAccounts
UNION ALL SELECT 'SampleLoans', COUNT(*) FROM #SampleLoans
UNION ALL SELECT 'SampleInstallments', COUNT(*) FROM #SampleInstallments
UNION ALL SELECT 'SampleTransactions', COUNT(*) FROM #SampleTransactions
UNION ALL SELECT 'SampleTransferRequests', COUNT(*) FROM #SampleTransferRequests;

/* ---------------------------------------------------------
   4) Delete in foreign-key-safe order
   --------------------------------------------------------- */
DECLARE @Deleted TABLE
(
    StepNo INT IDENTITY(1,1) PRIMARY KEY,
    EntityName NVARCHAR(100) NOT NULL,
    RowsDeleted INT NOT NULL
);

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE TR
    FROM dbo.EmployeeTransferRequest TR
    WHERE TR.TransferRequestID IN (SELECT TransferRequestID FROM #SampleTransferRequests);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'EmployeeTransferRequest', @@ROWCOUNT);

    DELETE AL
    FROM dbo.AuditLog AL
    WHERE AL.UserID IN (SELECT UserID FROM #SampleUsers)
       OR (AL.TableName IN (N'Users', N'User', N'dbo.Users') AND AL.RecordID IN (SELECT UserID FROM #SampleUsers))
       OR (AL.TableName IN (N'Customer', N'Customers', N'dbo.Customer') AND AL.RecordID IN (SELECT CustomerID FROM #SampleCustomers))
       OR (AL.TableName IN (N'Employee', N'Employees', N'dbo.Employee') AND AL.RecordID IN (SELECT EmployeeID FROM #SampleEmployees))
       OR (AL.TableName IN (N'Account', N'Accounts', N'dbo.Account') AND AL.RecordID IN (SELECT AccountID FROM #SampleAccounts))
       OR (AL.TableName IN (N'Transactions', N'Transaction', N'dbo.Transactions') AND AL.RecordID IN (SELECT TransactionID FROM #SampleTransactions))
       OR (AL.TableName IN (N'Loan', N'Loans', N'dbo.Loan') AND AL.RecordID IN (SELECT LoanID FROM #SampleLoans))
       OR (AL.TableName IN (N'Installment', N'Installments', N'dbo.Installment') AND AL.RecordID IN (SELECT InstallmentID FROM #SampleInstallments))
       OR (AL.TableName IN (N'Branch', N'Branches', N'dbo.Branch') AND AL.RecordID IN (SELECT BranchID FROM #SampleBranches));
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'AuditLog', @@ROWCOUNT);

    DELETE BL
    FROM dbo.BranchLedger BL
    WHERE BL.TransactionID IN (SELECT TransactionID FROM #SampleTransactions)
       OR BL.BranchID IN (SELECT BranchID FROM #SampleBranches);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'BranchLedger', @@ROWCOUNT);

    DELETE I
    FROM dbo.Installment I
    WHERE I.InstallmentID IN (SELECT InstallmentID FROM #SampleInstallments);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Installment', @@ROWCOUNT);

    DELETE L
    FROM dbo.Loan L
    WHERE L.LoanID IN (SELECT LoanID FROM #SampleLoans);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Loan', @@ROWCOUNT);

    DELETE T
    FROM dbo.Transactions T
    WHERE T.TransactionID IN (SELECT TransactionID FROM #SampleTransactions);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Transactions', @@ROWCOUNT);

    DELETE A
    FROM dbo.Account A
    WHERE A.AccountID IN (SELECT AccountID FROM #SampleAccounts);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Account', @@ROWCOUNT);

    DELETE EB
    FROM dbo.EMPB EB
    WHERE EB.EmployeeID IN (SELECT EmployeeID FROM #SampleEmployees)
       OR EB.BranchID IN (SELECT BranchID FROM #SampleBranches);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'EMPB', @@ROWCOUNT);

    DELETE S
    FROM dbo.Sessions S
    WHERE S.UserID IN (SELECT UserID FROM #SampleUsers);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Sessions', @@ROWCOUNT);

    DELETE UR
    FROM dbo.UserRoles UR
    WHERE UR.UserID IN (SELECT UserID FROM #SampleUsers);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'UserRoles', @@ROWCOUNT);

    DELETE U
    FROM dbo.Users U
    WHERE U.UserID IN (SELECT UserID FROM #SampleUsers);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Users', @@ROWCOUNT);

    DELETE E
    FROM dbo.Employee E
    WHERE E.EmployeeID IN (SELECT EmployeeID FROM #SampleEmployees);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Employee', @@ROWCOUNT);

    DELETE C
    FROM dbo.Customer C
    WHERE C.CustomerID IN (SELECT CustomerID FROM #SampleCustomers);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Customer', @@ROWCOUNT);

    DELETE AT
    FROM dbo.AccountType AT
    WHERE AT.AccountTypeID IN (SELECT AccountTypeID FROM #SampleAccountTypes);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'AccountType', @@ROWCOUNT);

    DELETE B
    FROM dbo.Branch B
    WHERE B.BranchID IN (SELECT BranchID FROM #SampleBranches);
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Branch', @@ROWCOUNT);

    /* Direct Account deletes do not fire the account balance-update trigger.
       Recompute Branch.Balance for any branches still present. */
    UPDATE B
    SET B.Balance = ISNULL(X.TotalBalance, 0)
    FROM dbo.Branch B
    OUTER APPLY
    (
        SELECT SUM(A.Balance) AS TotalBalance
        FROM dbo.Account A
        WHERE A.BranchID = B.BranchID
    ) X;
    INSERT INTO @Deleted(EntityName, RowsDeleted) VALUES(N'Branch balance recalculated', @@ROWCOUNT);

    IF @PreviewOnly = 1
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT 'PREVIEW ONLY: transaction rolled back. No data was deleted.';
    END
    ELSE
    BEGIN
        COMMIT TRANSACTION;
        PRINT 'Sample cleanup committed successfully.';
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR('Sample cleanup failed and was rolled back. Original error: %s', 16, 1, @Err);
    RETURN;
END CATCH;

PRINT 'Cleanup delete summary:';
SELECT StepNo, EntityName, RowsDeleted
FROM @Deleted
ORDER BY StepNo;

PRINT 'Remaining sample root counts after cleanup:';
SELECT 'SampleBranches' AS Entity, COUNT(*) AS RowsRemaining
FROM dbo.Branch
WHERE BranchCode IN (N'BB001', N'RV001', N'GD001', N'SH001', N'MD001', N'RH001', N'MT001', N'MW001')
UNION ALL
SELECT 'SampleAccountTypes', COUNT(*)
FROM dbo.AccountType
WHERE TypeName IN (N'Savings Basic', N'Savings Premium', N'Current Account', N'Student Account', N'Business Account', N'Golden Reserve')
UNION ALL
SELECT 'SampleCustomers', COUNT(*)
FROM dbo.Customer
WHERE NationalID = N'3000000001'
   OR NationalID BETWEEN N'3100000001' AND N'3100000012'
   OR NationalID BETWEEN N'3200000001' AND N'3200000025'
   OR NationalID BETWEEN N'4000000001' AND N'4000000032'
UNION ALL
SELECT 'SampleEmployees', COUNT(*)
FROM dbo.Employee
WHERE NationalID BETWEEN N'3100000001' AND N'3100000012'
   OR NationalID BETWEEN N'3200000001' AND N'3200000025'
UNION ALL
SELECT 'SampleUsers', COUNT(*)
FROM dbo.Users
WHERE Username IN
(
    N'gandalf.highadmin',
    N'spongebob.manager', N'squidward.vice', N'galadriel.manager', N'legolas.vice',
    N'aragorn.manager', N'faramir.vice', N'frodo.manager', N'samwise.vice',
    N'sauron.manager', N'theoden.manager', N'boromir.manager', N'thranduil.manager',
    N'patrick.teller', N'sandy.loan', N'mrkrabs.cash', N'plankton.risk', N'pearl.support',
    N'merry.accounts', N'pippin.teller', N'rosie.support', N'bilbo.archive',
    N'arwen.private', N'elrond.compliance', N'gimli.vault',
    N'eowyn.service', N'denethor.audit', N'beregond.teller',
    N'gollum.collections', N'saruman.risk', N'shelob.vault',
    N'eomer.field', N'treebeard.advisor', N'wormtongue.ops',
    N'tom.teller', N'goldberry.service', N'tauriel.private', N'bard.loan',
    N'olivia.harper', N'daniel.reed', N'maya.foster', N'noah.bennett', N'chloe.mason',
    N'ryan.brooks', N'sophia.lane', N'liam.carter', N'emma.collins', N'ethan.price',
    N'ava.morgan', N'james.parker', N'isabella.hughes', N'logan.evans', N'grace.murphy',
    N'henry.cooper', N'amelia.ross', N'lucas.ward', N'mia.richardson', N'oscar.bailey',
    N'zoe.cox', N'mason.gray', N'lily.howard', N'jack.king', N'nora.scott',
    N'leo.green', N'ella.adams', N'max.baker', N'ivy.nelson', N'adam.turner',
    N'ruby.phillips', N'finn.campbell'
);
GO
