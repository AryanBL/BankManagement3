(function () {
  const now = new Date();
  const iso = (days = 0) => new Date(now.getTime() + days * 86400000).toISOString();
  const users = {
    Customer: { UserID: 604, CustomerID: 497, EmployeeID: null, CurrentBranchID: null, CurrentBranchName: null, Username: 'customer_demo', FirstName: 'Noah', LastName: 'Bennett', EffectiveRoles: 'Customer' },
    Employee: { UserID: 88, CustomerID: 461, EmployeeID: 204, CurrentBranchID: 2, CurrentBranchName: 'North Branch', Username: 'merry.accounts', FirstName: 'Meriadoc', LastName: 'Brandybuck', EffectiveRoles: 'Customer,Employee' },
    Admin: { UserID: 31, CustomerID: 444, EmployeeID: 121, CurrentBranchID: 1, CurrentBranchName: 'Central Branch', Username: 'frodo.manager', FirstName: 'Frodo', LastName: 'Baggins', EffectiveRoles: 'Customer,Employee,Admin' },
    HighAdmin: { UserID: 1, CustomerID: 436, EmployeeID: null, CurrentBranchID: null, CurrentBranchName: null, Username: 'highadmin', FirstName: 'Gandalf', LastName: 'Stormcrow', EffectiveRoles: 'Customer,HighAdmin' }
  };
  const accounts = [
    { AccountID: 10041, AccountNumber: '120026070041', CustomerID: 497, CustomerFirstName: 'Noah', CustomerLastName: 'Bennett', CustomerNationalID: '4000000004', AccountTypeID: 1, AccountTypeName: 'Savings Basic', BranchID: 1, BranchCode: 'BR-001', Balance: 24500000, AccountStatus: 'Active', BranchName: 'Central Branch', OpeningDate: iso(-210) },
    { AccountID: 10088, AccountNumber: '120026070088', CustomerID: 497, CustomerFirstName: 'Noah', CustomerLastName: 'Bennett', CustomerNationalID: '4000000004', AccountTypeID: 3, AccountTypeName: 'Current Account', BranchID: 2, BranchCode: 'BR-002', Balance: 8750000, AccountStatus: 'Active', BranchName: 'North Branch', OpeningDate: iso(-84) },
    { AccountID: 10102, AccountNumber: '120026070102', CustomerID: 499, CustomerFirstName: 'Olivia', CustomerLastName: 'Harper', CustomerNationalID: '4000000001', AccountTypeID: 2, AccountTypeName: 'Savings Premium', BranchID: 1, BranchCode: 'BR-001', Balance: 64000000, AccountStatus: 'Frozen', BranchName: 'Central Branch', OpeningDate: iso(-365) },
    { AccountID: 10120, AccountNumber: '120026070120', CustomerID: 461, CustomerFirstName: 'Meriadoc', CustomerLastName: 'Brandybuck', CustomerNationalID: '3200000020', AccountTypeID: 1, AccountTypeName: 'Savings Basic', BranchID: 3, BranchCode: 'BR-003', Balance: 5100000, AccountStatus: 'Active', BranchName: 'West Branch', OpeningDate: iso(-120) },
    { AccountID: 10121, AccountNumber: '120026070121', CustomerID: 444, CustomerFirstName: 'Frodo', CustomerLastName: 'Baggins', CustomerNationalID: '3100000001', AccountTypeID: 3, AccountTypeName: 'Current Account', BranchID: 2, BranchCode: 'BR-002', Balance: 9900000, AccountStatus: 'Active', BranchName: 'North Branch', OpeningDate: iso(-250) },
    { AccountID: 10122, AccountNumber: '120026070122', CustomerID: 436, CustomerFirstName: 'Gandalf', CustomerLastName: 'Stormcrow', CustomerNationalID: '3000000001', AccountTypeID: 2, AccountTypeName: 'Savings Premium', BranchID: 1, BranchCode: 'BR-001', Balance: 15000000, AccountStatus: 'Active', BranchName: 'Central Branch', OpeningDate: iso(-480) }
  ];
  const customers = [
    { CustomerID: 478, FirstName: 'Ella', LastName: 'Adams', NationalID: '4000000027', Phone: '0913000027', Email: 'ella.adams@example.com', IsActive: true },
    { CustomerID: 497, FirstName: 'Noah', LastName: 'Bennett', NationalID: '4000000004', Phone: '0913000004', Email: 'noah.bennett@example.com', IsActive: true },
    { CustomerID: 499, FirstName: 'Olivia', LastName: 'Harper', NationalID: '4000000001', Phone: '0913000001', Email: 'olivia.harper@example.com', IsActive: true },
    { CustomerID: 489, FirstName: 'Liam', LastName: 'Carter', NationalID: '4000000008', Phone: '0913000008', Email: 'liam.carter@example.com', IsActive: true },
    { CustomerID: 491, FirstName: 'Logan', LastName: 'Evans', NationalID: '4000000014', Phone: '0913000014', Email: 'logan.evans@example.com', IsActive: false }
  ];
  const employees = [
    { EmployeeID: 121, FirstName: 'Frodo', LastName: 'Baggins', JobTitle: 'Branch Manager', BranchID: 1, CurrentBranchID: 1, BranchName: 'Central Branch', CurrentBranchName: 'Central Branch', Salary: 78000000, EmpStatus: 'Active', CanAccessAdmin: true },
    { EmployeeID: 204, FirstName: 'Meriadoc', LastName: 'Brandybuck', JobTitle: 'Accounts Officer', BranchID: 2, CurrentBranchID: 2, BranchName: 'North Branch', CurrentBranchName: 'North Branch', Salary: 46000000, EmpStatus: 'Active', CanAccessAdmin: false },
    { EmployeeID: 217, FirstName: 'Patrick', LastName: 'Star', JobTitle: 'Teller', BranchID: 3, CurrentBranchID: 3, BranchName: 'West Branch', CurrentBranchName: 'West Branch', Salary: 39000000, EmpStatus: 'Active', CanAccessAdmin: false },
    { EmployeeID: 236, FirstName: 'Elrond', LastName: 'Halfelven', JobTitle: 'Compliance Officer', BranchID: 1, CurrentBranchID: 1, BranchName: 'Central Branch', CurrentBranchName: 'Central Branch', Salary: 64000000, EmpStatus: 'OnLeave', CanAccessAdmin: false }
  ];
  const branches = [
    { BranchID: 1, BranchCode: 'BR-001', BranchName: 'Central Branch', City: 'Tehran', ManagerName: 'Frodo Baggins', EmployeeCount: 18 },
    { BranchID: 2, BranchCode: 'BR-002', BranchName: 'North Branch', City: 'Tehran', ManagerName: 'Galadriel Lothlorien', EmployeeCount: 13 },
    { BranchID: 3, BranchCode: 'BR-003', BranchName: 'West Branch', City: 'Karaj', ManagerName: 'Aragorn Elessar', EmployeeCount: 9 }
  ];
  const history = [
    { TransactionID: 90081, TransactionType: 'Deposit', Amount: 2500000, TransactionStatus: 'Completed', TransactionDate: iso(-1), Description: 'Salary deposit' },
    { TransactionID: 90080, TransactionType: 'Transfer', Amount: 780000, TransactionStatus: 'Completed', TransactionDate: iso(-2), Description: 'Utility payment' },
    { TransactionID: 90077, TransactionType: 'Withdrawal', Amount: 320000, TransactionStatus: 'Completed', TransactionDate: iso(-4), Description: 'ATM withdrawal' },
    { TransactionID: 90069, TransactionType: 'Transfer', Amount: 1200000, TransactionStatus: 'Pending', TransactionDate: iso(0), Description: 'Scheduled transfer' }
  ];
  const pending = [
    { TransactionID: 90069, TransactionType: 'Transfer', SourceAccount: '120026070041', DestinationAccount: '120026070088', Amount: 1200000, TransactionStatus: 'Pending', ReadyToCompleteAt: iso(0) },
    { TransactionID: 90072, TransactionType: 'Deposit', SourceAccount: null, DestinationAccount: '120026070102', Amount: 300000, TransactionStatus: 'Pending', ReadyToCompleteAt: iso(0) }
  ];
  const loans = [
    { LoanID: 7101, CustomerID: 497, CustomerName: 'Noah Bennett', BranchID: 1, BranchName: 'Central Branch', BranchCode: 'BR-001', LoanAmount: 120000000, InterestRate: 12, InstallmentCount: 24, PaidInstallmentCount: 9, RemainingInstallmentAmount: 79500000, LoanStatus: 'Active' },
    { LoanID: 7114, CustomerID: 478, CustomerName: 'Ella Adams', BranchID: 2, BranchName: 'North Branch', BranchCode: 'BR-002', LoanAmount: 85000000, InterestRate: 10, InstallmentCount: 18, PaidInstallmentCount: 18, RemainingInstallmentAmount: 0, LoanStatus: 'Completed' },
    { LoanID: 7123, CustomerID: 499, CustomerName: 'Olivia Harper', BranchID: 1, BranchName: 'Central Branch', BranchCode: 'BR-001', LoanAmount: 200000000, InterestRate: 14, InstallmentCount: 36, PaidInstallmentCount: 4, RemainingInstallmentAmount: 183000000, LoanStatus: 'Overdue' },
    { LoanID: 7130, CustomerID: 461, CustomerName: 'Meriadoc Brandybuck', BranchID: 3, BranchName: 'West Branch', BranchCode: 'BR-003', LoanAmount: 25000000, InterestRate: 8, InstallmentCount: 12, PaidInstallmentCount: 2, RemainingInstallmentAmount: 22500000, LoanStatus: 'Active' },
    { LoanID: 7131, CustomerID: 444, CustomerName: 'Frodo Baggins', BranchID: 2, BranchName: 'North Branch', BranchCode: 'BR-002', LoanAmount: 40000000, InterestRate: 9, InstallmentCount: 12, PaidInstallmentCount: 5, RemainingInstallmentAmount: 24400000, LoanStatus: 'Active' },
    { LoanID: 7132, CustomerID: 436, CustomerName: 'Gandalf Stormcrow', BranchID: 1, BranchName: 'Central Branch', BranchCode: 'BR-001', LoanAmount: 60000000, InterestRate: 7, InstallmentCount: 18, PaidInstallmentCount: 6, RemainingInstallmentAmount: 42800000, LoanStatus: 'Active' }
  ];

  function role() { return sessionStorage.getItem(window.BankConfig.PREVIEW_ROLE) || 'HighAdmin'; }
  function listReports() {
    const definitions = {
      'customer-basic-profile': ['Employee','Admin','HighAdmin'],
      'customer-account-summary': ['Employee','Admin','HighAdmin'],
      'account-operational-summary': ['Employee','Admin','HighAdmin'],
      'employee-directory': ['Employee','Admin','HighAdmin'],
      'pending-transactions': ['Employee','Admin','HighAdmin'],
      'loan-operational-summary': ['Employee','Admin','HighAdmin'],
      'daily-transaction-summary': ['Admin','HighAdmin'],
      'account-status-summary': ['Admin','HighAdmin'],
      'loan-overdue-summary': ['Admin','HighAdmin'],
      'highadmin-employee-branch-overview': ['HighAdmin'],
      'highadmin-branch-financial-overview': ['HighAdmin'],
      'highadmin-user-access-overview': ['HighAdmin'],
      'audit-trail': ['HighAdmin'],
      'branch-ledger': ['HighAdmin']
    };
    return Object.entries(definitions).map(([key, requiredRoles]) => ({ key, url: `/api/reports/${key}`, requiredRoles }));
  }
  function reportRows(key) {
    if (key === 'pending-transactions') return pending;
    if (key.includes('account')) return accounts;
    if (key.includes('employee')) return employees;
    if (key.includes('loan')) return loans;
    if (key === 'audit-trail') return [
      { AuditID: 3001, EventType: 'LOGIN_SUCCESS', Username: 'highadmin', EventDate: iso(0), Source: 'API', Details: 'Session issued' },
      { AuditID: 3000, EventType: 'ACCOUNT_OPENED', Username: 'customer_demo', EventDate: iso(-1), Source: 'sp_Account_Open', Details: 'Account 120026070102 created' }
    ];
    if (key === 'branch-ledger') return [
      { BranchName: 'Central Branch', EntryDate: iso(-1), EntryType: 'Credit', Amount: 2500000, Reference: 'TRX-90081' },
      { BranchName: 'North Branch', EntryDate: iso(-2), EntryType: 'Debit', Amount: 780000, Reference: 'TRX-90080' }
    ];
    if (key.includes('branch')) return branches;
    return customers;
  }

  function scopedAccounts(query) {
    const previewUser = users[role()];
    const requestedScope = String(query.get('scope') || '').toLowerCase();
    if (requestedScope === 'mine') {
      return accounts.filter((account) => Number(account.CustomerID) === Number(previewUser.CustomerID));
    }
    if (role() === 'HighAdmin') return accounts;
    if (role() === 'Employee' || role() === 'Admin') {
      return accounts.filter((account) => Number(account.BranchID) === Number(previewUser.CurrentBranchID));
    }
    return accounts.filter((account) => Number(account.CustomerID) === Number(previewUser.CustomerID));
  }

  function scopedLoans(query) {
    const previewUser = users[role()];
    const requestedScope = String(query.get('scope') || '').toLowerCase();
    if (requestedScope === 'mine') {
      return loans.filter((loan) => Number(loan.CustomerID) === Number(previewUser.CustomerID));
    }
    if (role() === 'HighAdmin') return loans;
    if (role() === 'Employee' || role() === 'Admin') {
      return loans.filter((loan) => Number(loan.BranchID) === Number(previewUser.CurrentBranchID));
    }
    return loans.filter((loan) => Number(loan.CustomerID) === Number(previewUser.CustomerID));
  }


  function scopedEmployees() {
    const previewUser = users[role()];
    if (role() === 'HighAdmin') return employees;
    if (role() === 'Admin') {
      return employees.filter((employee) => Number(employee.CurrentBranchID) === Number(previewUser.CurrentBranchID));
    }
    if (role() === 'Employee') {
      return employees.filter((employee) => Number(employee.EmployeeID) === Number(previewUser.EmployeeID));
    }
    return [];
  }

  async function respond(path, options = {}) {
    await new Promise((r) => setTimeout(r, 220));
    const method = (options.method || 'GET').toUpperCase();
    const requestUrl = new URL(path, 'http://preview.local');
    const pathname = requestUrl.pathname;
    const query = requestUrl.searchParams;

    if (pathname === '/api/health') return { success: true, message: 'Preview backend is available.', data: { databaseName: 'BankManagement', sqlLogin: 'BankAppLogin', databaseUser: 'BankAppRuntimeUser' } };
    if (pathname === '/api/auth/me') return { success: true, data: users[role()] };
    if (pathname === '/api/auth/login') return { success: true, data: { ...users.HighAdmin, sessionToken: 'preview-session-token', effectiveRoles: users.HighAdmin.EffectiveRoles } };
    if (pathname === '/api/auth/logout') return { success: true, message: 'Logged out.' };

    if (pathname.startsWith('/api/customers')) return { success: true, data: method === 'GET' ? customers : { CustomerID: 999, message: 'Preview operation completed.' } };

    if (pathname === '/api/accounts/mine') {
      const mineQuery = new URLSearchParams(query);
      mineQuery.set('scope', 'mine');
      return { success: true, data: scopedAccounts(mineQuery), meta: { accessScope: 'mine' } };
    }
    if (/^\/api\/accounts\/\d+\/history$/.test(pathname)) return { success: true, data: history };
    if (/^\/api\/accounts\/\d+$/.test(pathname)) {
      const accountID = Number(pathname.split('/')[3]);
      return { success: true, data: accounts.find((account) => Number(account.AccountID) === accountID) || null };
    }
    if (pathname === '/api/accounts') {
      return method === 'GET'
        ? { success: true, data: scopedAccounts(query), meta: { accessScope: role() === 'HighAdmin' ? 'all' : (role() === 'Customer' ? 'mine' : 'branch'), branchID: users[role()].CurrentBranchID || null } }
        : { success: true, data: { AccountID: 10199, AccountNumber: '120026070199', message: 'Preview operation completed.' } };
    }
    if (pathname.startsWith('/api/accounts/')) return { success: true, data: { message: 'Preview account operation completed.' } };

    if (pathname.startsWith('/api/transactions')) return { success: true, data: { TransactionID: 90125, ReadyToCompleteAt: iso(0), message: 'Preview transaction accepted for an owned account.' } };

    if (/^\/api\/loans\/\d+\/status$/.test(pathname)) {
      const loanID = Number(pathname.split('/')[3]);
      const loan = loans.find((row) => Number(row.LoanID) === loanID) || loans[0];
      return { success: true, data: [[loan], [{ InstallmentID: loan.LoanID * 10 + 1, InstallmentNumber: 1, DueDate: iso(10), Amount: 5500000, InstallmentStatus: 'Pending' }, { InstallmentID: loan.LoanID * 10 + 2, InstallmentNumber: 2, DueDate: iso(40), Amount: 5500000, InstallmentStatus: 'Pending' }]] };
    }
    if (pathname === '/api/loans') {
      return method === 'GET'
        ? { success: true, data: scopedLoans(query), meta: { accessScope: query.get('scope') === 'mine' || role() === 'Customer' ? 'mine' : (role() === 'HighAdmin' ? 'all' : 'branch'), branchID: role() === 'Employee' || role() === 'Admin' ? users[role()].CurrentBranchID : null } }
        : { success: true, data: { LoanID: 7199, message: 'Preview loan operation completed.' } };
    }
    if (pathname.startsWith('/api/loans/')) return { success: true, data: { message: 'Preview loan operation completed.' } };

    if (/^\/api\/employees\/\d+\/branch-history$/.test(pathname)) {
      const employeeID = Number(pathname.split('/')[3]);
      const employee = scopedEmployees().find((row) => Number(row.EmployeeID) === employeeID);
      return { success: true, data: employee ? [{ EMPBID: employeeID * 10, EmployeeID: employeeID, BranchID: employee.CurrentBranchID, BranchName: employee.CurrentBranchName, StartDate: iso(-180), EndDate: null, WorkingStatus: 'Working', IsCurrentAssignment: 1 }] : [] };
    }
    if (/^\/api\/employees\/\d+$/.test(pathname) && method === 'GET') {
      const employeeID = Number(pathname.split('/')[3]);
      const employee = scopedEmployees().find((row) => Number(row.EmployeeID) === employeeID);
      return { success: true, data: employee ? [employee] : [] };
    }
    if (pathname === '/api/employees' && method === 'GET') return { success: true, data: scopedEmployees() };
    if (pathname.startsWith('/api/employees')) return { success: true, data: { EmployeeID: 299, message: 'Preview employee operation completed.' } };
    if (pathname.startsWith('/api/employee-transfers')) return { success: true, data: { TransferRequestID: 84, status: 'Pending', message: 'Preview transfer request submitted.' } };
    if (pathname.startsWith('/api/branches')) return { success: true, data: /^\/api\/branches\/\d+$/.test(pathname) ? branches[0] : branches };
    if (pathname.startsWith('/api/highadmin')) return { success: true, data: { message: 'Preview HighAdmin operation completed.' } };
    if (pathname === '/api/reports') return { success: true, data: listReports() };
    if (pathname.startsWith('/api/reports/')) {
      const key = pathname.split('/')[3];
      return { success: true, data: reportRows(key), meta: { page: 1, pageSize: 50, view: `vw_${key}` } };
    }
    return { success: true, data: [] };
  }
  window.BankMock = { respond, users, accounts, customers, employees, branches, history, pending, loans };
})();
