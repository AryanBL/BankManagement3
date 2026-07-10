/* =========================================================
   TableCreation_FULL_FINAL_SAFE_REBUILD.sql
   ---------------------------------------------------------
   Final integrated clean-rebuild table-creation script for
   the BankManagement project.

   PURPOSE:
   - Safely reset an existing development/test database by
     removing dbo foreign keys and project objects first.
   - Recreate the base schema WITH the final module columns and
     workflow tables that were previously added later by support
     scripts.

   WARNING:
   This script deletes existing project data. Use only for a fresh
   rebuild/testing database, not for production migration.

   AFTER THIS FILE:
   The support/rule scripts may still be run. They are idempotent
   and will skip objects already created here, while still creating
   triggers, functions, roles, access rules, and agent/procedure
   objects.
   ========================================================= */

SET NOCOUNT ON;
GO

/* =========================================================
   1) Clean reset section
   ========================================================= */

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE '
    + QUOTENAME(SCHEMA_NAME(tp.schema_id)) + N'.' + QUOTENAME(tp.name)
    + N' DROP CONSTRAINT ' + QUOTENAME(fk.name) + N';' + CHAR(13) + CHAR(10)
FROM sys.foreign_keys AS fk
INNER JOIN sys.tables AS tp
    ON tp.object_id = fk.parent_object_id
WHERE SCHEMA_NAME(tp.schema_id) = N'dbo';

IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'DROP TRIGGER '
    + QUOTENAME(OBJECT_SCHEMA_NAME(tr.object_id)) + N'.' + QUOTENAME(tr.name)
    + N';' + CHAR(13) + CHAR(10)
FROM sys.triggers AS tr
WHERE tr.parent_class = 1
  AND OBJECT_SCHEMA_NAME(tr.object_id) = N'dbo';
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'DROP VIEW '
    + QUOTENAME(SCHEMA_NAME(v.schema_id)) + N'.' + QUOTENAME(v.name)
    + N';' + CHAR(13) + CHAR(10)
FROM sys.views AS v
WHERE SCHEMA_NAME(v.schema_id) = N'dbo';
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'DROP PROCEDURE '
    + QUOTENAME(SCHEMA_NAME(p.schema_id)) + N'.' + QUOTENAME(p.name)
    + N';' + CHAR(13) + CHAR(10)
FROM sys.procedures AS p
WHERE SCHEMA_NAME(p.schema_id) = N'dbo';
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'DROP FUNCTION '
    + QUOTENAME(SCHEMA_NAME(o.schema_id)) + N'.' + QUOTENAME(o.name)
    + N';' + CHAR(13) + CHAR(10)
FROM sys.objects AS o
WHERE SCHEMA_NAME(o.schema_id) = N'dbo'
  AND o.type IN ('FN', 'IF', 'TF', 'FS', 'FT');
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'DROP SEQUENCE '
    + QUOTENAME(SCHEMA_NAME(seq.schema_id)) + N'.' + QUOTENAME(seq.name)
    + N';' + CHAR(13) + CHAR(10)
FROM sys.sequences AS seq
WHERE SCHEMA_NAME(seq.schema_id) = N'dbo';
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'DROP TABLE '
    + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
    + N';' + CHAR(13) + CHAR(10)
FROM sys.tables AS t
WHERE SCHEMA_NAME(t.schema_id) = N'dbo'
ORDER BY t.name;
IF LEN(@sql) > 0 EXEC sys.sp_executesql @sql;
GO

PRINT 'Clean reset completed. Creating final integrated schema...';
GO

/* =========================================================
   2) Core customer, branch, account, employee schema
   ========================================================= */

CREATE TABLE dbo.Customer
(
    CustomerID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    NationalID NVARCHAR(20) NOT NULL,
    BirthDate DATE NOT NULL,
    Phone NVARCHAR(20) NOT NULL,
    Email NVARCHAR(100) NOT NULL,
    Address NVARCHAR(200) NULL,
    RegistrationDate DATE NOT NULL CONSTRAINT DF_Customer_RegistrationDate DEFAULT (CAST(GETDATE() AS DATE)),
    IsActive BIT NOT NULL CONSTRAINT DF_Customer_IsActive DEFAULT (1),
    CONSTRAINT UQ_Customer_NationalID UNIQUE (NationalID),
    CONSTRAINT UQ_Customer_Phone UNIQUE (Phone),
    CONSTRAINT UQ_Customer_Email UNIQUE (Email),
    CONSTRAINT CHK_Customer_NationalID_Format CHECK (LEN(NationalID) = 10 AND NationalID NOT LIKE '%[^0-9]%')
);
GO

CREATE TABLE dbo.Branch
(
    BranchID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    BranchName NVARCHAR(100) NOT NULL,
    BranchCode NVARCHAR(20) NOT NULL UNIQUE,
    Balance DECIMAL(18,2) NOT NULL CONSTRAINT DF_Branch_Balance DEFAULT (0),
    City NVARCHAR(50) NOT NULL,
    Address NVARCHAR(200) NULL,
    Phone NVARCHAR(20) NULL
);
GO

CREATE TABLE dbo.AccountType
(
    AccountTypeID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TypeName NVARCHAR(50) NOT NULL UNIQUE,
    Description NVARCHAR(200) NULL,
    MinBalance DECIMAL(18,2) NOT NULL CONSTRAINT DF_AccountType_MinBalance DEFAULT (0),
    InterestRate DECIMAL(5,2) NOT NULL CONSTRAINT DF_AccountType_InterestRate DEFAULT (0),
    MonthlyFee DECIMAL(18,2) NOT NULL CONSTRAINT DF_AccountType_MonthlyFee DEFAULT (0)
);
GO

CREATE TABLE dbo.Account
(
    AccountID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AccountNumber NVARCHAR(30) NOT NULL UNIQUE,
    CustomerID INT NOT NULL,
    BranchID INT NOT NULL,
    AccountTypeID INT NOT NULL,
    Balance DECIMAL(18,2) NOT NULL CONSTRAINT DF_Account_Balance DEFAULT (0),
    OpenDate DATE NOT NULL,
    CloseDate DATE NULL,
    AccountStatus NVARCHAR(20) NOT NULL,
    FrozenPreviousStatus NVARCHAR(20) NULL,
    CONSTRAINT FK_Account_Customer FOREIGN KEY (CustomerID) REFERENCES dbo.Customer(CustomerID),
    CONSTRAINT FK_Account_Branch FOREIGN KEY (BranchID) REFERENCES dbo.Branch(BranchID),
    CONSTRAINT FK_Account_AccountType FOREIGN KEY (AccountTypeID) REFERENCES dbo.AccountType(AccountTypeID),
    CONSTRAINT CHK_Account_Status CHECK (AccountStatus IN ('Active', 'Closed', 'Frozen', 'Dormant')),
    CONSTRAINT CHK_Account_CloseDate CHECK (CloseDate IS NULL OR CloseDate >= OpenDate),
    CONSTRAINT CHK_Account_FrozenPreviousStatus CHECK (FrozenPreviousStatus IS NULL OR FrozenPreviousStatus IN ('Active', 'Dormant')),
    CONSTRAINT CHK_Account_AccountNumber_12Digit CHECK (LEN(AccountNumber) = 12 AND AccountNumber NOT LIKE '%[^0-9]%')
);
GO

CREATE INDEX IX_Account_CustomerStatus ON dbo.Account(CustomerID, AccountStatus);
GO
CREATE INDEX IX_Account_BranchStatus ON dbo.Account(BranchID, AccountStatus);
GO

CREATE SEQUENCE dbo.seq_AccountNumber
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO MAXVALUE
    CACHE 50;
GO

CREATE TABLE dbo.Employee
(
    EmployeeID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    NationalID NVARCHAR(20) NOT NULL UNIQUE,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    HireDate DATE NOT NULL,
    JobTitle NVARCHAR(100) NOT NULL,
    Salary DECIMAL(18,2) NOT NULL,
    Phone NVARCHAR(20) NULL,
    Email NVARCHAR(100) NULL,
    EmpStatus NVARCHAR(20) NOT NULL,
    CanAccessAdmin BIT NOT NULL CONSTRAINT DF_Employee_CanAccessAdmin DEFAULT (0),
    CONSTRAINT CHK_Employee_Status CHECK (EmpStatus IN ('Active', 'OnLeave', 'Terminated'))
);
GO

CREATE TABLE dbo.EMPB
(
    EMPBID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EmployeeID INT NOT NULL,
    BranchID INT NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NULL,
    WorkingStatus NVARCHAR(20) NOT NULL,
    CONSTRAINT FK_EMPB_Employee FOREIGN KEY (EmployeeID) REFERENCES dbo.Employee(EmployeeID),
    CONSTRAINT FK_EMPB_Branch FOREIGN KEY (BranchID) REFERENCES dbo.Branch(BranchID),
    CONSTRAINT CHK_EMPB_Status CHECK (WorkingStatus IN ('Working', 'Transferred', 'Ended')),
    CONSTRAINT CHK_EMPB_Dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);
GO

CREATE UNIQUE INDEX IX_Employee_OneActiveBranch
ON dbo.EMPB(EmployeeID)
WHERE WorkingStatus = 'Working' AND EndDate IS NULL;
GO

CREATE INDEX IX_EMPB_CurrentBranchEmployees
ON dbo.EMPB(BranchID, EmployeeID)
INCLUDE (StartDate, EndDate, WorkingStatus)
WHERE WorkingStatus = 'Working' AND EndDate IS NULL;
GO

/* =========================================================
   3) Transactions, loans, installments, ledger
   ========================================================= */

CREATE TABLE dbo.TransactionType
(
    TransactionTypeID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TypeName NVARCHAR(50) NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.Transactions
(
    TransactionID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TransactionTypeID INT NOT NULL,
    FromAccountID INT NULL,
    ToAccountID INT NULL,
    EmployeeID INT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    TransactionDate DATETIME NOT NULL CONSTRAINT DF_Transactions_TransactionDate DEFAULT (GETDATE()),
    TransactionStatus NVARCHAR(20) NOT NULL,
    ReadyToCompleteAt DATETIME NULL,
    CompletedAt DATETIME NULL,
    Description NVARCHAR(200) NULL,
    CONSTRAINT FK_Transactions_FromAccount FOREIGN KEY (FromAccountID) REFERENCES dbo.Account(AccountID),
    CONSTRAINT FK_Transactions_ToAccount FOREIGN KEY (ToAccountID) REFERENCES dbo.Account(AccountID),
    CONSTRAINT FK_Transactions_TransactionType FOREIGN KEY (TransactionTypeID) REFERENCES dbo.TransactionType(TransactionTypeID),
    CONSTRAINT FK_Transactions_Employee FOREIGN KEY (EmployeeID) REFERENCES dbo.Employee(EmployeeID),
    CONSTRAINT CHK_Transactions_Amount CHECK (Amount > 0),
    CONSTRAINT CHK_Transactions_Status CHECK (TransactionStatus IN ('Pending', 'Completed', 'Failed', 'Cancelled')),
    CONSTRAINT CHK_Transactions_AtLeastOneAccount CHECK (FromAccountID IS NOT NULL OR ToAccountID IS NOT NULL),
    CONSTRAINT CHK_Transactions_DifferentAccounts CHECK (FromAccountID IS NULL OR ToAccountID IS NULL OR FromAccountID <> ToAccountID),
    CONSTRAINT CHK_Transactions_CompletedAtConsistency CHECK (
        (TransactionStatus = 'Completed' AND CompletedAt IS NOT NULL)
        OR (TransactionStatus <> 'Completed' AND CompletedAt IS NULL)
    )
);
GO

CREATE INDEX IX_Transactions_FromAccount ON dbo.Transactions(FromAccountID, TransactionDate DESC);
GO
CREATE INDEX IX_Transactions_ToAccount ON dbo.Transactions(ToAccountID, TransactionDate DESC);
GO

INSERT INTO dbo.TransactionType(TypeName)
VALUES ('Deposit'), ('Withdrawal'), ('Transfer'), ('Interest');
GO

CREATE OR ALTER FUNCTION dbo.fn_GetCompletionDelaySeconds
(
    @Amount DECIMAL(18,2)
)
RETURNS INT
AS
BEGIN
    RETURN
        CASE
            WHEN @Amount < 5000 THEN 0
            WHEN @Amount < 25000 THEN 60
            WHEN @Amount < 100000 THEN 180
            ELSE 300
        END;
END;
GO

CREATE OR ALTER VIEW dbo.vw_AccountPendingOutgoing
AS
SELECT
    FromAccountID AS AccountID,
    SUM(Amount) AS PendingOutgoingAmount
FROM dbo.Transactions
WHERE TransactionStatus = 'Pending'
  AND FromAccountID IS NOT NULL
GROUP BY FromAccountID;
GO

CREATE TABLE dbo.Loan
(
    LoanID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CustomerID INT NOT NULL,
    BranchID INT NOT NULL,
    LoanAmount DECIMAL(18,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NULL,
    LoanStatus NVARCHAR(20) NOT NULL,
    CONSTRAINT FK_Loan_Customer FOREIGN KEY (CustomerID) REFERENCES dbo.Customer(CustomerID),
    CONSTRAINT FK_Loan_Branch FOREIGN KEY (BranchID) REFERENCES dbo.Branch(BranchID),
    CONSTRAINT CHK_Loan_Amount CHECK (LoanAmount > 0),
    CONSTRAINT CHK_Loan_Status CHECK (LoanStatus IN ('Active', 'Paid', 'Defaulted')),
    CONSTRAINT CHK_Loan_Dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);
GO

CREATE TABLE dbo.Installment
(
    InstallmentID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    LoanID INT NOT NULL,
    DueDate DATE NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    PaidDate DATE NULL,
    InstallmentStatus NVARCHAR(20) NOT NULL,
    PaymentTransactionID INT NULL,
    CONSTRAINT FK_Installment_Loan FOREIGN KEY (LoanID) REFERENCES dbo.Loan(LoanID),
    CONSTRAINT FK_Installment_PaymentTransaction FOREIGN KEY (PaymentTransactionID) REFERENCES dbo.Transactions(TransactionID),
    CONSTRAINT CHK_Installment_Amount CHECK (Amount > 0),
    CONSTRAINT CHK_Installment_Status CHECK (InstallmentStatus IN ('Pending', 'Paid', 'Late', 'Defaulted'))
);
GO

CREATE INDEX IX_Installment_PaymentTransaction
ON dbo.Installment(PaymentTransactionID)
WHERE PaymentTransactionID IS NOT NULL;
GO

CREATE TABLE dbo.BranchLedger
(
    BranchLedgerID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    BranchID INT NOT NULL,
    TransactionID INT NULL,
    DeltaAmount DECIMAL(18,2) NOT NULL,
    BalanceAfter DECIMAL(18,2) NOT NULL,
    EntryDate DATETIME NOT NULL CONSTRAINT DF_BranchLedger_EntryDate DEFAULT (GETDATE()),
    Description NVARCHAR(200) NULL,
    CONSTRAINT FK_BranchLedger_Branch FOREIGN KEY (BranchID) REFERENCES dbo.Branch(BranchID),
    CONSTRAINT FK_BranchLedger_Transaction FOREIGN KEY (TransactionID) REFERENCES dbo.Transactions(TransactionID)
);
GO

CREATE INDEX IX_BranchLedger_BranchDate
ON dbo.BranchLedger(BranchID, EntryDate DESC);
GO

/* =========================================================
   4) Roles, users, sessions, audit
   ========================================================= */

CREATE TABLE dbo.Roles
(
    RoleID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    RoleName NVARCHAR(50) NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.Users
(
    UserID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Username NVARCHAR(50) NOT NULL UNIQUE,
    PasswordHash CHAR(64) NOT NULL,
    EmployeeID INT NULL,
    CustomerID INT NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),
    CONSTRAINT FK_Users_Employee FOREIGN KEY (EmployeeID) REFERENCES dbo.Employee(EmployeeID),
    CONSTRAINT FK_Users_Customer FOREIGN KEY (CustomerID) REFERENCES dbo.Customer(CustomerID)
);
GO

CREATE UNIQUE INDEX UQ_Users_CustomerID
ON dbo.Users(CustomerID)
WHERE CustomerID IS NOT NULL;
GO

CREATE UNIQUE INDEX UQ_Users_EmployeeID
ON dbo.Users(EmployeeID)
WHERE EmployeeID IS NOT NULL;
GO

CREATE TABLE dbo.UserRoles
(
    UserRoleID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    UserID INT NOT NULL,
    RoleID INT NOT NULL,
    CONSTRAINT FK_UserRoles_User FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID) ON DELETE CASCADE,
    CONSTRAINT FK_UserRoles_Role FOREIGN KEY (RoleID) REFERENCES dbo.Roles(RoleID) ON DELETE CASCADE,
    CONSTRAINT UQ_UserRoles UNIQUE (UserID, RoleID)
);
GO

INSERT INTO dbo.Roles(RoleName)
VALUES ('Customer'), ('Employee'), ('Admin'), ('HighAdmin');
GO

CREATE TABLE dbo.Sessions
(
    SessionID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    UserID INT NOT NULL,
    SessionToken NVARCHAR(200) NOT NULL UNIQUE,
    LoginTime DATETIME NOT NULL CONSTRAINT DF_Sessions_LoginTime DEFAULT (GETDATE()),
    LogoutTime DATETIME NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_Sessions_IsActive DEFAULT (1),
    CONSTRAINT FK_Sessions_User FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.AuditLog
(
    AuditID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    UserID INT NULL,
    ActionType NVARCHAR(100) NOT NULL,
    TableName NVARCHAR(100) NULL,
    RecordID INT NULL,
    ActionDate DATETIME NOT NULL CONSTRAINT DF_AuditLog_ActionDate DEFAULT (GETDATE()),
    Details NVARCHAR(MAX) NULL,
    CONSTRAINT FK_AuditLog_User FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
);
GO

CREATE INDEX IX_AuditLog_UserDate ON dbo.AuditLog(UserID, ActionDate DESC);
GO
CREATE INDEX IX_AuditLog_TableRecord ON dbo.AuditLog(TableName, RecordID);
GO

/* =========================================================
   5) Employee transfer workflow table
   ========================================================= */

CREATE TABLE dbo.EmployeeTransferRequest
(
    TransferRequestID INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EmployeeID INT NOT NULL,
    FromBranchID INT NOT NULL,
    ToBranchID INT NOT NULL,
    RequestedByUserID INT NOT NULL,
    RequestType NVARCHAR(30) NOT NULL,
    Reason NVARCHAR(500) NULL,
    CurrentManagerUserID INT NULL,
    CurrentManagerDecision NVARCHAR(20) NULL,
    CurrentManagerDecisionDate DATETIME NULL,
    CurrentManagerNote NVARCHAR(500) NULL,
    DestinationManagerUserID INT NULL,
    DestinationManagerDecision NVARCHAR(20) NULL,
    DestinationManagerDecisionDate DATETIME NULL,
    DestinationManagerNote NVARCHAR(500) NULL,
    TransferStatus NVARCHAR(50) NOT NULL,
    EffectiveDate DATE NULL,
    CreatedAt DATETIME NOT NULL CONSTRAINT DF_EmployeeTransferRequest_CreatedAt DEFAULT (GETDATE()),
    CompletedAt DATETIME NULL,
    CancelledAt DATETIME NULL,
    CONSTRAINT FK_EmployeeTransferRequest_Employee FOREIGN KEY (EmployeeID) REFERENCES dbo.Employee(EmployeeID),
    CONSTRAINT FK_EmployeeTransferRequest_FromBranch FOREIGN KEY (FromBranchID) REFERENCES dbo.Branch(BranchID),
    CONSTRAINT FK_EmployeeTransferRequest_ToBranch FOREIGN KEY (ToBranchID) REFERENCES dbo.Branch(BranchID),
    CONSTRAINT FK_EmployeeTransferRequest_RequestedByUser FOREIGN KEY (RequestedByUserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT FK_EmployeeTransferRequest_CurrentManagerUser FOREIGN KEY (CurrentManagerUserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT FK_EmployeeTransferRequest_DestinationManagerUser FOREIGN KEY (DestinationManagerUserID) REFERENCES dbo.Users(UserID),
    CONSTRAINT CHK_EmployeeTransferRequest_BranchDifferent CHECK (FromBranchID <> ToBranchID),
    CONSTRAINT CHK_EmployeeTransferRequest_RequestType CHECK (RequestType IN ('EmployeeRequest', 'ManagerRequest')),
    CONSTRAINT CHK_EmployeeTransferRequest_CurrentDecision CHECK (CurrentManagerDecision IS NULL OR CurrentManagerDecision IN ('Approved', 'Rejected')),
    CONSTRAINT CHK_EmployeeTransferRequest_DestinationDecision CHECK (DestinationManagerDecision IS NULL OR DestinationManagerDecision IN ('Approved', 'Rejected')),
    CONSTRAINT CHK_EmployeeTransferRequest_Status CHECK (TransferStatus IN
    (
        'PendingCurrentManagerApproval',
        'PendingDestinationManagerApproval',
        'RejectedByCurrentManager',
        'RejectedByDestinationManager',
        'Completed',
        'Cancelled'
    ))
);
GO

CREATE UNIQUE INDEX UX_EmployeeTransferRequest_OneOpenPerEmployee
ON dbo.EmployeeTransferRequest(EmployeeID)
WHERE TransferStatus IN ('PendingCurrentManagerApproval', 'PendingDestinationManagerApproval');
GO

CREATE INDEX IX_EmployeeTransferRequest_Status
ON dbo.EmployeeTransferRequest(TransferStatus, FromBranchID, ToBranchID, CreatedAt);
GO

PRINT 'Final integrated BankManagement schema created successfully.';
GO
