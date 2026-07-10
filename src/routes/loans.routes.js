const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();
router.use(authenticate());

router.post('/', authorize('Employee', 'Admin', 'HighAdmin'), requireBodyFields(['customerID', 'branchID', 'loanAmount', 'interestRate', 'numberOfInstallments']), asyncHandler(async (req, res) => {
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
    values: { ...req.body, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.get('/:loanID/status', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Loan_GetStatus', {
    inputs: {
      LoanID: TYPES.int,
      UserID: TYPES.int
    },
    values: { LoanID: req.params.loanID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordsets.length > 1 ? result.recordsets : result.recordset });
}));

router.post('/installments/:installmentID/pay', requireBodyFields(['fromAccountID']), asyncHandler(async (req, res) => {
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
    values: { ...req.body, InstallmentID: req.params.installmentID, EmployeeID: req.body.employeeID || req.user.EmployeeID, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/maintenance/process-overdue-installments', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Loan_ProcessOverdueInstallments');
  ok(res, { data: result.recordset, output: result.output });
}));

module.exports = router;
