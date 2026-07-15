/* =============================================================
   AgentJob_Account_DormantSweep_FINAL.sql
   SQL Server Agent job for automatic account dormancy processing

   Behavior:
     - Runs every day at 02:30.
     - Calls dbo.sp_Account_DormantSweep @MonthsInactive = 12.
     - Recreates the job safely if it already exists.

   Prerequisites:
     1. Database BankManagement exists.
     2. dbo.sp_Account_DormantSweep is already installed.
     3. SQL Server Agent is installed and running.
     4. Execute using a login allowed to manage Agent jobs.
   ============================================================= */

USE msdb;
GO

SET NOCOUNT ON;
GO

DECLARE @DatabaseName SYSNAME = N'BankManagement';
DECLARE @JobName      SYSNAME = N'Account Dormant Sweep';
DECLARE @ScheduleName SYSNAME = N'Account Dormant Sweep - Daily 02:30';
DECLARE @JobID        UNIQUEIDENTIFIER;
DECLARE @Command      NVARCHAR(MAX) =
    N'EXEC dbo.sp_Account_DormantSweep @MonthsInactive = 12;';

/* Validate the target database. */
IF DB_ID(@DatabaseName) IS NULL
BEGIN
    ;THROW 50001, 'Target database BankManagement does not exist.', 1;
END;

/* Validate that the dormant-sweep procedure exists. */
DECLARE @ProcedureExists BIT = 0;
DECLARE @ValidationSql NVARCHAR(MAX) =
    N'USE ' + QUOTENAME(@DatabaseName) + N';
      IF OBJECT_ID(N''dbo.sp_Account_DormantSweep'', N''P'') IS NOT NULL
          SET @Exists = 1;';

EXEC sys.sp_executesql
    @ValidationSql,
    N'@Exists BIT OUTPUT',
    @Exists = @ProcedureExists OUTPUT;

IF @ProcedureExists = 0
BEGIN
    ;THROW 50002,
          'dbo.sp_Account_DormantSweep is not installed in BankManagement.',
          1;
END;

/* Delete the existing job so this installer is rerunnable. */
IF EXISTS
(
    SELECT 1
    FROM msdb.dbo.sysjobs
    WHERE name = @JobName
)
BEGIN
    EXEC msdb.dbo.sp_delete_job
        @job_name = @JobName,
        @delete_unused_schedule = 1;
END;

/* Create the SQL Server Agent job. */
EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description =
        N'Marks eligible Active accounts Dormant after 12 months without completed customer-initiated activity.',
    @category_name = N'[Uncategorized (Local)]',
    @job_id = @JobID OUTPUT;

/* Add the job execution step. */
EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobID,
    @step_name = N'Execute account dormant sweep',
    @subsystem = N'TSQL',
    @database_name = @DatabaseName,
    @command = @Command,
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2;     -- Quit with failure

/* Run once every day at 02:30. */
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobID,
    @name = @ScheduleName,
    @enabled = 1,
    @freq_type = 4,            -- Daily
    @freq_interval = 1,        -- Every day
    @freq_subday_type = 1,     -- Once
    @active_start_time = 023000; -- 02:30:00

/* Assign the job to the local SQL Server instance. */
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobID;

PRINT N'Account Dormant Sweep SQL Server Agent job created successfully.';
PRINT N'Schedule: every day at 02:30.';
PRINT N'Command: EXEC dbo.sp_Account_DormantSweep @MonthsInactive = 12;';
GO

/* Verify the installed job. */
SELECT
    j.name AS JobName,
    j.enabled AS JobEnabled,
    s.step_name AS StepName,
    s.database_name AS TargetDatabase,
    s.command AS JobCommand,
    sch.name AS ScheduleName,
    sch.enabled AS ScheduleEnabled,
    sch.active_start_time AS ActiveStartTime
FROM msdb.dbo.sysjobs AS j
INNER JOIN msdb.dbo.sysjobsteps AS s
    ON s.job_id = j.job_id
LEFT JOIN msdb.dbo.sysjobschedules AS js
    ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules AS sch
    ON sch.schedule_id = js.schedule_id
WHERE j.name = N'Account Dormant Sweep';
GO