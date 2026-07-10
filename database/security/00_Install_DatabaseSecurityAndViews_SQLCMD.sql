/* =========================================================
   00_Install_DatabaseSecurityAndViews_SQLCMD.sql
   ---------------------------------------------------------
   SQLCMD installer for the DatabaseSecurityAndViews module.
   Enable SQLCMD Mode in SSMS before running this file.
   ========================================================= */

:r .\Views\01_BankManagement_ReportingViews.sql
:r .\Security\01_DatabaseRolesAndUsers.sql
:r .\Security\02_DatabasePrivileges.sql

PRINT 'DatabaseSecurityAndViews module installed successfully.';
GO
