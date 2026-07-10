# Backend API to frontend mapping

## Public and authentication

| API | Frontend |
|---|---|
| `GET /api/health` | Login connection test and top-bar status |
| `POST /api/setup/initial-high-admin` | First-time HighAdmin setup modal |
| `POST /api/auth/signup` | Customer signup form |
| `POST /api/auth/login` | Login form and role redirect |
| `GET /api/auth/me` | Route guard, profile, and role validation |
| `POST /api/auth/logout` | Sidebar/profile logout |

## Customers

| API | Frontend |
|---|---|
| `GET /api/customers` | Customer directory and filters |
| `POST /api/customers` | Register customer form |
| `PUT /api/customers/:customerID` | Edit customer form |
| `DELETE /api/customers/:customerID` | Deactivate confirmation |

## Accounts

| API | Frontend |
|---|---|
| `GET /api/accounts` | Customer portfolio and staff account search |
| `GET /api/accounts/:accountID` | Account detail modal |
| `GET /api/accounts/:accountID/history` | History modal, date filters, CSV export |
| `POST /api/accounts` | Customer account-opening form |
| `POST /api/accounts/:accountID/close` | Account management modal |
| `POST /api/accounts/:accountID/freeze` | Account management modal |
| `POST /api/accounts/:accountID/unfreeze` | Admin/HighAdmin account management |
| `POST /api/accounts/:accountID/change-type` | Account type form |
| `POST /api/accounts/maintenance/dormant-sweep` | Maintenance workspace |
| `POST /api/accounts/maintenance/apply-monthly-interest` | Maintenance workspace |

## Transactions

| API | Frontend |
|---|---|
| `POST /api/transactions/deposit` | Deposit form |
| `POST /api/transactions/withdraw` | Withdrawal form |
| `POST /api/transactions/transfer` | Transfer form |
| `POST /api/transactions/:transactionID/finalize` | Pending transaction table |
| `POST /api/transactions/:transactionID/reverse` | Reversal form |
| `POST /api/transactions/maintenance/process-pending-batch` | Admin maintenance and transaction desk |

## Loans

| API | Frontend |
|---|---|
| `POST /api/loans` | Staff loan-creation form |
| `GET /api/loans/:loanID/status` | Loan summary/installment modal |
| `POST /api/loans/installments/:installmentID/pay` | Installment payment form |
| `POST /api/loans/maintenance/process-overdue-installments` | Admin maintenance |

## Employees and transfers

| API | Frontend |
|---|---|
| `GET /api/employees` | Employee directory and filters |
| `GET /api/employees/:employeeID` | Employee detail modal |
| `POST /api/employees` | Hire employee form |
| `POST /api/employees/:employeeID/create-user-account` | Create login form |
| `POST /api/employees/:employeeID/change-job-title` | Job-title form |
| `POST /api/employees/:employeeID/fire` | Termination form |
| `POST /api/employees/:employeeID/suspend` | Suspension form |
| `GET /api/employees/:employeeID/branch-history` | Branch-history modal |
| `POST /api/employee-transfers/request-by-employee` | Self-transfer request |
| `POST /api/employee-transfers/request-by-manager` | Manager transfer request |
| `POST /api/employee-transfers/:id/current-manager-decision` | Decision form |
| `POST /api/employee-transfers/:id/destination-manager-decision` | Decision form |

## Branches

| API | Frontend |
|---|---|
| `GET /api/branches` | Branch directory and form catalogues |
| `GET /api/branches/:branchID` | Branch detail modal |

## HighAdmin governance

| API | Frontend |
|---|---|
| `POST /api/highadmin/managers` | Hire manager form |
| `POST /api/highadmin/managers/:employeeID/promote` | Promote employee form |
| `POST /api/highadmin/managers/:employeeID/downgrade` | Downgrade manager form |
| `POST /api/highadmin/managers/:employeeID/fire` | Terminate manager form |
| `POST /api/highadmin/managers/:employeeID/suspend` | Suspend manager form |
| `POST /api/highadmin/branches/:branchID/replace-manager` | Replace manager form |

## Reports

The report catalogue is loaded dynamically from `GET /api/reports`. Every registered report key can be opened, paged, and exported to CSV through `GET /api/reports/:reportKey`.
