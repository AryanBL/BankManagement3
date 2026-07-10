/* =========================================================
   AgentJob_ApplyMonthlyInterest.sql

   Creates a SQL Server Agent job that calls
   dbo.sp_Account_ApplyMonthlyInterest once a month, so every
   eligible account is credited interest automatically.

   PREREQUISITES:
   - SQL Server Agent service must be running.
   - Must run AFTER TableCreation.sql,
     Schema_CustomerAccessAndBranchLedger.sql,
     Trigger_Transactions_EnforceTypePattern_Update.sql, and
     Procedure_Account_ApplyMonthlyInterest.sql.
   - Adjust @DatabaseName below to match your actual database
     name before running this script.
   - Adjust @owner_login_name below to match your environment
     (see the same note in the existing AgentJob_* scripts).

   SCHEDULE:
   Runs once a month, on day 1 at 00:05:00 (a few minutes after
   midnight, clear of the other jobs' midnight/every-minute runs).
   ========================================================= */

USE msdb;
GO

DECLARE @DatabaseName NVARCHAR(128) = N'BankManagement';  -- <-- EDIT THIS
DECLARE @JobName      NVARCHAR(128) = N'Apply Monthly Account Interest';

------------------------------------------------------------
-- Drop the job first if it already exists, so this script is
-- safe to re-run.
------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;
END;
GO

DECLARE @DatabaseName NVARCHAR(128) = N'BankManagement';  -- <-- EDIT THIS (must match above)
DECLARE @JobName      NVARCHAR(128) = N'Apply Monthly Account Interest';
DECLARE @JobID UNIQUEIDENTIFIER;

------------------------------------------------------------
-- Create the job
------------------------------------------------------------
EXEC msdb.dbo.sp_add_job
    @job_name        = @JobName,
    @enabled         = 1,
    @description     = N'Monthly sweep that credits interest to every eligible Active account via dbo.sp_Account_ApplyMonthlyInterest.',
    @owner_login_name = N'sa',           -- <-- adjust if 'sa' is not appropriate in your environment
    @job_id          = @JobID OUTPUT;

------------------------------------------------------------
-- Add the job step
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobstep
    @job_id            = @JobID,
    @step_name         = N'Apply monthly interest',
    @subsystem         = N'TSQL',
    @database_name     = @DatabaseName,
    @command           = N'EXEC dbo.sp_Account_ApplyMonthlyInterest;',
    @on_success_action  = 1,   -- quit reporting success
    @on_fail_action     = 2,   -- quit reporting failure
    @retry_attempts     = 1,
    @retry_interval     = 5;   -- minutes between retries on failure

------------------------------------------------------------
-- Schedule: monthly, on day 1, at 00:05:00.
-- freq_type = 16 means "monthly", freq_interval = 1 means "on
-- day 1 of the month" (interpreted together with freq_relative_interval
-- = 0, the default, for an absolute day-of-month schedule).
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobschedule
    @job_id                = @JobID,
    @name                  = N'Monthly on day 1',
    @enabled               = 1,
    @freq_type             = 16,   -- monthly
    @freq_interval         = 1,    -- day 1 of the month
    @freq_recurrence_factor = 1,   -- every 1 month
    @freq_subday_type      = 1,    -- once per occurrence, at a specific time
    @active_start_time     = 500;  -- 00:05:00

------------------------------------------------------------
-- Target the local server.
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @JobID,
    @server_name = N'(local)';
GO

/* =========================================================
   MANUAL TEST / TROUBLESHOOTING

   Run the job immediately without waiting for the schedule:
     EXEC msdb.dbo.sp_start_job N'Apply Monthly Account Interest';

   Check recent run history and outcome:
     SELECT TOP 20
         j.name AS JobName,
         h.run_date,
         h.run_time,
         h.run_status,   -- 0=Failed, 1=Succeeded, 2=Retry, 3=Cancelled
         h.message
     FROM msdb.dbo.sysjobhistory h
     INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
     WHERE j.name = N'Apply Monthly Account Interest'
     ORDER BY h.run_date DESC, h.run_time DESC;

   Disable the job without deleting it:
     EXEC msdb.dbo.sp_update_job
         @job_name = N'Apply Monthly Account Interest',
         @enabled  = 0;

   Remove the job entirely:
     EXEC msdb.dbo.sp_delete_job
         @job_name = N'Apply Monthly Account Interest';
   ========================================================= */
