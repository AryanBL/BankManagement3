/* =========================================================
   Procedure_User_Login_FINAL.sql
   sp_User_Login
   ---------------------------------------------------------
   PURPOSE:
   Final shared application login procedure for all application
   roles in the Bank Management system:

       Customer
       Employee
       Admin
       HighAdmin

   FINAL SECURITY MODEL:
   1. Login requires exactly one identifier plus password.
   2. Supported login identifiers:
        - Username
        - UserID
        - CustomerID
        - EmployeeID
   3. ID-based login still requires the correct password.
      UserID / CustomerID / EmployeeID are identifiers, not secrets.
   4. Users.IsActive controls whether the login account can log in.
   5. Every login user must have CustomerID and an active Customer row.
   6. Employee.EmpStatus controls employee/admin privilege effectiveness.
      Fired/suspended employees may still log in as Customer.
   7. Admin is effective only for active Branch Manager / Vice Manager
      employees with CanAccessAdmin = 1.
   8. HighAdmin is effective only if assigned HighAdmin role and the
      user is not linked to EmployeeID.
   9. The returned @Roles value is the EFFECTIVE role list, not the
      raw UserRoles list.
   10. Every session has an absolute expiration time. The default
       lifetime is 10 minutes and is not extended by activity.

   OUTPUT:
   - @UserID
   - @CustomerID
   - @EmployeeID
   - @SessionToken
   - @Roles = effective roles, comma-separated
   - @ExpiresAt = absolute session expiration timestamp

   REQUIREMENTS:
   - dbo.Users with IsActive
   - dbo.Customer with IsActive
   - dbo.Employee
   - dbo.Roles
   - dbo.UserRoles
   - dbo.Sessions
   - dbo.AuditLog
   - dbo.fn_HashPassword
   ========================================================= */

IF OBJECT_ID('dbo.sp_User_Login', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_User_Login;
GO

CREATE PROCEDURE dbo.sp_User_Login
(
    @Username NVARCHAR(50) = NULL,
    @Password NVARCHAR(4000) = NULL,

    @LoginUserID INT = NULL,
    @LoginCustomerID INT = NULL,
    @LoginEmployeeID INT = NULL,
    @SessionTtlMinutes INT = 10,

    @UserID INT OUTPUT,
    @CustomerID INT OUTPUT,
    @EmployeeID INT OUTPUT,
    @SessionToken NVARCHAR(200) OUTPUT,
    @Roles NVARCHAR(MAX) OUTPUT,
    @ExpiresAt DATETIME = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @UserID = NULL;
    SET @CustomerID = NULL;
    SET @EmployeeID = NULL;
    SET @SessionToken = NULL;
    SET @Roles = NULL;
    SET @ExpiresAt = NULL;

    BEGIN TRY
        ------------------------------------------------------------
        -- 1. Validate login identifier input.
        --    Exactly one identifier is required.
        ------------------------------------------------------------
        DECLARE @CleanUsername NVARCHAR(50);
        SET @CleanUsername = NULLIF(LTRIM(RTRIM(@Username)), N'');

        DECLARE @IdentifierCount INT;
        SET @IdentifierCount =
              CASE WHEN @CleanUsername IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN @LoginUserID IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN @LoginCustomerID IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN @LoginEmployeeID IS NOT NULL THEN 1 ELSE 0 END;

        IF @IdentifierCount = 0
        BEGIN
            RAISERROR('Provide one login identifier: Username, UserID, CustomerID, or EmployeeID.', 16, 1);
            RETURN;
        END;

        IF @IdentifierCount > 1
        BEGIN
            RAISERROR('Provide only one login identifier at a time.', 16, 1);
            RETURN;
        END;

        IF @Password IS NULL OR LEN(@Password) = 0
        BEGIN
            RAISERROR('Password is required.', 16, 1);
            RETURN;
        END;

        IF @SessionTtlMinutes IS NULL
            SET @SessionTtlMinutes = 10;

        IF @SessionTtlMinutes < 1 OR @SessionTtlMinutes > 1440
        BEGIN
            RAISERROR('SessionTtlMinutes must be between 1 and 1440.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 2. Verify password and locate the active application user.
        --    Users.IsActive is the whole-login switch.
        --    Employee.EmpStatus is NOT checked here as a login blocker,
        --    because terminated/on-leave employees may still use their
        --    Customer capabilities.
        ------------------------------------------------------------
        DECLARE @PasswordHash CHAR(64);
        SET @PasswordHash = dbo.fn_HashPassword(@Password);

        SELECT
            @UserID = U.UserID,
            @CustomerID = U.CustomerID,
            @EmployeeID = U.EmployeeID
        FROM dbo.Users AS U
        WHERE U.PasswordHash = @PasswordHash
          AND U.IsActive = 1
          AND
          (
                (@CleanUsername IS NOT NULL AND U.Username = @CleanUsername)
             OR (@LoginUserID IS NOT NULL AND U.UserID = @LoginUserID)
             OR (@LoginCustomerID IS NOT NULL AND U.CustomerID = @LoginCustomerID)
             OR (@LoginEmployeeID IS NOT NULL AND U.EmployeeID = @LoginEmployeeID)
          );

        IF @UserID IS NULL
        BEGIN
            RAISERROR('Invalid login identifier/password or inactive user account.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 3. Every user must have an active Customer profile.
        --    This includes employees, managers, and HighAdmin.
        ------------------------------------------------------------
        IF @CustomerID IS NULL OR NOT EXISTS
        (
            SELECT 1
            FROM dbo.Customer AS C
            WHERE C.CustomerID = @CustomerID
              AND C.IsActive = 1
        )
        BEGIN
            RAISERROR('Login denied: missing or inactive customer profile.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 4. Load raw role flags from UserRoles.
        ------------------------------------------------------------
        DECLARE @HasCustomer BIT,
                @HasEmployee BIT,
                @HasAdmin BIT,
                @HasHighAdmin BIT;

        SET @HasCustomer = CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Customer'
        ) THEN 1 ELSE 0 END;

        SET @HasEmployee = CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Employee'
        ) THEN 1 ELSE 0 END;

        SET @HasAdmin = CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Admin'
        ) THEN 1 ELSE 0 END;

        SET @HasHighAdmin = CASE WHEN EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'HighAdmin'
        ) THEN 1 ELSE 0 END;

        IF @HasCustomer = 0
        BEGIN
            RAISERROR('Login denied: user does not have Customer role.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 5. HighAdmin must not be linked to EmployeeID.
        ------------------------------------------------------------
        IF @HasHighAdmin = 1 AND @EmployeeID IS NOT NULL
        BEGIN
            RAISERROR('Login denied: HighAdmin user must not be linked to EmployeeID.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 6. Calculate EFFECTIVE Employee/Admin privileges.
        --    Raw roles may exist historically, but if employment status
        --    or manager privilege is no longer valid, the effective role
        --    is removed from the login result.
        ------------------------------------------------------------
        DECLARE @EmployeeIsActive BIT,
                @AdminIsEffective BIT;

        SET @EmployeeIsActive = 0;
        SET @AdminIsEffective = 0;

        IF @HasEmployee = 1
           AND @EmployeeID IS NOT NULL
           AND EXISTS
           (
               SELECT 1
               FROM dbo.Employee AS E
               WHERE E.EmployeeID = @EmployeeID
                 AND E.EmpStatus = N'Active'
           )
        BEGIN
            SET @EmployeeIsActive = 1;
        END;

        IF @HasAdmin = 1
           AND @EmployeeIsActive = 1
           AND EXISTS
           (
               SELECT 1
               FROM dbo.Employee AS E
               WHERE E.EmployeeID = @EmployeeID
                 AND E.EmpStatus = N'Active'
                 AND E.CanAccessAdmin = 1
                 AND E.JobTitle IN (N'Branch Manager', N'Vice Manager')
           )
        BEGIN
            SET @AdminIsEffective = 1;
        END;

        ------------------------------------------------------------
        -- 7. Build effective role list returned to the application.
        ------------------------------------------------------------
        DECLARE @RoleList TABLE
        (
            RoleName NVARCHAR(50) NOT NULL PRIMARY KEY
        );

        INSERT INTO @RoleList(RoleName)
        VALUES(N'Customer');

        IF @EmployeeIsActive = 1
            INSERT INTO @RoleList(RoleName) VALUES(N'Employee');

        IF @AdminIsEffective = 1
            INSERT INTO @RoleList(RoleName) VALUES(N'Admin');

        IF @HasHighAdmin = 1
            INSERT INTO @RoleList(RoleName) VALUES(N'HighAdmin');

        SELECT @Roles = STUFF
        (
            (
                SELECT N',' + RoleName
                FROM @RoleList
                ORDER BY RoleName
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'),
            1, 1, N''
        );

        ------------------------------------------------------------
        -- 8. Create a new active session with a fixed absolute
        --    expiration time. Activity does not extend ExpiresAt.
        ------------------------------------------------------------
        DECLARE @LoginTime DATETIME;
        SET @LoginTime = GETDATE();
        SET @ExpiresAt = DATEADD(MINUTE, @SessionTtlMinutes, @LoginTime);

        -- Opportunistically close previously expired sessions so the
        -- IsActive flag remains consistent even if they are never used again.
        UPDATE dbo.Sessions
        SET IsActive = 0,
            LogoutTime = COALESCE(LogoutTime, @LoginTime)
        WHERE IsActive = 1
          AND ExpiresAt <= @LoginTime;

        SET @SessionToken = CONVERT(NVARCHAR(36), NEWID())
                          + N'-'
                          + CONVERT(NVARCHAR(36), NEWID());

        INSERT INTO dbo.Sessions
        (
            UserID,
            SessionToken,
            LoginTime,
            ExpiresAt,
            LogoutTime,
            IsActive
        )
        VALUES
        (
            @UserID,
            @SessionToken,
            @LoginTime,
            @ExpiresAt,
            NULL,
            1
        );

        ------------------------------------------------------------
        -- 9. Audit successful login.
        ------------------------------------------------------------
        DECLARE @LoginMethod NVARCHAR(30);
        SET @LoginMethod = CASE
            WHEN @CleanUsername IS NOT NULL THEN N'Username'
            WHEN @LoginUserID IS NOT NULL THEN N'UserID'
            WHEN @LoginCustomerID IS NOT NULL THEN N'CustomerID'
            WHEN @LoginEmployeeID IS NOT NULL THEN N'EmployeeID'
            ELSE N'Unknown'
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
            N'UserLogin',
            N'Users',
            @UserID,
            @LoginTime,
            CONCAT(N'User logged in. LoginMethod=', @LoginMethod,
                   N'; EffectiveRoles=', ISNULL(@Roles, N''),
                   N'; SessionTTLMinutes=', @SessionTtlMinutes)
        );

        ------------------------------------------------------------
        -- 10. Return login context.
        ------------------------------------------------------------
        SELECT
            @UserID AS UserID,
            @CustomerID AS CustomerID,
            @EmployeeID AS EmployeeID,
            @SessionToken AS SessionToken,
            @Roles AS EffectiveRoles,
            @LoginTime AS LoginTime,
            @ExpiresAt AS ExpiresAt;
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
