/* =========================================================
   Function_UserHasEffectiveRole.sql
   dbo.fn_UserHasEffectiveRole
   ---------------------------------------------------------
   Central helper used by the final authorization-protected
   procedures. It returns whether a user currently has an
   EFFECTIVE role under the final model:
     Customer, Employee, Admin, HighAdmin.

   This function deliberately checks current user/customer/
   employee state, not only raw UserRoles rows.

   Run AFTER:
     - TableCreation.sql
     - Schema_CustomerAccessAndBranchLedger.sql
     - ApplyAccessRules.sql
   ========================================================= */

IF OBJECT_ID('dbo.fn_UserHasEffectiveRole', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_UserHasEffectiveRole;
GO

CREATE FUNCTION dbo.fn_UserHasEffectiveRole
(
    @UserID INT,
    @RoleName NVARCHAR(50)
)
RETURNS BIT
AS
BEGIN
    DECLARE @Result BIT = 0;
    DECLARE @CustomerID INT;
    DECLARE @EmployeeID INT;

    SELECT
        @CustomerID = U.CustomerID,
        @EmployeeID = U.EmployeeID
    FROM dbo.Users AS U
    INNER JOIN dbo.Customer AS C
        ON C.CustomerID = U.CustomerID
    WHERE U.UserID = @UserID
      AND U.IsActive = 1
      AND C.IsActive = 1;

    IF @CustomerID IS NULL
        RETURN 0;

    IF @RoleName = N'Customer'
       AND EXISTS
       (
           SELECT 1
           FROM dbo.UserRoles AS UR
           INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
           WHERE UR.UserID = @UserID
             AND R.RoleName = N'Customer'
       )
    BEGIN
        SET @Result = 1;
    END;

    IF @RoleName = N'HighAdmin'
       AND @EmployeeID IS NULL
       AND EXISTS
       (
           SELECT 1
           FROM dbo.UserRoles AS UR
           INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
           WHERE UR.UserID = @UserID
             AND R.RoleName = N'HighAdmin'
       )
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.UserRoles AS UR
           INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
           WHERE UR.UserID = @UserID
             AND R.RoleName IN (N'Employee', N'Admin')
       )
    BEGIN
        SET @Result = 1;
    END;

    IF @RoleName = N'Employee'
       AND @EmployeeID IS NOT NULL
       AND EXISTS
       (
           SELECT 1
           FROM dbo.UserRoles AS UR
           INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
           INNER JOIN dbo.Employee AS E ON E.EmployeeID = @EmployeeID
           WHERE UR.UserID = @UserID
             AND R.RoleName = N'Employee'
             AND E.EmpStatus = N'Active'
       )
    BEGIN
        SET @Result = 1;
    END;

    IF @RoleName = N'Admin'
       AND @EmployeeID IS NOT NULL
       AND EXISTS
       (
           SELECT 1
           FROM dbo.UserRoles AS UR
           INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
           INNER JOIN dbo.Employee AS E ON E.EmployeeID = @EmployeeID
           WHERE UR.UserID = @UserID
             AND R.RoleName = N'Admin'
             AND E.EmpStatus = N'Active'
             AND E.CanAccessAdmin = 1
             AND E.JobTitle IN (N'Branch Manager', N'Vice Manager')
       )
       AND EXISTS
       (
           SELECT 1
           FROM dbo.UserRoles AS UR
           INNER JOIN dbo.Roles AS R ON R.RoleID = UR.RoleID
           WHERE UR.UserID = @UserID
             AND R.RoleName = N'Employee'
       )
    BEGIN
        SET @Result = 1;
    END;

    RETURN @Result;
END;
GO
