const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate());

/*
 * Safe branch catalogue used by account-opening and transfer forms.
 * Every authenticated user may see only non-sensitive branch identity fields.
 */
router.get('/options', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Branch_ListOptions', {
    inputs: {
      UserID: TYPES.int
    },
    values: {
      UserID: req.user.UserID
    }
  });
  ok(res, { data: result.recordset });
}));

router.use(authorize('Employee', 'Admin', 'HighAdmin'));

router.get('/', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Branch_GetInfo', {
    inputs: {
      UserID: TYPES.int,
      BranchID: [TYPES.int, 'branchID'],
      BranchCode: [TYPES.string20, 'branchCode']
    },
    values: { ...req.query, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset });
}));

router.get('/:branchID', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Branch_GetInfo', {
    inputs: {
      UserID: TYPES.int,
      BranchID: TYPES.int,
      BranchCode: [TYPES.string20, 'branchCode']
    },
    values: { ...req.query, UserID: req.user.UserID, BranchID: req.params.branchID }
  });
  ok(res, { data: result.recordset[0] || null });
}));

module.exports = router;
