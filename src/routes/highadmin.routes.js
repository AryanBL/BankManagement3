const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');


function validateManagerHireBody(req, res, next) {
  const branchID = Number(req.body.branchID);
  const jobTitle = String(req.body.jobTitle || '').trim();

  if (!Number.isInteger(branchID) || branchID <= 0) {
    return res.status(400).json({
      success: false,
      error: { message: 'A valid positive branchID is required when hiring a Branch Manager or Vice Manager.' }
    });
  }

  if (!['Branch Manager', 'Vice Manager'].includes(jobTitle)) {
    return res.status(400).json({
      success: false,
      error: { message: 'jobTitle must be either Branch Manager or Vice Manager.' }
    });
  }

  req.body.branchID = branchID;
  req.body.jobTitle = jobTitle;
  return next();
}

const router = express.Router();
router.use(authenticate());
router.use(authorize('HighAdmin'));

router.post('/managers', requireBodyFields(['branchID', 'username', 'password', 'nationalID', 'firstName', 'lastName', 'birthDate', 'jobTitle', 'salary', 'phone', 'email']), validateManagerHireBody, asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_HireManager', {
    inputs: {
      HighAdminUserID: TYPES.int,
      BranchID: [TYPES.int, 'branchID'],
      Username: [TYPES.string50, 'username'],
      Password: [TYPES.string4000, 'password'],
      NationalID: [TYPES.string20, 'nationalID'],
      FirstName: [TYPES.string50, 'firstName'],
      LastName: [TYPES.string50, 'lastName'],
      BirthDate: [TYPES.date, 'birthDate'],
      HireDate: [TYPES.date, 'hireDate'],
      JobTitle: [TYPES.string100, 'jobTitle'],
      Salary: [TYPES.money, 'salary'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email'],
      Address: [TYPES.string200, 'address']
    },
    outputs: {
      EmployeeID: TYPES.int,
      CustomerID: TYPES.int,
      UserID: TYPES.int
    },
    values: { ...req.body, HighAdminUserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/managers/:employeeID/promote', requireBodyFields(['branchID', 'managerJobTitle']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_PromoteToManager', {
    inputs: {
      HighAdminUserID: TYPES.int,
      EmployeeID: TYPES.int,
      BranchID: [TYPES.int, 'branchID'],
      ManagerJobTitle: [TYPES.string100, 'managerJobTitle'],
      EffectiveDate: [TYPES.date, 'effectiveDate'],
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, HighAdminUserID: req.user.UserID, EmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/managers/:employeeID/downgrade', requireBodyFields(['newJobTitle']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_DowngradeManager', {
    inputs: {
      HighAdminUserID: TYPES.int,
      ManagerEmployeeID: TYPES.int,
      NewJobTitle: [TYPES.string100, 'newJobTitle'],
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, HighAdminUserID: req.user.UserID, ManagerEmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/managers/:employeeID/fire', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_FireManager', {
    inputs: {
      HighAdminUserID: TYPES.int,
      ManagerEmployeeID: TYPES.int,
      TerminationDate: [TYPES.date, 'terminationDate'],
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, HighAdminUserID: req.user.UserID, ManagerEmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/managers/:employeeID/suspend', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_SuspendManager', {
    inputs: {
      HighAdminUserID: TYPES.int,
      ManagerEmployeeID: TYPES.int,
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, HighAdminUserID: req.user.UserID, ManagerEmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/managers/:employeeID/unsuspend', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_UnsuspendManager', {
    inputs: {
      HighAdminUserID: TYPES.int,
      ManagerEmployeeID: TYPES.int,
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, HighAdminUserID: req.user.UserID, ManagerEmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/branches/:branchID/replace-manager', requireBodyFields(['newManagerEmployeeID']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_ReplaceBranchManager', {
    inputs: {
      HighAdminUserID: TYPES.int,
      BranchID: TYPES.int,
      NewManagerEmployeeID: [TYPES.int, 'newManagerEmployeeID'],
      OldManagerNewJobTitle: [TYPES.string100, 'oldManagerNewJobTitle'],
      EffectiveDate: [TYPES.date, 'effectiveDate'],
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, HighAdminUserID: req.user.UserID, BranchID: req.params.branchID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

module.exports = router;
