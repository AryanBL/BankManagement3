/* =========================================================
   Procedure_Withdrawal.sql
   sp_Transaction_Withdrawal
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Every authenticated user can withdraw only from an account
     owned by the same CustomerID linked to the login.
   - Employee/Admin/HighAdmin privileges do not bypass ownership.
   - @EmployeeID is metadata only and must match the authenticated
     employee when supplied.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Transaction_Withdrawal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Transaction_Withdrawal;
GO

CREATE PROCEDURE dbo.sp_Transaction_Withdrawal
(
    @AccountID          INT,
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
        BEGIN RAISERROR('A valid authenticated user is required for withdrawal.', 16, 1); RETURN; END;
        IF @Amount IS NULL OR @Amount <= 0
        BEGIN RAISERROR('Withdrawal amount must be greater than zero.', 16, 1); RETURN; END;

        DECLARE @CallerCustomerID INT, @CallerEmployeeID INT, @EffectiveEmployeeID INT, @AccountCustomerID INT;
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
            BEGIN RAISERROR('Customer/HighAdmin withdrawals cannot provide EmployeeID metadata.', 16, 1); RETURN; END;
            SET @EffectiveEmployeeID = NULL;
        END;

        SELECT @AccountCustomerID = CustomerID FROM dbo.Account WHERE AccountID = @AccountID;
        IF @AccountCustomerID IS NULL
        BEGIN RAISERROR('Account does not exist.', 16, 1); RETURN; END;

        IF @AccountCustomerID <> @CallerCustomerID
        BEGIN RAISERROR('Only the account owner can withdraw from this account.', 16, 1); RETURN; END;

        BEGIN TRANSACTION;

        DECLARE @CurrentBalance DECIMAL(18,2), @AccountStatus NVARCHAR(20), @AccountTypeID INT;
        SELECT @CurrentBalance = Balance, @AccountStatus = AccountStatus, @AccountTypeID = AccountTypeID
        FROM dbo.Account WITH (UPDLOCK, HOLDLOCK)
        WHERE AccountID = @AccountID;

        IF @AccountStatus <> 'Active'
        BEGIN RAISERROR('Withdrawals are only allowed on an Active account.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @MinBalance DECIMAL(18,2), @PendingOutgoingAmount DECIMAL(18,2), @AvailableBalance DECIMAL(18,2);
        SELECT @MinBalance = MinBalance FROM dbo.AccountType WHERE AccountTypeID = @AccountTypeID;
        SELECT @PendingOutgoingAmount = PendingOutgoingAmount FROM dbo.vw_AccountPendingOutgoing WHERE AccountID = @AccountID;
        SET @PendingOutgoingAmount = ISNULL(@PendingOutgoingAmount, 0);
        SET @AvailableBalance = @CurrentBalance - @PendingOutgoingAmount;

        IF (@AvailableBalance - @Amount) < @MinBalance
        BEGIN RAISERROR('Insufficient available funds: withdrawal would breach minimum balance.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @TransactionTypeID INT;
        SELECT @TransactionTypeID = TransactionTypeID FROM dbo.TransactionType WHERE TypeName = 'Withdrawal';
        IF @TransactionTypeID IS NULL
        BEGIN RAISERROR('Withdrawal transaction type is not configured.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @DelaySeconds INT = dbo.fn_GetCompletionDelaySeconds(@Amount);
        SET @ReadyToCompleteAt = DATEADD(SECOND, @DelaySeconds, GETDATE());

        INSERT INTO dbo.Transactions
            (TransactionTypeID, FromAccountID, ToAccountID, EmployeeID, Amount,
             TransactionStatus, ReadyToCompleteAt, CompletedAt, Description)
        VALUES
            (@TransactionTypeID, @AccountID, NULL, @EffectiveEmployeeID, @Amount,
             'Pending', @ReadyToCompleteAt, NULL, @Description);

        SET @TransactionID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@UserID, 'WithdrawalInitiated', 'Transactions', @TransactionID,
                CONCAT('Withdrawal of ', @Amount, ' from AccountID ', @AccountID,
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
