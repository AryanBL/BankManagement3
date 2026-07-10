/* =========================================================
   Procedure_FinalizeTransaction.sql
   sp_Transaction_Finalize

   Completes a 'Pending' transaction that was created by
   sp_Transaction_Deposit, sp_Transaction_Withdrawal, or
   sp_Transaction_Transfer, once its amount-based hold
   (ReadyToCompleteAt) has elapsed.

   This is the ONLY procedure that ever updates Account.Balance
   for a normal transaction -- the initiating procedures only
   validate and record intent. Splitting the work this way keeps
   row locks on dbo.Account brief: a $250,000 transfer locks the
   two account rows only for the few milliseconds it takes to
   move the money here, not for the whole 5-minute hold.

   Call pattern: the application calls this for a given
   @TransactionID whenever it wants to check on / push forward a
   pending transaction (e.g. when the customer reloads the page,
   or from a periodic job). If called before ReadyToCompleteAt,
   it simply reports that the transaction is still pending and
   makes no changes.

   Re-validates everything that could have changed since the
   transaction was initiated:
     - the transaction must still be 'Pending'
     - involved account(s) must still be in an allowed status
     - the minimum balance rule is re-checked against the REAL
       current balance (not the available-balance estimate used
       at initiation), since other transactions may have
       finalized in the meantime
   If re-validation fails, the transaction is marked 'Failed'
   (it is not silently left Pending forever) and no balance
   changes are made.

   Must run AFTER TableCreation.sql.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Transaction_Finalize
(
    @TransactionID  INT,
    @ResultStatus   NVARCHAR(20) OUTPUT,   -- 'Completed', 'StillPending', or 'Failed'
    @ResultMessage  NVARCHAR(400) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        ----------------------------------------------------
        -- Load the pending transaction
        ----------------------------------------------------
        DECLARE
            @FromAccountID      INT,
            @ToAccountID        INT,
            @Amount             DECIMAL(18,2),
            @TransactionStatus  NVARCHAR(20),
            @ReadyToCompleteAt  DATETIME;

        SELECT
            @FromAccountID     = FromAccountID,
            @ToAccountID       = ToAccountID,
            @Amount            = Amount,
            @TransactionStatus = TransactionStatus,
            @ReadyToCompleteAt = ReadyToCompleteAt
        FROM dbo.Transactions
        WHERE TransactionID = @TransactionID;

        IF @TransactionStatus IS NULL
        BEGIN
            SET @ResultStatus  = 'Failed';
            SET @ResultMessage = 'Transaction does not exist.';
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @TransactionStatus <> 'Pending'
        BEGIN
            -- Not an error: calling Finalize twice on an already
            -- Completed/Failed/Cancelled transaction is harmless,
            -- it just reports the existing outcome.
            SET @ResultStatus  = @TransactionStatus;
            SET @ResultMessage = CONCAT('Transaction is already ', @TransactionStatus, '.');
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ----------------------------------------------------
        -- Enforce the time-to-complete hold
        ----------------------------------------------------
        IF GETDATE() < @ReadyToCompleteAt
        BEGIN
            SET @ResultStatus  = 'StillPending';
            SET @ResultMessage = CONCAT(
                'Not ready yet. Earliest completion time: ',
                CONVERT(VARCHAR(30), @ReadyToCompleteAt, 121)
            );
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        ----------------------------------------------------
        -- Lock whichever account(s) this transaction touches,
        -- in a fixed AccountID order to avoid deadlocking against
        -- another Finalize call running for a transaction between
        -- the same pair of accounts.
        ----------------------------------------------------
        DECLARE @LowID INT, @HighID INT;

        IF @FromAccountID IS NOT NULL AND @ToAccountID IS NOT NULL
        BEGIN
            SET @LowID  = CASE WHEN @FromAccountID < @ToAccountID THEN @FromAccountID ELSE @ToAccountID END;
            SET @HighID = CASE WHEN @FromAccountID < @ToAccountID THEN @ToAccountID ELSE @FromAccountID END;
        END
        ELSE
        BEGIN
            SET @LowID  = ISNULL(@FromAccountID, @ToAccountID);
            SET @HighID = @LowID;
        END;

        DECLARE @Dummy INT;
        SELECT @Dummy = AccountID FROM dbo.Account WITH (UPDLOCK, HOLDLOCK)
        WHERE AccountID IN (@LowID, @HighID)
        ORDER BY AccountID;

        ----------------------------------------------------
        -- Re-validate the SOURCE side, if any (Withdrawal/Transfer)
        ----------------------------------------------------
        IF @FromAccountID IS NOT NULL
        BEGIN
            DECLARE
                @FromBalance    DECIMAL(18,2),
                @FromStatus     NVARCHAR(20),
                @FromTypeID     INT,
                @FromMinBalance DECIMAL(18,2);

            SELECT
                @FromBalance = Balance,
                @FromStatus  = AccountStatus,
                @FromTypeID  = AccountTypeID
            FROM dbo.Account
            WHERE AccountID = @FromAccountID;

            IF @FromStatus IS NULL OR @FromStatus <> 'Active'
            BEGIN
                UPDATE dbo.Transactions
                SET TransactionStatus = 'Failed'
                WHERE TransactionID = @TransactionID;

                SET @ResultStatus  = 'Failed';
                SET @ResultMessage = 'Source account is no longer Active; transaction marked Failed.';

                INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
                VALUES (NULL, 'TransactionFinalizeFailed', 'Transactions', @TransactionID, @ResultMessage);

                COMMIT TRANSACTION;
                RETURN;
            END;

            SELECT @FromMinBalance = MinBalance
            FROM dbo.AccountType
            WHERE AccountTypeID = @FromTypeID;

            IF (@FromBalance - @Amount) < @FromMinBalance
            BEGIN
                UPDATE dbo.Transactions
                SET TransactionStatus = 'Failed'
                WHERE TransactionID = @TransactionID;

                SET @ResultStatus  = 'Failed';
                SET @ResultMessage = 'Source account no longer has sufficient available balance; transaction marked Failed.';

                INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
                VALUES (NULL, 'TransactionFinalizeFailed', 'Transactions', @TransactionID, @ResultMessage);

                COMMIT TRANSACTION;
                RETURN;
            END;
        END;

        ----------------------------------------------------
        -- Re-validate the DESTINATION side, if any (Deposit/Transfer)
        ----------------------------------------------------
        IF @ToAccountID IS NOT NULL
        BEGIN
            DECLARE @ToStatus NVARCHAR(20);

            SELECT @ToStatus = AccountStatus
            FROM dbo.Account
            WHERE AccountID = @ToAccountID;

            IF @ToStatus IS NULL OR @ToStatus NOT IN ('Active', 'Dormant')
            BEGIN
                UPDATE dbo.Transactions
                SET TransactionStatus = 'Failed'
                WHERE TransactionID = @TransactionID;

                SET @ResultStatus  = 'Failed';
                SET @ResultMessage = 'Destination account can no longer receive funds; transaction marked Failed.';

                INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
                VALUES (NULL, 'TransactionFinalizeFailed', 'Transactions', @TransactionID, @ResultMessage);

                COMMIT TRANSACTION;
                RETURN;
            END;
        END;

        ----------------------------------------------------
        -- All checks passed: apply the balance change(s) now
        ----------------------------------------------------
        IF @FromAccountID IS NOT NULL
        BEGIN
            UPDATE dbo.Account
            SET Balance = Balance - @Amount
            WHERE AccountID = @FromAccountID;
        END;

        DECLARE @ReactivatedToAccount BIT = 0;

        IF @ToAccountID IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Account WHERE AccountID = @ToAccountID AND AccountStatus = 'Dormant')
                SET @ReactivatedToAccount = 1;

            UPDATE dbo.Account
            SET Balance = Balance + @Amount,
                AccountStatus = CASE WHEN AccountStatus = 'Dormant' THEN 'Active' ELSE AccountStatus END
            WHERE AccountID = @ToAccountID;
        END;

        UPDATE dbo.Transactions
        SET TransactionStatus = 'Completed',
            CompletedAt = GETDATE()
        WHERE TransactionID = @TransactionID;

        SET @ResultStatus  = 'Completed';
        SET @ResultMessage = 'Transaction completed successfully.';

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (
            NULL,
            'TransactionFinalized',
            'Transactions',
            @TransactionID,
            CONCAT('Finalized amount ', @Amount,
                   ' FromAccountID=', ISNULL(CAST(@FromAccountID AS VARCHAR(20)), 'NULL'),
                   ' ToAccountID=', ISNULL(CAST(@ToAccountID AS VARCHAR(20)), 'NULL'))
        );

        IF @ReactivatedToAccount = 1
        BEGIN
            INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
            VALUES (
                NULL,
                'AccountReactivated',
                'Account',
                @ToAccountID,
                CONCAT('Dormant account reactivated by completed incoming TransactionID ', @TransactionID)
            );
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
