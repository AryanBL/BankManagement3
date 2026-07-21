# BankManagement

BankManagement is a role-aware banking application built with Microsoft SQL Server, Node.js, Express, and a browser-based frontend written in HTML, CSS, and vanilla JavaScript. The database owns the core business rules through stored procedures, triggers, functions, constraints, transactions, and SQL Server Agent jobs. The backend exposes those operations as a REST API and the frontend provides separate workspaces for customers, employees, branch administrators, and the HighAdmin.

## Contents

- [Architecture](#architecture)
- [Technology stack](#technology-stack)
- [Roles and access model](#roles-and-access-model)
- [Main features](#main-features)
- [Database state rules](#database-state-rules)
- [Scheduled processing](#scheduled-processing)
- [Project structure](#project-structure)
- [Requirements](#requirements)
- [Database installation](#database-installation)
- [Backend configuration and startup](#backend-configuration-and-startup)
- [Frontend startup](#frontend-startup)
- [Initial HighAdmin setup](#initial-highadmin-setup)
- [Authentication and authorization](#authentication-and-authorization)
- [API overview](#api-overview)
- [Testing and verification](#testing-and-verification)
- [Operational notes](#operational-notes)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)

## Architecture

```text
Browser frontend
    |
    | HTTP/JSON + Bearer session token
    v
Node.js / Express API
    |
    | typed mssql parameters
    v
SQL Server stored procedures and reporting views
    |
    +-- tables, constraints, functions, and triggers
    +-- audit log and branch ledger
    +-- SQL Server Agent jobs
```

The project does not use an ORM. Route handlers call named stored procedures with typed parameters through the `mssql` driver. Authorization-sensitive rules are checked in both the Express layer and the database layer.

## Technology stack

### Backend

- Node.js
- Express 4
- `mssql` SQL Server driver
- Helmet
- CORS middleware
- Express rate limiting
- Morgan request logging
- Environment-based configuration with `dotenv`

### Database

- Microsoft SQL Server
- T-SQL stored procedures
- Triggers and constraints
- Database functions
- Reporting views
- SQL Server roles and least-privilege users
- SQL Server Agent jobs

### Frontend

- HTML5
- CSS3
- Vanilla JavaScript
- Fetch API
- Responsive role-specific workspaces
- Dependency-free Node.js static server

## Roles and access model

The application uses four effective roles:

| Role | Scope |
|---|---|
| `Customer` | Personal accounts, transactions, loans, and installments |
| `Employee` | Operational access limited to the employee's current branch |
| `Admin` | Branch management and maintenance operations within the current branch |
| `HighAdmin` | Cross-branch governance, manager administration, and global reports |

Every application user is linked to an active customer profile. Staff users may also have Employee and Admin privileges. Effective staff privileges depend on the employee's current status and current `EMPB` branch assignment.

### Effective-role rules

- `Active` employees may retain effective Employee access.
- `OnLeave` and `Terminated` employees lose effective Employee and Admin access.
- Admin access also requires an authorized manager job title and `CanAccessAdmin = 1`.
- HighAdmin is centrally scoped and is not restricted to one branch.
- Frontend role visibility is only a usability feature. The backend and database remain authoritative.

## Main features

### Authentication and sessions

- Customer signup
- One-time initial HighAdmin creation
- Username and password login
- Database-backed opaque session tokens
- Fixed session expiration
- Session validation on every protected request
- Logout and session invalidation
- Effective-role calculation during login and validation

### Customer management

- Search customers by name, National ID, phone, or email
- Branch-scoped customer visibility for Employee and Admin users
- Cross-branch search for HighAdmin
- Create, update, and deactivate customers
- Deactivation protection when pending operations exist
- Audit records for customer operations

### Accounts

- Open accounts with generated account numbers
- View personal or authorized branch accounts
- View account details and history
- Change account type
- Freeze and unfreeze accounts
- Close eligible accounts
- Dormant-account processing
- Monthly interest processing
- Branch-balance and branch-ledger synchronization

### Transactions

- Deposit
- Withdrawal
- Transfer
- Amount-based pending delays
- Manual finalization of one eligible transaction
- Automatic pending-transaction batch processing
- Completed-transaction reversal in the database/API

Transaction reversal is not part of the current supported frontend workflow. It is available only through the backend/API and its stored procedure.

### Loans and installments

- Create a loan and installment schedule
- View loan status and installment details
- Pay installments from an account owned by the borrower
- Synchronize installment status with the payment transaction
- Daily Late and Defaulted status reconciliation
- Mark a loan Paid when all installments are paid
- Freeze the borrower's Active or Dormant accounts when a loan becomes Defaulted

### Employees and branches

- Search employees within the authorized scope
- Hire ordinary employees
- Create employee application accounts
- Change job titles
- View assignment history
- Request and approve branch transfers
- Suspend and terminate employees
- Reactivate an `OnLeave` employee only by the same manager or HighAdmin user who recorded the latest suspension

### Managers and HighAdmin operations

- Hire branch managers
- Promote employees to manager roles
- Downgrade managers
- Replace a branch manager
- Suspend and terminate managers
- Reactivate an `OnLeave` manager only by the same HighAdmin user who recorded the latest suspension
- Prevent more than one active Branch Manager in one branch
- Access global reports, audit data, and branch-ledger data

### Reporting

- Role-filtered report catalogue
- Read-only reporting views
- Pagination
- CSV export from the frontend
- Separate report, audit, and HighAdmin report database connections

## Database state rules

### Account states

```text
Active -> Dormant
Active/Dormant -> Frozen
Frozen -> previous Active or Dormant state
Active/Dormant -> Closed
Dormant -> Active after a completed incoming deposit or transfer
```

- Dormant processing is performed by `dbo.sp_Account_DormantSweep`.
- Frozen accounts reject financial activity and monthly interest.
- Closed accounts are terminal and cannot be reopened by the application.
- `FrozenPreviousStatus` preserves whether a frozen account was Active or Dormant.

### Transaction states

```text
Pending -> Completed
Pending -> Failed
Pending -> Cancelled
Completed -> reversed correction transaction
```

The finalizer rechecks ownership, account status, minimum balance, available funds, and the transaction's `ReadyToCompleteAt` value before posting balances.

### Installment states

```text
Pending -> Late -> Defaulted
Pending/Late -> Paid
```

The displayed status may be calculated from the due date and pending payment state, while the stored status changes through procedures, triggers, or scheduled processing.

### Loan states

```text
Active -> Paid
Active -> Defaulted
```

A loan becomes Defaulted when at least one installment becomes Defaulted. At that transition, all Active or Dormant accounts owned by the borrower are frozen.

### Employee states

```text
Active -> OnLeave -> Active
Active/OnLeave -> Terminated
```

Suspension reversal is actor-bound:

- an ordinary employee can be reactivated only by the same Branch Manager, Vice Manager, or HighAdmin user who recorded the latest suspension;
- a manager can be reactivated only by the same HighAdmin user who recorded the latest manager suspension.

## Scheduled processing

SQL Server Agent must be installed and running for automatic background processing.

| Job | Schedule | Procedure |
|---|---|---|
| `Process Pending Bank Transactions` | Every minute | `dbo.sp_Transaction_ProcessPendingBatch` |
| `Apply Monthly Account Interest` | Day 1 of each month at 00:05 | `dbo.sp_Account_ApplyMonthlyInterest` |
| `Daily Loan and Installment Status Maintenance` | Daily at 00:10 | `dbo.sp_Loan_ProcessOverdueInstallments` |

The daily loan job performs these operations:

- changes overdue unpaid installments from Pending to Late;
- changes installments more than 90 days overdue to Defaulted;
- changes an Active loan with a Defaulted installment to Defaulted;
- changes an Active loan with all installments Paid to Paid;
- freezes the borrower's Active or Dormant accounts when the loan first becomes Defaulted.

SQL Server Express does not include SQL Server Agent. With Express, these procedures must be run manually or scheduled through another service such as Windows Task Scheduler and `sqlcmd`.

## Project structure

```text
BankManagement/
├── README.md
├── CHANGELOG.md
├── backend/
│   ├── package.json
│   ├── .env.example
│   ├── src/
│   │   ├── app.js
│   │   ├── server.js
│   │   ├── config/
│   │   ├── middleware/
│   │   ├── routes/
│   │   └── utils/
│   ├── database/
│   │   ├── install/
│   │   ├── scripts/
│   │   │   ├── Agent Jobs/
│   │   │   ├── Functions/
│   │   │   ├── Rules/
│   │   │   ├── SampleData/
│   │   │   ├── StoredProcedures/
│   │   │   ├── TableCreation/
│   │   │   └── Triggers/
│   │   └── security/
│   └── docs/
└── frontend/
    ├── index.html
    ├── customer.html
    ├── employee.html
    ├── admin.html
    ├── highadmin.html
    ├── preview.html
    ├── frontend-server.js
    ├── assets/
    │   ├── css/
    │   ├── images/
    │   └── js/
    └── docs/
```

## Requirements

### Required

- Windows, macOS, or Linux for Node.js
- Microsoft SQL Server
- SQL Server Management Studio for the supplied SQLCMD installers
- Node.js LTS and npm

### Recommended

- SQL Server Developer, Standard, or Enterprise when SQL Server Agent automation is required
- Postman for direct API testing
- Visual Studio Code or another code editor

The SQL Server instance must allow TCP connections. The default backend configuration uses port `1433`.

## Database installation

The installation scripts are under:

```text
backend/database/install/
```

### 1. Extract the project

Use a short local path without unusual permission restrictions, for example:

```text
C:\BankManagement
```

The backend path used in SQLCMD variables must be the folder that contains `package.json`, `src`, and `database`:

```text
C:\BankManagement\backend
```

### 2. Enable SQLCMD Mode

In SSMS:

```text
Query -> SQLCMD Mode
```

### 3. Configure database and login passwords

Open:

```text
backend/database/install/01_create_database_and_logins.sqlcmd
```

Replace all placeholder passwords. Use the same values later in `backend/.env`.

### 4. Configure `ProjectRoot`

In each installer that contains a `ProjectRoot` variable, set it to the full backend path. Example:

```sql
:setvar ProjectRoot "C:\BankManagement\backend"
```

### 5. Run the core installers

Run in this order:

```text
01_create_database_and_logins.sqlcmd
02_install_bankmanagement_database.sqlcmd
03_install_security_and_views.sqlcmd
09_install_ui_dropdown_and_branch_overview_patch.sqlcmd
11_install_reactivation_and_daily_loan_status_patch.sqlcmd
```

The numbered patch installers `05` through `10` are retained for updating older installations. Their final procedure definitions are already present in the current project files, except that installer `09` is still required to install the branch and account-type option catalogue procedures.

### 6. Install the remaining SQL Server Agent jobs

Installer `11` creates the daily loan and installment job. Install the other two jobs manually from:

```text
backend/database/scripts/Agent Jobs/AgentJob_ProcessPendingTransactions.sql
backend/database/scripts/Agent Jobs/AgentJob_ApplyMonthlyInterest.sql
```

Before running them:

- confirm `@DatabaseName` is `BankManagement` or change it;
- replace the hard-coded job owner with a valid SQL Server Agent-capable login;
- confirm SQL Server Agent is running.

### 7. Optional sample data

After all schema objects, procedures, triggers, security objects, and jobs are installed, run:

```text
04_optional_sample_data.sqlcmd
```

Do not run the sample-data installer on a database containing important data.

### Updating an older installation

For an existing earlier database, back up the database and run the applicable installers from `05` through `11` in numeric order. Review every `ProjectRoot`, database name, and SQL Agent owner before execution.

## Backend configuration and startup

### 1. Create `.env`

In the backend folder:

```powershell
Copy-Item .env.example .env
```

Command Prompt equivalent:

```cmd
copy .env.example .env
```

### 2. Configure the environment

At minimum, set:

```env
PORT=4000
SESSION_TTL_MINUTES=10
NODE_ENV=development
CORS_ORIGIN=http://127.0.0.1:5500,http://localhost:5500

DB_SERVER=localhost
DB_PORT=1433
DB_DATABASE=BankManagement
DB_USER=BankAppLogin
DB_PASSWORD=your_app_login_password
DB_ENCRYPT=false
DB_TRUST_SERVER_CERTIFICATE=true
DB_USE_UTC=false

REPORT_DB_USER=BankReportLogin
REPORT_DB_PASSWORD=your_report_login_password
AUDIT_DB_USER=BankAuditorLogin
AUDIT_DB_PASSWORD=your_auditor_login_password
HIGHADMIN_REPORT_DB_USER=BankHighAdminReportLogin
HIGHADMIN_REPORT_DB_PASSWORD=your_highadmin_report_login_password
```

Use the passwords configured in `01_create_database_and_logins.sqlcmd`.

### 3. Install dependencies

```bash
cd backend
npm install
```

### 4. Start the API

Development mode:

```bash
npm run dev
```

Normal mode:

```bash
npm start
```

### 5. Verify the API

Open:

```text
http://127.0.0.1:4000/api/health
```

A successful response identifies the database, SQL login, and database user used by the application pool.

## Frontend startup

The frontend includes a small static server and has no external runtime dependencies.

```bash
cd frontend
npm start
```

Windows alternatives:

```text
start-frontend.cmd
start-frontend.ps1
```

Then open:

```text
http://127.0.0.1:5500
```

Do not open the pages directly with a `file:///` URL. The static server gives the frontend a stable origin for Fetch and CORS.

The default backend URL is defined in:

```text
frontend/assets/js/core/config.js
```

It can also be changed from **Connection settings** on the login page.

Preview mode is available at:

```text
http://127.0.0.1:5500/preview.html
```

Preview mode uses mock data and does not modify the database.

## Initial HighAdmin setup

The initial HighAdmin route is intended for one-time bootstrap:

```http
POST /api/setup/initial-high-admin
Content-Type: application/json
```

Example body:

```json
{
  "username": "highadmin",
  "password": "ReplaceWithAStrongPassword",
  "firstName": "System",
  "lastName": "Administrator",
  "nationalID": "1234567890",
  "birthDate": "1990-01-01",
  "phone": "09120000000",
  "email": "admin@example.com",
  "address": "Main office"
}
```

After creation, sign in through the frontend or:

```http
POST /api/auth/login
Content-Type: application/json
```

Protected requests use:

```http
Authorization: Bearer <session-token>
```

## Authentication and authorization

### Authentication flow

1. The client submits a username and password to `POST /api/auth/login`.
2. The backend calls `dbo.sp_User_Login` with typed parameters.
3. SQL Server validates the stored password hash and active user/customer state.
4. The procedure calculates effective roles and creates a row in `dbo.Sessions`.
5. The API returns an opaque session token and its expiration time.
6. Protected requests send the token in the `Authorization` header.
7. The authentication middleware calls `dbo.sp_User_ValidateSession`.
8. The validated user, customer, employee, branch, and effective roles are attached to `req.user`.
9. Logout calls `dbo.sp_User_Logout`, which deactivates the session.

Sessions use a fixed absolute expiration. Request activity does not extend `ExpiresAt`.

### Authorization layers

The system uses several complementary controls:

1. **Frontend role visibility** hides unavailable controls.
2. **Express route authorization** rejects requests without a required effective role.
3. **Stored-procedure authorization** verifies the authenticated `UserID`, ownership, branch assignment, status, and business conditions.
4. **SQL Server permissions** restrict each backend connection to its intended procedures or views.
5. **Constraints and triggers** protect integrity even when more than one row is affected.
6. **AuditLog** records security-sensitive and operational actions.

### SQL injection protection

User input is passed with `request.input(...)` and explicit SQL Server types. The project does not concatenate ordinary request values into SQL commands. Report keys and SQL identifiers are selected from server-owned configuration rather than accepted directly from the client.

## API overview

Base URL:

```text
http://127.0.0.1:4000/api
```

### Public and setup

```text
GET    /health
POST   /setup/initial-high-admin
POST   /auth/signup
POST   /auth/login
```

### Authenticated session

```text
POST   /auth/logout
GET    /auth/me
```

### Customers

```text
GET    /customers
POST   /customers
PUT    /customers/:customerID
DELETE /customers/:customerID
```

### Accounts

```text
GET    /accounts/mine
GET    /accounts/options/account-types
GET    /accounts
GET    /accounts/:accountID
GET    /accounts/:accountID/history
POST   /accounts
POST   /accounts/:accountID/close
POST   /accounts/:accountID/freeze
POST   /accounts/:accountID/unfreeze
POST   /accounts/:accountID/change-type
POST   /accounts/maintenance/dormant-sweep
POST   /accounts/maintenance/apply-monthly-interest
```

### Transactions

```text
POST   /transactions/deposit
POST   /transactions/withdraw
POST   /transactions/transfer
POST   /transactions/:transactionID/finalize
POST   /transactions/:transactionID/reverse
POST   /transactions/maintenance/process-pending-batch
```

The reversal route is an API-level operation and is not exposed as a supported frontend action.

### Loans

```text
GET    /loans
POST   /loans
GET    /loans/:loanID/status
POST   /loans/installments/:installmentID/pay
POST   /loans/maintenance/process-overdue-installments
```

### Employees and transfers

```text
GET    /employees
GET    /employees/:employeeID
POST   /employees
POST   /employees/:employeeID/create-user-account
POST   /employees/:employeeID/change-job-title
POST   /employees/:employeeID/fire
POST   /employees/:employeeID/suspend
POST   /employees/:employeeID/unsuspend
GET    /employees/:employeeID/branch-history

POST   /employee-transfers/request-by-employee
POST   /employee-transfers/request-by-manager
POST   /employee-transfers/:transferRequestID/current-manager-decision
POST   /employee-transfers/:transferRequestID/destination-manager-decision
```

### Branches

```text
GET    /branches/options
GET    /branches
GET    /branches/:branchID
```

### HighAdmin

```text
POST   /highadmin/managers
POST   /highadmin/managers/:employeeID/promote
POST   /highadmin/managers/:employeeID/downgrade
POST   /highadmin/managers/:employeeID/fire
POST   /highadmin/managers/:employeeID/suspend
POST   /highadmin/managers/:employeeID/unsuspend
POST   /highadmin/branches/:branchID/replace-manager
```

### Reports

```text
GET    /reports
GET    /reports/:reportKey?page=1&pageSize=50
```

The database procedures remain authoritative for the exact access rules of each operation.

## Testing and verification

### Backend JavaScript syntax

```bash
cd backend
npm run check
```

### Frontend server syntax

```bash
cd frontend
npm run check
```

### Health check

```text
GET http://127.0.0.1:4000/api/health
```

### Postman resources

```text
backend/docs/postman_collection.json
backend/docs/BankManagement_Postman_API_Testing_Guide.html
```

### Verify required procedures

```sql
USE BankManagement;
GO

SELECT name
FROM sys.procedures
WHERE name IN
(
    N'sp_User_Login',
    N'sp_User_ValidateSession',
    N'sp_Transaction_Finalize',
    N'sp_Transaction_ProcessPendingBatch',
    N'sp_Account_ApplyMonthlyInterest',
    N'sp_Loan_ProcessOverdueInstallments',
    N'sp_Employee_Unsuspend',
    N'sp_HighAdmin_UnsuspendManager'
)
ORDER BY name;
```

### Verify Agent jobs

```sql
SELECT name, enabled
FROM msdb.dbo.sysjobs
WHERE name IN
(
    N'Process Pending Bank Transactions',
    N'Apply Monthly Account Interest',
    N'Daily Loan and Installment Status Maintenance'
)
ORDER BY name;
```

### Manual maintenance tests

Use only in a development or controlled test database:

```sql
EXEC dbo.sp_Transaction_ProcessPendingBatch;
EXEC dbo.sp_Account_ApplyMonthlyInterest;
EXEC dbo.sp_Loan_ProcessOverdueInstallments
    @UserID = NULL,
    @BranchID = NULL;
```

Monthly interest has no per-month duplicate guard. Do not execute it twice for the same accounting period unless duplicate crediting is intended and handled.

## Operational notes

- Store `.env` outside version control and never commit real passwords.
- Change all placeholder SQL login passwords before installation.
- Use a valid SQL Server Agent job owner instead of a machine-specific login.
- Run the backend and frontend on separate ports, normally `4000` and `5500`.
- Configure `CORS_ORIGIN` explicitly for the frontend origin.
- Keep SQL Server TCP/IP enabled and confirm the configured port.
- Back up before destructive schema changes, production data migrations, or security changes.
- Use the report-specific database connections for reporting views.
- Review `AuditLog`, `BranchLedger`, and SQL Agent history when investigating operational changes.

## Known limitations

- The current frontend does not provide a supported transaction-reversal workflow, although the database/API operation exists.
- There is no password-change or password-reset endpoint.
- Employee transfer requests can be created and decided, but there is no authoritative transfer-request listing endpoint.
- Monthly interest processing does not prevent a second successful run in the same month.
- SQL Server Agent scripts contain environment-specific owner values that must be reviewed before installation.
- The project uses SQLCMD installers rather than a migration framework.
- Session tokens are stored in browser local storage or session storage by the frontend; production deployment should apply a strict Content Security Policy and consider hardened cookie-based session delivery.

## Troubleshooting

### `Login failed for user 'BankAppLogin'`

Confirm that:

- SQL Server Authentication is enabled;
- `01_create_database_and_logins.sqlcmd` completed successfully;
- the password in `.env` matches the login password;
- the backend is connecting to the correct SQL Server instance and port.

### `Cannot open database 'BankManagement'`

Confirm the database exists and the login is mapped to the expected database user by the security installer.

### `Could not find stored procedure`

Run the core installers and required patch installers in the documented order. Confirm every `ProjectRoot` points to the backend folder.

### SQLCMD `:r` file not found

- Enable SQLCMD Mode in SSMS.
- Use the absolute backend path for `ProjectRoot`.
- Keep quotation marks around paths containing spaces.

### CORS error in the browser

Set:

```env
CORS_ORIGIN=http://127.0.0.1:5500,http://localhost:5500
```

Restart the backend after changing `.env`.

### Frontend opens but API requests fail

Verify:

- the backend health endpoint works;
- the frontend connection setting points to `http://127.0.0.1:4000`;
- the browser is using the static server rather than `file:///`;
- the session has not expired.

### SQL Server Agent job does not run

Confirm:

- the SQL Server Agent service is running;
- the job is enabled;
- the job owner is valid;
- the job step targets the `BankManagement` database;
- the procedure exists;
- the SQL Agent history contains no permission or ownership errors.

### Port already in use

Change `PORT` in `backend/.env` or the frontend static-server port, then update CORS and the frontend backend URL accordingly.
