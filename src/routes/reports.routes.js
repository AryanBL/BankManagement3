const express = require('express');
const { TYPES, executeQuery } = require('../utils/procedure');
const { asyncHandler, ok, getPaging } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate());

const REPORT_VIEWS = {
  'customer-basic-profile': { view: 'vw_CustomerBasicProfile', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'] },
  'customer-account-summary': { view: 'vw_CustomerAccountSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'] },
  'account-operational-summary': { view: 'vw_AccountOperationalSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'] },
  'employee-directory': { view: 'vw_EmployeeDirectory', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'] },
  'pending-transactions': { view: 'vw_PendingTransactions', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'] },
  'loan-operational-summary': { view: 'vw_LoanOperationalSummary', poolName: 'report', roles: ['Employee', 'Admin', 'HighAdmin'] },
  'daily-transaction-summary': { view: 'vw_DailyTransactionSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'] },
  'account-status-summary': { view: 'vw_AccountStatusSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'] },
  'loan-overdue-summary': { view: 'vw_LoanOverdueSummary', poolName: 'report', roles: ['Admin', 'HighAdmin'] },
  'highadmin-employee-branch-overview': { view: 'vw_HighAdmin_EmployeeBranchOverview', poolName: 'highadminReport', roles: ['HighAdmin'] },
  'highadmin-branch-financial-overview': { view: 'vw_HighAdmin_BranchFinancialOverview', poolName: 'highadminReport', roles: ['HighAdmin'] },
  'highadmin-user-access-overview': { view: 'vw_HighAdmin_UserAccessOverview', poolName: 'highadminReport', roles: ['HighAdmin'] },
  'audit-trail': { view: 'vw_AuditTrail_Safe', poolName: 'audit', roles: ['HighAdmin'] },
  'branch-ledger': { view: 'vw_BranchLedgerReport', poolName: 'audit', roles: ['HighAdmin'] }
};

async function selectFromView(view, poolName, req) {
  const { page, pageSize, offset } = getPaging(req);
  const result = await executeQuery(
    `SELECT * FROM dbo.${view} ORDER BY 1 OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`,
    {
      poolName,
      inputs: {
        Offset: TYPES.int,
        PageSize: TYPES.int
      },
      values: {
        Offset: offset,
        PageSize: pageSize
      }
    }
  );
  return { rows: result.recordset, page, pageSize };
}

router.get('/', asyncHandler(async (req, res) => {
  ok(res, {
    data: Object.keys(REPORT_VIEWS).map((key) => ({
      key,
      url: `/api/reports/${key}`,
      requiredRoles: REPORT_VIEWS[key].roles
    }))
  });
}));

router.get('/:reportKey', asyncHandler(async (req, res, next) => {
  const report = REPORT_VIEWS[req.params.reportKey];
  if (!report) {
    return res.status(404).json({ success: false, error: { message: 'Unknown report key.' } });
  }

  const roles = req.user.roles || [];
  const allowed = report.roles.some((role) => roles.includes(role));
  if (!allowed) {
    return res.status(403).json({ success: false, error: { message: `Access denied. Required role: ${report.roles.join(' or ')}` } });
  }

  const data = await selectFromView(report.view, report.poolName, req);
  return ok(res, { data: data.rows, meta: { page: data.page, pageSize: data.pageSize, view: report.view } });
}));

module.exports = router;
