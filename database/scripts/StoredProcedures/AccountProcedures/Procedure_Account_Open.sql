/* =========================================================
   Procedure_Account_Open_SELF_SERVICE_FIXED.sql
   ---------------------------------------------------------
   PURPOSE:
   Customer self-service account creation procedure.

   IMPORTANT DESIGN RULES:
   - The customer opens the account without Employee involvement.
   - The application sends the authenticated UserID, not CustomerID.
   - The procedure derives CustomerID from dbo.Users internally.
   - The customer selects the BranchID.
   - Account.Balance starts with AccountType.MinBalance.
   - Optional InitialDeposit is added through dbo.sp_Transaction_Deposit
     and therefore follows the normal Pending transaction workflow.
   - MonthlyFee is ignored here.

   COMPATIBILITY NOTES:
   - Uses DROP + CREATE instead of CREATE OR ALTER to avoid version issues.
   - Uses RAISERROR instead of THROW to avoid parser/version issues.
   - Does NOT reference AccountType.IsActive because the current
     dbo.AccountType table does not contain that column.

   REQUIRED OBJECTS:
   - dbo.Users, with IsActive column
   - dbo.Customer, with IsActive column
   - dbo.Roles and dbo.UserRoles
   - dbo.Branch
   - dbo.AccountType
   - dbo.Account
   - dbo.seq_AccountNumber
   - dbo.sp_Transaction_Deposit
   - dbo.AuditLog
   ========================================================= */

IF OBJECT_ID('dbo.sp_Account_Open', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_Open;
GO

CREATE PROCEDURE dbo.sp_Account_Open
(
    @UserID INT,
    @BranchID INT,
    @AccountTypeID INT,
    @InitialDeposit DECIMAL(18,2) = 0,

    @AccountID INT OUTPUT,
    @AccountNumber NVARCHAR(12) OUTPUT,
    @InitialDepositTransactionID INT OUTPUT,
    @InitialDepositReadyToCompleteAt DATETIME OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @AccountID = NULL;
    SET @AccountNumber = NULL;
    SET @InitialDepositTransactionID = NULL;
    SET @InitialDepositReadyToCompleteAt = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @CustomerID INT;

        SELECT @CustomerID = U.CustomerID
        FROM dbo.Users AS U
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND U.CustomerID IS NOT NULL;

        IF @CustomerID IS NULL
        BEGIN
            RAISERROR('Invalid or inactive customer user.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = 'Customer'
        )
        BEGIN
            RAISERROR('Only users with the Customer role can open accounts by self-service.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Customer AS C
            WHERE C.CustomerID = @CustomerID
              AND C.IsActive = 1
        )
        BEGIN
            RAISERROR('The linked customer record is invalid or inactive.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Branch AS B
            WHERE B.BranchID = @BranchID
        )
        BEGIN
            RAISERROR('Invalid branch.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        DECLARE @MinBalance DECIMAL(18,2);
        DECLARE @AccountTypeName NVARCHAR(50);

        SELECT
            @MinBalance = AT.MinBalance,
            @AccountTypeName = AT.TypeName
        FROM dbo.AccountType AS AT
        WHERE AT.AccountTypeID = @AccountTypeID;

        IF @MinBalance IS NULL
        BEGIN
            RAISERROR('Invalid account type.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @MinBalance < 0
        BEGIN
            RAISERROR('Account type minimum balance cannot be negative.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @InitialDeposit IS NULL
            SET @InitialDeposit = 0;

        IF @InitialDeposit < 0
        BEGIN
            RAISERROR('Initial deposit cannot be negative.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF OBJECT_ID('dbo.seq_AccountNumber', 'SO') IS NULL
        BEGIN
            RAISERROR('Missing dbo.seq_AccountNumber. Run the account-module support schema first.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        DECLARE @SeqValue BIGINT;
        SET @SeqValue = NEXT VALUE FOR dbo.seq_AccountNumber;

        IF @SeqValue > 999999999999
        BEGIN
            RAISERROR('Account number sequence exceeded the 12-digit limit.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SET @AccountNumber = RIGHT(REPLICATE('0', 12) + CAST(@SeqValue AS NVARCHAR(12)), 12);

        INSERT INTO dbo.Account
        (
            AccountNumber,
            CustomerID,
            BranchID,
            AccountTypeID,
            Balance,
            AccountStatus,
            OpenDate
        )
        VALUES
        (
            @AccountNumber,
            @CustomerID,
            @BranchID,
            @AccountTypeID,
            @MinBalance,
            'Active',
            CAST(GETDATE() AS DATE)
        );

        SET @AccountID = CONVERT(INT, SCOPE_IDENTITY());

        IF @InitialDeposit > 0
        BEGIN
            EXEC dbo.sp_Transaction_Deposit
                @AccountID = @AccountID,
                @Amount = @InitialDeposit,
                @EmployeeID = NULL,
                @Description = N'Initial deposit during self-service account opening.',
                @TransactionID = @InitialDepositTransactionID OUTPUT,
                @ReadyToCompleteAt = @InitialDepositReadyToCompleteAt OUTPUT,
                @UserID = @UserID;
        END;

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
            'ACCOUNT_OPEN_SELF_SERVICE',
            'Account',
            @AccountID,
            GETDATE(),
            CONCAT(
                'CustomerID=', @CustomerID,
                '; BranchID=', @BranchID,
                '; AccountTypeID=', @AccountTypeID,
                '; AccountType=', ISNULL(@AccountTypeName, ''),
                '; MinBalance=', @MinBalance,
                '; InitialDeposit=', @InitialDeposit,
                '; AccountNumber=', @AccountNumber
            )
        );

        COMMIT TRANSACTION;
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
