const express = require('express');
const { TYPES, executeQuery } = require('../utils/procedure');
const { asyncHandler, ok, getPaging } = require('../utils/http');
const { authenticate } = require('../middleware/auth');
const { hasRole, httpError } = require('../utils/access-scope');

const router = express.Router();
router.use(authenticate());

const REPORT_VIEWS = {
  'customer-basic-profile': { view: 'vw_CustomerBasicProfile', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'] },
  'customer-account-summary': { view: 'vw_CustomerAccountSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column' },
  'account-operational-summary': { view: 'vw_AccountOperationalSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column' },
  'employee-directory': { view: 'vw_EmployeeDirectory', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column' },
  'pending-transactions': { view: 'vw_PendingTransactions', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'account-link' },
  'loan-operational-summary': { view: 'vw_LoanOperationalSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'], branchMode: 'column' },
  'daily-transaction-summary': { view: 'vw_DailyTransactionSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'] },
  'account-status-summary': { view: 'vw_AccountStatusSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'], branchMode: 'column' },
  'loan-overdue-summary': { view: 'vw_LoanOverdueSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'], branchMode: 'column' },
  'highadmin-employee-branch-overview': { view: 'vw_HighAdmin_EmployeeBranchOverview', poolName: 'highadminReport', roles: ['HighAdmin'] },
  'highadmin-branch-financial-overview': { view: 'vw_HighAdmin_BranchFinancialOverview', poolName: 'highadminReport', roles: ['HighAdmin'] },
  'highadmin-user-access-overview': { view: 'vw_HighAdmin_UserAccessOverview', poolName: 'highadminReport', roles: ['HighAdmin'] },
  'audit-trail': { view: 'vw_AuditTrail_Safe', poolName: 'audit', roles: ['HighAdmin'] },
  'branch-ledger': { view: 'vw_BranchLedgerReport', poolName: 'audit', roles: ['HighAdmin'] }
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
      SELECT P.*
      FROM dbo.${report.view} AS P
      WHERE EXISTS
      (
        SELECT 1
        FROM dbo.vw_AccountOperationalSummary AS A
        WHERE A.BranchID = @BranchID
          AND (A.AccountID = P.FromAccountID OR A.AccountID = P.ToAccountID)
      )
      ORDER BY 1
      OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`;
  } else if (report.branchMode === 'column' && branchID) {
    queryText = `
      SELECT *
      FROM dbo.${report.view}
      WHERE BranchID = @BranchID
      ORDER BY 1
      OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`;
  } else {
    queryText = `
      SELECT *
      FROM dbo.${report.view}
      ORDER BY 1
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
      branchScopedForStaff: Boolean(REPORT_VIEWS[key].branchMode)
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
      accessScope: data.branchID ? 'branch' : 'all',
      branchID: data.branchID || null
    }
  });
}));

module.exports = router;
