const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate, authorize } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();
router.use(authenticate());

router.get('/', asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Customer_Search', {
    inputs: {
      UserID: TYPES.int,
      NameSearch: [TYPES.string100, 'nameSearch'],
      NationalID: [TYPES.string20, 'nationalID'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email'],
      IncludeInactive: [TYPES.bit, 'includeInactive']
    },
    values: { ...req.query, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset });
}));

router.post('/', authorize('Employee', 'Admin', 'HighAdmin'), requireBodyFields(['firstName', 'lastName', 'nationalID', 'birthDate', 'phone', 'email']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Customer_Create', {
    inputs: {
      FirstName: [TYPES.string50, 'firstName'],
      LastName: [TYPES.string50, 'lastName'],
      NationalID: [TYPES.string20, 'nationalID'],
      BirthDate: [TYPES.date, 'birthDate'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email'],
      Address: [TYPES.string200, 'address'],
      CreatedByUserID: TYPES.int
    },
    outputs: { CustomerID: TYPES.int },
    values: { ...req.body, CreatedByUserID: req.user.UserID }
  });
  created(res, { data: result.recordset[0] || result.output, output: result.output });
}));

router.put('/:customerID', authorize('Employee', 'Admin', 'HighAdmin'), requireBodyFields(['firstName', 'lastName', 'phone', 'email']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Customer_Update', {
    inputs: {
      CustomerID: TYPES.int,
      FirstName: [TYPES.string50, 'firstName'],
      LastName: [TYPES.string50, 'lastName'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email'],
      Address: [TYPES.string200, 'address'],
      UserID: TYPES.int
    },
    values: { ...req.body, CustomerID: req.params.customerID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

router.delete('/:customerID', authorize('Employee', 'Admin', 'HighAdmin'), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_Customer_Delete', {
    inputs: {
      CustomerID: TYPES.int,
      UserID: TYPES.int
    },
    values: { CustomerID: req.params.customerID, UserID: req.user.UserID }
  });
  ok(res, { data: result.recordset, output: result.output });
}));

module.exports = router;
