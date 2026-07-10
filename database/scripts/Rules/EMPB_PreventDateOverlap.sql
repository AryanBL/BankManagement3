CREATE TRIGGER trg_EMPB_PreventDateOverlap
ON dbo.EMPB
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if the inserted or updated rows overlap with any existing records for the same employee
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.EMPB e 
            ON i.EmployeeID = e.EmployeeID
        WHERE 
            -- Exclude comparing the exact same record against itself 
            -- (Assuming EmployeeID, BranchID, and StartDate form a unique combination for a period)
            NOT (i.BranchID = e.BranchID AND i.StartDate = e.StartDate)
            
            -- Overlap Logic: 
            -- New StartDate must be before the Existing EndDate AND
            -- Existing StartDate must be before the New EndDate.
            -- We use '9999-12-31' to handle NULL EndDates (Currently 'Working' or 'Transferred')
            AND i.StartDate < ISNULL(e.EndDate, '9999-12-31')
            AND e.StartDate < ISNULL(i.EndDate, '9999-12-31')
    )
    BEGIN
        RAISERROR ('An employee cannot have overlapping work dates across different branches. The previous assignment must end before a new one starts.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;
GO
