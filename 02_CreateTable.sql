/**************************************************************************************************************************************************************************************************************/
USE [DBAMaintenance]
GO

/****** Create Table [VSS].[AttachUserDB_PSFailedStep]  ******/

/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Create a table for capturing progress of refresh attempt */
-- =============================================
IF NOT EXISTS (SELECT 1 FROM [sys].[tables] AS T JOIN [sys].[schemas] AS S ON T.[schema_id]=S.[schema_id] WHERE S.[name]='VSS' AND T.[name]='AttachUserDB_PSFailedStep')
BEGIN
CREATE TABLE [VSS].[AttachUserDB_PSFailedStep](
	[AttachUserDB_PSFailedStepID] [INT] IDENTITY(1,1) NOT NULL,
	[Step] [INT] NOT NULL,
	[StepDescription] [VARCHAR](50) NULL,
	[StepCompleteDescription] [VARCHAR](8000) NULL,
	[CreateDate] [DATETIME] NOT NULL DEFAULT GETDATE(),
	[RefreshHeaderID] [INT] NOT NULL,
 CONSTRAINT [PK:VSS.AttachUserDB_PSFailedStep:AttachUserDB_PSFailedStepID] PRIMARY KEY CLUSTERED 
   ([RefreshHeaderID] ASC, [AttachUserDB_PSFailedStepID] ASC)
 WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100) ) 
END

/**************************************************************************************************************************************************************************************************************/
USE [DBAMaintenance]
GO

/****** Create Table [VSS].[AttachUserDB_RefreshHeader]  ******/
/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Create a table for Refresher Header */
-- =============================================
IF NOT EXISTS (SELECT 1 FROM [sys].[tables] AS T JOIN [sys].[schemas] AS S ON T.[schema_id]=S.[schema_id] WHERE S.[name]='VSS' AND T.[name]='AttachUserDB_RefreshHeader')
BEGIN

CREATE TABLE [VSS].[AttachUserDB_RefreshHeader](
	[RefreshHeaderID] [INT] IDENTITY(1,1) NOT NULL,
	[RefreshStartDate] [DATETIME2](3) NOT NULL DEFAULT SYSDATETIME(),
	[RefreshEndDate] [DATETIME2](3) NULL,
	[RefreshStatus] [TINYINT] NOT NULL,
	[RefreshName] [VARCHAR](255) NOT NULL,
PRIMARY KEY CLUSTERED 
([RefreshHeaderID] ASC)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100) 
) ;

ALTER TABLE [VSS].[AttachUserDB_RefreshHeader] ADD  DEFAULT ((0)) FOR [RefreshStatus];
 
END

/**************************************************************************************************************************************************************************************************************/
USE [DBAMaintenance]
GO

/****** Create Table [VSS].[AttachUserDB_RefreshConfiguration]  ******/
/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Create a table for Refresh Configuration */
-- =============================================
IF NOT EXISTS (SELECT 1 FROM [sys].[tables] AS T JOIN [sys].[schemas] AS S ON T.[schema_id]=S.[schema_id] WHERE S.[name]='VSS' AND T.[name]='AttachUserDB_RefreshConfiguration')
BEGIN
CREATE TABLE [VSS].[AttachUserDB_RefreshConfiguration](
	[AttachUserDB_RefreshConfigurationID] [int] IDENTITY(1,1) NOT NULL PRIMARY KEY,
	[RefreshName] [VARCHAR](255) NOT NULL,
	[DataPath] [VARCHAR](50) NOT NULL,
	[DataDisk] [VARCHAR](1) NOT NULL,
	[LogPath] [VARCHAR](50) NOT NULL,
	[LogDisk] [VARCHAR](1) NOT NULL,
	[EBSKMS] [varchar](255) NULL,
	[SourceDataSnapID] [varchar](255) NULL,
	[SourceLogSnapID] [varchar](255) NULL,
	[UseRecent] [BIT] NOT NULL,
	[SourceDataVol] [VARCHAR](30) NOT NULL,
	[SourceLogVol] [VARCHAR](30) NOT NULL,
	[SourceServer] [VARCHAR](255) NOT NULL
)  
END

/**************************************************************************************************************************************************************************************************************/
USE [DBAMaintenance]
GO

/****** Create Table [VSS].[AttachUserDB_RefreshConfigurationFiles]  ******/
/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Create a table for Refresh Configuration details */
-- =============================================
IF NOT EXISTS (SELECT 1 FROM [sys].[tables] AS T JOIN [sys].[schemas] AS S ON T.[schema_id]=S.[schema_id] WHERE S.[name]='VSS' AND T.[name]='AttachUserDB_RefreshConfigurationFiles')
BEGIN
CREATE TABLE [VSS].[AttachUserDB_RefreshConfigurationFiles](
	[AttachUserDB_RefreshConfigurationID] [int] NOT NULL,
	[DatabaseName] [varchar](255) NOT NULL,
	[Prefix] [varchar](255) NULL,
	[Suffix] [varchar](255) NULL,
 CONSTRAINT [PK:VSS.AttachUserDB_RefreshConfigurationFiles:AttachUserDB_RefreshConfigurationID:AttachUSerDB_MasterFilesID] PRIMARY KEY CLUSTERED 
([AttachUserDB_RefreshConfigurationID] ASC, [DatabaseName] ASC)
 WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100)
 ) ;
 
ALTER TABLE [VSS].[AttachUserDB_RefreshConfigurationFiles]  WITH CHECK ADD FOREIGN KEY([AttachUserDB_RefreshConfigurationID])
REFERENCES [VSS].[AttachUserDB_RefreshConfiguration] ([AttachUserDB_RefreshConfigurationID])
ON DELETE CASCADE;
 
END

/**************************************************************************************************************************************************************************************************************/
USE [DBAMaintenance]
GO

/****** Create Table [VSS].[AttachUserDB_MasterFiles]  ******/
/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Create a table for database file information */
-- =============================================
IF NOT EXISTS (SELECT 1 FROM [sys].[tables] AS T JOIN [sys].[schemas] AS S ON T.[schema_id]=S.[schema_id] WHERE S.[name]='VSS' AND T.[name]='AttachUserDB_MasterFiles')
BEGIN
CREATE TABLE [VSS].[AttachUserDB_MasterFiles](
	[AttachUserDB_MasterFilesID] [int] IDENTITY(1,1) NOT NULL PRIMARY KEY,
	[Database] [varchar](200) NOT NULL,
	[FileID] [varchar](200) NOT NULL,
	[Type] [varchar](200) NOT NULL,
	[Physical_Name] [varchar](300) NOT NULL,
	[LastActionDate] [datetime] NULL,
	[SourceServer] [varchar](255) NULL,
 )

END
