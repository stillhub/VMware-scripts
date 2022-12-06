<#
    This script copies Portgroups between all ESX(i) hosts specified in ESX.txt.
    Also, it copies the Portgroup security settings (Promiscuous, MAC changes, Forged Transmits).

    Author: Jared Stillwell
    Last Edit: 2021-10-13
    Version 2.0

    Notes:
    - See bottom of script for additional features.
    -

#>

<########################################################################>

## Script settings

# Program settings

$host.ui.RawUI.WindowTitle = "VMware Portgroup copier"
$ESX_Array = Get-Content ".\ESX.txt"
$Cred_Location = “.\ESX_cred.txt”
$Log_Location = ".\Logs\Portgroups_$LogDate.log"
$HostUsername = "root"

# Email settings

$smtp = "smtp.x.local"
$to = "x@example.com"
$from = "Service Desk <servicedesk@example.com>"
$cc = "Jared.Stillwell@example.com"

# Log settings

$LogDate = get-date -format "dMMyy-HH.mm"
Start-Transcript -Path $Log_Location
Get-Date ; whoami ; Hostname

<########################################################################>

# Function to encrypt new password
function NewPassword{
    $securePassword = Read-host -AsSecureString | ConvertFrom-SecureString | Out-File -FilePath $Cred_Location
}

# Function to send log via email
function SendEmail{
    $subject = "VMware Hosts portgroup replication - $LogDate" 
    $body = "Hi Team,<br><br><br><br>"
    $body += "Attached is the log file from the VMware portgroup replication script.<br>"
    $body += "<br><br>Regards<br><br>Service Desk<br><br>"
    Send-MailMessage -SmtpServer $smtp -To $to -CC $cc -Attachments $Log_Location -From $from -Subject $subject -Body $body -BodyAsHtml -Priority high
}

# Function to start the program
function StartProgram{
    Clear-Host
    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope Session -Confirm:$false
    $HostPassword = Get-Content $Cred_Location | ConvertTo-SecureString
    $cred = New-Object System.Management.Automation.PsCredential($HostUsername,$HostPassword)
    Connect-VIServer $ESX_Array -Protocol https -Credential $cred

    ## Loops through all hosts defined in ESX.txt
    foreach($ESX_Source in $ESX_Array){
        ## Define destination host by looping hosts specified in ESX.txt
        foreach($ESX_Target in $ESX_Array){

            ## Check if source and destination hosts are the same
            if($ESX_Source -notmatch $ESX_Target){
                # Check if Source host is connected
                if(!($Source_Host = get-vmhost $ESX_Source -erroraction SilentlyContinue)) { write-host -fore Red "Cannot connect to source: " $ESX_Source; exit }
                # Check if Destination host is connected
                if(!($Dest_Host = get-vmhost $ESX_Target -erroraction SilentlyContinue)) { write-host -fore Red "Cannot connect to target: " $ESX_Target; exit }
                
                # Get list of names of virtual switches on source host
                $Source_vSwitchArray = ($Source_Host | get-virtualswitch).Name

                ## Loops through all virtual switches defined in $Source_vSwitchArray
                foreach($vSwitch in $Source_vSwitchArray){
                    $Source_vSwitch = $Source_Host | get-virtualswitch -Name $vSwitch
                    # Create virtual switch on destination host if not found
                    if(!($Dest_Host | get-virtualswitch -Name $vSwitch -erroraction SilentlyContinue)){ 
	                    write-host -fore Yellow "Creating virtual switch $vSwitch on $Dest_Host"
	                    $Dest_vSwitch = New-VirtualSwitch -Server $ESX_Target -Name $vSwitch -Mtu $Source_vSwitch.Mtu | out-null
                    }

                    # Gathers Portgroups from source host and defines target vswitch
                    $Source_PortgroupsArray = $Source_Host | get-virtualswitch -Name $vSwitch | get-virtualportgroup
                    $Dest_vSwitch = Get-VirtualSwitch -VMHost $Dest_Host -Name $vSwitch
                    ## Loops through Portgroups defined in $Source_PortgroupsArray
                    foreach($Source_PortGroup in $Source_PortgroupsArray){
                        # Copies source Portgroup if not found in destination host
                        if (!($Dest_Host | Get-VirtualPortgroup -Name $Source_PortGroup.Name -ErrorAction SilentlyContinue)){
		                    write-host "Creating portgroup $Source_PortGroup.Name on $Dest_Host"
                            # Create new Portgroup in target host with same name and VLanID as source
		                    $CopiedPortGroup = New-VirtualPortgroup -Server $ESX_Target -Name $Source_PortGroup.Name -VirtualSwitch $Dest_vSwitch -VLanId $Source_PortGroup.VLanId
                            
                            ## Replicates security settings from source Portgroup (Promiscuous, MAC changes, Forged Transmits)
                            $Original_SourcePortGroup = $Source_Host | Get-VirtualPortgroup -Name $Source_PortGroup.Name
                            # Check if security settings are configured on source Portgroup
                            if (($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security).count -gt 0) {
                                # Checks and sets Promiscuous security settings
                                if ($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.AllowPromiscuous -ne $null) {
                                    write-host "Added Promiscuous security policy for Portgroup: " $Source_PortGroup.Name
                                    $CopiedPortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.AllowPromiscuous
                                }
                                # Checks and sets MAC change security settings
                                if ($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.MacChanges -ne $null) {
                                    write-host "Added MAC changes security policy for Portgroup: " $Source_PortGroup.Name
                                    $CopiedPortGroup | Get-SecurityPolicy | Set-SecurityPolicy -MacChanges $Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.MacChanges
                                }
                                # Checks and sets Forged Transmits security settings
                                if ($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.ForgedTransmits -ne $null) {
                                    write-host "Added Forged Transmits security policy for Portgroup: " $Source_PortGroup.Name
                                    $CopiedPortGroup | Get-SecurityPolicy | Set-SecurityPolicy -ForgedTransmits $Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.ForgedTransmits
                                }
                            }else{
                                write-host "Source Portgroup had no security policies set: " $Source_PortGroup.Name
                            }
	                    }else{ 
		                    write-host "The portgroup " $Source_PortGroup.Name " already exists." 
	                    }
                    }
                }
            }
        }
    }
    Stop-Transcript
}

# Function to start the program
function StartTest{
    Clear-Host
    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope Session -Confirm:$false
    $HostPassword = Get-Content $Cred_Location | ConvertTo-SecureString
    $cred = New-Object System.Management.Automation.PsCredential($HostUsername,$HostPassword)
    Connect-VIServer $ESX_Array -Protocol https -Credential $cred

    ## Loops through all hosts defined in ESX.txt
    foreach($ESX_Source in $ESX_Array){
        ## Define destination host by looping hosts specified in ESX.txt
        foreach($ESX_Target in $ESX_Array){

            ## Check if source and destination hosts are the same
            if($ESX_Source -notmatch $ESX_Target){
                # Check if Source host is connected
                if(!($Source_Host = get-vmhost $ESX_Source -erroraction SilentlyContinue)) { write-host -fore Red "Cannot connect to source: " $ESX_Source; exit }
                # Check if Destination host is connected
                if(!($Dest_Host = get-vmhost $ESX_Target -erroraction SilentlyContinue)) { write-host -fore Red "Cannot connect to target: " $ESX_Target; exit }
                
                # Get list of names of virtual switches on source host
                $Source_vSwitchArray = ($Source_Host | get-virtualswitch).Name

                ## Loops through all virtual switches defined in $Source_vSwitchArray
                foreach($vSwitch in $Source_vSwitchArray){
                    $Source_vSwitch = $Source_Host | get-virtualswitch -Name $vSwitch
                    # Get virtual switch on destination host if not found
                    if(!($Dest_Host | get-virtualswitch -Name $vSwitch -erroraction SilentlyContinue)){ 
	                    write-host -fore Yellow "Creating virtual switch " $vSwitch 

                        write-host -fore Red "---------------------------------------------"
                        write-host -fore Red "TEST ERROR - This would have created vSwitch: $vSwitch Source: $ESX_Source Destination: $ESX_Target" 
                        write-host -fore Red "---------------------------------------------"

                        # Stop create switch function
##### $Dest_vSwitch = $Dest_Host | New-VirtualSwitch -Name $vSwitch -Mtu $Source_vSwitch.Mtu | out-null
                    }

                    # Gathers Portgroups from source host and defines target vswitch
                    $Source_PortgroupsArray = $Source_Host | get-virtualswitch -Name $vSwitch | get-virtualportgroup

                    $Dest_vSwitch = Get-VirtualSwitch -VMHost $Dest_Host -Name $vSwitch
                    ## Loops through Portgroups defined in $Source_PortgroupsArray
                    foreach($Source_PortGroup in $Source_PortgroupsArray){
                        # Copies source Portgroup if not found in destination host
                        if (!($Dest_Host | Get-VirtualPortgroup -Name $Source_PortGroup.Name -ErrorAction SilentlyContinue)){

		                    write-host "Creating portgroup " $Source_PortGroup.Name
                            # Create new Portgroup in target host with same name and VLanID as source

		                    write-host -fore Red "---------------------------------------------"
                            write-host -fore Red "TEST ERROR - This would have created Portgroup: $Source_PortGroup.Name | vSwitch: $vSwitch | Source: $ESX_Source | Destination: $ESX_Target"
                            write-host -fore Red "---------------------------------------------"

##### $CopiedPortGroup = New-VirtualPortgroup -VMHost $Dest_Host -Name $Source_PortGroup.Name -VirtualSwitch $Dest_vSwitch -VLanId $Source_PortGroup.VLanId
                            
                            ## Replicates security settings from source Portgroup (Promiscuous, MAC changes, Forged Transmits)
                            $Original_SourcePortGroup = $Source_Host | Get-VirtualPortgroup -Name $Source_PortGroup.Name
                            # Check if security settings are configured on source Portgroup
                            if (($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security).count -gt 0) {
                                # Checks and sets Promiscuous security settings
                                if ($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.AllowPromiscuous -ne $null) {
                                    write-host "Added Promiscuous security policy for Portgroup: " $Source_PortGroup.Name

                            write-host -fore Red "---------------------------------------------"
                            write-host -fore Red "TEST ERROR - This would have added Promiscuous settings: $Source_PortGroup.Name | vSwitch: $vSwitch | Source: $ESX_Source | Destination: $ESX_Target"
                            write-host -fore Red "---------------------------------------------"

##### $CopiedPortGroup | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.AllowPromiscuous
                                }
                                # Checks and sets MAC change security settings
                                if ($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.MacChanges -ne $null) {
                                    write-host "Added MAC changes security policy for Portgroup: " $Source_PortGroup.Name

                            write-host -fore Red "---------------------------------------------"
                            write-host -fore Red "TEST ERROR - This would have created MAC changes settings: $Source_PortGroup.Name | vSwitch: $vSwitch | Source: $ESX_Source | Destination: $ESX_Target"
                            write-host -fore Red "---------------------------------------------"


##### $CopiedPortGroup | Get-SecurityPolicy | Set-SecurityPolicy -MacChanges $Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.MacChanges
                                }
                                # Checks and sets Forged Transmits security settings
                                if ($Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.ForgedTransmits -ne $null) {
                                    write-host "Added Forged Transmits security policy for Portgroup: " $Source_PortGroup.Name

                            write-host -fore Red "---------------------------------------------"
                            write-host -fore Red "TEST ERROR - This would have created forged transmits settings: $Source_PortGroup.Name | vSwitch: $vSwitch | Source: $ESX_Source | Destination: $ESX_Target"
                            write-host -fore Red "---------------------------------------------"

##### $CopiedPortGroup | Get-SecurityPolicy | Set-SecurityPolicy -ForgedTransmits $Original_SourcePortGroup.ExtensionData.Spec.Policy.Security.ForgedTransmits
                                }
                            }else{
                                write-host "Source Portgroup had no security policies set: " $Source_PortGroup.Name
                            }
	                    }else{ 
		                    write-host "The portgroup: " $Source_PortGroup.Name " already exists on vSwitch: $vSwitch | Source: $ESX_Source | Destination: $ESX_Target"
	                    }
                    }
                }
            }
        }
    }
    Stop-Transcript
}

<########################################################################
#   -- HOW TO GUIDE
#   -- 
#   -- Add '#' at the start of commands below to disable.
#   - Set new password: Remove '#' from line below [ #NewPassword ]
#   - Disable main task: Add '#' infront of line below [ #StartProgram ]
#   - Disable email: Add '#' infront of line below [ #SendEmail ]
########################################################################>
#NewPassword
StartProgram
#StartTest
SendEmail

