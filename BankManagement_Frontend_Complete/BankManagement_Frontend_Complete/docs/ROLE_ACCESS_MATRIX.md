# Frontend role access matrix

The frontend routes users to their highest effective role. Backend middleware and SQL Server procedures remain authoritative.

| Capability | Customer | Employee | Admin | HighAdmin |
|---|:---:|:---:|:---:|:---:|
| Signup, login, logout, session check | ✓ | ✓ | ✓ | ✓ |
| View own accounts/history | ✓ | ✓ | ✓ | ✓ |
| Open own account | ✓ | Available through API, not advertised as staff workflow | Available through API, not advertised as staff workflow | Available through API, not advertised as staff workflow |
| Withdraw/transfer | Own authorized accounts | ✓ | ✓ | ✓ |
| Deposit | — | ✓ | ✓ | ✓ |
| Customer create/update/deactivate | — | ✓ | ✓ | ✓ |
| Account search/details/history | Own records | ✓ | ✓ | ✓ |
| Freeze/close/change account type | — | ✓ | ✓ | ✓ |
| Unfreeze account | — | — | ✓ | ✓ through inherited Admin role |
| Finalize transaction | — | ✓ | ✓ | ✓ |
| Reverse transaction in current frontend | — | — | — | — |
| Process pending batch | — | — | ✓ | ✓ |
| Create loan | — | ✓ | ✓ | ✓ |
| View/pay own loan installment | ✓ | ✓ | ✓ | ✓ |
| Run daily loan/installment status maintenance manually | — | — | ✓ | ✓ |
| Employee directory/history | — | Read-only | ✓ | ✓ |
| Hire/create login/change title/suspend/reactivate/fire employee | — | — | ✓ | ✓ |
| Employee transfer request | — | Self | Self/manager | Manager workflow through inherited Admin role |
| Transfer approval decisions | — | — | ✓ | ✓ through inherited Admin role |
| Branch directory | — | ✓ | ✓ | ✓ |
| Operational reports | — | ✓ | ✓ | ✓ |
| Admin reports | — | — | ✓ | ✓ |
| HighAdmin reports | — | — | — | ✓ |
| Manager governance | — | — | — | ✓ |
| Audit trail and branch ledger | — | — | — | ✓ |
| Interest/dormant maintenance | — | — | ✓ | ✓ |
