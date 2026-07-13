/* =========================================================
   Procedure_HighAdmin_HireManager.sql
   dbo.sp_HighAdmin_HireManager
   ---------------------------------------------------------
   PURPOSE
   - HighAdmin hires a Branch Manager or Vice Manager.
   - A valid branch assignment is mandatory.
   - Creates or reuses the person's Customer profile/login.
   - Ensures roles: Customer + Employee + Admin.

   WHY CUSTOMER IS ALSO ASSIGNED
   - The current authentication model requires every login user to
     have an active Customer profile and Customer role.
   - This also supports the staff member's personal accounts/loans.
   ========================================================= */

IF OBJECT_ID(N'dbo.sp_HighAdmin_HireManager', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_HighAdmin_HireManager;
GO

CREATE PROCEDURE dbo.sp_HighAdmin_HireManager
(
    @HighAdminUserID INT,
    @BranchID INT,
    @Username NVARCHAR(50),
    @Password NVARCHAR(4000),
    @NationalID NVARCHAR(20),
    @FirstName NVARCHAR(50),
    @LastName NVARCHAR(50),
    @BirthDate DATE,
    @HireDate DATE = NULL,
    @JobTitle NVARCHAR(100),
    @Salary DECIMAL(18,2),
    @Phone NVARCHAR(20),
    @Email NVARCHAR(100),
    @Address NVARCHAR(200) = NULL,
    @EmployeeID INT OUTPUT,
    @CustomerID INT OUTPUT,
    @UserID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @EmployeeID = NULL;
    SET @CustomerID = NULL;
    SET @UserID = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @JobTitle = LTRIM(RTRIM(@JobTitle));
        SET @Username = LTRIM(RTRIM(@Username));
        SET @NationalID = LTRIM(RTRIM(@NationalID));
        SET @FirstName = LTRIM(RTRIM(@FirstName));
        SET @LastName = LTRIM(RTRIM(@LastName));

        IF dbo.fn_UserHasEffectiveRole(@HighAdminUserID, N'HighAdmin') = 0
        BEGIN
            RAISERROR('Only an active HighAdmin can hire managers.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @BranchID IS NULL OR @BranchID <= 0
        BEGIN
            RAISERROR('A valid positive BranchID is required when hiring a Branch Manager or Vice Manager.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Branch
            WHERE BranchID = @BranchID
        )
        BEGIN
            RAISERROR('The selected branch does not exist.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @JobTitle NOT IN (N'Branch Manager', N'Vice Manager')
        BEGIN
            RAISERROR('JobTitle must be either Branch Manager or Vice Manager.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @JobTitle = N'Branch Manager'
           AND EXISTS
           (
               SELECT 1
               FROM dbo.EMPB AS EB
               INNER JOIN dbo.Employee AS E
                   ON E.EmployeeID = EB.EmployeeID
               WHERE EB.BranchID = @BranchID
                 AND EB.WorkingStatus = N'Working'
                 AND EB.EndDate IS NULL
                 AND E.EmpStatus = N'Active'
                 AND E.JobTitle = N'Branch Manager'
           )
        BEGIN
            RAISERROR('This branch already has an active Branch Manager.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @HireDate IS NULL
            SET @HireDate = CAST(GETDATE() AS DATE);

        IF @NationalID IS NULL OR @NationalID = N''
           OR @FirstName IS NULL OR @FirstName = N''
           OR @LastName IS NULL OR @LastName = N''
           OR @Username IS NULL OR @Username = N''
        BEGIN
            RAISERROR('Username, NationalID, FirstName, and LastName are required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @BirthDate IS NULL
        BEGIN
            RAISERROR('BirthDate is required.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @Salary IS NULL OR @Salary < 0
        BEGIN
            RAISERROR('Salary must be provided and cannot be negative.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @Password IS NULL OR LEN(@Password) < 6
        BEGIN
            RAISERROR('Password must be at least 6 characters.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.Employee
            WHERE NationalID = @NationalID
        )
        BEGIN
            RAISERROR('An employee with this NationalID already exists.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.Users
            WHERE Username = @Username
              AND CustomerID <> ISNULL
              (
                  (
                      SELECT CustomerID
                      FROM dbo.Customer
                      WHERE NationalID = @NationalID
                  ),
                  -1
              )
        )
        BEGIN
            RAISERROR('Username already exists.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        SELECT @CustomerID = CustomerID
        FROM dbo.Customer
        WHERE NationalID = @NationalID;

        IF @CustomerID IS NOT NULL
           AND EXISTS
           (
               SELECT 1
               FROM dbo.Customer
               WHERE CustomerID = @CustomerID
                 AND IsActive = 0
           )
        BEGIN
            RAISERROR('Matching customer exists but is inactive.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;

        IF @CustomerID IS NULL
        BEGIN
            EXEC dbo.sp_Customer_Create
                @FirstName = @FirstName,
                @LastName = @LastName,
                @NationalID = @NationalID,
                @BirthDate = @BirthDate,
                @Phone = @Phone,
                @Email = @Email,
                @Address = @Address,
                @CustomerID = @CustomerID OUTPUT,
                @CreatedByUserID = @HighAdminUserID;
        END;

        INSERT INTO dbo.Employee
        (
            NationalID,
            FirstName,
            LastName,
            HireDate,
            JobTitle,
            Salary,
            Phone,
            Email,
            EmpStatus
        )
        VALUES
        (
            @NationalID,
            @FirstName,
            @LastName,
            @HireDate,
            @JobTitle,
            @Salary,
            @Phone,
            @Email,
            N'Active'
        );

        SET @EmployeeID = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.EMPB
        (
            EmployeeID,
            BranchID,
            StartDate,
            EndDate,
            WorkingStatus
        )
        VALUES
        (
            @EmployeeID,
            @BranchID,
            @HireDate,
            NULL,
            N'Working'
        );

        SELECT @UserID = UserID
        FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
        WHERE CustomerID = @CustomerID;

        IF @UserID IS NULL
        BEGIN
            INSERT INTO dbo.Users
            (
                Username,
                PasswordHash,
                EmployeeID,
                CustomerID,
                IsActive
            )
            VALUES
            (
                @Username,
                dbo.fn_HashPassword(@Password),
                @EmployeeID,
                @CustomerID,
                1
            );

            SET @UserID = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM dbo.Users
                WHERE UserID = @UserID
                  AND EmployeeID IS NOT NULL
            )
            BEGIN
                RAISERROR('Existing customer login is already linked to another employee.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.Users
                WHERE Username = @Username
                  AND UserID <> @UserID
            )
            BEGIN
                RAISERROR('Username already exists.', 16, 1);
                ROLLBACK TRANSACTION;
                RETURN;
            END;

            UPDATE dbo.Users
            SET Username = @Username,
                PasswordHash = dbo.fn_HashPassword(@Password),
                EmployeeID = @EmployeeID,
                IsActive = 1
            WHERE UserID = @UserID;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Customer'
        )
        BEGIN
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @UserID, RoleID
            FROM dbo.Roles
            WHERE RoleName = N'Customer';
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Employee'
        )
        BEGIN
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @UserID, RoleID
            FROM dbo.Roles
            WHERE RoleName = N'Employee';
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.UserRoles AS UR
            INNER JOIN dbo.Roles AS R
                ON R.RoleID = UR.RoleID
            WHERE UR.UserID = @UserID
              AND R.RoleName = N'Admin'
        )
        BEGIN
            INSERT INTO dbo.UserRoles(UserID, RoleID)
            SELECT @UserID, RoleID
            FROM dbo.Roles
            WHERE RoleName = N'Admin';
        END;

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
            @HighAdminUserID,
            N'ManagerHired',
            N'Employee',
            @EmployeeID,
            CONCAT
            (
                N'Manager hired. JobTitle=', @JobTitle,
                N'; BranchID=', @BranchID,
                N'; UserID=', @UserID,
                N'; CustomerID=', @CustomerID
            )
        );

        COMMIT TRANSACTION;

        SELECT
            @EmployeeID AS EmployeeID,
            @CustomerID AS CustomerID,
            @UserID AS UserID,
            @JobTitle AS JobTitle,
            @BranchID AS BranchID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @Msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @Severity INT = ERROR_SEVERITY();
        DECLARE @State INT = ERROR_STATE();

        RAISERROR(@Msg, @Severity, @State);
        RETURN;
    END CATCH;
END;
GO
