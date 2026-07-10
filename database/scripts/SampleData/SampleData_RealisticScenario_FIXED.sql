/* =========================================================
   SampleData_RealisticScenario.sql
   ---------------------------------------------------------
   Realistic sample-data scenario for the final BankManagement
   database project.

   Scenario order:
     1) Reference data: branches and account types.
     2) One initial HighAdmin user exists at the beginning.
     3) HighAdmin hires Branch Managers and Vice Managers.
     4) Managers hire normal employees and create employee logins.
     5) Normal customers sign up by themselves.
     6) Customers and staff open bank accounts.
     7) Deposits, withdrawals, transfers, pending, cancelled,
        failed, and reversed transactions are simulated.
     8) Loans and installments are created, paid, late, and defaulted.
     9) Interest is applied and branch/account states are varied.

   Names:
     - Managers and employees use SpongeBob SquarePants and
       The Lord of the Rings character names, as requested.
     - Normal customers use generic names.

   RUN AFTER the complete final schema, rules, triggers, and
   stored procedures have been installed. This script is intended
   for a fresh/demo database. It stops if dbo.Users already has rows.
   ========================================================= */

USE BankManagement;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM dbo.Users)
BEGIN
    RAISERROR('SampleData_RealisticScenario.sql is intended for a fresh/demo database. dbo.Users is not empty.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('dbo.sp_HighAdmin_CreateInitialUser','P') IS NULL
   OR OBJECT_ID('dbo.sp_HighAdmin_HireManager','P') IS NULL
   OR OBJECT_ID('dbo.sp_Employee_Hire','P') IS NULL
   OR OBJECT_ID('dbo.sp_Employee_CreateUserAccount','P') IS NULL
   OR OBJECT_ID('dbo.sp_User_SignUp','P') IS NULL
   OR OBJECT_ID('dbo.sp_Account_Open','P') IS NULL
   OR OBJECT_ID('dbo.sp_Transaction_Deposit','P') IS NULL
   OR OBJECT_ID('dbo.sp_Transaction_Withdrawal','P') IS NULL
   OR OBJECT_ID('dbo.sp_Transaction_Transfer','P') IS NULL
   OR OBJECT_ID('dbo.sp_Transaction_ProcessPendingBatch','P') IS NULL
   OR OBJECT_ID('dbo.sp_Transaction_Reverse','P') IS NULL
   OR OBJECT_ID('dbo.sp_Loan_Create','P') IS NULL
   OR OBJECT_ID('dbo.sp_Loan_PayInstallment','P') IS NULL
   OR OBJECT_ID('dbo.sp_Loan_ProcessOverdueInstallments','P') IS NULL
   OR OBJECT_ID('dbo.sp_Account_ApplyMonthlyInterest','P') IS NULL
BEGIN
    RAISERROR('Required final stored procedures are missing. Install all final modules before running sample data.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('tempdb..#Managers') IS NOT NULL DROP TABLE #Managers;
IF OBJECT_ID('tempdb..#Employees') IS NOT NULL DROP TABLE #Employees;
IF OBJECT_ID('tempdb..#AppUsers') IS NOT NULL DROP TABLE #AppUsers;
IF OBJECT_ID('tempdb..#Accounts') IS NOT NULL DROP TABLE #Accounts;
IF OBJECT_ID('tempdb..#Loans') IS NOT NULL DROP TABLE #Loans;
IF OBJECT_ID('tempdb..#TxCreated') IS NOT NULL DROP TABLE #TxCreated;

CREATE TABLE #AppUsers
(
    UserKey NVARCHAR(50) NOT NULL PRIMARY KEY,
    UserID INT NOT NULL,
    CustomerID INT NOT NULL,
    AppUserType NVARCHAR(30) NOT NULL,
    DisplayName NVARCHAR(120) NOT NULL
);

CREATE TABLE #Managers
(
    ManagerKey NVARCHAR(50) NOT NULL PRIMARY KEY,
    BranchCode NVARCHAR(20) NOT NULL,
    BranchID INT NOT NULL,
    EmployeeID INT NOT NULL,
    CustomerID INT NOT NULL,
    UserID INT NOT NULL,
    JobTitle NVARCHAR(100) NOT NULL,
    DisplayName NVARCHAR(120) NOT NULL
);

CREATE TABLE #Employees
(
    EmployeeKey NVARCHAR(50) NOT NULL PRIMARY KEY,
    ManagerKey NVARCHAR(50) NOT NULL,
    EmployeeID INT NOT NULL,
    CustomerID INT NULL,
    UserID INT NULL,
    JobTitle NVARCHAR(100) NOT NULL,
    FinalAction NVARCHAR(20) NOT NULL,
    DisplayName NVARCHAR(120) NOT NULL
);

CREATE TABLE #Accounts
(
    AccountKey NVARCHAR(50) NOT NULL PRIMARY KEY,
    UserKey NVARCHAR(50) NOT NULL,
    AccountID INT NOT NULL,
    AccountNumber NVARCHAR(12) NOT NULL,
    CustomerID INT NOT NULL,
    BranchCode NVARCHAR(20) NOT NULL,
    AccountTypeName NVARCHAR(50) NOT NULL
);

CREATE TABLE #TxCreated
(
    TxKey NVARCHAR(50) NOT NULL PRIMARY KEY,
    TransactionID INT NOT NULL,
    TxScenario NVARCHAR(50) NOT NULL
);

CREATE TABLE #Loans
(
    LoanKey NVARCHAR(50) NOT NULL PRIMARY KEY,
    LoanID INT NOT NULL,
    CustomerKey NVARCHAR(50) NOT NULL,
    Scenario NVARCHAR(30) NOT NULL
);

PRINT '1) Creating branches and account types...';
INSERT INTO dbo.Branch (BranchName, BranchCode, City, Address, Phone)
VALUES    (N'Bikini Bottom Central', N'BB001', N'Bikini Bottom', N'124 Conch Street, Downtown Bikini Bottom', N'555-0101'),
    (N'Rivendell Private Banking', N'RV001', N'Rivendell', N'Last Homely House, East Valley', N'555-0102'),
    (N'Gondor Capital Branch', N'GD001', N'Minas Tirith', N'White Tree Avenue, Level 4', N'555-0103'),
    (N'Shire Community Branch', N'SH001', N'Hobbiton', N'Bag End Road, Hobbiton', N'555-0104'),
    (N'Mordor Industrial Branch', N'MD001', N'Barad-dur', N'Ash Plain Commercial District', N'555-0105'),
    (N'Rohan Rural Branch', N'RH001', N'Edoras', N'Golden Hall Street', N'555-0106'),
    (N'Minas Tirith Commercial', N'MT001', N'Minas Tirith', N'Market Circle, Level 2', N'555-0107'),
    (N'Mirkwood Green Branch', N'MW001', N'Mirkwood', N'Forest Gate Finance Plaza', N'555-0108');
INSERT INTO dbo.AccountType (TypeName, Description, MinBalance, InterestRate, MonthlyFee)
VALUES    (N'Savings Basic', N'Low-minimum everyday savings account.', 100, 1.25, 0),
    (N'Savings Premium', N'Higher-balance savings account with better interest.', 1000, 2.5, 0),
    (N'Current Account', N'Daily transaction account for salary and expenses.', 500, 0, 0),
    (N'Student Account', N'Low-minimum account for young adult students.', 50, 0.75, 0),
    (N'Business Account', N'Business operating account with higher minimum balance.', 5000, 1.1, 0),
    (N'Golden Reserve', N'High-value reserve account for priority customers.', 10000, 3.1, 0);
PRINT '2) Creating the initial HighAdmin user...';

DECLARE @HighAdminUserID INT, @HighAdminCustomerID INT;
EXEC dbo.sp_HighAdmin_CreateInitialUser
    @Username = N'gandalf.highadmin',
    @Password = N'Mellon#2026',
    @FirstName = N'Gandalf',
    @LastName = N'Stormcrow',
    @NationalID = N'3000000001',
    @BirthDate = '1950-01-03',
    @Phone = N'0900000001',
    @Email = N'gandalf.highadmin@bank.local',
    @Address = N'HighAdmin Office, White Council Tower',
    @UserID = @HighAdminUserID OUTPUT,
    @CustomerID = @HighAdminCustomerID OUTPUT;

INSERT INTO #AppUsers(UserKey, UserID, CustomerID, AppUserType, DisplayName)
VALUES (N'HA_GANDALF', @HighAdminUserID, @HighAdminCustomerID, N'HighAdmin', N'Gandalf Stormcrow');

PRINT '3) HighAdmin hires branch managers and vice managers...';
IF OBJECT_ID('tempdb..#ManagerSeed') IS NOT NULL DROP TABLE #ManagerSeed;
CREATE TABLE #ManagerSeed
(
    ManagerKey NVARCHAR(50), BranchCode NVARCHAR(20), Username NVARCHAR(50), PasswordValue NVARCHAR(4000),
    NationalID NVARCHAR(20), FirstName NVARCHAR(50), LastName NVARCHAR(50), BirthDate DATE, HireDate DATE,
    JobTitle NVARCHAR(100), Salary DECIMAL(18,2), Phone NVARCHAR(20), Email NVARCHAR(100), Address NVARCHAR(200)
);
INSERT INTO #ManagerSeed VALUES
    (N'BM_BIKINI', N'BB001', N'spongebob.manager', N'Pineapple#1', N'3100000001', N'SpongeBob', N'SquarePants', N'1988-07-14', N'2024-01-02', N'Branch Manager', 98000, N'0901000001', N'spongebob.manager@bank.local', N'Pineapple House, Bikini Bottom'),
    (N'VM_BIKINI', N'BB001', N'squidward.vice', N'Clarinet#2', N'3100000002', N'Squidward', N'Tentacles', N'1979-10-09', N'2024-01-04', N'Vice Manager', 87000, N'0901000002', N'squidward.vice@bank.local', N'Easter Island Head, Bikini Bottom'),
    (N'BM_RIVENDELL', N'RV001', N'galadriel.manager', N'Lorien#1', N'3100000003', N'Galadriel', N'Lothlorien', N'1970-02-15', N'2024-01-05', N'Branch Manager', 125000, N'0901000003', N'galadriel.manager@bank.local', N'Golden Wood Residence'),
    (N'VM_RIVENDELL', N'RV001', N'legolas.vice', N'Mirkwood#2', N'3100000004', N'Legolas', N'Greenleaf', N'1983-05-12', N'2024-01-06', N'Vice Manager', 102000, N'0901000004', N'legolas.vice@bank.local', N'Northern Mirkwood Avenue'),
    (N'BM_GONDOR', N'GD001', N'aragorn.manager', N'Anduril#1', N'3100000005', N'Aragorn', N'Elessar', N'1975-03-01', N'2024-01-07', N'Branch Manager', 130000, N'0901000005', N'aragorn.manager@bank.local', N'Citadel House, Minas Tirith'),
    (N'VM_GONDOR', N'GD001', N'faramir.vice', N'Ithilien#2', N'3100000006', N'Faramir', N'Ranger', N'1981-09-17', N'2024-01-08', N'Vice Manager', 99000, N'0901000006', N'faramir.vice@bank.local', N'Ithilien Gardens'),
    (N'BM_SHIRE', N'SH001', N'frodo.manager', N'RingBearer#1', N'3100000007', N'Frodo', N'Baggins', N'1986-09-22', N'2024-01-09', N'Branch Manager', 92000, N'0901000007', N'frodo.manager@bank.local', N'Bag End, Hobbiton'),
    (N'VM_SHIRE', N'SH001', N'samwise.vice', N'PoTayToes#2', N'3100000008', N'Samwise', N'Gamgee', N'1987-04-06', N'2024-01-10', N'Vice Manager', 86000, N'0901000008', N'samwise.vice@bank.local', N'Number 3 Bagshot Row'),
    (N'BM_MORDOR', N'MD001', N'sauron.manager', N'OneRing#1', N'3100000009', N'Sauron', N'Mordor', N'1965-11-11', N'2024-01-11', N'Branch Manager', 140000, N'0901000009', N'sauron.manager@bank.local', N'Barad-dur Executive Floor'),
    (N'BM_ROHAN', N'RH001', N'theoden.manager', N'Rohan#1', N'3100000010', N'Theoden', N'King', N'1968-06-18', N'2024-01-12', N'Branch Manager', 103000, N'0901000010', N'theoden.manager@bank.local', N'Golden Hall, Edoras'),
    (N'BM_MINAS', N'MT001', N'boromir.manager', N'Horn#1', N'3100000011', N'Boromir', N'Steward', N'1978-12-03', N'2024-01-13', N'Branch Manager', 111000, N'0901000011', N'boromir.manager@bank.local', N'Captain Quarter, Minas Tirith'),
    (N'BM_MIRKWOOD', N'MW001', N'thranduil.manager', N'Woodland#1', N'3100000012', N'Thranduil', N'Oropherion', N'1969-08-08', N'2024-01-14', N'Branch Manager', 118000, N'0901000012', N'thranduil.manager@bank.local', N'Woodland Realm Palace');

DECLARE
    @ManagerKey NVARCHAR(50), @MBranchCode NVARCHAR(20), @MUsername NVARCHAR(50), @MPassword NVARCHAR(4000),
    @MNationalID NVARCHAR(20), @MFirstName NVARCHAR(50), @MLastName NVARCHAR(50), @MBirthDate DATE, @MHireDate DATE,
    @MJobTitle NVARCHAR(100), @MSalary DECIMAL(18,2), @MPhone NVARCHAR(20), @MEmail NVARCHAR(100), @MAddress NVARCHAR(200),
    @MBranchID INT, @MEmployeeID INT, @MCustomerID INT, @MUserID INT;

DECLARE manager_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT ManagerKey, BranchCode, Username, PasswordValue, NationalID, FirstName, LastName, BirthDate, HireDate, JobTitle, Salary, Phone, Email, Address
FROM #ManagerSeed
ORDER BY ManagerKey;

OPEN manager_cursor;
FETCH NEXT FROM manager_cursor INTO @ManagerKey, @MBranchCode, @MUsername, @MPassword, @MNationalID, @MFirstName, @MLastName, @MBirthDate, @MHireDate, @MJobTitle, @MSalary, @MPhone, @MEmail, @MAddress;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @MBranchID = BranchID FROM dbo.Branch WHERE BranchCode = @MBranchCode;
    EXEC dbo.sp_HighAdmin_HireManager
        @HighAdminUserID = @HighAdminUserID,
        @BranchID = @MBranchID,
        @Username = @MUsername,
        @Password = @MPassword,
        @NationalID = @MNationalID,
        @FirstName = @MFirstName,
        @LastName = @MLastName,
        @BirthDate = @MBirthDate,
        @HireDate = @MHireDate,
        @JobTitle = @MJobTitle,
        @Salary = @MSalary,
        @Phone = @MPhone,
        @Email = @MEmail,
        @Address = @MAddress,
        @EmployeeID = @MEmployeeID OUTPUT,
        @CustomerID = @MCustomerID OUTPUT,
        @UserID = @MUserID OUTPUT;

    INSERT INTO #Managers(ManagerKey, BranchCode, BranchID, EmployeeID, CustomerID, UserID, JobTitle, DisplayName)
    VALUES(@ManagerKey, @MBranchCode, @MBranchID, @MEmployeeID, @MCustomerID, @MUserID, @MJobTitle, CONCAT(@MFirstName, N' ', @MLastName));

    INSERT INTO #AppUsers(UserKey, UserID, CustomerID, AppUserType, DisplayName)
    VALUES(@ManagerKey, @MUserID, @MCustomerID, N'Manager', CONCAT(@MFirstName, N' ', @MLastName));

    FETCH NEXT FROM manager_cursor INTO @ManagerKey, @MBranchCode, @MUsername, @MPassword, @MNationalID, @MFirstName, @MLastName, @MBirthDate, @MHireDate, @MJobTitle, @MSalary, @MPhone, @MEmail, @MAddress;
END;
CLOSE manager_cursor;
DEALLOCATE manager_cursor;

PRINT '4) Branch managers hire ordinary employees and create employee logins...';
IF OBJECT_ID('tempdb..#EmployeeSeed') IS NOT NULL DROP TABLE #EmployeeSeed;
CREATE TABLE #EmployeeSeed
(
    EmployeeKey NVARCHAR(50), ManagerKey NVARCHAR(50), Username NVARCHAR(50), PasswordValue NVARCHAR(4000),
    NationalID NVARCHAR(20), FirstName NVARCHAR(50), LastName NVARCHAR(50), BirthDate DATE, HireDate DATE,
    JobTitle NVARCHAR(100), Salary DECIMAL(18,2), Phone NVARCHAR(20), Email NVARCHAR(100), Address NVARCHAR(200),
    CreateLogin BIT, FinalAction NVARCHAR(20)
);
INSERT INTO #EmployeeSeed VALUES
    (N'EMP_PATRICK', N'BM_BIKINI', N'patrick.teller', N'Starfish#1', N'3200000001', N'Patrick', N'Star', N'1990-02-26', N'2024-02-01', N'Teller', 42000, N'0902000001', N'patrick.teller@bank.local', N'Rock House, Bikini Bottom', 1, N'Active'),
    (N'EMP_SANDY', N'BM_BIKINI', N'sandy.loan', N'Acorn#1', N'3200000002', N'Sandy', N'Cheeks', N'1989-07-17', N'2024-02-01', N'Loan Officer', 62000, N'0902000002', N'sandy.loan@bank.local', N'Treedome, Bikini Bottom', 1, N'Active'),
    (N'EMP_KRABS', N'BM_BIKINI', N'mrkrabs.cash', N'Krabby#1', N'3200000003', N'Eugene', N'Krabs', N'1973-11-30', N'2024-02-02', N'Cash Operations Clerk', 57000, N'0902000003', N'mrkrabs.cash@bank.local', N'Krusty Krab Office', 1, N'Active'),
    (N'EMP_PLANKTON', N'BM_BIKINI', N'plankton.risk', N'ChumBucket#1', N'3200000004', N'Sheldon', N'Plankton', N'1982-04-01', N'2024-02-05', N'Risk Analyst', 59000, N'0902000004', N'plankton.risk@bank.local', N'Chum Bucket Lab', 1, N'Suspend'),
    (N'EMP_PEARL', N'BM_BIKINI', N'pearl.support', N'Whale#1', N'3200000005', N'Pearl', N'Krabs', N'2001-05-12', N'2024-02-07', N'Customer Support Agent', 41000, N'0902000005', N'pearl.support@bank.local', N'Anchor Way, Bikini Bottom', 1, N'Active'),
    (N'EMP_MERRY', N'BM_SHIRE', N'merry.accounts', N'Buckland#1', N'3200000006', N'Meriadoc', N'Brandybuck', N'1993-03-12', N'2024-02-03', N'Account Officer', 52000, N'0902000006', N'merry.accounts@bank.local', N'Buckland Lane', 1, N'Active'),
    (N'EMP_PIPPIN', N'BM_SHIRE', N'pippin.teller', N'Took#1', N'3200000007', N'Peregrin', N'Took', N'1995-09-21', N'2024-02-03', N'Teller', 43000, N'0902000007', N'pippin.teller@bank.local', N'Tookborough Road', 1, N'Active'),
    (N'EMP_ROSIE', N'BM_SHIRE', N'rosie.support', N'Cotton#1', N'3200000008', N'Rosie', N'Cotton', N'1994-10-02', N'2024-02-04', N'Customer Support Agent', 44000, N'0902000008', N'rosie.support@bank.local', N'Bywater Village', 1, N'Active'),
    (N'EMP_BILBO', N'BM_SHIRE', N'bilbo.archive', N'Adventure#1', N'3200000009', N'Bilbo', N'Baggins', N'1960-09-22', N'2024-02-05', N'Archive Clerk', 39000, N'0902000009', N'bilbo.archive@bank.local', N'Bag End Old Study', 1, N'Fire'),
    (N'EMP_ARWEN', N'BM_RIVENDELL', N'arwen.private', N'Evenstar#1', N'3200000010', N'Arwen', N'Undomiel', N'1988-12-12', N'2024-02-03', N'Private Banking Officer', 76000, N'0902000010', N'arwen.private@bank.local', N'Rivendell Terrace', 1, N'Active'),
    (N'EMP_ELROND', N'BM_RIVENDELL', N'elrond.compliance', N'Halfelven#1', N'3200000011', N'Elrond', N'Halfelven', N'1971-01-01', N'2024-02-03', N'Compliance Officer', 88000, N'0902000011', N'elrond.compliance@bank.local', N'Council Chamber Residence', 1, N'Active'),
    (N'EMP_GIMLI', N'BM_RIVENDELL', N'gimli.vault', N'AxeStrong#1', N'3200000012', N'Gimli', N'Gloinsson', N'1980-06-06', N'2024-02-05', N'Vault Officer', 60000, N'0902000012', N'gimli.vault@bank.local', N'Stone Hall Apartment', 1, N'Active'),
    (N'EMP_EOWYN', N'BM_GONDOR', N'eowyn.service', N'Shieldmaiden#1', N'3200000013', N'Eowyn', N'Rohan', N'1987-02-19', N'2024-02-06', N'Service Officer', 56000, N'0902000013', N'eowyn.service@bank.local', N'White City Residence', 1, N'Active'),
    (N'EMP_DENETHOR', N'BM_GONDOR', N'denethor.audit', N'Steward#1', N'3200000014', N'Denethor', N'Steward', N'1962-09-20', N'2024-02-06', N'Internal Audit Clerk', 68000, N'0902000014', N'denethor.audit@bank.local', N'Hall of Records', 1, N'Active'),
    (N'EMP_BEREGOND', N'BM_GONDOR', N'beregond.teller', N'Guard#1', N'3200000015', N'Beregond', N'Guard', N'1991-03-08', N'2024-02-08', N'Teller', 45000, N'0902000015', N'beregond.teller@bank.local', N'Guard Street', 1, N'Active'),
    (N'EMP_GOLLUM', N'BM_MORDOR', N'gollum.collections', N'Precious#1', N'3200000016', N'Smeagol', N'Gollum', N'1977-05-05', N'2024-02-07', N'Collections Clerk', 47000, N'0902000016', N'gollum.collections@bank.local', N'Cave Side Road', 1, N'Active'),
    (N'EMP_SARUMAN', N'BM_MORDOR', N'saruman.risk', N'ManyColors#1', N'3200000017', N'Saruman', N'White', N'1961-04-04', N'2024-02-08', N'Risk Monitoring Officer', 73000, N'0902000017', N'saruman.risk@bank.local', N'Orthanc Annex', 1, N'Active'),
    (N'EMP_SHELOB', N'BM_MORDOR', N'shelob.vault', N'WebStrong#1', N'3200000018', N'Shelob', N'Weaver', N'1985-08-14', N'2024-02-09', N'Vault Assistant', 48000, N'0902000018', N'shelob.vault@bank.local', N'Pass of Cirith Ungol', 0, N'Active'),
    (N'EMP_EOMER', N'BM_ROHAN', N'eomer.field', N'Marshal#1', N'3200000019', N'Eomer', N'Marshal', N'1984-03-03', N'2024-02-10', N'Field Banking Officer', 61000, N'0902000019', N'eomer.field@bank.local', N'Eastfold Quarter', 1, N'Active'),
    (N'EMP_TREEBEARD', N'BM_ROHAN', N'treebeard.advisor', N'Entmoot#1', N'3200000020', N'Treebeard', N'Ent', N'1959-07-07', N'2024-02-10', N'Senior Customer Advisor', 65000, N'0902000020', N'treebeard.advisor@bank.local', N'Fangorn Desk', 1, N'Active'),
    (N'EMP_WORMTONGUE', N'BM_ROHAN', N'wormtongue.ops', N'Whisper#1', N'3200000021', N'Grima', N'Wormtongue', N'1974-01-15', N'2024-02-11', N'Operations Clerk', 44000, N'0902000021', N'wormtongue.ops@bank.local', N'Edoras Back Office', 1, N'Fire'),
    (N'EMP_TOM', N'BM_MINAS', N'tom.teller', N'Bombadil#1', N'3200000022', N'Tom', N'Bombadil', N'1964-12-25', N'2024-02-12', N'Teller', 46000, N'0902000022', N'tom.teller@bank.local', N'Riverbank House', 1, N'Active'),
    (N'EMP_GOLDBERRY', N'BM_MINAS', N'goldberry.service', N'River#1', N'3200000023', N'Goldberry', N'Riverdaughter', N'1986-06-01', N'2024-02-12', N'Service Officer', 52000, N'0902000023', N'goldberry.service@bank.local', N'Water Garden Lane', 1, N'Active'),
    (N'EMP_TAURIEL', N'BM_MIRKWOOD', N'tauriel.private', N'Forest#1', N'3200000024', N'Tauriel', N'Mirkwood', N'1990-11-11', N'2024-02-13', N'Private Banking Officer', 69000, N'0902000024', N'tauriel.private@bank.local', N'Greenwood Path', 1, N'Active'),
    (N'EMP_BARD', N'BM_MIRKWOOD', N'bard.loan', N'Laketown#1', N'3200000025', N'Bard', N'Bowman', N'1982-01-22', N'2024-02-13', N'Loan Officer', 64000, N'0902000025', N'bard.loan@bank.local', N'Lake-town Street', 1, N'Active');

DECLARE
    @EmployeeKey NVARCHAR(50), @HiringManagerKey NVARCHAR(50), @EUsername NVARCHAR(50), @EPassword NVARCHAR(4000),
    @ENationalID NVARCHAR(20), @EFirstName NVARCHAR(50), @ELastName NVARCHAR(50), @EBirthDate DATE, @EHireDate DATE,
    @EJobTitle NVARCHAR(100), @ESalary DECIMAL(18,2), @EPhone NVARCHAR(20), @EEmail NVARCHAR(100), @EAddress NVARCHAR(200),
    @ECreateLogin BIT, @EFinalAction NVARCHAR(20), @HiringManagerUserID INT,
    @EEmployeeID INT, @EEMPBID INT, @EUserID INT, @ECustomerID INT;

DECLARE employee_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT EmployeeKey, ManagerKey, Username, PasswordValue, NationalID, FirstName, LastName, BirthDate, HireDate, JobTitle, Salary, Phone, Email, Address, CreateLogin, FinalAction
FROM #EmployeeSeed
ORDER BY EmployeeKey;

OPEN employee_cursor;
FETCH NEXT FROM employee_cursor INTO @EmployeeKey, @HiringManagerKey, @EUsername, @EPassword, @ENationalID, @EFirstName, @ELastName, @EBirthDate, @EHireDate, @EJobTitle, @ESalary, @EPhone, @EEmail, @EAddress, @ECreateLogin, @EFinalAction;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @HiringManagerUserID = UserID FROM #Managers WHERE ManagerKey = @HiringManagerKey;
    EXEC dbo.sp_Employee_Hire
        @ManagerUserID = @HiringManagerUserID,
        @NationalID = @ENationalID,
        @FirstName = @EFirstName,
        @LastName = @ELastName,
        @HireDate = @EHireDate,
        @JobTitle = @EJobTitle,
        @Salary = @ESalary,
        @Phone = @EPhone,
        @Email = @EEmail,
        @EmployeeID = @EEmployeeID OUTPUT,
        @EMPBID = @EEMPBID OUTPUT;

    SET @EUserID = NULL; SET @ECustomerID = NULL;
    IF @ECreateLogin = 1
    BEGIN
        EXEC dbo.sp_Employee_CreateUserAccount
            @ManagerUserID = @HiringManagerUserID,
            @EmployeeID = @EEmployeeID,
            @Username = @EUsername,
            @Password = @EPassword,
            @BirthDate = @EBirthDate,
            @Phone = @EPhone,
            @Email = @EEmail,
            @Address = @EAddress,
            @UserID = @EUserID OUTPUT,
            @CustomerID = @ECustomerID OUTPUT;

        IF @EUserID IS NULL OR @ECustomerID IS NULL
        BEGIN
            RAISERROR('Employee login creation failed for sample employee %s. Check password length, username uniqueness, and sp_Employee_CreateUserAccount validation rules.', 16, 1, @EmployeeKey);
            RETURN;
        END;

        INSERT INTO #AppUsers(UserKey, UserID, CustomerID, AppUserType, DisplayName)
        VALUES(@EmployeeKey, @EUserID, @ECustomerID, N'Employee', CONCAT(@EFirstName, N' ', @ELastName));
    END;

    IF @EFinalAction = N'Suspend'
        EXEC dbo.sp_Employee_Suspend @ManagerUserID = @HiringManagerUserID, @EmployeeID = @EEmployeeID, @Reason = N'Sample scenario: temporary compliance review.';
    ELSE IF @EFinalAction = N'Fire'
    BEGIN
        DECLARE @SampleTerminationDate DATE = CAST(GETDATE() AS DATE);

        EXEC dbo.sp_Employee_Fire
            @ManagerUserID = @HiringManagerUserID,
            @EmployeeID = @EEmployeeID,
            @TerminationDate = @SampleTerminationDate,
            @Reason = N'Sample scenario: terminated after internal review.';
    END;

    INSERT INTO #Employees(EmployeeKey, ManagerKey, EmployeeID, CustomerID, UserID, JobTitle, FinalAction, DisplayName)
    VALUES(@EmployeeKey, @HiringManagerKey, @EEmployeeID, @ECustomerID, @EUserID, @EJobTitle, @EFinalAction, CONCAT(@EFirstName, N' ', @ELastName));

    FETCH NEXT FROM employee_cursor INTO @EmployeeKey, @HiringManagerKey, @EUsername, @EPassword, @ENationalID, @EFirstName, @ELastName, @EBirthDate, @EHireDate, @EJobTitle, @ESalary, @EPhone, @EEmail, @EAddress, @ECreateLogin, @EFinalAction;
END;
CLOSE employee_cursor;
DEALLOCATE employee_cursor;

PRINT '5) Simulating an employee transfer request: Rosie Cotton moves from Shire to Rivendell...';
DECLARE @RosieUserID INT, @RivendellBranchID INT, @TransferRequestID INT, @FrodoUserID INT, @GaladrielUserID INT;
SELECT @RosieUserID = UserID FROM #Employees WHERE EmployeeKey = N'EMP_ROSIE';
SELECT @RivendellBranchID = BranchID FROM dbo.Branch WHERE BranchCode = N'RV001';
SELECT @FrodoUserID = UserID FROM #Managers WHERE ManagerKey = N'BM_SHIRE';
SELECT @GaladrielUserID = UserID FROM #Managers WHERE ManagerKey = N'BM_RIVENDELL';
EXEC dbo.sp_EmployeeTransfer_RequestByEmployee @UserID = @RosieUserID, @ToBranchID = @RivendellBranchID, @Reason = N'Wants private-banking experience in Rivendell.', @TransferRequestID = @TransferRequestID OUTPUT;
EXEC dbo.sp_EmployeeTransfer_ApproveCurrentManager @ManagerUserID = @FrodoUserID, @TransferRequestID = @TransferRequestID, @Approve = 1, @DecisionNote = N'Approved by current branch manager.';
EXEC dbo.sp_EmployeeTransfer_ApproveDestinationManager @ManagerUserID = @GaladrielUserID, @TransferRequestID = @TransferRequestID, @Approve = 1, @DecisionNote = N'Accepted by destination branch manager.';

PRINT '6) Normal customers sign up through self-service user registration...';
IF OBJECT_ID('tempdb..#CustomerSeed') IS NOT NULL DROP TABLE #CustomerSeed;
CREATE TABLE #CustomerSeed
(
    CustomerKey NVARCHAR(50), Username NVARCHAR(50), PasswordValue NVARCHAR(4000), FirstName NVARCHAR(50), LastName NVARCHAR(50),
    NationalID NVARCHAR(20), BirthDate DATE, Phone NVARCHAR(20), Email NVARCHAR(100), Address NVARCHAR(200)
);
INSERT INTO #CustomerSeed VALUES
    (N'CUST_OLIVIA', N'olivia.harper', N'Olivia#2026', N'Olivia', N'Harper', N'4000000001', N'1988-05-04', N'0913000001', N'olivia.harper@example.com', N'12 Cedar Street'),
    (N'CUST_DANIEL', N'daniel.reed', N'Daniel#2026', N'Daniel', N'Reed', N'4000000002', N'1982-02-14', N'0913000002', N'daniel.reed@example.com', N'44 Lake Avenue'),
    (N'CUST_MAYA', N'maya.foster', N'Maya#2026', N'Maya', N'Foster', N'4000000003', N'1999-08-10', N'0913000003', N'maya.foster@example.com', N'78 Elm Road'),
    (N'CUST_NOAH', N'noah.bennett', N'Noah#2026', N'Noah', N'Bennett', N'4000000004', N'1976-12-01', N'0913000004', N'noah.bennett@example.com', N'9 Market Street'),
    (N'CUST_CHLOE', N'chloe.mason', N'Chloe#2026', N'Chloe', N'Mason', N'4000000005', N'1991-01-18', N'0913000005', N'chloe.mason@example.com', N'51 Orchard Lane'),
    (N'CUST_RYAN', N'ryan.brooks', N'Ryan#2026', N'Ryan', N'Brooks', N'4000000006', N'1985-04-22', N'0913000006', N'ryan.brooks@example.com', N'6 Maple Court'),
    (N'CUST_SOPHIA', N'sophia.lane', N'Sophia#2026', N'Sophia', N'Lane', N'4000000007', N'1979-07-07', N'0913000007', N'sophia.lane@example.com', N'88 King Street'),
    (N'CUST_LIAM', N'liam.carter', N'Liam#2026', N'Liam', N'Carter', N'4000000008', N'2000-09-13', N'0913000008', N'liam.carter@example.com', N'33 University Ave'),
    (N'CUST_EMMA', N'emma.collins', N'Emma#2026', N'Emma', N'Collins', N'4000000009', N'1993-03-23', N'0913000009', N'emma.collins@example.com', N'17 River Road'),
    (N'CUST_ETHAN', N'ethan.price', N'Ethan#2026', N'Ethan', N'Price', N'4000000010', N'1989-11-19', N'0913000010', N'ethan.price@example.com', N'21 Hill Drive'),
    (N'CUST_AVA', N'ava.morgan', N'Ava#2026', N'Ava', N'Morgan', N'4000000011', N'1996-06-06', N'0913000011', N'ava.morgan@example.com', N'4 Willow Close'),
    (N'CUST_JAMES', N'james.parker', N'James#2026', N'James', N'Parker', N'4000000012', N'1980-10-27', N'0913000012', N'james.parker@example.com', N'90 Station Road'),
    (N'CUST_ISABELLA', N'isabella.hughes', N'Isabella#2026', N'Isabella', N'Hughes', N'4000000013', N'1992-12-12', N'0913000013', N'isabella.hughes@example.com', N'18 Garden Square'),
    (N'CUST_LOGAN', N'logan.evans', N'Logan#2026', N'Logan', N'Evans', N'4000000014', N'1987-07-30', N'0913000014', N'logan.evans@example.com', N'61 Bridge Lane'),
    (N'CUST_GRACE', N'grace.murphy', N'Grace#2026', N'Grace', N'Murphy', N'4000000015', N'1998-04-04', N'0913000015', N'grace.murphy@example.com', N'10 Pine Street'),
    (N'CUST_HENRY', N'henry.cooper', N'Henry#2026', N'Henry', N'Cooper', N'4000000016', N'1974-09-09', N'0913000016', N'henry.cooper@example.com', N'31 Plaza Road'),
    (N'CUST_AMELIA', N'amelia.ross', N'Amelia#2026', N'Amelia', N'Ross', N'4000000017', N'1983-08-26', N'0913000017', N'amelia.ross@example.com', N'27 Forest Way'),
    (N'CUST_LUCAS', N'lucas.ward', N'Lucas#2026', N'Lucas', N'Ward', N'4000000018', N'1990-05-15', N'0913000018', N'lucas.ward@example.com', N'70 Sunset Blvd'),
    (N'CUST_MIA', N'mia.richardson', N'Mia#2026', N'Mia', N'Richardson', N'4000000019', N'1997-02-02', N'0913000019', N'mia.richardson@example.com', N'5 Crescent Street'),
    (N'CUST_OSCAR', N'oscar.bailey', N'Oscar#2026', N'Oscar', N'Bailey', N'4000000020', N'1981-01-20', N'0913000020', N'oscar.bailey@example.com', N'38 Harbor Road'),
    (N'CUST_ZOE', N'zoe.cox', N'Zoe#2026', N'Zoe', N'Cox', N'4000000021', N'1994-03-11', N'0913000021', N'zoe.cox@example.com', N'73 Hillcrest Drive'),
    (N'CUST_MASON', N'mason.gray', N'Mason#2026', N'Mason', N'Gray', N'4000000022', N'1986-06-17', N'0913000022', N'mason.gray@example.com', N'45 Industrial Park'),
    (N'CUST_LILY', N'lily.howard', N'Lily#2026', N'Lily', N'Howard', N'4000000023', N'1995-10-05', N'0913000023', N'lily.howard@example.com', N'11 Elm Court'),
    (N'CUST_JACK', N'jack.king', N'Jack#2026', N'Jack', N'King', N'4000000024', N'1978-12-24', N'0913000024', N'jack.king@example.com', N'2 Commerce Street'),
    (N'CUST_NORA', N'nora.scott', N'Nora#2026', N'Nora', N'Scott', N'4000000025', N'1991-04-29', N'0913000025', N'nora.scott@example.com', N'64 Lake View'),
    (N'CUST_LEO', N'leo.green', N'Leo#2026', N'Leo', N'Green', N'4000000026', N'1984-07-08', N'0913000026', N'leo.green@example.com', N'84 Valley Road'),
    (N'CUST_ELLA', N'ella.adams', N'Ella#2026', N'Ella', N'Adams', N'4000000027', N'1998-01-07', N'0913000027', N'ella.adams@example.com', N'29 Meadow Lane'),
    (N'CUST_MAX', N'max.baker', N'Max#2026', N'Max', N'Baker', N'4000000028', N'1988-09-28', N'0913000028', N'max.baker@example.com', N'55 Bakery Street'),
    (N'CUST_IVY', N'ivy.nelson', N'Ivy#2026', N'Ivy', N'Nelson', N'4000000029', N'1992-05-19', N'0913000029', N'ivy.nelson@example.com', N'16 Green Road'),
    (N'CUST_ADAM', N'adam.turner', N'Adam#2026', N'Adam', N'Turner', N'4000000030', N'1977-11-03', N'0913000030', N'adam.turner@example.com', N'7 North Road'),
    (N'CUST_RUBY', N'ruby.phillips', N'Ruby#2026', N'Ruby', N'Phillips', N'4000000031', N'1999-06-24', N'0913000031', N'ruby.phillips@example.com', N'39 Pearl Street'),
    (N'CUST_FINN', N'finn.campbell', N'Finn#2026', N'Finn', N'Campbell', N'4000000032', N'1990-08-08', N'0913000032', N'finn.campbell@example.com', N'23 Windmill Road');

DECLARE
    @CustomerKey NVARCHAR(50), @CUsername NVARCHAR(50), @CPassword NVARCHAR(4000), @CFirstName NVARCHAR(50), @CLastName NVARCHAR(50),
    @CNationalID NVARCHAR(20), @CBirthDate DATE, @CPhone NVARCHAR(20), @CEmail NVARCHAR(100), @CAddress NVARCHAR(200),
    @CUserID INT, @CCustomerID INT;

DECLARE customer_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT CustomerKey, Username, PasswordValue, FirstName, LastName, NationalID, BirthDate, Phone, Email, Address
FROM #CustomerSeed
ORDER BY CustomerKey;

OPEN customer_cursor;
FETCH NEXT FROM customer_cursor INTO @CustomerKey, @CUsername, @CPassword, @CFirstName, @CLastName, @CNationalID, @CBirthDate, @CPhone, @CEmail, @CAddress;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_User_SignUp
        @Username = @CUsername,
        @Password = @CPassword,
        @FirstName = @CFirstName,
        @LastName = @CLastName,
        @NationalID = @CNationalID,
        @BirthDate = @CBirthDate,
        @Phone = @CPhone,
        @Email = @CEmail,
        @Address = @CAddress,
        @UserID = @CUserID OUTPUT,
        @CustomerID = @CCustomerID OUTPUT;

    IF @CUserID IS NULL OR @CCustomerID IS NULL
    BEGIN
        RAISERROR('Customer signup failed for sample customer %s. Check password length, username uniqueness, and sp_User_SignUp validation rules.', 16, 1, @CustomerKey);
        RETURN;
    END;

    INSERT INTO #AppUsers(UserKey, UserID, CustomerID, AppUserType, DisplayName)
    VALUES(@CustomerKey, @CUserID, @CCustomerID, N'Customer', CONCAT(@CFirstName, N' ', @CLastName));

    FETCH NEXT FROM customer_cursor INTO @CustomerKey, @CUsername, @CPassword, @CFirstName, @CLastName, @CNationalID, @CBirthDate, @CPhone, @CEmail, @CAddress;
END;
CLOSE customer_cursor;
DEALLOCATE customer_cursor;

PRINT '7) Customers and staff open accounts through self-service account opening...';
IF OBJECT_ID('tempdb..#AccountPlan') IS NOT NULL DROP TABLE #AccountPlan;
CREATE TABLE #AccountPlan
(
    AccountKey NVARCHAR(50), UserKey NVARCHAR(50), BranchCode NVARCHAR(20), AccountTypeName NVARCHAR(50), InitialDeposit DECIMAL(18,2)
);
INSERT INTO #AccountPlan VALUES
    (N'A_OLIVIA_SAV', N'CUST_OLIVIA', N'BB001', N'Savings Basic', 6500),
    (N'A_OLIVIA_CUR', N'CUST_OLIVIA', N'GD001', N'Current Account', 2500),
    (N'A_DANIEL_CUR', N'CUST_DANIEL', N'RV001', N'Current Account', 8500),
    (N'A_DANIEL_PRE', N'CUST_DANIEL', N'RV001', N'Savings Premium', 6000),
    (N'A_MAYA_STU', N'CUST_MAYA', N'SH001', N'Student Account', 1200),
    (N'A_NOAH_BUS', N'CUST_NOAH', N'GD001', N'Business Account', 35000),
    (N'A_NOAH_SAV', N'CUST_NOAH', N'GD001', N'Savings Basic', 4000),
    (N'A_CHLOE_SAV', N'CUST_CHLOE', N'BB001', N'Savings Basic', 7000),
    (N'A_RYAN_PRE', N'CUST_RYAN', N'SH001', N'Savings Premium', 15000),
    (N'A_RYAN_CUR', N'CUST_RYAN', N'SH001', N'Current Account', 3000),
    (N'A_SOPHIA_BUS', N'CUST_SOPHIA', N'RV001', N'Business Account', 60000),
    (N'A_SOPHIA_PRE', N'CUST_SOPHIA', N'BB001', N'Savings Premium', 8000),
    (N'A_LIAM_STU', N'CUST_LIAM', N'BB001', N'Student Account', 1300),
    (N'A_EMMA_CUR', N'CUST_EMMA', N'RH001', N'Current Account', 7000),
    (N'A_ETHAN_SAV', N'CUST_ETHAN', N'GD001', N'Savings Basic', 5200),
    (N'A_AVA_SAV', N'CUST_AVA', N'MW001', N'Savings Basic', 4400),
    (N'A_AVA_CUR', N'CUST_AVA', N'MW001', N'Current Account', 2600),
    (N'A_JAMES_STU', N'CUST_JAMES', N'SH001', N'Student Account', 900),
    (N'A_ISABELLA_PRE', N'CUST_ISABELLA', N'RV001', N'Savings Premium', 11000),
    (N'A_ISABELLA_CUR', N'CUST_ISABELLA', N'GD001', N'Current Account', 3400),
    (N'A_LOGAN_SAV', N'CUST_LOGAN', N'BB001', N'Savings Basic', 2000),
    (N'A_GRACE_STU', N'CUST_GRACE', N'SH001', N'Student Account', 600),
    (N'A_HENRY_BUS', N'CUST_HENRY', N'MD001', N'Business Account', 42000),
    (N'A_HENRY_RES', N'CUST_HENRY', N'MT001', N'Golden Reserve', 25000),
    (N'A_AMELIA_SAV', N'CUST_AMELIA', N'RH001', N'Savings Basic', 9000),
    (N'A_LUCAS_PRE', N'CUST_LUCAS', N'GD001', N'Savings Premium', 15000),
    (N'A_MIA_CUR', N'CUST_MIA', N'MT001', N'Current Account', 7000),
    (N'A_OSCAR_BUS', N'CUST_OSCAR', N'MT001', N'Business Account', 85000),
    (N'A_OSCAR_SAV', N'CUST_OSCAR', N'MT001', N'Savings Basic', 10000),
    (N'A_ZOE_SAV', N'CUST_ZOE', N'MW001', N'Savings Basic', 5500),
    (N'A_MASON_BUS', N'CUST_MASON', N'MD001', N'Business Account', 70000),
    (N'A_LILY_STU', N'CUST_LILY', N'BB001', N'Student Account', 1500),
    (N'A_JACK_CUR', N'CUST_JACK', N'RH001', N'Current Account', 6800),
    (N'A_NORA_PRE', N'CUST_NORA', N'RV001', N'Savings Premium', 12500),
    (N'A_LEO_SAV', N'CUST_LEO', N'SH001', N'Savings Basic', 3000),
    (N'A_ELLA_STU', N'CUST_ELLA', N'MW001', N'Student Account', 800),
    (N'A_MAX_BUS', N'CUST_MAX', N'GD001', N'Business Account', 95000),
    (N'A_IVY_SAV', N'CUST_IVY', N'BB001', N'Savings Basic', 4500),
    (N'A_ADAM_RES', N'CUST_ADAM', N'RV001', N'Golden Reserve', 50000),
    (N'A_RUBY_CUR', N'CUST_RUBY', N'SH001', N'Current Account', 2500),
    (N'A_FINN_SAV', N'CUST_FINN', N'RH001', N'Savings Basic', 7700),
    (N'A_SPONGEBOB_CUR', N'BM_BIKINI', N'BB001', N'Current Account', 9000),
    (N'A_SQUIDWARD_PRE', N'VM_BIKINI', N'BB001', N'Savings Premium', 13000),
    (N'A_ARAGORN_RES', N'BM_GONDOR', N'GD001', N'Golden Reserve', 35000),
    (N'A_GALADRIEL_RES', N'BM_RIVENDELL', N'RV001', N'Golden Reserve', 80000),
    (N'A_PATRICK_STU', N'EMP_PATRICK', N'BB001', N'Student Account', 600),
    (N'A_SANDY_SAV', N'EMP_SANDY', N'BB001', N'Savings Basic', 5000),
    (N'A_MERRY_CUR', N'EMP_MERRY', N'SH001', N'Current Account', 2200),
    (N'A_ARWEN_PRE', N'EMP_ARWEN', N'RV001', N'Savings Premium', 6000),
    (N'A_EOWYN_SAV', N'EMP_EOWYN', N'GD001', N'Savings Basic', 4800),
    (N'A_GOLLUM_SAV', N'EMP_GOLLUM', N'MD001', N'Savings Basic', 3500);

DECLARE
    @AccountKey NVARCHAR(50), @AUserKey NVARCHAR(50), @ABranchCode NVARCHAR(20), @ATypeName NVARCHAR(50), @InitialDeposit DECIMAL(18,2),
    @AUserID INT, @ACustomerID INT, @ABranchID INT, @ATypeID INT, @AccountID INT, @AccountNumber NVARCHAR(12), @InitialTxID INT, @ReadyAt DATETIME;

DECLARE account_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT AccountKey, UserKey, BranchCode, AccountTypeName, InitialDeposit
FROM #AccountPlan
ORDER BY AccountKey;

OPEN account_cursor;
FETCH NEXT FROM account_cursor INTO @AccountKey, @AUserKey, @ABranchCode, @ATypeName, @InitialDeposit;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @AUserID = NULL; SET @ACustomerID = NULL; SET @ABranchID = NULL; SET @ATypeID = NULL; SET @AccountID = NULL; SET @AccountNumber = NULL; SET @InitialTxID = NULL; SET @ReadyAt = NULL;
    SELECT @AUserID = UserID, @ACustomerID = CustomerID FROM #AppUsers WHERE UserKey = @AUserKey;
    SELECT @ABranchID = BranchID FROM dbo.Branch WHERE BranchCode = @ABranchCode;
    SELECT @ATypeID = AccountTypeID FROM dbo.AccountType WHERE TypeName = @ATypeName;

    EXEC dbo.sp_Account_Open
        @UserID = @AUserID,
        @BranchID = @ABranchID,
        @AccountTypeID = @ATypeID,
        @InitialDeposit = @InitialDeposit,
        @AccountID = @AccountID OUTPUT,
        @AccountNumber = @AccountNumber OUTPUT,
        @InitialDepositTransactionID = @InitialTxID OUTPUT,
        @InitialDepositReadyToCompleteAt = @ReadyAt OUTPUT;

    INSERT INTO #Accounts(AccountKey, UserKey, AccountID, AccountNumber, CustomerID, BranchCode, AccountTypeName)
    VALUES(@AccountKey, @AUserKey, @AccountID, @AccountNumber, @ACustomerID, @ABranchCode, @ATypeName);

    IF @InitialTxID IS NOT NULL
        INSERT INTO #TxCreated(TxKey, TransactionID, TxScenario) VALUES(CONCAT(N'INIT_', @AccountKey), @InitialTxID, N'InitialDeposit');

    FETCH NEXT FROM account_cursor INTO @AccountKey, @AUserKey, @ABranchCode, @ATypeName, @InitialDeposit;
END;
CLOSE account_cursor;
DEALLOCATE account_cursor;

-- For demo data we complete initial deposits immediately.
UPDATE dbo.Transactions
SET ReadyToCompleteAt = DATEADD(MINUTE, -10, GETDATE())
WHERE TransactionStatus = N'Pending'
  AND TransactionID IN (SELECT TransactionID FROM #TxCreated WHERE TxScenario = N'InitialDeposit');
EXEC dbo.sp_Transaction_ProcessPendingBatch;

PRINT '8) Simulating varied deposits, withdrawals, transfers, cancellations, failures, and reversals...';
IF OBJECT_ID('tempdb..#TransactionPlan') IS NOT NULL DROP TABLE #TransactionPlan;
CREATE TABLE #TransactionPlan
(
    TxKey NVARCHAR(50), ActionName NVARCHAR(20), ActorUserKey NVARCHAR(50), FromAccountKey NVARCHAR(50) NULL,
    ToAccountKey NVARCHAR(50) NULL, Amount DECIMAL(18,2), Description NVARCHAR(200), Outcome NVARCHAR(30)
);
INSERT INTO #TransactionPlan VALUES
    (N'TX01', N'Deposit', N'CUST_OLIVIA', NULL, N'A_OLIVIA_SAV', 750, N'Mobile check deposit', N'CompleteNow'),
    (N'TX02', N'Withdrawal', N'CUST_OLIVIA', N'A_OLIVIA_CUR', NULL, 300, N'ATM withdrawal', N'CompleteNow'),
    (N'TX03', N'Transfer', N'CUST_DANIEL', N'A_DANIEL_CUR', N'A_MAYA_STU', 1250, N'Rent support transfer', N'CompleteNow'),
    (N'TX04', N'Deposit', N'EMP_KRABS', NULL, N'A_NOAH_BUS', 4000, N'Teller-assisted business cash deposit', N'CompleteNow'),
    (N'TX05', N'Withdrawal', N'CUST_NOAH', N'A_NOAH_BUS', NULL, 10000, N'Supplier cash withdrawal', N'CompleteNow'),
    (N'TX06', N'Transfer', N'CUST_SOPHIA', N'A_SOPHIA_BUS', N'A_RYAN_PRE', 12000, N'Vendor settlement transfer', N'CompleteNow'),
    (N'TX07', N'Deposit', N'CUST_CHLOE', NULL, N'A_CHLOE_SAV', 500, N'Small savings deposit', N'CompleteNow'),
    (N'TX08', N'Transfer', N'CUST_RYAN', N'A_RYAN_PRE', N'A_LIAM_STU', 850, N'Family support transfer', N'CompleteNow'),
    (N'TX09', N'Withdrawal', N'CUST_EMMA', N'A_EMMA_CUR', NULL, 750, N'Cardless cash withdrawal', N'CompleteNow'),
    (N'TX10', N'Deposit', N'CUST_ETHAN', NULL, N'A_ETHAN_SAV', 900, N'Salary top-up deposit', N'CompleteNow'),
    (N'TX11', N'Transfer', N'CUST_HENRY', N'A_HENRY_BUS', N'A_OSCAR_BUS', 18000, N'Business-to-business payment', N'CompleteNow'),
    (N'TX12', N'Withdrawal', N'CUST_OSCAR', N'A_OSCAR_BUS', NULL, 14000, N'Payroll withdrawal', N'CompleteNow'),
    (N'TX13', N'Deposit', N'EMP_ARWEN', NULL, N'A_NORA_PRE', 2200, N'Private banking deposit assistance', N'CompleteNow'),
    (N'TX14', N'Transfer', N'CUST_ADAM', N'A_ADAM_RES', N'A_GALADRIEL_RES', 15000, N'High-value internal transfer', N'CompleteNow'),
    (N'TX15', N'Withdrawal', N'CUST_MAX', N'A_MAX_BUS', NULL, 20000, N'Business expense withdrawal', N'CompleteNow'),
    (N'TX16', N'Deposit', N'CUST_IVY', NULL, N'A_IVY_SAV', 650, N'Branch counter deposit', N'CompleteNow'),
    (N'TX17', N'Transfer', N'CUST_FINN', N'A_FINN_SAV', N'A_JACK_CUR', 1200, N'Shared trip reimbursement', N'CompleteNow'),
    (N'TX18', N'Deposit', N'CUST_LILY', NULL, N'A_LILY_STU', 300, N'Student savings cash-in', N'CompleteNow'),
    (N'TX19', N'Withdrawal', N'EMP_SANDY', N'A_SANDY_SAV', NULL, 650, N'Employee personal ATM withdrawal', N'CompleteNow'),
    (N'TX20', N'Transfer', N'BM_BIKINI', N'A_SPONGEBOB_CUR', N'A_PATRICK_STU', 400, N'Staff lunch reimbursement', N'CompleteNow'),
    (N'TX21', N'Deposit', N'CUST_CHLOE', NULL, N'A_CHLOE_SAV', 125000, N'Large pending deposit kept for queue demo', N'LeavePending'),
    (N'TX22', N'Transfer', N'CUST_NOAH', N'A_NOAH_BUS', N'A_SOPHIA_BUS', 30000, N'Large pending supplier transfer', N'LeavePending'),
    (N'TX23', N'Transfer', N'CUST_RYAN', N'A_RYAN_CUR', N'A_LIAM_STU', 1000, N'Customer changed mind before completion', N'CancelPending'),
    (N'TX24', N'Withdrawal', N'CUST_ETHAN', N'A_ETHAN_SAV', NULL, 500, N'Fraud check failure by temporary freeze', N'FailByFreeze'),
    (N'TX25', N'Deposit', N'CUST_DANIEL', NULL, N'A_DANIEL_PRE', 600, N'Deposit later reversed by operations', N'ReverseCompleted'),
    (N'TX26', N'Transfer', N'CUST_AMELIA', N'A_AMELIA_SAV', N'A_FINN_SAV', 1700, N'Family transfer', N'CompleteNow'),
    (N'TX27', N'Withdrawal', N'CUST_NORA', N'A_NORA_PRE', NULL, 950, N'ATM withdrawal', N'CompleteNow'),
    (N'TX28', N'Deposit', N'CUST_LEO', NULL, N'A_LEO_SAV', 400, N'Cash deposit', N'CompleteNow'),
    (N'TX29', N'Transfer', N'CUST_MASON', N'A_MASON_BUS', N'A_HENRY_BUS', 22000, N'Industrial supply payment', N'CompleteNow'),
    (N'TX30', N'Withdrawal', N'CUST_ADAM', N'A_ADAM_RES', NULL, 5000, N'Reserve account withdrawal', N'CompleteNow');

DECLARE
    @TxKey NVARCHAR(50), @ActionName NVARCHAR(20), @ActorUserKey NVARCHAR(50), @FromAccountKey NVARCHAR(50), @ToAccountKey NVARCHAR(50),
    @TxAmount DECIMAL(18,2), @TxDescription NVARCHAR(200), @Outcome NVARCHAR(30), @ActorUserID INT, @ActorEmployeeID INT,
    @FromAccountID INT, @ToAccountID INT, @TxID INT, @TxReady DATETIME, @ResultStatus NVARCHAR(20), @ResultMessage NVARCHAR(400),
    @OperationsUserID INT;

SELECT @OperationsUserID = UserID FROM #Managers WHERE ManagerKey = N'BM_BIKINI';

DECLARE tx_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT TxKey, ActionName, ActorUserKey, FromAccountKey, ToAccountKey, Amount, Description, Outcome
FROM #TransactionPlan
ORDER BY TxKey;

OPEN tx_cursor;
FETCH NEXT FROM tx_cursor INTO @TxKey, @ActionName, @ActorUserKey, @FromAccountKey, @ToAccountKey, @TxAmount, @TxDescription, @Outcome;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @ActorUserID = NULL; SET @ActorEmployeeID = NULL; SET @FromAccountID = NULL; SET @ToAccountID = NULL; SET @TxID = NULL; SET @TxReady = NULL;
    SELECT @ActorUserID = UserID FROM #AppUsers WHERE UserKey = @ActorUserKey;
    SELECT @ActorEmployeeID = EmployeeID FROM dbo.Users WHERE UserID = @ActorUserID;
    SELECT @FromAccountID = AccountID FROM #Accounts WHERE AccountKey = @FromAccountKey;
    SELECT @ToAccountID = AccountID FROM #Accounts WHERE AccountKey = @ToAccountKey;

    IF @ActionName = N'Deposit'
    BEGIN
        EXEC dbo.sp_Transaction_Deposit
            @AccountID = @ToAccountID,
            @Amount = @TxAmount,
            @EmployeeID = @ActorEmployeeID,
            @Description = @TxDescription,
            @TransactionID = @TxID OUTPUT,
            @ReadyToCompleteAt = @TxReady OUTPUT,
            @UserID = @ActorUserID;
    END
    ELSE IF @ActionName = N'Withdrawal'
    BEGIN
        EXEC dbo.sp_Transaction_Withdrawal
            @AccountID = @FromAccountID,
            @Amount = @TxAmount,
            @EmployeeID = @ActorEmployeeID,
            @Description = @TxDescription,
            @TransactionID = @TxID OUTPUT,
            @ReadyToCompleteAt = @TxReady OUTPUT,
            @UserID = @ActorUserID;
    END
    ELSE IF @ActionName = N'Transfer'
    BEGIN
        EXEC dbo.sp_Transaction_Transfer
            @FromAccountID = @FromAccountID,
            @ToAccountID = @ToAccountID,
            @Amount = @TxAmount,
            @EmployeeID = @ActorEmployeeID,
            @Description = @TxDescription,
            @TransactionID = @TxID OUTPUT,
            @ReadyToCompleteAt = @TxReady OUTPUT,
            @UserID = @ActorUserID;
    END

    INSERT INTO #TxCreated(TxKey, TransactionID, TxScenario)
    VALUES(@TxKey, @TxID, @Outcome);

    IF @Outcome = N'CompleteNow'
    BEGIN
        UPDATE dbo.Transactions SET ReadyToCompleteAt = DATEADD(MINUTE, -10, GETDATE()) WHERE TransactionID = @TxID;
        EXEC dbo.sp_Transaction_ProcessPendingBatch;
    END
    ELSE IF @Outcome = N'CancelPending'
    BEGIN
        EXEC dbo.sp_Transaction_Reverse @TransactionID = @TxID, @ReasonDescription = N'Sample scenario cancellation before completion.', @UserID = @OperationsUserID;
    END
    ELSE IF @Outcome = N'FailByFreeze'
    BEGIN
        EXEC dbo.sp_Account_Freeze @AccountID = @FromAccountID, @UserID = @OperationsUserID, @ReasonDescription = N'Sample scenario: freeze before pending withdrawal finalizes.';
        UPDATE dbo.Transactions SET ReadyToCompleteAt = DATEADD(MINUTE, -10, GETDATE()) WHERE TransactionID = @TxID;
        EXEC dbo.sp_Transaction_ProcessPendingBatch;
        EXEC dbo.sp_Account_Unfreeze @AccountID = @FromAccountID, @UserID = @OperationsUserID, @ReasonDescription = N'Sample scenario: fraud hold removed after failed transaction demo.';
    END
    ELSE IF @Outcome = N'ReverseCompleted'
    BEGIN
        UPDATE dbo.Transactions SET ReadyToCompleteAt = DATEADD(MINUTE, -10, GETDATE()) WHERE TransactionID = @TxID;
        EXEC dbo.sp_Transaction_ProcessPendingBatch;
        EXEC dbo.sp_Transaction_Reverse @TransactionID = @TxID, @ReasonDescription = N'Sample scenario: completed deposit reversed by operations.', @UserID = @OperationsUserID;
    END
    -- LeavePending intentionally remains pending with its original future ReadyToCompleteAt.

    FETCH NEXT FROM tx_cursor INTO @TxKey, @ActionName, @ActorUserKey, @FromAccountKey, @ToAccountKey, @TxAmount, @TxDescription, @Outcome;
END;
CLOSE tx_cursor;
DEALLOCATE tx_cursor;

PRINT '9) Creating account status cases: dormant, reactivated, frozen, and closed...';
DECLARE @DormantAccount1 INT, @DormantAccount2 INT, @CloseAccountID INT, @FreezeAccountID INT, @ReactivationTxID INT, @ReactivationReady DATETIME;
SELECT @DormantAccount1 = AccountID FROM #Accounts WHERE AccountKey = N'A_ISABELLA_PRE';
SELECT @DormantAccount2 = AccountID FROM #Accounts WHERE AccountKey = N'A_LOGAN_SAV';
SELECT @CloseAccountID = AccountID FROM #Accounts WHERE AccountKey = N'A_JAMES_STU';
SELECT @FreezeAccountID = AccountID FROM #Accounts WHERE AccountKey = N'A_AVA_CUR';

UPDATE dbo.Account SET AccountStatus = N'Dormant', OpenDate = DATEADD(MONTH, -16, CAST(GETDATE() AS DATE)) WHERE AccountID IN (@DormantAccount1, @DormantAccount2);

-- Incoming deposit reactivates one dormant account; the other remains Dormant.
DECLARE @IsabellaUserID INT;
SELECT @IsabellaUserID = UserID FROM #AppUsers WHERE UserKey = N'CUST_ISABELLA';
EXEC dbo.sp_Transaction_Deposit @AccountID = @DormantAccount1, @Amount = 700, @EmployeeID = NULL, @Description = N'Dormant account reactivation deposit', @TransactionID = @ReactivationTxID OUTPUT, @ReadyToCompleteAt = @ReactivationReady OUTPUT, @UserID = @IsabellaUserID;
UPDATE dbo.Transactions SET ReadyToCompleteAt = DATEADD(MINUTE, -10, GETDATE()) WHERE TransactionID = @ReactivationTxID;
EXEC dbo.sp_Transaction_ProcessPendingBatch;

EXEC dbo.sp_Account_Freeze @AccountID = @FreezeAccountID, @UserID = @OperationsUserID, @ReasonDescription = N'Sample scenario: KYC documents need review.';
EXEC dbo.sp_Account_Close @AccountID = @CloseAccountID, @UserID = @OperationsUserID, @ReasonDescription = N'Sample scenario: customer requested account closure.';

PRINT '10) Creating loans, installment payments, late cases, and default cases...';
IF OBJECT_ID('tempdb..#LoanPlan') IS NOT NULL DROP TABLE #LoanPlan;
CREATE TABLE #LoanPlan
(
    LoanKey NVARCHAR(50), CustomerKey NVARCHAR(50), BranchCode NVARCHAR(20), CreatorUserKey NVARCHAR(50),
    LoanAmount DECIMAL(18,2), InterestRate DECIMAL(5,2), NumberOfInstallments INT, StartDate DATE, Scenario NVARCHAR(30),
    PayAccountKey NVARCHAR(50) NULL
);
INSERT INTO #LoanPlan VALUES
    (N'LN_NOAH_WORKING_CAPITAL', N'CUST_NOAH', N'GD001', N'BM_GONDOR', 25000, 8.5, 12, '2026-05-01', N'PayFirst', N'A_NOAH_SAV'),
    (N'LN_SOPHIA_DEFAULT_CASE', N'CUST_SOPHIA', N'RV001', N'BM_RIVENDELL', 50000, 9.5, 10, '2025-10-01', N'DefaultOverdue', NULL),
    (N'LN_LUCAS_PERSONAL', N'CUST_LUCAS', N'GD001', N'BM_GONDOR', 18000, 7.2, 18, '2026-04-01', N'PayFirst', N'A_LUCAS_PRE'),
    (N'LN_OSCAR_EXPANSION', N'CUST_OSCAR', N'MT001', N'BM_MINAS', 120000, 10.0, 24, '2026-03-01', N'PayTwo', N'A_OSCAR_BUS'),
    (N'LN_MIA_SMALL', N'CUST_MIA', N'MT001', N'BM_MINAS', 5000, 6.0, 6, '2026-07-01', N'ActiveNoPayment', NULL),
    (N'LN_JACK_DEFAULT_CASE', N'CUST_JACK', N'RH001', N'BM_ROHAN', 30000, 9.0, 12, '2025-09-01', N'DefaultOverdue', NULL),
    (N'LN_DANIEL_LATE_CASE', N'CUST_DANIEL', N'RV001', N'BM_RIVENDELL', 15000, 7.0, 12, '2026-02-01', N'LateButActive', NULL),
    (N'LN_AMELIA_CAR', N'CUST_AMELIA', N'RH001', N'BM_ROHAN', 22000, 8.0, 18, '2026-06-01', N'PayFirst', N'A_AMELIA_SAV');

DECLARE
    @LoanKey NVARCHAR(50), @LoanCustomerKey NVARCHAR(50), @LoanBranchCode NVARCHAR(20), @CreatorUserKey NVARCHAR(50),
    @LoanAmount DECIMAL(18,2), @InterestRate DECIMAL(5,2), @NInstallments INT, @LoanStartDate DATE, @LoanScenario NVARCHAR(30), @PayAccountKey NVARCHAR(50),
    @LoanCustomerID INT, @LoanBranchID INT, @CreatorUserID INT, @LoanID INT,
    @InstallmentID INT, @PayAccountID INT, @PayTxID INT, @PayReady DATETIME;

DECLARE loan_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT LoanKey, CustomerKey, BranchCode, CreatorUserKey, LoanAmount, InterestRate, NumberOfInstallments, StartDate, Scenario, PayAccountKey
FROM #LoanPlan
ORDER BY LoanKey;

OPEN loan_cursor;
FETCH NEXT FROM loan_cursor INTO @LoanKey, @LoanCustomerKey, @LoanBranchCode, @CreatorUserKey, @LoanAmount, @InterestRate, @NInstallments, @LoanStartDate, @LoanScenario, @PayAccountKey;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @LoanCustomerID = NULL; SET @LoanBranchID = NULL; SET @CreatorUserID = NULL; SET @LoanID = NULL; SET @InstallmentID = NULL; SET @PayAccountID = NULL; SET @PayTxID = NULL; SET @PayReady = NULL;
    SELECT @LoanCustomerID = CustomerID FROM #AppUsers WHERE UserKey = @LoanCustomerKey;
    SELECT @LoanBranchID = BranchID FROM dbo.Branch WHERE BranchCode = @LoanBranchCode;
    SELECT @CreatorUserID = UserID FROM #AppUsers WHERE UserKey = @CreatorUserKey;

    EXEC dbo.sp_Loan_Create
        @CustomerID = @LoanCustomerID,
        @BranchID = @LoanBranchID,
        @LoanAmount = @LoanAmount,
        @InterestRate = @InterestRate,
        @NumberOfInstallments = @NInstallments,
        @StartDate = @LoanStartDate,
        @LoanID = @LoanID OUTPUT,
        @UserID = @CreatorUserID;

    INSERT INTO #Loans(LoanKey, LoanID, CustomerKey, Scenario)
    VALUES(@LoanKey, @LoanID, @LoanCustomerKey, @LoanScenario);

    IF @LoanScenario IN (N'PayFirst', N'PayTwo')
    BEGIN
        SELECT TOP(1) @InstallmentID = InstallmentID FROM dbo.Installment WHERE LoanID = @LoanID AND InstallmentStatus = N'Pending' ORDER BY DueDate;
        IF @PayAccountKey IS NOT NULL
            SELECT @PayAccountID = AccountID FROM #Accounts WHERE AccountKey = @PayAccountKey;
        ELSE
            SELECT TOP(1) @PayAccountID = AccountID FROM #Accounts WHERE UserKey = @LoanCustomerKey ORDER BY AccountID;
        SELECT @CreatorUserID = UserID FROM #AppUsers WHERE UserKey = @LoanCustomerKey;
        EXEC dbo.sp_Loan_PayInstallment @InstallmentID = @InstallmentID, @FromAccountID = @PayAccountID, @EmployeeID = NULL, @TransactionID = @PayTxID OUTPUT, @ReadyToCompleteAt = @PayReady OUTPUT, @UserID = @CreatorUserID;
        UPDATE dbo.Transactions SET ReadyToCompleteAt = DATEADD(MINUTE, -10, GETDATE()) WHERE TransactionID = @PayTxID;
        EXEC dbo.sp_Transaction_ProcessPendingBatch;

        IF @LoanScenario = N'PayTwo'
        BEGIN
            SELECT TOP(1) @InstallmentID = InstallmentID FROM dbo.Installment WHERE LoanID = @LoanID AND InstallmentStatus = N'Pending' ORDER BY DueDate;
            EXEC dbo.sp_Loan_PayInstallment @InstallmentID = @InstallmentID, @FromAccountID = @PayAccountID, @EmployeeID = NULL, @TransactionID = @PayTxID OUTPUT, @ReadyToCompleteAt = @PayReady OUTPUT, @UserID = @CreatorUserID;
            UPDATE dbo.Transactions SET ReadyToCompleteAt = DATEADD(MINUTE, -10, GETDATE()) WHERE TransactionID = @PayTxID;
            EXEC dbo.sp_Transaction_ProcessPendingBatch;
        END
    END
    ELSE IF @LoanScenario = N'LateButActive'
    BEGIN
        SELECT TOP(1) @InstallmentID = InstallmentID FROM dbo.Installment WHERE LoanID = @LoanID ORDER BY DueDate;
        UPDATE dbo.Installment SET DueDate = DATEADD(DAY, -35, CAST(GETDATE() AS DATE)), InstallmentStatus = N'Late' WHERE InstallmentID = @InstallmentID;
    END

    FETCH NEXT FROM loan_cursor INTO @LoanKey, @LoanCustomerKey, @LoanBranchCode, @CreatorUserKey, @LoanAmount, @InterestRate, @NInstallments, @LoanStartDate, @LoanScenario, @PayAccountKey;
END;
CLOSE loan_cursor;
DEALLOCATE loan_cursor;

-- Make selected default-demo loans more than 90 days overdue and run the overdue processor.
UPDATE i
SET DueDate = DATEADD(DAY, -120, CAST(GETDATE() AS DATE))
FROM dbo.Installment i
INNER JOIN #Loans l ON l.LoanID = i.LoanID
WHERE l.Scenario = N'DefaultOverdue'
  AND i.InstallmentStatus <> N'Paid';
EXEC dbo.sp_Loan_ProcessOverdueInstallments;

PRINT '11) Applying monthly interest to eligible active interest-bearing accounts...';
EXEC dbo.sp_Account_ApplyMonthlyInterest;

PRINT '12) Final sample data summary...';
SELECT 'Branches' AS Entity, COUNT(*) AS TotalRows FROM dbo.Branch
UNION ALL SELECT 'Customers', COUNT(*) FROM dbo.Customer
UNION ALL SELECT 'Employees', COUNT(*) FROM dbo.Employee
UNION ALL SELECT 'Users', COUNT(*) FROM dbo.Users
UNION ALL SELECT 'Accounts', COUNT(*) FROM dbo.Account
UNION ALL SELECT 'Transactions', COUNT(*) FROM dbo.Transactions
UNION ALL SELECT 'Loans', COUNT(*) FROM dbo.Loan
UNION ALL SELECT 'Installments', COUNT(*) FROM dbo.Installment
UNION ALL SELECT 'AuditLog', COUNT(*) FROM dbo.AuditLog
UNION ALL SELECT 'BranchLedger', COUNT(*) FROM dbo.BranchLedger;

SELECT AccountStatus, COUNT(*) AS AccountCount, SUM(Balance) AS TotalBalance
FROM dbo.Account
GROUP BY AccountStatus
ORDER BY AccountStatus;

SELECT TransactionStatus, COUNT(*) AS TransactionCount, SUM(Amount) AS TotalAmount
FROM dbo.Transactions
GROUP BY TransactionStatus
ORDER BY TransactionStatus;

SELECT EmpStatus, COUNT(*) AS EmployeeCount
FROM dbo.Employee
GROUP BY EmpStatus
ORDER BY EmpStatus;

SELECT LoanStatus, COUNT(*) AS LoanCount
FROM dbo.Loan
GROUP BY LoanStatus
ORDER BY LoanStatus;

PRINT 'Realistic sample scenario completed successfully.';
