const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();
router.use(authenticate());

router.post('/deposit', authorize('Employee', 'Admin', 'HighAdmin'), requireBodyFields(['accountID', 'amount']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_Deposit', {
    inputs: {
      AccountID: [TYPES.int, 'accountID'],
      Amount: [TYPES.money, 'amount'],
      EmployeeID: [TYPES.int, 'employeeID'],
      Description: [TYPES.string200, 'description'],
      UserID: TYPES.int
    },
    outputs: {
      TransactionID: TYPES.int,
      ReadyToCompleteAt: TYPES.datetime
    },
    values: { ...req.body, EmployeeID: req.body.employeeID || req.user.EmployeeID, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/withdraw', requireBodyFields(['accountID', 'amount']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_Withdrawal', {
    inputs: {
      AccountID: [TYPES.int, 'accountID'],
      Amount: [TYPES.money, 'amount'],
      EmployeeID: [TYPES.int, 'employeeID'],
      Description: [TYPES.string200, 'description'],
      UserID: TYPES.int
    },
    outputs: {
      TransactionID: TYPES.int,
      ReadyToCompleteAt: TYPES.datetime
    },
    values: { ...req.body, EmployeeID: req.body.employeeID || req.user.EmployeeID, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/transfer', requireBodyFields(['fromAccountID', 'toAccountID', 'amount']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_Transfer', {
    inputs: {
      FromAccountID: [TYPES.int, 'fromAccountID'],
      ToAccountID: [TYPES.int, 'toAccountID'],
      Amount: [TYPES.money, 'amount'],
      EmployeeID: [TYPES.int, 'employeeID'],
      Description: [TYPES.string200, 'description'],
      UserID: TYPES.int
    },
    outputs: {
      TransactionID: TYPES.int,
      ReadyToCompleteAt: TYPES.datetime
    },
    values: { ...req.body, EmployeeID: req.body.employeeID || req.user.EmployeeID, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/:transactionID/finalize', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_Finalize', {
    inputs: {
      TransactionID: TYPES.int
    },
    outputs: {
      ResultStatus: TYPES.string20,
      ResultMessage: TYPES.string4000
    },
    values: { TransactionID: req.params.transactionID }
  });
  ok(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/:transactionID/reverse', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_Reverse', {
    inputs: {
      TransactionID: TYPES.int,
      EmployeeID: [TYPES.int, 'employeeID'],
      ReasonDescription: [TYPES.string200, 'reasonDescription'],
      UserID: TYPES.int
    },
    values: { ...req.body, TransactionID: req.params.transactionID, EmployeeID: req.body.employeeID || req.user.EmployeeID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/maintenance/process-pending-batch', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_ProcessPendingBatch');
  ok(res, { data: result.recordset, output: result.output });
}));

module.exports = router;
