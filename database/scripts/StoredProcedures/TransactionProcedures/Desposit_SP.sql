/* =========================================================
   Procedure_Deposit.sql
   sp_Transaction_Deposit
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Every authenticated user can deposit only into an account
     owned by the same CustomerID linked to the login.
   - Employee/Admin/HighAdmin privileges do not bypass ownership.
   - @EmployeeID is metadata only and must match the authenticated
     employee when supplied.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Transaction_Deposit', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Transaction_Deposit;
GO

CREATE PROCEDURE dbo.sp_Transaction_Deposit
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
        BEGIN RAISERROR('A valid authenticated user is required for deposit.', 16, 1); RETURN; END;
        IF @Amount IS NULL OR @Amount <= 0
        BEGIN RAISERROR('Deposit amount must be greater than zero.', 16, 1); RETURN; END;

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
            BEGIN RAISERROR('Customer/HighAdmin deposits cannot provide EmployeeID metadata.', 16, 1); RETURN; END;
            SET @EffectiveEmployeeID = NULL;
        END;

        SELECT @AccountCustomerID = CustomerID FROM dbo.Account WHERE AccountID = @AccountID;
        IF @AccountCustomerID IS NULL
        BEGIN RAISERROR('Account does not exist.', 16, 1); RETURN; END;

        IF @AccountCustomerID <> @CallerCustomerID
        BEGIN RAISERROR('Only the account owner can deposit into this account.', 16, 1); RETURN; END;

        BEGIN TRANSACTION;

        DECLARE @AccountStatus NVARCHAR(20);
        SELECT @AccountStatus = AccountStatus
        FROM dbo.Account WITH (UPDLOCK, HOLDLOCK)
        WHERE AccountID = @AccountID;

        IF @AccountStatus NOT IN ('Active', 'Dormant')
        BEGIN RAISERROR('Deposits are not allowed on a Closed or Frozen account.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @TransactionTypeID INT;
        SELECT @TransactionTypeID = TransactionTypeID FROM dbo.TransactionType WHERE TypeName = 'Deposit';
        IF @TransactionTypeID IS NULL
        BEGIN RAISERROR('Deposit transaction type is not configured.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        DECLARE @DelaySeconds INT = dbo.fn_GetCompletionDelaySeconds(@Amount);
        SET @ReadyToCompleteAt = DATEADD(SECOND, @DelaySeconds, GETDATE());

        INSERT INTO dbo.Transactions
            (TransactionTypeID, FromAccountID, ToAccountID, EmployeeID, Amount,
             TransactionStatus, ReadyToCompleteAt, CompletedAt, Description)
        VALUES
            (@TransactionTypeID, NULL, @AccountID, @EffectiveEmployeeID, @Amount,
             'Pending', @ReadyToCompleteAt, NULL, @Description);

        SET @TransactionID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@UserID, 'DepositInitiated', 'Transactions', @TransactionID,
                CONCAT('Deposit of ', @Amount, ' into AccountID ', @AccountID,
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
