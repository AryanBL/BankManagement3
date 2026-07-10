/* =========================================================
   AgentJob_ProcessOverdueInstallments.sql

   Creates a SQL Server Agent job that calls
   dbo.sp_Loan_ProcessOverdueInstallments once a day at
   midnight, so installments more than 90 days overdue (with no
   in-flight payment) get marked Defaulted automatically -- along
   with their loan -- without anyone having to remember to check.

   PREREQUISITES:
   - SQL Server Agent service must be running.
   - Must run AFTER TableCreation.sql and
     Procedure_Loan_ProcessOverdueInstallments.sql, since the job
     step calls dbo.sp_Loan_ProcessOverdueInstallments directly.
   - Adjust @DatabaseName below to match your actual database
     name before running this script.
   - Adjust @owner_login_name below (see the note on 'sa' in
     AgentJob_ProcessPendingTransactions.sql -- the same
     consideration applies here).

   SCHEDULE:
   Runs once daily at 00:00:00 (midnight). Unlike transaction
   finalization, defaulting doesn't need minute-level precision --
   a 90-day threshold is unaffected by a few hours' difference in
   when the daily sweep happens to run.
   ========================================================= */

USE msdb;
GO

DECLARE @DatabaseName NVARCHAR(128) = N'BankManagement';  -- <-- EDIT THIS
DECLARE @JobName      NVARCHAR(128) = N'Process Overdue Loan Installments';

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
DECLARE @JobName      NVARCHAR(128) = N'Process Overdue Loan Installments';
DECLARE @JobID UNIQUEIDENTIFIER;

------------------------------------------------------------
-- Create the job
------------------------------------------------------------
EXEC msdb.dbo.sp_add_job
    @job_name        = @JobName,
    @enabled         = 1,
    @description     = N'Daily sweep that marks installments more than 90 days overdue (with no in-flight payment) as Defaulted, and defaults their loan, via dbo.sp_Loan_ProcessOverdueInstallments.',
    @owner_login_name = N'sa',           -- <-- adjust if 'sa' is not appropriate in your environment
    @job_id          = @JobID OUTPUT;

------------------------------------------------------------
-- Add the job step
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobstep
    @job_id            = @JobID,
    @step_name         = N'Default installments overdue more than 90 days',
    @subsystem         = N'TSQL',
    @database_name     = @DatabaseName,
    @command           = N'EXEC dbo.sp_Loan_ProcessOverdueInstallments;',
    @on_success_action  = 1,   -- quit reporting success
    @on_fail_action     = 2,   -- quit reporting failure
    @retry_attempts     = 1,
    @retry_interval     = 5;   -- minutes between retries on failure

------------------------------------------------------------
-- Schedule: once daily, at 00:00:00 (midnight).
-- freq_subday_type = 1 means "run once at active_start_time"
-- (as opposed to repeating every N seconds/minutes/hours), and
-- active_start_time = 0 is 00:00:00.
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobschedule
    @job_id                = @JobID,
    @name                  = N'Daily at midnight',
    @enabled               = 1,
    @freq_type             = 4,    -- daily
    @freq_interval         = 1,    -- every 1 day
    @freq_subday_type      = 1,    -- once per day, at a specific time
    @freq_subday_interval  = 0,
    @active_start_time     = 0;    -- 00:00:00

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
     EXEC msdb.dbo.sp_start_job N'Process Overdue Loan Installments';

   Check recent run history and outcome:
     SELECT TOP 20
         j.name AS JobName,
         h.run_date,
         h.run_time,
         h.run_status,   -- 0=Failed, 1=Succeeded, 2=Retry, 3=Cancelled
         h.message
     FROM msdb.dbo.sysjobhistory h
     INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
     WHERE j.name = N'Process Overdue Loan Installments'
     ORDER BY h.run_date DESC, h.run_time DESC;

   Disable the job without deleting it:
     EXEC msdb.dbo.sp_update_job
         @job_name = N'Process Overdue Loan Installments',
         @enabled  = 0;

   Remove the job entirely:
     EXEC msdb.dbo.sp_delete_job
         @job_name = N'Process Overdue Loan Installments';
   ========================================================= */
