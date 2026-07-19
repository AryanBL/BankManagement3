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


  function isManagerLevelEmployee(employee) {
    return Boolean(employee?.CanAccessAdmin) || /^(branch manager|vice manager)$/i.test(String(employee?.JobTitle || '').trim());
  }

  function canManageEmployee(state, employee) {
    if (!roleAtLeast(state, 'Admin') || !employee?.EmployeeID) return false;
    if (Number(employee.EmployeeID) === Number(state.user?.EmployeeID)) return false;
    return !isManagerLevelEmployee(employee);
  }

  function employeeDirectoryTitle(state) {
    if (state.config.role === 'HighAdmin') return 'All employees';
    if (state.config.role === 'Admin') return 'Current branch employees';
    return 'My employee profile';
  }

  function employeeDirectoryNotice(state) {
    if (state.config.role === 'HighAdmin') {
      return '<div class="alert alert-info"><strong>Enterprise scope.</strong> HighAdmin can view employees across all branches. Manager-level changes remain in Manager governance.</div>';
    }
    if (state.config.role === 'Admin') {
      return '<div class="alert alert-info"><strong>Current-branch scope.</strong> The API and stored procedures return only employees currently assigned to your branch. Actions are available only for eligible ordinary employees in that branch.</div>';
    }
    return '<div class="alert alert-info"><strong>Personal scope.</strong> Normal employees can view only their own employee record and branch history.</div>';
  }

  function customerDirectoryTitle(state) {
    return state.config.role === 'HighAdmin' ? 'All customers' : 'Current branch customers';
  }

  function customerDirectoryNotice(state) {
    if (state.config.role === 'HighAdmin') {
      return '<div class="alert alert-info"><strong>Enterprise scope.</strong> HighAdmin can view and manage customers across all branches.</div>';
    }
    return `<div class="alert alert-info"><strong>Current-branch scope.</strong> Only customers who own at least one account in ${UI().escapeHtml(state.user?.CurrentBranchName || `Branch ${state.user?.CurrentBranchID || ''}`)} are returned. Customers with accounts in more than one branch are visible to each corresponding branch.</div>`;
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
    const normalizedOptions = Array.isArray(options) ? options : [];
    if (normalizedOptions.length) {
      return {
        ...selectField(name, label, normalizedOptions, required, value, help),
        valueType: 'number',
        emptyLabel: `Select ${String(label || 'item').toLowerCase()}…`
      };
    }
    return {
      ...numberField(name, label, required, value, help),
      min: 1,
      suggestions: normalizedOptions
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
    return cached(state, `accounts.viewable.${includeClosed}`, async () => rows(await API().get('/api/accounts', includeClosed ? { includeClosed: true } : undefined)));
  }

  async function getOwnAccounts(state, includeClosed = true) {
    return cached(state, `accounts.mine.${includeClosed}`, async () => rows(await API().get('/api/accounts/mine', includeClosed ? { includeClosed: true } : undefined)));
  }

  async function getLoans(state, scope = 'viewable') {
    const path = scope === 'mine' ? '/api/loans?scope=mine' : '/api/loans';
    return cached(state, `loans.${scope}`, async () => rows(await API().get(path)));
  }

  async function getBranches(state) {
    return cached(state, 'branches', async () => rows(await API().get('/api/branches')));
  }

  async function getBranchChoices(state) {
    return cached(state, 'branch.options', async () => rows(await API().get('/api/branches/options')));
  }

  async function getAccountTypeChoices(state) {
    return cached(state, 'account-type.options', async () => rows(await API().get('/api/accounts/options/account-types')));
  }

  async function getCustomers(state) {
    return cached(state, 'customers', async () => rows(await API().get('/api/customers', { includeInactive: true })));
  }

  async function getEmployees(state) {
    return cached(state, 'employees', async () => rows(await API().get('/api/employees', { includeTerminated: true, searchBranchHistory: true })));
  }

  async function accountOptions(state, includeClosed = false) {
    const accounts = await getOwnAccounts(state, includeClosed);
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
    const branches = await getBranchChoices(state);
    return uniqueOptions(branches, 'BranchID', (branch) => {
      const code = branch.BranchCode || branch.BranchID;
      const name = branch.BranchName || 'Branch';
      const city = branch.City ? ` · ${branch.City}` : '';
      return `${code} · ${name}${city}`;
    });
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
    const accountTypes = await getAccountTypeChoices(state);
    return uniqueOptions(accountTypes, 'AccountTypeID', (accountType) => {
      const name = accountType.TypeName || accountType.AccountTypeName || 'Account type';
      const minBalance = accountType.MinBalance !== undefined
        ? ` · Minimum ${UI().formatMoney(accountType.MinBalance)}`
        : '';
      return `${accountType.AccountTypeID} · ${name}${minBalance}`;
    });
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
    const meta = payload?.meta || {};
    UI().openModal({
      title,
      size: 'lg',
      content: UI().renderRecordsets(sets, {
        titles,
        dateFields: meta.dateFields || {},
        dateFieldsBySet: meta.dateFieldsByRecordset || []
      })
    });
  }

  function filterTools(filterAction, clearAction, hasFilters) {
    return `${actionButton(filterAction, 'Filters', 'filter', 'btn-secondary')} ${hasFilters ? actionButton(clearAction, 'Clear filters', 'close', 'btn-secondary') : ''} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`;
  }

  const sections = {
    customerOverview: {
      actions: () => `${actionButton('open-account', 'Open new account', 'plus')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async (state) => {
        const accounts = rows(await API().get('/api/accounts/mine'));
        const history = [];
        for (const account of accounts.slice(0, 4)) {
          const payload = await safeGet(`/api/accounts/${account.AccountID}/history`, { scope: 'mine' });
          rows(payload).forEach((transaction) => history.push({ ...transaction, AccountNumber: account.AccountNumber }));
        }
        history.sort((a, b) => UI().dateSortValue(b.TransactionDate || b.CreatedAt || b.date, 'datetime') - UI().dateSortValue(a.TransactionDate || a.CreatedAt || a.date, 'datetime'));
        return { accounts, history };
      },
      render: ({ accounts, history }) => {
        const totalBalance = accounts.reduce((sum, account) => sum + Number(account.Balance || 0), 0);
        const pending = history.filter((transaction) => /pending/i.test(transaction.TransactionStatus || '')).length;
        const accountCards = accounts.length
          ? `<div class="content-grid">${accounts.slice(0, 4).map((account) => `<div class="span-6"><div class="account-card card"><div class="account-label">${UI().escapeHtml(account.AccountTypeName || 'Bank account')}</div><div class="account-balance">${UI().formatMoney(account.Balance || 0)}</div><div class="account-number">${UI().escapeHtml(account.AccountNumber || '')}</div><div class="account-meta"><span>${UI().escapeHtml(account.BranchName || account.BranchCode || '')}</span><span>${UI().statusBadge(account.AccountStatus || 'Active')}</span></div><div class="form-actions" style="justify-content:flex-start"><button class="btn btn-sm btn-secondary" data-action="view-account" data-id="${account.AccountID}" data-scope="mine">${icon('eye', 14)} Details</button><button class="btn btn-sm btn-secondary" data-action="account-history" data-id="${account.AccountID}" data-scope="mine">${icon('reports', 14)} History</button></div></div></div>`).join('')}</div>`
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
      load: async () => rows(await API().get('/api/accounts/mine')),
      render: (accounts) => card('Account portfolio', UI().renderTable(accounts, {
        hide: ['CustomerID'],
        actions: (account) => `${smallAction('view-account', 'Details', 'eye', `data-id="${account.AccountID}"`)}${smallAction('account-history', 'History', 'reports', `data-id="${account.AccountID}"`)}`
      }))
    },

    customerTransactions: {
      actions: () => `${actionButton('transfer', 'New transfer', 'transfer')} ${actionButton('withdraw', 'Withdraw', 'money', 'btn-secondary')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => {
        const accounts = rows(await API().get('/api/accounts/mine'));
        const history = [];
        for (const account of accounts) {
          const payload = await safeGet(`/api/accounts/${account.AccountID}/history`, { scope: 'mine' });
          rows(payload).forEach((transaction) => history.push({ ...transaction, AccountNumber: account.AccountNumber }));
        }
        history.sort((a, b) => UI().dateSortValue(b.TransactionDate || b.CreatedAt || b.date, 'datetime') - UI().dateSortValue(a.TransactionDate || a.CreatedAt || a.date, 'datetime'));
        return { accounts, history };
      },
      render: ({ accounts, history }) => `<div class="content-grid"><div class="span-8">${card('Transaction history', UI().renderTable(history, { hide: ['Description'], maxColumns: 10 }))}</div><div class="span-4">${card('Account balances', accounts.map((account) => `<div class="account-mini"><strong>${UI().escapeHtml(account.AccountNumber || '')}</strong><span>${UI().formatMoney(account.Balance || 0)}</span>${UI().statusBadge(account.AccountStatus || 'Active')}</div>`).join('') || UI().emptyState('No accounts', 'No account balance is available.'))}${card('Processing rule', '<div class="alert alert-info"><strong>Transaction Date</strong> is the creation time. <strong>Ready To Complete At</strong> is a scheduled processing time and can be 0–5 minutes later depending on the amount. Both are displayed in the browser\'s local time.</div>', '', 'section-spacer')}</div></div>`
    },

    customerLoans: {
      actions: () => `${actionButton('pay-installment', 'Pay installment', 'money')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => ({ loans: rows(await API().get('/api/loans', { scope: 'mine', pageSize: 200 })) }),
      render: ({ loans }) => `<div class="content-grid"><div class="span-8">${card('My loans', UI().renderTable(loans, {
        hide: ['CustomerID'],
        maxColumns: 12,
        actions: (loan) => smallAction('lookup-loan', 'Status & installments', 'eye', `data-id="${loan.LoanID}" data-scope="mine"`)
      }))}</div><div class="span-4">${card('Installment payment', `<div class="alert alert-info"><strong>Borrower-only payment:</strong> the backend and SQL Server verify that both the installment and source account belong to your customer profile.</div><div class="form-actions">${actionButton('pay-installment', 'Pay installment', 'money')}</div>`)}</div></div>`
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
          EffectiveRoles: roles.join(', '),
          LoginTime: user.LoginTime,
          ExpiresAt: user.ExpiresAt
        }))}</div><div class="span-5">${card('Session security', `<div class="alert alert-info"><strong>Database-backed bearer session</strong><br>The token has a fixed 10-minute lifetime. Activity does not extend it. SQL Server rejects the token after <strong>${UI().escapeHtml(UI().formatDate(user.ExpiresAt, { kind: 'datetime' }))}</strong>, and the browser automatically returns to login.</div><div class="connection-summary"><span>Frontend</span><strong>${UI().escapeHtml(location.origin)}</strong><span>Backend</span><strong>${UI().escapeHtml(window.BankConfig.getApiBaseUrl())}</strong></div><div class="form-actions">${actionButton('logout', 'End current session', 'logout', 'btn-danger')}</div>`)}</div></div>`;
      }
    },

    staffOverview: {
      actions: () => actionButton('refresh-section', 'Refresh dashboard', 'refresh', 'btn-secondary'),
      load: async (state) => {
        const currentBranchID = Number(state.user?.CurrentBranchID || 0);
        const branchPromise = currentBranchID
          ? safeGet(`/api/branches/${currentBranchID}`)
          : Promise.resolve({ data: null });

        const [customersPayload, branchPayload, employeesPayload, pendingPayload, loansPayload] = await Promise.all([
          safeGet('/api/customers'),
          branchPromise,
          safeGet('/api/employees'),
          safeGet('/api/reports/pending-transactions', { page: 1, pageSize: 8 }),
          safeGet('/api/loans', { page: 1, pageSize: 200 })
        ]);

        const branchData = Array.isArray(branchPayload?.data)
          ? branchPayload.data[0] || null
          : branchPayload?.data || null;

        return {
          role: state.config.role,
          customers: rows(customersPayload),
          branch: branchData,
          employees: rows(employeesPayload),
          pending: rows(pendingPayload),
          loans: rows(loansPayload)
        };
      },
      render: (data, state) => {
        const branch = data.branch || {};
        const branchName = branch.BranchName || state.user?.CurrentBranchName || 'Current branch';
        const managerName = [
          branch.CurrentBranchManagerFirstName,
          branch.CurrentBranchManagerLastName
        ].filter(Boolean).join(' ') || 'Not assigned';
        const totalAccounts = Number(branch.TotalAccountCount || 0);
        const activeAccounts = Number(branch.ActiveAccountCount || 0);
        const currentEmployees = Number(branch.CurrentEmployeeCount || data.employees.length || 0);
        const branchDetails = {
          BranchName: branchName,
          BranchCode: branch.BranchCode || '—',
          BranchID: branch.BranchID || state.user?.CurrentBranchID || '—',
          City: branch.City || '—',
          Address: branch.Address || '—',
          Phone: branch.Phone || '—',
          Balance: branch.Balance ?? '—',
          CurrentManager: managerName
        };
        const operatingDetails = {
          VisibleCustomers: data.customers.length,
          CurrentEmployees: currentEmployees,
          CurrentViceManagers: Number(branch.CurrentViceManagerCount || 0),
          ActiveAccounts: activeAccounts,
          TotalAccounts: totalAccounts,
          VisibleLoans: data.loans.length,
          PendingTransactions: data.pending.length
        };

        return `<div class="stat-grid">
          ${UI().statCard('Customers', data.customers.length, `Visible in ${branchName}`, 'users')}
          ${UI().statCard('Accounts', totalAccounts, `${activeAccounts} active`, 'card', 'var(--blue-500)', 'rgba(59,130,246,.12)')}
          ${UI().statCard('Pending transactions', data.pending.length, 'Awaiting finalization', 'clock', 'var(--amber-500)', 'rgba(245,158,11,.14)')}
          ${UI().statCard('Loans', data.loans.length, `${countStatus(data.loans, /active/i)} active`, 'loan', 'var(--violet-500)', 'rgba(139,92,246,.12)')}
        </div>
        <div class="dashboard-grid">
          ${card('Pending transaction queue', UI().renderTable(data.pending.slice(0, 8), { hide: ['Description'], maxColumns: 8 }), `<button class="btn btn-sm btn-secondary" data-action="view-report" data-report="pending-transactions">Open report ${icon('arrow', 14)}</button>`)}
          ${card('Operations shortcuts', `<div class="quick-actions"><button class="quick-action" data-action="create-customer">${icon('userPlus', 21)}<strong>New customer</strong><span>Register a customer profile</span></button><button class="quick-action" data-action="deposit">${icon('money', 21)}<strong>Personal deposit</strong><span>Deposit into one of your own accounts</span></button><button class="quick-action" data-action="create-loan">${icon('loan', 21)}<strong>New loan</strong><span>Create an installment schedule</span></button><button class="quick-action" data-section-target="reports">${icon('reports', 21)}<strong>Reports</strong><span>Open protected SQL views</span></button></div>`)}
        </div>
        <div class="section-spacer">
          <div class="content-grid">
            <div class="span-7">${card('Current branch overview', UI().keyValue(branchDetails))}</div>
            <div class="span-5">${card('Current branch operating totals', UI().keyValue(operatingDetails), `<button class="btn btn-sm btn-secondary" data-section-target="branches">Branch details ${icon('arrow', 14)}</button>`)}</div>
          </div>
        </div>`;
      }
    },

    customers: {
      actions: (state) => `${actionButton('create-customer', 'Add customer', 'userPlus')} ${filterTools('customer-filters', 'clear-customer-filters', Boolean(Object.keys(state.filters.customers || {}).length))}`,
      load: async (state) => {
        const filters = cleanObject(state.filters.customers || {});
        return { filters, customers: rows(await API().get('/api/customers', filters)) };
      },
      render: ({ filters, customers }, state) => `${UI().filterSummary(filters)}${card(customerDirectoryTitle(state), `${customerDirectoryNotice(state)}${UI().renderTable(customers, {
        hide: ['Address'],
        maxColumns: 11,
        actions: (customer) => `${smallAction('edit-customer', 'Edit', 'edit', `data-row="${encodeRow(customer)}"`)}${smallAction('delete-customer', 'Deactivate', 'trash', `data-id="${customer.CustomerID}" data-name="${UI().escapeHtml(`${customer.FirstName || ''} ${customer.LastName || ''}`)}"`, 'btn-danger')}`
      })}`)}`
    },

    staffOwnAccounts: {
      actions: () => `${actionButton('open-account', 'Open personal account', 'plus')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => rows(await API().get('/api/accounts/mine', { includeClosed: true })),
      render: (accounts) => `<div class="content-grid"><div class="span-8">${card('My personal accounts', UI().renderTable(accounts, {
        hide: ['CustomerID'],
        maxColumns: 11,
        actions: (account) => `${smallAction('view-account', 'Details', 'eye', `data-id="${account.AccountID}" data-scope="mine"`)}${smallAction('account-history', 'History', 'reports', `data-id="${account.AccountID}" data-scope="mine"`)}`
      }))}</div><div class="span-4">${card('Ownership rule', '<div class="alert alert-info"><strong>Personal portfolio:</strong> these accounts belong to the CustomerID linked to your login. Transactions are available only from this portfolio.</div>')}</div></div>`
    },

    staffAccounts: {
      actions: (state) => filterTools('account-filters', 'clear-account-filters', Boolean(Object.keys(state.filters.accounts || {}).length)),
      load: async (state) => {
        const filters = { includeClosed: true, ...cleanObject(state.filters.accounts || {}) };
        const response = await API().get('/api/accounts', filters);
        return { filters, accounts: rows(response), meta: response.meta || {} };
      },
      render: ({ filters, accounts, meta }, state) => `${UI().filterSummary(filters)}${card(meta?.accessScope === 'all' ? 'All bank accounts' : 'Current branch accounts', `<div class="alert alert-info"><strong>Operational account management.</strong> Employees and branch managers can view and manage eligible accounts in their current branch. HighAdmin can manage eligible accounts across all branches. Deposit, withdrawal, transfer, finalization, reversal, and installment payment remain owner-only operations.</div>${UI().renderTable(accounts, {
        hide: ['OpeningDate', 'CustomerID'],
        maxColumns: 11,
        actions: (account) => `${smallAction('view-account', 'View', 'eye', `data-id="${account.AccountID}" data-scope="viewable"`)}${smallAction('account-history', 'History', 'reports', `data-id="${account.AccountID}" data-scope="viewable"`)}${smallAction('account-more', 'Manage', 'settings', `data-row="${encodeRow(account)}"`)}`
      })}`)}`
    },

    staffTransactions: {
      actions: () => `${actionButton('deposit', 'Deposit to my account', 'plus')} ${actionButton('withdraw', 'Withdraw from my account', 'money', 'btn-secondary')} ${actionButton('transfer', 'Transfer from my account', 'transfer', 'btn-secondary')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => {
        const accounts = rows(await API().get('/api/accounts/mine'));
        const history = [];
        for (const account of accounts) {
          const payload = await safeGet(`/api/accounts/${account.AccountID}/history`, { scope: 'mine' });
          rows(payload).forEach((transaction) => history.push({ ...transaction, AccountNumber: account.AccountNumber }));
        }
        history.sort((a, b) => UI().dateSortValue(b.TransactionDate || b.CreatedAt || b.date, 'datetime') - UI().dateSortValue(a.TransactionDate || a.CreatedAt || a.date, 'datetime'));
        return { accounts, history };
      },
      render: ({ accounts, history }) => `<div class="content-grid"><div class="span-8">${card('My transaction history', UI().renderTable(history, { hide: ['Description'], maxColumns: 11 }))}</div><div class="span-4">${card('Owner-only controls', `<div class="alert alert-info">Your Employee, Admin, or HighAdmin role does not authorize transactions on another customer account. Deposit, withdrawal, transfer, finalization, reversal, and installment-payment ownership are enforced by the API and SQL procedures.</div>${accounts.map((account) => `<div class="account-mini"><strong>${UI().escapeHtml(account.AccountNumber || '')}</strong><span>${UI().formatMoney(account.Balance || 0)}</span>${UI().statusBadge(account.AccountStatus || 'Active')}</div>`).join('') || UI().emptyState('No personal accounts', 'Open a personal account before creating a transaction.')}`)}</div></div>`
    },

    staffOwnLoans: {
      actions: () => `${actionButton('pay-installment', 'Pay my installment', 'money')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => ({ loans: rows(await API().get('/api/loans', { scope: 'mine', pageSize: 200 })) }),
      render: ({ loans }) => `<div class="content-grid"><div class="span-8">${card('My personal loans', UI().renderTable(loans, {
        hide: ['CustomerID'],
        maxColumns: 12,
        actions: (loan) => smallAction('lookup-loan', 'Status & installments', 'eye', `data-id="${loan.LoanID}" data-scope="mine"`)
      }))}</div><div class="span-4">${card('Borrower-only payment', `<div class="alert alert-info">Only the borrower may pay an installment, even when the same login also has Employee, Admin, or HighAdmin privileges.</div><div class="form-actions">${actionButton('pay-installment', 'Pay my installment', 'money')}</div>`)}</div></div>`
    },

    staffLoans: {
      actions: (state) => `${actionButton('create-loan', 'Create loan', 'plus')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')} ${roleAtLeast(state, 'Admin') ? actionButton('process-overdue', state.config.role === 'HighAdmin' ? 'Process overdue' : 'Process branch overdue', 'clock', 'btn-secondary') : ''}`,
      load: async () => {
        const response = await API().get('/api/loans', { pageSize: 200 });
        return { loans: rows(response), meta: response.meta || {} };
      },
      render: ({ loans, meta }) => card(meta?.accessScope === 'all' ? 'All bank loans' : 'Current branch loans', `<div class="alert alert-info"><strong>Read-only loan servicing view.</strong> Employees and branch managers can inspect only loans and installment schedules from their current branch. HighAdmin can inspect every branch. Payments are available only in My loans.</div>${UI().renderTable(loans, {
        hide: ['StartDate'],
        maxColumns: 12,
        actions: (loan) => smallAction('lookup-loan', 'Status & installments', 'eye', `data-id="${loan.LoanID}" data-scope="viewable"`)
      })}`)
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
      actions: (state) => {
        if (state.config.role === 'Employee') {
          return actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary');
        }

        const filters = filterTools(
          'employee-filters',
          'clear-employee-filters',
          Boolean(Object.keys(state.filters.employees || {}).length)
        );

        if (state.config.role === 'HighAdmin') {
          return filters;
        }

        return `${actionButton('hire-employee', 'Hire employee', 'userPlus')} ${filters}`;
      },
      load: async (state) => {
        const filters = { includeTerminated: true, ...cleanObject(state.filters.employees || {}) };
        return { filters, employees: rows(await API().get('/api/employees', filters)) };
      },
      render: ({ filters, employees }, state) => `${state.config.role === 'Employee' ? '' : UI().filterSummary(filters)}${card(employeeDirectoryTitle(state), `${employeeDirectoryNotice(state)}${UI().renderTable(employees, {
        hide: ['Phone', 'Email', 'HireDate'],
        maxColumns: 11,
        actions: (employee) => `${smallAction('employee-details', 'View', 'eye', `data-id="${employee.EmployeeID}"`)}${canManageEmployee(state, employee) ? `${smallAction('change-job', 'Job title', 'briefcase', `data-id="${employee.EmployeeID}"`)}${smallAction('employee-more', 'Manage', 'settings', `data-row="${encodeRow(employee)}"`)}` : ''}`
      })}`)}`
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
      render: (_, state) => `<div class="content-grid"><div class="span-4">${card('Transaction maintenance', `<p class="muted">Finalize pending transactions whose ready time has been reached. This does not authorize staff to initiate customer transactions.</p>${actionButton('process-pending', 'Process pending batch', 'refresh')}`)}</div><div class="span-4">${card('Loan maintenance', `<p class="muted">${state.config.role === 'HighAdmin' ? 'Process all branches or select one branch.' : 'Manually process only overdue installments from your current branch.'}</p>${actionButton('process-overdue', state.config.role === 'HighAdmin' ? 'Process overdue installments' : 'Process my branch overdue', 'clock')}`)}</div><div class="span-4">${card('Account maintenance', `<p class="muted">Apply monthly interest or mark long-inactive accounts dormant.</p><div class="maintenance-buttons">${actionButton('apply-interest', 'Apply monthly interest', 'money')}${actionButton('dormant-sweep', 'Dormant sweep', 'clock', 'btn-secondary')}</div>`)}</div></div><div class="section-spacer">${card('Safety notice', `<div class="alert alert-warning"><strong>These are maintenance operations.</strong><br>${state.config.role === 'HighAdmin' ? 'HighAdmin may operate across all branches.' : 'The overdue-loan action is restricted by the backend and stored procedure to your active branch.'}</div>`)}</div>`
    },

    executiveOverview: {
      actions: () => `${actionButton('view-report', 'Branch financial report', 'reports', 'btn-secondary', 'data-report="highadmin-branch-financial-overview"')} ${actionButton('refresh-section', 'Refresh', 'refresh', 'btn-secondary')}`,
      load: async () => {
        const [branchesPayload, employeesPayload, customersPayload, financialPayload] = await Promise.all([
          safeGet('/api/branches'),
          safeGet('/api/employees', { includeTerminated: true }),
          safeGet('/api/customers', { includeInactive: true }),
          safeGet('/api/reports/highadmin-branch-financial-overview', { page: 1, pageSize: 30 })
        ]);
        const branches = rows(branchesPayload);
        return {
          branches,
          employees: rows(employeesPayload),
          customers: rows(customersPayload),
          totalAccounts: branches.reduce((sum, branch) => sum + Number(branch.TotalAccountCount || 0), 0),
          activeAccounts: branches.reduce((sum, branch) => sum + Number(branch.ActiveAccountCount || 0), 0),
          financial: rows(financialPayload)
        };
      },
      render: (data) => `<div class="stat-grid">
        ${UI().statCard('Branch network', data.branches.length, 'Operating units', 'building')}
        ${UI().statCard('Workforce', data.employees.length, `${countStatus(data.employees, /active|working/i)} active`, 'users', 'var(--blue-500)', 'rgba(59,130,246,.12)')}
        ${UI().statCard('Customer base', data.customers.length, 'Registered customers', 'userPlus', 'var(--violet-500)', 'rgba(139,92,246,.12)')}
        ${UI().statCard('Managed accounts', data.totalAccounts, `${data.activeAccounts} active`, 'wallet', 'var(--gold-500)', 'rgba(215,168,79,.15)')}
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
    const [branches, accountTypes] = await Promise.all([
      branchOptions(state),
      accountTypeOptions(state)
    ]);

    UI().openForm({
      title: 'Open bank account',
      submitText: 'Open account',
      intro: '<div class="alert alert-info">Choose a branch and account type from the available catalogues. The numeric IDs are submitted automatically.</div>',
      fields: [
        selectOrNumber('branchID', 'Branch', branches, true, '', 'Select the branch where the account will be opened.'),
        selectOrNumber('accountTypeID', 'Account type', accountTypes, true, '', 'Select the required account product.'),
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

  async function showAccountHistory(accountID, fromDate, toDate, scope = 'viewable') {
    const params = cleanObject({ fromDate, toDate, scope: scope === 'mine' ? 'mine' : undefined });
    const response = await API().get(`/api/accounts/${accountID}/history`, params);
    UI().openModal({
      title: `Account ${accountID} history`,
      size: 'lg',
      content: `<div class="alert alert-info"><strong>Local time display:</strong> Transaction Date is when the transaction was created. Ready To Complete At is the scheduled processing time and may be later. Existing sample records keep their seeded historical dates.</div>${UI().renderTable(rows(response), { maxColumns: 12, dateFields: response.meta?.dateFields || {} })}<div class="form-actions"><button class="btn btn-secondary" data-action="account-history-filter" data-id="${accountID}" data-scope="${scope}">${icon('filter', 16)} Filter dates</button><button class="btn btn-secondary" data-action="export-account-history" data-id="${accountID}">${icon('download', 16)} Export CSV</button></div>`
    });
    const state = window.BankWorkspace.getState();
    state.activeAccountHistory = { accountID, rows: rows(response), fromDate, toDate, scope, dateFields: response.meta?.dateFields || {} };
  }

  async function lookupLoan(loanID, scope = 'viewable') {
    const response = await API().get(`/api/loans/${loanID}/status`, scope === 'mine' ? { scope: 'mine' } : undefined);
    showPayload(`Loan ${loanID} status`, response, ['Loan summary', 'Installment schedule']);
  }

  async function viewReport(reportKey, page = 1, pageSize = 50) {
    const response = await API().get(`/api/reports/${reportKey}`, { page, pageSize });
    const reportRows = rows(response);
    const state = window.BankWorkspace.getState();
    const dateFields = response.meta?.dateFields || {};
    state.activeReport = { key: reportKey, page, pageSize, rows: reportRows, meta: response.meta || {}, dateFields };
    const hasNext = reportRows.length === pageSize;
    UI().openModal({
      title: UI().humanize(reportKey),
      size: 'lg',
      content: `<div class="report-meta"><span>Page ${page}</span><span>${reportRows.length} row${reportRows.length === 1 ? '' : 's'}</span><span>${response.meta?.sort === 'newest-first' ? 'Newest first' : 'Sorted by report definition'}</span><span>Dates use your browser locale</span><span>${UI().escapeHtml(response.meta?.view || '')}</span></div>${UI().renderTable(reportRows, { maxColumns: 14, dateFields })}`,
      footer: `<div class="report-footer"><button class="btn btn-secondary" data-action="report-page" data-report="${reportKey}" data-page="${Math.max(1, page - 1)}" ${page <= 1 ? 'disabled' : ''}>${icon('arrow', 14, 'icon-reverse')} Previous</button><button class="btn btn-secondary" data-action="export-current-report">${icon('download', 15)} Export CSV</button><button class="btn btn-primary" data-action="report-page" data-report="${reportKey}" data-page="${page + 1}" ${hasNext ? '' : 'disabled'}>Next ${icon('arrow', 14)}</button></div>`
    });
  }

  const actions = {
    'open-account': async ({ state, refresh }) => openAccountForm(state, refresh),

    'view-account': async ({ element }) => {
      const scope = element.dataset.scope === 'mine' ? 'mine' : 'viewable';
      const response = await API().get(`/api/accounts/${element.dataset.id}`, scope === 'mine' ? { scope: 'mine' } : undefined);
      UI().openModal({ title: `Account ${element.dataset.id}`, size: 'lg', content: UI().keyValue(response.data) });
    },

    'account-history': async ({ element }) => showAccountHistory(element.dataset.id, undefined, undefined, element.dataset.scope === 'mine' ? 'mine' : 'viewable'),

    'account-history-filter': async ({ element }) => {
      const current = window.BankWorkspace.getState().activeAccountHistory || {};
      UI().openForm({
        title: 'Filter account history',
        submitText: 'Apply dates',
        fields: [
          { name: 'fromDate', label: 'From date', type: 'date', value: current.fromDate || '' },
          { name: 'toDate', label: 'To date', type: 'date', value: current.toDate || '' }
        ],
        onSubmit: async (data) => showAccountHistory(element.dataset.id, data.fromDate, data.toDate, element.dataset.scope || current.scope || 'viewable')
      });
    },

    'export-account-history': async () => {
      const current = window.BankWorkspace.getState().activeAccountHistory;
      UI().downloadCSV(current?.rows || [], `account-${current?.accountID || 'history'}-history.csv`, { dateFields: current?.dateFields || {} });
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
      const status = String(account.AccountStatus || '').toLowerCase();
      const canFreeze = status !== 'frozen' && status !== 'closed';
      const canUnfreeze = isAdmin && status === 'frozen';
      const canChangeType = status === 'active' || status === 'dormant';
      const canClose = status !== 'closed' && status !== 'frozen';
      const availableActions = [
        canFreeze ? `<button class="quick-action" data-action="freeze-account" data-id="${accountID}">${icon('lock', 21)}<strong>Freeze</strong><span>Restrict financial operations</span></button>` : '',
        canUnfreeze ? `<button class="quick-action" data-action="unfreeze-account" data-id="${accountID}">${icon('refresh', 21)}<strong>Unfreeze</strong><span>Restore an eligible account</span></button>` : '',
        canChangeType ? `<button class="quick-action" data-action="change-account-type" data-id="${accountID}">${icon('card', 21)}<strong>Change type</strong><span>Move to another account type</span></button>` : '',
        canClose ? `<button class="quick-action" data-action="close-account" data-id="${accountID}">${icon('trash', 21)}<strong>Close account</strong><span>Close an eligible account</span></button>` : ''
      ].filter(Boolean).join('');
      UI().openModal({
        title: `Manage account ${account.AccountNumber || accountID}`,
        content: availableActions
          ? `<div class="alert alert-info">These are account-management operations, not financial transactions. Branch scope and role authorization are enforced by the backend.</div><div class="quick-actions section-spacer">${availableActions}</div>`
          : UI().emptyState('No eligible actions', 'The current account status does not allow another management action for your role.')
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
        intro: '<div class="alert alert-info">Only accounts in your personal portfolio are available. Staff roles do not permit deposits into another customer account.</div>',
        fields: [
          selectOrNumber('accountID', 'My destination account', accounts, true),
          moneyField('amount', 'Amount'),
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
        intro: '<div class="alert alert-info">Only accounts owned by the CustomerID linked to your login are available.</div>',
        fields: [
          selectOrNumber('accountID', 'My source account', accounts, true),
          moneyField('amount', 'Amount'),
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
        intro: '<div class="alert alert-info">The source must be one of your personal accounts. Enter the receiving AccountID manually; the receiving account may belong to another customer.</div>',
        fields: [
          selectOrNumber('fromAccountID', 'My source account', accounts, true),
          numberField('toAccountID', 'Destination Account ID', true, '', 'Enter the receiving account ID.'),
          moneyField('amount', 'Amount'),
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
      const scope = element.dataset.scope === 'mine' ? 'mine' : 'viewable';
      if (element.dataset.id) return lookupLoan(element.dataset.id, scope);
      UI().openForm({
        title: 'Find loan',
        submitText: 'View status',
        fields: [numberField('loanID', 'Loan ID')],
        onSubmit: async (data) => lookupLoan(data.loanID, scope)
      });
    },

    'create-loan': async ({ state, refresh }) => {
      const customers = await customerOptions(state);
      const isHighAdmin = state.config.role === 'HighAdmin';
      const branches = isHighAdmin ? await branchOptions(state) : [];
      UI().openForm({
        title: 'Create loan',
        submitText: 'Create loan',
        size: 'lg',
        intro: isHighAdmin
          ? '<div class="alert alert-info">HighAdmin may create a loan for any branch.</div>'
          : `<div class="alert alert-info">This loan will be created for your current branch: <strong>${UI().escapeHtml(state.user?.CurrentBranchName || state.user?.CurrentBranchID || 'Unassigned')}</strong>.</div>`,
        fields: [
          selectOrNumber('customerID', 'Customer', customers, true),
          isHighAdmin
            ? selectOrNumber('branchID', 'Branch', branches, true)
            : { name: 'branchID', type: 'hidden', value: state.user?.CurrentBranchID || '' },
          moneyField('loanAmount', 'Loan amount'),
          { name: 'interestRate', label: 'Interest rate (%)', type: 'number', min: 0, step: '0.01', required: true },
          numberField('numberOfInstallments', 'Number of installments'),
          { name: 'startDate', label: 'Start date', type: 'date' }
        ],
        onSubmit: async (data) => {
          const response = await API().post('/api/loans', data);
          await success(state, refresh, `Loan ${response.data?.LoanID || ''} was created.`, 'Loan created', { loanID: response.data?.LoanID, customerID: data.customerID, amount: data.loanAmount, branchID: data.branchID });
        }
      });
    },

    'pay-installment': async ({ state, refresh }) => {
      const accounts = await accountOptions(state, false);
      UI().openForm({
        title: 'Pay loan installment',
        submitText: 'Create payment',
        intro: '<div class="alert alert-info">Only the borrower may pay an installment, and the source account must belong to the same borrower.</div>',
        fields: [
          numberField('installmentID', 'Installment ID'),
          selectOrNumber('fromAccountID', 'My source account', accounts, true)
        ],
        onSubmit: async (data) => {
          const installmentID = data.installmentID;
          delete data.installmentID;
          const response = await API().post(`/api/loans/installments/${installmentID}/pay`, data);
          await success(state, refresh, `Installment payment transaction ${response.data?.TransactionID || ''} was created.`, 'Loan installment payment created', { installmentID, transactionID: response.data?.TransactionID, accountID: data.fromAccountID });
        }
      });
    },

    'process-overdue': async ({ state, refresh }) => {
      if (state.config.role === 'HighAdmin') {
        const branches = await branchOptions(state);
        return UI().openForm({
          title: 'Process overdue installments',
          submitText: 'Process overdue',
          intro: '<div class="alert alert-warning">Leave Branch empty to process all branches, or select one branch for a targeted manual run.</div>',
          fields: [selectOrNumber('branchID', 'Branch (optional)', branches, false)],
          onSubmit: async (data) => {
            const response = await API().post('/api/loans/maintenance/process-overdue-installments', cleanObject(data));
            showPayload('Overdue processing result', response);
            await success(state, refresh, 'Overdue installments were processed.', 'Overdue installments processed', { branchID: data.branchID || 'ALL' });
          }
        });
      }

      return UI().confirmAction({
        title: 'Process current branch overdue installments',
        message: `Run overdue processing for ${state.user?.CurrentBranchName || `Branch ${state.user?.CurrentBranchID || ''}`}? The backend and stored procedure reject access to other branches.`,
        confirmText: 'Process my branch',
        onConfirm: async () => {
          const response = await API().post('/api/loans/maintenance/process-overdue-installments');
          showPayload('Branch overdue processing result', response);
          await success(state, refresh, 'Current-branch overdue installments were processed.', 'Branch overdue installments processed', { branchID: state.user?.CurrentBranchID });
        }
      });
    },

    'view-branch': async ({ element }) => {
      const response = await API().get(`/api/branches/${element.dataset.id}`);
      UI().openModal({ title: `Branch ${element.dataset.id}`, size: 'lg', content: UI().keyValue(response.data) });
    },

    'employee-filters': async ({ state, refresh }) => {
      const current = state.filters.employees || {};
      const fields = [
        numberField('employeeID', 'Employee ID', false, current.employeeID || ''),
        { name: 'nameSearch', label: 'Name contains', value: current.nameSearch || '' },
        { name: 'nationalID', label: 'National ID', value: current.nationalID || '' },
        { name: 'jobTitle', label: 'Job title', value: current.jobTitle || '' },
        selectField('empStatus', 'Employment status', ['Active', 'OnLeave', 'Terminated'], false, current.empStatus || ''),
        selectField('includeTerminated', 'Include terminated', [option('true', 'Yes'), option('false', 'No')], false, String(current.includeTerminated ?? 'true'))
      ];

      if (state.config.role === 'HighAdmin') {
        fields.splice(5, 0,
          { name: 'branchCode', label: 'Branch code', value: current.branchCode || '' },
          selectField('workingStatus', 'Working status', ['Working', 'Transferred', 'Ended'], false, current.workingStatus || '')
        );
        fields.push(selectField('searchBranchHistory', 'Search branch history', [option('true', 'Yes'), option('false', 'No')], false, String(current.searchBranchHistory ?? 'false')));
      }

      UI().openForm({
        title: state.config.role === 'HighAdmin' ? 'Employee filters' : 'Current branch employee filters',
        submitText: 'Apply filters',
        size: 'lg',
        intro: state.config.role === 'Admin'
          ? '<div class="alert alert-info">Branch selection is fixed to your current branch and cannot be changed from the browser.</div>'
          : '',
        fields,
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
      const sets = recordsets(response);
      const target = sets.flat().find((row) => Number(row?.EmployeeID) === Number(element.dataset.id)) || sets.flat()[0] || {};
      const canManage = canManageEmployee(state, target);
      UI().openModal({
        title: `Employee ${element.dataset.id}`,
        size: 'lg',
        content: `${UI().renderRecordsets(sets, { titles: ['Employee details', 'Current branch assignment', 'Access details'] })}<div class="form-actions"><button class="btn btn-secondary" data-action="employee-branch-history" data-id="${element.dataset.id}">${icon('branch', 16)} Branch history</button>${canManage ? `<button class="btn btn-primary" data-action="create-employee-user" data-id="${element.dataset.id}">${icon('userPlus', 16)} Create login</button>` : ''}</div>`
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
      const status = String(employee.EmpStatus || employee.EmploymentStatus || '').toLowerCase();
      const suspensionAction = status === 'onleave'
        ? `<button class="quick-action" data-action="unsuspend-employee" data-id="${employee.EmployeeID}">${icon('check', 21)}<strong>Reactivate</strong><span>Reverse the latest suspension</span></button>`
        : status === 'terminated'
          ? ''
          : `<button class="quick-action" data-action="suspend-employee" data-id="${employee.EmployeeID}">${icon('alert', 21)}<strong>Suspend</strong><span>Set employee to OnLeave</span></button>`;
      UI().openModal({
        title: `Manage ${`${employee.FirstName || ''} ${employee.LastName || ''}`.trim() || `employee ${employee.EmployeeID}`}`,
        content: `<div class="quick-actions"><button class="quick-action" data-action="create-employee-user" data-id="${employee.EmployeeID}">${icon('userPlus', 21)}<strong>Create login</strong><span>Link application access</span></button><button class="quick-action" data-action="change-job" data-id="${employee.EmployeeID}">${icon('briefcase', 21)}<strong>Change title</strong><span>Update job assignment</span></button>${suspensionAction}<button class="quick-action" data-action="fire-employee" data-id="${employee.EmployeeID}">${icon('trash', 21)}<strong>Terminate</strong><span>End employment record</span></button></div>`
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

    'unsuspend-employee': async ({ element, state, refresh }) => UI().openForm({
      title: 'Reactivate employee',
      submitText: 'Reactivate',
      intro: '<div class="alert alert-info">Only the same manager or HighAdmin user who performed the latest suspension can reverse it.</div>',
      fields: [{ name: 'reason', label: 'Reason for reactivation', type: 'textarea', required: true, full: true }],
      onSubmit: async (data) => {
        await API().post(`/api/employees/${element.dataset.id}/unsuspend`, data);
        await success(state, refresh, 'Employee was restored to Active.', 'Employee reactivated', { employeeID: element.dataset.id });
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
      UI().downloadCSV(report?.rows || [], `${report?.key || 'bank-report'}-page-${report?.page || 1}.csv`, { dateFields: report?.dateFields || report?.meta?.dateFields || {} });
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
        title: 'Hire branch manager or vice manager',
        submitText: 'Hire manager',
        size: 'lg',
        intro: '<div class="alert alert-warning"><strong>Branch assignment is mandatory.</strong> The manager cannot be created without selecting a valid branch.</div><div class="alert alert-info">Manager hiring creates or reuses the person\'s customer identity and assigns Customer, Employee, and Admin roles. This is required by the current authentication model and enables the staff member\'s personal accounts and loans.</div>',
        fields: [
          selectOrNumber('branchID', 'Branch', branches, true, '', 'Required. The new manager will be assigned to this branch immediately.'),
          { name: 'username', label: 'Username', required: true, autocomplete: 'off' },
          { name: 'password', label: 'Temporary password', type: 'password', required: true, autocomplete: 'new-password' },
          { name: 'nationalID', label: 'National ID', required: true },
          { name: 'firstName', label: 'First name', required: true },
          { name: 'lastName', label: 'Last name', required: true },
          { name: 'birthDate', label: 'Birth date', type: 'date', required: true },
          { name: 'hireDate', label: 'Hire date', type: 'date' },
          selectField('jobTitle', 'Job title', [
            option('Branch Manager', 'Branch Manager'),
            option('Vice Manager', 'Vice Manager')
          ], true, 'Branch Manager', 'Only manager-level job titles are allowed here.'),
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
      const status = String(manager.EmpStatus || manager.EmploymentStatus || '').toLowerCase();
      const suspensionAction = status === 'onleave'
        ? `<button class="quick-action" data-action="unsuspend-manager" data-id="${manager.EmployeeID}">${icon('check', 21)}<strong>Reactivate</strong><span>Reverse the latest suspension</span></button>`
        : status === 'terminated'
          ? ''
          : `<button class="quick-action" data-action="suspend-manager" data-id="${manager.EmployeeID}">${icon('alert', 21)}<strong>Suspend</strong><span>Set manager to OnLeave</span></button>`;
      UI().openModal({
        title: `Manager actions · ${`${manager.FirstName || ''} ${manager.LastName || ''}`.trim() || manager.EmployeeID}`,
        content: `<div class="quick-actions"><button class="quick-action" data-action="employee-details" data-id="${manager.EmployeeID}">${icon('eye', 21)}<strong>View details</strong><span>Employee and branch records</span></button><button class="quick-action" data-action="downgrade-manager" data-id="${manager.EmployeeID}">${icon('briefcase', 21)}<strong>Downgrade</strong><span>Remove manager role and change title</span></button>${suspensionAction}<button class="quick-action" data-action="fire-manager" data-id="${manager.EmployeeID}">${icon('trash', 21)}<strong>Terminate</strong><span>End manager employment</span></button></div>`
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

    'unsuspend-manager': async ({ element, state, refresh }) => UI().openForm({
      title: 'Reactivate manager',
      submitText: 'Reactivate',
      intro: '<div class="alert alert-info">Only the same HighAdmin user who performed the latest suspension can reverse it. The Admin role is restored automatically.</div>',
      fields: [{ name: 'reason', label: 'Reason for reactivation', type: 'textarea', required: true, full: true }],
      onSubmit: async (data) => {
        await API().post(`/api/highadmin/managers/${element.dataset.id}/unsuspend`, data);
        await success(state, refresh, 'Manager was restored to Active.', 'Manager reactivated', { employeeID: element.dataset.id });
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
