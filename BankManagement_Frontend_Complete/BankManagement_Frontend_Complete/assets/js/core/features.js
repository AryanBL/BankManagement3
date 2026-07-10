(function () {
  const UI = () => window.BankUI;
  const API = () => window.BankAPI;
  const icon = (...args) => window.BankIcons.icon(...args);

  function rows(payload) {
    const data = payload?.data;
    if (Array.isArray(data) && !data.some(Array.isArray)) return data;
    if (data && !Array.isArray(data)) return [data];
    return [];
  }

  function recordsets(payload) {
    const data = payload?.data;
    if (Array.isArray(data) && data.some(Array.isArray)) return data.filter(Array.isArray);
    return [rows(payload)];
  }

  function card(title, content, tools = '', className = '') {
    return `<article class="card ${className}"><header class="card-header"><h3>${UI().escapeHtml(title)}</h3>${tools}</header><div class="card-body">${content}</div></article>`;
  }

  function actionButton(action, label, iconName = 'plus', className = 'btn-primary', attributes = '') {
    return `<button class="btn ${className}" type="button" data-action="${action}" ${attributes}>${icon(iconName, 17)} ${UI().escapeHtml(label)}</button>`;
  }

  function smallAction(action, label, iconName, attributes = '', className = 'btn-secondary') {
    return `<button class="btn btn-sm ${className}" type="button" data-action="${action}" ${attributes}>${icon(iconName, 14)} ${UI().escapeHtml(label)}</button>`;
  }

  function countStatus(list, pattern) {
    return list.filter((row) => pattern.test(String(
      row.AccountStatus || row.TransactionStatus || row.LoanStatus || row.EmpStatus ||
      row.EmploymentStatus || row.WorkingStatus || row.IsActive || ''
    ))).length;
  }

  function encodeRow(row) {
    return encodeURIComponent(JSON.stringify(row || {}));
  }

  function decodeRow(value) {
    try { return JSON.parse(decodeURIComponent(value || '')); }
    catch (_) { return {}; }
  }

  function roleAtLeast(state, minimumRole) {
    const hierarchy = window.BankConfig.ROLE_HIERARCHY;
    return hierarchy.indexOf(state.config.role) >= hierarchy.indexOf(minimumRole);
  }

  function cleanObject(object) {
    return Object.fromEntries(Object.entries(object || {}).filter(([, value]) => value !== '' && value !== undefined && value !== null));
  }

  async function safeGet(path, params) {
    try { return await API().get(path, params); }
    catch (_) { return { data: [] }; }
  }

  async function cached(state, key, loader) {
    if (state.cache[key]) return state.cache[key];
    const value = await loader();
    state.cache[key] = value;
    return value;
  }

  function numberField(name, label, required = true, value = '', help = '') {
    return { name, label, type: 'number', required, value, min: 0, step: 1, help };
  }

  function moneyField(name, label, required = true, value = '', help = '') {
    return { name, label, type: 'number', required, value, min: 0, step: '0.01', help };
  }

  function selectField(name, label, options, required = true, value = '', help = '') {
    return { name, label, type: 'select', options, required, value, help };
  }

  function selectOrNumber(name, label, options, required = true, value = '', help = '') {
    return {
      ...numberField(name, label, required, value, help),
      min: 1,
      suggestions: Array.isArray(options) ? options : []
    };
  }

  function option(value, label) {
    return { value, label };
  }

  function uniqueOptions(items, valueKey, labelBuilder) {
    const seen = new Set();
    return items.reduce((result, item) => {
      const value = item?.[valueKey];
      if (value === undefined || value === null || value === '' || seen.has(String(value))) return result;
      seen.add(String(value));
      result.push(option(value, labelBuilder(item)));
      return result;
    }, []);
  }

  async function getAccounts(state, includeClosed = true) {
    return cached(state, `accounts.${includeClosed}`, async () => rows(await API().get('/api/accounts', includeClosed ? { includeClosed: true } : undefined)));
  }

  async function getBranches(state) {
    return cached(state, 'branches', async () => rows(await API().get('/api/branches')));
  }

  async function getCustomers(state) {
    return cached(state, 'customers', async () => rows(await API().get('/api/customers', { includeInactive: true })));
  }

  async function getEmployees(state) {
    return cached(state, 'employees', async () => rows(await API().get('/api/employees', { includeTerminated: true, searchBranchHistory: true })));
  }

  async function accountOptions(state, includeClosed = false) {
    const accounts = await getAccounts(state, includeClosed);
    return uniqueOptions(accounts, 'AccountID', (account) => {
      const number = account.AccountNumber || `Account ${account.AccountID}`;
      const owner = [account.CustomerFirstName, account.CustomerLastName].filter(Boolean).join(' ')
        || account.CustomerName || account.CustomerNationalID || '';
      const balance = account.Balance !== undefined ? ` · ${UI().formatMoney(account.Balance)}` : '';
      const status = account.AccountStatus ? ` · ${account.AccountStatus}` : '';
      return `${number}${owner ? ` · ${owner}` : ''}${balance}${status}`;
    });
  }

  async function branchOptions(state) {
    const branches = await getBranches(state);
    return uniqueOptions(branches, 'BranchID', (branch) => `${branch.BranchCode || branch.BranchID} · ${branch.BranchName || 'Branch'}`);
  }

  async function customerOptions(state) {
    const customers = await getCustomers(state);
    return uniqueOptions(customers, 'CustomerID', (customer) => {
      const name = `${customer.FirstName || ''} ${customer.LastName || ''}`.trim();
      return `${customer.CustomerID} · ${name || 'Customer'}${customer.NationalID ? ` · ${customer.NationalID}` : ''}`;
    });
  }

  async function employeeOptions(state) {
    const employees = await getEmployees(state);
    return uniqueOptions(employees, 'EmployeeID', (employee) => {
      const name = `${employee.FirstName || ''} ${employee.LastName || ''}`.trim();
      return `${employee.EmployeeID} · ${name || 'Employee'}${employee.JobTitle ? ` · ${employee.JobTitle}` : ''}`;
    });
  }

  async function accountTypeOptions(state) {
    const accounts = await getAccounts(state, true);
    return uniqueOptions(accounts, 'AccountTypeID', (account) => `${account.AccountTypeID} · ${account.AccountTypeName || 'Account type'}`);
  }

  function readActivity() {
    try { return JSON.parse(localStorage.getItem(window.BankConfig.STORAGE_ACTIVITY) || '[]'); }
    catch (_) { return []; }
  }

  function writeActivity(entries) {
    localStorage.setItem(window.BankConfig.STORAGE_ACTIVITY, JSON.stringify(entries.slice(0, 50)));
  }

  function logActivity(state, title, details = {}) {
    const entry = {
      date: new Date().toISOString(),
      role: state.config.role,
      username: state.user?.Username || state.user?.username || '',
      title,
      ...details
    };
    writeActivity([entry, ...readActivity()]);
  }

  function renderActivity(limit = 12) {
    const items = readActivity().slice(0, limit);
    if (!items.length) return UI().emptyState('No local workflow activity', 'Actions completed through this browser will be listed here.');
    return UI().renderTable(items, { hide: ['role', 'username'], maxColumns: 6 });
  }

  async function success(state, refresh, message, activityTitle = message, activityDetails = {}) {
    UI().toast(message, 'success');
    logActivity(state, activityTitle, activityDetails);
    state.cache = {};
    if (refresh) await refresh();
  }

  function showPayload(title, payload, titles) {
    const sets = recordsets(payload);
    UI().openModal({
      title,
      size: 'lg',
      content: UI().renderRecordsets(sets, { titles })
    });
  }

  function filterTools(filterAction, clearAction, hasFilters) {
    return `${actionButton(filterAction, 'Filters', 'filter', 'btn-secondary')} ${hasFilters ? actionButton(clearAction, 'Clear filters', 'close', 'btn-secondary') : ''} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`;
  }

  const sections = {
    customerOverview: {
      actions: () => `${actionButton('open-account', 'Open new account', 'plus')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async (state) => {
        const accounts = rows(await API().get('/api/accounts'));
        const history = [];
        for (const account of accounts.slice(0, 4)) {
          const payload = await safeGet(`/api/accounts/${account.AccountID}/history`);
          rows(payload).forEach((transaction) => history.push({ ...transaction, AccountNumber: account.AccountNumber }));
        }
        history.sort((a, b) => new Date(b.TransactionDate || b.CreatedAt || 0) - new Date(a.TransactionDate || a.CreatedAt || 0));
        return { accounts, history };
      },
      render: ({ accounts, history }) => {
        const totalBalance = accounts.reduce((sum, account) => sum + Number(account.Balance || 0), 0);
        const pending = history.filter((transaction) => /pending/i.test(transaction.TransactionStatus || '')).length;
        const accountCards = accounts.length
          ? `<div class="content-grid">${accounts.slice(0, 4).map((account) => `<div class="span-6"><div class="account-card card"><div class="account-label">${UI().escapeHtml(account.AccountTypeName || 'Bank account')}</div><div class="account-balance">${UI().formatMoney(account.Balance || 0)}</div><div class="account-number">${UI().escapeHtml(account.AccountNumber || '')}</div><div class="account-meta"><span>${UI().escapeHtml(account.BranchName || account.BranchCode || '')}</span><span>${UI().statusBadge(account.AccountStatus || 'Active')}</span></div><div class="form-actions" style="justify-content:flex-start"><button class="btn btn-sm btn-secondary" data-action="view-account" data-id="${account.AccountID}">${icon('eye', 14)} Details</button><button class="btn btn-sm btn-secondary" data-action="account-history" data-id="${account.AccountID}">${icon('reports', 14)} History</button></div></div></div>`).join('')}</div>`
          : UI().emptyState('No account yet', 'Open your first account to begin using personal banking services.');
        return `<div class="stat-grid">
          ${UI().statCard('Total balance', UI().formatMoney(totalBalance), `${accounts.length} linked account${accounts.length === 1 ? '' : 's'}`, 'wallet')}
          ${UI().statCard('Active accounts', countStatus(accounts, /active/i), 'Available for transactions', 'card', 'var(--blue-500)', 'rgba(59,130,246,.12)')}
          ${UI().statCard('Pending activity', pending, 'Awaiting completion', 'clock', 'var(--amber-500)', 'rgba(245,158,11,.14)')}
          ${UI().statCard('Session security', 'Protected', 'Bearer token validated by SQL Server', 'shield', 'var(--violet-500)', 'rgba(139,92,246,.12)')}
        </div>
        <div class="dashboard-grid">
          ${card('My accounts', accountCards, `<button class="btn btn-sm btn-secondary" data-section-target="accounts">View all ${icon('arrow', 14)}</button>`)}
          ${card('Quick actions', `<div class="quick-actions"><button class="quick-action" data-action="transfer">${icon('transfer', 21)}<strong>Transfer money</strong><span>Send funds from one of your accounts</span></button><button class="quick-action" data-action="withdraw">${icon('money', 21)}<strong>Withdraw</strong><span>Create a withdrawal transaction</span></button><button class="quick-action" data-action="lookup-loan">${icon('loan', 21)}<strong>Loan status</strong><span>Review installments and outstanding balance</span></button><button class="quick-action" data-section-target="profile">${icon('user', 21)}<strong>My profile</strong><span>Review identity and effective roles</span></button></div>`)}
        </div>
        <div class="section-spacer">${card('Recent activity', UI().renderTable(history.slice(0, 10), { hide: ['Description'], maxColumns: 8 }), `<button class="btn btn-sm btn-secondary" data-section-target="transactions">Full activity ${icon('arrow', 14)}</button>`)}</div>`;
      }
    },

    customerAccounts: {
      actions: () => `${actionButton('open-account', 'Open account', 'plus')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => rows(await API().get('/api/accounts')),
      render: (accounts) => card('Account portfolio', UI().renderTable(accounts, {
        hide: ['CustomerID'],
        actions: (account) => `${smallAction('view-account', 'Details', 'eye', `data-id="${account.AccountID}"`)}${smallAction('account-history', 'History', 'reports', `data-id="${account.AccountID}"`)}`
      }))
    },

    customerTransactions: {
      actions: () => `${actionButton('transfer', 'New transfer', 'transfer')} ${actionButton('withdraw', 'Withdraw', 'money', 'btn-secondary')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => {
        const accounts = rows(await API().get('/api/accounts'));
        const history = [];
        for (const account of accounts) {
          const payload = await safeGet(`/api/accounts/${account.AccountID}/history`);
          rows(payload).forEach((transaction) => history.push({ ...transaction, AccountNumber: account.AccountNumber }));
        }
        history.sort((a, b) => new Date(b.TransactionDate || b.CreatedAt || 0) - new Date(a.TransactionDate || a.CreatedAt || 0));
        return { accounts, history };
      },
      render: ({ accounts, history }) => `<div class="content-grid"><div class="span-8">${card('Transaction history', UI().renderTable(history, { hide: ['Description'], maxColumns: 10 }))}</div><div class="span-4">${card('Account balances', accounts.map((account) => `<div class="account-mini"><strong>${UI().escapeHtml(account.AccountNumber || '')}</strong><span>${UI().formatMoney(account.Balance || 0)}</span>${UI().statusBadge(account.AccountStatus || 'Active')}</div>`).join('') || UI().emptyState('No accounts', 'No account balance is available.'))}${card('Processing rule', '<div class="alert alert-info">New financial operations can be created as <strong>Pending</strong>. The backend and SQL Server finalizer apply them only when their completion time is reached.</div>', '', 'section-spacer')}</div></div>`
    },

    customerLoans: {
      actions: () => `${actionButton('lookup-loan', 'Check loan status', 'search')} ${actionButton('pay-installment', 'Pay installment', 'money', 'btn-secondary')}`,
      load: async () => null,
      render: () => `<div class="content-grid"><div class="span-7">${card('Loan status centre', `<div class="empty-state"><div class="empty-icon">${icon('loan', 26)}</div><strong>Find a loan by ID</strong><div>The backend applies customer ownership rules before returning the loan and its installment schedule.</div><div class="form-actions" style="justify-content:center">${actionButton('lookup-loan', 'Find loan', 'search')}</div></div>`)}</div><div class="span-5">${card('Installment payment', `<div class="alert alert-info">Provide an installment ID and one of your source account IDs. The payment creates a transaction that can remain pending until its ready time.</div><div class="form-actions">${actionButton('pay-installment', 'Pay installment', 'money')}</div>`)}</div></div>`
    },

    profile: {
      actions: () => `${actionButton('api-settings', 'Backend connection', 'plug', 'btn-secondary')} ${actionButton('logout', 'Logout', 'logout', 'btn-danger')}`,
      load: async () => (await API().get('/api/auth/me')).data,
      render: (user) => {
        const roles = window.BankSession.normalizeRoles(user);
        return `<div class="content-grid"><div class="span-7">${card('Identity and access', UI().keyValue({
          FullName: `${user.FirstName || ''} ${user.LastName || ''}`.trim() || '—',
          Username: user.Username || '—',
          UserID: user.UserID,
          CustomerID: user.CustomerID,
          EmployeeID: user.EmployeeID,
          EffectiveRoles: roles.join(', ')
        }))}</div><div class="span-5">${card('Session security', `<div class="alert alert-info"><strong>Database-backed bearer session</strong><br>The browser stores the session token and sends it in the Authorization header. The backend validates the token and effective role before each protected request.</div><div class="connection-summary"><span>Frontend</span><strong>${UI().escapeHtml(location.origin)}</strong><span>Backend</span><strong>${UI().escapeHtml(window.BankConfig.getApiBaseUrl())}</strong></div><div class="form-actions">${actionButton('logout', 'End current session', 'logout', 'btn-danger')}</div>`)}</div></div>`;
      }
    },

    staffOverview: {
      actions: () => actionButton('refresh-section', 'Refresh dashboard', 'refresh', 'btn-secondary'),
      load: async (state) => {
        const [customersPayload, accountsPayload, branchesPayload, employeesPayload, pendingPayload, loansPayload] = await Promise.all([
          safeGet('/api/customers'),
          safeGet('/api/accounts'),
          safeGet('/api/branches'),
          safeGet('/api/employees'),
          safeGet('/api/reports/pending-transactions', { page: 1, pageSize: 8 }),
          safeGet('/api/reports/loan-operational-summary', { page: 1, pageSize: 8 })
        ]);
        return {
          role: state.config.role,
          customers: rows(customersPayload),
          accounts: rows(accountsPayload),
          branches: rows(branchesPayload),
          employees: rows(employeesPayload),
          pending: rows(pendingPayload),
          loans: rows(loansPayload)
        };
      },
      render: (data) => `<div class="stat-grid">
        ${UI().statCard('Customers', data.customers.length, 'Visible in your database scope', 'users')}
        ${UI().statCard('Accounts', data.accounts.length, `${countStatus(data.accounts, /active/i)} active`, 'card', 'var(--blue-500)', 'rgba(59,130,246,.12)')}
        ${UI().statCard('Pending transactions', data.pending.length, 'Awaiting finalization', 'clock', 'var(--amber-500)', 'rgba(245,158,11,.14)')}
        ${UI().statCard('Loans in report', data.loans.length, `${countStatus(data.loans, /active/i)} active`, 'loan', 'var(--violet-500)', 'rgba(139,92,246,.12)')}
      </div>
      <div class="dashboard-grid">
        ${card('Pending transaction queue', UI().renderTable(data.pending.slice(0, 8), { hide: ['Description'], maxColumns: 8 }), `<button class="btn btn-sm btn-secondary" data-action="view-report" data-report="pending-transactions">Open report ${icon('arrow', 14)}</button>`)}
        ${card('Operations shortcuts', `<div class="quick-actions"><button class="quick-action" data-action="create-customer">${icon('userPlus', 21)}<strong>New customer</strong><span>Register a customer profile</span></button><button class="quick-action" data-action="deposit">${icon('money', 21)}<strong>Deposit</strong><span>Create a deposit transaction</span></button><button class="quick-action" data-action="create-loan">${icon('loan', 21)}<strong>New loan</strong><span>Create an installment schedule</span></button><button class="quick-action" data-section-target="reports">${icon('reports', 21)}<strong>Reports</strong><span>Open protected SQL views</span></button></div>`)}
      </div>
      <div class="section-spacer">${card('Branch network', UI().renderTable(data.branches, { hide: ['Address'], maxColumns: 8 }))}</div>`
    },

    customers: {
      actions: (state) => `${actionButton('create-customer', 'Add customer', 'userPlus')} ${filterTools('customer-filters', 'clear-customer-filters', Boolean(Object.keys(state.filters.customers || {}).length))}`,
      load: async (state) => {
        const filters = cleanObject(state.filters.customers || {});
        return { filters, customers: rows(await API().get('/api/customers', filters)) };
      },
      render: ({ filters, customers }) => `${UI().filterSummary(filters)}${card('Customer directory', UI().renderTable(customers, {
        hide: ['Address', 'BirthDate', 'RegistrationDate'],
        actions: (customer) => `${smallAction('edit-customer', 'Edit', 'edit', `data-row="${encodeRow(customer)}"`)}${smallAction('delete-customer', 'Deactivate', 'trash', `data-id="${customer.CustomerID}" data-name="${UI().escapeHtml(`${customer.FirstName || ''} ${customer.LastName || ''}`)}"`, 'btn-danger')}`
      }))}`
    },

    staffAccounts: {
      actions: (state) => filterTools('account-filters', 'clear-account-filters', Boolean(Object.keys(state.filters.accounts || {}).length)),
      load: async (state) => {
        const filters = { includeClosed: true, ...cleanObject(state.filters.accounts || {}) };
        return { filters, accounts: rows(await API().get('/api/accounts', filters)) };
      },
      render: ({ filters, accounts }, state) => `${UI().filterSummary(filters)}${card('Account operations', UI().renderTable(accounts, {
        hide: ['OpeningDate', 'CustomerID'],
        maxColumns: 11,
        actions: (account) => `${smallAction('view-account', 'View', 'eye', `data-id="${account.AccountID}"`)}${smallAction('account-history', 'History', 'reports', `data-id="${account.AccountID}"`)}${smallAction('account-more', 'Manage', 'settings', `data-row="${encodeRow(account)}" data-role="${state.config.role}"`)}`
      }))}`
    },

    staffTransactions: {
      actions: (state) => `${actionButton('deposit', 'Deposit', 'plus')} ${actionButton('withdraw', 'Withdraw', 'money', 'btn-secondary')} ${actionButton('transfer', 'Transfer', 'transfer', 'btn-secondary')} ${roleAtLeast(state, 'Admin') ? actionButton('process-pending', 'Process ready batch', 'refresh', 'btn-secondary') : ''}`,
      load: async () => ({ pending: rows(await safeGet('/api/reports/pending-transactions', { page: 1, pageSize: 100 })) }),
      render: ({ pending }, state) => `<div class="content-grid"><div class="span-8">${card('Pending transactions', UI().renderTable(pending, {
        maxColumns: 10,
        actions: (transaction) => `${smallAction('finalize-transaction', 'Finalize', 'check', `data-id="${transaction.TransactionID}"`)}${smallAction('reverse-transaction', 'Reverse', 'refresh', `data-id="${transaction.TransactionID}"`, 'btn-danger')}`
      }))}</div><div class="span-4">${card('Transaction controls', `<div class="alert alert-info">The database sets <strong>ReadyToCompleteAt</strong> based on transaction amount. Finalization changes balances only after the transaction is eligible.</div>${roleAtLeast(state, 'Admin') ? `<div class="form-actions">${actionButton('process-pending', 'Process ready batch', 'refresh')}</div>` : '<div class="alert alert-warning section-spacer">Only Admin and HighAdmin can run the batch processor.</div>'}`)}</div></div>`
    },

    staffLoans: {
      actions: (state) => `${actionButton('create-loan', 'Create loan', 'plus')} ${actionButton('lookup-loan', 'Find loan', 'search', 'btn-secondary')} ${actionButton('pay-installment', 'Pay installment', 'money', 'btn-secondary')} ${roleAtLeast(state, 'Admin') ? actionButton('process-overdue', 'Process overdue', 'clock', 'btn-secondary') : ''}`,
      load: async () => ({ loans: rows(await safeGet('/api/reports/loan-operational-summary', { page: 1, pageSize: 100 })) }),
      render: ({ loans }) => card('Loan operations', UI().renderTable(loans, {
        hide: ['StartDate'],
        maxColumns: 12,
        actions: (loan) => smallAction('lookup-loan', 'Status', 'eye', `data-id="${loan.LoanID}"`)
      }))
    },

    branches: {
      actions: () => actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary'),
      load: async () => rows(await API().get('/api/branches')),
      render: (branches) => card('Branch network', UI().renderTable(branches, {
        maxColumns: 10,
        actions: (branch) => smallAction('view-branch', 'Details', 'eye', `data-id="${branch.BranchID}"`)
      }))
    },

    employees: {
      actions: (state) => `${roleAtLeast(state, 'Admin') ? actionButton('hire-employee', 'Hire employee', 'userPlus') : ''} ${filterTools('employee-filters', 'clear-employee-filters', Boolean(Object.keys(state.filters.employees || {}).length))}`,
      load: async (state) => {
        const filters = { includeTerminated: true, ...cleanObject(state.filters.employees || {}) };
        return { filters, employees: rows(await API().get('/api/employees', filters)) };
      },
      render: ({ filters, employees }, state) => `${UI().filterSummary(filters)}${card('Employee directory', UI().renderTable(employees, {
        hide: ['Phone', 'Email', 'HireDate'],
        maxColumns: 11,
        actions: (employee) => `${smallAction('employee-details', 'View', 'eye', `data-id="${employee.EmployeeID}"`)}${roleAtLeast(state, 'Admin') ? `${smallAction('change-job', 'Job title', 'briefcase', `data-id="${employee.EmployeeID}"`)}${smallAction('employee-more', 'Manage', 'settings', `data-row="${encodeRow(employee)}"`)}` : ''}`
      }))}`
    },

    transfers: {
      actions: (state) => `${actionButton(state.config.role === 'Employee' ? 'request-transfer-self' : 'request-transfer-manager', 'New transfer request', 'transfer')} ${roleAtLeast(state, 'Admin') ? actionButton('transfer-decision', 'Record decision', 'check', 'btn-secondary') : ''}`,
      load: async () => ({ activity: readActivity().filter((entry) => /transfer/i.test(entry.title || '')).slice(0, 20) }),
      render: ({ activity }, state) => `<div class="content-grid"><div class="span-7">${card('Employee branch transfer workflow', `<div class="workflow-steps"><div><span>1</span><strong>Request</strong><small>Employee or manager submits destination branch.</small></div><div><span>2</span><strong>Current manager</strong><small>The current branch manager approves or rejects.</small></div><div><span>3</span><strong>Destination manager</strong><small>The destination manager makes the final decision.</small></div></div><div class="alert alert-info section-spacer">The current backend does not expose a transfer-request listing endpoint. Newly created IDs are displayed after submission and recorded locally in this browser.</div><div class="form-actions" style="justify-content:flex-start">${actionButton(state.config.role === 'Employee' ? 'request-transfer-self' : 'request-transfer-manager', 'Create request', 'transfer')}${roleAtLeast(state, 'Admin') ? actionButton('transfer-decision', 'Record decision', 'check', 'btn-secondary') : ''}</div>`)}</div><div class="span-5">${card('Recent browser activity', activity.length ? UI().renderTable(activity, { hide: ['role', 'username'], maxColumns: 5 }) : UI().emptyState('No transfer actions yet', 'Transfer requests and decisions completed in this browser will appear here.'))}</div></div>`
    },

    reports: {
      actions: () => actionButton('refresh-section', 'Refresh catalogue', 'refresh', 'btn-secondary'),
      load: async (state) => {
        const reports = rows(await API().get('/api/reports'));
        const roles = window.BankSession.normalizeRoles(state.user);
        return reports.filter((report) => (report.requiredRoles || []).some((role) => roles.includes(role)));
      },
      render: (reports) => `<div class="content-grid">${reports.map((report) => `<div class="span-4"><article class="card report-card"><div class="card-body"><div class="stat-icon">${icon(report.key.includes('audit') ? 'shield' : 'reports', 21)}</div><h3>${UI().escapeHtml(UI().humanize(report.key))}</h3><p class="muted">Protected SQL Server view. Required role: ${UI().escapeHtml((report.requiredRoles || []).join(' or '))}.</p><div class="form-actions" style="justify-content:flex-start"><button class="btn btn-sm btn-primary" data-action="view-report" data-report="${report.key}">Open report</button></div></div></article></div>`).join('') || UI().emptyState('No reports available', 'The current role has no registered reports.')}</div>`
    },

    maintenance: {
      actions: () => actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary'),
      load: async () => null,
      render: () => `<div class="content-grid"><div class="span-4">${card('Transaction maintenance', `<p class="muted">Finalize all pending transactions whose ready time has been reached.</p>${actionButton('process-pending', 'Process pending batch', 'refresh')}`)}</div><div class="span-4">${card('Loan maintenance', `<p class="muted">Update overdue installments and associated loan states.</p>${actionButton('process-overdue', 'Process overdue installments', 'clock')}`)}</div><div class="span-4">${card('Account maintenance', `<p class="muted">Apply monthly interest or mark long-inactive accounts dormant.</p><div class="maintenance-buttons">${actionButton('apply-interest', 'Apply monthly interest', 'money')}${actionButton('dormant-sweep', 'Dormant sweep', 'clock', 'btn-secondary')}</div>`)}</div></div><div class="section-spacer">${card('Safety notice', '<div class="alert alert-warning"><strong>These are broad database operations.</strong><br>Run them only when the corresponding scheduled process is intended. Results are recorded by the backend and can affect many records.</div>')}</div>`
    },

    executiveOverview: {
      actions: () => `${actionButton('view-report', 'Branch financial report', 'reports', 'btn-secondary', 'data-report="highadmin-branch-financial-overview"')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => {
        const [branchesPayload, employeesPayload, customersPayload, accountsPayload, financialPayload] = await Promise.all([
          safeGet('/api/branches'),
          safeGet('/api/employees', { includeTerminated: true }),
          safeGet('/api/customers', { includeInactive: true }),
          safeGet('/api/accounts', { includeClosed: true }),
          safeGet('/api/reports/highadmin-branch-financial-overview', { page: 1, pageSize: 30 })
        ]);
        return {
          branches: rows(branchesPayload),
          employees: rows(employeesPayload),
          customers: rows(customersPayload),
          accounts: rows(accountsPayload),
          financial: rows(financialPayload)
        };
      },
      render: (data) => `<div class="stat-grid">
        ${UI().statCard('Branch network', data.branches.length, 'Operating units', 'building')}
        ${UI().statCard('Workforce', data.employees.length, `${countStatus(data.employees, /active|working/i)} active`, 'users', 'var(--blue-500)', 'rgba(59,130,246,.12)')}
        ${UI().statCard('Customer base', data.customers.length, 'Registered customers', 'userPlus', 'var(--violet-500)', 'rgba(139,92,246,.12)')}
        ${UI().statCard('Managed accounts', data.accounts.length, `${countStatus(data.accounts, /active/i)} active`, 'wallet', 'var(--gold-500)', 'rgba(215,168,79,.15)')}
      </div><div class="dashboard-grid">${card('Branch financial overview', UI().renderTable(data.financial, { maxColumns: 10 }))}${card('Governance shortcuts', `<div class="quick-actions"><button class="quick-action" data-action="hire-manager">${icon('userPlus', 21)}<strong>Hire manager</strong><span>Create manager, customer, and user records</span></button><button class="quick-action" data-action="replace-manager">${icon('transfer', 21)}<strong>Replace manager</strong><span>Change branch leadership</span></button><button class="quick-action" data-action="view-report" data-report="highadmin-user-access-overview">${icon('shield', 21)}<strong>Access overview</strong><span>Review users and effective roles</span></button><button class="quick-action" data-action="view-report" data-report="audit-trail">${icon('reports', 21)}<strong>Audit trail</strong><span>Review security-sensitive activity</span></button></div>`)}</div>`
    },

    managers: {
      actions: () => `${actionButton('hire-manager', 'Hire manager', 'userPlus')} ${actionButton('replace-manager', 'Replace branch manager', 'transfer', 'btn-secondary')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => {
        const employees = rows(await API().get('/api/employees', { includeTerminated: true, searchBranchHistory: true }));
        return employees.filter((employee) => /manager/i.test(String(employee.JobTitle || employee.CurrentJobTitle || '')));
      },
      render: (managers) => card('Manager governance', UI().renderTable(managers, {
        maxColumns: 12,
        actions: (manager) => `${smallAction('employee-details', 'View', 'eye', `data-id="${manager.EmployeeID}"`)}${smallAction('downgrade-manager', 'Downgrade', 'briefcase', `data-id="${manager.EmployeeID}"`)}${smallAction('manager-more', 'More', 'settings', `data-row="${encodeRow(manager)}"`)}`
      }), `<button class="btn btn-sm btn-secondary" data-action="promote-manager-manual">${icon('trend', 14)} Promote employee by ID</button>`)
    },

    audit: {
      actions: () => `${actionButton('view-report', 'Audit trail', 'shield', 'btn-secondary', 'data-report="audit-trail"')} ${actionButton('view-report', 'Branch ledger', 'reports', 'btn-secondary', 'data-report="branch-ledger"')}`,
      load: async () => {
        const [auditPayload, ledgerPayload] = await Promise.all([
          safeGet('/api/reports/audit-trail', { page: 1, pageSize: 50 }),
          safeGet('/api/reports/branch-ledger', { page: 1, pageSize: 50 })
        ]);
        return { audit: rows(auditPayload), ledger: rows(ledgerPayload) };
      },
      render: ({ audit, ledger }) => `<div class="content-grid"><div class="span-7">${card('Safe audit trail', UI().renderTable(audit, { maxColumns: 10 }))}</div><div class="span-5">${card('Branch ledger', UI().renderTable(ledger, { maxColumns: 10 }))}</div></div>`
    }
  };

  async function openAccountForm(state, refresh) {
    let branches = [];
    let accountTypes = [];
    try {
      const ownAccounts = await getAccounts(state, true);
      branches = uniqueOptions(ownAccounts, 'BranchID', (account) => `${account.BranchID} · ${account.BranchCode || account.BranchName || 'Branch'}`);
      accountTypes = uniqueOptions(ownAccounts, 'AccountTypeID', (account) => `${account.AccountTypeID} · ${account.AccountTypeName || 'Account type'}`);
    } catch (_) {
      // Customer users cannot use the branch catalogue endpoint. Existing account data is used when available.
    }

    UI().openForm({
      title: 'Open bank account',
      submitText: 'Open account',
      intro: '<div class="alert alert-info">The current backend requires numeric Branch ID and Account Type ID. Existing values are offered when they can be discovered from your accessible account records.</div>',
      fields: [
        selectOrNumber('branchID', 'Branch', branches, true, '', 'Use a valid BranchID from the database.'),
        selectOrNumber('accountTypeID', 'Account type', accountTypes, true, '', 'Use a valid AccountTypeID from the database.'),
        moneyField('initialDeposit', 'Initial deposit', false, 0)
      ],
      onSubmit: async (data) => {
        const response = await API().post('/api/accounts', data);
        const account = response.data || response.output || {};
        showPayload('Account opened', response);
        await success(state, refresh, `Account ${account.AccountNumber || account.AccountID || ''} was opened.`, 'Account opened', { accountID: account.AccountID, accountNumber: account.AccountNumber });
      }
    });
  }

  async function showAccountHistory(accountID, fromDate, toDate) {
    const params = cleanObject({ fromDate, toDate });
    const response = await API().get(`/api/accounts/${accountID}/history`, params);
    UI().openModal({
      title: `Account ${accountID} history`,
      size: 'lg',
      content: `${UI().renderTable(rows(response), { maxColumns: 12 })}<div class="form-actions"><button class="btn btn-secondary" data-action="account-history-filter" data-id="${accountID}">${icon('filter', 16)} Filter dates</button><button class="btn btn-secondary" data-action="export-account-history" data-id="${accountID}">${icon('download', 16)} Export CSV</button></div>`
    });
    const state = window.BankWorkspace.getState();
    state.activeAccountHistory = { accountID, rows: rows(response), fromDate, toDate };
  }

  async function lookupLoan(loanID) {
    const response = await API().get(`/api/loans/${loanID}/status`);
    showPayload(`Loan ${loanID} status`, response, ['Loan summary', 'Installment schedule']);
  }

  async function viewReport(reportKey, page = 1, pageSize = 50) {
    const response = await API().get(`/api/reports/${reportKey}`, { page, pageSize });
    const reportRows = rows(response);
    const state = window.BankWorkspace.getState();
    state.activeReport = { key: reportKey, page, pageSize, rows: reportRows, meta: response.meta || {} };
    const hasNext = reportRows.length === pageSize;
    UI().openModal({
      title: UI().humanize(reportKey),
      size: 'lg',
      content: `<div class="report-meta"><span>Page ${page}</span><span>${reportRows.length} row${reportRows.length === 1 ? '' : 's'}</span><span>${UI().escapeHtml(response.meta?.view || '')}</span></div>${UI().renderTable(reportRows, { maxColumns: 14 })}`,
      footer: `<div class="report-footer"><button class="btn btn-secondary" data-action="report-page" data-report="${reportKey}" data-page="${Math.max(1, page - 1)}" ${page <= 1 ? 'disabled' : ''}>${icon('arrow', 14, 'icon-reverse')} Previous</button><button class="btn btn-secondary" data-action="export-current-report">${icon('download', 15)} Export CSV</button><button class="btn btn-primary" data-action="report-page" data-report="${reportKey}" data-page="${page + 1}" ${hasNext ? '' : 'disabled'}>Next ${icon('arrow', 14)}</button></div>`
    });
  }

  const actions = {
    'open-account': async ({ state, refresh }) => openAccountForm(state, refresh),

    'view-account': async ({ element }) => {
      const response = await API().get(`/api/accounts/${element.dataset.id}`);
      UI().openModal({ title: `Account ${element.dataset.id}`, size: 'lg', content: UI().keyValue(response.data) });
    },

    'account-history': async ({ element }) => showAccountHistory(element.dataset.id),

    'account-history-filter': async ({ element }) => {
      const current = window.BankWorkspace.getState().activeAccountHistory || {};
      UI().openForm({
        title: 'Filter account history',
        submitText: 'Apply dates',
        fields: [
          { name: 'fromDate', label: 'From date', type: 'date', value: current.fromDate || '' },
          { name: 'toDate', label: 'To date', type: 'date', value: current.toDate || '' }
        ],
        onSubmit: async (data) => showAccountHistory(element.dataset.id, data.fromDate, data.toDate)
      });
    },

    'export-account-history': async () => {
      const current = window.BankWorkspace.getState().activeAccountHistory;
      UI().downloadCSV(current?.rows || [], `account-${current?.accountID || 'history'}-history.csv`);
    },

    'customer-filters': async ({ state, refresh }) => {
      const current = state.filters.customers || {};
      UI().openForm({
        title: 'Customer filters',
        submitText: 'Apply filters',
        fields: [
          { name: 'nameSearch', label: 'Name contains', value: current.nameSearch || '' },
          { name: 'nationalID', label: 'National ID', value: current.nationalID || '' },
          { name: 'phone', label: 'Phone', value: current.phone || '' },
          { name: 'email', label: 'Email', type: 'email', value: current.email || '' },
          selectField('includeInactive', 'Include inactive', [option('true', 'Yes'), option('false', 'No')], false, String(current.includeInactive ?? 'false'))
        ],
        onSubmit: async (data) => {
          state.filters.customers = cleanObject(data);
          await refresh();
        }
      });
    },

    'clear-customer-filters': async ({ state, refresh }) => {
      state.filters.customers = {};
      await refresh();
    },

    'create-customer': async ({ state, refresh }) => UI().openForm({
      title: 'Register customer',
      submitText: 'Create customer',
      size: 'lg',
      fields: [
        { name: 'firstName', label: 'First name', required: true },
        { name: 'lastName', label: 'Last name', required: true },
        { name: 'nationalID', label: 'National ID', required: true },
        { name: 'birthDate', label: 'Birth date', type: 'date', required: true },
        { name: 'phone', label: 'Phone', required: true },
        { name: 'email', label: 'Email', type: 'email', required: true },
        { name: 'address', label: 'Address', type: 'textarea', full: true }
      ],
      onSubmit: async (data) => {
        const response = await API().post('/api/customers', data);
        await success(state, refresh, `Customer ${response.data?.CustomerID || ''} was created.`, 'Customer created', { customerID: response.data?.CustomerID });
      }
    }),

    'edit-customer': async ({ element, state, refresh }) => {
      const customer = decodeRow(element.dataset.row);
      UI().openForm({
        title: `Edit ${customer.FirstName || ''} ${customer.LastName || 'customer'}`.trim(),
        submitText: 'Save changes',
        size: 'lg',
        fields: [
          { name: 'firstName', label: 'First name', required: true, value: customer.FirstName || '' },
          { name: 'lastName', label: 'Last name', required: true, value: customer.LastName || '' },
          { name: 'phone', label: 'Phone', required: true, value: customer.Phone || '' },
          { name: 'email', label: 'Email', type: 'email', required: true, value: customer.Email || '' },
          { name: 'address', label: 'Address', type: 'textarea', full: true, value: customer.Address || '' }
        ],
        onSubmit: async (data) => {
          await API().put(`/api/customers/${customer.CustomerID}`, data);
          await success(state, refresh, 'Customer information was updated.', 'Customer updated', { customerID: customer.CustomerID });
        }
      });
    },

    'delete-customer': async ({ element, state, refresh }) => UI().confirmAction({
      title: 'Deactivate customer',
      message: `Deactivate ${element.dataset.name || `customer ${element.dataset.id}`}? The database procedure applies its own safety rules.`,
      confirmText: 'Deactivate',
      danger: true,
      onConfirm: async () => {
        await API().delete(`/api/customers/${element.dataset.id}`);
        await success(state, refresh, 'Customer was deactivated.', 'Customer deactivated', { customerID: element.dataset.id });
      }
    }),

    'account-filters': async ({ state, refresh }) => {
      const current = state.filters.accounts || {};
      UI().openForm({
        title: 'Account filters',
        submitText: 'Apply filters',
        size: 'lg',
        fields: [
          numberField('accountID', 'Account ID', false, current.accountID || ''),
          { name: 'accountNumberSearch', label: 'Account number contains', value: current.accountNumberSearch || '' },
          numberField('customerID', 'Customer ID', false, current.customerID || ''),
          { name: 'customerNationalID', label: 'Customer national ID', value: current.customerNationalID || '' },
          { name: 'customerNameSearch', label: 'Customer name contains', value: current.customerNameSearch || '' },
          { name: 'branchCode', label: 'Branch code', value: current.branchCode || '' },
          { name: 'accountTypeName', label: 'Account type name', value: current.accountTypeName || '' },
          selectField('accountStatus', 'Account status', ['Active', 'Frozen', 'Dormant', 'Closed'], false, current.accountStatus || ''),
          moneyField('minBalance', 'Minimum balance', false, current.minBalance || ''),
          moneyField('maxBalance', 'Maximum balance', false, current.maxBalance || ''),
          selectField('includeClosed', 'Include closed', [option('true', 'Yes'), option('false', 'No')], false, String(current.includeClosed ?? 'true'))
        ],
        onSubmit: async (data) => {
          state.filters.accounts = cleanObject(data);
          await refresh();
        }
      });
    },

    'clear-account-filters': async ({ state, refresh }) => {
      state.filters.accounts = {};
      await refresh();
    },

    'account-more': async ({ element, state }) => {
      const account = decodeRow(element.dataset.row);
      const isAdmin = roleAtLeast(state, 'Admin');
      const accountID = account.AccountID;
      UI().openModal({
        title: `Manage account ${account.AccountNumber || accountID}`,
        content: `<div class="quick-actions"><button class="quick-action" data-action="freeze-account" data-id="${accountID}">${icon('lock', 21)}<strong>Freeze</strong><span>Restrict financial operations</span></button>${isAdmin ? `<button class="quick-action" data-action="unfreeze-account" data-id="${accountID}">${icon('refresh', 21)}<strong>Unfreeze</strong><span>Restore an eligible account</span></button>` : ''}<button class="quick-action" data-action="change-account-type" data-id="${accountID}">${icon('card', 21)}<strong>Change type</strong><span>Move to another account type</span></button><button class="quick-action" data-action="close-account" data-id="${accountID}">${icon('trash', 21)}<strong>Close account</strong><span>Close an eligible zero-balance account</span></button></div>`
      });
    },

    'freeze-account': async ({ element, state, refresh }) => UI().openForm({
      title: 'Freeze account',
      submitText: 'Freeze',
      fields: [{ name: 'reasonDescription', label: 'Reason', type: 'textarea', required: true, full: true }],
      onSubmit: async (data) => {
        await API().post(`/api/accounts/${element.dataset.id}/freeze`, data);
        await success(state, refresh, 'Account was frozen.', 'Account frozen', { accountID: element.dataset.id });
      }
    }),

    'unfreeze-account': async ({ element, state, refresh }) => UI().openForm({
      title: 'Unfreeze account',
      submitText: 'Unfreeze',
      fields: [{ name: 'reasonDescription', label: 'Reason', type: 'textarea', required: true, full: true }],
      onSubmit: async (data) => {
        await API().post(`/api/accounts/${element.dataset.id}/unfreeze`, data);
        await success(state, refresh, 'Account was unfrozen.', 'Account unfrozen', { accountID: element.dataset.id });
      }
    }),

    'change-account-type': async ({ element, state, refresh }) => {
      const types = await accountTypeOptions(state);
      UI().openForm({
        title: 'Change account type',
        submitText: 'Change type',
        intro: '<div class="alert alert-warning">The database rejects this operation while the account has pending transactions or fails account-type business rules.</div>',
        fields: [
          selectOrNumber('newAccountTypeID', 'New account type', types, true),
          { name: 'reasonDescription', label: 'Reason', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          await API().post(`/api/accounts/${element.dataset.id}/change-type`, data);
          await success(state, refresh, 'Account type was changed.', 'Account type changed', { accountID: element.dataset.id, accountTypeID: data.newAccountTypeID });
        }
      });
    },

    'close-account': async ({ element, state, refresh }) => UI().openForm({
      title: 'Close account',
      submitText: 'Close account',
      intro: '<div class="alert alert-danger">Closing an account is a destructive lifecycle action. The stored procedure can reject accounts with a balance or unresolved activity.</div>',
      fields: [{ name: 'reasonDescription', label: 'Reason', type: 'textarea', required: true, full: true }],
      onSubmit: async (data) => {
        await API().post(`/api/accounts/${element.dataset.id}/close`, data);
        await success(state, refresh, 'Account was closed.', 'Account closed', { accountID: element.dataset.id });
      }
    }),

    'deposit': async ({ state, refresh }) => {
      const accounts = await accountOptions(state, false);
      UI().openForm({
        title: 'Create deposit',
        submitText: 'Create deposit',
        fields: [
          selectOrNumber('accountID', 'Destination account', accounts, true),
          moneyField('amount', 'Amount'),
          numberField('employeeID', 'Employee ID override', false, '', 'Leave empty to use the logged-in employee identity.'),
          { name: 'description', label: 'Description', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          const response = await API().post('/api/transactions/deposit', data);
          await success(state, refresh, `Deposit transaction ${response.data?.TransactionID || ''} was created.`, 'Deposit created', { transactionID: response.data?.TransactionID, accountID: data.accountID, amount: data.amount });
        }
      });
    },

    'withdraw': async ({ state, refresh }) => {
      const accounts = await accountOptions(state, false);
      UI().openForm({
        title: 'Create withdrawal',
        submitText: 'Create withdrawal',
        fields: [
          selectOrNumber('accountID', 'Source account', accounts, true),
          moneyField('amount', 'Amount'),
          roleAtLeast(state, 'Employee') ? numberField('employeeID', 'Employee ID override', false, '', 'Leave empty to use the logged-in employee identity.') : { name: 'employeeID', type: 'hidden', value: '' },
          { name: 'description', label: 'Description', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          const response = await API().post('/api/transactions/withdraw', data);
          await success(state, refresh, `Withdrawal transaction ${response.data?.TransactionID || ''} was created.`, 'Withdrawal created', { transactionID: response.data?.TransactionID, accountID: data.accountID, amount: data.amount });
        }
      });
    },

    'transfer': async ({ state, refresh }) => {
      const accounts = await accountOptions(state, false);
      UI().openForm({
        title: 'Create transfer',
        submitText: 'Create transfer',
        fields: [
          selectOrNumber('fromAccountID', 'From account', accounts, true),
          state.config.role === 'Customer'
            ? numberField('toAccountID', 'Destination Account ID', true, '', 'Enter the receiving account ID. Customer account search intentionally lists only your own accounts.')
            : selectOrNumber('toAccountID', 'To account', accounts, true),
          moneyField('amount', 'Amount'),
          roleAtLeast(state, 'Employee') ? numberField('employeeID', 'Employee ID override', false) : { name: 'employeeID', type: 'hidden', value: '' },
          { name: 'description', label: 'Description', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          if (String(data.fromAccountID) === String(data.toAccountID)) throw new Error('Source and destination accounts must be different.');
          const response = await API().post('/api/transactions/transfer', data);
          await success(state, refresh, `Transfer transaction ${response.data?.TransactionID || ''} was created.`, 'Transfer created', { transactionID: response.data?.TransactionID, fromAccountID: data.fromAccountID, toAccountID: data.toAccountID, amount: data.amount });
        }
      });
    },

    'finalize-transaction': async ({ element, state, refresh }) => {
      const response = await API().post(`/api/transactions/${element.dataset.id}/finalize`);
      showPayload(`Transaction ${element.dataset.id} finalization`, response);
      await success(state, refresh, 'Transaction finalization was processed.', 'Transaction finalized', { transactionID: element.dataset.id });
    },

    'reverse-transaction': async ({ element, state, refresh }) => UI().openForm({
      title: 'Reverse transaction',
      submitText: 'Reverse transaction',
      intro: '<div class="alert alert-danger">Reversal is a financial correction. Use a clear reason and only reverse eligible test or operational transactions.</div>',
      fields: [
        numberField('employeeID', 'Employee ID override', false),
        { name: 'reasonDescription', label: 'Reason', type: 'textarea', required: true, full: true }
      ],
      onSubmit: async (data) => {
        await API().post(`/api/transactions/${element.dataset.id}/reverse`, data);
        await success(state, refresh, 'Transaction was reversed.', 'Transaction reversed', { transactionID: element.dataset.id });
      }
    }),

    'process-pending': async ({ state, refresh }) => UI().confirmAction({
      title: 'Process pending transactions',
      message: 'Run the pending transaction batch now? Only transactions whose ReadyToCompleteAt time has been reached will be finalized.',
      confirmText: 'Process batch',
      onConfirm: async () => {
        const response = await API().post('/api/transactions/maintenance/process-pending-batch');
        showPayload('Pending batch result', response);
        await success(state, refresh, 'Pending transaction batch completed.', 'Pending transaction batch processed');
      }
    }),

    'lookup-loan': async ({ element }) => {
      if (element.dataset.id) return lookupLoan(element.dataset.id);
      UI().openForm({
        title: 'Find loan',
        submitText: 'View status',
        fields: [numberField('loanID', 'Loan ID')],
        onSubmit: async (data) => lookupLoan(data.loanID)
      });
    },

    'create-loan': async ({ state, refresh }) => {
      const [customers, branches] = await Promise.all([customerOptions(state), branchOptions(state)]);
      UI().openForm({
        title: 'Create loan',
        submitText: 'Create loan',
        size: 'lg',
        fields: [
          selectOrNumber('customerID', 'Customer', customers, true),
          selectOrNumber('branchID', 'Branch', branches, true),
          moneyField('loanAmount', 'Loan amount'),
          { name: 'interestRate', label: 'Interest rate (%)', type: 'number', min: 0, step: '0.01', required: true },
          numberField('numberOfInstallments', 'Number of installments'),
          { name: 'startDate', label: 'Start date', type: 'date' }
        ],
        onSubmit: async (data) => {
          const response = await API().post('/api/loans', data);
          await success(state, refresh, `Loan ${response.data?.LoanID || ''} was created.`, 'Loan created', { loanID: response.data?.LoanID, customerID: data.customerID, amount: data.loanAmount });
        }
      });
    },

    'pay-installment': async ({ state, refresh }) => {
      const accounts = await accountOptions(state, false);
      UI().openForm({
        title: 'Pay loan installment',
        submitText: 'Create payment',
        fields: [
          numberField('installmentID', 'Installment ID'),
          selectOrNumber('fromAccountID', 'Source account', accounts, true),
          roleAtLeast(state, 'Employee') ? numberField('employeeID', 'Employee ID override', false) : { name: 'employeeID', type: 'hidden', value: '' }
        ],
        onSubmit: async (data) => {
          const installmentID = data.installmentID;
          delete data.installmentID;
          const response = await API().post(`/api/loans/installments/${installmentID}/pay`, data);
          await success(state, refresh, `Installment payment transaction ${response.data?.TransactionID || ''} was created.`, 'Loan installment payment created', { installmentID, transactionID: response.data?.TransactionID, accountID: data.fromAccountID });
        }
      });
    },

    'process-overdue': async ({ state, refresh }) => UI().confirmAction({
      title: 'Process overdue installments',
      message: 'Run the overdue-installment process now? This can update installment penalties and loan states across the database.',
      confirmText: 'Process overdue',
      onConfirm: async () => {
        const response = await API().post('/api/loans/maintenance/process-overdue-installments');
        showPayload('Overdue processing result', response);
        await success(state, refresh, 'Overdue installments were processed.', 'Overdue installments processed');
      }
    }),

    'view-branch': async ({ element }) => {
      const response = await API().get(`/api/branches/${element.dataset.id}`);
      UI().openModal({ title: `Branch ${element.dataset.id}`, size: 'lg', content: UI().keyValue(response.data) });
    },

    'employee-filters': async ({ state, refresh }) => {
      const current = state.filters.employees || {};
      UI().openForm({
        title: 'Employee filters',
        submitText: 'Apply filters',
        size: 'lg',
        fields: [
          numberField('employeeID', 'Employee ID', false, current.employeeID || ''),
          { name: 'nameSearch', label: 'Name contains', value: current.nameSearch || '' },
          { name: 'nationalID', label: 'National ID', value: current.nationalID || '' },
          { name: 'jobTitle', label: 'Job title', value: current.jobTitle || '' },
          selectField('empStatus', 'Employment status', ['Active', 'OnLeave', 'Terminated'], false, current.empStatus || ''),
          { name: 'branchCode', label: 'Branch code', value: current.branchCode || '' },
          selectField('workingStatus', 'Working status', ['Working', 'NotWorking'], false, current.workingStatus || ''),
          selectField('includeTerminated', 'Include terminated', [option('true', 'Yes'), option('false', 'No')], false, String(current.includeTerminated ?? 'true')),
          selectField('searchBranchHistory', 'Search branch history', [option('true', 'Yes'), option('false', 'No')], false, String(current.searchBranchHistory ?? 'false'))
        ],
        onSubmit: async (data) => {
          state.filters.employees = cleanObject(data);
          await refresh();
        }
      });
    },

    'clear-employee-filters': async ({ state, refresh }) => {
      state.filters.employees = {};
      await refresh();
    },

    'hire-employee': async ({ state, refresh }) => UI().openForm({
      title: 'Hire employee',
      submitText: 'Hire employee',
      size: 'lg',
      intro: '<div class="alert alert-info">The backend assigns the new employee according to the authenticated manager context and database rules.</div>',
      fields: [
        { name: 'nationalID', label: 'National ID', required: true },
        { name: 'firstName', label: 'First name', required: true },
        { name: 'lastName', label: 'Last name', required: true },
        { name: 'hireDate', label: 'Hire date', type: 'date' },
        { name: 'jobTitle', label: 'Job title', required: true },
        moneyField('salary', 'Salary'),
        { name: 'phone', label: 'Phone' },
        { name: 'email', label: 'Email', type: 'email' }
      ],
      onSubmit: async (data) => {
        const response = await API().post('/api/employees', data);
        await success(state, refresh, `Employee ${response.data?.EmployeeID || ''} was hired.`, 'Employee hired', { employeeID: response.data?.EmployeeID });
      }
    }),

    'employee-details': async ({ element, state }) => {
      const response = await API().get(`/api/employees/${element.dataset.id}`);
      const canManage = roleAtLeast(state, 'Admin');
      UI().openModal({
        title: `Employee ${element.dataset.id}`,
        size: 'lg',
        content: `${UI().renderRecordsets(recordsets(response), { titles: ['Employee details', 'Current branch assignment', 'Access details'] })}<div class="form-actions"><button class="btn btn-secondary" data-action="employee-branch-history" data-id="${element.dataset.id}">${icon('branch', 16)} Branch history</button>${canManage ? `<button class="btn btn-primary" data-action="create-employee-user" data-id="${element.dataset.id}">${icon('userPlus', 16)} Create login</button>` : ''}</div>`
      });
    },

    'employee-branch-history': async ({ element }) => {
      const response = await API().get(`/api/employees/${element.dataset.id}/branch-history`);
      UI().openModal({ title: 'Employee branch history', size: 'lg', content: UI().renderTable(rows(response), { maxColumns: 12 }) });
    },

    'create-employee-user': async ({ element, state, refresh }) => UI().openForm({
      title: 'Create employee application login',
      submitText: 'Create login',
      size: 'lg',
      fields: [
        { name: 'username', label: 'Username', required: true, autocomplete: 'off' },
        { name: 'password', label: 'Temporary password', type: 'password', required: true, autocomplete: 'new-password' },
        { name: 'birthDate', label: 'Birth date', type: 'date', required: true },
        { name: 'phone', label: 'Phone' },
        { name: 'email', label: 'Email', type: 'email' },
        { name: 'address', label: 'Address', type: 'textarea', full: true }
      ],
      onSubmit: async (data) => {
        const response = await API().post(`/api/employees/${element.dataset.id}/create-user-account`, data);
        await success(state, refresh, `Application login ${data.username} was created.`, 'Employee login created', { employeeID: element.dataset.id, userID: response.data?.UserID, username: data.username });
      }
    }),

    'change-job': async ({ element, state, refresh }) => UI().openForm({
      title: 'Change employee job title',
      submitText: 'Update title',
      fields: [
        { name: 'newJobTitle', label: 'New job title', required: true },
        { name: 'reasonDescription', label: 'Reason', type: 'textarea', full: true }
      ],
      onSubmit: async (data) => {
        await API().post(`/api/employees/${element.dataset.id}/change-job-title`, data);
        await success(state, refresh, 'Employee job title was updated.', 'Employee job title changed', { employeeID: element.dataset.id, jobTitle: data.newJobTitle });
      }
    }),

    'employee-more': async ({ element }) => {
      const employee = decodeRow(element.dataset.row);
      UI().openModal({
        title: `Manage ${`${employee.FirstName || ''} ${employee.LastName || ''}`.trim() || `employee ${employee.EmployeeID}`}`,
        content: `<div class="quick-actions"><button class="quick-action" data-action="create-employee-user" data-id="${employee.EmployeeID}">${icon('userPlus', 21)}<strong>Create login</strong><span>Link application access</span></button><button class="quick-action" data-action="change-job" data-id="${employee.EmployeeID}">${icon('briefcase', 21)}<strong>Change title</strong><span>Update job assignment</span></button><button class="quick-action" data-action="suspend-employee" data-id="${employee.EmployeeID}">${icon('alert', 21)}<strong>Suspend</strong><span>Set employee to OnLeave</span></button><button class="quick-action" data-action="fire-employee" data-id="${employee.EmployeeID}">${icon('trash', 21)}<strong>Terminate</strong><span>End employment record</span></button></div>`
      });
    },

    'suspend-employee': async ({ element, state, refresh }) => UI().openForm({
      title: 'Suspend employee',
      submitText: 'Suspend',
      fields: [{ name: 'reason', label: 'Reason', type: 'textarea', required: true, full: true }],
      onSubmit: async (data) => {
        await API().post(`/api/employees/${element.dataset.id}/suspend`, data);
        await success(state, refresh, 'Employee was suspended.', 'Employee suspended', { employeeID: element.dataset.id });
      }
    }),

    'fire-employee': async ({ element, state, refresh }) => UI().openForm({
      title: 'Terminate employee',
      submitText: 'Terminate',
      intro: '<div class="alert alert-danger">This ends the employment record. The user can retain only roles still allowed by database policy.</div>',
      fields: [
        { name: 'terminationDate', label: 'Termination date', type: 'date' },
        { name: 'reason', label: 'Reason', type: 'textarea', required: true, full: true }
      ],
      onSubmit: async (data) => {
        await API().post(`/api/employees/${element.dataset.id}/fire`, data);
        await success(state, refresh, 'Employee was terminated.', 'Employee terminated', { employeeID: element.dataset.id });
      }
    }),

    'request-transfer-self': async ({ state, refresh }) => {
      const branches = roleAtLeast(state, 'Employee') ? await branchOptions(state) : [];
      UI().openForm({
        title: 'Request branch transfer',
        submitText: 'Submit request',
        fields: [
          selectOrNumber('toBranchID', 'Destination branch', branches, true),
          { name: 'reason', label: 'Reason', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          const response = await API().post('/api/employee-transfers/request-by-employee', data);
          const requestID = response.data?.TransferRequestID || response.output?.TransferRequestID;
          showPayload('Transfer request created', response);
          await success(state, refresh, `Transfer request ${requestID || ''} was submitted.`, 'Employee transfer requested', { transferRequestID: requestID, toBranchID: data.toBranchID });
        }
      });
    },

    'request-transfer-manager': async ({ state, refresh }) => {
      const [employees, branches] = await Promise.all([employeeOptions(state), branchOptions(state)]);
      UI().openForm({
        title: 'Manager transfer request',
        submitText: 'Submit request',
        size: 'lg',
        fields: [
          selectOrNumber('employeeID', 'Employee', employees, true),
          selectOrNumber('toBranchID', 'Destination branch', branches, true),
          { name: 'reason', label: 'Reason', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          const response = await API().post('/api/employee-transfers/request-by-manager', data);
          const requestID = response.data?.TransferRequestID || response.output?.TransferRequestID;
          showPayload('Transfer request created', response);
          await success(state, refresh, `Transfer request ${requestID || ''} was submitted.`, 'Manager transfer requested', { transferRequestID: requestID, employeeID: data.employeeID, toBranchID: data.toBranchID });
        }
      });
    },

    'transfer-decision': async ({ state, refresh }) => UI().openForm({
      title: 'Record transfer decision',
      submitText: 'Record decision',
      fields: [
        numberField('transferRequestID', 'Transfer request ID'),
        selectField('stage', 'Decision stage', [
          option('current-manager-decision', 'Current manager'),
          option('destination-manager-decision', 'Destination manager')
        ]),
        selectField('approve', 'Decision', [option('true', 'Approve'), option('false', 'Reject')]),
        { name: 'decisionNote', label: 'Decision note', type: 'textarea', full: true }
      ],
      onSubmit: async (data) => {
        const requestID = data.transferRequestID;
        const stage = data.stage;
        const body = { approve: data.approve === 'true', decisionNote: data.decisionNote };
        const response = await API().post(`/api/employee-transfers/${requestID}/${stage}`, body);
        showPayload('Transfer decision result', response);
        await success(state, refresh, 'Transfer decision was recorded.', 'Transfer decision recorded', { transferRequestID: requestID, stage, approved: body.approve });
      }
    }),

    'view-report': async ({ element }) => viewReport(element.dataset.report, Number(element.dataset.page || 1)),

    'report-page': async ({ element }) => viewReport(element.dataset.report, Number(element.dataset.page || 1)),

    'export-current-report': async () => {
      const report = window.BankWorkspace.getState().activeReport;
      UI().downloadCSV(report?.rows || [], `${report?.key || 'bank-report'}-page-${report?.page || 1}.csv`);
    },

    'apply-interest': async ({ state, refresh }) => UI().confirmAction({
      title: 'Apply monthly interest',
      message: 'Apply monthly interest to all eligible accounts now? This operation can change many balances and should not be repeated accidentally.',
      confirmText: 'Apply interest',
      onConfirm: async () => {
        const response = await API().post('/api/accounts/maintenance/apply-monthly-interest');
        showPayload('Monthly interest result', response);
        await success(state, refresh, 'Monthly interest process completed.', 'Monthly interest applied');
      }
    }),

    'dormant-sweep': async ({ state, refresh }) => UI().openForm({
      title: 'Dormant account sweep',
      submitText: 'Run sweep',
      intro: '<div class="alert alert-warning">This broad operation can update many account statuses.</div>',
      fields: [numberField('monthsInactive', 'Months inactive', true, 12)],
      onSubmit: async (data) => {
        const response = await API().post('/api/accounts/maintenance/dormant-sweep', data);
        showPayload('Dormant sweep result', response);
        await success(state, refresh, 'Dormant account sweep completed.', 'Dormant account sweep processed', { monthsInactive: data.monthsInactive });
      }
    }),

    'hire-manager': async ({ state, refresh }) => {
      const branches = await branchOptions(state);
      UI().openForm({
        title: 'Hire branch manager',
        submitText: 'Hire manager',
        size: 'lg',
        fields: [
          selectOrNumber('branchID', 'Branch', branches, true),
          { name: 'username', label: 'Username', required: true, autocomplete: 'off' },
          { name: 'password', label: 'Temporary password', type: 'password', required: true, autocomplete: 'new-password' },
          { name: 'nationalID', label: 'National ID', required: true },
          { name: 'firstName', label: 'First name', required: true },
          { name: 'lastName', label: 'Last name', required: true },
          { name: 'birthDate', label: 'Birth date', type: 'date', required: true },
          { name: 'hireDate', label: 'Hire date', type: 'date' },
          { name: 'jobTitle', label: 'Job title', required: true, value: 'Branch Manager' },
          moneyField('salary', 'Salary'),
          { name: 'phone', label: 'Phone', required: true },
          { name: 'email', label: 'Email', type: 'email', required: true },
          { name: 'address', label: 'Address', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          const response = await API().post('/api/highadmin/managers', data);
          await success(state, refresh, `Manager ${response.data?.EmployeeID || ''} was hired.`, 'Branch manager hired', { employeeID: response.data?.EmployeeID, branchID: data.branchID, username: data.username });
        }
      });
    },

    'promote-manager-manual': async ({ state, refresh }) => {
      const employees = await employeeOptions(state);
      const branches = await branchOptions(state);
      UI().openForm({
        title: 'Promote employee to manager',
        submitText: 'Promote',
        fields: [
          selectOrNumber('employeeID', 'Employee', employees, true),
          selectOrNumber('branchID', 'Manager branch', branches, true),
          { name: 'managerJobTitle', label: 'Manager job title', required: true, value: 'Branch Manager' },
          { name: 'effectiveDate', label: 'Effective date', type: 'date' },
          { name: 'reason', label: 'Reason', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          const employeeID = data.employeeID;
          delete data.employeeID;
          await API().post(`/api/highadmin/managers/${employeeID}/promote`, data);
          await success(state, refresh, 'Employee was promoted to manager.', 'Employee promoted to manager', { employeeID, branchID: data.branchID });
        }
      });
    },

    'promote-manager': async ({ element, state, refresh }) => {
      const branches = await branchOptions(state);
      UI().openForm({
        title: 'Promote employee to manager',
        submitText: 'Promote',
        fields: [
          selectOrNumber('branchID', 'Manager branch', branches, true),
          { name: 'managerJobTitle', label: 'Manager job title', required: true, value: 'Branch Manager' },
          { name: 'effectiveDate', label: 'Effective date', type: 'date' },
          { name: 'reason', label: 'Reason', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          await API().post(`/api/highadmin/managers/${element.dataset.id}/promote`, data);
          await success(state, refresh, 'Employee was promoted to manager.', 'Employee promoted to manager', { employeeID: element.dataset.id, branchID: data.branchID });
        }
      });
    },

    'downgrade-manager': async ({ element, state, refresh }) => UI().openForm({
      title: 'Downgrade manager',
      submitText: 'Downgrade',
      fields: [
        { name: 'newJobTitle', label: 'New job title', required: true },
        { name: 'reason', label: 'Reason', type: 'textarea', full: true }
      ],
      onSubmit: async (data) => {
        await API().post(`/api/highadmin/managers/${element.dataset.id}/downgrade`, data);
        await success(state, refresh, 'Manager was downgraded.', 'Manager downgraded', { employeeID: element.dataset.id, jobTitle: data.newJobTitle });
      }
    }),

    'manager-more': async ({ element }) => {
      const manager = decodeRow(element.dataset.row);
      UI().openModal({
        title: `Manager actions · ${`${manager.FirstName || ''} ${manager.LastName || ''}`.trim() || manager.EmployeeID}`,
        content: `<div class="quick-actions"><button class="quick-action" data-action="employee-details" data-id="${manager.EmployeeID}">${icon('eye', 21)}<strong>View details</strong><span>Employee and branch records</span></button><button class="quick-action" data-action="downgrade-manager" data-id="${manager.EmployeeID}">${icon('briefcase', 21)}<strong>Downgrade</strong><span>Remove manager role and change title</span></button><button class="quick-action" data-action="suspend-manager" data-id="${manager.EmployeeID}">${icon('alert', 21)}<strong>Suspend</strong><span>Temporarily suspend manager</span></button><button class="quick-action" data-action="fire-manager" data-id="${manager.EmployeeID}">${icon('trash', 21)}<strong>Terminate</strong><span>End manager employment</span></button></div>`
      });
    },

    'suspend-manager': async ({ element, state, refresh }) => UI().openForm({
      title: 'Suspend manager',
      submitText: 'Suspend',
      fields: [{ name: 'reason', label: 'Reason', type: 'textarea', required: true, full: true }],
      onSubmit: async (data) => {
        await API().post(`/api/highadmin/managers/${element.dataset.id}/suspend`, data);
        await success(state, refresh, 'Manager was suspended.', 'Manager suspended', { employeeID: element.dataset.id });
      }
    }),

    'fire-manager': async ({ element, state, refresh }) => UI().openForm({
      title: 'Terminate manager',
      submitText: 'Terminate',
      intro: '<div class="alert alert-danger">Use branch manager replacement first when the branch must retain active management.</div>',
      fields: [
        { name: 'terminationDate', label: 'Termination date', type: 'date' },
        { name: 'reason', label: 'Reason', type: 'textarea', required: true, full: true }
      ],
      onSubmit: async (data) => {
        await API().post(`/api/highadmin/managers/${element.dataset.id}/fire`, data);
        await success(state, refresh, 'Manager was terminated.', 'Manager terminated', { employeeID: element.dataset.id });
      }
    }),

    'replace-manager': async ({ state, refresh }) => {
      const [branches, employees] = await Promise.all([branchOptions(state), employeeOptions(state)]);
      UI().openForm({
        title: 'Replace branch manager',
        submitText: 'Replace manager',
        size: 'lg',
        fields: [
          selectOrNumber('branchID', 'Branch', branches, true),
          selectOrNumber('newManagerEmployeeID', 'New manager employee', employees, true),
          { name: 'oldManagerNewJobTitle', label: 'Old manager new job title' },
          { name: 'effectiveDate', label: 'Effective date', type: 'date' },
          { name: 'reason', label: 'Reason', type: 'textarea', full: true }
        ],
        onSubmit: async (data) => {
          const branchID = data.branchID;
          delete data.branchID;
          await API().post(`/api/highadmin/branches/${branchID}/replace-manager`, data);
          await success(state, refresh, 'Branch manager was replaced.', 'Branch manager replaced', { branchID, newManagerEmployeeID: data.newManagerEmployeeID });
        }
      });
    }
  };

  window.BankFeatures = { sections, actions, card, actionButton, smallAction };
})();
