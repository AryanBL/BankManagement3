/* =========================================================
   AgentJob_ProcessOverdueInstallments.sql
   ---------------------------------------------------------
   Installs the daily SQL Server Agent job that reconciles loan
   and installment statuses by executing:

       dbo.sp_Loan_ProcessOverdueInstallments

   Daily behavior:
   - Pending overdue installments become Late.
   - Installments more than 90 days overdue become Defaulted.
   - Active loans with a Defaulted installment become Defaulted.
   - Active loans with all installments Paid become Paid.
   - When a loan becomes Defaulted, the borrower's Active or
     Dormant accounts become Frozen.

   SQL Server Agent must be installed and running.
   ========================================================= */

USE msdb;
GO

DECLARE @OldJobName NVARCHAR(128) = N'Process Overdue Loan Installments';
DECLARE @JobName NVARCHAR(128) = N'Daily Loan and Installment Status Maintenance';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @OldJobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @OldJobName;
END;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;
END;
GO

DECLARE @DatabaseName NVARCHAR(128) = N'BankManagement';
DECLARE @JobName NVARCHAR(128) = N'Daily Loan and Installment Status Maintenance';
DECLARE @JobID UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Daily reconciliation of Pending/Late/Defaulted/Paid installment and loan states. Freezes borrower accounts when a loan first becomes Defaulted.',
    @owner_login_name = N'sa',
    @job_id = @JobID OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @JobID,
    @step_name = N'Update loan and installment statuses',
    @subsystem = N'TSQL',
    @database_name = @DatabaseName,
    @command = N'EXEC dbo.sp_Loan_ProcessOverdueInstallments @UserID = NULL, @BranchID = NULL;',
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 1,
    @retry_interval = 5;

EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @JobID,
    @name = N'Daily at 00:10',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 1,
    @freq_subday_interval = 0,
    @active_start_time = 1000;

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @JobID,
    @server_name = N'(local)';
GO

/* Manual test:
   EXEC msdb.dbo.sp_start_job
       N'Daily Loan and Installment Status Maintenance';
*/
