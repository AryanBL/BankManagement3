/* =========================================================
   Procedure_ReverseTransaction_FINAL_FIXED.sql
   dbo.sp_Transaction_Reverse
   ---------------------------------------------------------
   Final coherent version for the current security model.

   Fixes:
     1. Avoids CREATE OR ALTER compatibility/object-resolution issues
        by using DROP + CREATE in separate batches.
     2. Allows cancellation/reversal only by the customer who owns
        the account that initiated the transaction.
     3. Keeps @EmployeeID as a backward-compatible metadata parameter.
     4. Writes AuditLog.UserID instead of NULL when a login user is known.
     5. Locks the transaction row before changing its status.

   Run AFTER:
     - TableCreation.sql
     - Schema_CustomerAccessAndBranchLedger.sql
     - ApplyAccessRules.sql
     - 99_Function_UserHasEffectiveRole.sql
     - Trigger_Account_SyncBranchLedger.sql
   ========================================================= */

IF OBJECT_ID('dbo.sp_Transaction_Reverse', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Transaction_Reverse;
GO

CREATE PROCEDURE dbo.sp_Transaction_Reverse
(
    @TransactionID      INT,
    @EmployeeID         INT = NULL,      -- kept for compatibility with the older procedure signature
    @ReasonDescription  NVARCHAR(200) = NULL,
    @UserID             INT = NULL       -- preferred final authorization parameter
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ----------------------------------------------------
        -- Resolve the authorizing UserID.
        -- Final model uses UserID. Older calls may only pass
        -- EmployeeID; in that case we resolve the active user
        -- linked to that employee.
        ----------------------------------------------------
        IF @UserID IS NULL AND @EmployeeID IS NOT NULL
        BEGIN
            SELECT @UserID = U.UserID
            FROM dbo.Users AS U
            WHERE U.EmployeeID = @EmployeeID
              AND U.IsActive = 1;
        END;

        IF @UserID IS NULL
        BEGIN
            RAISERROR('A reversal/cancellation must be authorized by a valid UserID or EmployeeID.', 16, 1);
            RETURN;
        END;

        DECLARE @ResolvedEmployeeID INT;

        SELECT @ResolvedEmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        WHERE U.UserID = @UserID
          AND U.IsActive = 1;

        IF @EmployeeID IS NOT NULL
           AND @ResolvedEmployeeID IS NOT NULL
           AND @EmployeeID <> @ResolvedEmployeeID
        BEGIN
            RAISERROR('The supplied EmployeeID does not match the supplied UserID.', 16, 1);
            RETURN;
        END;

        DECLARE @CallerCustomerID INT;

        SELECT @CallerCustomerID = U.CustomerID
        FROM dbo.Users AS U
        INNER JOIN dbo.Customer AS C
            ON C.CustomerID = U.CustomerID
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND C.IsActive = 1;

        IF @CallerCustomerID IS NULL
        BEGIN
            RAISERROR('A valid authenticated account owner is required to reverse a transaction.', 16, 1);
            RETURN;
        END;

        BEGIN TRANSACTION;

        DECLARE
            @TypeName           NVARCHAR(50),
            @FromAccountID      INT,
            @ToAccountID        INT,
            @Amount             DECIMAL(18,2),
            @CurrentStatus      NVARCHAR(20);

        SELECT
            @TypeName       = tt.TypeName,
            @FromAccountID  = tr.FromAccountID,
            @ToAccountID    = tr.ToAccountID,
            @Amount         = tr.Amount,
            @CurrentStatus  = tr.TransactionStatus
        FROM dbo.Transactions AS tr WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.TransactionType AS tt
            ON tt.TransactionTypeID = tr.TransactionTypeID
        WHERE tr.TransactionID = @TransactionID;

        IF @TypeName IS NULL
        BEGIN
            RAISERROR('Transaction does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        DECLARE
            @OwnerAccountID INT,
            @TransactionOwnerCustomerID INT;

        SET @OwnerAccountID = COALESCE(@FromAccountID, @ToAccountID);

        SELECT @TransactionOwnerCustomerID = A.CustomerID
        FROM dbo.Account AS A
        WHERE A.AccountID = @OwnerAccountID;

        IF @TransactionOwnerCustomerID IS NULL
           OR @TransactionOwnerCustomerID <> @CallerCustomerID
        BEGIN
            RAISERROR('Only the transaction account owner can cancel or reverse this transaction.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @CurrentStatus NOT IN (N'Pending', N'Completed')
        BEGIN
            RAISERROR('Only a Pending or Completed transaction can be reversed/cancelled.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ----------------------------------------------------
        -- CASE 1: Pending -> pure cancellation.
        -- No Account.Balance change has happened yet.
        ----------------------------------------------------
        IF @CurrentStatus = N'Pending'
        BEGIN
            UPDATE dbo.Transactions
            SET TransactionStatus = N'Cancelled',
                CompletedAt = NULL,
                Description = CONCAT(
                    ISNULL(Description, N''),
                    N' [Cancelled before completion: ',
                    ISNULL(@ReasonDescription, N'no reason given'),
                    N']'
                )
            WHERE TransactionID = @TransactionID;

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
                N'TransactionCancelledPending',
                N'Transactions',
                @TransactionID,
                GETDATE(),
                CONCAT(
                    N'Cancelled pending ', @TypeName,
                    N' of ', @Amount,
                    N'. AuthorizingUserID=', @UserID,
                    N'; AuthorizingEmployeeID=', ISNULL(CAST(@ResolvedEmployeeID AS NVARCHAR(20)), N'NULL'),
                    N'; Reason=', ISNULL(@ReasonDescription, N'not provided')
                )
            );

            COMMIT TRANSACTION;

            SELECT
                @TransactionID AS TransactionID,
                N'Cancelled' AS ResultStatus,
                N'Pending transaction cancelled successfully.' AS ResultMessage;
            RETURN;
        END;

        ----------------------------------------------------
        -- CASE 2: Completed -> reverse applied balance effects.
        ----------------------------------------------------
        IF @FromAccountID IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Account WITH (UPDLOCK, HOLDLOCK) WHERE AccountID = @FromAccountID)
            BEGIN
                RAISERROR('Source account does not exist.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;
        END;

        IF @ToAccountID IS NOT NULL
        BEGIN
            DECLARE
                @ToBalance DECIMAL(18,2),
                @ToTypeID INT,
                @ToMinBalance DECIMAL(18,2);

            SELECT
                @ToBalance = Balance,
                @ToTypeID = AccountTypeID
            FROM dbo.Account WITH (UPDLOCK, HOLDLOCK)
            WHERE AccountID = @ToAccountID;

            IF @ToBalance IS NULL
            BEGIN
                RAISERROR('Destination account does not exist.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;

            SELECT @ToMinBalance = MinBalance
            FROM dbo.AccountType
            WHERE AccountTypeID = @ToTypeID;

            -- Reversing a Deposit/Transfer takes money away from the
            -- credited account, so minimum balance is checked again.
            IF (@ToBalance - @Amount) < @ToMinBalance
            BEGIN
                RAISERROR('Cannot reverse: destination account would fall below its minimum balance.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;
        END;

        -- Undo debit side: Withdrawal/Transfer source gets money back.
        IF @FromAccountID IS NOT NULL
        BEGIN
            UPDATE dbo.Account
            SET Balance = Balance + @Amount
            WHERE AccountID = @FromAccountID;
        END;

        -- Undo credit side: Deposit/Transfer destination loses money.
        IF @ToAccountID IS NOT NULL
        BEGIN
            UPDATE dbo.Account
            SET Balance = Balance - @Amount
            WHERE AccountID = @ToAccountID;
        END;

        UPDATE dbo.Transactions
        SET TransactionStatus = N'Cancelled',
            CompletedAt = NULL,
            Description = CONCAT(
                ISNULL(Description, N''),
                N' [Reversed: ',
                ISNULL(@ReasonDescription, N'no reason given'),
                N']'
            )
        WHERE TransactionID = @TransactionID;

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
            N'TransactionReversal',
            N'Transactions',
            @TransactionID,
            GETDATE(),
            CONCAT(
                N'Reversed completed ', @TypeName,
                N' of ', @Amount,
                N'. FromAccountID=', ISNULL(CAST(@FromAccountID AS NVARCHAR(20)), N'NULL'),
                N'; ToAccountID=', ISNULL(CAST(@ToAccountID AS NVARCHAR(20)), N'NULL'),
                N'; AuthorizingUserID=', @UserID,
                N'; AuthorizingEmployeeID=', ISNULL(CAST(@ResolvedEmployeeID AS NVARCHAR(20)), N'NULL'),
                N'; Reason=', ISNULL(@ReasonDescription, N'not provided')
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @TransactionID AS TransactionID,
            N'Cancelled' AS ResultStatus,
            N'Completed transaction reversed successfully.' AS ResultMessage;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN;
    END CATCH;
END;
GO
