/* =========================================================
   Procedure_AccountHistory_FINAL_FIXED.sql

   Creates:
     - dbo.vw_AccountPendingOutgoing
     - dbo.vw_AccountTransactionHistory
     - dbo.sp_Transaction_GetAccountHistory
     - dbo.sp_Account_GetAvailableBalance

   Fixes:
     - Replaces CREATE OR ALTER with DROP + CREATE for compatibility.
     - Adds final @UserID authorization checks.
     - Allows customers to view only their own accounts.
     - Allows effective Employee/Admin/HighAdmin users to view any account.

   Must run AFTER:
     - TableCreation.sql
     - Schema_CustomerAccessAndBranchLedger.sql
     - ApplyAccessRules.sql
     - 99_Function_UserHasEffectiveRole.sql
   ========================================================= */

------------------------------------------------------------
-- Drop dependent procedures first
------------------------------------------------------------
IF OBJECT_ID('dbo.sp_Transaction_GetAccountHistory', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Transaction_GetAccountHistory;
GO

IF OBJECT_ID('dbo.sp_Account_GetAvailableBalance', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_GetAvailableBalance;
GO

------------------------------------------------------------
-- Drop views after procedures
------------------------------------------------------------
IF OBJECT_ID('dbo.vw_AccountTransactionHistory', 'V') IS NOT NULL
    DROP VIEW dbo.vw_AccountTransactionHistory;
GO

IF OBJECT_ID('dbo.vw_AccountPendingOutgoing', 'V') IS NOT NULL
    DROP VIEW dbo.vw_AccountPendingOutgoing;
GO

------------------------------------------------------------
-- View: pending outgoing amount per account.
-- Pending withdrawals and outgoing transfers reduce available
-- balance before the money actually moves.
------------------------------------------------------------
CREATE VIEW dbo.vw_AccountPendingOutgoing
AS
SELECT
    tr.FromAccountID AS AccountID,
    SUM(tr.Amount) AS PendingOutgoingAmount
FROM dbo.Transactions AS tr
INNER JOIN dbo.TransactionType AS tt
    ON tt.TransactionTypeID = tr.TransactionTypeID
WHERE tr.FromAccountID IS NOT NULL
  AND tr.TransactionStatus = N'Pending'
  AND tt.TypeName IN (N'Withdrawal', N'Transfer')
GROUP BY tr.FromAccountID;
GO

------------------------------------------------------------
-- View: one row per account/transaction pairing.
-- A transfer appears twice: Out for the sender and In for the receiver.
------------------------------------------------------------
CREATE VIEW dbo.vw_AccountTransactionHistory
AS
SELECT
    tr.TransactionID,
    tr.FromAccountID AS RelatedAccountID,
    CAST(N'Out' AS NVARCHAR(10)) AS Direction,
    tt.TypeName,
    tr.Amount,
    tr.TransactionDate,
    tr.TransactionStatus,
    tr.ReadyToCompleteAt,
    tr.CompletedAt,
    tr.EmployeeID,
    tr.Description,
    tr.ToAccountID AS CounterpartyAccountID
FROM dbo.Transactions AS tr
INNER JOIN dbo.TransactionType AS tt
    ON tr.TransactionTypeID = tt.TransactionTypeID
WHERE tr.FromAccountID IS NOT NULL

UNION ALL

SELECT
    tr.TransactionID,
    tr.ToAccountID AS RelatedAccountID,
    CAST(N'In' AS NVARCHAR(10)) AS Direction,
    tt.TypeName,
    tr.Amount,
    tr.TransactionDate,
    tr.TransactionStatus,
    tr.ReadyToCompleteAt,
    tr.CompletedAt,
    tr.EmployeeID,
    tr.Description,
    tr.FromAccountID AS CounterpartyAccountID
FROM dbo.Transactions AS tr
INNER JOIN dbo.TransactionType AS tt
    ON tr.TransactionTypeID = tt.TransactionTypeID
WHERE tr.ToAccountID IS NOT NULL;
GO

------------------------------------------------------------
-- Procedure: authorized account transaction history.
------------------------------------------------------------
CREATE PROCEDURE dbo.sp_Transaction_GetAccountHistory
(
    @UserID     INT,
    @AccountID  INT,
    @FromDate   DATETIME = NULL,
    @ToDate     DATETIME = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CallerCustomerID INT,
        @AccountOwnerCustomerID INT,
        @CanView BIT;

    IF @UserID IS NULL
    BEGIN
        RAISERROR('UserID is required.', 16, 1);
        RETURN;
    END;

    IF @AccountID IS NULL
    BEGIN
        RAISERROR('AccountID is required.', 16, 1);
        RETURN;
    END;

    SELECT @CallerCustomerID = U.CustomerID
    FROM dbo.Users AS U
    WHERE U.UserID = @UserID
      AND U.IsActive = 1;

    SELECT @AccountOwnerCustomerID = A.CustomerID
    FROM dbo.Account AS A
    WHERE A.AccountID = @AccountID;

    IF @AccountOwnerCustomerID IS NULL
    BEGIN
        RAISERROR('Account does not exist.', 16, 1);
        RETURN;
    END;

    SET @CanView = 0;

    IF dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin') = 1
       OR dbo.fn_UserHasEffectiveRole(@UserID, N'Admin') = 1
       OR dbo.fn_UserHasEffectiveRole(@UserID, N'Employee') = 1
    BEGIN
        SET @CanView = 1;
    END;
    ELSE IF dbo.fn_UserHasEffectiveRole(@UserID, N'Customer') = 1
            AND @CallerCustomerID = @AccountOwnerCustomerID
    BEGIN
        SET @CanView = 1;
    END;

    IF @CanView = 0
    BEGIN
        RAISERROR('You are not authorized to view this account history.', 16, 1);
        RETURN;
    END;

    SELECT
        TransactionID,
        Direction,
        TypeName,
        Amount,
        TransactionDate,
        TransactionStatus,
        ReadyToCompleteAt,
        CompletedAt,
        EmployeeID,
        CounterpartyAccountID,
        Description
    FROM dbo.vw_AccountTransactionHistory
    WHERE RelatedAccountID = @AccountID
      AND (@FromDate IS NULL OR TransactionDate >= @FromDate)
      AND (@ToDate   IS NULL OR TransactionDate < DATEADD(DAY, 1, @ToDate))
    ORDER BY TransactionDate DESC, TransactionID DESC;
END;
GO

------------------------------------------------------------
-- Procedure: authorized available balance check.
------------------------------------------------------------
CREATE PROCEDURE dbo.sp_Account_GetAvailableBalance
(
    @UserID    INT,
    @AccountID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @CallerCustomerID INT,
        @AccountOwnerCustomerID INT,
        @CanView BIT;

    IF @UserID IS NULL
    BEGIN
        RAISERROR('UserID is required.', 16, 1);
        RETURN;
    END;

    IF @AccountID IS NULL
    BEGIN
        RAISERROR('AccountID is required.', 16, 1);
        RETURN;
    END;

    SELECT @CallerCustomerID = U.CustomerID
    FROM dbo.Users AS U
    WHERE U.UserID = @UserID
      AND U.IsActive = 1;

    SELECT @AccountOwnerCustomerID = A.CustomerID
    FROM dbo.Account AS A
    WHERE A.AccountID = @AccountID;

    IF @AccountOwnerCustomerID IS NULL
    BEGIN
        RAISERROR('Account does not exist.', 16, 1);
        RETURN;
    END;

    SET @CanView = 0;

    IF dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin') = 1
       OR dbo.fn_UserHasEffectiveRole(@UserID, N'Admin') = 1
       OR dbo.fn_UserHasEffectiveRole(@UserID, N'Employee') = 1
    BEGIN
        SET @CanView = 1;
    END;
    ELSE IF dbo.fn_UserHasEffectiveRole(@UserID, N'Customer') = 1
            AND @CallerCustomerID = @AccountOwnerCustomerID
    BEGIN
        SET @CanView = 1;
    END;

    IF @CanView = 0
    BEGIN
        RAISERROR('You are not authorized to view this account balance.', 16, 1);
        RETURN;
    END;

    SELECT
        a.AccountID,
        a.AccountNumber,
        a.CustomerID,
        a.BranchID,
        a.AccountStatus,
        a.Balance,
        ISNULL(p.PendingOutgoingAmount, 0) AS PendingOutgoingAmount,
        a.Balance - ISNULL(p.PendingOutgoingAmount, 0) AS AvailableBalance,
        at.MinBalance
    FROM dbo.Account AS a
    INNER JOIN dbo.AccountType AS at
        ON a.AccountTypeID = at.AccountTypeID
    LEFT JOIN dbo.vw_AccountPendingOutgoing AS p
        ON p.AccountID = a.AccountID
    WHERE a.AccountID = @AccountID;
END;
GO
