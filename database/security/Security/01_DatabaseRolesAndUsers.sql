/* =========================================================
   01_DatabaseRolesAndUsers.sql
   ---------------------------------------------------------
   Defines SQL Server database-level security personas for the
   BankManagement project.

   IMPORTANT TERMINOLOGY:
     - Application users are real bank users stored in dbo.Users.
     - Database users are SQL Server security principals used by
       the application, reporting tools, auditors, or maintenance.

   This script creates database roles and database users. By
   default, users are created WITHOUT LOGIN so the script is safe
   to run in a demo database without hard-coded passwords.

   Optional real connection logins:
     If a SQL Server login with the expected name already exists,
     this script maps the database user to that login. Otherwise,
     it creates the database user WITHOUT LOGIN.

   Optional login names expected by this script:
     - BankAppLogin
     - BankReportLogin
     - BankAuditorLogin
     - BankHighAdminReportLogin
     - BankMaintenanceLogin

   Run AFTER:
     - TableCreation.sql
     - ApplyAccessRules.sql
     - View creation module
   ========================================================= */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------
   1) Create database roles.
   --------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_app_executor' AND type = 'R')
    CREATE ROLE dbrole_bank_app_executor;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_reporting' AND type = 'R')
    CREATE ROLE dbrole_bank_reporting;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_auditor' AND type = 'R')
    CREATE ROLE dbrole_bank_auditor;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_highadmin_viewer' AND type = 'R')
    CREATE ROLE dbrole_bank_highadmin_viewer;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dbrole_bank_maintenance' AND type = 'R')
    CREATE ROLE dbrole_bank_maintenance;
GO

/* ---------------------------------------------------------
   2) Create or map database users.
   --------------------------------------------------------- */
IF SUSER_ID(N'BankAppLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAppUser')
        EXEC(N'CREATE USER [BankAppUser] FOR LOGIN [BankAppLogin]');
    ELSE
        EXEC(N'ALTER USER [BankAppUser] WITH LOGIN = [BankAppLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAppUser')
BEGIN
    EXEC(N'CREATE USER [BankAppUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankReportLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankReportUser')
        EXEC(N'CREATE USER [BankReportUser] FOR LOGIN [BankReportLogin]');
    ELSE
        EXEC(N'ALTER USER [BankReportUser] WITH LOGIN = [BankReportLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankReportUser')
BEGIN
    EXEC(N'CREATE USER [BankReportUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankAuditorLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAuditorUser')
        EXEC(N'CREATE USER [BankAuditorUser] FOR LOGIN [BankAuditorLogin]');
    ELSE
        EXEC(N'ALTER USER [BankAuditorUser] WITH LOGIN = [BankAuditorLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankAuditorUser')
BEGIN
    EXEC(N'CREATE USER [BankAuditorUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankHighAdminReportLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankHighAdminReportUser')
        EXEC(N'CREATE USER [BankHighAdminReportUser] FOR LOGIN [BankHighAdminReportLogin]');
    ELSE
        EXEC(N'ALTER USER [BankHighAdminReportUser] WITH LOGIN = [BankHighAdminReportLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankHighAdminReportUser')
BEGIN
    EXEC(N'CREATE USER [BankHighAdminReportUser] WITHOUT LOGIN');
END;
GO

IF SUSER_ID(N'BankMaintenanceLogin') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankMaintenanceUser')
        EXEC(N'CREATE USER [BankMaintenanceUser] FOR LOGIN [BankMaintenanceLogin]');
    ELSE
        EXEC(N'ALTER USER [BankMaintenanceUser] WITH LOGIN = [BankMaintenanceLogin]');
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'BankMaintenanceUser')
BEGIN
    EXEC(N'CREATE USER [BankMaintenanceUser] WITHOUT LOGIN');
END;
GO

/* ---------------------------------------------------------
   3) Add users to roles idempotently.
   --------------------------------------------------------- */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_app_executor' AND m.name = N'BankAppUser'
)
    ALTER ROLE dbrole_bank_app_executor ADD MEMBER BankAppUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_reporting' AND m.name = N'BankReportUser'
)
    ALTER ROLE dbrole_bank_reporting ADD MEMBER BankReportUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_auditor' AND m.name = N'BankAuditorUser'
)
    ALTER ROLE dbrole_bank_auditor ADD MEMBER BankAuditorUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_highadmin_viewer' AND m.name = N'BankHighAdminReportUser'
)
    ALTER ROLE dbrole_bank_highadmin_viewer ADD MEMBER BankHighAdminReportUser;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_maintenance' AND m.name = N'BankMaintenanceUser'
)
    ALTER ROLE dbrole_bank_maintenance ADD MEMBER BankMaintenanceUser;
GO

/* ---------------------------------------------------------
   OPTIONAL: create SQL Server logins in master.
   ---------------------------------------------------------
   This section is intentionally commented out to avoid storing
   passwords in project source code. If you need real SQL logins,
   run the following in the master database and replace passwords:

   USE master;
   CREATE LOGIN BankAppLogin WITH PASSWORD = 'Replace_With_Strong_Password_1!';
   CREATE LOGIN BankReportLogin WITH PASSWORD = 'Replace_With_Strong_Password_2!';
   CREATE LOGIN BankAuditorLogin WITH PASSWORD = 'Replace_With_Strong_Password_3!';
   CREATE LOGIN BankHighAdminReportLogin WITH PASSWORD = 'Replace_With_Strong_Password_4!';
   CREATE LOGIN BankMaintenanceLogin WITH PASSWORD = 'Replace_With_Strong_Password_5!';

   Then return to the BankManagement database and re-run this file.
   --------------------------------------------------------- */

PRINT 'Database roles and users created/mapped successfully.';
GO
