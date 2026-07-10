/* =========================================================
   Procedure_Account_Freeze_Unfreeze.sql
   sp_Account_Freeze / sp_Account_Unfreeze
   ---------------------------------------------------------
   FINAL AUTHORIZATION:
   - Freeze: effective Employee/Admin/HighAdmin.
   - Unfreeze: effective Admin or HighAdmin.
   ========================================================= */

IF OBJECT_ID('dbo.sp_Account_Freeze', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_Account_Freeze;
GO
CREATE PROCEDURE dbo.sp_Account_Freeze
(
    @AccountID INT,
    @UserID INT,
    @ReasonDescription NVARCHAR(200) = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        IF dbo.fn_UserHasEffectiveRole(@UserID,N'Employee')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'Admin')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'HighAdmin')=0
        BEGIN RAISERROR('Only an effective Employee, Admin, or HighAdmin can freeze accounts.',16,1); RETURN; END;
        BEGIN TRANSACTION;
        DECLARE @CurrentStatus NVARCHAR(20);
        SELECT @CurrentStatus=AccountStatus FROM dbo.Account WITH (UPDLOCK,HOLDLOCK) WHERE AccountID=@AccountID;
        IF @CurrentStatus IS NULL BEGIN RAISERROR('Account does not exist.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CurrentStatus='Closed' BEGIN RAISERROR('Closed account cannot be frozen.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CurrentStatus='Frozen' BEGIN RAISERROR('Account is already frozen.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        UPDATE dbo.Account SET AccountStatus='Frozen', FrozenPreviousStatus=@CurrentStatus WHERE AccountID=@AccountID;
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details)
        VALUES(@UserID,'AccountFrozen','Account',@AccountID,CONCAT('Previous status: ',@CurrentStatus,'. Reason: ',ISNULL(@ReasonDescription,'not provided')));
        COMMIT TRANSACTION;
        SELECT @AccountID AS AccountID, 'Frozen' AS AccountStatus, @CurrentStatus AS PreviousStatus;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO

IF OBJECT_ID('dbo.sp_Account_Unfreeze', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_Account_Unfreeze;
GO
CREATE PROCEDURE dbo.sp_Account_Unfreeze
(
    @AccountID INT,
    @UserID INT,
    @ReasonDescription NVARCHAR(200) = NULL
)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        IF dbo.fn_UserHasEffectiveRole(@UserID,N'Admin')=0 AND dbo.fn_UserHasEffectiveRole(@UserID,N'HighAdmin')=0
        BEGIN RAISERROR('Only an effective Admin or HighAdmin can unfreeze accounts.',16,1); RETURN; END;
        BEGIN TRANSACTION;
        DECLARE @CurrentStatus NVARCHAR(20), @RestoreStatus NVARCHAR(20);
        SELECT @CurrentStatus=AccountStatus, @RestoreStatus=ISNULL(FrozenPreviousStatus,'Active') FROM dbo.Account WITH (UPDLOCK,HOLDLOCK) WHERE AccountID=@AccountID;
        IF @CurrentStatus IS NULL BEGIN RAISERROR('Account does not exist.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @CurrentStatus <> 'Frozen' BEGIN RAISERROR('Only a Frozen account can be unfrozen.',16,1); ROLLBACK TRANSACTION; RETURN; END;
        IF @RestoreStatus NOT IN ('Active','Dormant') SET @RestoreStatus='Active';
        UPDATE dbo.Account SET AccountStatus=@RestoreStatus, FrozenPreviousStatus=NULL WHERE AccountID=@AccountID;
        INSERT INTO dbo.AuditLog(UserID,ActionType,TableName,RecordID,Details)
        VALUES(@UserID,'AccountUnfrozen','Account',@AccountID,CONCAT('Restored status: ',@RestoreStatus,'. Reason: ',ISNULL(@ReasonDescription,'not provided')));
        COMMIT TRANSACTION;
        SELECT @AccountID AS AccountID, @RestoreStatus AS AccountStatus;
    END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; DECLARE @Msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@Msg,16,1); RETURN; END CATCH
END;
GO
