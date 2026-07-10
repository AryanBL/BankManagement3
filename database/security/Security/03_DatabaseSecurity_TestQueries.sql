/* =========================================================
   03_DatabaseSecurity_TestQueries.sql
   ---------------------------------------------------------
   Optional test queries for database-level security.
   Run as a database owner/sysadmin in a test database.
   These tests use EXECUTE AS USER with the WITHOUT LOGIN users
   created by 01_DatabaseRolesAndUsers.sql.
   ========================================================= */
SET NOCOUNT ON;
GO

PRINT 'Testing BankReportUser: SELECT from view should work.';
EXECUTE AS USER = 'BankReportUser';
SELECT TOP (5) * FROM dbo.vw_DailyTransactionSummary;
REVERT;
GO

PRINT 'Testing BankReportUser: direct SELECT from dbo.Customer should fail unless user has extra permissions.';
BEGIN TRY
    EXECUTE AS USER = 'BankReportUser';
    SELECT TOP (5) * FROM dbo.Customer;
    PRINT 'WARNING: direct table SELECT succeeded. Check for extra permissions such as db_owner or explicit table grants.';
END TRY
BEGIN CATCH
    PRINT 'Expected failure for direct table access: ' + ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    REVERT;
END TRY
BEGIN CATCH
    -- Already reverted or no impersonation context existed.
END CATCH;
GO

PRINT 'Testing BankAuditorUser: audit view should work.';
EXECUTE AS USER = 'BankAuditorUser';
SELECT TOP (5) * FROM dbo.vw_AuditTrail_Safe;
REVERT;
GO

PRINT 'Testing BankAppUser: procedure execution should be granted. Actual business authorization still depends on procedure parameters and application effective roles.';
EXECUTE AS USER = 'BankAppUser';
SELECT HAS_PERMS_BY_NAME('dbo.sp_User_Login', 'OBJECT', 'EXECUTE') AS CanExecuteLoginProcedure;
REVERT;
GO
