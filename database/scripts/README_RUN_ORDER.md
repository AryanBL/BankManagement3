# Fixed Scripts Package - Run Order

This package removes the superseded update folders and keeps one final definition per stored procedure.
Run in this order:

1. `TableCreation/TableCreation.sql`
2. `Functions/PasswordHash.sql`
3. `Rules/Schema_CustomerAccessAndBranchLedger.sql`
4. `Rules/Schema_AccountModuleSupport_SELF_SERVICE.sql`
5. `Rules/Schema_EmployeeModuleSupport.sql`
6. `Rules/EMPB_PreventDateOverlap.sql`
7. `Rules/ApplyAccessRules.sql`
8. `Rules/99_Function_UserHasEffectiveRole.sql`
9. Triggers
10. User/session/customer/account/transaction/loan/employee procedures
11. Agent Jobs
12. `SampleData/SampleData.sql` only after all objects are installed

Main coherence fixes:

- Removed old duplicate modules that could overwrite final procedures.
- Rewrote `SampleData.sql` for the final schema.
- Fixed `Branch.Balance` null/default consistency.
- Added `fn_UserHasEffectiveRole` and used it in final authorization-sensitive procedures.
- Employee/manager user creation now reuses existing customer login rows instead of violating `UQ_Users_CustomerID`.
- Manager replacement now ensures `Customer + Employee + Admin` roles.
- Fired/suspended employees keep `Users.IsActive = 1` and lose only effective employee/admin privileges.
- Single transaction finalizer now logs `AccountReactivated` like batch finalizer.
- Customer/account/transaction/loan sensitive procedures now require authenticated `@UserID` authorization.

Notes:

- The old directories `EmploymentStatus_CustomerLogin_Update` and `UserSecurity_HighAdmin_Module` are intentionally excluded from this fixed package.
- `Rules/Schema_UserSecurity_HighAdminSupport.sql` is kept as a no-op placeholder only, so it cannot reintroduce old conflicting triggers.
