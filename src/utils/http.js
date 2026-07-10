function ok(res, data = {}, statusCode = 200) {
  return res.status(statusCode).json({ success: true, ...data });
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
  getPaging
};
