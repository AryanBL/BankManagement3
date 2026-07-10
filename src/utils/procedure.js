const { sql, getPool } = require('../config/db');

const TYPES = {
  int: sql.Int,
  bit: sql.Bit,
  decimal: sql.Decimal(18, 2),
  money: sql.Decimal(18, 2),
  percent: sql.Decimal(5, 2),
  date: sql.Date,
  datetime: sql.DateTime,
  string20: sql.NVarChar(20),
  string30: sql.NVarChar(30),
  string50: sql.NVarChar(50),
  string100: sql.NVarChar(100),
  string200: sql.NVarChar(200),
  string500: sql.NVarChar(500),
  string4000: sql.NVarChar(4000),
  stringMax: sql.NVarChar(sql.MAX),
  token: sql.NVarChar(200)
};

function valueOrNull(value) {
  return value === undefined || value === '' ? null : value;
}

function addInputs(request, inputMap, source) {
  for (const [name, definition] of Object.entries(inputMap || {})) {
    const type = Array.isArray(definition) ? definition[0] : definition;
    const sourceName = Array.isArray(definition) ? definition[1] : name;
    request.input(name, type, valueOrNull(source[sourceName]));
  }
}

function addOutputs(request, outputMap) {
  for (const [name, type] of Object.entries(outputMap || {})) {
    request.output(name, type);
  }
}

async function executeProcedure(procedureName, { inputs = {}, outputs = {}, values = {}, poolName = 'app' } = {}) {
  const pool = await getPool(poolName);
  const request = pool.request();
  addInputs(request, inputs, values);
  addOutputs(request, outputs);
  const result = await request.execute(procedureName);

  return {
    recordsets: result.recordsets || [],
    recordset: result.recordset || [],
    output: result.output || {},
    rowsAffected: result.rowsAffected || []
  };
}

async function executeQuery(queryText, { inputs = {}, values = {}, poolName = 'app' } = {}) {
  const pool = await getPool(poolName);
  const request = pool.request();
  addInputs(request, inputs, values);
  const result = await request.query(queryText);
  return {
    recordsets: result.recordsets || [],
    recordset: result.recordset || [],
    rowsAffected: result.rowsAffected || []
  };
}

module.exports = {
  sql,
  TYPES,
  executeProcedure,
  executeQuery,
  valueOrNull
};
