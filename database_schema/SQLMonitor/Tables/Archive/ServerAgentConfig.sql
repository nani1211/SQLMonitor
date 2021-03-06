USE [SQLMonitor]
GO

IF OBJECT_ID('[Archive].[ServerAgentConfig]') IS NOT NULL
BEGIN
    DROP TABLE [Archive].[ServerAgentConfig];
END
GO

CREATE TABLE [Archive].[ServerAgentConfig](
    [ServerAgentConfigID] [int] NOT NULL,
	[ServerName] [nvarchar](128) NOT NULL,
    [AutoStart] [int] NOT NULL,
    [StartupAccount] [nvarchar] (128) NOT NULL,
    [JobHistoryMaxRows] [int] NOT NULL,
    [JobHistoryMaxRowsPerJob] [int] NOT NULL,
    [ErrorLogFile] [nvarchar] (255) NOT NULL,
    [EmailProfile] [nvarchar] (64) NULL,
    [FailSafeOperator] [nvarchar] (255) NULL,
    [RecordStatus] [char] (1) NOT NULL,        -- record status - used to determine if the record is active or not
    [RecordCreated] [datetime2] (0) NOT NULL   -- audit timestamp storing the date and time the record was created (is additional detail necessary?)
) ON [ARCHIVE]
GO


-- clustered index on ServerInfoID
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[Archive].[ServerAgentConfig]') AND name = N'PK_ServerAgentConfig_Archive')
ALTER TABLE [Archive].[ServerAgentConfig]
ADD  CONSTRAINT [PK_ServerAgentConfig_Archive] PRIMARY KEY CLUSTERED ([ServerAgentConfigID] ASC)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = ON, IGNORE_DUP_KEY = OFF, ONLINE = OFF, 
    ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100) ON [ARCHIVE]
GO


USE [master]
GO
