const { TYPES, executeProcedure } = require('../utils/procedure');

function extractBearerToken(req) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (/^Bearer$/i.test(scheme) && token) return token.trim();
  return null;
}

function parseRoles(effectiveRoles) {
  return String(effectiveRoles || '')
    .split(',')
    .map((role) => role.trim())
    .filter(Boolean);
}

function authenticate(requiredRole = null) {
  return async function authMiddleware(req, res, next) {
    try {
      const token = extractBearerToken(req);
      if (!token) {
        return res.status(401).json({
          success: false,
          error: { message: 'Missing Authorization header. Use: Bearer <session-token>' }
        });
      }

      const result = await executeProcedure('dbo.sp_User_ValidateSession', {
        inputs: {
          SessionToken: TYPES.token,
          RequiredRole: TYPES.string50
        },
        values: {
          SessionToken: token,
          RequiredRole: requiredRole
        }
      });

      const user = result.recordset[0];
      if (!user) {
        return res.status(401).json({ success: false, error: { message: 'Invalid session.' } });
      }

      req.sessionToken = token;
      req.user = {
        ...user,
        roles: parseRoles(user.EffectiveRoles)
      };

      return next();
    } catch (error) {
      error.status = 401;
      return next(error);
    }
  };
}

function authorize(...allowedRoles) {
  return function roleMiddleware(req, res, next) {
    const roles = req.user && req.user.roles ? req.user.roles : [];
    const allowed = allowedRoles.some((role) => roles.includes(role));
    if (!allowed) {
      return res.status(403).json({
        success: false,
        error: {
          message: `Access denied. Required role: ${allowedRoles.join(' or ')}`
        }
      });
    }
    return next();
  };
}

module.exports = {
  authenticate,
  authorize,
  extractBearerToken,
  parseRoles
};
