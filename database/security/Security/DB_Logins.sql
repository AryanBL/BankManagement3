USE [master];
GO

IF SUSER_ID(N'BankReportLogin') IS NULL
BEGIN
    CREATE LOGIN [BankReportLogin]
    WITH PASSWORD = N'BankReport',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
ELSE
BEGIN
    ALTER LOGIN [BankReportLogin] ENABLE;
    ALTER LOGIN [BankReportLogin]
    WITH PASSWORD = N'BankReport',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
GO

IF SUSER_ID(N'BankAuditorLogin') IS NULL
BEGIN
    CREATE LOGIN [BankAuditorLogin]
    WITH PASSWORD = N'BankAudit',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
ELSE
BEGIN
    ALTER LOGIN [BankAuditorLogin] ENABLE;
    ALTER LOGIN [BankAuditorLogin]
    WITH PASSWORD = N'BankAudit',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
GO

IF SUSER_ID(N'BankHighAdminReportLogin') IS NULL
BEGIN
    CREATE LOGIN [BankHighAdminReportLogin]
    WITH PASSWORD = N'BankHighAdminReport',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
ELSE
BEGIN
    ALTER LOGIN [BankHighAdminReportLogin] ENABLE;
    ALTER LOGIN [BankHighAdminReportLogin]
    WITH PASSWORD = N'BankHighAdminReport',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
GO

USE [BankManagement];
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE sid = SUSER_SID(N'BankReportLogin')
)
BEGIN
    CREATE USER [BankReportRuntimeUser] FOR LOGIN [BankReportLogin];
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE sid = SUSER_SID(N'BankAuditorLogin')
)
BEGIN
    CREATE USER [BankAuditorRuntimeUser] FOR LOGIN [BankAuditorLogin];
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE sid = SUSER_SID(N'BankHighAdminReportLogin')
)
BEGIN
    CREATE USER [BankHighAdminReportRuntimeUser] FOR LOGIN [BankHighAdminReportLogin];
END
GO

ALTER ROLE [dbrole_bank_reporting] ADD MEMBER [BankReportRuntimeUser];
ALTER ROLE [dbrole_bank_auditor] ADD MEMBER [BankAuditorRuntimeUser];
ALTER ROLE [dbrole_bank_highadmin_viewer] ADD MEMBER [BankHighAdminReportRuntimeUser];
GO