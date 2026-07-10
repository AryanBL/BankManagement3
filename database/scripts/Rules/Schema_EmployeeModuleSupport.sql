/* =========================================================
   Schema_EmployeeModuleSupport.sql
   ---------------------------------------------------------
   PURPOSE:
   Adds the workflow table and performance indexes required
   for employee branch-transfer requests.

   IMPORTANT:
   - This does NOT replace dbo.EMPB.
   - dbo.EMPB remains the source of truth for actual branch
     assignment history.
   - dbo.EmployeeTransferRequest stores the approval workflow
     BEFORE the actual EMPB transfer is applied.
   - Keep the existing IX_Employee_OneActiveBranch filtered
     unique index. It correctly enforces one current branch per
     employee.

   REQUIRED EXISTING OBJECTS:
   - dbo.Employee
   - dbo.Branch
   - dbo.Users
   - dbo.EMPB
   - dbo.AuditLog
   ========================================================= */

SET XACT_ABORT ON;
GO

------------------------------------------------------------
-- Prerequisite checks.
------------------------------------------------------------
IF OBJECT_ID('dbo.Employee', 'U') IS NULL
BEGIN
    RAISERROR('Missing dbo.Employee. Run TableCreation.sql first.', 16, 1);
    RETURN;
END;
GO

IF OBJECT_ID('dbo.Branch', 'U') IS NULL
BEGIN
    RAISERROR('Missing dbo.Branch. Run TableCreation.sql first.', 16, 1);
    RETURN;
END;
GO

IF OBJECT_ID('dbo.Users', 'U') IS NULL
BEGIN
    RAISERROR('Missing dbo.Users. Run TableCreation.sql and ApplyAccessRules.sql first.', 16, 1);
    RETURN;
END;
GO

IF OBJECT_ID('dbo.EMPB', 'U') IS NULL
BEGIN
    RAISERROR('Missing dbo.EMPB. Run TableCreation.sql first.', 16, 1);
    RETURN;
END;
GO

------------------------------------------------------------
-- Employee transfer request workflow table.
------------------------------------------------------------
IF OBJECT_ID('dbo.EmployeeTransferRequest', 'U') IS NULL
BEGIN
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
        CreatedAt DATETIME NOT NULL CONSTRAINT DF_EmployeeTransferRequest_CreatedAt DEFAULT(GETDATE()),
        CompletedAt DATETIME NULL,
        CancelledAt DATETIME NULL,

        CONSTRAINT FK_EmployeeTransferRequest_Employee
            FOREIGN KEY (EmployeeID) REFERENCES dbo.Employee(EmployeeID),
        CONSTRAINT FK_EmployeeTransferRequest_FromBranch
            FOREIGN KEY (FromBranchID) REFERENCES dbo.Branch(BranchID),
        CONSTRAINT FK_EmployeeTransferRequest_ToBranch
            FOREIGN KEY (ToBranchID) REFERENCES dbo.Branch(BranchID),
        CONSTRAINT FK_EmployeeTransferRequest_RequestedByUser
            FOREIGN KEY (RequestedByUserID) REFERENCES dbo.Users(UserID),
        CONSTRAINT FK_EmployeeTransferRequest_CurrentManagerUser
            FOREIGN KEY (CurrentManagerUserID) REFERENCES dbo.Users(UserID),
        CONSTRAINT FK_EmployeeTransferRequest_DestinationManagerUser
            FOREIGN KEY (DestinationManagerUserID) REFERENCES dbo.Users(UserID),

        CONSTRAINT CHK_EmployeeTransferRequest_BranchDifferent
            CHECK (FromBranchID <> ToBranchID),
        CONSTRAINT CHK_EmployeeTransferRequest_RequestType
            CHECK (RequestType IN ('EmployeeRequest', 'ManagerRequest')),
        CONSTRAINT CHK_EmployeeTransferRequest_CurrentDecision
            CHECK (CurrentManagerDecision IS NULL OR CurrentManagerDecision IN ('Approved', 'Rejected')),
        CONSTRAINT CHK_EmployeeTransferRequest_DestinationDecision
            CHECK (DestinationManagerDecision IS NULL OR DestinationManagerDecision IN ('Approved', 'Rejected')),
        CONSTRAINT CHK_EmployeeTransferRequest_Status
            CHECK (TransferStatus IN
            (
                'PendingCurrentManagerApproval',
                'PendingDestinationManagerApproval',
                'RejectedByCurrentManager',
                'RejectedByDestinationManager',
                'Completed',
                'Cancelled'
            ))
    );
END;
GO

------------------------------------------------------------
-- Ensure each employee has only one open transfer workflow.
-- This is separate from IX_Employee_OneActiveBranch.
------------------------------------------------------------
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = 'UX_EmployeeTransferRequest_OneOpenPerEmployee'
      AND object_id = OBJECT_ID('dbo.EmployeeTransferRequest')
)
BEGIN
    CREATE UNIQUE INDEX UX_EmployeeTransferRequest_OneOpenPerEmployee
    ON dbo.EmployeeTransferRequest(EmployeeID)
    WHERE TransferStatus IN
    (
        'PendingCurrentManagerApproval',
        'PendingDestinationManagerApproval'
    );
END;
GO

------------------------------------------------------------
-- Search/support indexes.
------------------------------------------------------------
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EmployeeTransferRequest_Status'
      AND object_id = OBJECT_ID('dbo.EmployeeTransferRequest')
)
BEGIN
    CREATE INDEX IX_EmployeeTransferRequest_Status
    ON dbo.EmployeeTransferRequest(TransferStatus, FromBranchID, ToBranchID, CreatedAt);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_EMPB_CurrentBranchEmployees'
      AND object_id = OBJECT_ID('dbo.EMPB')
)
BEGIN
    CREATE INDEX IX_EMPB_CurrentBranchEmployees
    ON dbo.EMPB(BranchID, EmployeeID)
    INCLUDE (StartDate, EndDate, WorkingStatus)
    WHERE WorkingStatus = 'Working' AND EndDate IS NULL;
END;
GO
