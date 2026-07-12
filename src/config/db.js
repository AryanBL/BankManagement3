const sql = require('mssql');
const env = require('./env');

function makeConfig(user, password) {
  return {
    server: env.db.server,
    port: env.db.port,
    database: env.db.database,
    user,
    password,
    options: {
      encrypt: env.db.encrypt,
      trustServerCertificate: env.db.trustServerCertificate,
      enableArithAbort: true,
      useUTC: env.db.useUTC
    },
    requestTimeout: env.db.requestTimeout,
    connectionTimeout: env.db.connectionTimeout,
    pool: {
      max: env.db.poolMax,
      min: env.db.poolMin,
      idleTimeoutMillis: 30000
    }
  };
}

const poolDefinitions = {
  app: makeConfig(env.db.user, env.db.password),
  report: makeConfig(env.reportDb.user, env.reportDb.password),
  audit: makeConfig(env.auditDb.user, env.auditDb.password),
  highadminReport: makeConfig(env.highAdminReportDb.user, env.highAdminReportDb.password)
};

const pools = new Map();

async function getPool(name = 'app') {
  const config = poolDefinitions[name];
  if (!config) throw new Error(`Unknown database pool: ${name}`);

  if (!pools.has(name)) {
    const pool = new sql.ConnectionPool(config);
    const close = pool.close.bind(pool);
    pool.close = (...args) => {
      pools.delete(name);
      return close(...args);
    };
    pools.set(name, pool.connect());
  }

  return pools.get(name);
}

async function closePools() {
  const connectedPools = await Promise.allSettled([...pools.values()]);
  await Promise.all(
    connectedPools
      .filter((result) => result.status === 'fulfilled')
      .map((result) => result.value.close())
  );
  pools.clear();
}

module.exports = {
  sql,
  getPool,
  closePools
};
