/* =========================================================
   Procedure_Loan_PayInstallment.sql
   sp_Loan_PayInstallment
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Only the borrower can pay an installment.
   - The paying account must also belong to the borrower.
   - Employee/Admin/HighAdmin privileges do not bypass ownership.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Loan_PayInstallment','P') IS NOT NULL DROP PROCEDURE dbo.sp_Loan_PayInstallment;
GO
CREATE PROCEDURE dbo.sp_Loan_PayInstallment
(
    @InstallmentID INT,@FromAccountID INT,@EmployeeID INT=NULL,@TransactionID INT OUTPUT,@ReadyToCompleteAt DATETIME OUTPUT,@UserID INT=NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET @TransactionID=NULL; SET @ReadyToCompleteAt=NULL;
    BEGIN TRY
        IF @UserID IS NULL OR dbo.fn_UserHasEffectiveRole(@UserID,N'Customer')=0 BEGIN RAISERROR('A valid authenticated user is required.',16,1); RETURN; END;
        BEGIN TRANSACTION;
        DECLARE @LoanID INT,@Amount DECIMAL(18,2),@InstallmentStatus NVARCHAR(20),@ExistingPaymentTxID INT,@LoanCustomerID INT,@LoanStatus NVARCHAR(20),@CallerCustomerID INT;
        SELECT @LoanID=i.LoanID,@Amount=i.Amount,@InstallmentStatus=i.InstallmentStatus,@ExistingPaymentTxID=i.PaymentTransactionID FROM dbo.Installment i WHERE i.InstallmentID=@InstallmentID;
        SELECT @CallerCustomerID=CustomerID FROM dbo.Users WHERE UserID=@UserID;
        IF @LoanID IS NULL BEGIN RAISERROR('Installment does not exist.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @InstallmentStatus='Paid' BEGIN RAISERROR('This installment has already been paid.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @InstallmentStatus='Defaulted' BEGIN RAISERROR('This installment has been marked Defaulted and can no longer be paid directly.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @ExistingPaymentTxID IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.Transactions WHERE TransactionID=@ExistingPaymentTxID AND TransactionStatus='Pending') BEGIN RAISERROR('A payment for this installment is already pending completion.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @LoanCustomerID=CustomerID,@LoanStatus=LoanStatus FROM dbo.Loan WHERE LoanID=@LoanID;
        IF @LoanStatus<>'Active' BEGIN RAISERROR('This loan is not Active; no further payments are expected.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @LoanCustomerID<>@CallerCustomerID BEGIN RAISERROR('Only the borrower can pay this loan installment.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF NOT EXISTS(SELECT 1 FROM dbo.Account WHERE AccountID=@FromAccountID AND CustomerID=@LoanCustomerID) BEGIN RAISERROR('The paying account does not belong to the customer who owns this loan.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        EXEC dbo.sp_Transaction_Withdrawal @AccountID=@FromAccountID,@Amount=@Amount,@EmployeeID=@EmployeeID,@Description=N'Loan installment payment',@TransactionID=@TransactionID OUTPUT,@ReadyToCompleteAt=@ReadyToCompleteAt OUTPUT,@UserID=@UserID;
        IF @@TRANCOUNT=0 BEGIN RAISERROR('Installment payment could not be initiated: the withdrawal was rejected.',16,1); RETURN; END;
        UPDATE dbo.Installment SET PaymentTransactionID=@TransactionID WHERE InstallmentID=@InstallmentID;
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details) VALUES(@UserID,'InstallmentPaymentInitiated','Installment',@InstallmentID,CONCAT('Payment of ',@Amount,' queued via TransactionID ',@TransactionID,'; ready at ',CONVERT(VARCHAR(30),@ReadyToCompleteAt,121)));
        COMMIT TRANSACTION;
        SELECT @TransactionID AS TransactionID,@ReadyToCompleteAt AS ReadyToCompleteAt;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO
