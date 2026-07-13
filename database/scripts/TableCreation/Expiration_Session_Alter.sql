USE BankManagement;
GO

/* Add ExpiresAt only when it does not already exist */
IF COL_LENGTH(N'dbo.Sessions', N'ExpiresAt') IS NULL
BEGIN
    ALTER TABLE dbo.Sessions
        ADD ExpiresAt DATETIME NULL;
END;
GO

/* Give existing sessions an expiration time */
UPDATE dbo.Sessions
SET ExpiresAt = DATEADD(MINUTE, 10, LoginTime)
WHERE ExpiresAt IS NULL;
GO

/* Make the column required */
IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Sessions')
      AND name = N'ExpiresAt'
      AND is_nullable = 1
)
BEGIN
    ALTER TABLE dbo.Sessions
        ALTER COLUMN ExpiresAt DATETIME NOT NULL;
END;
GO

/* Add the default for newly inserted sessions */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.default_constraints AS DC
    INNER JOIN sys.columns AS C
        ON C.object_id = DC.parent_object_id
       AND C.column_id = DC.parent_column_id
    WHERE DC.parent_object_id = OBJECT_ID(N'dbo.Sessions')
      AND C.name = N'ExpiresAt'
)
BEGIN
    ALTER TABLE dbo.Sessions
        ADD CONSTRAINT DF_Sessions_ExpiresAt
        DEFAULT (DATEADD(MINUTE, 10, GETDATE()))
        FOR ExpiresAt;
END;
GO

/* Deactivate sessions that are already expired */
UPDATE dbo.Sessions
SET IsActive = 0,
    LogoutTime = COALESCE(LogoutTime, GETDATE())
WHERE IsActive = 1
  AND ExpiresAt <= GETDATE();
GO

/* Add the expiration lookup index */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.Sessions')
      AND name = N'IX_Sessions_ActiveExpiry'
)
BEGIN
    CREATE INDEX IX_Sessions_ActiveExpiry
        ON dbo.Sessions(IsActive, ExpiresAt);
END;
GO