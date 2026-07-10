# Sample-data aligned Postman test matrix

## Required first run

Run:

```text
00 - REQUIRED Preflight, Sample Logins, and ID Resolution
```

This folder uses exact seeded credentials:

| Role/state | Username | Password |
|---|---|---|
| HighAdmin | `gandalf.highadmin` | `Mellon#2026` |
| Admin / Branch Manager | `spongebob.manager` | `Pineapple#1` |
| Destination Admin | `galadriel.manager` | `Lorien#1` |
| Employee | `patrick.teller` | `Starfish#1` |
| Customer | `olivia.harper` | `Olivia#2026` |
| Customer | `noah.bennett` | `Noah#2026` |
| Customer | `maya.foster` | `Maya#2026` |
| Customer with frozen account | `ava.morgan` | `Ava#2026` |
| Customer with closed account | `james.parker` | `James#2026` |

IDs are resolved dynamically from branch codes, national IDs, account types, and report rows.

## Expected error tests

Folders 03 and 04 deliberately generate errors. A response such as:

```json
{
  "success": false,
  "error": {
    "message": "..."
  }
}
```

is correct when the Postman test itself is green.

Exact SQL error-injection mappings:

| SQL scenario | HTTP request | Expected |
|---|---|---|
| E01 duplicate username | `POST /api/auth/signup` | 400 |
| E02 insufficient transfer | `POST /api/transactions/transfer` | 400 |
| E03 closed-account withdrawal | `POST /api/transactions/withdraw` | 400 |
| E04 frozen-account deposit | `POST /api/transactions/deposit` | 400 |
| E05 missing transaction reversal | `POST /api/transactions/-999999/reverse` | 400 |
| E06 negative loan | `POST /api/loans` | 400 |
| E07 second initial HighAdmin | `POST /api/setup/initial-high-admin` | 400 |
| E08 customer reads another customer account | `GET /api/accounts/{NoahAccountID}` as Olivia | 400 |

## Important sample-state behavior

Suspended and fired employees are not fully locked out. The database procedures intentionally preserve their customer login:

- `plankton.risk` logs in as Customer only because the employee is `OnLeave`.
- `bilbo.archive` logs in as Customer only because the employee is `Terminated`.
- `shelob.vault` cannot log in because the sample script never created a login.

## Optional folders

Folders 06 and 07 change database state. Do not run them as part of a read-only demonstration.
