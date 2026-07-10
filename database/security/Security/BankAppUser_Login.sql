USE [master];
GO

IF SUSER_ID(N'BankAppLogin') IS NULL
BEGIN
    CREATE LOGIN [BankAppLogin]
    WITH PASSWORD = N'BankApp_Pass',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
ELSE
BEGIN
    ALTER LOGIN [BankAppLogin] ENABLE;

    ALTER LOGIN [BankAppLogin]
    WITH PASSWORD = N'BankApp_Pass',
         CHECK_POLICY = OFF,
         CHECK_EXPIRATION = OFF,
         DEFAULT_DATABASE = [BankManagement];
END
GO

USE [BankManagement];
GO

IF USER_ID(N'BankAppRuntimeUser') IS NULL
BEGIN
    CREATE USER [BankAppRuntimeUser] FOR LOGIN [BankAppLogin];
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = N'dbrole_bank_app_executor'
)
AND NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    INNER JOIN sys.database_principals r
        ON r.principal_id = drm.role_principal_id
    INNER JOIN sys.database_principals m
        ON m.principal_id = drm.member_principal_id
    WHERE r.name = N'dbrole_bank_app_executor'
      AND m.name = N'BankAppRuntimeUser'
)
BEGIN
    ALTER ROLE [dbrole_bank_app_executor] ADD MEMBER [BankAppRuntimeUser];
END
GO