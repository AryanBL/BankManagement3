const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();
router.use(authenticate());

router.post('/request-by-employee', authorize('Employee', 'Admin'), requireBodyFields(['toBranchID']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_EmployeeTransfer_RequestByEmployee', {
    inputs: {
      UserID: TYPES.int,
      ToBranchID: [TYPES.int, 'toBranchID'],
      Reason: [TYPES.string500, 'reason']
    },
    outputs: { TransferRequestID: TYPES.int },
    values: { ...req.body, UserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/request-by-manager', authorize('Admin', 'HighAdmin'), requireBodyFields(['employeeID', 'toBranchID']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_EmployeeTransfer_RequestByManager', {
    inputs: {
      ManagerUserID: TYPES.int,
      EmployeeID: [TYPES.int, 'employeeID'],
      ToBranchID: [TYPES.int, 'toBranchID'],
      Reason: [TYPES.string500, 'reason']
    },
    outputs: { TransferRequestID: TYPES.int },
    values: { ...req.body, ManagerUserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.post('/:transferRequestID/current-manager-decision', authorize('Admin'), requireBodyFields(['approve']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_EmployeeTransfer_ApproveCurrentManager', {
    inputs: {
      ManagerUserID: TYPES.int,
      TransferRequestID: TYPES.int,
      Approve: [TYPES.bit, 'approve'],
      DecisionNote: [TYPES.string500, 'decisionNote']
    },
    values: { ...req.body, ManagerUserID: req.user.UserID, TransferRequestID: req.params.transferRequestID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.post('/:transferRequestID/destination-manager-decision', authorize('Admin'), requireBodyFields(['approve']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_EmployeeTransfer_ApproveDestinationManager', {
    inputs: {
      ManagerUserID: TYPES.int,
      TransferRequestID: TYPES.int,
      Approve: [TYPES.bit, 'approve'],
      DecisionNote: [TYPES.string500, 'decisionNote']
    },
    values: { ...req.body, ManagerUserID: req.user.UserID, TransferRequestID: req.params.transferRequestID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

module.exports = router;
