const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');
const { hasRole, httpError } = require('../utils/access-scope');

const router = express.Router();
router.use(authenticate());

function scopedEmployeeSearchValues(req) {
  const values = { ...req.query };

  if (hasRole(req.user, 'HighAdmin')) {
    return values;
  }

  if (hasRole(req.user, 'Admin')) {
    const currentBranchID = Number(req.user.CurrentBranchID);
    if (!Number.isInteger(currentBranchID) || currentBranchID <= 0) {
      throw httpError(403, 'The current manager does not have an active branch assignment.');
    }

    if (values.branchID !== undefined && values.branchID !== '') {
      const requestedBranchID = Number(values.branchID);
      if (!Number.isInteger(requestedBranchID) || requestedBranchID !== currentBranchID) {
        throw httpError(403, 'Managers can search employees only in their own current branch.');
      }
    }

    values.branchID = currentBranchID;
    values.searchBranchHistory = false;
    delete values.branchCode;
    return values;
  }

  values.employeeID = req.user.EmployeeID;
  values.searchBranchHistory = false;
  delete values.branchID;
  delete values.branchCode;
  return values;
}

async function assertEmployeeTargetVisible(req, employeeID) {
  if (hasRole(req.user, 'HighAdmin')) return;

  const targetID = Number(employeeID);
  if (!Number.isInteger(targetID) || targetID <= 0) {
    throw httpError(400, 'A valid employee ID is required.');
  }

  if (!hasRole(req.user, 'Admin')) {
    if (targetID !== Number(req.user.EmployeeID)) {
      throw httpError(403, 'Normal employees can view only their own employee record.');
    }
    return;
  }

  try {
    const result = await executeProcedure('dbo.sp_Employee_Search', {
      inputs: {
        UserID: TYPES.int,
        EmployeeID: TYPES.int,
        BranchID: TYPES.int,
        IncludeTerminated: TYPES.bit,
        SearchBranchHistory: TYPES.bit
      },
      values: {
        UserID: req.user.UserID,
        EmployeeID: targetID,
        BranchID: req.user.CurrentBranchID,
        IncludeTerminated: true,
        SearchBranchHistory: false
      }
    });

    if (!result.recordset[0]) {
      throw httpError(403, 'Managers can access only employees in their own current branch.');
    }
  } catch (error) {
    if (error.status) throw error;
    throw httpError(403, 'Managers can access only eligible employees in their own current branch.');
  }
}

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
    values: { ...scopedEmployeeSearchValues(req), UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset });
}));

router.get('/:employeeID', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  await assertEmployeeTargetVisible(req, req.params.employeeID);
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
  await assertEmployeeTargetVisible(req, req.params.employeeID);
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
  await assertEmployeeTargetVisible(req, req.params.employeeID);
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
  await assertEmployeeTargetVisible(req, req.params.employeeID);
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
  await assertEmployeeTargetVisible(req, req.params.employeeID);
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
  await assertEmployeeTargetVisible(req, req.params.employeeID);
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
