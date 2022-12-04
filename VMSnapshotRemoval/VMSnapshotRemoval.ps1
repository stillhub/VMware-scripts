# Script to create a report vCenter Snapshots that have not been removed in the last 24 hours. Removes snapshot more than 41 hours old.
# Script created by Jared Stillwell
# Version: 1.0
#
# Notes:
#  - To encrypt a new password, remove the "#" from the '#EncryptPassword' at the bottom of the script.
#  - The script does not require any input, so it can setup in task scheduler to run on a schedule.
#  - The default script does not enable snapshot removal, remove "#" from '#DeleteSnapshots' to enable function.
#


Import-Module VMware.PowerCLI

#vCenter host details
$login_host = @("vcenterhost.x.local")
$login_user = "username@x.local"

#SMTP email server for report
$smtpServer = "smtp.x.local"
$smtpFrom = "scripts@x.com"
$smtpTo = @("jared.stillwell@example.com")

#Variables
$m = Get-Date -UFormat %m
$y = (get-date).year
$d = (get-date).day
$date = "$y$m$d"

function EncryptPassword{
    $securePassword = Read-host -AsSecureString | ConvertFrom-SecureString
    $securePassword | Out-File -FilePath “.\Passwords\password.txt”
}

function LoginVMWare{
    # Connect to host

    $login_pwd = Get-Content “.\Passwords\password.txt” | ConvertTo-SecureString
    $cred = New-Object System.Management.Automation.PsCredential($login_user,$login_pwd)

    Write-Verbose -Message 'Ignoring self-signed SSL certificates for vCenter Server (optional)'
    $null = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -DisplayDeprecationWarnings:$false -Scope User -Confirm:$false

    ###Check if we are connected to vCenter Server(s)
    if($global:DefaultVIServers.Count -lt 1){
	    echo "Connecting to Hosts"

	    #To connect using PowerCLI credential store
	    Connect-viserver -server $login_host -Protocol https -Credential $cred
    }
    else{
	    echo "Already connected"
    }
}

function CreateReport{
    ### Gather details for report
    $getSnap = Get-VM | Get-Snapshot | Where {$_.Created -lt (Get-Date).AddHours(-24) }
    $getSnap | Select-Object VM, Name, Created,@{Label=”Size”;Expression={“{0:N2} GB” -f ($_.SizeGB)}} | Export-Csv ".\Reports\$date - $login_host Snapshots Purge Report.csv" -NoTypeInformation
}

function DeleteSnapshots{
    ### Purge Snapshots
    $getSnap = Get-VM | Get-Snapshot | Where {$_.Created -lt (Get-Date).AddHours(-41) }
    $getSnap | Select-Object VM, Name, Created,@{Label=”Size”;Expression={“{0:N2} GB” -f ($_.SizeGB)}} | Export-Csv ".\Reports\$date - $login_host Snapshots Purge Report.csv" -NoTypeInformation
    $getSnap | Remove-Snapshot -Confirm:$false
}

function DisconnectVMWare{
    ### Disconnect from host
    Disconnect-VIServer -Server $login_host -confirm:$false
}

function SendEmail{
    ### Email report
    $css = @"
    <style>
    h1, h5, th { text-align: center; font-family: Segoe UI; }
    table { margin: auto; font-family: Segoe UI; box-shadow: 10px 10px 5px #888; border: thin ridge grey; }
    th { background: #2656b5; color: #fff; max-width: 400px; padding: 5px 10px; }
    td { font-size: 11px; padding: 5px 20px; color: #000; }
    tr { background: #b8d1f3; }
    tr:nth-child(even) { background: #dae5f4; }
    tr:nth-child(odd) { background: #b8d1f3; }
    </style>
"@
    Import-CSV ".\Reports\$date - $login_host Snapshots Purge Report.csv" -Delimiter ',' | ConvertTo-Html  -Head $css -Body "<h1>$login_host Snapshots older than 24 hours</h1>`n<h5>Generated on $(Get-Date)</h5>" | Out-File ".\Reports\$date - $login_host Snapshots Purge Report.html"
    $messageSubject = "$date - $login_host Snapshots Purge Task"
    $messagebody = Get-Content ".\Reports\$date - $login_host Snapshots Purge Report.html" -Raw
    Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -subject $messageSubject -Body $messagebody -BodyAsHtml
}

# Remove hash from commands below to run certain functions.

#EncryptPassword
LoginVMWare
CreateReport
#DeleteSnapshots
DisconnectVMWare
SendEmail