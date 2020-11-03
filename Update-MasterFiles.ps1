
#########################################################################
#### Author:		Gollamudi, Naveen
#### Create date: 2020-11-02
#### Description:	Creating the Batch for every refresh attempt 
#########################################################################

Import-Module "S:\Powershell\Modules\Update-MasterFiles" -Force

Update-MasterFiles -Refreshname "TestWarehouse" -Test $false -Verbose