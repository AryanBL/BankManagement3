const express = require('express');
const { TYPES, executeQuery } = require('../utils/procedure');
const { asyncHandler, ok, getPaging } = require('../utils/http');
const { authenticate } = require('../middleware/auth');
const { hasRole, httpError } = require('../utils/access-scope');

const router = express.Router();
router.use(authenticate());

/*
 * Every orderBy value and dateFields entry below is server-defined.
 * No client input is interpolated into SQL identifiers or ORDER BY clauses.
 * Date-bearing reports are ordered newest first. The frontend receives an
 * explicit date type map so SQL DATE and DATETIME values are rendered correctly.
 */
const REPORT_VIEWS = {
  'customer-basic-profile': {
    view: 'vw_CustomerBasicProfile', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'customer-account-link',
    orderBy: 'R.RegistrationDate DESC, R.CustomerID DESC',
    dateFields: { BirthDate: 'date', RegistrationDate: 'date' }
  },
  'customer-account-summary': {
    view: 'vw_CustomerAccountSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column',
    orderBy: 'R.OpenDate DESC, R.AccountID DESC',
    dateFields: { OpenDate: 'date', CloseDate: 'date' }
  },
  'account-operational-summary': {
    view: 'vw_AccountOperationalSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column',
    orderBy: 'R.OpenDate DESC, R.AccountID DESC',
    dateFields: { OpenDate: 'date', CloseDate: 'date' }
  },
  'employee-directory': {
    view: 'vw_EmployeeDirectory', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column',
    orderBy: 'R.HireDate DESC, R.EmployeeID DESC',
    dateFields: { HireDate: 'date', CurrentBranchStartDate: 'date' }
  },
  'pending-transactions': {
    view: 'vw_PendingTransactions', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'account-link',
    orderBy: 'R.TransactionDate DESC, R.TransactionID DESC',
    dateFields: { TransactionDate: 'datetime', ReadyToCompleteAt: 'datetime' }
  },
  'loan-operational-summary': {
    view: 'vw_LoanOperationalSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column',
    orderBy: 'R.StartDate DESC, R.LoanID DESC',
    dateFields: { StartDate: 'date', EndDate: 'date' }
  },
  'daily-transaction-summary': {
    view: 'vw_DailyTransactionSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'],
    orderBy: 'R.TransactionDay DESC, R.TransactionType ASC, R.TransactionStatus ASC',
    dateFields: { TransactionDay: 'date' }
  },
  'account-status-summary': {
    view: 'vw_AccountStatusSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'], branchMode: 'column',
    orderBy: 'R.BranchID DESC, R.AccountStatus ASC',
    dateFields: {}
  },
  'loan-overdue-summary': {
    view: 'vw_LoanOverdueSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'], branchMode: 'column',
    orderBy: 'R.OldestOverdueDueDate DESC, R.LoanID DESC',
    dateFields: { OldestOverdueDueDate: 'date' }
  },
  'highadmin-employee-branch-overview': {
    view: 'vw_HighAdmin_EmployeeBranchOverview', poolName: 'highadminReport', roles: ['HighAdmin'],
    orderBy: 'R.StartDate DESC, R.EMPBID DESC, R.EmployeeID DESC',
    dateFields: { HireDate: 'date', StartDate: 'date', EndDate: 'date' }
  },
  'highadmin-branch-financial-overview': {
    view: 'vw_HighAdmin_BranchFinancialOverview', poolName: 'highadminReport', roles: ['HighAdmin'],
    orderBy: 'R.BranchID DESC',
    dateFields: {}
  },
  'highadmin-user-access-overview': {
    view: 'vw_HighAdmin_UserAccessOverview', poolName: 'highadminReport', roles: ['HighAdmin'],
    orderBy: 'R.UserID DESC',
    dateFields: {}
  },
  'audit-trail': {
    view: 'vw_AuditTrail_Safe', poolName: 'audit', roles: ['HighAdmin'],
    orderBy: 'R.ActionDate DESC, R.AuditID DESC',
    dateFields: { ActionDate: 'datetime' }
  },
  'branch-ledger': {
    view: 'vw_BranchLedgerReport', poolName: 'audit', roles: ['HighAdmin'],
    orderBy: 'R.EntryDate DESC, R.BranchLedgerID DESC',
    dateFields: { EntryDate: 'datetime' }
  }
};

function reportBranchScope(req, report) {
  if (!report.branchMode || hasRole(req.user, 'HighAdmin')) return null;
  if (!hasRole(req.user, 'Employee') && !hasRole(req.user, 'Admin')) return null;
  if (!req.user.CurrentBranchID) {
    throw httpError(403, 'The current employee does not have an active branch assignment.');
  }
  return req.user.CurrentBranchID;
}

async function selectFromView(report, req) {
  const { page, pageSize, offset } = getPaging(req);
  const branchID = reportBranchScope(req, report);
  let queryText;

  if (report.branchMode === 'account-link' && branchID) {
    queryText = `
      SELECT R.*
      FROM dbo.${report.view} AS R
      WHERE EXISTS
      (
        SELECT 1
        FROM dbo.vw_AccountOperationalSummary AS A
        WHERE A.BranchID = @BranchID
          AND (A.AccountID = R.FromAccountID OR A.AccountID = R.ToAccountID)
      )
      ORDER BY ${report.orderBy}
      OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`;
  } else if (report.branchMode === 'customer-account-link' && branchID) {
    queryText = `
      SELECT R.*
      FROM dbo.${report.view} AS R
      WHERE EXISTS
      (
        SELECT 1
        FROM dbo.vw_AccountOperationalSummary AS A
        WHERE A.CustomerID = R.CustomerID
          AND A.BranchID = @BranchID
      )
      ORDER BY ${report.orderBy}
      OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`;
  } else if (report.branchMode === 'column' && branchID) {
    queryText = `
      SELECT R.*
      FROM dbo.${report.view} AS R
      WHERE R.BranchID = @BranchID
      ORDER BY ${report.orderBy}
      OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`;
  } else {
    queryText = `
      SELECT R.*
      FROM dbo.${report.view} AS R
      ORDER BY ${report.orderBy}
      OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`;
  }

  const inputs = {
    Offset: TYPES.int,
    PageSize: TYPES.int
  };
  const values = {
    Offset: offset,
    PageSize: pageSize
  };

  if (branchID) {
    inputs.BranchID = TYPES.int;
    values.BranchID = branchID;
  }

  const result = await executeQuery(queryText, {
    poolName: report.poolName,
    inputs,
    values
  });

  return { rows: result.recordset, page, pageSize, branchID };
}

router.get('/', asyncHandler(async (req, res) => {
  ok(res, {
    data: Object.keys(REPORT_VIEWS).map((key) => ({
      key,
      url: `/api/reports/${key}`,
      requiredRoles: REPORT_VIEWS[key].roles,
      branchScopedForStaff: Boolean(REPORT_VIEWS[key].branchMode),
      defaultSort: 'newest-first',
      dateFields: REPORT_VIEWS[key].dateFields
    }))
  });
}));

router.get('/:reportKey', asyncHandler(async (req, res) => {
  const report = REPORT_VIEWS[req.params.reportKey];
  if (!report) {
    return res.status(404).json({ success: false, error: { message: 'Unknown report key.' } });
  }

  const roles = req.user.roles || [];
  const allowed = report.roles.some((role) => roles.includes(role));
  if (!allowed) {
    return res.status(403).json({ success: false, error: { message: `Access denied. Required role: ${report.roles.join(' or ')}` } });
  }

  const data = await selectFromView(report, req);
  return ok(res, {
    data: data.rows,
    meta: {
      page: data.page,
      pageSize: data.pageSize,
      view: report.view,
      sort: 'newest-first',
      accessScope: data.branchID ? 'branch' : 'all',
      branchID: data.branchID || null,
      dateFields: report.dateFields
    }
  });
}));

module.exports = router;
