const { TYPES, executeProcedure } = require('./procedure');

const ACCOUNT_SEARCH_INPUTS = {
  UserID: TYPES.int,
  AccountID: [TYPES.int, 'accountID'],
  AccountNumber: [TYPES.string30, 'accountNumber'],
  AccountNumberSearch: [TYPES.string30, 'accountNumberSearch'],
  CustomerID: [TYPES.int, 'customerID'],
  CustomerNationalID: [TYPES.string20, 'customerNationalID'],
  CustomerNameSearch: [TYPES.string100, 'customerNameSearch'],
  BranchID: [TYPES.int, 'branchID'],
  BranchCode: [TYPES.string20, 'branchCode'],
  AccountTypeID: [TYPES.int, 'accountTypeID'],
  AccountTypeName: [TYPES.string50, 'accountTypeName'],
  AccountStatus: [TYPES.string20, 'accountStatus'],
  MinBalance: [TYPES.money, 'minBalance'],
  MaxBalance: [TYPES.money, 'maxBalance'],
  IncludeClosed: [TYPES.bit, 'includeClosed']
};

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function hasRole(user, role) {
  return Array.isArray(user?.roles) && user.roles.includes(role);
}

function resolveAccessScope(req, requestedScope = 'viewable') {
  if (requestedScope === 'mine') {
    return {
      mode: 'mine',
      customerID: req.user.CustomerID,
      branchID: null
    };
  }

  if (hasRole(req.user, 'HighAdmin')) {
    return { mode: 'all', customerID: null, branchID: null };
  }

  if (hasRole(req.user, 'Employee') || hasRole(req.user, 'Admin')) {
    if (!req.user.CurrentBranchID) {
      throw httpError(403, 'The current employee does not have an active branch assignment.');
    }
    return {
      mode: 'branch',
      customerID: null,
      branchID: req.user.CurrentBranchID
    };
  }

  return {
    mode: 'mine',
    customerID: req.user.CustomerID,
    branchID: null
  };
}

function applyAccountScope(req, filters = {}, requestedScope = 'viewable') {
  const scope = resolveAccessScope(req, requestedScope);
  const values = { ...filters };
  delete values.scope;

  if (scope.mode === 'mine') {
    values.customerID = scope.customerID;
  } else if (scope.mode === 'branch') {
    values.branchID = scope.branchID;
  }

  return { scope, values };
}

async function searchAccounts(req, filters = {}, requestedScope = 'viewable') {
  const { scope, values } = applyAccountScope(req, filters, requestedScope);
  const result = await executeProcedure('dbo.sp_Account_Search', {
    inputs: ACCOUNT_SEARCH_INPUTS,
    values: { ...values, UserID: req.user.UserID }
  });
  return { scope, rows: result.recordset };
}

async function assertAccountVisible(req, accountID, requestedScope = 'viewable') {
  const result = await searchAccounts(req, {
    accountID,
    includeClosed: true
  }, requestedScope);

  const account = result.rows[0];
  if (!account) {
    const message = requestedScope === 'mine'
      ? 'Only the account owner can access this personal account operation.'
      : result.scope.mode === 'branch'
        ? 'This account is outside the employee current-branch access scope.'
        : 'Account was not found or is not accessible.';
    throw httpError(403, message);
  }

  return account;
}

async function assertAccountOwner(req, accountID) {
  return assertAccountVisible(req, accountID, 'mine');
}

module.exports = {
  ACCOUNT_SEARCH_INPUTS,
  hasRole,
  resolveAccessScope,
  applyAccountScope,
  searchAccounts,
  assertAccountVisible,
  assertAccountOwner,
  httpError
};
