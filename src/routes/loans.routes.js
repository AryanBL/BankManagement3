const express = require('express');
const { TYPES, executeProcedure, executeQuery } = require('../utils/procedure');
const { asyncHandler, ok, created, getPaging } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');
const { hasRole, resolveAccessScope, assertAccountOwner, httpError } = require('../utils/access-scope');

const router = express.Router();
router.use(authenticate());

function resolveLoanScope(req, requestedScope = 'viewable') {
  return resolveAccessScope(req, requestedScope);
}

async function queryLoans(req, requestedScope = 'viewable', extraFilters = {}) {
  const scope = resolveLoanScope(req, requestedScope);
  const { page, pageSize, offset } = getPaging(req);

  const forcedCustomerID = scope.mode === 'mine' ? scope.customerID : null;
  const forcedBranchID = scope.mode === 'branch' ? scope.branchID : null;

  const values = {
    LoanID: extraFilters.loanID ?? req.query.loanID,
    CustomerID: forcedCustomerID ?? extraFilters.customerID ?? req.query.customerID,
    BranchID: forcedBranchID ?? extraFilters.branchID ?? req.query.branchID,
    LoanStatus: extraFilters.loanStatus ?? req.query.loanStatus,
    Offset: offset,
    PageSize: pageSize
  };

  const result = await executeQuery(
    `SELECT *
     FROM dbo.vw_LoanOperationalSummary
     WHERE (@LoanID IS NULL OR LoanID = @LoanID)
       AND (@CustomerID IS NULL OR CustomerID = @CustomerID)
       AND (@BranchID IS NULL OR BranchID = @BranchID)
       AND (@LoanStatus IS NULL OR LoanStatus = @LoanStatus)
     ORDER BY LoanID DESC
     OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;`,
    {
      inputs: {
        LoanID: TYPES.int,
        CustomerID: TYPES.int,
        BranchID: TYPES.int,
        LoanStatus: TYPES.string20,
        Offset: TYPES.int,
        PageSize: TYPES.int
      },
      values
    }
  );

  return {
    scope,
    rows: result.recordset,
    page,
    pageSize
  };
}

async function assertLoanVisible(req, loanID, requestedScope = 'viewable') {
  const result = await queryLoans(req, requestedScope, { loanID });
  const loan = result.rows[0];
  if (!loan) {
    const message = requestedScope === 'mine'
      ? 'Only the borrower can access this personal loan.'
      : result.scope.mode === 'branch'
        ? 'This loan is outside the employee current-branch access scope.'
        : 'Loan was not found or is not accessible.';
    throw httpError(403, message);
  }
  return loan;
}

/*
 * Loan listing:
 * - ?scope=mine: authenticated user's own loans
 * - default Customer: own loans
 * - default Employee/Admin: current branch loans
 * - default HighAdmin: all loans
 */
router.get('/', asyncHandler(async (req, res) => {
  const requestedScope = String(req.query.scope || '').toLowerCase() === 'mine' ? 'mine' : 'viewable';
  const result = await queryLoans(req, requestedScope);
  ok(res, {
    data: result.rows,
    meta: {
      page: result.page,
      pageSize: result.pageSize,
      accessScope: result.scope.mode,
      branchID: result.scope.branchID || null
    }
  });
}));

router.post('/', authorize('Employee', 'Admin', 'HighAdmin'), requireBodyFields(['customerID', 'branchID', 'loanAmount', 'interestRate', 'numberOfInstallments']), asyncHandler(async (req, res) => {
  const isHighAdmin = hasRole(req.user, 'HighAdmin');
  const branchID = isHighAdmin ? req.body.branchID : req.user.CurrentBranchID;

  if (!branchID) {
    throw httpError(403, 'The current employee does not have an active branch assignment.');
  }

  if (!isHighAdmin && String(req.body.branchID) !== String(branchID)) {
    throw httpError(403, 'Employees and branch managers can create loans only for their current branch.');
  }

  const result = await executeProcedure('dbo.sp_Loan_Create', {
    inputs: {
      CustomerID: [TYPES.int, 'customerID'],
      BranchID: [TYPES.int, 'branchID'],
      LoanAmount: [TYPES.money, 'loanAmount'],
      InterestRate: [TYPES.percent, 'interestRate'],
      NumberOfInstallments: [TYPES.int, 'numberOfInstallments'],
      StartDate: [TYPES.date, 'startDate'],
      UserID: TYPES.int
    },
    outputs: { LoanID: TYPES.int },
    values: { ...req.body, branchID, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.get('/:loanID/status', asyncHandler(async (req, res) => {
  const requestedScope = String(req.query.scope || '').toLowerCase() === 'mine' ? 'mine' : 'viewable';
  await assertLoanVisible(req, req.params.loanID, requestedScope);

  const result = await executeProcedure('dbo.sp_Loan_GetStatus', {
    inputs: {
      LoanID: TYPES.int,
      UserID: TYPES.int
    },
    values: { LoanID: req.params.loanID, UserID: req.user.UserID }
  });
  ok(res, {
    data: result.recordsets.length > 1 ? result.recordsets : result.recordset,
    meta: { accessScope: requestedScope }
  });
}));

/* The paying account and the loan must both belong to the authenticated borrower. */
router.post('/installments/:installmentID/pay', requireBodyFields(['fromAccountID']), asyncHandler(async (req, res) => {
  await assertAccountOwner(req, req.body.fromAccountID);

  const result = await executeProcedure('dbo.sp_Loan_PayInstallment', {
    inputs: {
      InstallmentID: TYPES.int,
      FromAccountID: [TYPES.int, 'fromAccountID'],
      EmployeeID: [TYPES.int, 'employeeID'],
      UserID: TYPES.int
    },
    outputs: {
      TransactionID: TYPES.int,
      ReadyToCompleteAt: TYPES.datetime
    },
    values: {
      ...req.body,
      InstallmentID: req.params.installmentID,
      EmployeeID: req.user.EmployeeID || null,
      UserID: req.user.UserID
    }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

/*
 * Manual overdue processing:
 * - Branch manager/Admin: current branch only
 * - HighAdmin: all branches, or one optional branchID
 * - SQL Agent: calls the procedure without UserID and still processes all branches
 */
router.post('/maintenance/process-overdue-installments', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const isHighAdmin = hasRole(req.user, 'HighAdmin');
  const branchID = isHighAdmin ? (req.body?.branchID || null) : req.user.CurrentBranchID;

  if (!isHighAdmin && !branchID) {
    throw httpError(403, 'The current branch manager does not have an active branch assignment.');
  }

  const result = await executeProcedure('dbo.sp_Loan_ProcessOverdueInstallments', {
    inputs: {
      UserID: TYPES.int,
      BranchID: TYPES.int
    },
    values: {
      UserID: req.user.UserID,
      BranchID: branchID
    }
  });
  ok(res, {
    data: result.recordset,
    output: result.output,
    meta: {
      accessScope: isHighAdmin && !branchID ? 'all' : 'branch',
      branchID: branchID || null
    }
  });
}));

module.exports = router;
