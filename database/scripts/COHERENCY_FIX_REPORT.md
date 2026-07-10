# Coherency Fix Report

This fixed package was built from the uploaded `Scripts.zip` content and reorganized in the same main sub-directory style, but with superseded modules removed or neutralized.

## Removed from executable package

The following old/conflicting folders were not included because they contained older procedure definitions that could overwrite final logic:

- `EmploymentStatus_CustomerLogin_Update/`
- `UserSecurity_HighAdmin_Module/`

`Rules/Schema_UserSecurity_HighAdminSupport.sql` is kept only as a no-op placeholder so it cannot reintroduce old triggers.

## Fixed coherency issues

1. **Old procedure overwrite risk**
   - Final package contains one executable definition per stored procedure.
   - Final files are renamed to canonical names, for example `Procedure_User_Login.sql`, `Procedure_HighAdmin_ReplaceBranchManager.sql`, etc.

2. **Branch.Balance NULL/default issue**
   - `TableCreation.sql` now creates `Branch.Balance` as `NOT NULL DEFAULT(0)`.
   - `Schema_CustomerAccessAndBranchLedger.sql` now also repairs older databases where `Branch.Balance` already existed as nullable.

3. **One login per CustomerID conflict**
   - `sp_Employee_CreateUserAccount` now reuses an existing customer login when the employee's `NationalID` already belongs to a customer with a user row.
   - `sp_HighAdmin_HireManager` does the same.
   - `sp_HighAdmin_CreateInitialUser` can reuse an existing customer-only login for HighAdmin.

4. **Manager replacement role gap**
   - `sp_HighAdmin_ReplaceBranchManager` now ensures the incoming manager has `Customer + Employee + Admin` roles, not only `Admin`.

5. **Employee status vs user login**
   - Final employee/manager fire/suspend procedures do not set `Users.IsActive = 0`.
   - Employment state is controlled by `Employee.EmpStatus`.
   - The user can still log in as Customer if `Users.IsActive = 1` and `Customer.IsActive = 1`.

6. **Vice/branch manager protection**
   - `sp_Employee_Suspend` now explicitly blocks manager-level targets, matching `sp_Employee_Fire`.
   - Manager-level actions remain under HighAdmin procedures.

7. **Dormant reactivation audit**
   - `sp_Transaction_Finalize` now logs `AccountReactivated` when a single finalized transaction reactivates a Dormant destination account.
   - This matches the batch finalizer behavior.

8. **Sensitive procedure authorization**
   - Added central helper `dbo.fn_UserHasEffectiveRole`.
   - Customer update/delete, account close/freeze/unfreeze/change type, transaction deposit/withdraw/transfer, and loan create/status/payment now require authenticated `@UserID` and check effective role.

9. **SampleData.sql**
   - Rewritten for final schema.
   - Uses 12-digit numeric account numbers.
   - Uses `FromAccountID` / `ToAccountID` model.
   - Ensures every `Users` row has `CustomerID`.
   - Assigns roles in final model order.

## Install entry point

Use `00_MasterInstall_SQLCMD.sql` in SQLCMD mode, or manually run files in `README_RUN_ORDER.md` order.
