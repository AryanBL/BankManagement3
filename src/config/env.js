require('dotenv').config();

function bool(value, defaultValue = false) {
  if (value === undefined || value === null || value === '') return defaultValue;
  return ['true', '1', 'yes', 'y'].includes(String(value).toLowerCase());
}

function number(value, defaultValue) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

function required(name, fallback = undefined) {
  const value = process.env[name] ?? fallback;
  if (value === undefined || value === null || value === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const env = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: number(process.env.PORT, 4000),
  corsOrigin: (process.env.CORS_ORIGIN || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean),

  db: {
    server: required('DB_SERVER', 'localhost'),
    port: number(process.env.DB_PORT, 1433),
    database: required('DB_DATABASE', 'BankManagement'),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    encrypt: bool(process.env.DB_ENCRYPT, false),
    trustServerCertificate: bool(process.env.DB_TRUST_SERVER_CERTIFICATE, true),
    requestTimeout: number(process.env.DB_REQUEST_TIMEOUT_MS, 30000),
    connectionTimeout: number(process.env.DB_CONNECTION_TIMEOUT_MS, 15000),
    poolMax: number(process.env.DB_POOL_MAX, 10),
    poolMin: number(process.env.DB_POOL_MIN, 0)
  },

  reportDb: {
    user: process.env.REPORT_DB_USER || process.env.DB_USER,
    password: process.env.REPORT_DB_PASSWORD || process.env.DB_PASSWORD
  },

  auditDb: {
    user: process.env.AUDIT_DB_USER || process.env.DB_USER,
    password: process.env.AUDIT_DB_PASSWORD || process.env.DB_PASSWORD
  },

  highAdminReportDb: {
    user: process.env.HIGHADMIN_REPORT_DB_USER || process.env.DB_USER,
    password: process.env.HIGHADMIN_REPORT_DB_PASSWORD || process.env.DB_PASSWORD
  }
};

module.exports = env;
