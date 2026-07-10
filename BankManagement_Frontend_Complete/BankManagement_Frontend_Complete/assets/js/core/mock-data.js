(function () {
  const now = new Date();
  const iso = (days = 0) => new Date(now.getTime() + days * 86400000).toISOString();
  const users = {
    Customer: { UserID: 604, CustomerID: 497, EmployeeID: null, Username: 'customer_demo', FirstName: 'Noah', LastName: 'Bennett', EffectiveRoles: 'Customer' },
    Employee: { UserID: 88, CustomerID: 461, EmployeeID: 204, Username: 'merry.accounts', FirstName: 'Meriadoc', LastName: 'Brandybuck', EffectiveRoles: 'Customer,Employee' },
    Admin: { UserID: 31, CustomerID: 444, EmployeeID: 121, Username: 'frodo.manager', FirstName: 'Frodo', LastName: 'Baggins', EffectiveRoles: 'Customer,Employee,Admin' },
    HighAdmin: { UserID: 1, CustomerID: 436, EmployeeID: null, Username: 'highadmin', FirstName: 'Gandalf', LastName: 'Stormcrow', EffectiveRoles: 'Customer,Employee,Admin,HighAdmin' }
  };
  const accounts = [
    { AccountID: 10041, AccountNumber: '120026070041', CustomerID: 497, CustomerNationalID: '4000000004', AccountTypeID: 1, AccountTypeName: 'Savings Basic', BranchID: 1, BranchCode: 'BR-001', Balance: 24500000, AccountStatus: 'Active', BranchName: 'Central Branch', OpeningDate: iso(-210) },
    { AccountID: 10088, AccountNumber: '120026070088', CustomerID: 497, CustomerNationalID: '4000000004', AccountTypeID: 3, AccountTypeName: 'Current Account', BranchID: 2, BranchCode: 'BR-002', Balance: 8750000, AccountStatus: 'Active', BranchName: 'North Branch', OpeningDate: iso(-84) },
    { AccountID: 10102, AccountNumber: '120026070102', CustomerID: 499, CustomerNationalID: '4000000001', AccountTypeID: 2, AccountTypeName: 'Savings Premium', BranchID: 1, BranchCode: 'BR-001', Balance: 64000000, AccountStatus: 'Frozen', BranchName: 'Central Branch', OpeningDate: iso(-365) }
  ];
  const customers = [
    { CustomerID: 478, FirstName: 'Ella', LastName: 'Adams', NationalID: '4000000027', Phone: '0913000027', Email: 'ella.adams@example.com', IsActive: true },
    { CustomerID: 497, FirstName: 'Noah', LastName: 'Bennett', NationalID: '4000000004', Phone: '0913000004', Email: 'noah.bennett@example.com', IsActive: true },
    { CustomerID: 499, FirstName: 'Olivia', LastName: 'Harper', NationalID: '4000000001', Phone: '0913000001', Email: 'olivia.harper@example.com', IsActive: true },
    { CustomerID: 489, FirstName: 'Liam', LastName: 'Carter', NationalID: '4000000008', Phone: '0913000008', Email: 'liam.carter@example.com', IsActive: true },
    { CustomerID: 491, FirstName: 'Logan', LastName: 'Evans', NationalID: '4000000014', Phone: '0913000014', Email: 'logan.evans@example.com', IsActive: false }
  ];
  const employees = [
    { EmployeeID: 121, FirstName: 'Frodo', LastName: 'Baggins', JobTitle: 'Branch Manager', BranchName: 'Central Branch', Salary: 78000000, EmploymentStatus: 'Active' },
    { EmployeeID: 204, FirstName: 'Meriadoc', LastName: 'Brandybuck', JobTitle: 'Accounts Officer', BranchName: 'North Branch', Salary: 46000000, EmploymentStatus: 'Active' },
    { EmployeeID: 217, FirstName: 'Patrick', LastName: 'Star', JobTitle: 'Teller', BranchName: 'West Branch', Salary: 39000000, EmploymentStatus: 'Active' },
    { EmployeeID: 236, FirstName: 'Elrond', LastName: 'Halfelven', JobTitle: 'Compliance Officer', BranchName: 'Central Branch', Salary: 64000000, EmploymentStatus: 'Suspended' }
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
    { LoanID: 7101, CustomerName: 'Noah Bennett', LoanAmount: 120000000, InterestRate: 12, NumberOfInstallments: 24, PaidInstallments: 9, RemainingBalance: 79500000, LoanStatus: 'Active' },
    { LoanID: 7114, CustomerName: 'Ella Adams', LoanAmount: 85000000, InterestRate: 10, NumberOfInstallments: 18, PaidInstallments: 18, RemainingBalance: 0, LoanStatus: 'Completed' },
    { LoanID: 7123, CustomerName: 'Olivia Harper', LoanAmount: 200000000, InterestRate: 14, NumberOfInstallments: 36, PaidInstallments: 4, RemainingBalance: 183000000, LoanStatus: 'Overdue' }
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

  async function respond(path, options = {}) {
    await new Promise((r) => setTimeout(r, 220));
    const method = (options.method || 'GET').toUpperCase();
    if (path === '/api/health') return { success: true, message: 'Preview backend is available.', data: { databaseName: 'BankManagement', sqlLogin: 'BankAppLogin', databaseUser: 'BankAppRuntimeUser' } };
    if (path === '/api/auth/me') return { success: true, data: users[role()] };
    if (path === '/api/auth/login') return { success: true, data: { ...users.HighAdmin, sessionToken: 'preview-session-token', effectiveRoles: users.HighAdmin.EffectiveRoles } };
    if (path === '/api/auth/logout') return { success: true, message: 'Logged out.' };
    if (path.startsWith('/api/customers')) return { success: true, data: method === 'GET' ? customers : { CustomerID: 999, message: 'Preview operation completed.' } };
    if (/^\/api\/accounts\/\d+\/history/.test(path)) return { success: true, data: history };
    if (/^\/api\/accounts\/\d+/.test(path)) return { success: true, data: accounts[0] };
    if (path.startsWith('/api/accounts')) return { success: true, data: method === 'GET' ? accounts : { AccountID: 10199, AccountNumber: '120026070199', message: 'Preview operation completed.' } };
    if (path.startsWith('/api/transactions')) return { success: true, data: { TransactionID: 90125, ReadyToCompleteAt: iso(0), message: 'Preview transaction accepted.' } };
    if (/^\/api\/loans\/\d+\/status/.test(path)) return { success: true, data: [[loans[0]], [{ InstallmentID: 8101, InstallmentNumber: 1, DueDate: iso(10), Amount: 5500000, InstallmentStatus: 'Pending' }, { InstallmentID: 8102, InstallmentNumber: 2, DueDate: iso(40), Amount: 5500000, InstallmentStatus: 'Pending' }]] };
    if (path.startsWith('/api/loans')) return { success: true, data: { LoanID: 7199, message: 'Preview loan operation completed.' } };
    if (path.startsWith('/api/employees')) return { success: true, data: method === 'GET' ? employees : { EmployeeID: 299, message: 'Preview employee operation completed.' } };
    if (path.startsWith('/api/employee-transfers')) return { success: true, data: { TransferRequestID: 84, status: 'Pending', message: 'Preview transfer request submitted.' } };
    if (path.startsWith('/api/branches')) return { success: true, data: /^\/api\/branches\/\d+/.test(path) ? branches[0] : branches };
    if (path.startsWith('/api/highadmin')) return { success: true, data: { message: 'Preview HighAdmin operation completed.' } };
    if (path === '/api/reports') return { success: true, data: listReports() };
    if (path.startsWith('/api/reports/')) {
      const key = path.split('/')[3].split('?')[0];
      return { success: true, data: reportRows(key), meta: { page: 1, pageSize: 50, view: `vw_${key}` } };
    }
    return { success: true, data: [] };
  }
  window.BankMock = { respond, users, accounts, customers, employees, branches, history, pending, loans };
})();
