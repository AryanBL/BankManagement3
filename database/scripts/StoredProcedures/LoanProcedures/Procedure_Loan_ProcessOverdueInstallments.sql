/* =========================================================
   Procedure_Loan_ProcessOverdueInstallments.sql
   sp_Loan_ProcessOverdueInstallments

   Manual/API scope:
   - Effective Admin (branch manager / vice manager): current
     branch only.
   - Effective HighAdmin: all branches, or one optional BranchID.

   Scheduled scope:
   - SQL Server Agent may call the procedure without @UserID;
     that trusted system call processes all branches.

   Default rule:
   - Installment is not Paid or Defaulted.
   - DueDate is more than 90 days in the past.
   - No payment transaction is currently Pending.
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_Loan_ProcessOverdueInstallments
(
    @UserID   INT = NULL,
    @BranchID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE
            @EffectiveBranchID INT = NULL,
            @AccessMode NVARCHAR(30) = N'SystemAllBranches';

        ----------------------------------------------------
        -- Resolve API caller scope. NULL @UserID is reserved
        -- for SQL Agent / trusted scheduled execution.
        ----------------------------------------------------
        IF @UserID IS NOT NULL
        BEGIN
            IF dbo.fn_UserHasEffectiveRole(@UserID, N'HighAdmin') = 1
            BEGIN
                SET @EffectiveBranchID = @BranchID;
                SET @AccessMode = CASE WHEN @BranchID IS NULL
                    THEN N'HighAdminAllBranches'
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
                    RAISERROR('A branch manager can process overdue installments only for the current branch.', 16, 1);
                    RETURN;
                END;

                SET @AccessMode = N'AdminCurrentBranch';
            END
            ELSE
            BEGIN
                RAISERROR('Only an effective branch manager/Admin or HighAdmin can process overdue installments manually.', 16, 1);
                RETURN;
            END;
        END;

        BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#ToDefault') IS NOT NULL DROP TABLE #ToDefault;

        SELECT
            I.InstallmentID,
            I.LoanID,
            L.BranchID,
            I.DueDate,
            I.Amount
        INTO #ToDefault
        FROM dbo.Installment AS I
        INNER JOIN dbo.Loan AS L
            ON L.LoanID = I.LoanID
        LEFT JOIN dbo.Transactions AS T
            ON T.TransactionID = I.PaymentTransactionID
        WHERE I.InstallmentStatus NOT IN (N'Paid', N'Defaulted')
          AND I.DueDate < DATEADD(DAY, -90, CAST(GETDATE() AS DATE))
          AND (T.TransactionID IS NULL OR T.TransactionStatus <> N'Pending')
          AND (@EffectiveBranchID IS NULL OR L.BranchID = @EffectiveBranchID);

        IF NOT EXISTS (SELECT 1 FROM #ToDefault)
        BEGIN
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
                N'OverdueInstallmentSweep',
                N'Installment',
                NULL,
                CONCAT(
                    N'No eligible overdue installments found. AccessMode=', @AccessMode,
                    N'; BranchID=', ISNULL(CONVERT(NVARCHAR(20), @EffectiveBranchID), N'ALL')
                )
            );

            COMMIT TRANSACTION;

            SELECT
                CAST(NULL AS INT) AS InstallmentID,
                CAST(NULL AS INT) AS LoanID,
                CAST(NULL AS INT) AS BranchID,
                CAST(NULL AS NVARCHAR(20)) AS Outcome
            WHERE 1 = 0;

            RETURN;
        END;

        UPDATE I
        SET I.InstallmentStatus = N'Defaulted'
        FROM dbo.Installment AS I
        INNER JOIN #ToDefault AS D
            ON D.InstallmentID = I.InstallmentID;

        IF OBJECT_ID('tempdb..#LoansToDefault') IS NOT NULL DROP TABLE #LoansToDefault;

        SELECT DISTINCT
            D.LoanID,
            D.BranchID
        INTO #LoansToDefault
        FROM #ToDefault AS D
        INNER JOIN dbo.Loan AS L
            ON L.LoanID = D.LoanID
        WHERE L.LoanStatus = N'Active';

        UPDATE L
        SET L.LoanStatus = N'Defaulted'
        FROM dbo.Loan AS L
        INNER JOIN #LoansToDefault AS D
            ON D.LoanID = L.LoanID;

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
            N'InstallmentDefaulted',
            N'Installment',
            D.InstallmentID,
            CONCAT(
                N'LoanID=', D.LoanID,
                N'; BranchID=', D.BranchID,
                N'; Amount=', D.Amount,
                N'; DueDate=', CONVERT(NVARCHAR(10), D.DueDate, 120),
                N'; AccessMode=', @AccessMode
            )
        FROM #ToDefault AS D;

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
                N'Loan marked Defaulted because at least one installment was more than 90 days overdue. ',
                N'BranchID=', D.BranchID,
                N'; AccessMode=', @AccessMode
            )
        FROM #LoansToDefault AS D;

        COMMIT TRANSACTION;

        SELECT
            D.InstallmentID,
            D.LoanID,
            D.BranchID,
            N'Defaulted' AS Outcome
        FROM #ToDefault AS D
        ORDER BY D.BranchID, D.LoanID, D.InstallmentID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
