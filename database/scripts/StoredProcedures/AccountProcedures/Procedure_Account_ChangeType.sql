/* =========================================================
   Procedure_Account_ChangeType.sql
   sp_Account_ChangeType
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Effective Employee/Admin/HighAdmin can change account type.
   - Any Pending transaction on the account blocks the change.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Account_ChangeType', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_Account_ChangeType;
GO
CREATE PROCEDURE dbo.sp_Account_ChangeType
(
    @AccountID INT,
    @NewAccountTypeID INT,
    @UserID INT,
    @ReasonDescription NVARCHAR(200) = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        IF dbo.fn_UserHasEffectiveRole(@UserID,N'Employee')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'Admin')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'HighAdmin')=0
        BEGIN RAISERROR('Only an effective Employee, Admin, or HighAdmin can change account type.',16,1); RETURN; END;
        BEGIN TRANSACTION;
        DECLARE @CurrentTypeID INT,@CurrentStatus NVARCHAR(20),@Balance DECIMAL(18,2),@PendingOutgoing DECIMAL(18,2),@AvailableBalance DECIMAL(18,2),@NewMinBalance DECIMAL(18,2),@OldTypeName NVARCHAR(50),@NewTypeName NVARCHAR(50),@PendingTransactionCount INT;
        SELECT @CurrentTypeID=A.AccountTypeID,@CurrentStatus=A.AccountStatus,@Balance=A.Balance FROM dbo.Account A WITH(UPDLOCK,HOLDLOCK) WHERE A.AccountID=@AccountID;
        IF @CurrentStatus IS NULL BEGIN RAISERROR('Account does not exist.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CurrentStatus IN ('Closed','Frozen') BEGIN RAISERROR('Account type can be changed only for Active or Dormant accounts.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @PendingTransactionCount=COUNT(1) FROM dbo.Transactions WITH(UPDLOCK,HOLDLOCK) WHERE TransactionStatus='Pending' AND (FromAccountID=@AccountID OR ToAccountID=@AccountID);
        IF @PendingTransactionCount>0 BEGIN RAISERROR('Cannot change account type while the account has pending transactions.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CurrentTypeID=@NewAccountTypeID BEGIN RAISERROR('Account already has this account type.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @NewMinBalance=MinBalance,@NewTypeName=TypeName FROM dbo.AccountType WHERE AccountTypeID=@NewAccountTypeID;
        IF @NewMinBalance IS NULL BEGIN RAISERROR('Target account type does not exist.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        SELECT @OldTypeName=TypeName FROM dbo.AccountType WHERE AccountTypeID=@CurrentTypeID;
        SELECT @PendingOutgoing=PendingOutgoingAmount FROM dbo.vw_AccountPendingOutgoing WHERE AccountID=@AccountID;
        SET @PendingOutgoing=ISNULL(@PendingOutgoing,0); SET @AvailableBalance=@Balance-@PendingOutgoing;
        IF @AvailableBalance < @NewMinBalance BEGIN RAISERROR('Cannot change account type: available balance is below target minimum balance.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        UPDATE dbo.Account SET AccountTypeID=@NewAccountTypeID WHERE AccountID=@AccountID;
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details)
        VALUES(@UserID,'AccountTypeChanged','Account',@AccountID,CONCAT('From ',ISNULL(@OldTypeName,CAST(@CurrentTypeID AS NVARCHAR(20))),' to ',@NewTypeName,'. Reason: ',ISNULL(@ReasonDescription,'not provided')));
        COMMIT TRANSACTION;
        SELECT @AccountID AS AccountID,@CurrentTypeID AS OldAccountTypeID,@NewAccountTypeID AS NewAccountTypeID,@AvailableBalance AS AvailableBalance,@NewMinBalance AS NewMinBalance,@PendingTransactionCount AS PendingTransactionCount;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO
