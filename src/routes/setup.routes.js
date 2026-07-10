const express = require('express');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, created } = require('../utils/http');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();

router.post('/initial-high-admin', requireBodyFields(['username', 'password', 'firstName', 'lastName', 'nationalID', 'birthDate', 'phone', 'email']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_HighAdmin_CreateInitialUser', {
    inputs: {
      Username: [TYPES.string50, 'username'],
      Password: [TYPES.string4000, 'password'],
      FirstName: [TYPES.string50, 'firstName'],
      LastName: [TYPES.string50, 'lastName'],
      NationalID: [TYPES.string20, 'nationalID'],
      BirthDate: [TYPES.date, 'birthDate'],
      Phone: [TYPES.string20, 'phone'],
      Email: [TYPES.string100, 'email'],
      Address: [TYPES.string200, 'address']
    },
    outputs: {
      UserID: TYPES.int,
      CustomerID: TYPES.int
    },
    values: req.body
  });

  created(res, {
    data: result.recordset[0] || result.output,
    output: result.output
  });
}));

module.exports = router;
