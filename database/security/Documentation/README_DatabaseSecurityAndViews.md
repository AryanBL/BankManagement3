# Database Security and Views Module

This module adds a database-level security layer on top of the application-level security already implemented in the BankManagement project.

## Final terminology

| Term | Meaning |
|---|---|
| Application user | A real bank-system person stored in `dbo.Users`, linked to `dbo.Customer` and optionally `dbo.Employee`. |
| Application role | A business role stored in `dbo.Roles` and `dbo.UserRoles`: `Customer`, `Employee`, `Admin`, `HighAdmin`. |
| Effective role | The currently valid business role after checking `Users.IsActive`, `Customer.IsActive`, and `Employee.EmpStatus`. |
| Database login | SQL Server instance-level principal that can connect to SQL Server. |
| Database user | Database-level principal inside the BankManagement database. |
| Database role | SQL Server permission group used to grant database permissions. |
| View | A controlled read-only projection of base tables. |
| Stored procedure | The main controlled interface for changing data and running business operations. |

## Important design decision

The project does **not** create one SQL Server login/database user for every real customer or employee.

Real application users remain in:

```sql
 dbo.Users
 dbo.Roles
 dbo.UserRoles
 dbo.UserSessions / dbo.Sessions
```

Database users are technical access personas:

```text
BankAppUser
BankReportUser
BankAuditorUser
BankHighAdminReportUser
BankMaintenanceUser
```

This avoids duplicating passwords and identity management in both the banking application and SQL Server.

## Files and order

Run the files in this order:

```text
1. Scripts/Views/01_BankManagement_ReportingViews.sql
2. Scripts/Security/01_DatabaseRolesAndUsers.sql
3. Scripts/Security/02_DatabasePrivileges.sql
4. Scripts/Security/03_DatabaseSecurity_TestQueries.sql   optional
```

The full SQLCMD installer is:

```text
Scripts/00_Install_DatabaseSecurityAndViews_SQLCMD.sql
```

Run it only with SQLCMD mode enabled in SSMS.

## Database roles created

| Role | Purpose |
|---|---|
| `dbrole_bank_app_executor` | Technical role for the application backend. It can execute stored procedures. |
| `dbrole_bank_reporting` | Read-only reporting role. It can select from reporting views only. |
| `dbrole_bank_auditor` | Read-only audit role. It can select from audit and ledger views. |
| `dbrole_bank_highadmin_viewer` | Read-only database-level oversight role for HighAdmin-style reports. |
| `dbrole_bank_maintenance` | Metadata visibility role for maintenance/documentation. |

## Database users created

| User | Role membership | Intended use |
|---|---|---|
| `BankAppUser` | `dbrole_bank_app_executor` | Application backend connection user. |
| `BankReportUser` | `dbrole_bank_reporting` | Read-only dashboards and reports. |
| `BankAuditorUser` | `dbrole_bank_auditor` | Audit trail and ledger review. |
| `BankHighAdminReportUser` | `dbrole_bank_highadmin_viewer` | Global read-only oversight reports. |
| `BankMaintenanceUser` | `dbrole_bank_maintenance` | Metadata review and maintenance support. |

By default, users are created `WITHOUT LOGIN`. This keeps the module safe and avoids hard-coded passwords.

If real SQL Server logins are needed, create the logins in `master`, then re-run `01_DatabaseRolesAndUsers.sql` to map the database users to those logins.

## Views created

| View | Purpose |
|---|---|
| `dbo.vw_CustomerBasicProfile` | Customer profile with masked National ID. |
| `dbo.vw_CustomerAccountSummary` | Customer accounts, branch, account type, balance, and available balance. |
| `dbo.vw_AccountOperationalSummary` | Operational account overview for dashboards. |
| `dbo.vw_EmployeeDirectory` | Current employee directory without salary. |
| `dbo.vw_HighAdmin_EmployeeBranchOverview` | Complete employee and branch-assignment history, including salary. |
| `dbo.vw_PendingTransactions` | Pending transaction queue. |
| `dbo.vw_LoanOperationalSummary` | Loan and installment summary. |
| `dbo.vw_HighAdmin_BranchFinancialOverview` | Branch balance, account totals, employees, and balance reconciliation. |
| `dbo.vw_HighAdmin_UserAccessOverview` | User and role overview without password hashes or session tokens. |
| `dbo.vw_AuditTrail_Safe` | Audit log with actor username. |
| `dbo.vw_BranchLedgerReport` | Branch ledger movement report. |
| `dbo.vw_DailyTransactionSummary` | Daily aggregate transaction summary. |
| `dbo.vw_AccountStatusSummary` | Account status counts and balances by branch. |
| `dbo.vw_LoanOverdueSummary` | Overdue/defaulted installment summary. |

## Base table access

The module does not grant direct access to base tables such as:

```text
dbo.Customer
dbo.Account
dbo.Transactions
dbo.Users
dbo.UserRoles
dbo.Sessions
dbo.AuditLog
```

Normal access should happen through stored procedures and controlled views.

## Application-level versus database-level security

Database-level security protects the database from direct access.

Application-level security still controls business rules such as:

```text
Customer can view only own accounts.
Employee can search customers.
Admin can manage ordinary employees.
HighAdmin can view global information.
```

Those rules remain inside procedures and helper functions such as:

```sql
dbo.fn_UserHasEffectiveRole
sp_User_Login
sp_User_ValidateSession
```
