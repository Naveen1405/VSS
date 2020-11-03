#########################################################################
#### Author:		Gollamudi, Naveen
#### Create date: 2020-11-02
#### Description:	Creating the Batch for every refresh attempt 
#########################################################################


########################################################################################################################
### Define Varaible ###
########################################################################################################################
param(
    [cmdletbinding()]
	[string]$Server        =  $env:COMPUTERNAME,
    [string]$RefreshName   =  "TestWarehouse",
    [string]$VSSLoggingDB  =  "DBAMaintenance"
    )

#set the error preference
$ErrorActionPreference = "stop"
########################################################################################################################
### Create Functions ###
########################################################################################################################
function FuncWriteErrorLog
	{param($FnDetails,$FnLevel,$FnEventID)
		$EventLog = Get-EventLog -list | Where-Object {$_.Log -eq "Application"}
		$EventLog.MachineName = "."
		$EventLog.Source = "VSSRestore.ps1"
		$EventLog.WriteEntry($FnDetails,$FnLevel, $FnEventID)
    #mark the header as failed
    invoke-sqlcmd -ServerInstance $Server -Database $VSSLoggingDB -Query "EXEC Netapp.spAttachUserDB_Complete $RefreshHeaderID, 2";
	}
function FuncSQLInsert 
	{
		param($intStep, $strStepDescription, $strStepCompleteDescription)
		Invoke-Sqlcmd -QueryTimeout 3600 -ServerInstance $Server -Database $VSSLoggingDB -Query "INSERT INTO VSS.AttachUserDB_PSFailedStep (Step,StepDescription,StepCompleteDescription, RefreshHeaderID) VALUES('$intStep','$strStepDescription','$strStepCompleteDescription', $RefreshHeaderID)"
	}
#Function to load the instance metadata
function Get-EC2InstanceMetadata {
  param([string]$Path)
  (Invoke-WebRequest -Uri "http://169.254.169.254/latest/$Path").Content 
}
#Function to get Instance
function Get-VolumeDetail { 
    param([string]$DrivePath)
    Try {
      #Get instance id,AZ and region
      $InstanceId = Get-EC2InstanceMetadata "meta-data/instance-id"
      $AZ = Get-EC2InstanceMetadata "meta-data/placement/availability-zone"
      $Region = $AZ.Remove($AZ.Length - 1)  

      #Get the volumes attached to this instance
      $BlockDeviceMappings = (Get-EC2Instance -Region $Region -Instance $InstanceId).Instances.BlockDeviceMappings
      
      #Get the volume ID for the drive path provided
      $BlockDeviceMappings = $BlockDeviceMappings | ? { $_.DeviceName -eq $DrivePath }
      $VolumeID            = $BlockDeviceMappings.Ebs.VolumeID
        }
    Catch {
      Write-Host "Could not access the AWS API, therefore, VolumeId is not available. 
    Verify that you provided your access keys." -ForegroundColor Yellow
          }
     return $VolumeID 
 }
########################################################################################################################
#### Create New batch and get refresh parameters
########################################################################################################################
$RefreshHeader = Invoke-Sqlcmd -QueryTimeout 30 -ServerInstance $Server -Database $VSSLoggingDB -Query "EXEC VSS.uspAttachUserDB_CreateHeader $RefreshName"
$RefreshHeaderID = $RefreshHeader.RefreshHeaderID

#Get Refresh Parameters
$GetRefreshParametersSQL = "SELECT * FROM VSS.AttachUserDB_RefreshConfiguration WHERE RefreshName = '$RefreshName'"
$RefreshParameters = invoke-sqlcmd -Query $GetRefreshParametersSQL -ServerInstance $Server -Database $VSSLoggingDB

$DataPath         =  $RefreshParameters.DataPath
$DataDisk         =  $RefreshParameters.DataDisk
$LogPath          =  $RefreshParameters.LogPath
$LogDisk          =  $RefreshParameters.LogDisk
$KMSId            =  $RefreshParameters.EBSKMS
$SrcDataSnapId    =  $RefreshParameters.SourceDataSnapID
$SrcLogSnapId     =  $RefreshParameters.SourceLogSnapID
$RecentSnapshot   =  $RefreshParameters.UseRecent
$SrcDataVol       =  $RefreshParameters.SourceDataVol
$SrcLogVol        =  $RefreshParameters.SourceLogVol
$SrcServer        =  $RefreshParameters.SourceServer
$AvailabilityZone =  Get-EC2InstanceMetadata "meta-data/placement/availability-zone"
$InstanceID       =  Get-EC2InstanceMetadata "meta-data/instance-id"
$Region           =  $AvailabilityZone.Remove($AvailabilityZone.Length - 1)
########################################################################################################################
#### IMPORT REQUIRED MODULES ####
########################################################################################################################
#only load ps snapins if prior to powershell v4
if ($PSVersionTable.PsVersion.Major -lt 3)
{
   # Add-PSSnapin SqlServerCmdletSnapin100
   # Add-PSSnapin SqlServerProviderSnapin100
}
else
{
   # import-module SqlPS -DisableNameChecking -Force
} 

#Importing AWSPowerShel Module
try
	{
        $intStep = 1
		FuncSQLInsert $intStep "Starting" "Importing AWSPowerShell"
		$error.clear()

       # import-module AWSPowerShell -Force
    }
catch
	{
        FuncSQLInsert $intStep "Failed" "Importing AWSPowerShell"
		break
    }
FuncSQLInsert $intStep "Complete" "Importing AWSPowerShell"
########################################################################################################################
### Execute Code ###
########################################################################################################################
#Check if data and log volumes are same
if ($DataPath -eq $LogPath) {
$isDataLogSame = 1
}

#Get the data Volume ID
$DataVolumeId = $null
$DataVolumeId = Get-VolumeDetail $Datapath

#Get the Log Volume ID, if it is different from Data
$LogVolumeId = $null
if ($isDataLogsame -ne 1) {    
    $LogVolumeId = Get-VolumeDetail $Logpath
  }
########################################################################
#Detach SQL databases from earlier refresh, if they are still attached
if ($DataVolumeID -ne $null -or $LogVolumeID -ne $null) {
  write-host "Detaching the database(s)"

  try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Detaching Database(s)"
	    $error.clear()

      $SQLDetachScript = "EXEC [VSS].[uspVSS_SQL_Detach] @RefreshName = '$RefreshName' "      
      Invoke-Sqlcmd -QueryTimeout 3600 -ServerInstance $Server -Database $VSSLoggingDB -Query $SQLDetachScript
      }
  catch {
         FuncSQLInsert $intStep "Failed" "Detaching Database(s)"
		 break
        }
  FuncSQLInsert $intStep "Complete" "Detaching Database(s)"
  }
else 
 {
 write-host "No Database(s) to Detach"
 }
########################################################################
#Check if Data Volume is  attached, if so detach the volume
if ($DataVolumeID -ne $null) {
  Write-Host "Data Volume is still attached $DataVolumeId, path $DataPath on instance $InstanceID in region $Region"

  try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Detaching Data Volume"
	    $error.clear()

    Dismount-EC2Volume -VolumeId $DataVolumeId -InstanceId $InstanceID -Device $DataPath
    
    Write-Host -NoNewLine Checking $DataVolumeId

    while ((Get-EC2Volume -VolumeId $DataVolumeId).State -ne "available") {
      write-host -NoNewline "."
      sleep 5
           }
     Write-host "."
     write-host "Volume: $DataVolumeId is dismounted"  
      }
  catch {
         FuncSQLInsert $intStep "Failed" "Detaching Data Volume"
		 break
        }
  FuncSQLInsert $intStep "Complete" "Detaching Data Volume"
   }
ELSE {
  Write-Host "Data Volume is not attached"
  $intStep = $intStep+1
  FuncSQLInsert $intStep "Completed" "Data Volume not attached"
   }   
########################################################################
#Delete the Data volume
if ($DataVolumeID -ne $null) {
    if ((Get-EC2Volume -VolumeId $DataVolumeId).State -eq "available") {
    write-host "Deleting the Data Volume $DataVolumeId"
      try {
          $intStep = $intStep+1
	      FuncSQLInsert $intStep "Starting" "Deleting Data Volume"
	      $error.clear()

        Remove-EC2Volume -VolumeId $DataVolumeId -Force
           }
      catch {
          FuncSQLInsert $intStep "Failed" "Deleting Data Volume"
	      break
            }
    FuncSQLInsert $intStep "Complete" "Deleting Data Volume"
    }
}
########################################################################
#Check if Log Volume is  attached, if so detach volume
if ($LogVolumeID -ne $null) {
  Write-Host "Log Volume is still attached $LogVolumeID on instance $InstanceID in region $Region"

  try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Detaching Log Volume"
	    $error.clear()

      Dismount-EC2Volume -VolumeId $LogVolumeID -InstanceId $InstanceID
    
      Write-Host -NoNewLine Checking $LogVolumeID
      while ((Get-EC2Volume -VolumeId $LogVolumeID).State -ne "available") {
        write-host -NoNewline "."
        sleep 5
            }
       Write-host "."
       write-host "Volume: $LogVolumeID is dismounted"
        }
  catch {
         FuncSQLInsert $intStep "Failed" "Detaching Log Volume"
		 break
        }
  FuncSQLInsert $intStep "Complete" "Detaching Log Volume"
   }
ELSE {
  Write-Host "Log Volume is either not attached or same as data volume"
  $intStep = $intStep+1
  FuncSQLInsert $intStep "Completed" "Log Volume not attached"
   }
########################################################################
#Delete the Log volume
if ($LogVolumeID -ne $null) {
    if ((Get-EC2Volume -VolumeId $LogVolumeID).State -eq "available") {
    write-host "Deleting the Log Volume $LogVolumeID"
      try {
          $intStep = $intStep+1
	      FuncSQLInsert $intStep "Starting" "Deleting Log Volume"
	      $error.clear()

        Remove-EC2Volume -VolumeId $LogVolumeID -Force
           }
      catch {
          FuncSQLInsert $intStep "Failed" "Deleting Log Volume"
	      break
            }
    FuncSQLInsert $intStep "Complete" "Deleting Log Volume"
    }
}
########################################################################
#Get Data snapshot details
if ($RecentSnapshot -eq 1) {
    write-host "Getting the latest snapshot details of the Data Volume"
    
    try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Fetching Data snapshot"
	   	$error.clear()

        $DataSnapshotInfo= (Get-EC2Snapshot | ? {$_.VolumeId -eq $SrcDataVol -and $_.Status -eq "completed"} | sort {$_.StartTime} -Descending)[0]
        $DataSnapId   = $DataSnapshotInfo.SnapshotId
        $DataSnapTime = $DataSnapshotInfo.StartTime        
        }
    catch {
           FuncSQLInsert $intStep "Failed" "Fetching Data snapshot"
		   break    
          }
    FuncSQLInsert $intStep "Complete" "Fetching Data snapshot"
   }
if ($RecentSnapshot -eq 0 -and $SrcDataSnapId -ne $null) {
    write-host "Getting the snapshot details of the Data Volume for the snapshot $SrcDataSnapId"

     try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Fetching specific Data snapshot"
	   	$error.clear()
        
        $DataSnapshotInfo= Get-EC2Snapshot | ? {$_.VolumeId -eq $SrcDataVol -and $_.Status -eq "completed" -and $_.SnapshotId -eq $SrcDataSnapId}
        $DataSnapId   = $DataSnapshotInfo.SnapshotId
        $DataSnapTime = $DataSnapshotInfo.StartTime
        
        }
    catch {
           FuncSQLInsert $intStep "Failed" "Fetching specific Data snapshot"
		   break    
          }
    FuncSQLInsert $intStep "Complete" "Fetching specific Data snapshot"
    }
########################################################################
#Get Log Snapshot details, if it is not same as data vol
if ($isDataLogSame -ne 1) { 
    if ($RecentSnapshot -eq 1) {
    write-host "Getting the latest snapshot details of the Log Volume"

    try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Fetching Log snapshot"
	   	$error.clear()
        
        $LogSnapshotInfo= (Get-EC2Snapshot | ? {$_.VolumeId -eq $SrcLogVol -and $_.Status -eq "completed"} | sort {$_.StartTime} -Descending)[0]
        $LogSnapId   = $LogSnapshotInfo.SnapshotId
        $LogSnapTime = $LogSnapshotInfo.StartTime        
        }
    catch {
           FuncSQLInsert $intStep "Failed" "Fetching Log snapshot"
		   break    
          }    
    FuncSQLInsert $intStep "Complete" "Fetching Log snapshot"
   }
if ($RecentSnapshot -eq 0 -and $SrcLogSnapId -ne $null) {
    write-host "Getting the snapshot details of the Log Volume for the snapshot $SrcLogSnapId"

     try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Fetching specific Log snapshot"
	   	$error.clear()
        
        $LogSnapshotInfo= Get-EC2Snapshot | ? {$_.VolumeId -eq $SrcLogVol -and $_.Status -eq "completed" -and $_.SnapshotId -eq $SrcLogSnapId}
        $LogSnapId   = $LogSnapshotInfo.SnapshotId
        $LogSnapTime = $LogSnapshotInfo.StartTime        
        }
    catch {
           FuncSQLInsert $intStep "Failed" "Fetching specific Log snapshot"
		   break    
          }
   FuncSQLInsert $intStep "Complete" "Fetching specific Log snapshot"
    } 
 }
 else {
  write-host "Log Volume is same as Data Volume"
  }
########################################################################
#Check the time difference between Data and Log Snapshots
if ($isDataLogSame -ne 1) {
   write-host "Validating Data & Log Snapshots"
   
    $intStep = $intStep+1
    FuncSQLInsert $intStep "Starting" "Validate Snapshots"
    $error.clear()
      
    $SnapTimeDiff = (New-TimeSpan -Start $DataSnaptime -End $LogSnaptime).TotalMinutes
       if (($SnapTimeDiff -gt 2 )-eq $true -or ($SnapTimeDiff -lt -2 )-eq $true) {
       #FAIL
        Write-Host "Snapshot Validation failed"
        
        FuncSQLInsert $intStep "Failed" "Validate Snapshots"
         }
       else {
         Write-Host $SnapTimeDiff
         	
         $DataSnaptime = [datetime]$DataSnaptime 
         $LogSnaptime  = [datetime]$LogSnaptime

         FuncSQLInsert $intStep "SnapTime" $DataSnaptime
         FuncSQLInsert $intStep "Complete" "Validate Snapshots"
         }       
   }
else {
    $intStep = $intStep+1 
    FuncSQLInsert $intStep "SnapTime" $DataSnaptime      
     }
########################################################################
#Define Tags for Data Volume
$ServerLowerCase = $Server.ToLower()
$DataTag         = @{ Key ="Name"; Value = "$ServerLowerCase-vss-$DataDisk"}
$DataSnapTimeTag = @{ Key ="SnapTime"; Value = "$DataSnaptime"}

$Datatagspec = new-object Amazon.EC2.Model.TagSpecification
$Datatagspec.ResourceType = "volume"
$Datatagspec.Tags.Add($Datatag)
$Datatagspec.Tags.Add($DataSnapTimeTag)
########################################################################
#Create Data Volume
if ((Get-EC2Snapshot -SnapshotId $DataSnapId).Status -eq "completed") {
 Write-Host "Creating Data Volme from $DataSnapId Snapshot"
     try {
        $intStep = $intStep+1
		FuncSQLInsert $intStep "Starting" "Creating Data Volume"
	   	$error.clear()
            
       $NewDataVolume = ( New-EC2Volume -SnapshotId $DataSnapId `
                          -AvailabilityZone $AvailabilityZone `
                          -Encrypted 1 `
                          -KmsKeyId $KMSId `
                          -TagSpecification $Datatagspec)                                 

        # Wait for the creation to complete, this may take a while for large volumes
        Write-Host -NoNewLine Checking $NewDataVolume.VolumeId 
        while ((Get-EC2Volume -VolumeId $NewDataVolume.VolumeId).status -ne "available") {
          write-host -NoNewline "."
          sleep 5
                 }
        Write-host "."
        write-host "Volume: $NewDataVolume.VolumeId is ready"
        $NewDataVolID = $NewDataVolume.VolumeId
        }
    catch {
           FuncSQLInsert $intStep "Failed" "Creating Data Volume"
		   break    
          }
   FuncSQLInsert $intStep "Complete" "Creating Data Volume"
   }
########################################################################
#Attach Data Volume
if ((get-ec2volume -VolumeId $NewDataVolID).state -eq "available"){
 Write-Host "Attaching Data Volme from $NewDataVolID Snapshot"
  try {
      $intStep = $intStep+1
	  FuncSQLInsert $intStep "Starting" "Attaching Data Volume"
	  $error.clear()
      
      Add-EC2Volume -InstanceId $InstanceId -VolumeId $NewDataVolID -Device $DataPath

      # Wait for the attachment to complete
      Write-Host -NoNewLine Checking $NewDataVolID
      while ((Get-EC2Volume -VolumeId $NewDataVolID).State -ne "in-use") {
          write-host -NoNewline "."
          sleep 5
        }
     Write-host "."
     Write-host "Volume: $NewDataVolID is attached"
       }
  catch {
      FuncSQLInsert $intStep "Failed" "Attaching Data Volume"
      break
        }
FuncSQLInsert $intStep "Complete" "Attaching Data Volume"
}
########################################################################
#Mount Data Volume With Right Drive Letter
if ( (Get-EC2Volume -VolumeId $NewDataVolID).State -eq "in-use") {
 write-host "Mount With the Data Disk Letter"
 sleep 10
  try {
      $intStep = $intStep+1
	  FuncSQLInsert $intStep "Starting" "Mounting Data Volume"
	  $error.clear()
      
      $NewDataVolID     = $NewDataVolID.Replace(' ','')     
      $DataDiskNumber   = (get-disk | ? {$_.SerialNumber -replace "_[^ ]*$" -replace "vol", "vol-" -eq $NewDataVolID}).Number     
      $CurrentDataDrive = (get-partition -DiskNumber $DataDiskNumber).DriveLetter
      $CurrentDataDrive = $CurrentDataDrive.ToString()
      $CurrentDataDrive = $CurrentDataDrive.Replace(' ','')
           
         if  ($CurrentDataDrive -ne $DataDisk)  {                       
                   get-partition -DiskNumber $DataDiskNumber | Set-Partition -NewDriveLetter $DataDisk
                    }
      }
  catch {
      FuncSQLInsert $intStep "Failed" "Mounting Data Volume"
      break 
        }
FuncSQLInsert $intStep "Complete" "Mounting Data Volume"
}
########################################################################
#Define Tags for Log Volume
$LogTag         = @{ Key ="Name"; Value = "$ServerLowerCase-vss-$LogDisk"}
$LogSnapTimeTag = @{ Key ="SnapTime"; Value = "$LogSnaptime"}

$Logtagspec = new-object Amazon.EC2.Model.TagSpecification
$Logtagspec.ResourceType = "volume"
$Logtagspec.Tags.Add($LogTag)
$Logtagspec.Tags.Add($LogSnapTimeTag)
########################################################################
#Create Log Volume 
if ($isDataLogSame -ne 1) {
    if ((Get-EC2Snapshot -SnapshotId $LogSnapId).Status -eq "completed" ) {
     Write-Host "Creating Log Volme from $LogSnapId Snapshot"
         try {
            $intStep = $intStep+1
		    FuncSQLInsert $intStep "Starting" "Creating Log Volume"
	   	    $error.clear()
            
           $NewLogVolume = ( New-EC2Volume -SnapshotId $LogSnapId `
                              -AvailabilityZone $AvailabilityZone `
                              -Encrypted 1 `
                              -KmsKeyId $KMSId `
                              -TagSpecification $Logtagspec)                                 

            # Wait for the creation to complete, this may take a while for large volumes
            Write-Host -NoNewLine Checking $NewLogVolume.VolumeId 
            while ((Get-EC2Volume -VolumeId $NewLogVolume.VolumeId).status -ne "available") {
              write-host -NoNewline "."
              sleep 5
                     }
            Write-host "."
            write-host "Volume: $NewLogVolume.VolumeId is ready"
            $NewLogVolID = $NewLogVolume.VolumeId
            }
        catch {
               FuncSQLInsert $intStep "Failed" "Creating Log Volume"
		       break    
              }
       FuncSQLInsert $intStep "Complete" "Creating Log Volume"
    }
}
########################################################################
#Attach Log Volume
if ($isDataLogSame -ne 1) { 
    if ( (get-ec2volume -VolumeId $NewLogVolID).state -eq "available"){
     Write-Host "Attaching Log Volme from $NewLogVolID Snapshot"
      try {
          $intStep = $intStep+1
	      FuncSQLInsert $intStep "Starting" "Attaching Log Volume"
	      $error.clear()
      
          Add-EC2Volume -InstanceId $InstanceId -VolumeId $NewLogVolID -Device $LogPath

          # Wait for the attachment to complete
          Write-Host -NoNewLine Checking $NewLogVolID
          while ((Get-EC2Volume -VolumeId $NewLogVolID).State -ne "in-use") {
              write-host -NoNewline "."
              sleep 5
            }
         Write-host "."
         Write-host "Volume: $NewLogVolID is attached"
           }
      catch {
          FuncSQLInsert $intStep "Failed" "Attaching Log Volume"
          break
            }
    FuncSQLInsert $intStep "Complete" "Attaching Log Volume"
    }

}
########################################################################
#Mount Log Volume
if ($isDataLogSame -ne 1) {
    if ( (Get-EC2Volume -VolumeId $NewLogVolID).State -eq "in-use") {
     write-host "Mount With the Log Disk Letter"
     sleep 10
      try {
          $intStep = $intStep+1
	      FuncSQLInsert $intStep "Starting" "Mounting Log Volume"
	      $error.clear()
      
          $NewLogVolID     = $NewLogVolID.Replace(' ','')     
          $LogDiskNumber   = (get-disk | ? {$_.SerialNumber -replace "_[^ ]*$" -replace "vol", "vol-" -eq $NewLogVolID}).Number     
          $CurrentLogDrive = (get-partition -DiskNumber $LogDiskNumber).DriveLetter
          $CurrentLogDrive = $CurrentLogDrive.ToString()
          $CurrentLogDrive = $CurrentLogDrive.Replace(' ','')
           
             if  ($CurrentLogDrive -ne $LogDisk)  {                       
                       get-partition -DiskNumber $LogDiskNumber | Set-Partition -NewDriveLetter $LogDisk
                        }
          }
      catch {
          FuncSQLInsert $intStep "Failed" "Mounting Log Volume"
          break 
            }
    FuncSQLInsert $intStep "Complete" "Mounting Log Volume"
    }
}
########################################################################
#Attach SQL Databases
Write-host "Attaching SQL Database(s)"
try {
    $intStep = $intStep+1
	FuncSQLInsert $intStep "Starting" "Attaching Database(s)"
	$error.clear()

    $SQLAttachScript = "EXEC [VSS].[uspVSS_SQL_attach] @RefreshName = '$RefreshName' "
    Invoke-Sqlcmd -QueryTimeout 3600 -ServerInstance $Server -Database $VSSLoggingDB -Query $SQLAttachScript
    }
catch {
     FuncSQLInsert $intStep "Failed" "Attaching Database(s)"
     break 
      }
FuncSQLInsert $intStep "Complete" "Attaching Database(s)"
########################################################################
#Mark the process Completed~
$intStep = $intStep+1
FuncSQLInsert $intStep "Process Complete" "VSS Refresh"
$error.clear()