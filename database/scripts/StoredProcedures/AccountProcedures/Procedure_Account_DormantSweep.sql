/* =========================================================
   Procedure_Account_DormantSweep_UPDATED.sql
   sp_Account_DormantSweep

   Marks Active accounts as Dormant after N months with no
   completed customer-initiated activity. Customer activity means
   completed Deposit, Withdrawal, or Transfer only. Interest credits
   are excluded by design. Accounts with Pending transactions are
   also excluded so in-flight transactions are not forced to fail
   simply because the sweep ran first.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Account_DormantSweep
(
    @MonthsInactive INT = 12
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF @MonthsInactive IS NULL OR @MonthsInactive <= 0
        BEGIN
            RAISERROR('Months inactive must be greater than zero.', 16, 1);
            RETURN;
        END;

        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#DormantCandidates') IS NOT NULL DROP TABLE #DormantCandidates;

        SELECT
            a.AccountID,
            a.AccountNumber,
            a.OpenDate,
            lastact.LastCustomerActivityAt,
            DATEADD(MONTH, @MonthsInactive,
                    CAST(ISNULL(lastact.LastCustomerActivityAt, a.OpenDate) AS DATE)) AS DormantDueDate
        INTO #DormantCandidates
        FROM dbo.Account a WITH (UPDLOCK, HOLDLOCK)
        OUTER APPLY
        (
            SELECT MAX(COALESCE(tr.CompletedAt, tr.TransactionDate)) AS LastCustomerActivityAt
            FROM dbo.Transactions tr
            INNER JOIN dbo.TransactionType tt ON tt.TransactionTypeID = tr.TransactionTypeID
            WHERE tr.TransactionStatus = 'Completed'
              AND tt.TypeName IN ('Deposit', 'Withdrawal', 'Transfer')
              AND (tr.FromAccountID = a.AccountID OR tr.ToAccountID = a.AccountID)
        ) lastact
        WHERE a.AccountStatus = 'Active'
          AND DATEADD(MONTH, @MonthsInactive,
                      CAST(ISNULL(lastact.LastCustomerActivityAt, a.OpenDate) AS DATE)) <= CAST(GETDATE() AS DATE)
          AND NOT EXISTS (
                SELECT 1
                FROM dbo.Transactions trp
                WHERE trp.TransactionStatus = 'Pending'
                  AND (trp.FromAccountID = a.AccountID OR trp.ToAccountID = a.AccountID)
          );

        UPDATE a
        SET AccountStatus = 'Dormant',
            FrozenPreviousStatus = NULL
        FROM dbo.Account a
        INNER JOIN #DormantCandidates d ON d.AccountID = a.AccountID;

        INSERT INTO dbo.AuditLog (UserID, ActionType, TableName, RecordID, Details)
        SELECT
            NULL,
            'AccountMarkedDormant',
            'Account',
            d.AccountID,
            CONCAT('Account ', d.AccountNumber, ' marked Dormant after ', @MonthsInactive,
                   ' months without completed customer-initiated transactions. Last activity: ',
                   COALESCE(CONVERT(VARCHAR(30), d.LastCustomerActivityAt, 121), 'none'))
        FROM #DormantCandidates d;

        SELECT
            AccountID,
            AccountNumber,
            LastCustomerActivityAt,
            DormantDueDate
        INTO #DormantResult
        FROM #DormantCandidates;

        COMMIT TRANSACTION;

        SELECT AccountID, AccountNumber, LastCustomerActivityAt, DormantDueDate
        FROM #DormantResult
        ORDER BY AccountID;

        DROP TABLE #DormantResult;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
