/* =========================================================
   Schema_CustomerAccessAndBranchLedger.sql

   Adds:
     - Customer.IsActive            (soft-delete flag)
     - Customer.Phone / Email       -> NOT NULL + UNIQUE
     - CHK_Customer_NationalID_Format (exactly 10 numeric digits)
     - CHK_Customer_MinAge          (must be >= 18 at time of write)
     - Users.IsActive                (cascaded by Customer deactivation)
     - Branch.Balance                (running total, kept in sync by trigger)
     - dbo.BranchLedger              (full history of Branch.Balance changes)
     - 'Interest' TransactionType seed row

   Must run AFTER TableCreation.sql and before ApplyAccessRules.sql.

   NOTE ON THE NOT NULL CHANGES:
   If Phone/Email already contain NULLs in existing data, the
   ALTER COLUMN ... NOT NULL statements below will fail until
   those rows are backfilled. This is intentional -- a silent
   default value would misrepresent real contact data for
   existing customers, so a human needs to supply it.
   ========================================================= */

SET XACT_ABORT ON;

BEGIN TRANSACTION;

------------------------------------------------------------
-- Customer: soft-delete flag
------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Customer') AND name = 'IsActive'
)
    ALTER TABLE dbo.Customer ADD IsActive BIT NOT NULL CONSTRAINT DF_Customer_IsActive DEFAULT (1);

------------------------------------------------------------
-- Customer: Phone / Email -> required + unique
------------------------------------------------------------
ALTER TABLE dbo.Customer ALTER COLUMN Phone NVARCHAR(20) NOT NULL;
ALTER TABLE dbo.Customer ALTER COLUMN Email NVARCHAR(100) NOT NULL;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_Customer_Phone' AND object_id = OBJECT_ID('dbo.Customer'))
    ALTER TABLE dbo.Customer ADD CONSTRAINT UQ_Customer_Phone UNIQUE (Phone);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_Customer_Email' AND object_id = OBJECT_ID('dbo.Customer'))
    ALTER TABLE dbo.Customer ADD CONSTRAINT UQ_Customer_Email UNIQUE (Email);

------------------------------------------------------------
-- Customer: NationalID format (10 numeric digits, no checksum)
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CHK_Customer_NationalID_Format')
    ALTER TABLE dbo.Customer WITH CHECK
    ADD CONSTRAINT CHK_Customer_NationalID_Format
        CHECK (LEN(NationalID) = 10 AND NationalID NOT LIKE '%[^0-9]%');

------------------------------------------------------------
-- Customer: minimum age 18
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CHK_Customer_MinAge')
    ALTER TABLE dbo.Customer WITH CHECK
    ADD CONSTRAINT CHK_Customer_MinAge
        CHECK (BirthDate <= DATEADD(YEAR, -18, CAST(GETDATE() AS DATE)));

------------------------------------------------------------
-- Users: soft-deactivation flag, cascaded from Customer
------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Users') AND name = 'IsActive'
)
    ALTER TABLE dbo.Users ADD IsActive BIT NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1);

------------------------------------------------------------
-- Branch: running balance total
-- TableCreation now creates Branch.Balance, but older versions
-- created it as nullable with no default. Normalize it here so
-- TR_Account_SyncBranchLedger cannot produce NULL + amount = NULL.
------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Branch') AND name = 'Balance'
)
BEGIN
    ALTER TABLE dbo.Branch
    ADD Balance DECIMAL(18,2) NOT NULL CONSTRAINT DF_Branch_Balance DEFAULT (0);
END
ELSE
BEGIN
    UPDATE dbo.Branch
    SET Balance = 0
    WHERE Balance IS NULL;

    IF EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('dbo.Branch')
          AND name = 'Balance'
          AND is_nullable = 1
    )
    BEGIN
        ALTER TABLE dbo.Branch ALTER COLUMN Balance DECIMAL(18,2) NOT NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.default_constraints dc
        INNER JOIN sys.columns c
            ON c.default_object_id = dc.object_id
        WHERE dc.parent_object_id = OBJECT_ID('dbo.Branch')
          AND c.name = 'Balance'
    )
    BEGIN
        ALTER TABLE dbo.Branch
        ADD CONSTRAINT DF_Branch_Balance DEFAULT (0) FOR Balance;
    END;
END;

------------------------------------------------------------
-- BranchLedger: full history of Branch.Balance changes.
-- TransactionID is nullable -- most entries originate from a
-- specific dbo.Transactions row (deposit/withdrawal/transfer/
-- interest finalizing), but the syncing trigger applies in
-- bulk/set-based fashion and does not always have a single
-- TransactionID to attribute a given delta to, so it is left
-- NULL when not directly known rather than guessed.
------------------------------------------------------------
IF OBJECT_ID('dbo.BranchLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BranchLedger
    (
        BranchLedgerID  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        BranchID        INT NOT NULL,
        TransactionID   INT NULL,
        DeltaAmount     DECIMAL(18,2) NOT NULL,
        BalanceAfter    DECIMAL(18,2) NOT NULL,
        EntryDate       DATETIME NOT NULL CONSTRAINT DF_BranchLedger_EntryDate DEFAULT (GETDATE()),
        Description     NVARCHAR(200) NULL,
        CONSTRAINT FK_BranchLedger_Branch FOREIGN KEY (BranchID) REFERENCES dbo.Branch(BranchID),
        CONSTRAINT FK_BranchLedger_Transaction FOREIGN KEY (TransactionID) REFERENCES dbo.Transactions(TransactionID)
    );

    CREATE INDEX IX_BranchLedger_BranchDate ON dbo.BranchLedger(BranchID, EntryDate DESC);
END;

------------------------------------------------------------
-- Seed Branch.Balance from any existing Account data, so the
-- new column starts consistent with reality rather than 0 on
-- a database that already has accounts/balances.
------------------------------------------------------------
UPDATE b
SET b.Balance = ISNULL(s.TotalBalance, 0)
FROM dbo.Branch b
LEFT JOIN (
    SELECT BranchID, SUM(Balance) AS TotalBalance
    FROM dbo.Account
    GROUP BY BranchID
) s ON s.BranchID = b.BranchID;

------------------------------------------------------------
-- Seed the 'Interest' transaction type, used by
-- sp_Account_ApplyMonthlyInterest.
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.TransactionType WHERE TypeName = 'Interest')
    INSERT INTO dbo.TransactionType (TypeName) VALUES ('Interest');

COMMIT TRANSACTION;
GO
