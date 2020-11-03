USE [DBAMaintenance]
GO

/****** Create schema [VSS] if not exists  ******/
/* =============================================
-- Author:		Gollamudi, Naveen
-- Create date: 2020-11-02
-- Description:	To Create VSS Schema */
-- =============================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='VSS')
BEGIN
EXEC ('CREATE SCHEMA [VSS] AUTHORIZATION [dbo]')
END
