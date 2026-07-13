/* =========================================================
   sp_Branch_ListOptions
   ---------------------------------------------------------
   PURPOSE:
   Returns the non-sensitive branch catalogue required by
   authenticated UI forms such as account opening and employee
   transfer requests.

   SECURITY:
   - Every caller must map to an active application user and an
     active Customer profile.
   - Only branch identity fields are returned.
   - Financial, staffing, address, phone, and manager details are
     intentionally excluded from this catalogue.
   ========================================================= */

IF OBJECT_ID(N'dbo.sp_Branch_ListOptions', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Branch_ListOptions;
GO

CREATE PROCEDURE dbo.sp_Branch_ListOptions
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
        B.BranchID,
        B.BranchCode,
        B.BranchName,
        B.City
    FROM dbo.Branch AS B
    ORDER BY
        B.BranchName,
        B.BranchCode,
        B.BranchID;
END;
GO
