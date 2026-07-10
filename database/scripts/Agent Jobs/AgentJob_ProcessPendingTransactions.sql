/* =========================================================
   AgentJob_ProcessPendingTransactions.sql

   Creates a SQL Server Agent job that calls
   dbo.sp_Transaction_ProcessPendingBatch on a fixed recurring
   schedule, so every Pending transaction whose amount-based
   hold has elapsed gets finalized automatically -- no
   application code has to remember to poll for it.

   PREREQUISITES:
   - SQL Server Agent service must be running.
     (In SSMS Object Explorer: right-click "SQL Server Agent" ->
      Start, if it shows a stopped/red icon.)
   - Must run AFTER TableCreation.sql and
     Procedure_ProcessPendingBatch.sql, since the job step calls
     dbo.sp_Transaction_ProcessPendingBatch directly.
   - Adjust @DatabaseName below to match your actual database
     name before running this script.

   SCHEDULE:
   Runs every 1 minute, all day, every day. 1 minute is a
   reasonable default given the shortest non-zero hold tier is
   also 1 minute (transactions under $5,000 need no wait at all
   and are visible as 'ready' the moment they're inserted, since
   ReadyToCompleteAt is already in the past for them).
   Change @freq_subday_interval below to run more or less often.
   ========================================================= */

USE msdb;
GO

DECLARE @DatabaseName NVARCHAR(128) = N'BankManagement';  -- <-- EDIT THIS
DECLARE @JobName      NVARCHAR(128) = N'Process Pending Bank Transactions';

------------------------------------------------------------
-- Drop the job first if it already exists, so this script is
-- safe to re-run (e.g. after editing the schedule).
------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;
END;
GO

DECLARE @DatabaseName NVARCHAR(128) = N'BankManagement';  -- <-- EDIT THIS (must match above)
DECLARE @JobName      NVARCHAR(128) = N'Process Pending Bank Transactions';
DECLARE @JobID UNIQUEIDENTIFIER;

------------------------------------------------------------
-- Create the job
------------------------------------------------------------
EXEC msdb.dbo.sp_add_job
    @job_name        = @JobName,
    @enabled         = 1,
    @description     = N'Sweeps dbo.Transactions for Pending rows whose amount-based completion delay has elapsed and finalizes them via dbo.sp_Transaction_ProcessPendingBatch.',
    @owner_login_name = N'ARYANDESKTOP\Aryan',           -- <-- adjust if 'sa' is not appropriate in your environment
    @job_id          = @JobID OUTPUT;

------------------------------------------------------------
-- Add the job step: just calls the batch procedure.
-- The procedure is XACT_ABORT-safe and wraps everything in its
-- own transaction, so a single job step is sufficient -- no
-- extra T-SQL is needed here beyond the EXEC call.
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobstep
    @job_id            = @JobID,
    @step_name         = N'Process ready pending transactions',
    @subsystem         = N'TSQL',
    @database_name     = @DatabaseName,
    @command           = N'EXEC dbo.sp_Transaction_ProcessPendingBatch;',
    @on_success_action  = 1,   -- quit reporting success
    @on_fail_action     = 2,   -- quit reporting failure
    @retry_attempts     = 1,
    @retry_interval     = 1;   -- minutes between retries on failure

------------------------------------------------------------
-- Schedule: every 1 minute, every day, all day.
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobschedule
    @job_id                = @JobID,
    @name                  = N'Every minute, all day',
    @enabled               = 1,
    @freq_type             = 4,    -- daily
    @freq_interval         = 1,    -- every 1 day
    @freq_subday_type      = 4,    -- minutes
    @freq_subday_interval  = 1,    -- every 1 minute
    @active_start_time     = 0;    -- 00:00:00, i.e. runs all day

------------------------------------------------------------
-- Target the local server (standard for a single-server setup).
------------------------------------------------------------
EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @JobID,
    @server_name = N'(local)';
GO

/* =========================================================
   MANUAL TEST / TROUBLESHOOTING

   Run the job immediately without waiting for the schedule:
     EXEC msdb.dbo.sp_start_job N'Process Pending Bank Transactions';

   Check recent run history and outcome:
     SELECT TOP 20
         j.name AS JobName,
         h.run_date,
         h.run_time,
         h.run_status,   -- 0=Failed, 1=Succeeded, 2=Retry, 3=Cancelled
         h.message
     FROM msdb.dbo.sysjobhistory h
     INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
     WHERE j.name = N'Process Pending Bank Transactions'
     ORDER BY h.run_date DESC, h.run_time DESC;

   Disable the job without deleting it (e.g. during testing):
     EXEC msdb.dbo.sp_update_job
         @job_name = N'Process Pending Bank Transactions',
         @enabled  = 0;

   Remove the job entirely:
     EXEC msdb.dbo.sp_delete_job
         @job_name = N'Process Pending Bank Transactions';
   ========================================================= */
