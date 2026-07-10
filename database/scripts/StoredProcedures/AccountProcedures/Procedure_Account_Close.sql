/* =========================================================
   Procedure_Account_Close.sql
   sp_Account_Close
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Effective Employee/Admin/HighAdmin can close accounts.
   - Customer users cannot close accounts through this procedure.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Account_Close', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Account_Close;
GO

CREATE PROCEDURE dbo.sp_Account_Close
(
    @AccountID INT,
    @UserID INT,
    @ReasonDescription NVARCHAR(200) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF dbo.fn_UserHasEffectiveRole(@UserID, N'Employee') = 0
           AND dbo.fn_UserHasEffectiveRole(@UserID, N'Admin') = 0
           AND dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin') = 0
        BEGIN RAISERROR('Only an effective Employee, Admin, or HighAdmin can close accounts.', 16, 1); RETURN; END;

        DECLARE @CallerEmployeeID INT;
        SELECT @CallerEmployeeID = EmployeeID FROM dbo.Users WHERE UserID = @UserID;

        BEGIN TRANSACTION;

        DECLARE @CurrentStatus NVARCHAR(20), @ClosingBalance DECIMAL(18,2), @BranchID INT, @AccountNumber NVARCHAR(30);
        SELECT @CurrentStatus = AccountStatus, @ClosingBalance = Balance, @BranchID = BranchID, @AccountNumber = AccountNumber
        FROM dbo.Account WITH (UPDLOCK, HOLDLOCK)
        WHERE AccountID = @AccountID;

        IF @CurrentStatus IS NULL
        BEGIN RAISERROR('Account does not exist.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CurrentStatus = 'Closed'
        BEGIN RAISERROR('Account is already closed.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CurrentStatus = 'Frozen'
        BEGIN RAISERROR('Frozen account must be unfrozen before closure.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;
        IF EXISTS (SELECT 1 FROM dbo.Transactions WHERE TransactionStatus = 'Pending' AND (FromAccountID=@AccountID OR ToAccountID=@AccountID))
        BEGIN RAISERROR('Cannot close an account that has a Pending transaction.', 16, 1); ROLLBACK TRANSACTION; RETURN; END;

        UPDATE dbo.Account
        SET Balance = 0,
            AccountStatus = 'Closed',
            CloseDate = CAST(GETDATE() AS DATE),
            FrozenPreviousStatus = NULL
        WHERE AccountID = @AccountID;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        VALUES (@UserID, 'AccountClosed', 'Account', @AccountID,
                CONCAT('Account ', @AccountNumber, ' closed. CallerEmployeeID=', ISNULL(CONVERT(NVARCHAR(20),@CallerEmployeeID),'NULL'),
                       '; Closing balance ', @ClosingBalance, '; BranchID ', @BranchID,
                       '; Reason: ', ISNULL(@ReasonDescription, 'not provided')));

        COMMIT TRANSACTION;
        SELECT @AccountID AS AccountID, @AccountNumber AS AccountNumber, @ClosingBalance AS ClosingBalance, 'Closed' AS AccountStatus;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN;
    END CATCH
END;
GO
