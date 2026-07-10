/* =========================================================
   Procedure_Loan_Create.sql
   sp_Loan_Create
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Effective Employee/Admin/HighAdmin can create loans.
   - Customer-only users cannot create loans directly here.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Loan_Create','P') IS NOT NULL DROP PROCEDURE dbo.sp_Loan_Create;
GO
CREATE PROCEDURE dbo.sp_Loan_Create
(
    @CustomerID INT,@BranchID INT,@LoanAmount DECIMAL(18,2),@InterestRate DECIMAL(5,2),@NumberOfInstallments INT,@StartDate DATE=NULL,@LoanID INT OUTPUT,@UserID INT=NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET @LoanID=NULL;
    BEGIN TRY
        IF @UserID IS NULL OR (dbo.fn_UserHasEffectiveRole(@UserID,N'Employee')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'Admin')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'HighAdmin')=0) BEGIN RAISERROR('Only an effective Employee, Admin, or HighAdmin can create loans.',16,1); RETURN; END;
        IF @LoanAmount IS NULL OR @LoanAmount<=0 BEGIN RAISERROR('Loan amount must be greater than zero.',16,1); RETURN; END;
        IF @InterestRate IS NULL OR @InterestRate<0 BEGIN RAISERROR('Interest rate cannot be negative.',16,1); RETURN; END;
        IF @NumberOfInstallments IS NULL OR @NumberOfInstallments<1 BEGIN RAISERROR('Number of installments must be at least 1.',16,1); RETURN; END;
        IF @NumberOfInstallments>360 BEGIN RAISERROR('Number of installments cannot exceed 360.',16,1); RETURN; END;
        IF @StartDate IS NULL SET @StartDate=CAST(GETDATE() AS DATE);
        BEGIN TRANSACTION;
        IF NOT EXISTS(SELECT 1 FROM dbo.Customer WHERE CustomerID=@CustomerID AND IsActive=1) BEGIN RAISERROR('Customer does not exist or is inactive.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF NOT EXISTS(SELECT 1 FROM dbo.Branch WHERE BranchID=@BranchID) BEGIN RAISERROR('Branch does not exist.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        DECLARE @TotalToRepay DECIMAL(18,2),@BaseInstallmentAmt DECIMAL(18,2),@LastInstallmentAmt DECIMAL(18,2);
        SET @TotalToRepay=ROUND(@LoanAmount*(1+@InterestRate/100.0),2); SET @BaseInstallmentAmt=ROUND(@TotalToRepay/@NumberOfInstallments,2); SET @LastInstallmentAmt=@TotalToRepay-(@BaseInstallmentAmt*(@NumberOfInstallments-1));
        INSERT INTO dbo.Loan(CustomerID,BranchID,LoanAmount,InterestRate,StartDate,EndDate,LoanStatus) VALUES(@CustomerID,@BranchID,@LoanAmount,@InterestRate,@StartDate,DATEADD(MONTH,@NumberOfInstallments,@StartDate),'Active');
        SET @LoanID=CONVERT(INT,SCOPE_IDENTITY());
        ;WITH Seq AS(SELECT 1 AS InstallmentNumber UNION ALL SELECT InstallmentNumber+1 FROM Seq WHERE InstallmentNumber<@NumberOfInstallments)
        INSERT INTO dbo.Installment(LoanID,DueDate,Amount,PaidDate,InstallmentStatus,PaymentTransactionID)
        SELECT @LoanID,DATEADD(MONTH,InstallmentNumber,@StartDate),CASE WHEN InstallmentNumber=@NumberOfInstallments THEN @LastInstallmentAmt ELSE @BaseInstallmentAmt END,NULL,'Pending',NULL FROM Seq OPTION(MAXRECURSION 1000);
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details) VALUES(@UserID,'LoanCreated','Loan',@LoanID,CONCAT('Loan of ',@LoanAmount,' at ',@InterestRate,'% over ',@NumberOfInstallments,' installments for CustomerID ',@CustomerID));
        COMMIT TRANSACTION;
        SELECT @LoanID AS LoanID;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO
