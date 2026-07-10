const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();
router.use(authenticate());

router.get('/', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Employee_Search', {
    inputs: {
      UserID: TYPES.int,
      EmployeeID: [TYPES.int, 'employeeID'],
      NameSearch: [TYPES.string100, 'nameSearch'],
      NationalID: [TYPES.string20, 'nationalID'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email'],
      JobTitle: [TYPES.string100, 'jobTitle'],
      EmpStatus: [TYPES.string20, 'empStatus'],
      BranchID: [TYPES.int, 'branchID'],
      BranchCode: [TYPES.string20, 'branchCode'],
      WorkingStatus: [TYPES.string20, 'workingStatus'],
      IncludeTerminated: [TYPES.bit, 'includeTerminated'],
      SearchBranchHistory: [TYPES.bit, 'searchBranchHistory']
    },
    values: { ...req.query, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset });
}));

router.get('/:employeeID', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Employee_GetInfo', {
    inputs: {
      UserID: TYPES.int,
      EmployeeID: TYPES.int
    },
    values: { UserID: req.user.UserID, EmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordsets.length > 1 ? result.recordsets : result.recordset });
}));

router.post('/', authorize('Admin', 'HighAdmin'), requireBodyFields(['nationalID', 'firstName', 'lastName', 'jobTitle', 'salary']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Employee_Hire', {
    inputs: {
      ManagerUserID: TYPES.int,
      NationalID: [TYPES.string20, 'nationalID'],
      FirstName: [TYPES.string50, 'firstName'],
      LastName: [TYPES.string50, 'lastName'],
      HireDate: [TYPES.date, 'hireDate'],
      JobTitle: [TYPES.string100, 'jobTitle'],
      Salary: [TYPES.money, 'salary'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email']
    },
    outputs: {
      EmployeeID: TYPES.int,
      EMPBID: TYPES.int
    },
    values: { ...req.body, ManagerUserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/:employeeID/create-user-account', authorize('Admin', 'HighAdmin'), requireBodyFields(['username', 'password', 'birthDate']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Employee_CreateUserAccount', {
    inputs: {
      ManagerUserID: TYPES.int,
      EmployeeID: TYPES.int,
      Username: [TYPES.string50, 'username'],
      Password: [TYPES.string4000, 'password'],
      BirthDate: [TYPES.date, 'birthDate'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email'],
      Address: [TYPES.string200, 'address']
    },
    outputs: {
      UserID: TYPES.int,
      CustomerID: TYPES.int
    },
    values: { ...req.body, ManagerUserID: req.user.UserID, EmployeeID: req.params.employeeID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/:employeeID/change-job-title', authorize('Admin', 'HighAdmin'), requireBodyFields(['newJobTitle']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Employee_ChangeJobTitle', {
    inputs: {
      ManagerUserID: TYPES.int,
      TargetEmployeeID: TYPES.int,
      NewJobTitle: [TYPES.string100, 'newJobTitle'],
      ReasonDescription: [TYPES.string500, 'reasonDescription']
    },
    values: { ...req.body, ManagerUserID: req.user.UserID, TargetEmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/:employeeID/fire', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Employee_Fire', {
    inputs: {
      ManagerUserID: TYPES.int,
      EmployeeID: TYPES.int,
      TerminationDate: [TYPES.date, 'terminationDate'],
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, ManagerUserID: req.user.UserID, EmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/:employeeID/suspend', authorize('Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Employee_Suspend', {
    inputs: {
      ManagerUserID: TYPES.int,
      EmployeeID: TYPES.int,
      Reason: [TYPES.string500, 'reason']
    },
    values: { ...req.body, ManagerUserID: req.user.UserID, EmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.get('/:employeeID/branch-history', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_EMPBranchHistory_Get', {
    inputs: {
      UserID: TYPES.int,
      EmployeeID: TYPES.int,
      BranchID: [TYPES.int, 'branchID'],
      IncludeCurrentOnly: [TYPES.bit, 'includeCurrentOnly']
    },
    values: { ...req.query, UserID: req.user.UserID, EmployeeID: req.params.employeeID }
  });
  ok(res, { data: result.recordset });
}));

module.exports = router;
