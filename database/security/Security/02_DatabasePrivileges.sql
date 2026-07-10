/* =========================================================
   02_DatabasePrivileges.sql
   ---------------------------------------------------------
   Grants database-level permissions for the BankManagement
   project. The design is:

     - No direct table access for application/report/audit users.
     - Application service user executes stored procedures.
     - Reporting/audit users read controlled views only.
     - Business authorization remains inside dbo.Users/dbo.Roles
       and procedure-level checks.

   Run AFTER:
     - 01_BankManagement_ReportingViews.sql
     - 01_DatabaseRolesAndUsers.sql
   ========================================================= */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------
   1) Remove accidental direct DML permissions from project roles.
   REVOKE is safe even if no permission was previously granted.
   We do not use DENY because DENY can create unnecessary conflicts
   during testing and maintenance.
   --------------------------------------------------------- */
DECLARE @RoleName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

DECLARE role_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.database_principals
WHERE name IN
(
    N'dbrole_bank_app_executor',
    N'dbrole_bank_reporting',
    N'dbrole_bank_auditor',
    N'dbrole_bank_highadmin_viewer',
    N'dbrole_bank_maintenance'
);

OPEN role_cursor;
FETCH NEXT FROM role_cursor INTO @RoleName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'';

    SELECT @Sql = @Sql +
        N'REVOKE SELECT, INSERT, UPDATE, DELETE ON OBJECT::'
        + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
        + N' TO ' + QUOTENAME(@RoleName) + N';' + CHAR(13) + CHAR(10)
    FROM sys.tables AS t
    WHERE SCHEMA_NAME(t.schema_id) = N'dbo';

    IF LEN(@Sql) > 0 EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM role_cursor INTO @RoleName;
END;
CLOSE role_cursor;
DEALLOCATE role_cursor;
GO

/* ---------------------------------------------------------
   2) BankAppUser: application backend technical user.
   It can execute procedures. The procedures themselves enforce
   application roles using @UserID/session/effective-role logic.
   --------------------------------------------------------- */
GRANT EXECUTE ON SCHEMA::dbo TO dbrole_bank_app_executor;
GO

GRANT SELECT ON dbo.vw_CustomerBasicProfile TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_CustomerAccountSummary TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_AccountOperationalSummary TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_EmployeeDirectory TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_PendingTransactions TO dbrole_bank_app_executor;
GRANT SELECT ON dbo.vw_LoanOperationalSummary TO dbrole_bank_app_executor;
GO

/* ---------------------------------------------------------
   3) Reporting role: aggregate and operational read-only views.
   --------------------------------------------------------- */
GRANT SELECT ON dbo.vw_CustomerBasicProfile TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_CustomerAccountSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_AccountOperationalSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_EmployeeDirectory TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_PendingTransactions TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_LoanOperationalSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_HighAdmin_BranchFinancialOverview TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_DailyTransactionSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_AccountStatusSummary TO dbrole_bank_reporting;
GRANT SELECT ON dbo.vw_LoanOverdueSummary TO dbrole_bank_reporting;
GO

/* ---------------------------------------------------------
   4) Auditor role: audit and financial trace views.
   --------------------------------------------------------- */
GRANT SELECT ON dbo.vw_AuditTrail_Safe TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_BranchLedgerReport TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_DailyTransactionSummary TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_AccountStatusSummary TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_LoanOverdueSummary TO dbrole_bank_auditor;
GRANT SELECT ON dbo.vw_HighAdmin_UserAccessOverview TO dbrole_bank_auditor;
GO

/* ---------------------------------------------------------
   5) HighAdmin reporting role: full read-only oversight views.
   This is still a database-level reporting persona, not the same
   thing as the application HighAdmin stored in dbo.Users.
   --------------------------------------------------------- */
GRANT SELECT ON dbo.vw_CustomerBasicProfile TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_CustomerAccountSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_AccountOperationalSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_EmployeeDirectory TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_HighAdmin_EmployeeBranchOverview TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_HighAdmin_BranchFinancialOverview TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_HighAdmin_UserAccessOverview TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_AuditTrail_Safe TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_BranchLedgerReport TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_DailyTransactionSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_AccountStatusSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_LoanOperationalSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_LoanOverdueSummary TO dbrole_bank_highadmin_viewer;
GRANT SELECT ON dbo.vw_PendingTransactions TO dbrole_bank_highadmin_viewer;
GO

/* ---------------------------------------------------------
   6) Maintenance role: metadata visibility only by default.
   Real DBA maintenance can be performed by db_owner/sysadmin.
   --------------------------------------------------------- */
GRANT VIEW DEFINITION TO dbrole_bank_maintenance;
GO

PRINT 'Database permissions granted successfully.';
GO
