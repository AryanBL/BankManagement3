/* =========================================================
   Schema_AccountModuleSupport_SELF_SERVICE.sql

   Reduced account-module support script for the self-service
   account-opening flow.

   IMPORTANT:
   This file intentionally DOES NOT recreate objects that already
   exist in Schema_CustomerAccessAndBranchLedger.sql, including:
     - Customer.IsActive
     - Users.IsActive
     - Branch.Balance
     - dbo.BranchLedger
     - Interest transaction type
     - customer Phone/Email uniqueness
     - customer NationalID/min-age constraints

   Execute AFTER:
     1) TableCreation.sql
     2) PasswordHash.sql
     3) ApplyAccessRules.sql
     4) Schema_CustomerAccessAndBranchLedger.sql

   Adds only the account-specific missing support:
     - dbo.seq_AccountNumber for pure global 12-digit account numbers
     - Account.FrozenPreviousStatus for freeze/unfreeze restoration
     - account-number format constraint for future rows
     - account workflow indexes

   This version is separated into GO-delimited batches and uses
   dynamic SQL for constraints that reference newly added columns.
   That avoids SQL Server metadata/compile-time errors such as:
     Invalid column name 'FrozenPreviousStatus'.
   ========================================================= */

SET XACT_ABORT ON;
GO

------------------------------------------------------------
-- Prerequisite checks: fail early if the existing customer/
-- branch-ledger schema has not been installed yet.
------------------------------------------------------------
IF COL_LENGTH('dbo.Customer', 'IsActive') IS NULL
    THROW 51001, 'Missing Customer.IsActive. Run Schema_CustomerAccessAndBranchLedger.sql before this file.', 1;

IF COL_LENGTH('dbo.Users', 'IsActive') IS NULL
    THROW 51002, 'Missing Users.IsActive. Run Schema_CustomerAccessAndBranchLedger.sql before this file.', 1;

IF COL_LENGTH('dbo.Branch', 'Balance') IS NULL
    THROW 51003, 'Missing Branch.Balance. Run Schema_CustomerAccessAndBranchLedger.sql before this file.', 1;

IF OBJECT_ID('dbo.BranchLedger', 'U') IS NULL
    THROW 51004, 'Missing dbo.BranchLedger. Run Schema_CustomerAccessAndBranchLedger.sql before this file.', 1;

IF NOT EXISTS (SELECT 1 FROM dbo.TransactionType WHERE TypeName = 'Interest')
    THROW 51005, 'Missing Interest transaction type. Run Schema_CustomerAccessAndBranchLedger.sql before this file.', 1;
GO

------------------------------------------------------------
-- Account freeze workflow support.
------------------------------------------------------------
IF COL_LENGTH('dbo.Account', 'FrozenPreviousStatus') IS NULL
BEGIN
    ALTER TABLE dbo.Account
    ADD FrozenPreviousStatus NVARCHAR(20) NULL;
END;
GO

IF COL_LENGTH('dbo.Account', 'FrozenPreviousStatus') IS NULL
    THROW 51006, 'Failed to add Account.FrozenPreviousStatus.', 1;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CHK_Account_FrozenPreviousStatus'
      AND parent_object_id = OBJECT_ID('dbo.Account')
)
BEGIN
    EXEC(N'
        ALTER TABLE dbo.Account WITH NOCHECK
        ADD CONSTRAINT CHK_Account_FrozenPreviousStatus
        CHECK (FrozenPreviousStatus IS NULL OR FrozenPreviousStatus IN (''Active'', ''Dormant''));
    ');
END;
GO

------------------------------------------------------------
-- Account number rule: new/updated account numbers must be
-- exactly 12 numeric digits. WITH NOCHECK avoids blocking
-- installation if old demo rows used another format.
------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CHK_Account_AccountNumber_12Digit'
      AND parent_object_id = OBJECT_ID('dbo.Account')
)
BEGIN
    EXEC(N'
        ALTER TABLE dbo.Account WITH NOCHECK
        ADD CONSTRAINT CHK_Account_AccountNumber_12Digit
        CHECK (LEN(AccountNumber) = 12 AND AccountNumber NOT LIKE ''%[^0-9]%'');
    ');
END;
GO

------------------------------------------------------------
-- Account lookup indexes.
------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Account_CustomerStatus'
      AND object_id = OBJECT_ID('dbo.Account')
)
BEGIN
    CREATE INDEX IX_Account_CustomerStatus
    ON dbo.Account(CustomerID, AccountStatus);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Account_BranchStatus'
      AND object_id = OBJECT_ID('dbo.Account')
)
BEGIN
    CREATE INDEX IX_Account_BranchStatus
    ON dbo.Account(BranchID, AccountStatus);
END;
GO

------------------------------------------------------------
-- Sequence for pure global account numbering.
-- It starts at MAX(existing numeric 12-digit AccountNumber)+1
-- when installing over demo data; otherwise it starts at 1.
------------------------------------------------------------
IF OBJECT_ID('dbo.seq_AccountNumber', 'SO') IS NULL
BEGIN
    DECLARE @StartWith BIGINT;

    SELECT @StartWith = ISNULL(MAX(TRY_CONVERT(BIGINT, AccountNumber)), 0) + 1
    FROM dbo.Account
    WHERE LEN(AccountNumber) = 12
      AND AccountNumber NOT LIKE '%[^0-9]%';

    IF @StartWith < 1 SET @StartWith = 1;

    DECLARE @sql NVARCHAR(MAX) =
        N'CREATE SEQUENCE dbo.seq_AccountNumber AS BIGINT START WITH '
        + CAST(@StartWith AS NVARCHAR(30))
        + N' INCREMENT BY 1 MINVALUE 1 NO MAXVALUE CACHE 50;';

    EXEC(@sql);
END;
GO
