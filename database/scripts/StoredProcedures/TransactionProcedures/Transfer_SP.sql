/* =========================================================
   Procedure_Transfer.sql
   sp_Transaction_Transfer
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Every authenticated user can transfer only from a source
     account owned by the same CustomerID linked to the login.
   - Employee/Admin/HighAdmin privileges do not bypass ownership.
   - @EmployeeID is metadata only and must match the authenticated
     employee when supplied.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Transaction_Transfer', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Transaction_Transfer;
GO

CREATE PROCEDURE dbo.sp_Transaction_Transfer
(
    @FromAccountID      INT,
    @ToAccountID        INT,
    @Amount             DECIMAL(18,2),
    @EmployeeID         INT           = NULL,
    @Description        NVARCHAR(200) = NULL,
    @TransactionID       INT OUTPUT,
    @ReadyToCompleteAt   DATETIME OUTPUT,
    @UserID              INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @TransactionID = NULL;
    SET @ReadyToCompleteAt = NULL;

    BEGIN TRY
        IF @UserID IS NULL OR dbo.fn_UserHasEffectiveRole(@UserID, N'Customer') = 0
        BEGIN RAISERROR('A valid authenticated user is required for transfer.', 16, 1); RETURN; END;
        IF @Amount IS NULL OR @Amount <= 0
        BEGIN RAISERROR('Transfer amount must be greater than zero.', 16, 1); RETURN; END;
        IF @FromAccountID = @ToAccountID
        BEGIN RAISERROR('Cannot transfer an account to itself.', 16, 1); RETURN; END;

        DECLARE @CallerCustomerID INT, @CallerEmployeeID INT, @EffectiveEmployeeID INT, @FromCustomerID INT;
        SELECT @CallerCustomerID = CustomerID, @CallerEmployeeID = EmployeeID
        FROM dbo.Users WHERE UserID = @UserID AND IsActive = 1;

        IF dbo.fn_UserHasEffectiveRole(@UserID, N'Employee') = 1 OR dbo.fn_UserHasEffectiveRole(@UserID, N'Admin') = 1
        BEGIN
            IF @EmployeeID IS NOT NULL AND @EmployeeID <> @CallerEmployeeID
            BEGIN RAISERROR('EmployeeID must match the authenticated employee user.', 16, 1); RETURN; END;
            SET @EffectiveEmployeeID = @CallerEmployeeID;
        END
        ELSE
        BEGIN
            IF @EmployeeID IS NOT NULL
            BEGIN RAISERROR('Customer/HighAdmin transfers cannot provide EmployeeID metadata.', 16, 1); RETURN; END;
            SET @EffectiveEmployeeID = NULL;
        END;

        SELECT @FromCustomerID = CustomerID FROM dbo.Account WHERE AccountID = @FromAccountID;
        IF @FromCustomerID IS NULL
        BEGIN RAISERROR('Source account does not exist.', 16, 1); RETURN; END;

        IF @FromCustomerID <> @CallerCustomerID
        BEGIN RAISERROR('Only the source-account owner can initiate this transfer.', 16, 1); RETURN; END;

        BEGIN TRANSACTION;

        DECLARE @LowID INT = CASE WHEN @FromAccountID < @ToAccountID THEN @FromAccountID ELSE @ToAccountID END;
        DECLARE @HighID INT = CASE WHEN @FromAccountID < @ToAccountID THEN @ToAccountID ELSE @FromAccountID END;
        DECLARE @Dummy INT;
        SELECT @Dummy = AccountID FROM dbo.Account WITH (UPDLOCK, HOLDLOCK)
        WHERE AccountID IN (@LowID, @HighID)
        ORDER BY AccountID;

        DECLARE @FromBalance DECIMAL(18,2), @FromStatus NVARCHAR(20), @FromTypeID INT, @ToStatus NVARCHAR(20);
        SELECT @FromBalance = Balance, @FromStatus = AccountStatus, @FromTypeID = AccountTypeID FROM dbo.Account WHERE AccountID = @FromAccountID;
        SELECT @ToStatus = AccountStatus FROM dbo.Account WHERE AccountID = @ToAccountID;

        IF @FromBalance IS NULL
        BEGIN RAISERROR('Source account does not exist.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF @ToStatus IS NULL
        BEGIN RAISERROR('Destination account does not exist.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF @FromStatus <> 'Active'
        BEGIN RAISERROR('Source account must be Active to send a transfer.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF @ToStatus NOT IN ('Active', 'Dormant')
        BEGIN RAISERROR('Destination account cannot be Closed or Frozen.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @MinBalance DECIMAL(18,2), @PendingOutgoingAmount DECIMAL(18,2), @AvailableBalance DECIMAL(18,2);
        SELECT @MinBalance = MinBalance FROM dbo.AccountType WHERE AccountTypeID = @FromTypeID;
        SELECT @PendingOutgoingAmount = PendingOutgoingAmount FROM dbo.vw_AccountPendingOutgoing WHERE AccountID = @FromAccountID;
        SET @PendingOutgoingAmount = ISNULL(@PendingOutgoingAmount, 0);
        SET @AvailableBalance = @FromBalance - @PendingOutgoingAmount;

        IF (@AvailableBalance - @Amount) < @MinBalance
        BEGIN RAISERROR('Insufficient available funds: transfer would breach minimum balance.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @TransactionTypeID INT;
        SELECT @TransactionTypeID = TransactionTypeID FROM dbo.TransactionType WHERE TypeName = 'Transfer';
        IF @TransactionTypeID IS NULL
        BEGIN RAISERROR('Transfer transaction type is not configured.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @DelaySeconds INT = dbo.fn_GetCompletionDelaySeconds(@Amount);
        SET @ReadyToCompleteAt = DATEADD(SECOND, @DelaySeconds, GETDATE());

        INSERT INTO dbo.Transactions
            (TransactionTypeID, FromAccountID, ToAccountID, EmployeeID, Amount,
             TransactionStatus, ReadyToCompleteAt, CompletedAt, Description)
        VALUES
            (@TransactionTypeID, @FromAccountID, @ToAccountID, @EffectiveEmployeeID, @Amount,
             'Pending', @ReadyToCompleteAt, NULL, @Description);

        SET @TransactionID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@UserID, 'TransferInitiated', 'Transactions', @TransactionID,
                CONCAT('Transfer of ', @Amount, ' from AccountID ', @FromAccountID,
                       ' to AccountID ', @ToAccountID,
                       ' queued; ready at ', CONVERT(VARCHAR(30), @ReadyToCompleteAt, 121)));

        COMMIT TRANSACTION;
        SELECT @TransactionID AS TransactionID, @ReadyToCompleteAt AS ReadyToCompleteAt;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN;
    END CATCH
END;
GO
