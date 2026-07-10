# BankManagement Backend v2

REST API backend for the final BankManagement SQL Server project.

This backend uses:

- Node.js
- Express
- SQL Server
- `mssql` driver
- Direct stored procedure calls
- No ORM
- Session-token authentication using the database `Sessions` table
- Role-based authorization using the database `sp_User_ValidateSession` procedure

The database remains the main owner of business rules. The backend receives HTTP requests, validates sessions, sends safe parameterized calls to stored procedures, and returns JSON.

---

## 1. What you need to install

Install these tools on Windows:

1. Node.js LTS
2. SQL Server Developer or SQL Server Express
3. SQL Server Management Studio, also called SSMS
4. Visual Studio Code, optional but recommended
5. Postman, optional for API testing

---

## 2. Create the database and logins

Open SSMS and connect as a SQL Server administrator.

Enable SQLCMD mode:

`Query > SQLCMD Mode`

Run these files in order:

```text
backend-folder/database/install/01_create_database_and_logins.sqlcmd
backend-folder/database/install/02_install_bankmanagement_database.sqlcmd
backend-folder/database/install/03_install_security_and_views.sqlcmd
```

Before running file 2 and 3, open the file and replace this line:

```sql
:setvar ProjectRoot "C:\CHANGE_ME\bank-management-backend-v2"
```

with the real full path of this backend folder, for example:

```sql
:setvar ProjectRoot "C:\Users\Ali\Downloads\bank-management-backend-v2"
```

The first script creates the SQL Server logins:

```text
BankAppLogin
BankReportLogin
BankAuditorLogin
BankHighAdminReportLogin
BankMaintenanceLogin
```

The database security script then maps those server logins to database users such as `BankAppUser` and gives each user only the permissions required for its job.

Optional demo data:

```text
backend-folder/database/install/04_optional_sample_data.sqlcmd
```

Only run the sample-data script after the database is fully installed.

---

## 3. Configure the backend

In the backend folder:

```bash
copy .env.example .env
```

Edit `.env` and set your SQL Server connection information:

```env
PORT=4000
DB_SERVER=localhost
DB_PORT=1433
DB_DATABASE=BankManagement
DB_USER=BankAppLogin
DB_PASSWORD=Replace_With_Strong_Password_1!
DB_ENCRYPT=false
DB_TRUST_SERVER_CERTIFICATE=true

REPORT_DB_USER=BankReportLogin
REPORT_DB_PASSWORD=Replace_With_Strong_Password_2!
AUDIT_DB_USER=BankAuditorLogin
AUDIT_DB_PASSWORD=Replace_With_Strong_Password_3!
HIGHADMIN_REPORT_DB_USER=BankHighAdminReportLogin
HIGHADMIN_REPORT_DB_PASSWORD=Replace_With_Strong_Password_4!
```

Use the same passwords you placed in `01_create_database_and_logins.sqlcmd`.

If your SQL Server uses a named instance like `localhost\SQLEXPRESS`, the easiest beginner option is usually to configure SQL Server to listen on TCP port `1433`, then keep:

```env
DB_SERVER=localhost
DB_PORT=1433
```

---

## 4. Install and run

Open a terminal in the backend folder:

```bash
npm install
npm run dev
```

For normal running without auto-restart:

```bash
npm start
```

Test the server:

```text
GET http://localhost:4000/api/health
```

A successful response looks like:

```json
{
  "success": true,
  "message": "BankManagement backend is running.",
  "data": {
    "databaseName": "BankManagement",
    "sqlLogin": "BankAppLogin",
    "databaseUser": "BankAppUser"
  }
}
```

---

## 5. First login setup

Create the first HighAdmin application user:

```text
POST http://localhost:4000/api/setup/initial-high-admin
```

Example body:

```json
{
  "username": "highadmin",
  "password": "Admin123!",
  "firstName": "System",
  "lastName": "Owner",
  "nationalID": "1234567890",
  "birthDate": "1990-01-01",
  "phone": "09120000000",
  "email": "highadmin@example.com",
  "address": "Main office"
}
```

Then log in:

```text
POST http://localhost:4000/api/auth/login
```

Body:

```json
{
  "username": "highadmin",
  "password": "Admin123!"
}
```

The response contains a `SessionToken`. Send that token with protected requests:

```text
Authorization: Bearer YOUR_SESSION_TOKEN
```

---

## 6. Main API groups

```text
GET    /api/health
POST   /api/setup/initial-high-admin
POST   /api/auth/signup
POST   /api/auth/login
POST   /api/auth/logout
GET    /api/auth/me

GET    /api/customers
POST   /api/customers
PUT    /api/customers/:customerID
DELETE /api/customers/:customerID

GET    /api/accounts
GET    /api/accounts/:accountID
GET    /api/accounts/:accountID/history
POST   /api/accounts
POST   /api/accounts/:accountID/close
POST   /api/accounts/:accountID/freeze
POST   /api/accounts/:accountID/unfreeze
POST   /api/accounts/:accountID/change-type
POST   /api/accounts/maintenance/dormant-sweep
POST   /api/accounts/maintenance/apply-monthly-interest

POST   /api/transactions/deposit
POST   /api/transactions/withdraw
POST   /api/transactions/transfer
POST   /api/transactions/:transactionID/finalize
POST   /api/transactions/:transactionID/reverse
POST   /api/transactions/maintenance/process-pending-batch

POST   /api/loans
GET    /api/loans/:loanID/status
POST   /api/loans/installments/:installmentID/pay
POST   /api/loans/maintenance/process-overdue-installments

GET    /api/employees
GET    /api/employees/:employeeID
POST   /api/employees
POST   /api/employees/:employeeID/create-user-account
POST   /api/employees/:employeeID/change-job-title
POST   /api/employees/:employeeID/fire
POST   /api/employees/:employeeID/suspend
GET    /api/employees/:employeeID/branch-history

POST   /api/employee-transfers/request-by-employee
POST   /api/employee-transfers/request-by-manager
POST   /api/employee-transfers/:transferRequestID/current-manager-decision
POST   /api/employee-transfers/:transferRequestID/destination-manager-decision

GET    /api/branches
GET    /api/branches/:branchID

POST   /api/highadmin/managers
POST   /api/highadmin/managers/:employeeID/promote
POST   /api/highadmin/managers/:employeeID/downgrade
POST   /api/highadmin/managers/:employeeID/fire
POST   /api/highadmin/managers/:employeeID/suspend
POST   /api/highadmin/branches/:branchID/replace-manager

GET    /api/reports
GET    /api/reports/:reportKey?page=1&pageSize=50
```

---

## 7. Important beginner notes

### Backend user vs application user

There are two different user concepts:

1. SQL Server login/database user: used by the backend to connect to SQL Server. Example: `BankAppLogin` mapped to `BankAppUser`.
2. Application user: stored in `dbo.Users`. Example: `highadmin`, branch employees, and customers.

The backend logs into SQL Server once using `BankAppLogin`, but every business action also passes the real authenticated application `UserID` to stored procedures. The database procedures then check application roles.

### SQL injection protection

This backend does not concatenate user input into SQL commands. It uses `mssql` parameters for stored procedure inputs.

### No ORM

There is no Sequelize, Prisma, Entity Framework, or any ORM. This is intentional because the project requires SQL and stored-procedure work.

### Why report routes use other database logins

The security module gives the main app user procedure-execute permission. Report/audit views are intentionally separated. So the backend supports separate read-only report connections:

- `BankReportLogin`
- `BankAuditorLogin`
- `BankHighAdminReportLogin`

This makes the demo closer to a real least-privilege system.

---

## 8. Common errors

### Login failed for user BankAppLogin

Either the SQL Server login was not created, the password in `.env` is wrong, or SQL Server Authentication is not enabled.

### Cannot open database BankManagement

The database was not created, the name in `.env` is wrong, or the login is not mapped to a database user.

### Procedure not found

The database install scripts were not all run, or they were run in the wrong database.

### SELECT permission denied on a report view

Run `03_install_security_and_views.sqlcmd`, then confirm your `.env` uses the report/audit logins.

---

## 9. Development check

Check JavaScript syntax:

```bash
npm run check
```
