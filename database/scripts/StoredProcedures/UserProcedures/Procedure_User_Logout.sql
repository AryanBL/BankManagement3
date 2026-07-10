/* =========================================================
   Procedure_User_Logout_FINAL.sql
   sp_User_Logout
   ---------------------------------------------------------
   PURPOSE:
   Final shared logout procedure for every application role:

       Customer
       Employee
       Admin
       HighAdmin

   RULES:
   1. Logout is session-token based.
   2. The session must currently be active.
   3. Logout does not depend on Employee.EmpStatus.
      Even if an employee was suspended/terminated after login,
      the user can still close the session normally.
   4. The procedure marks the session inactive, sets LogoutTime,
      and writes AuditLog.
   ========================================================= */

IF OBJECT_ID('dbo.sp_User_Logout', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_User_Logout;
GO

CREATE PROCEDURE dbo.sp_User_Logout
(
    @SessionToken NVARCHAR(200)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @SessionID INT,
            @UserID INT,
            @LogoutTime DATETIME;

        IF @SessionToken IS NULL OR LEN(LTRIM(RTRIM(@SessionToken))) = 0
        BEGIN
            RAISERROR('Session token is required.', 16, 1);
            RETURN;
        END;

        SELECT
            @SessionID = S.SessionID,
            @UserID = S.UserID
        FROM dbo.Sessions AS S WITH (UPDLOCK, HOLDLOCK)
        WHERE S.SessionToken = @SessionToken
          AND S.IsActive = 1;

        IF @SessionID IS NULL
        BEGIN
            RAISERROR('Invalid or inactive session token.', 16, 1);
            RETURN;
        END;

        SET @LogoutTime = GETDATE();

        UPDATE dbo.Sessions
        SET IsActive = 0,
            LogoutTime = @LogoutTime
        WHERE SessionID = @SessionID
          AND IsActive = 1;

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
            N'UserLogout',
            N'Sessions',
            @SessionID,
            GETDATE(),
            N'User logged out.'
        );

        SELECT
            @UserID AS UserID,
            @SessionID AS SessionID,
            @LogoutTime AS LogoutTime,
            N'LoggedOut' AS Result;
    END TRY
    BEGIN CATCH
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
        RETURN;
    END CATCH
END;
GO
