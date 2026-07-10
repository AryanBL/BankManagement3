/* =========================================================
   SampleData.sql
   ---------------------------------------------------------
   Coherent sample data for the FINAL schema.
   Must run AFTER all schema, rules, triggers, and procedures.
   Uses final rules:
     - 12-digit numeric account numbers
     - Every Users row has CustomerID
     - Employees also have Customer role
     - HighAdmin has CustomerID and no EmployeeID
   Default password for all sample users: Pass1234
   ========================================================= */

SET XACT_ABORT ON;
BEGIN TRANSACTION;

------------------------------------------------------------
-- Branches
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE BranchCode=N'BR001')
    INSERT INTO dbo.Branch(BranchName,BranchCode,Balance,City,Address,Phone) VALUES(N'Central Branch',N'BR001',0,N'Tehran',N'Central St.',N'02111111111');
IF NOT EXISTS (SELECT 1 FROM dbo.Branch WHERE BranchCode=N'BR002')
    INSERT INTO dbo.Branch(BranchName,BranchCode,Balance,City,Address,Phone) VALUES(N'North Branch',N'BR002',0,N'Tehran',N'North St.',N'02122222222');

------------------------------------------------------------
-- Account types
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.AccountType WHERE TypeName=N'Savings Basic')
    INSERT INTO dbo.AccountType(TypeName,Description,MinBalance,InterestRate,MonthlyFee) VALUES(N'Savings Basic',N'Basic savings account',1000,2.50,0);
IF NOT EXISTS (SELECT 1 FROM dbo.AccountType WHERE TypeName=N'Current Account')
    INSERT INTO dbo.AccountType(TypeName,Description,MinBalance,InterestRate,MonthlyFee) VALUES(N'Current Account',N'Daily banking account',500,0,0);
IF NOT EXISTS (SELECT 1 FROM dbo.AccountType WHERE TypeName=N'Business Account')
    INSERT INTO dbo.AccountType(TypeName,Description,MinBalance,InterestRate,MonthlyFee) VALUES(N'Business Account',N'Business banking account',5000,1.00,0);

------------------------------------------------------------
-- Customers
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE NationalID=N'1000000001')
    INSERT INTO dbo.Customer(FirstName,LastName,NationalID,BirthDate,Phone,Email,Address,RegistrationDate,IsActive) VALUES(N'High',N'Admin',N'1000000001','1980-01-01',N'09120000001',N'highadmin@example.com',N'HQ',CAST(GETDATE() AS DATE),1);
IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE NationalID=N'1000000002')
    INSERT INTO dbo.Customer(FirstName,LastName,NationalID,BirthDate,Phone,Email,Address,RegistrationDate,IsActive) VALUES(N'Branch',N'Manager',N'1000000002','1982-02-02',N'09120000002',N'manager1@example.com',N'Branch 1',CAST(GETDATE() AS DATE),1);
IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE NationalID=N'1000000003')
    INSERT INTO dbo.Customer(FirstName,LastName,NationalID,BirthDate,Phone,Email,Address,RegistrationDate,IsActive) VALUES(N'Vice',N'Manager',N'1000000003','1985-03-03',N'09120000003',N'vice1@example.com',N'Branch 1',CAST(GETDATE() AS DATE),1);
IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE NationalID=N'1000000004')
    INSERT INTO dbo.Customer(FirstName,LastName,NationalID,BirthDate,Phone,Email,Address,RegistrationDate,IsActive) VALUES(N'Normal',N'Employee',N'1000000004','1990-04-04',N'09120000004',N'employee1@example.com',N'Branch 1',CAST(GETDATE() AS DATE),1);
IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE NationalID=N'1000000005')
    INSERT INTO dbo.Customer(FirstName,LastName,NationalID,BirthDate,Phone,Email,Address,RegistrationDate,IsActive) VALUES(N'Customer',N'One',N'1000000005','1995-05-05',N'09120000005',N'customer1@example.com',N'Customer Address',CAST(GETDATE() AS DATE),1);

DECLARE @HighAdminCustomerID INT=(SELECT CustomerID FROM dbo.Customer WHERE NationalID=N'1000000001');
DECLARE @ManagerCustomerID INT=(SELECT CustomerID FROM dbo.Customer WHERE NationalID=N'1000000002');
DECLARE @ViceCustomerID INT=(SELECT CustomerID FROM dbo.Customer WHERE NationalID=N'1000000003');
DECLARE @EmpCustomerID INT=(SELECT CustomerID FROM dbo.Customer WHERE NationalID=N'1000000004');
DECLARE @CustCustomerID INT=(SELECT CustomerID FROM dbo.Customer WHERE NationalID=N'1000000005');
DECLARE @Branch1 INT=(SELECT BranchID FROM dbo.Branch WHERE BranchCode=N'BR001');
DECLARE @Branch2 INT=(SELECT BranchID FROM dbo.Branch WHERE BranchCode=N'BR002');

------------------------------------------------------------
-- Employees and branch assignments
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE NationalID=N'1000000002')
    INSERT INTO dbo.Employee(NationalID,FirstName,LastName,HireDate,JobTitle,Salary,Phone,Email,EmpStatus,CanAccessAdmin) VALUES(N'1000000002',N'Branch',N'Manager',CAST(GETDATE() AS DATE),N'Branch Manager',90000,N'09120000002',N'manager1@example.com',N'Active',1);
IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE NationalID=N'1000000003')
    INSERT INTO dbo.Employee(NationalID,FirstName,LastName,HireDate,JobTitle,Salary,Phone,Email,EmpStatus,CanAccessAdmin) VALUES(N'1000000003',N'Vice',N'Manager',CAST(GETDATE() AS DATE),N'Vice Manager',80000,N'09120000003',N'vice1@example.com',N'Active',1);
IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE NationalID=N'1000000004')
    INSERT INTO dbo.Employee(NationalID,FirstName,LastName,HireDate,JobTitle,Salary,Phone,Email,EmpStatus,CanAccessAdmin) VALUES(N'1000000004',N'Normal',N'Employee',CAST(GETDATE() AS DATE),N'Teller',50000,N'09120000004',N'employee1@example.com',N'Active',0);

DECLARE @ManagerEmployeeID INT=(SELECT EmployeeID FROM dbo.Employee WHERE NationalID=N'1000000002');
DECLARE @ViceEmployeeID INT=(SELECT EmployeeID FROM dbo.Employee WHERE NationalID=N'1000000003');
DECLARE @EmpEmployeeID INT=(SELECT EmployeeID FROM dbo.Employee WHERE NationalID=N'1000000004');

IF NOT EXISTS (SELECT 1 FROM dbo.EMPB WHERE EmployeeID=@ManagerEmployeeID AND WorkingStatus=N'Working' AND EndDate IS NULL)
    INSERT INTO dbo.EMPB(EmployeeID,BranchID,StartDate,EndDate,WorkingStatus) VALUES(@ManagerEmployeeID,@Branch1,CAST(GETDATE() AS DATE),NULL,N'Working');
IF NOT EXISTS (SELECT 1 FROM dbo.EMPB WHERE EmployeeID=@ViceEmployeeID AND WorkingStatus=N'Working' AND EndDate IS NULL)
    INSERT INTO dbo.EMPB(EmployeeID,BranchID,StartDate,EndDate,WorkingStatus) VALUES(@ViceEmployeeID,@Branch1,CAST(GETDATE() AS DATE),NULL,N'Working');
IF NOT EXISTS (SELECT 1 FROM dbo.EMPB WHERE EmployeeID=@EmpEmployeeID AND WorkingStatus=N'Working' AND EndDate IS NULL)
    INSERT INTO dbo.EMPB(EmployeeID,BranchID,StartDate,EndDate,WorkingStatus) VALUES(@EmpEmployeeID,@Branch1,CAST(GETDATE() AS DATE),NULL,N'Working');

------------------------------------------------------------
-- Users and roles
------------------------------------------------------------
DECLARE @CustomerRoleID INT=(SELECT RoleID FROM dbo.Roles WHERE RoleName=N'Customer');
DECLARE @EmployeeRoleID INT=(SELECT RoleID FROM dbo.Roles WHERE RoleName=N'Employee');
DECLARE @AdminRoleID INT=(SELECT RoleID FROM dbo.Roles WHERE RoleName=N'Admin');
DECLARE @HighAdminRoleID INT=(SELECT RoleID FROM dbo.Roles WHERE RoleName=N'HighAdmin');

IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE CustomerID=@HighAdminCustomerID)
    INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(N'highadmin',dbo.fn_HashPassword(N'Pass1234'),NULL,@HighAdminCustomerID,1);
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE CustomerID=@ManagerCustomerID)
    INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(N'manager1',dbo.fn_HashPassword(N'Pass1234'),@ManagerEmployeeID,@ManagerCustomerID,1);
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE CustomerID=@ViceCustomerID)
    INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(N'vice1',dbo.fn_HashPassword(N'Pass1234'),@ViceEmployeeID,@ViceCustomerID,1);
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE CustomerID=@EmpCustomerID)
    INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(N'employee1',dbo.fn_HashPassword(N'Pass1234'),@EmpEmployeeID,@EmpCustomerID,1);
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE CustomerID=@CustCustomerID)
    INSERT INTO dbo.Users(Username,PasswordHash,EmployeeID,CustomerID,IsActive) VALUES(N'customer1',dbo.fn_HashPassword(N'Pass1234'),NULL,@CustCustomerID,1);

DECLARE @HighAdminUserID INT=(SELECT UserID FROM dbo.Users WHERE CustomerID=@HighAdminCustomerID);
DECLARE @ManagerUserID INT=(SELECT UserID FROM dbo.Users WHERE CustomerID=@ManagerCustomerID);
DECLARE @ViceUserID INT=(SELECT UserID FROM dbo.Users WHERE CustomerID=@ViceCustomerID);
DECLARE @EmpUserID INT=(SELECT UserID FROM dbo.Users WHERE CustomerID=@EmpCustomerID);
DECLARE @CustUserID INT=(SELECT UserID FROM dbo.Users WHERE CustomerID=@CustCustomerID);

IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@HighAdminUserID AND RoleID=@CustomerRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@HighAdminUserID,@CustomerRoleID);
IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@HighAdminUserID AND RoleID=@HighAdminRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@HighAdminUserID,@HighAdminRoleID);

IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@ManagerUserID AND RoleID=@CustomerRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@ManagerUserID,@CustomerRoleID);
IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@ManagerUserID AND RoleID=@EmployeeRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@ManagerUserID,@EmployeeRoleID);
IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@ManagerUserID AND RoleID=@AdminRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@ManagerUserID,@AdminRoleID);

IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@ViceUserID AND RoleID=@CustomerRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@ViceUserID,@CustomerRoleID);
IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@ViceUserID AND RoleID=@EmployeeRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@ViceUserID,@EmployeeRoleID);
IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@ViceUserID AND RoleID=@AdminRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@ViceUserID,@AdminRoleID);

IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@EmpUserID AND RoleID=@CustomerRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@EmpUserID,@CustomerRoleID);
IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@EmpUserID AND RoleID=@EmployeeRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@EmpUserID,@EmployeeRoleID);

IF NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserID=@CustUserID AND RoleID=@CustomerRoleID) INSERT INTO dbo.UserRoles(UserID,RoleID) VALUES(@CustUserID,@CustomerRoleID);

------------------------------------------------------------
-- Accounts: 12 numeric digits only.
------------------------------------------------------------
DECLARE @SavingsTypeID INT=(SELECT AccountTypeID FROM dbo.AccountType WHERE TypeName=N'Savings Basic');
DECLARE @CurrentTypeID INT=(SELECT AccountTypeID FROM dbo.AccountType WHERE TypeName=N'Current Account');

IF NOT EXISTS (SELECT 1 FROM dbo.Account WHERE AccountNumber=N'000000000001')
    INSERT INTO dbo.Account(AccountNumber,CustomerID,BranchID,AccountTypeID,Balance,OpenDate,CloseDate,AccountStatus,FrozenPreviousStatus) VALUES(N'000000000001',@CustCustomerID,@Branch1,@SavingsTypeID,10000,CAST(GETDATE() AS DATE),NULL,N'Active',NULL);
IF NOT EXISTS (SELECT 1 FROM dbo.Account WHERE AccountNumber=N'000000000002')
    INSERT INTO dbo.Account(AccountNumber,CustomerID,BranchID,AccountTypeID,Balance,OpenDate,CloseDate,AccountStatus,FrozenPreviousStatus) VALUES(N'000000000002',@EmpCustomerID,@Branch1,@CurrentTypeID,8000,CAST(GETDATE() AS DATE),NULL,N'Active',NULL);
IF NOT EXISTS (SELECT 1 FROM dbo.Account WHERE AccountNumber=N'000000000003')
    INSERT INTO dbo.Account(AccountNumber,CustomerID,BranchID,AccountTypeID,Balance,OpenDate,CloseDate,AccountStatus,FrozenPreviousStatus) VALUES(N'000000000003',@ManagerCustomerID,@Branch1,@CurrentTypeID,15000,CAST(GETDATE() AS DATE),NULL,N'Active',NULL);

------------------------------------------------------------
-- One sample loan for customer1
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Loan WHERE CustomerID=@CustCustomerID AND LoanAmount=50000)
BEGIN
    INSERT INTO dbo.Loan(CustomerID,BranchID,LoanAmount,InterestRate,StartDate,EndDate,LoanStatus) VALUES(@CustCustomerID,@Branch1,50000,5,CAST(GETDATE() AS DATE),DATEADD(MONTH,12,CAST(GETDATE() AS DATE)),N'Active');
    DECLARE @LoanID INT=CONVERT(INT,SCOPE_IDENTITY());
    ;WITH Seq AS(SELECT 1 AS n UNION ALL SELECT n+1 FROM Seq WHERE n<12)
    INSERT INTO dbo.Installment(LoanID,DueDate,Amount,PaidDate,InstallmentStatus,PaymentTransactionID)
    SELECT @LoanID,DATEADD(MONTH,n,CAST(GETDATE() AS DATE)),ROUND((50000*1.05)/12,2),NULL,N'Pending',NULL FROM Seq OPTION(MAXRECURSION 100);
END;

COMMIT TRANSACTION;
GO
