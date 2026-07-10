const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();
router.use(authenticate());

router.get('/', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_Search', {
    inputs: {
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
    },
    values: { ...req.query, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset });
}));

router.get('/:accountID', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_GetInfo', {
    inputs: {
      UserID: TYPES.int,
      AccountID: TYPES.int,
      AccountNumber: [TYPES.string30, 'accountNumber'],
      CustomerID: [TYPES.int, 'customerID']
    },
    values: { ...req.query, UserID: req.user.UserID, AccountID: req.params.accountID }
  });
  ok(res, { data: result.recordset });
}));

router.get('/:accountID/history', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Transaction_GetAccountHistory', {
    inputs: {
      UserID: TYPES.int,
      AccountID: TYPES.int,
      FromDate: [TYPES.datetime, 'fromDate'],
      ToDate: [TYPES.datetime, 'toDate']
    },
    values: { ...req.query, UserID: req.user.UserID, AccountID: req.params.accountID }
  });
  ok(res, { data: result.recordset });
}));

router.post('/', requireBodyFields(['branchID', 'accountTypeID']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_Open', {
    inputs: {
      UserID: TYPES.int,
      BranchID: [TYPES.int, 'branchID'],
      AccountTypeID: [TYPES.int, 'accountTypeID'],
      InitialDeposit: [TYPES.money, 'initialDeposit']
    },
    outputs: {
      AccountID: TYPES.int,
      AccountNumber: TYPES.string30,
      InitialDepositTransactionID: TYPES.int,
      InitialDepositReadyToCompleteAt: TYPES.datetime
    },
    values: { ...req.body, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/:accountID/close', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_Close', {
    inputs: {
      AccountID: TYPES.int,
      UserID: TYPES.int,
      ReasonDescription: [TYPES.string200, 'reasonDescription']
    },
    values: { ...req.body, AccountID: req.params.accountID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/:accountID/freeze', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_Freeze', {
    inputs: {
      AccountID: TYPES.int,
      UserID: TYPES.int,
      ReasonDescription: [TYPES.string200, 'reasonDescription']
    },
    values: { ...req.body, AccountID: req.params.accountID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/:accountID/unfreeze', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_Unfreeze', {
    inputs: {
      AccountID: TYPES.int,
      UserID: TYPES.int,
      ReasonDescription: [TYPES.string200, 'reasonDescription']
    },
    values: { ...req.body, AccountID: req.params.accountID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/:accountID/change-type', authorize('Employee', 'Admin', 'HighAdmin'), requireBodyFields(['newAccountTypeID']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_ChangeType', {
    inputs: {
      AccountID: TYPES.int,
      NewAccountTypeID: [TYPES.int, 'newAccountTypeID'],
      UserID: TYPES.int,
      ReasonDescription: [TYPES.string200, 'reasonDescription']
    },
    values: { ...req.body, AccountID: req.params.accountID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/maintenance/dormant-sweep', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_DormantSweep', {
    inputs: {
      MonthsInactive: [TYPES.int, 'monthsInactive']
    },
    values: req.body
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/maintenance/apply-monthly-interest', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Account_ApplyMonthlyInterest');
  ok(res, { data: result.recordset, output: result.output });
}));

module.exports = router;
