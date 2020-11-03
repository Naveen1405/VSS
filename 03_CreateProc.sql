/**************************************************************************************************************************************************************************************************************/
USE [DBAMaintenance]
GO

/****** Create proc [VSS].[uspAttachUserDB_CreateHeader]  ******/


/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	Creating the Batch for every refresh attempt */
-- =============================================
CREATE OR ALTER PROCEDURE [VSS].[uspAttachUserDB_CreateHeader]
@RefreshName varchar(255)
AS

INSERT INTO VSS.AttachUserDB_RefreshHeader
		(RefreshName)
VALUES	(@RefreshName);

SELECT SCOPE_IDENTITY() AS RefreshHeaderID
GO


/**************************************************************************************************************************************************************************************************************/
USE [DBAMaintenance]
GO

/****** Create proc [VSS].[uspVSS_SQL_Detach]  ******/


/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Detach databases from earlier refresh */
-- =============================================

CREATE OR ALTER PROC [VSS].[uspVSS_SQL_Detach] (
   @RefreshName VARCHAR(20))
AS
BEGIN
--DECLARE @RefreshName VARCHAR(20)='TestWarehouse'

SET NOCOUNT ON;

DECLARE @DatabaseLoop VARCHAR(255);
DECLARE @DBDetachScript NVARCHAR(4000);
DECLARE @DetachAndOfflineStatements TABLE
	(DatabaseName VARCHAR(255) NOT NULL PRIMARY KEY
	, OfflineStatement VARCHAR(4000));

IF OBJECT_ID('tempdb..#DatabaseToDetach') IS NOT NULL 
 BEGIN 
	DROP TABLE #DatabaseToDetach
END

	CREATE TABLE #DatabaseToDetach ([DBNo] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
									[DBName] VARCHAR(255) NOT NULL,								
									[FullDBName] VARCHAR(275))  ;
 

INSERT INTO #DatabaseToDetach
(
    [DBName],
	[FullDBName]
)
SELECT CF.[DatabaseName],
	   COALESCE( CF.[Prefix],'')+CF.[DatabaseName]+COALESCE( CF.[suffix],'') 
       FROM [VSS].[AttachUserDB_RefreshConfigurationFiles] AS CF
 INNER JOIN [VSS].[AttachUserDB_RefreshConfiguration] AS C ON CF.[AttachUserDB_RefreshConfigurationID]=c.[AttachUserDB_RefreshConfigurationID]
 AND C.[RefreshName]=@RefreshName;


 INSERT INTO @DetachAndOfflineStatements
		(DatabaseName, OfflineStatement)
 SELECT FullDBName,
      'IF EXISTS (SELECT 1 FROM sys.databases where name = '''  + FullDBName +  ''') BEGIN '
      +'ALTER DATABASE [' + FullDBName + '] SET OFFLINE WITH ROLLBACK IMMEDIATE;' + CHAR(10)
		+ 'EXEC master.dbo.sp_detach_db [' + FullDBName + '] ; END;'
	FROM #DatabaseToDetach

/* start a loop to drop the dbs */
		SELECT @DatabaseLoop = MIN(DatabaseName)
		FROM @DetachAndOfflineStatements AS DAOS;

		/* start a loop to process */
		WHILE @DatabaseLoop IS NOT NULL
		BEGIN;

		SELECT @DBDetachScript= OfflineStatement
		 FROM @DetachAndOfflineStatements AS DAOS
		WHERE DAOS.DatabaseName=@DatabaseLoop

		
		EXEC master..sp_executesql @DBDetachScript;

		SELECT @DatabaseLoop = MIN(DatabaseName)
			FROM @DetachAndOfflineStatements AS DAOS
		WHERE DAOS.DatabaseName > @DatabaseLoop;
		END;

END;

/**************************************************************************************************************************************************************************************************************/
USE DBAMaintenance;
GO

/****** Create proc [VSS].[uspVSS_SQL_attach]  ******/


/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Attach Databases */
-- =============================================
CREATE OR ALTER PROC [VSS].[uspVSS_SQL_Attach] (
   @RefreshName VARCHAR(20))
AS
BEGIN
--DECLARE @RefreshName VARCHAR(20)='TestWarehouse'

SET NOCOUNT ON;

DECLARE @RefreshConfigID INT;
DECLARE @SourceServer VARCHAR(50);
DECLARE @strDataLocation CHAR(1);
DECLARE @strLogLocation CHAR(1);
DECLARE @DatabaseLoop VARCHAR(255);
DECLARE @SQLAttachDB NVARCHAR(4000);
DECLARE @DatabaseToAttach NVARCHAR(4000);
DECLARE @AttachDSQLParameters NVARCHAR(4000) = N'@DatabaseToAttach sysname, @SQLAttachDB nvarchar(4000)';

DECLARE @AttachStatements TABLE
(
    DatabaseName VARCHAR(255) NOT NULL PRIMARY KEY,
    AttachDBCommand VARCHAR(4000)
);


SELECT @RefreshConfigID = [AttachUserDB_RefreshConfigurationID],
       @SourceServer = [SourceServer],
       @strDataLocation = [DataDisk],
       @strLogLocation = [LogDisk]
FROM [VSS].[AttachUserDB_RefreshConfiguration]
WHERE [RefreshName] = @RefreshName;



INSERT INTO @AttachStatements
(
    DatabaseName,
    AttachDBCommand
)
SELECT DISTINCT
       COALESCE(AUDRCF.Prefix, '') + AUDRCF.DatabaseName + COALESCE(AUDRCF.suffix, ''),
       'IF NOT EXISTS (SELECT 1 FROM sys.databases where name = ''' + COALESCE(AUDRCF.Prefix, '') + AUDRCF.DatabaseName
       + COALESCE(AUDRCF.suffix, '') + ''') BEGIN 
CREATE DATABASE [' + COALESCE(AUDRCF.Prefix, '') + AUDRCF.DatabaseName + COALESCE(AUDRCF.suffix, '') + '] ON'
       + CHAR(10)
       + STUFF(
         (
             SELECT ',(FILENAME = ''' + CASE
                                            WHEN Type = 0 THEN
                                                @strDataLocation
                                            WHEN Type = 1 THEN
                                                @strLogLocation
                                        END + SUBSTRING(Physical_Name, 2, LEN(AUDMF.Physical_Name)) + ''')' + CHAR(10)
             FROM vss.AttachUserDB_MasterFiles AS AUDMF
             WHERE AUDMF.[DATABASE] = AUDRCF.DatabaseName
                   AND AUDMF.SourceServer = @SourceServer
             ORDER BY [DATABASE],
                      Type,
                      CONVERT(INT, FileID)
             FOR XML PATH('')
         ),
         1,
         1,
         ''
              ) + ' FOR ATTACH;' + CHAR(10) + 'IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseToAttach)'
       + CHAR(10) + 'BEGIN' + CHAR(10)
       + '		DECLARE @ErrorMessage varchar(4000) = ''Attach failed for database '' + @DatabaseToAttach + ''. Attach script run : '' + @SQLAttachDB;'
       + CHAR(10) + '		THROW 50000, @ErrorMessage, 7;' + CHAR(10) + 'END; 
END;'  AS AttachDBCommand
FROM vss.AttachUserDB_RefreshConfigurationFiles AS AUDRCF
WHERE @RefreshConfigID = AUDRCF.AttachUserDB_RefreshConfigurationID;


/* Get the first database to attach */
SELECT @DatabaseLoop = MIN(DatabaseName)
FROM @AttachStatements AS TS;

/* loop through the dbs and attach them */
WHILE @DatabaseLoop IS NOT NULL
BEGIN;

    /* populate the variables*/
    SELECT @SQLAttachDB = AttachDBCommand,
           @DatabaseToAttach = DatabaseName
    FROM @AttachStatements AS RS
    WHERE RS.DatabaseName = @DatabaseLoop;


    /* run the commands*/
    BEGIN;
        /* attach the db */
        PRINT 'Executing statement';
        EXEC master..sp_executesql @SQLAttachDB,
                                   @AttachDSQLParameters,
                                   @DatabaseToAttach = @DatabaseToAttach,
                                   @SQLAttachDB = @SQLAttachDB;
        PRINT 'Statement Complete';
    END;


    /* get the next database*/
    SELECT @DatabaseLoop = MIN(DatabaseName)
    FROM @AttachStatements AS TS
    WHERE TS.DatabaseName > @DatabaseLoop;

 END;
END;
/**************************************************************************************************************************************************************************************************************/

USE [DBAMaintenance]
GO

/****** Create proc [VSS].[uspCheckRefreshSuccessful]  ******/

/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	Validate whether the refresh successfully restored all databases */
-- =============================================
CREATE OR ALTER PROCEDURE [VSS].[uspCheckRefreshSuccessful]
	@RefreshName VARCHAR(255)
AS
BEGIN
--DECLARE @RefreshName VARCHAR(255)='TestWarehouse'
	SET NOCOUNT ON;

	/* declare variables */
	DECLARE	@DatabaseList VARCHAR(8000)
	,	@ErrorMessage VARCHAR(8000)
	,   @maxRefreshHeaderID INT;

	SELECT @maxRefreshHeaderID = MAX([refreshHeaderID]) FROM [VSS].[AttachUserDB_PSFailedStep]

    /* check that the procedure wrote the completion step */
	IF NOT EXISTS ( SELECT	1
					FROM	[VSS].[AttachUserDB_PSFailedStep] AS AUDPFS
					WHERE	AUDPFS.[StepCompleteDescription] = 'VSS Refresh'
					AND [StepDescription] = 'Process Complete'
					AND AUDPFS.[RefreshHeaderID] = @maxRefreshHeaderID)
		BEGIN
			
			SET @ErrorMessage = 'VSS Refresh Process didn''t complete correctly for refresh ' + @RefreshName + ' on server ' + @@SERVERNAME;
			
			THROW 50000, @ErrorMessage, 1;
		END;

	/* Check that all the databases for the refresh were correctly attached */
	IF EXISTS ( SELECT	1
				FROM	[VSS].[AttachUserDB_RefreshConfigurationFiles] AS AUDRCF
				INNER JOIN [VSS].[AttachUserDB_RefreshConfiguration] AS AUDRC
						ON AUDRC.[AttachUserDB_RefreshConfigurationID] = AUDRCF.[AttachUserDB_RefreshConfigurationID]
				LEFT OUTER JOIN [sys].[databases] AS D
						ON COALESCE( AUDRCF.[Prefix],'')+AUDRCF.[DatabaseName]+COALESCE( AUDRCF.[suffix],'') = D.[name]
				WHERE	D.[name] IS NULL
						AND AUDRC.[RefreshName] = @RefreshName )
		BEGIN

			/* populate a variable with the list of databases not attached */
			SELECT	@DatabaseList = STUFF((SELECT	',' + AUDRCF.[DatabaseName]
										   FROM		VSS.[AttachUserDB_RefreshConfigurationFiles] AS AUDRCF
										   INNER JOIN VSS.[AttachUserDB_RefreshConfiguration] AS AUDRC
													ON AUDRC.[AttachUserDB_RefreshConfigurationID] = AUDRCF.[AttachUserDB_RefreshConfigurationID]
										   LEFT OUTER JOIN [sys].[databases] AS D
													ON COALESCE( AUDRCF.[Prefix],'')+AUDRCF.[DatabaseName]+COALESCE( AUDRCF.[suffix],'') = D.[name]
										   WHERE	D.[name] IS NULL
													AND AUDRC.[RefreshName] = @RefreshName
										  FOR  XML PATH('')),1,1,'');
			/* set the error message and throw the error */
			SET @ErrorMessage = 'The following databases were not successfully attached for refresh ' + @RefreshName + ': ' + @DatabaseList;
			THROW 50000, @ErrorMessage, 1;
		END;
END;
;