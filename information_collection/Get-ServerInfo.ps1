param([String]$ServerName = '',
	  [String]$DatabaseName = '',
      [String]$MonitorProfile = '',
      [String]$MonitorProfileType = '',
	  [String]$QueryTimeout = 30)

# 
# Usage: 
#     .\Get-ServerInfo.ps1 -ServerName "Server Name" -DatabaseName "SQL Monitor Database" -MonitorProfile "Monitor Profile" -MonitorProfileType "Profile Type"
#     Will run the function (if all input parameters are present and valid)
#

# local variables declared and set to store values passed into script since two of the latter were being initialised when declared in one of the imported scripts
$ServerInstance = $ServerName
$Database = $DatabaseName
$ProfileName = $MonitorProfile
$ProfileType = $MonitorProfileType

# Global params
$CurrentPath = Get-Location
. "$($CurrentPath)\Community_Functions.ps1"
. "$($CurrentPath)\Test-NetworkConnection.ps1"

#------------------------------------------------------------# 

function Get-ServerInfo() {
    [CmdletBinding()]  
    param(  
    [Parameter(Position=0, Mandatory=$true)] [string]$ServerInstance, 
    [Parameter(Position=1, Mandatory=$true)] [string]$Database,
    [Parameter(Position=2, Mandatory=$true)] [string]$ProfileName,
    [Parameter(Position=3, Mandatory=$true)] [string]$ProfileType,
	[Parameter(Position=4, Mandatory=$false)] [string]$QueryTimeout = 360
    )  
    
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | out-null
    
    # start here
    "{0} : ============================== " -f $(Get-Date -Format "HH:mm:ss")
    "{0} : Starting function: Get-ServerInfo" -f $(Get-Date -Format "HH:mm:ss")
    "{0} : Server Name:       {1}" -f $(Get-Date -Format "HH:mm:ss"), $ServerInstance
    "{0} : Database Name:     {1}" -f $(Get-Date -Format "HH:mm:ss"), $Database
    "{0} : Profile Name:      {1}" -f $(Get-Date -Format "HH:mm:ss"), $ProfileName
    "{0} : Profile Type:      {1}" -f $(Get-Date -Format "HH:mm:ss"), $ProfileType
	"{0} : Query Timeout:     {1}" -f $(Get-Date -Format "HH:mm:ss"), $QueryTimeout
    "{0} : ============================== " -f $(Get-Date -Format "HH:mm:ss")
    
    # $scriptroot = "$($CurrentPath)\scripts\"
    $scriptroot = ".\scripts\"

    # get profile (incl, script names and scripts)
    $sql = "EXEC dbo.uspGetProfile '{0}', '{1}';" -f $ProfileName, $ProfileType
    $scripts = Invoke-Sqlcmd2 -ServerInstance $ServerInstance -Database $Database -Query $sql -QueryTimeout $QueryTimeout

    # get list of servers
    $sql = "EXEC dbo.uspGetServers;"
    $ServerInstances = Invoke-Sqlcmd2 -ServerInstance $ServerInstance -Database $Database -Query $sql -QueryTimeout $QueryTimeout
	
    # clear
    $sql = $null

	if ($scripts.Table.Rows.Count -gt 0) {
        Foreach ($Server in $ServerInstances) {
            $ServerName = $Server.ServerName
            $TcpPort = $Server.SqlTcpPort
            $InstanceName = "$ServerName,$TcpPort"
            "{0} : Processing server: {1}" -f $(Get-Date -Format "HH:mm:ss"), $InstanceName

            # test connection
            $TestConnection = Test-Port -hostname $ServerName -port $TcpPort
            if ($TestConnection -eq $true) {
                # test database authentication
                $TestAuthentication = Test-DatabaseConnection -InstanceName $InstanceName
                if ($TestAuthentication -eq $false) {
                    Write-Warning "Could not log on to $ServerName on port $TcpPort"
                }
            }
            else {
                Write-Warning "Network access to $ServerName on port $TcpPort not available"
            }

            # check if the connection test was successful
            if (($TestConnection -eq $true) -and ($TestAuthentication -eq $true)) {
                Foreach ($script in $scripts) {
                    $scriptname = $scriptroot + $script.ScriptName + ".sql"
                    $tablename = $script.ScriptName
                    $intervalminutes = $script.IntervalMinutes
                    # the script that should be executed, retrieved from the database
                    $executescript = $result.ExecuteScript

                    # check that the script file exists
                    if (Test-Path $scriptname -PathType Leaf) {
                        # check when the script was last run and compare to the pre-defined value for how many minutes should have elapsed
                        # this will avoid that say, a script that should run Monthly is run multiple times during the month
                        # the COALESCE function will either return the value of the most recent RecordCreated column for that server OR the value 600,000 (which is more than 1 year in minutes)
                        $sql = "SELECT COALESCE(DATEDIFF(N, MAX([RecordCreated]), CURRENT_TIMESTAMP), 600000) AS [MinutesElapsed] FROM $($ProfileName).$($tablename) WHERE [ServerName] = '$($ServerName)' AND [RecordStatus] = 'A';"
                        $result = Invoke-Sqlcmd2 -ServerInstance $ServerInstance -Database $Database -Query $sql -QueryTimeout $QueryTimeout
                        $minuteselapsed = $result.MinutesElapsed
                        $result = $null

                        # compare values and handle processing (greater than or equal to comparison)
                        if ($minuteselapsed -ge $intervalminutes) {

                            # run any script marked for pre-execution
                            $preexecutescript = $script.PreExecuteScript
                            # NOTE: if NOT IsNullOrEmpty...
                            if (![string]::IsNullOrEmpty($preexecutescript)) {
                                # replace the parameter with the server name
                                $preexecutescript = $preexecutescript -f $ServerName
                                # execute the query against the monitoring database
                                $preexecuteresult = Invoke-Sqlcmd2 -ServerInstance $ServerInstance -Database $Database -Query $preexecutescript -QueryTimeout $QueryTimeout
                            }

                            "{0} : Running script:    {1}" -f $(Get-Date -Format "HH:mm:ss"), $scriptname
                            # run the script retrieved from the database, otherwise load it from the file
                            if ([string]::IsNullOrEmpty($executescript)) {
                                $sql = Get-Content -Path $scriptname -Raw
                            }
                            else {
                                $sql = $executescript
                            }
                            # replace the script parameter with the result obtained
                            # NOTE: if NOT IsNullOrEmpty...
                            if (![string]::IsNullOrEmpty($preexecuteresult)) {
                                $sql = $sql -f $preexecuteresult.Output
                            }
                            # run and store the output in a data table variable
                            try {
                                $result = Invoke-Sqlcmd2 -ServerInstance $InstanceName -Database master -Query $sql.ToString() -QueryTimeout $QueryTimeout
                                $ErrorMessage = $null
                            }
                            catch {
                                $ErrorMessage = $_.Exception.Message
                                Write-Warning $ErrorMessage
                            }

                            # check if the data retrieval was successful
                            if ([string]::IsNullOrEmpty($ErrorMessage)) {
                                $dt = $result | Out-DataTable
                                $dtRowCount = $dt.Rows.Count

                                if ($dtRowCount -gt 0) {
                                    # workaround to remove excess columns added when converting to data table - start
                                    $dt.Columns.Remove("RowError")
                                    $dt.Columns.Remove("RowState")
                                    $dt.Columns.Remove("Table")
                                    $dt.Columns.Remove("ItemArray")
                                    $dt.Columns.Remove("HasErrors")
                                    # workaround to remove excess columns added when converting to data table - start
                                }

                                # update the status for older data
                                $sql = "IF EXISTS (SELECT 1 FROM $($ProfileName).$($tablename) WHERE [ServerName] = '$($ServerName)' AND [RecordStatus] = 'A') UPDATE $($ProfileName).$($tablename) SET [RecordStatus] = 'H' WHERE [ServerName] = '$($ServerName)' AND [RecordStatus] = 'A';"
                                Invoke-Sqlcmd2 -ServerInstance $ServerInstance -Database $Database -Query $sql -QueryTimeout $QueryTimeout

                                # write data extracted from remote server to the central table
                                if ($dtRowCount -gt 0) {
                                    Write-DataTable -Data $dt -ServerInstance $ServerInstance -Database $Database -TableName "$($ProfileName).$($tablename)"
                                }
                            }
                            # clean up
                            $ErrorMessage = $null
                            $executescript = $null
                            $result = $null
                            $dt = $null
                            $dtRowCount = 0
                            $preexecutescript = ""
                            $preexecuteresult = $null
                        }
                        # script has been executed against the current server in the past N minutes
                        else {
                            $ts =  [timespan]::fromminutes($minuteselapsed)
                            $age = New-Object DateTime -ArgumentList $ts.Ticks

                            $msg = "" 

                            if ($($age.Year-1) -gt 0) { $msg += " " + $($age.Year-1).ToString() + " Years" }
                            if ($($age.Month-1) -gt 0) { $msg += " " + $($age.Month-1).ToString() + " Months" }
                            if ($($age.Day-1) -gt 0) { $msg += " " + $($age.Day-1).ToString() + " days" }
                            if ($($age.Hour) -gt 0) { $msg += " " + $($age.Hour).ToString() + " hours" }
                            if ($($age.Minute) -gt 0) { $msg += " " + $($age.Minute).ToString() + " minutes" }
                            #if ($($age.second) -gt 0) { $msg += " " + $($age.second).ToString() + " seconds" }

                            $msg += " ago"

                            "{0} : Script {1} was last run$msg." -f $(Get-Date -Format "HH:mm:ss"), $scriptname
                        }
                    }
                    # script file does not exist
                    else {
                        "{0} : Script {1} not found." -f $(Get-Date -Format "HH:mm:ss"), $scriptname
                    }
                    $scriptname = $null
                    $tablename = $null
                    $intervalminutes = $null
                }
            }
            "{0} : Completed server:  {1}" -f $(Get-Date -Format "HH:mm:ss"), $InstanceName
            "{0} : ------------------------------ " -f $(Get-Date -Format "HH:mm:ss")
            $ServerName = $null
            $InstanceName = $null
        }
    }
    else {
        Write-Warning "No scripts found for the $ProfileType profile!"
    }
    "{0} : Done" -f $(Get-Date -Format "HH:mm:ss")
    "{0} : ============================== " -f $(Get-Date -Format "HH:mm:ss")
}

Clear-Host
# run this only if the parameters have been passed to the script
# interface implemented to be called from Windows Task Scheduler or similar applications
if (($ServerInstance -ne '') -and ($Database -ne '') -and ($ProfileName -ne '') -and ($ProfileType -ne '')) {
    Get-ServerInfo -ServerInstance $ServerInstance -Database $Database -ProfileName $ProfileName -ProfileType $ProfileType -QueryTimeout $QueryTimeout
}
# otherwise, do nothing
