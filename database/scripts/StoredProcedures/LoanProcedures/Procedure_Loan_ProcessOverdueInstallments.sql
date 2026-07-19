/* =========================================================
   Procedure_Loan_ProcessOverdueInstallments.sql
   sp_Loan_ProcessOverdueInstallments
   ---------------------------------------------------------
   Performs daily loan/installment status maintenance.

   Installment rules:
   - Paid and Defaulted are terminal.
   - Unpaid installments past DueDate become Late when no
     payment transaction is currently Pending.
   - Unpaid installments more than 90 days overdue become
     Defaulted when no payment transaction is currently Pending.
   - A Late installment whose DueDate is moved to today/future
     is restored to Pending.

   Loan rules:
   - An Active loan with any Defaulted installment becomes
     Defaulted.
   - An Active loan whose installments are all Paid becomes Paid.
   - When a loan becomes Defaulted, every Active or Dormant
     account owned by that borrower becomes Frozen. The previous
     status is stored in FrozenPreviousStatus.

   Scope:
   - Effective Admin: caller's current branch only.
   - Effective HighAdmin: all branches or optional BranchID.
   - SQL Server Agent: NULL UserID, all branches.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Loan_ProcessOverdueInstallments
(
    @UserID INT = NULL,
    @BranchID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @Today DATE = CAST(GETDATE() AS DATE),
            @DefaultCutoff DATE,
            @EffectiveBranchID INT = NULL,
            @AccessMode NVARCHAR(30) = N'SystemAllBranches';

        SET @DefaultCutoff = DATEADD(DAY, -90, @Today);

        IF @UserID IS NOT NULL
        BEGIN
            IF dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin') = 1
            BEGIN
                SET @EffectiveBranchID = @BranchID;
                SET @AccessMode = CASE
                    WHEN @BranchID IS NULL THEN N'HighAdminAllBranches'
                    ELSE N'HighAdminOneBranch'
                END;
            END
            ELSE IF dbo.fn_UserHasEffectiveRole(@UserID, N'Admin') = 1
            BEGIN
                SELECT TOP (1)
                    @EffectiveBranchID = EB.BranchID
                FROM dbo.Users AS U
                INNER JOIN dbo.EMPB AS EB
                    ON EB.EmployeeID = U.EmployeeID
                WHERE U.UserID = @UserID
                  AND EB.WorkingStatus = N'Working'
                  AND EB.EndDate IS NULL
                ORDER BY EB.StartDate DESC, EB.EMPBID DESC;

                IF @EffectiveBranchID IS NULL
                BEGIN
                    RAISERROR('The branch manager does not have an active branch assignment.', 16, 1);
                    RETURN;
                END;

                IF @BranchID IS NOT NULL AND @BranchID <> @EffectiveBranchID
                BEGIN
                    RAISERROR('A branch manager can update loan statuses only for the current branch.', 16, 1);
                    RETURN;
                END;

                SET @AccessMode = N'AdminCurrentBranch';
            END
            ELSE
            BEGIN
                RAISERROR('Only an effective branch manager/Admin or HighAdmin can run loan status maintenance manually.', 16, 1);
                RETURN;
            END;
        END;

        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#ToDefault') IS NOT NULL DROP TABLE #ToDefault;
        IF OBJECT_ID('tempdb..#ToLate') IS NOT NULL DROP TABLE #ToLate;
        IF OBJECT_ID('tempdb..#ToPending') IS NOT NULL DROP TABLE #ToPending;
        IF OBJECT_ID('tempdb..#LoansToDefault') IS NOT NULL DROP TABLE #LoansToDefault;
        IF OBJECT_ID('tempdb..#LoansToPaid') IS NOT NULL DROP TABLE #LoansToPaid;
        IF OBJECT_ID('tempdb..#AccountsToFreeze') IS NOT NULL DROP TABLE #AccountsToFreeze;

        SELECT
            I.InstallmentID,
            I.LoanID,
            L.CustomerID,
            L.BranchID,
            I.DueDate,
            I.Amount,
            I.InstallmentStatus AS OldStatus
        INTO #ToDefault
        FROM dbo.Installment AS I WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Loan AS L WITH (UPDLOCK, HOLDLOCK)
            ON L.LoanID = I.LoanID
        LEFT JOIN dbo.Transactions AS T
            ON T.TransactionID = I.PaymentTransactionID
        WHERE I.InstallmentStatus NOT IN (N'Paid', N'Defaulted')
          AND I.DueDate < @DefaultCutoff
          AND (T.TransactionID IS NULL OR T.TransactionStatus <> N'Pending')
          AND (@EffectiveBranchID IS NULL OR L.BranchID = @EffectiveBranchID);

        SELECT
            I.InstallmentID,
            I.LoanID,
            L.CustomerID,
            L.BranchID,
            I.DueDate,
            I.Amount,
            I.InstallmentStatus AS OldStatus
        INTO #ToLate
        FROM dbo.Installment AS I WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Loan AS L WITH (UPDLOCK, HOLDLOCK)
            ON L.LoanID = I.LoanID
        LEFT JOIN dbo.Transactions AS T
            ON T.TransactionID = I.PaymentTransactionID
        WHERE I.InstallmentStatus = N'Pending'
          AND I.DueDate < @Today
          AND I.DueDate >= @DefaultCutoff
          AND (T.TransactionID IS NULL OR T.TransactionStatus <> N'Pending')
          AND (@EffectiveBranchID IS NULL OR L.BranchID = @EffectiveBranchID);

        SELECT
            I.InstallmentID,
            I.LoanID,
            L.CustomerID,
            L.BranchID,
            I.DueDate,
            I.Amount,
            I.InstallmentStatus AS OldStatus
        INTO #ToPending
        FROM dbo.Installment AS I WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Loan AS L WITH (UPDLOCK, HOLDLOCK)
            ON L.LoanID = I.LoanID
        LEFT JOIN dbo.Transactions AS T
            ON T.TransactionID = I.PaymentTransactionID
        WHERE I.InstallmentStatus = N'Late'
          AND I.DueDate >= @Today
          AND (T.TransactionID IS NULL OR T.TransactionStatus <> N'Pending')
          AND (@EffectiveBranchID IS NULL OR L.BranchID = @EffectiveBranchID);

        UPDATE I
        SET I.InstallmentStatus = N'Defaulted'
        FROM dbo.Installment AS I
        INNER JOIN #ToDefault AS D
            ON D.InstallmentID = I.InstallmentID;

        UPDATE I
        SET I.InstallmentStatus = N'Late'
        FROM dbo.Installment AS I
        INNER JOIN #ToLate AS D
            ON D.InstallmentID = I.InstallmentID;

        UPDATE I
        SET I.InstallmentStatus = N'Pending'
        FROM dbo.Installment AS I
        INNER JOIN #ToPending AS D
            ON D.InstallmentID = I.InstallmentID;

        SELECT DISTINCT
            L.LoanID,
            L.CustomerID,
            L.BranchID,
            L.LoanStatus AS OldStatus
        INTO #LoansToDefault
        FROM dbo.Loan AS L WITH (UPDLOCK, HOLDLOCK)
        WHERE L.LoanStatus = N'Active'
          AND (@EffectiveBranchID IS NULL OR L.BranchID = @EffectiveBranchID)
          AND EXISTS
          (
              SELECT 1
              FROM dbo.Installment AS I
              WHERE I.LoanID = L.LoanID
                AND I.InstallmentStatus = N'Defaulted'
          );

        UPDATE L
        SET L.LoanStatus = N'Defaulted'
        FROM dbo.Loan AS L
        INNER JOIN #LoansToDefault AS D
            ON D.LoanID = L.LoanID;

        SELECT
            L.LoanID,
            L.CustomerID,
            L.BranchID,
            L.LoanStatus AS OldStatus
        INTO #LoansToPaid
        FROM dbo.Loan AS L WITH (UPDLOCK, HOLDLOCK)
        WHERE L.LoanStatus = N'Active'
          AND (@EffectiveBranchID IS NULL OR L.BranchID = @EffectiveBranchID)
          AND EXISTS
          (
              SELECT 1
              FROM dbo.Installment AS I
              WHERE I.LoanID = L.LoanID
          )
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.Installment AS I
              WHERE I.LoanID = L.LoanID
                AND I.InstallmentStatus <> N'Paid'
          );

        UPDATE L
        SET L.LoanStatus = N'Paid'
        FROM dbo.Loan AS L
        INNER JOIN #LoansToPaid AS P
            ON P.LoanID = L.LoanID;

        SELECT
            A.AccountID,
            A.CustomerID,
            A.BranchID,
            A.AccountStatus AS OldStatus,
            MIN(D.LoanID) AS LoanID
        INTO #AccountsToFreeze
        FROM dbo.Account AS A WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN #LoansToDefault AS D
            ON D.CustomerID = A.CustomerID
        WHERE A.AccountStatus IN (N'Active', N'Dormant')
        GROUP BY
            A.AccountID,
            A.CustomerID,
            A.BranchID,
            A.AccountStatus;

        UPDATE A
        SET
            A.FrozenPreviousStatus = A.AccountStatus,
            A.AccountStatus = N'Frozen'
        FROM dbo.Account AS A
        INNER JOIN #AccountsToFreeze AS F
            ON F.AccountID = A.AccountID;

        INSERT INTO dbo.AuditLog
        (
            UserID,
            ActionType,
            TableName,
            RecordID,
            Details
        )
        SELECT
            @UserID,
            N'InstallmentStatusChanged',
            N'Installment',
            X.InstallmentID,
            CONCAT(
                N'LoanID=', X.LoanID,
                N'; BranchID=', X.BranchID,
                N'; OldStatus=', X.OldStatus,
                N'; NewStatus=', X.NewStatus,
                N'; DueDate=', CONVERT(NVARCHAR(10), X.DueDate, 120),
                N'; AccessMode=', @AccessMode
            )
        FROM
        (
            SELECT InstallmentID, LoanID, BranchID, DueDate, OldStatus, N'Defaulted' AS NewStatus FROM #ToDefault
            UNION ALL
            SELECT InstallmentID, LoanID, BranchID, DueDate, OldStatus, N'Late' AS NewStatus FROM #ToLate
            UNION ALL
            SELECT InstallmentID, LoanID, BranchID, DueDate, OldStatus, N'Pending' AS NewStatus FROM #ToPending
        ) AS X;

        INSERT INTO dbo.AuditLog
        (
            UserID,
            ActionType,
            TableName,
            RecordID,
            Details
        )
        SELECT
            @UserID,
            N'LoanDefaulted',
            N'Loan',
            D.LoanID,
            CONCAT(
                N'CustomerID=', D.CustomerID,
                N'; BranchID=', D.BranchID,
                N'; Reason=one or more installments are Defaulted',
                N'; AccessMode=', @AccessMode
            )
        FROM #LoansToDefault AS D;

        INSERT INTO dbo.AuditLog
        (
            UserID,
            ActionType,
            TableName,
            RecordID,
            Details
        )
        SELECT
            @UserID,
            N'LoanPaid',
            N'Loan',
            P.LoanID,
            CONCAT(
                N'CustomerID=', P.CustomerID,
                N'; BranchID=', P.BranchID,
                N'; Reason=all installments are Paid',
                N'; AccessMode=', @AccessMode
            )
        FROM #LoansToPaid AS P;

        INSERT INTO dbo.AuditLog
        (
            UserID,
            ActionType,
            TableName,
            RecordID,
            Details
        )
        SELECT
            @UserID,
            N'AccountFrozenDueToLoanDefault',
            N'Account',
            F.AccountID,
            CONCAT(
                N'CustomerID=', F.CustomerID,
                N'; TriggeringLoanID=', F.LoanID,
                N'; AccountBranchID=', F.BranchID,
                N'; PreviousStatus=', F.OldStatus,
                N'; AccessMode=', @AccessMode
            )
        FROM #AccountsToFreeze AS F;

        INSERT INTO dbo.AuditLog
        (
            UserID,
            ActionType,
            TableName,
            RecordID,
            Details
        )
        VALUES
        (
            @UserID,
            N'DailyLoanStatusSweep',
            N'Loan',
            NULL,
            CONCAT(
                N'Late=', (SELECT COUNT(*) FROM #ToLate),
                N'; DefaultedInstallments=', (SELECT COUNT(*) FROM #ToDefault),
                N'; RestoredPending=', (SELECT COUNT(*) FROM #ToPending),
                N'; DefaultedLoans=', (SELECT COUNT(*) FROM #LoansToDefault),
                N'; PaidLoans=', (SELECT COUNT(*) FROM #LoansToPaid),
                N'; FrozenAccounts=', (SELECT COUNT(*) FROM #AccountsToFreeze),
                N'; BranchID=', ISNULL(CONVERT(NVARCHAR(20), @EffectiveBranchID), N'ALL'),
                N'; AccessMode=', @AccessMode
            )
        );

        COMMIT TRANSACTION;

        SELECT
            N'Installment' AS EntityType,
            X.InstallmentID AS EntityID,
            X.LoanID,
            X.BranchID,
            X.OldStatus,
            X.NewStatus
        FROM
        (
            SELECT InstallmentID, LoanID, BranchID, OldStatus, N'Defaulted' AS NewStatus FROM #ToDefault
            UNION ALL
            SELECT InstallmentID, LoanID, BranchID, OldStatus, N'Late' AS NewStatus FROM #ToLate
            UNION ALL
            SELECT InstallmentID, LoanID, BranchID, OldStatus, N'Pending' AS NewStatus FROM #ToPending
        ) AS X

        UNION ALL

        SELECT
            N'Loan',
            D.LoanID,
            D.LoanID,
            D.BranchID,
            D.OldStatus,
            N'Defaulted'
        FROM #LoansToDefault AS D

        UNION ALL

        SELECT
            N'Loan',
            P.LoanID,
            P.LoanID,
            P.BranchID,
            P.OldStatus,
            N'Paid'
        FROM #LoansToPaid AS P

        UNION ALL

        SELECT
            N'Account',
            F.AccountID,
            F.LoanID,
            F.BranchID,
            F.OldStatus,
            N'Frozen'
        FROM #AccountsToFreeze AS F
        ORDER BY EntityType, BranchID, LoanID, EntityID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
        RETURN;
    END CATCH;
END;
GO
