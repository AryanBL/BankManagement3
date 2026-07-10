function requireBodyFields(fields) {
  return function requireFields(req, res, next) {
    const missing = fields.filter((field) => req.body[field] === undefined || req.body[field] === null || req.body[field] === '');
    if (missing.length > 0) {
      return res.status(400).json({
        success: false,
        error: {
          message: `Missing required field(s): ${missing.join(', ')}`
        }
      });
    }
    return next();
  };
}

module.exports = { requireBodyFields };
