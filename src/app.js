const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const env = require('./config/env');
const { getPool } = require('./config/db');
const { ok } = require('./utils/http');
const { notFound, errorHandler } = require('./utils/errors');

const authRoutes = require('./routes/auth.routes');
const setupRoutes = require('./routes/setup.routes');
const customerRoutes = require('./routes/customers.routes');
const accountRoutes = require('./routes/accounts.routes');
const transactionRoutes = require('./routes/transactions.routes');
const loanRoutes = require('./routes/loans.routes');
const employeeRoutes = require('./routes/employees.routes');
const transferRoutes = require('./routes/transfers.routes');
const branchRoutes = require('./routes/branches.routes');
const highAdminRoutes = require('./routes/highadmin.routes');
const reportRoutes = require('./routes/reports.routes');

const app = express();

app.use(helmet());
app.use(cors({
  origin(origin, callback) {
    if (!origin || env.corsOrigin.length === 0 || env.corsOrigin.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error(`CORS blocked for origin: ${origin}`));
  },
  credentials: true
}));
app.use(express.json({ limit: '1mb' }));
app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));

app.get('/api/health', async (req, res, next) => {
  try {
    const pool = await getPool('app');
    const result = await pool.request().query('SELECT DB_NAME() AS databaseName, SUSER_SNAME() AS sqlLogin, USER_NAME() AS databaseUser;');
    ok(res, {
      message: 'BankManagement backend is running.',
      data: result.recordset[0]
    });
  } catch (error) {
    next(error);
  }
});

app.use('/api/setup', setupRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/accounts', accountRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/loans', loanRoutes);
app.use('/api/employees', employeeRoutes);
app.use('/api/employee-transfers', transferRoutes);
app.use('/api/branches', branchRoutes);
app.use('/api/highadmin', highAdminRoutes);
app.use('/api/reports', reportRoutes);

app.use(notFound);
app.use(errorHandler);

module.exports = app;
