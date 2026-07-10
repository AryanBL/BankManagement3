# BankManagement Frontend — Complete Package

Role-aware frontend for the BankManagement Node.js + SQL Server backend.

## Technology

- HTML5
- CSS3
- Vanilla JavaScript
- Browser Fetch API
- No framework
- No npm dependencies
- Built-in Node.js static server included

## Main pages

| File | Purpose |
|---|---|
| `index.html` | Login, customer signup, logout/session continuation, initial HighAdmin bootstrap, API settings |
| `customer.html` | Customer self-service workspace |
| `employee.html` | Employee operations workspace |
| `admin.html` | Admin and branch-management workspace |
| `highadmin.html` | HighAdmin governance, reports, and audit workspace |
| `preview.html` | Mock-data preview of every role without changing the database |

## Backend connection

The default backend address is:

```text
http://127.0.0.1:4000
```

It is configured in:

```text
assets/js/core/config.js
```

The address can also be changed without editing source code:

1. Open the login page.
2. Select **Connection settings**.
3. Enter the backend base URL.
4. Select **Save and test**.

The chosen value is saved in browser local storage.

## Run the backend

Open a terminal in the backend folder:

```bash
npm install
npm run dev
```

The backend should report that it is listening on port `4000`.

Test it in a browser or Postman:

```text
http://127.0.0.1:4000/api/health
```

## Configure backend CORS

For this frontend server, add the following to the backend `.env` file:

```env
CORS_ORIGIN=http://127.0.0.1:5500,http://localhost:5500
```

Restart the backend after changing `.env`.

An empty `CORS_ORIGIN` in the current backend allows all origins, but explicitly listing the frontend origin is recommended.

## Run the frontend

Node.js is already required by the backend, so the frontend package includes a dependency-free Node static server.

### Windows — easiest method

Double-click:

```text
start-frontend.cmd
```

Or open a terminal in this frontend folder and run:

```bash
npm start
```

### PowerShell

```powershell
.\start-frontend.ps1
```

### macOS/Linux

```bash
./start-frontend.sh
```

Then open:

```text
http://127.0.0.1:5500
```

Do not open the HTML files directly with a `file:///` address. Use the included static server so browser routing, Fetch API behavior, and CORS origins are consistent.

## Authentication flow

1. The login page calls `POST /api/auth/login`.
2. The returned session token is stored in local storage or session storage, depending on **Keep this session on this device**.
3. The frontend calls `GET /api/auth/me`.
4. It reads the effective role hierarchy:

```text
Customer → Employee → Admin → HighAdmin
```

5. The user is redirected to the page for the highest effective role.
6. Protected API requests send:

```http
Authorization: Bearer <session-token>
```

7. Logout calls `POST /api/auth/logout` and removes the browser session.

## Implemented backend features

### Authentication and setup

- Customer signup
- Login
- Session validation
- Logout
- Initial HighAdmin one-time setup
- Role-aware redirect
- Persistent or browser-session login

### Customer workspace

- Account portfolio and balances
- Account details
- Account history with date filters
- CSV history export
- Open account
- Withdrawal
- Transfer to another account ID
- Loan status lookup
- Installment payment
- Profile and session information

### Employee workspace

- Customer search, filters, create, update, deactivate
- Account search and filters
- Account details and history
- Freeze, close, and change account type
- Deposits, withdrawals, transfers
- Transaction finalization and reversal
- Loan creation, status, and payment
- Branch directory and details
- Employee directory and branch history
- Employee transfer request
- Operational reports

### Admin workspace

Includes Employee capabilities plus:

- Hire employees
- Create employee application accounts
- Change employee job titles
- Suspend and terminate employees
- Manager-created employee transfer requests
- Current/destination manager decisions
- Unfreeze accounts
- Process pending transactions
- Process overdue installments
- Apply monthly interest
- Dormant account sweep
- Admin reporting views

### HighAdmin workspace

Includes lower-role capabilities plus:

- Hire branch managers
- Promote employees to manager
- Downgrade managers
- Suspend and terminate managers
- Replace branch manager
- HighAdmin reporting views
- User access overview
- Audit trail
- Branch ledger

## Reporting

The UI discovers the report catalogue from:

```text
GET /api/reports
```

It supports:

- Role-filtered report cards
- Pagination
- CSV export
- Employee reports
- Admin reports
- HighAdmin reports
- Audit and ledger reports

## Important backend limitations reflected in the UI

### No public account-type catalogue endpoint

The backend does not currently expose endpoints such as:

```text
GET /api/account-types
GET /api/public/branches
```

Therefore, opening an account may require entering numeric `BranchID` and `AccountTypeID`. The frontend discovers existing values from accessible account records when possible.

### No transfer-request listing endpoint

The backend provides transfer creation and decision endpoints but no `GET /api/employee-transfers` route. The UI displays newly returned transfer IDs and keeps a local browser activity log, but it cannot load the authoritative server-side transfer queue.

### No password-change endpoint

The UI does not invent a password-change feature because no matching backend API exists.

## Preview mode

Open:

```text
http://127.0.0.1:5500/preview.html
```

Preview mode uses mock data and does not call or modify the backend database.

## Source structure

```text
BankManagement_Frontend_Complete/
├── index.html
├── preview.html
├── customer.html
├── employee.html
├── admin.html
├── highadmin.html
├── frontend-server.js
├── package.json
├── start-frontend.cmd
├── start-frontend.ps1
├── start-frontend.sh
├── assets/
│   ├── css/
│   │   ├── tokens.css
│   │   ├── base.css
│   │   ├── components.css
│   │   ├── auth.css
│   │   ├── dashboard.css
│   │   └── responsive.css
│   └── js/
│       ├── core/
│       │   ├── config.js
│       │   ├── icons.js
│       │   ├── session.js
│       │   ├── mock-data.js
│       │   ├── api.js
│       │   ├── ui.js
│       │   ├── workspace.js
│       │   └── features.js
│       └── pages/
│           ├── auth-page.js
│           ├── preview.js
│           ├── customer.js
│           ├── employee.js
│           ├── admin.js
│           └── highadmin.js
└── docs/
    ├── ROLE_ACCESS_MATRIX.md
    ├── API_UI_MAPPING.md
    └── CONNECTION_AND_RUN.md
```

## Security notes

- Frontend role-based hiding improves usability but is not the security boundary.
- The Node backend and SQL Server stored procedures remain authoritative.
- No database credentials are included in this frontend package.
- No sample passwords are embedded in the application source.
- API errors are displayed without exposing stack traces.
