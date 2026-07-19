/* =========================================================
   Procedure_Loan_GetStatus.sql
   sp_Loan_GetStatus
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Customer can view only own loans.
   - Effective Employee/Admin/HighAdmin can view any loan.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Loan_GetStatus','P') IS NOT NULL DROP PROCEDURE dbo.sp_Loan_GetStatus;
GO
CREATE PROCEDURE dbo.sp_Loan_GetStatus
(
    @LoanID INT,
    @UserID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    IF @UserID IS NULL OR dbo.fn_UserHasEffectiveRole(@UserID,N'Customer')=0 BEGIN RAISERROR('A valid authenticated user is required.',16,1); RETURN; END;
    DECLARE @LoanCustomerID INT,@CallerCustomerID INT;
    SELECT @LoanCustomerID=CustomerID FROM dbo.Loan WHERE LoanID=@LoanID;
    SELECT @CallerCustomerID=CustomerID FROM dbo.Users WHERE UserID=@UserID;
    IF @LoanCustomerID IS NULL BEGIN RAISERROR('Loan does not exist.',16,1); RETURN; END;
    IF dbo.fn_UserHasEffectiveRole(@UserID,N'Employee')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'Admin')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'HighAdmin')=0 AND @LoanCustomerID<>@CallerCustomerID BEGIN RAISERROR('Customer users can view only their own loan status.',16,1); RETURN; END;
    SELECT l.LoanID,l.CustomerID,c.FirstName,c.LastName,l.BranchID,l.LoanAmount,l.InterestRate,l.LoanAmount*(1+l.InterestRate/100.0) AS TotalToRepay,l.StartDate,l.EndDate,l.LoanStatus,COUNT(i.InstallmentID) AS TotalInstallments,SUM(CASE WHEN i.InstallmentStatus='Paid' THEN 1 ELSE 0 END) AS PaidInstallments,SUM(CASE WHEN i.InstallmentStatus='Paid' THEN i.Amount ELSE 0 END) AS AmountPaid,SUM(CASE WHEN i.InstallmentStatus<>'Paid' THEN i.Amount ELSE 0 END) AS AmountRemaining,SUM(CASE WHEN i.InstallmentStatus<>'Paid' AND i.DueDate<CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS OverdueInstallments
    FROM dbo.Loan l JOIN dbo.Customer c ON l.CustomerID=c.CustomerID LEFT JOIN dbo.Installment i ON i.LoanID=l.LoanID WHERE l.LoanID=@LoanID GROUP BY l.LoanID,l.CustomerID,c.FirstName,c.LastName,l.BranchID,l.LoanAmount,l.InterestRate,l.StartDate,l.EndDate,l.LoanStatus;
    SELECT i.InstallmentID,i.DueDate,i.Amount,i.PaidDate,i.InstallmentStatus AS StoredStatus,CASE WHEN i.InstallmentStatus IN ('Paid','Defaulted') THEN i.InstallmentStatus WHEN tr.TransactionStatus='Pending' THEN 'PaymentPending' WHEN i.DueDate<CAST(GETDATE() AS DATE) THEN 'Late' ELSE 'Pending' END AS DisplayStatus,i.PaymentTransactionID,tr.TransactionStatus AS PaymentTransactionStatus,tr.ReadyToCompleteAt AS PaymentReadyToCompleteAt
    FROM dbo.Installment i LEFT JOIN dbo.Transactions tr ON tr.TransactionID=i.PaymentTransactionID WHERE i.LoanID=@LoanID ORDER BY i.DueDate;
END;
GO
