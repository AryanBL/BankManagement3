const env = require('../config/env');

const DATE_ONLY_KEYS = new Set([
  'birthdate',
  'registrationdate',
  'opendate',
  'closedate',
  'hiredate',
  'startdate',
  'enddate',
  'duedate',
  'paiddate',
  'effectivedate',
  'terminationdate',
  'transactionday',
  'oldestoverdueduedate',
  'currentbranchstartdate'
]);

const DATE_TIME_KEYS = new Set([
  'date',
  'transactiondate',
  'readytocompleteat',
  'initialdepositreadytocompleteat',
  'paymentreadytocompleteat',
  'completedat',
  'createdat',
  'updatedat',
  'processedat',
  'cancelledat',
  'actiondate',
  'entrydate',
  'logintime',
  'logouttime',
  'expiresat',
  'sessionexpiresat',
  'lastactivityat',
  'currentmanagerdecisiondate',
  'destinationmanagerdecisiondate'
]);

function compactKey(key) {
  return String(key || '').replace(/[^a-z0-9]/gi, '').toLowerCase();
}

function dateKindForKey(key) {
  const compact = compactKey(key);
  if (DATE_TIME_KEYS.has(compact)) return 'datetime';
  if (DATE_ONLY_KEYS.has(compact)) return 'date';
  if (/(?:timestamp|datetime|time|expiresat|createdat|updatedat|processedat|completedat|cancelledat|readytocompleteat)$/.test(compact)) {
    return 'datetime';
  }
  if (/(?:date|day)$/.test(compact)) return 'date';
  return null;
}

function pad(number, width = 2) {
  return String(number).padStart(width, '0');
}

function sqlDateToCalendarString(value) {
  const useUTC = Boolean(env.db.useUTC);
  const year = useUTC ? value.getUTCFullYear() : value.getFullYear();
  const month = (useUTC ? value.getUTCMonth() : value.getMonth()) + 1;
  const day = useUTC ? value.getUTCDate() : value.getDate();
  return `${pad(year, 4)}-${pad(month)}-${pad(day)}`;
}

function normalizeDateValues(value, key = '') {
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) return null;
    return dateKindForKey(key) === 'date'
      ? sqlDateToCalendarString(value)
      : value.toISOString();
  }

  if (Array.isArray(value)) {
    return value.map((item) => normalizeDateValues(item, key));
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([childKey, childValue]) => [
        childKey,
        normalizeDateValues(childValue, childKey)
      ])
    );
  }

  return value;
}

function ok(res, data = {}, statusCode = 200) {
  return res.status(statusCode).json(normalizeDateValues({ success: true, ...data }));
}

function created(res, data = {}) {
  return ok(res, data, 201);
}

function asyncHandler(fn) {
  return function wrapped(req, res, next) {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

function pickBody(req, extras = {}) {
  return { ...(req.body || {}), ...extras };
}

function getPaging(req) {
  const page = Math.max(parseInt(req.query.page || '1', 10), 1);
  const pageSize = Math.min(Math.max(parseInt(req.query.pageSize || '50', 10), 1), 200);
  return { page, pageSize, offset: (page - 1) * pageSize };
}

module.exports = {
  ok,
  created,
  asyncHandler,
  pickBody,
  getPaging,
  normalizeDateValues,
  dateKindForKey
};
