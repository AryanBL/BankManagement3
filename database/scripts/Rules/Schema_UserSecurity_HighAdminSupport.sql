/* =========================================================
   DEPRECATED / NO-OP
   ---------------------------------------------------------
   This file used to contain an older HighAdmin access model.
   It is intentionally no-op in the fixed package because the
   final coherent model is enforced by:
     Rules/ApplyAccessRules.sql
     Rules/99_Function_UserHasEffectiveRole.sql

   Do not paste old trigger definitions back into this file.
   ========================================================= */
PRINT 'Schema_UserSecurity_HighAdminSupport.sql is deprecated; final rules are in ApplyAccessRules.sql.';
GO
