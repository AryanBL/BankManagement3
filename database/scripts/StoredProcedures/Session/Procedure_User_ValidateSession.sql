/* =========================================================
   Procedure_User_ValidateSession_FINAL.sql
   sp_User_ValidateSession
   ---------------------------------------------------------
   PURPOSE:
   Final shared session-validation procedure for every
   application role in the Bank Management system:

       Customer
       Employee
       Admin
       HighAdmin

   FINAL SECURITY MODEL:
   1. Session validation is based on an active, unexpired SessionToken.
      ExpiresAt is absolute and is not extended by request activity.
   2. Users.IsActive controls whether the login account itself
      is allowed to use the application.
   3. Every login user must have CustomerID and an active Customer
      row. This includes employees, managers, and HighAdmin.
   4. Employee.EmpStatus controls Employee/Admin privilege
      effectiveness only.
      - If an employee is Terminated or OnLeave, the session can
        still be valid as Customer.
      - Employee/Admin effective roles are removed.
   5. Admin is effective only for an active Branch Manager or Vice
      Manager with CanAccessAdmin = 1.
   6. HighAdmin is effective only when the user has HighAdmin role
      and is not linked to EmployeeID.
   7. The returned EffectiveRoles value is calculated dynamically
      from current user/customer/employee state.

   OPTIONAL AUTHORIZATION CHECK:
   - @RequiredRole may be NULL.
   - If provided, it must be one of:
       Customer, Employee, Admin, HighAdmin
   - The procedure raises an error if that role is not currently
     effective for the session.

   AUDIT NOTE:
   - This procedure intentionally does NOT write AuditLog on every
     validation call, because session validation may be called very
     frequently by the application.
   - Login/logout procedures handle audit logging.

   REQUIREMENTS:
   - dbo.Sessions
   - dbo.Users with IsActive
   - dbo.Customer with IsActive
   - dbo.Employee
   - dbo.Roles
   - dbo.UserRoles
   - dbo.EMPB
   ========================================================= */

IF OBJECT_ID('dbo.sp_User_ValidateSession', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_User_ValidateSession;
GO

CREATE PROCEDURE dbo.sp_User_ValidateSession
(
    @SessionToken NVARCHAR(200),
    @RequiredRole NVARCHAR(50) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        ------------------------------------------------------------
        -- 1. Validate input.
        ------------------------------------------------------------
        DECLARE @CleanSessionToken NVARCHAR(200);
        DECLARE @CleanRequiredRole NVARCHAR(50);

        SET @CleanSessionToken = NULLIF(LTRIM(RTRIM(@SessionToken)), N'');
        SET @CleanRequiredRole = NULLIF(LTRIM(RTRIM(@RequiredRole)), N'');

        IF @CleanSessionToken IS NULL
        BEGIN
            RAISERROR('Session token is required.', 16, 1);
            RETURN;
        END;

        IF @CleanRequiredRole IS NOT NULL
           AND @CleanRequiredRole NOT IN (N'Customer', N'Employee', N'Admin', N'HighAdmin')
        BEGIN
            RAISERROR('Invalid RequiredRole. Allowed values are Customer, Employee, Admin, HighAdmin.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 2. Resolve the session and enforce its absolute expiry.
        --    Expiration is checked before roles or business access.
        ------------------------------------------------------------
        DECLARE
            @SessionID INT,
            @UserID INT,
            @CustomerID INT,
            @EmployeeID INT,
            @LoginTime DATETIME,
            @ExpiresAt DATETIME,
            @SessionIsActive BIT,
            @UserIsActive BIT,
            @Username NVARCHAR(50),
            @Now DATETIME;

        SET @Now = GETDATE();

        SELECT
            @SessionID = S.SessionID,
            @UserID = U.UserID,
            @CustomerID = U.CustomerID,
            @EmployeeID = U.EmployeeID,
            @LoginTime = S.LoginTime,
            @ExpiresAt = S.ExpiresAt,
            @SessionIsActive = S.IsActive,
            @UserIsActive = U.IsActive,
            @Username = U.Username
        FROM dbo.Sessions AS S
        INNER JOIN dbo.Users AS U
            ON U.UserID = S.UserID
        WHERE S.SessionToken = @CleanSessionToken;

        IF @SessionID IS NULL
        BEGIN
            RAISERROR('Invalid session token.', 16, 1);
            RETURN;
        END;

        IF @SessionIsActive = 0
        BEGIN
            RAISERROR('Session is inactive. Please sign in again.', 16, 1);
            RETURN;
        END;

        IF @ExpiresAt IS NULL OR @ExpiresAt <= @Now
        BEGIN
            UPDATE dbo.Sessions
            SET IsActive = 0,
                LogoutTime = COALESCE(LogoutTime, @Now)
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
                N'SessionExpired',
                N'Sessions',
                @SessionID,
                @Now,
                N'Session expired after its fixed lifetime.'
            );

            RAISERROR('Session expired. Please sign in again.', 16, 1);
            RETURN;
        END;

        IF @UserIsActive = 0
        BEGIN
            RAISERROR('Invalid session: user account is inactive.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 3. Every valid application user must have an active
        --    Customer profile, including employees and HighAdmin.
        ------------------------------------------------------------
        IF @CustomerID IS NULL OR NOT EXISTS
        (
            SELECT 1
            FROM dbo.Customer AS C
            WHERE C.CustomerID = @CustomerID
              AND C.IsActive = 1
        )
        BEGIN
            RAISERROR('Invalid session: missing or inactive customer profile.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 4. Load raw role flags.
        --    These are assigned roles, not necessarily effective.
        ------------------------------------------------------------
        DECLARE
            @HasCustomer BIT,
            @HasEmployee BIT,
            @HasAdmin BIT,
            @HasHighAdmin BIT;

        SET @HasCustomer = 0;
        SET @HasEmployee = 0;
        SET @HasAdmin = 0;
        SET @HasHighAdmin = 0;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Customer'
        )
            SET @HasCustomer = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Employee'
        )
            SET @HasEmployee = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Admin'
        )
            SET @HasAdmin = 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'HighAdmin'
        )
            SET @HasHighAdmin = 1;

        IF @HasCustomer = 0
        BEGIN
            RAISERROR('Invalid session: user does not have Customer role.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 5. Validate HighAdmin identity consistency.
        --    HighAdmin is a central user with CustomerID but no
        --    EmployeeID, and should not be mixed with Employee/Admin.
        ------------------------------------------------------------
        IF @HasHighAdmin = 1 AND @EmployeeID IS NOT NULL
        BEGIN
            RAISERROR('Invalid session: HighAdmin user must not be linked to EmployeeID.', 16, 1);
            RETURN;
        END;

        IF @HasHighAdmin = 1 AND (@HasEmployee = 1 OR @HasAdmin = 1)
        BEGIN
            RAISERROR('Invalid session: HighAdmin role cannot be combined with Employee or Admin roles.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 6. Calculate current employee/admin context.
        --    Employee/Admin may become ineffective if the employee
        --    is suspended or terminated after login.
        ------------------------------------------------------------
        DECLARE
            @EmployeeStatus NVARCHAR(20),
            @JobTitle NVARCHAR(100),
            @CanAccessAdmin BIT,
            @EmployeeIsActive BIT,
            @AdminIsEffective BIT,
            @HighAdminIsEffective BIT,
            @CurrentBranchID INT,
            @CurrentBranchName NVARCHAR(100);

        SET @EmployeeStatus = NULL;
        SET @JobTitle = NULL;
        SET @CanAccessAdmin = 0;
        SET @EmployeeIsActive = 0;
        SET @AdminIsEffective = 0;
        SET @HighAdminIsEffective = 0;
        SET @CurrentBranchID = NULL;
        SET @CurrentBranchName = NULL;

        IF @EmployeeID IS NOT NULL
        BEGIN
            SELECT
                @EmployeeStatus = E.EmpStatus,
                @JobTitle = E.JobTitle,
                @CanAccessAdmin = E.CanAccessAdmin
            FROM dbo.Employee AS E
            WHERE E.EmployeeID = @EmployeeID;

            SELECT TOP (1)
                @CurrentBranchID = EB.BranchID,
                @CurrentBranchName = B.BranchName
            FROM dbo.EMPB AS EB
            INNER JOIN dbo.Branch AS B
                ON B.BranchID = EB.BranchID
            WHERE EB.EmployeeID = @EmployeeID
              AND EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
            ORDER BY EB.StartDate DESC, EB.EMPBID DESC;
        END;

        IF @HasEmployee = 1
           AND @EmployeeID IS NOT NULL
           AND @EmployeeStatus = N'Active'
        BEGIN
            SET @EmployeeIsActive = 1;
        END;

        IF @HasAdmin = 1
           AND @EmployeeIsActive = 1
           AND @CanAccessAdmin = 1
           AND @JobTitle IN (N'Branch Manager', N'Vice Manager')
        BEGIN
            SET @AdminIsEffective = 1;
        END;

        IF @HasHighAdmin = 1
           AND @EmployeeID IS NULL
        BEGIN
            SET @HighAdminIsEffective = 1;
        END;

        ------------------------------------------------------------
        -- 7. Build effective role list.
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

        IF @HighAdminIsEffective = 1
            INSERT INTO @RoleList(RoleName) VALUES(N'HighAdmin');

        DECLARE @EffectiveRoles NVARCHAR(MAX);

        SELECT @EffectiveRoles = STUFF
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
        -- 8. Optional required-role authorization check.
        ------------------------------------------------------------
        IF @CleanRequiredRole IS NOT NULL
           AND NOT EXISTS
           (
               SELECT 1
               FROM @RoleList
               WHERE RoleName = @CleanRequiredRole
           )
        BEGIN
            RAISERROR('Session is valid, but the required role is not currently effective for this user.', 16, 1);
            RETURN;
        END;

        ------------------------------------------------------------
        -- 9. Return current session/user context.
        ------------------------------------------------------------
        SELECT
            @SessionID AS SessionID,
            @UserID AS UserID,
            @Username AS Username,
            @CustomerID AS CustomerID,
            @EmployeeID AS EmployeeID,
            @CurrentBranchID AS CurrentBranchID,
            @CurrentBranchName AS CurrentBranchName,
            @EmployeeStatus AS EmployeeStatus,
            @JobTitle AS JobTitle,
            @CanAccessAdmin AS CanAccessAdmin,
            @LoginTime AS LoginTime,
            @ExpiresAt AS ExpiresAt,
            DATEDIFF(SECOND, @Now, @ExpiresAt) AS SecondsUntilExpiration,
            @EffectiveRoles AS EffectiveRoles,
            CASE WHEN EXISTS (SELECT 1 FROM @RoleList WHERE RoleName = N'Customer') THEN 1 ELSE 0 END AS IsCustomerEffective,
            @EmployeeIsActive AS IsEmployeeEffective,
            @AdminIsEffective AS IsAdminEffective,
            @HighAdminIsEffective AS IsHighAdminEffective;
    END TRY
    BEGIN CATCH
        DECLARE @Msg NVARCHAR(4000);
        DECLARE @Severity INT;
        DECLARE @State INT;

        SET @Msg = ERROR_MESSAGE();
        SET @Severity = ERROR_SEVERITY();
        SET @State = ERROR_STATE();

        RAISERROR(@Msg, @Severity, @State);
        RETURN;
    END CATCH
END;
GO
