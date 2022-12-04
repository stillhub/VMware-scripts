# Script to reclaim space on VMFS version 5 datastores.
# Script created by Jared Stillwell
# Version: 1.0
#
# Notes:
#  - store a list of datastore names under 'datastore.txt'


Import-Module VMware.PowerCLI

#Check if drives are compatible
#Check if log folder exists

#############################################################
### Settings

## Script settings
# CreateNewPassword - If set to 'YES', a new password will be set and no other functions will be executed.
# RunTest - If set to 'YES', the test function will be run and no other functions will be executed.
# Run Program - If set to 'YES', the main program will run (only can be run if CreateNewPassword and RunTest are set to 'NO'.
# SendEmail - If set to 'YES', the log file will be sent via SMTP relay. This sends an email only after RunProgram is Executed.

$CreateNewPassword = "NO"
$RunTest = "NO"
$RunProgram = "YES"
$SendEmail = "YES"

## Root Folder for Datastores.txt, ESX_cred.txt and logs
$RootFolder = "."

## ESX Host settings
$ESXHost = "linvmp71"
$HostUsername = "root"
$Password_Location = “$RootFolder\ESX_cred.txt”
$DataStore_List = Get-Content "$RootFolder\Datastores.txt"

## Email settings
$smtp = "smtp.x.local"
$to = "jared.stillwell@example.com"
$from = "Service Desk <servicedesk@x.com>"
$cc = "Jared.Stillwell@x.com"

## Log settings
$Log_Location = "$RootFolder\Logs\"
$Log_Name = "UnmapDSLog_" + (get-date -format "dMMyy-HH.mm") + ".log"

#############################################################

# Function to encrypt new password
function NewPassword{
    $securePassword = Read-host -AsSecureString | ConvertFrom-SecureString | Out-File -FilePath $Password_Location
}

# Function to test script. No changes will be made on Host
function StartTest{
    ConnectESXHost
    foreach ($datastore in $DataStore_List){ 
        $esx = Get-VMHost $ESXHost -Datastore $datastore  
        $esxcli = Get-EsxCli -VMHost $ESXHost
        Write-Host -fore Yellow "Reclaiming space on $ESXHost datastore: $datastore"
        write-host -fore gray "TEST (No changes made) - RunProgram will reclaim space on: $datastore"
        Write-Host -fore Green "Space has been reclaimed on Datastore $datastore"
    }
    Write-Host -fore green "Reclaimed space on all VDFS Datastores."
    DisconnectESXHost
}

# Function to run main script. 
function StartProgram{
    ConnectESXHost
    foreach ($datastore in $DataStore_List){
        $esx = Get-VMHost $ESXHost -Datastore $datastore
        $esxcli = Get-EsxCli -VMHost $ESXHost
        Write-Host -fore Yellow "Reclaiming space on $ESXHost datastore: $datastore"
        $esxcli.storage.vmfs.unmap($null, $datastore, $null)
        Write-Host -fore Green "Space has been reclaimed on Datastore $datastore"
    }
    Write-Host -fore green "Reclaimed space on all VDFS Datastores."
    DisconnectESXHost
}

# Function to send log via email
function SendEmail{
    $subject = "VMware VMFS unmap script - $LogDate" 
    $body = "Hi Team,<br><br><br><br>"
    $body += "Attached is the log file from the VMware VMFS unmap script.<br>"
    $body += "<br><br>Regards<br><br>Service Desk<br><br>"
    Send-MailMessage -SmtpServer $smtp -To $to -CC $cc -Attachments $LogPath -From $from -Subject $subject -Body $body -BodyAsHtml -Priority high
}

# Function to connect ESX Host
function ConnectESXHost{
    $HostPassword = Get-Content $Password_Location | ConvertTo-SecureString
    $cred = New-Object System.Management.Automation.PsCredential($HostUsername,$HostPassword)
    Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds -1 -Confirm:$False
    Connect-VIServer $ESXHost -Protocol https -Credential $cred
}

# Function to disconnect ESX Host
function DisconnectESXHost{
    Write-Host "Disconnecting from ESX Host: $ESXHost"
    Disconnect-VIServer $ESXHost -Confirm:$false 
}

# Main Method
$host.ui.RawUI.WindowTitle = "Reclaim space script for ESX VDFS Datastores"
$LogPath = $Log_Location + $Log_Name
$LogDate = get-date -format "dMMyy-HH.mm"
Start-Transcript -Path $LogPath
Get-Date; whoami; Hostname
if($CreateNewPassword -match "YES"){NewPassword; write-host -fore Red "CreateNewPassword Enabled - Change varible to 'NO' to execute program or test."; Stop-Transcript; Sleep 30; exit}
else{write-host -fore Yellow "CreateNewPassword Disabled - Existing password will be used."}
if($RunTest -match "YES"){write-host -fore Red "RunTest Enabled - Change varible to 'NO' to execute program"; StartTest; Stop-Transcript; Sleep 30; exit}
else{write-host -fore Yellow "RunTest Disabled - Environment test will not execute."}
if($RunProgram -match "YES"){write-host -fore Yellow "RunProgram Enabled. Main program will execute."; StartProgram; Stop-Transcript}
else{write-host -fore Red "RunProgram disabled - Main program will not be run."; Stop-Transcript}
if($SendEmail -match "YES"){SendEmail; write-host -fore Yellow "SendEmail Enabled - Email will be sent."}
else{write-host -fore Red "SendEmail disabled - No email will be sent"}