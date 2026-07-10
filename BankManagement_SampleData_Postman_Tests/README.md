# BankManagement realistic sample-data Postman package

This package was generated from:

```text
01_Combined_RealisticSampleData_And_ErrorInjection_HTML_FIXED.sql
```

## Files

- `BankManagement_RealisticSampleData_Tests.postman_collection.json`
- `BankManagement_RealisticSampleData_Local.postman_environment.json`
- `Sample_Data_Reference.json`
- `TEST_MATRIX.md`

## Import

1. Open Postman.
2. Select **Import**.
3. Import both Postman JSON files.
4. Select the environment:

   ```text
   BankManagement - Realistic Sample Data Local
   ```

5. Start the backend with `npm run dev`.
6. Confirm the base URL is `http://127.0.0.1:4000`.
7. Run:

   ```text
   00 - REQUIRED Preflight, Sample Logins, and ID Resolution
   ```

## What should pass

All requests in folder 00 should pass when:

- the uploaded realistic sample data is installed;
- the backend is running;
- SQL Server logins/passwords in `.env` are correct;
- report database logins are working.

Folders 03 and 04 contain deliberate negative tests. The API response reports `success: false`, but the Postman assertion passes when the expected HTTP status is returned.

## Login rate limit

The backend allows 20 login attempts per 15 minutes. Avoid repeatedly running the login-heavy preflight folder in a short period.

## Pending transactions

The seed creates pending transaction scenarios, but SQL Server Agent may complete them later. The pending-transactions report test therefore validates API access and view mapping rather than requiring an exact row count.

## State-changing folders

Folders 06 and 07 are optional. They create or modify data. Use them only on a demo database.
