const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');
const { assertAccountOwner } = require('../utils/access-scope');

const router = express.Router();
router.use(authenticate());

const TRANSACTION_DATE_FIELDS = {
  TransactionDate: 'datetime',
  ReadyToCompleteAt: 'datetime',
  CompletedAt: 'datetime'
};

/* Only the owner of the destination account may initiate a deposit. */
router.post('/deposit', requireBodyFields(['accountID', 'amount']), asyncHandler(async (req, res) => {
  await assertAccountOwner(req, req.body.accountID);
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
    values: {
      ...req.body,
      EmployeeID: req.user.EmployeeID || null,
      UserID: req.user.UserID
    }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output, meta: { dateFields: TRANSACTION_DATE_FIELDS } });
}));

/* Only the owner of the source account may initiate a withdrawal. */
router.post('/withdraw', requireBodyFields(['accountID', 'amount']), asyncHandler(async (req, res) => {
  await assertAccountOwner(req, req.body.accountID);
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
    values: {
      ...req.body,
      EmployeeID: req.user.EmployeeID || null,
      UserID: req.user.UserID
    }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output, meta: { dateFields: TRANSACTION_DATE_FIELDS } });
}));

/* Only the owner of the source account may initiate a transfer. */
router.post('/transfer', requireBodyFields(['fromAccountID', 'toAccountID', 'amount']), asyncHandler(async (req, res) => {
  await assertAccountOwner(req, req.body.fromAccountID);
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
    values: {
      ...req.body,
      EmployeeID: req.user.EmployeeID || null,
      UserID: req.user.UserID
    }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output, meta: { dateFields: TRANSACTION_DATE_FIELDS } });
}));

/* Owners may manually ask the finalizer to advance one of their transactions. */
router.post('/:transactionID/finalize', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_Finalize', {
    inputs: {
      TransactionID: TYPES.int,
      UserID: TYPES.int
    },
    outputs: {
      ResultStatus: TYPES.string20,
      ResultMessage: TYPES.string4000
    },
    values: {
      TransactionID: req.params.transactionID,
      UserID: req.user.UserID
    }
  });
  ok(res, { data: result.recordset[0] || result.output, output: result.output, meta: { dateFields: TRANSACTION_DATE_FIELDS } });
}));

/* Owners may cancel/reverse only transactions initiated from their own portfolio. */
router.post('/:transactionID/reverse', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_Reverse', {
    inputs: {
      TransactionID: TYPES.int,
      EmployeeID: [TYPES.int, 'employeeID'],
      ReasonDescription: [TYPES.string200, 'reasonDescription'],
      UserID: TYPES.int
    },
    values: {
      ...req.body,
      TransactionID: req.params.transactionID,
      EmployeeID: req.user.EmployeeID || null,
      UserID: req.user.UserID
    }
  });
  ok(res, { data: result.recordset, output: result.output, meta: { dateFields: TRANSACTION_DATE_FIELDS } });
}));

/* Batch finalization remains a maintenance operation, not a customer transaction initiation. */
router.post('/maintenance/process-pending-batch', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_ProcessPendingBatch');
  ok(res, { data: result.recordset, output: result.output, meta: { dateFields: TRANSACTION_DATE_FIELDS } });
}));

module.exports = router;
