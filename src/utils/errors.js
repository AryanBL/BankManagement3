function normalizeSqlError(err) {
  const message = err && err.originalError && err.originalError.info && err.originalError.info.message
    ? err.originalError.info.message
    : err.message || 'Unexpected server error';

  return {
    message,
    number: err.number,
    state: err.state,
    class: err.class,
    procedure: err.procName || err.procedure,
    lineNumber: err.lineNumber
  };
}

function notFound(req, res) {
  res.status(404).json({
    success: false,
    error: {
      message: `Route not found: ${req.method} ${req.originalUrl}`
    }
  });
}

function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);

  const isSqlError = Boolean(err && (err.number !== undefined || err.originalError));
  const status = err.statusCode || err.status || (isSqlError ? 400 : 500);
  const error = isSqlError ? normalizeSqlError(err) : { message: err.message || 'Unexpected server error' };

  if (process.env.NODE_ENV !== 'production') {
    error.stack = err.stack;
  }

  return res.status(status).json({ success: false, error });
}

module.exports = {
  notFound,
  errorHandler
};
