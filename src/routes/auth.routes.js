const express = require('express');
const rateLimit = require('express-rate-limit');
const { TYPES, executeProcedure } = require('../utils/procedure');
const { asyncHandler, ok, created } = require('../utils/http');
const { authenticate } = require('../middleware/auth');
const { requireBodyFields } = require('../middleware/validation');

const router = express.Router();

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { message: 'Too many login attempts. Try again later.' } }
});

router.post('/signup', requireBodyFields(['username', 'password', 'firstName', 'lastName', 'nationalID', 'birthDate', 'phone', 'email']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_User_SignUp', {
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

router.post('/login', loginLimiter, requireBodyFields(['password']), asyncHandler(async (req, res) => {
  const result = await executeProcedure('dbo.sp_User_Login', {
    inputs: {
      Username: [TYPES.string50, 'username'],
      Password: [TYPES.string4000, 'password'],
      LoginUserID: [TYPES.int, 'loginUserID'],
      LoginCustomerID: [TYPES.int, 'loginCustomerID'],
      LoginEmployeeID: [TYPES.int, 'loginEmployeeID']
    },
    outputs: {
      UserID: TYPES.int,
      CustomerID: TYPES.int,
      EmployeeID: TYPES.int,
      SessionToken: TYPES.token,
      Roles: TYPES.stringMax
    },
    values: req.body
  });

  ok(res, {
    data: result.recordset[0] || {
      userID: result.output.UserID,
      customerID: result.output.CustomerID,
      employeeID: result.output.EmployeeID,
      sessionToken: result.output.SessionToken,
      effectiveRoles: result.output.Roles
    },
    output: result.output
  });
}));

router.post('/logout', authenticate(), asyncHandler(async (req, res) => {
  await executeProcedure('dbo.sp_User_Logout', {
    inputs: {
      SessionToken: TYPES.token
    },
    values: {
      SessionToken: req.sessionToken
    }
  });

  ok(res, { message: 'Logged out successfully.' });
}));

router.get('/me', authenticate(), asyncHandler(async (req, res) => {
  ok(res, { data: req.user });
}));

module.exports = router;
