/* =========================================================
   sp_AccountType_ListOptions
   ---------------------------------------------------------
   PURPOSE:
   Returns the account-product catalogue required by account
   opening and account-type-change drop-down controls.

   SECURITY:
   - Every caller must map to an active application user and an
     active Customer profile.
   - The result contains reference/product data only.
   ========================================================= */

IF OBJECT_ID(N'dbo.sp_AccountType_ListOptions', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AccountType_ListOptions;
GO

CREATE PROCEDURE dbo.sp_AccountType_ListOptions
(
    @UserID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Users AS U
        INNER JOIN dbo.Customer AS C
            ON C.CustomerID = U.CustomerID
        WHERE U.UserID = @UserID
          AND U.IsActive = 1
          AND C.IsActive = 1
    )
    BEGIN
        RAISERROR('Invalid or inactive authenticated user.', 16, 1);
        RETURN;
    END;

    SELECT
        AT.AccountTypeID,
        AT.TypeName,
        AT.MinBalance,
        AT.InterestRate,
        AT.MonthlyFee
    FROM dbo.AccountType AS AT
    ORDER BY
        AT.TypeName,
        AT.AccountTypeID;
END;
GO
