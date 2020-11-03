#########################################################################
#### Author:		Gollamudi, Naveen
#### Create date: 2020-11-02
#### Description:	Creating the Batch for every refresh attempt 
#########################################################################


 function Update-MasterFiles
{
    [cmdletbinding()]
    param([string]$TargetServer = $env:COMPUTERNAME
        , [boolean]$Test = $true
        , [string]$RefreshName)
    
   
   #Get the Source Server
   $GetSourceServer = "SELECT SourceServer FROM DBAMaintenance.VSS.AttachUserDB_RefreshConfiguration WHERE RefreshName = '$RefreshName'"

    $SourceServerPar    = invoke-sqlcmd -Query $GetSourceServer -ServerInstance $TargetServer
    $SourceServer  = $SourceServerPar.SourceServer


    #Generate SQL Statement for getting list of databases & files
    $DBFileQuery =  "SELECT DB_NAME(database_id) AS DatabaseName
    , mf.file_id
    , mf.type
    , mf.physical_name    
    , '$SourceServer' AS ServerName
    FROM sys.master_files AS mf
    where DB_NAME(database_id) in ('TMGBankingWarehouse','TMGBankingWarehouseArchive','TMGBankingWarehousestage','TMGMastercardClearing','TMGMasterCardClearingStage')
    and database_id>4"

    #run the queries
    $MasterDBs = invoke-sqlcmd -ServerInstance $SourceServer -Query $DBFileQuery
       

    #insert all the rows into our table
    ForEach ($DB in $MasterDBs)
    {
        $InsertStatement = "WITH SourceSvr AS (SELECT [Database], FileID, Type, Physical_Name,LastActionDate, SourceServer FROM DBAMaintenance.VSS.AttachUserDB_MasterFiles WHERE SourceServer = '$($DB.Servername)')
                            MERGE INTO SourceSvr AS t
                            USING (VALUES ('$($DB.DatabaseName)', $($DB.file_id), '$($DB.Type)', '$($DB.Physical_Name)', '$($DB.ServerName)')) AS s
                            (DatabaseName, FileID, [Type],[Physical_Name], [ServerName])
	                            ON t.[Database] = s.[DatabaseName]
	                            AND t.[FileID] = s.[FileID]
                            WHEN MATCHED AND (t.[Type] <> s.[Type]
					                            OR t.Physical_Name <> s.Physical_Name)
	                            THEN UPDATE SET t.[Type] = s.[Type]
					                            , t.Physical_Name  = s.Physical_Name
                                                , t.LastActionDate = getdate()
                            WHEN NOT MATCHED BY TARGET
	                            THEN INSERT ([Database], [FileID], [Type], Physical_Name, LastActionDate, SourceServer)
	                            VALUES (s.DatabaseName, s.FileID, s.TYPE, s.Physical_Name,getdate(), s.ServerName);"
        try
        {
            write-verbose "Populating MasterFiles for file $($DB.physical_name)"
            if ($Test -eq $false)
            {
                invoke-sqlcmd -Query $InsertStatement -ServerInstance $TargetServer -Database "DBAMaintenance"
            }
        }
        catch
        {
             Write-Error $_
             [System.Environment]::Exit(1)
        }
        write-output $InsertStatement
    
    }
}

export-modulemember -function Update-MasterFiles