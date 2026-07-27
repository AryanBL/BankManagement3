# BankManagement

BankManagement is a role-aware banking application built with Microsoft SQL Server, Node.js, Express, and a browser-based frontend written in HTML, CSS, and vanilla JavaScript. The database owns the core business rules through stored procedures, triggers, functions, constraints, transactions, and SQL Server Agent jobs. The backend exposes those operations as a REST API, and the frontend provides separate workspaces for customers, employees, branch administrators, and the HighAdmin.

The repository supports two setup paths:

1. **Docker Compose on Ubuntu/WSL 2** — recommended for a reproducible local deployment.
2. **Manual Windows or Linux setup** — useful when connecting the backend to an existing SQL Server instance.

## Docker quick start

The Docker deployment packages SQL Server 2022, SQLCMD database initialization, the Node.js API, and the frontend as separate services.

```bash
cp .env.docker.example .env.docker
nano .env.docker

docker compose --env-file .env.docker config
docker compose --env-file .env.docker up -d --build
```

After startup:

```text
Frontend:       http://localhost:5500
Backend API:    http://localhost:4000
Health check:   http://localhost:4000/api/health
Docker SQL:     tcp:127.0.0.1,14331
```

Check the deployment:

```bash
docker compose --env-file .env.docker ps -a
docker compose --env-file .env.docker logs --tail=200 db-init
curl -i http://127.0.0.1:4000/api/health
```

The expected steady state is:

```text
bankmanagement-sqlserver   Up (healthy)
bankmanagement-db-init     Exited (0)
bankmanagement-backend     Up (healthy)
bankmanagement-frontend    Up (healthy)
```

`db-init` is a one-time installer. `Exited (0)` means it completed successfully.

## Contents

- [Docker quick start](#docker-quick-start)
- [Architecture](#architecture)
- [Container networking and ports](#container-networking-and-ports)
- [Technology stack](#technology-stack)
- [Roles and access model](#roles-and-access-model)
- [Main features](#main-features)
- [Database state rules](#database-state-rules)
- [Scheduled processing](#scheduled-processing)
- [Project structure](#project-structure)
- [Requirements](#requirements)
- [Docker deployment on Ubuntu/WSL](#docker-deployment-on-ubuntuwsl)
- [Manual database installation](#manual-database-installation)
- [Manual backend startup](#manual-backend-startup)
- [Manual frontend startup](#manual-frontend-startup)
- [Initial HighAdmin setup](#initial-highadmin-setup)
- [Authentication and authorization](#authentication-and-authorization)
- [API overview](#api-overview)
- [Testing and verification](#testing-and-verification)
- [Operational notes](#operational-notes)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)

## Architecture

### Logical application architecture

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

### Docker Compose architecture

```text
Windows browser / WSL host
        |
        +-- 127.0.0.1:5500  -> frontend:5500
        +-- 127.0.0.1:4000  -> backend:4000
        +-- 127.0.0.1:14331 -> mssql:1433
                                  ^
                                  |
                          backend -> mssql:1433
                          db-init -> mssql:1433
```

Compose creates the private network `bankmanagement_default`. Containers resolve one another by service name. The backend and initializer therefore use `mssql:1433`, not the host-side SQL port.

## Container networking and ports

The Linux distribution inside a container does not communicate with Windows through a special operating-system channel. Services communicate through ordinary TCP sockets, Docker's private bridge network, and explicit host-port forwarding.

| Traffic | Address used | Purpose |
|---|---|---|
| Browser → frontend | `http://127.0.0.1:5500` | Browser application |
| Browser → backend | `http://127.0.0.1:4000` | REST API |
| Backend → SQL Server | `mssql:1433` | Private Compose-network connection |
| `db-init` → SQL Server | `mssql:1433` | Private SQLCMD installation connection |
| SSMS/host → Docker SQL Server | `tcp:127.0.0.1,14331` | Host-to-container SQL connection |
| Native Windows SQL Server, when retained | commonly `tcp:127.0.0.1,14330` | Separate non-Docker instance |

The Compose mappings are loopback-only:

```yaml
mssql:
  ports:
    - "127.0.0.1:${MSSQL_HOST_PORT:-14331}:1433"

backend:
  ports:
    - "127.0.0.1:${BACKEND_HOST_PORT:-4000}:4000"

frontend:
  ports:
    - "127.0.0.1:${FRONTEND_HOST_PORT:-5500}:5500"
```

The left side is the WSL/Windows host port. The right side is the port inside the container.

Do not set the backend database port to `14331`. `14331` is only for SSMS and other host-side tools. Inside Docker, SQL Server listens on `1433`.

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

SQL Server Agent must be running for automatic background processing.

| Job | Schedule | Procedure |
|---|---|---|
| `Process Pending Bank Transactions` | Every minute | `dbo.sp_Transaction_ProcessPendingBatch` |
| `Apply Monthly Account Interest` | Day 1 of each month at 00:05 | `dbo.sp_Account_ApplyMonthlyInterest` |
| `Daily Loan and Installment Status Maintenance` | Daily at 00:10 | `dbo.sp_Loan_ProcessOverdueInstallments` |
| `Account Dormant Sweep` | Daily at 02:30 | `dbo.sp_Account_DormantSweep` |

The daily loan job:

- changes overdue unpaid installments from Pending to Late;
- changes installments more than 90 days overdue to Defaulted;
- changes an Active loan with a Defaulted installment to Defaulted;
- changes an Active loan with all installments Paid to Paid;
- freezes the borrower's Active or Dormant accounts when the loan first becomes Defaulted.

The Docker configuration enables SQL Server Agent with `MSSQL_AGENT_ENABLED=true`. The initializer waits for Agent and then installs all four jobs through:

```text
database/install/05_install_agent_jobs.sqlcmd
```

SQL Server Express does not include SQL Server Agent. With Express, run the procedures manually or schedule them through another service such as Windows Task Scheduler and `sqlcmd`.

## Project structure

```text
BankManagement/
├── README.md
├── CHANGELOG.md
├── compose.yaml
├── Dockerfile
├── .dockerignore
├── .env.example
├── .env.docker.example
├── package.json
├── package-lock.json
├── src/
│   ├── app.js
│   ├── server.js
│   ├── config/
│   ├── middleware/
│   ├── routes/
│   └── utils/
├── docker/
│   └── init-db.sh
├── database/
│   ├── install/
│   │   ├── 01_create_database_and_logins.sqlcmd
│   │   ├── 02_install_bankmanagement_database.sqlcmd
│   │   ├── 03_install_security_and_views.sqlcmd
│   │   ├── 04_optional_sample_data.sqlcmd
│   │   └── 05_install_agent_jobs.sqlcmd
│   ├── scripts/
│   │   ├── Agent Jobs/
│   │   ├── Functions/
│   │   ├── Rules/
│   │   ├── SampleData/
│   │   ├── StoredProcedures/
│   │   ├── TableCreation/
│   │   └── Triggers/
│   └── security/
├── docs/
│   └── postman_collection.json
└── BankManagement_Frontend_Complete/
    └── BankManagement_Frontend_Complete/
        ├── Dockerfile
        ├── .dockerignore
        ├── frontend-server.js
        ├── package.json
        ├── index.html
        ├── customer.html
        ├── employee.html
        ├── admin.html
        ├── highadmin.html
        ├── preview.html
        ├── assets/
        └── docs/
```

The root `Dockerfile` builds the backend. The nested frontend `Dockerfile` builds the static frontend server. `compose.yaml` assembles both images with SQL Server and the one-time initializer.

## Requirements

### Recommended Docker/WSL deployment

- Windows 10/11 with WSL 2 and Ubuntu, or a native x86-64 Linux host
- Docker Desktop with WSL integration, or Docker Engine plus the Docker Compose plugin
- Intel/AMD x86-64 (`amd64`) processor for the SQL Server Linux image
- At least 4 GB of memory available to WSL/Docker; SQL Server is configured with a 2048 MB internal memory limit
- Enough free disk space for Docker images and the persistent SQL Server volume

Verify:

```bash
docker version
docker compose version
uname -m
free -h
```

### Manual deployment

- Microsoft SQL Server
- SQLCMD tools or SSMS with SQLCMD Mode
- Node.js 22 LTS or another compatible current LTS release
- npm
- SQL Server Agent when scheduled jobs are required

For manual SQL Server connections, enable TCP/IP and use the actual configured instance port.

## Docker deployment on Ubuntu/WSL

### 1. Keep the repository in the WSL filesystem

For better Linux filesystem performance and fewer permission or line-ending problems, store the repository under your WSL home directory rather than running it directly under `/mnt/c`.

```bash
mkdir -p ~/project
cd ~/project
# clone the repository here, or copy the extracted folder here
cd BankManagement
```

### 2. Create `.env.docker`

```bash
cp .env.docker.example .env.docker
nano .env.docker
```

Do not commit `.env.docker`.

The initializer requires six unique passwords:

| Variable | Purpose |
|---|---|
| `MSSQL_SA_PASSWORD` | Container SQL Server administrator and database bootstrap |
| `BANK_APP_PASSWORD` | Main least-privilege backend connection |
| `BANK_REPORT_PASSWORD` | Reporting connection |
| `BANK_AUDITOR_PASSWORD` | Audit reporting connection |
| `BANK_HIGHADMIN_REPORT_PASSWORD` | HighAdmin reporting connection |
| `BANK_MAINTENANCE_PASSWORD` | Maintenance login created by the security installer |

Each password must:

- be at least 12 characters;
- contain uppercase and lowercase letters;
- contain a digit;
- contain a symbol.

For the five `BANK_*` passwords, avoid single quotes, double quotes, newlines, carriage returns, and the sequence `$(` because the values are passed through SQLCMD variable substitution.

Typical non-secret settings:

```dotenv
MSSQL_PID=Developer

MSSQL_HOST_PORT=14331
BACKEND_HOST_PORT=4000
FRONTEND_HOST_PORT=5500

MSSQL_MEMORY_LIMIT_MB=2048
SESSION_TTL_MINUTES=10

LOAD_SAMPLE_DATA=false
INSTALL_AGENT_JOBS=true
FORCE_DB_REBUILD=false

CORS_ORIGIN=http://localhost:5500,http://127.0.0.1:5500
```

When a native Windows SQL Server already uses `14330`, keep Docker SQL Server on host port `14331`.

### 3. Validate Compose interpolation

The custom environment file is not loaded automatically by plain `docker compose up`. Always pass it explicitly:

```bash
docker compose --env-file .env.docker config
```

If Compose reports that a required variable is missing, confirm:

- the file is named exactly `.env.docker`;
- the command is run from the repository root;
- the variable has a non-empty value;
- there are no spaces around `=`.

### 4. Build and start

```bash
docker compose --env-file .env.docker up -d --build
```

The startup order is:

```text
mssql becomes healthy
        ↓
db-init runs SQLCMD installers and exits successfully
        ↓
backend starts and passes /api/health
        ↓
frontend starts
```

The SQL Server health window can take several minutes on a first start. View progress in another terminal:

```bash
docker compose --env-file .env.docker ps -a
docker compose --env-file .env.docker logs -f --tail=200 mssql
```

### 5. Database initialization

`db-init` mounts the repository read-only at `/workspace`, starts from that directory, and runs:

```text
database/install/01_create_database_and_logins.sqlcmd
database/install/02_install_bankmanagement_database.sqlcmd
database/install/03_install_security_and_views.sqlcmd
database/install/04_optional_sample_data.sqlcmd   # only when enabled
database/install/05_install_agent_jobs.sqlcmd
```

The SQLCMD `:r` paths are repository-root-relative. No Windows drive path or `ProjectRoot` edit is required.

The core installers set the SQL session options required for filtered indexes and views, including:

```sql
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
```

Installer `02` is a clean rebuild. The Docker initializer protects existing data with `dbo.__DeploymentMetadata` and skips the destructive rebuild on ordinary restarts.

### 6. Verify the deployment

```bash
docker compose --env-file .env.docker ps -a
docker compose --env-file .env.docker logs --tail=300 db-init
curl -i http://127.0.0.1:4000/api/health
```

A successful health response identifies:

```text
Database:      BankManagement
SQL login:     BankAppLogin
Database user: BankAppUser
```

Open:

```text
http://localhost:5500
```

### 7. Connect with SSMS

Use:

```text
Server type:             Database Engine
Server name:             tcp:127.0.0.1,14331
Authentication:          SQL Server Authentication
Login:                   sa
Password:                MSSQL_SA_PASSWORD value
Trust server certificate: enabled for this local instance
```

The application does not run as `sa`. It uses the least-privilege project logins created by installer `01`.

### 8. Stop, restart, and preserve data

Stop containers while retaining the database:

```bash
docker compose --env-file .env.docker down
```

Restart:

```bash
docker compose --env-file .env.docker up -d
```

The named volume `bankmanagement_mssql-data` stores `/var/opt/mssql`.

Permanently delete the Docker database:

```bash
docker compose --env-file .env.docker down -v --remove-orphans
```

Use `-v` only for a disposable database. It does not affect a separate native Windows SQL Server database, but it permanently deletes the Docker SQL Server volume.

### 9. Rebuild and sample-data controls

For a fresh disposable demo database:

```dotenv
LOAD_SAMPLE_DATA=true
```

Sample data is loaded only during a fresh or forced schema installation.

To intentionally rerun the destructive schema installer:

```dotenv
FORCE_DB_REBUILD=true
```

Return it to `false` immediately after the rebuild.

### 10. Password changes with an existing volume

Installer `01` synchronizes the five project login passwords during each initializer run.

`MSSQL_SA_PASSWORD` is different: SQL Server uses it when the volume is first initialized. Changing only `.env.docker` later does not change the `sa` password stored in an existing volume. Either:

- change the `sa` login inside SQL Server and then update `.env.docker`; or
- delete and recreate the volume when the database is disposable.

## Manual database installation

Docker Compose is the recommended path. For a manual installation, use SQLCMD from the repository root because the installers use repository-root-relative `:r` paths.

### Installer order

```text
01_create_database_and_logins.sqlcmd
02_install_bankmanagement_database.sqlcmd
03_install_security_and_views.sqlcmd
04_optional_sample_data.sqlcmd   # optional and destructive for demo use
05_install_agent_jobs.sqlcmd
```

### Password variables

Installer `01` requires:

```text
BankAppPassword
BankReportPassword
BankAuditorPassword
BankHighAdminReportPassword
BankMaintenancePassword
```

Example from PowerShell, using SQL authentication:

```powershell
cd C:\path\to\BankManagement

$env:SQLCMDPASSWORD = "<sa-password>"

sqlcmd `
  -S "tcp:127.0.0.1,14330" `
  -U sa `
  -C `
  -b `
  -v `
    "BankAppPassword=<strong-app-password>" `
    "BankReportPassword=<strong-report-password>" `
    "BankAuditorPassword=<strong-audit-password>" `
    "BankHighAdminReportPassword=<strong-highadmin-report-password>" `
    "BankMaintenancePassword=<strong-maintenance-password>" `
  -i "database/install/01_create_database_and_logins.sqlcmd"

sqlcmd -S "tcp:127.0.0.1,14330" -U sa -C -b -i "database/install/02_install_bankmanagement_database.sqlcmd"
sqlcmd -S "tcp:127.0.0.1,14330" -U sa -C -b -i "database/install/03_install_security_and_views.sqlcmd"
sqlcmd -S "tcp:127.0.0.1,14330" -U sa -C -b -i "database/install/05_install_agent_jobs.sqlcmd"
```

Change the server and port to match the manual SQL Server instance.

Important:

- Installer `02` deletes and recreates the project schema and project data.
- Back up any important database before running it.
- Installer `04` is for disposable demo data only.
- SQL Server Agent must be enabled and running before relying on installer `05`.
- No hard-coded Windows `F:\...` path or `ProjectRoot` value is required in the current installers.

## Manual backend startup

Docker Compose injects the backend environment automatically. For a non-Docker backend, create a local `.env` in the repository root:

```bash
cp .env.example .env
```

At minimum:

```env
PORT=4000
SESSION_TTL_MINUTES=10
NODE_ENV=development
CORS_ORIGIN=http://127.0.0.1:5500,http://localhost:5500

DB_SERVER=127.0.0.1
DB_PORT=14330
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

Use the actual host port of the manual SQL Server instance.

Install and start:

```bash
npm ci
npm run dev
```

Normal production-style mode:

```bash
npm start
```

Verify:

```bash
curl -i http://127.0.0.1:4000/api/health
```

## Manual frontend startup

The frontend has no third-party runtime dependencies. Its small Node.js server uses built-in modules.

```bash
cd BankManagement_Frontend_Complete/BankManagement_Frontend_Complete
npm start
```

Then open:

```text
http://127.0.0.1:5500
```

Do not open pages directly with a `file:///` URL. The static server provides a stable browser origin for Fetch and CORS.

The default API URL is defined in:

```text
BankManagement_Frontend_Complete/BankManagement_Frontend_Complete/assets/js/core/config.js
```

It can also be changed from **Connection settings** on the login page.

Preview mode:

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

### Docker services

```bash
docker compose --env-file .env.docker ps -a
```

Expected:

```text
mssql      running and healthy
db-init    exited successfully with code 0
backend    running and healthy
frontend   running and healthy
```

### Backend health

```bash
curl -i http://127.0.0.1:4000/api/health
```

The health endpoint verifies both HTTP service availability and the application database connection.

### Container logs

```bash
docker compose --env-file .env.docker logs --tail=200 mssql
docker compose --env-file .env.docker logs --tail=300 db-init
docker compose --env-file .env.docker logs --tail=200 backend
docker compose --env-file .env.docker logs --tail=200 frontend
```

### Backend JavaScript syntax

```bash
npm run check
```

### Frontend server syntax

```bash
cd BankManagement_Frontend_Complete/BankManagement_Frontend_Complete
npm run check
```

### Postman resources

```text
docs/postman_collection.json
BankManagement_Postman_API_Testing_Guide.html
BankManagement_SampleData_Postman_Tests/
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
    N'sp_Account_DormantSweep',
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
    N'Daily Loan and Installment Status Maintenance',
    N'Account Dormant Sweep'
)
ORDER BY name;
```

### Manual maintenance tests

Use only in a development or controlled test database:

```sql
EXEC dbo.sp_Transaction_ProcessPendingBatch;
EXEC dbo.sp_Account_ApplyMonthlyInterest;
EXEC dbo.sp_Account_DormantSweep;
EXEC dbo.sp_Loan_ProcessOverdueInstallments
    @UserID = NULL,
    @BranchID = NULL;
```

Monthly interest has no per-month duplicate guard. Do not execute it twice for the same accounting period unless duplicate crediting is intended and handled.

## Operational notes

- Keep `.env` and `.env.docker` outside version control.
- Use unique strong passwords for all SQL logins.
- The Docker SQL Server and a native Windows SQL Server are separate installations with separate `master` databases, logins, passwords, and data files.
- The application containers communicate with SQL Server through `mssql:1433`; only host-side tools use `14331`.
- Published Compose ports are bound to `127.0.0.1` for local development.
- `docker compose down` preserves database data; `docker compose down -v` deletes it.
- Back up before destructive schema changes, production data migrations, or security changes.
- Keep `FORCE_DB_REBUILD=false` during normal operation.
- Configure `CORS_ORIGIN` explicitly for every allowed frontend origin.
- Use the report-specific database connections for reporting views.
- Review `AuditLog`, `BranchLedger`, SQL Server logs, and SQL Agent history when investigating operational changes.

## Known limitations

- The current frontend does not provide a supported transaction-reversal workflow, although the database/API operation exists.
- There is no password-change or password-reset endpoint.
- Employee transfer requests can be created and decided, but there is no authoritative transfer-request listing endpoint.
- Monthly interest processing does not prevent a second successful run in the same month.
- The project uses SQLCMD installers rather than a migration framework.
- The Docker initializer protects the clean-rebuild installer with a deployment marker, but intentional schema evolution should still be planned and backed up.
- Session tokens are stored in browser local storage or session storage by the frontend; production deployment should apply a strict Content Security Policy and consider hardened cookie-based session delivery.
- The supplied Compose configuration is intended for local development and demonstration, not high-availability production hosting.

## Troubleshooting

### Compose reports a missing `.env.docker` variable

Use:

```bash
docker compose --env-file .env.docker config
docker compose --env-file .env.docker up -d --build
```

Plain `docker compose up` does not automatically load a file named `.env.docker`.

### SQL Server remains unhealthy

Inspect:

```bash
docker compose --env-file .env.docker ps -a
docker compose --env-file .env.docker logs --tail=300 mssql

docker inspect bankmanagement-sqlserver \
  --format='{{range .State.Health.Log}}{{println .ExitCode}}{{println .Output}}{{end}}'
```

Common causes:

- the `sa` password does not meet policy;
- the current `.env.docker` password differs from the password stored in an existing SQL Server volume;
- WSL/Docker has insufficient memory;
- SQLCMD is unavailable at the health-check path.

A first startup may remain in `health: starting` for several minutes.

When the Docker database is disposable, a clean reset is:

```bash
docker compose --env-file .env.docker down -v --remove-orphans
docker compose --env-file .env.docker up -d --build
```

Do not use `-v` when the Docker database must be retained.

### `db-init` exits with code 1

```bash
docker compose --env-file .env.docker logs --no-color --tail=400 db-init
```

The initializer uses `sqlcmd -b` and `:On Error exit`, so the first SQL error is normally near the end of the log.

Common causes:

- weak application-login passwords;
- an incomplete or outdated installer file;
- running manual SQLCMD from a directory other than the repository root;
- SQL Server Agent not being ready.

The current repository uses root-relative `:r` paths and includes the required `QUOTED_IDENTIFIER` and ANSI settings for filtered indexes.

### `Invalid filename` for a SQLCMD `:r` file

The current installers do not use a hard-coded Windows path or `$(ProjectRoot)` in `:r` filenames. Confirm that:

- the latest installer files are present;
- SQLCMD is started from the repository root;
- `db-init` has `working_dir: /workspace`;
- the repository is mounted as `.:/workspace:ro`.

### `CREATE INDEX` fails with incorrect `QUOTED_IDENTIFIER`

Confirm the latest versions of installers `02` and `03` are present. They must set:

```sql
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
```

### Backend is unhealthy

Read the response body:

```bash
curl -i http://127.0.0.1:4000/api/health
docker compose --env-file .env.docker logs --tail=200 backend
```

If it says:

```text
Failed to connect to mssql:14331
```

the backend is using the host port incorrectly. In `compose.yaml`, the backend must use:

```yaml
DB_SERVER: mssql
DB_PORT: "1433"
```

Only SSMS uses `14331`.

### Frontend is not created or started

The frontend waits for the backend health check. Fix the backend first, then run:

```bash
docker compose --env-file .env.docker up -d frontend
```

### SSMS cannot connect to Docker SQL Server

Use:

```text
Server: tcp:127.0.0.1,14331
Authentication: SQL Server Authentication
Trust server certificate: enabled
```

Check the published mapping:

```bash
docker compose --env-file .env.docker port mssql 1433
```

### Port already in use

Change only the host-side values in `.env.docker`:

```dotenv
MSSQL_HOST_PORT=14332
BACKEND_HOST_PORT=4001
FRONTEND_HOST_PORT=5501
```

When changing the frontend port, update `CORS_ORIGIN`. When changing the backend port, update the frontend connection setting.

The backend-to-database port remains `1433`.

### SQL Server Agent job does not run

Confirm:

- `MSSQL_AGENT_ENABLED=true` is present in the SQL Server service;
- `INSTALL_AGENT_JOBS=true` is present in `.env.docker`;
- SQL Server Agent reports `Running`;
- the job is enabled;
- its step targets `BankManagement`;
- the procedure exists;
- SQL Agent history contains no permission or ownership errors.

### Browser opens but API requests fail

Verify:

```bash
docker compose --env-file .env.docker ps -a
curl -i http://127.0.0.1:4000/api/health
```

Also confirm:

- the frontend connection setting points to `http://127.0.0.1:4000`;
- `CORS_ORIGIN` contains the exact browser origin;
- the session has not expired;
- the browser is not opening the frontend through `file:///`.
