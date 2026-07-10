/* =========================================================
   ApplyAccessRules_HIGHADMIN_FINAL.sql
   ---------------------------------------------------------
   FINAL application access-control rules for the Bank
   Management project.

   IMPORTANT:
   - These are APPLICATION roles stored in dbo.Roles/UserRoles.
   - They are NOT SQL Server database roles.

   FINAL ROLE MODEL:
     Customer   : can use normal customer/account features.
     Employee   : normal branch employee.
     Admin      : Branch Manager or Vice Manager application role.
     HighAdmin  : central system-level manager-controller role.

   FINAL IDENTITY MODEL:
     1. Every login user must have CustomerID.
     2. A normal Customer user has CustomerID only.
     3. An Employee user has CustomerID + EmployeeID.
     4. An Admin user has CustomerID + EmployeeID and must be an
        active Branch Manager or Vice Manager with CanAccessAdmin = 1.
     5. A HighAdmin user has CustomerID but must NOT have EmployeeID.
     6. HighAdmin must also have Customer role.
     7. HighAdmin cannot be combined with Employee/Admin roles.
     8. Only one active HighAdmin user is allowed.
     9. Only one active Branch Manager is allowed per branch.

   EMPLOYEE STATUS NOTE:
   - Users.IsActive controls whether the person can log in at all.
   - Employee.EmpStatus controls employee/admin privilege effectiveness.
   - Fired/suspended employees may still keep Users.IsActive = 1
     so they can log in as Customer.

   EXECUTE AFTER:
     1) TableCreation.sql
     2) PasswordHash.sql
     3) Schema_CustomerAccessAndBranchLedger.sql
        or any script that adds Customer.IsActive / Users.IsActive

   This file intentionally replaces older conflicting triggers:
     - TR_Users_PreventDualRole
     - TR_Users_EnforceAccessType
   ========================================================= */

SET XACT_ABORT ON;
GO

------------------------------------------------------------
-- 1. Ensure required status columns exist.
------------------------------------------------------------
IF COL_LENGTH('dbo.Customer', 'IsActive') IS NULL
BEGIN
    ALTER TABLE dbo.Customer
    ADD IsActive BIT NOT NULL
        CONSTRAINT DF_Customer_IsActive DEFAULT(1)
        WITH VALUES;
END;
GO

IF COL_LENGTH('dbo.Users', 'IsActive') IS NULL
BEGIN
    ALTER TABLE dbo.Users
    ADD IsActive BIT NOT NULL
        CONSTRAINT DF_Users_IsActive DEFAULT(1)
        WITH VALUES;
END;
GO

------------------------------------------------------------
-- 2. Seed required application roles.
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = N'Customer')
    INSERT INTO dbo.Roles(RoleName) VALUES(N'Customer');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = N'Employee')
    INSERT INTO dbo.Roles(RoleName) VALUES(N'Employee');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = N'Admin')
    INSERT INTO dbo.Roles(RoleName) VALUES(N'Admin');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE RoleName = N'HighAdmin')
    INSERT INTO dbo.Roles(RoleName) VALUES(N'HighAdmin');
GO

------------------------------------------------------------
-- 3. One login per Customer and one login per Employee.
--    Employees also have CustomerID, so both rules are needed.
------------------------------------------------------------
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UQ_Users_CustomerID'
      AND object_id = OBJECT_ID(N'dbo.Users')
)
BEGIN
    CREATE UNIQUE INDEX UQ_Users_CustomerID
    ON dbo.Users(CustomerID)
    WHERE CustomerID IS NOT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'UQ_Users_EmployeeID'
      AND object_id = OBJECT_ID(N'dbo.Users')
)
BEGIN
    CREATE UNIQUE INDEX UQ_Users_EmployeeID
    ON dbo.Users(EmployeeID)
    WHERE EmployeeID IS NOT NULL;
END;
GO

------------------------------------------------------------
-- 4. Keep / recreate the one-current-branch rule.
--    This is still correct and should NOT be deleted.
------------------------------------------------------------
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_Employee_OneActiveBranch'
      AND object_id = OBJECT_ID(N'dbo.EMPB')
)
BEGIN
    CREATE UNIQUE INDEX IX_Employee_OneActiveBranch
    ON dbo.EMPB(EmployeeID)
    WHERE WorkingStatus = N'Working' AND EndDate IS NULL;
END;
GO

------------------------------------------------------------
-- 5. Drop obsolete/conflicting old triggers.
------------------------------------------------------------
IF OBJECT_ID(N'dbo.TR_Users_PreventDualRole', N'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_Users_PreventDualRole;
GO

IF OBJECT_ID(N'dbo.TR_Users_EnforceAccessType', N'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_Users_EnforceAccessType;
GO

------------------------------------------------------------
-- 6. Employee admin flag maintenance.
--
--    CanAccessAdmin is treated as manager-level privilege.
--    Only active Branch Manager / Vice Manager employees get it.
--
--    When a person is no longer manager-level, Admin role is
--    removed automatically. Users.IsActive is NOT changed here.
------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.TR_Employee_SetAdminFlag
ON dbo.Employee
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        UPDATE E
        SET CanAccessAdmin =
            CASE
                WHEN E.EmpStatus = N'Active'
                 AND E.JobTitle IN (N'Branch Manager', N'Vice Manager')
                    THEN 1
                ELSE 0
            END
        FROM dbo.Employee AS E
        INNER JOIN inserted AS I
            ON I.EmployeeID = E.EmployeeID;

        DELETE UR
        FROM dbo.UserRoles AS UR
        INNER JOIN dbo.Roles AS R
            ON R.RoleID = UR.RoleID
        INNER JOIN dbo.Users AS U
            ON U.UserID = UR.UserID
        INNER JOIN dbo.Employee AS E
            ON E.EmployeeID = U.EmployeeID
        INNER JOIN inserted AS I
            ON I.EmployeeID = E.EmployeeID
        WHERE R.RoleName = N'Admin'
          AND
          (
              E.EmpStatus <> N'Active'
              OR E.CanAccessAdmin <> 1
              OR E.JobTitle NOT IN (N'Branch Manager', N'Vice Manager')
          );
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
    END CATCH
END;
GO

------------------------------------------------------------
-- 7. Enforce user-link rules at Users level.
------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.TR_Users_EnforceUserLinks
ON dbo.Users
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        --------------------------------------------------------
        -- Every login user must have CustomerID.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            WHERE I.CustomerID IS NULL
        )
        BEGIN
            RAISERROR('Every application login user must be linked to a CustomerID.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- A login user cannot be linked to an inactive customer.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Customer AS C
                ON C.CustomerID = I.CustomerID
            WHERE C.IsActive = 0
        )
        BEGIN
            RAISERROR('A login user cannot be linked to an inactive customer.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- If this user already has HighAdmin role, it must not
        -- have EmployeeID.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.UserRoles AS UR
                ON UR.UserID = I.UserID
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE R.RoleName = N'HighAdmin'
              AND I.EmployeeID IS NOT NULL
        )
        BEGIN
            RAISERROR('HighAdmin user must not be linked to EmployeeID.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- If this user already has Employee/Admin role, it must
        -- have EmployeeID.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.UserRoles AS UR
                ON UR.UserID = I.UserID
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE R.RoleName IN (N'Employee', N'Admin')
              AND I.EmployeeID IS NULL
        )
        BEGIN
            RAISERROR('Employee/Admin users must be linked to EmployeeID.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- HighAdmin cannot be mixed with Employee/Admin.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            WHERE EXISTS
            (
                SELECT 1
                FROM dbo.UserRoles AS UR
                INNER JOIN dbo.Roles AS R
                    ON R.RoleID = UR.RoleID
                WHERE UR.UserID = I.UserID
                  AND R.RoleName = N'HighAdmin'
            )
            AND EXISTS
            (
                SELECT 1
                FROM dbo.UserRoles AS UR
                INNER JOIN dbo.Roles AS R
                    ON R.RoleID = UR.RoleID
                WHERE UR.UserID = I.UserID
                  AND R.RoleName IN (N'Employee', N'Admin')
            )
        )
        BEGIN
            RAISERROR('HighAdmin cannot be combined with Employee or Admin role.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- Only one active HighAdmin user.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            INNER JOIN dbo.Users AS U
                ON U.UserID = UR.UserID
            WHERE R.RoleName = N'HighAdmin'
              AND U.IsActive = 1
            GROUP BY R.RoleID
            HAVING COUNT(*) > 1
        )
        BEGIN
            RAISERROR('Only one active HighAdmin user is allowed.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
    END CATCH
END;
GO

------------------------------------------------------------
-- 8. Enforce role assignment rules.
------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.TR_UserRoles_EnforceAccessModel
ON dbo.UserRoles
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        --------------------------------------------------------
        -- Customer role requires CustomerID.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Users AS U
                ON U.UserID = I.UserID
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            WHERE R.RoleName = N'Customer'
              AND U.CustomerID IS NULL
        )
        BEGIN
            RAISERROR('Customer role requires CustomerID.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- Employee/Admin roles require EmployeeID.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Users AS U
                ON U.UserID = I.UserID
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            WHERE R.RoleName IN (N'Employee', N'Admin')
              AND U.EmployeeID IS NULL
        )
        BEGIN
            RAISERROR('Employee/Admin role requires EmployeeID.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- Admin role requires active manager-level employee.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Users AS U
                ON U.UserID = I.UserID
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            LEFT JOIN dbo.Employee AS E
                ON E.EmployeeID = U.EmployeeID
            WHERE R.RoleName = N'Admin'
              AND
              (
                    U.EmployeeID IS NULL
                 OR E.EmpStatus <> N'Active'
                 OR E.CanAccessAdmin <> 1
                 OR E.JobTitle NOT IN (N'Branch Manager', N'Vice Manager')
              )
        )
        BEGIN
            RAISERROR('Admin role is allowed only for active Branch Manager or Vice Manager employees.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- Employee/Admin users must also have Customer role.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            WHERE R.RoleName IN (N'Employee', N'Admin')
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.UserRoles AS UR2
                  INNER JOIN dbo.Roles AS R2
                      ON R2.RoleID = UR2.RoleID
                  WHERE UR2.UserID = I.UserID
                    AND R2.RoleName = N'Customer'
              )
        )
        BEGIN
            RAISERROR('Employee/Admin users must also have Customer role.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- HighAdmin role: CustomerID required, EmployeeID forbidden,
        -- Customer role required.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Users AS U
                ON U.UserID = I.UserID
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            WHERE R.RoleName = N'HighAdmin'
              AND (U.CustomerID IS NULL OR U.EmployeeID IS NOT NULL)
        )
        BEGIN
            RAISERROR('HighAdmin role requires CustomerID and must not have EmployeeID.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            WHERE R.RoleName = N'HighAdmin'
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.UserRoles AS UR2
                  INNER JOIN dbo.Roles AS R2
                      ON R2.RoleID = UR2.RoleID
                  WHERE UR2.UserID = I.UserID
                    AND R2.RoleName = N'Customer'
              )
        )
        BEGIN
            RAISERROR('HighAdmin user must also have Customer role.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- HighAdmin cannot be combined with Employee/Admin.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            WHERE R.RoleName = N'HighAdmin'
              AND EXISTS
              (
                  SELECT 1
                  FROM dbo.UserRoles AS UR2
                  INNER JOIN dbo.Roles AS R2
                      ON R2.RoleID = UR2.RoleID
                  WHERE UR2.UserID = I.UserID
                    AND R2.RoleName IN (N'Employee', N'Admin')
              )
        )
        BEGIN
            RAISERROR('HighAdmin cannot be combined with Employee or Admin role.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM inserted AS I
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = I.RoleID
            WHERE R.RoleName IN (N'Employee', N'Admin')
              AND EXISTS
              (
                  SELECT 1
                  FROM dbo.UserRoles AS UR2
                  INNER JOIN dbo.Roles AS R2
                      ON R2.RoleID = UR2.RoleID
                  WHERE UR2.UserID = I.UserID
                    AND R2.RoleName = N'HighAdmin'
              )
        )
        BEGIN
            RAISERROR('Employee/Admin role cannot be combined with HighAdmin.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;

        --------------------------------------------------------
        -- Only one active HighAdmin user.
        --------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            INNER JOIN dbo.Users AS U
                ON U.UserID = UR.UserID
            WHERE R.RoleName = N'HighAdmin'
              AND U.IsActive = 1
            GROUP BY R.RoleID
            HAVING COUNT(*) > 1
        )
        BEGIN
            RAISERROR('Only one active HighAdmin user is allowed.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
    END CATCH
END;
GO

------------------------------------------------------------
-- 9. Enforce one active Branch Manager per branch when EMPB
--    is inserted/updated.
------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.TR_EMPB_OneCurrentBranchManager
ON dbo.EMPB
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF EXISTS
        (
            SELECT 1
            FROM dbo.EMPB AS EB
            INNER JOIN dbo.Employee AS E
                ON E.EmployeeID = EB.EmployeeID
            WHERE EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
              AND E.EmpStatus = N'Active'
              AND E.JobTitle = N'Branch Manager'
            GROUP BY EB.BranchID
            HAVING COUNT(*) > 1
        )
        BEGIN
            RAISERROR('Only one active Branch Manager is allowed per branch.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
    END CATCH
END;
GO

------------------------------------------------------------
-- 10. Enforce one active Branch Manager per branch when
--     Employee.JobTitle or Employee.EmpStatus is changed.
------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.TR_Employee_OneCurrentBranchManager
ON dbo.Employee
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF EXISTS
        (
            SELECT 1
            FROM dbo.EMPB AS EB
            INNER JOIN dbo.Employee AS E
                ON E.EmployeeID = EB.EmployeeID
            WHERE EB.WorkingStatus = N'Working'
              AND EB.EndDate IS NULL
              AND E.EmpStatus = N'Active'
              AND E.JobTitle = N'Branch Manager'
            GROUP BY EB.BranchID
            HAVING COUNT(*) > 1
        )
        BEGIN
            RAISERROR('Only one active Branch Manager is allowed per branch.', 16, 1);
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            RETURN;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();
        RAISERROR(@Msg, @Severity, @State);
    END CATCH
END;
GO
