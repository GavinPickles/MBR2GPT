#Requires -RunAsAdministrator
$GreenTick = @{
  Object = [Char]8730 #only square root seems to work as a tick :(
  ForegroundColor = 'Green'
  NoNewLine = $true
  }

$RedCross = @{
  Object = "X"
  ForegroundColor = 'Red'
  NoNewLine = $true
  }



Write-host "Connecting to Vcenters & Setting up PowerCLI environment." -ForegroundColor Yellow
       #Powercli environment Settings
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -ErrorAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
        Set-PowerCLIConfiguration -ParticipateInCeip 0 -Confirm:$false -ErrorAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
        Set-PowerCLIConfiguration -ProxyPolicy NoProxy -Confirm:$false -ErrorAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
        Set-PowerCLIConfiguration -DefaultVIServerMode single -Confirm:$false -ErrorAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null



function credentials{

$script:Cred = Get-Credential -Message "Enter Credentials for this machine"
validatecreds

}
function validatecreds{
#Should probably change this to try catch statment at a later date
Write-host "Checking provided credentials work agaisnt target server" $script:Servername " " -NoNewline
$Job = Invoke-Command -ComputerName $Script:ServerName -ScriptBlock {get-process} -AsJob -JobName ValidateCreds -Credential $Script:cred
Wait-Job $Job -ErrorAction SilentlyContinue | Out-Null 
$JobResult =  $Job | Receive-Job -ErrorAction SilentlyContinue
if ($JobResult -ne $null){
$ResultName = $Jobresult[0].PSComputerName
}
If ($Job.state -eq "Completed" -and $ResultName -eq $script:Servername) {
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "Couldn't connect with provided credentials, please try again" -ForegroundColor Yellow
 credentials
}
}

function connect-vsphere{

        Try
            {
                connect-viserver VCENTERSERVERNAMEHERE -ErrorAction Stop
              
            }
            Catch 
            {
                $ErrorMessage = $_.Exception.Message
                Write-Host @RedCross
                Write-Host " (Failed)"
                write-host $ErrorMessage "Seems your account doesnt have access to VSphere or this server doesnt exist" -ForegroundColor yellow
                Write-Host "Try entering your details again" -ForegroundColor yellow
                connect-vsphere
            }
            
}
function get-vmname{
Write-Host "Please Enter VM Name to migrate" -ForegroundColor cyan
    do{
    try{
    [validatePattern('^(([a-z]|[A-Z]|[0-9]|[!^(){}\-_~])+)?\w$')]$script:Servername = read-host "Enter Name"
    } catch {}
   } until ($script:Servername)
   validate-vmname
   }
Function validate-vmname{

        Try{
        #In PowerCLI you can extend the virtual machine object with a vCenterServer property. Allowing us to display which Vcenter a VM is a member of :)
        #we create this property before calling the cmdlet.
        #New-VIProperty -Name vCenterServer -ObjectType VirtualMachine -Value {$Args[0].Uid.Split(":")[0].Split("@")[1]} | Out-Null 
        $CheckSN = get-vm $script:servername -ErrorAction Stop
        }
        Catch{$ErrorMessage = $_.Exception.Message
        write-host $ErrorMessage -ForegroundColor Red
        write-host "Make sure you have inputted the correct name" -ForegroundColor yellow
        get-vmname
        }
        Write-Host "Validated $Servername Conitnuing " -NoNewline
        Write-Host @GreenTick
        Write-Host " (Success)"
        return
        }
function checkspace{
write-host "checking available disk space on system " -NoNewline
$Job = Invoke-Command -ComputerName $Script:ServerName -ScriptBlock {Get-PSDrive C | Select-Object PSComputerName,Used,Free} -AsJob -JobName CheckFreeSpace -Credential $Script:cred
Wait-Job $Job | Out-Null
$JobResult =  $Job | Receive-Job
$FreeGB = ($Jobresult.free / 1GB)
If ($Job.state -eq "Completed" -and $FreeGB -gt "3") {
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "There isn't enough free space, please enusre 3GB free on system disk" -ForegroundColor Yellow
read-host "Press enter once resolved"
 checkspace
}
}

function CopyFiles{Write-Host "Copying files to $ServerName " -NoNewline

Copy-Item –Path C:\Scripts\Prestage* -Recurse –Destination 'C:\Prestage' –ToSession (New-PSSession -Name CopyFiles –ComputerName $ServerName -Credential $Script:cred)
$SessionToEnd = Get-PSSession | Where-Object name -EQ CopyFiles
Remove-PSSession $SessionToEnd
$Job = Invoke-Command -ComputerName $ServerName -ScriptBlock {Test-Path C:\Prestage} -AsJob -JobName CopyFilesCheck -Credential $Script:cred
Wait-Job $Job | Out-Null

$JobResult =  $Job | Receive-Job

If ($Job.state -eq "Completed" -and $JobResult -eq $true){
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "There was a problem, with your credentials accessing this server" $Cred.UserName -ForegroundColor Yellow
   credentials
   copyfiles

}
}

function RunDiskConversion{
Write-Host "Executing Diskconversion on $ServerName " -NoNewline
#try use session credentials first to prevent credential prompts and less frustrating run.
if (!$Script:cred){
$Job = Invoke-Command -ComputerName $script:ServerName -FilePath C:\Scripts\DiskConversion.ps1 -AsJob -JobName DiskConvert
}else{
$Job = Invoke-Command -ComputerName $ServerName -FilePath C:\Scripts\DiskConversion.ps1 -AsJob -JobName DiskConvert -Credential $Script:cred
}

Wait-Job $Job | Out-Null

#$JobResult =  $Job | Receive-Job

If ($Job.state -eq "Completed"){
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "There was a problem, with your credentials accessing this server" $Cred -ForegroundColor Yellow
   credentials
   RunDiskConversion

}
}

function PowerOnVMwareVM{

Write-Host "Powering on $script:ServerName " -NoNewline
#Start-VM -vm $ServerName | Out-Null

$vm = Get-VM -Name $script:ServerName
        if ($vm.PowerState -ne "PoweredOn") 
            {
            Start-VM -vm $ServerName | Out-Null

                do {
                #Wait 5 seconds
                Start-Sleep -s 5
                #Check the power status again
                $VM = Get-VM -Name $Script:ServerName
                $status = $VM.PowerState
                }until($status -eq "PoweredOn")
            }
$status = $VM.PowerState
If ($status -eq "PoweredOn"){
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "poweron manually to conintue" $Cred.UserName -ForegroundColor Yellow
Read-Host "Press enter to conitnue once powered on"
return

}
}
function WaitSystemDisk{
Write-Host "Converting System Disk on $script:ServerName " -NoNewline

$vm = Get-VM -Name $script:ServerName
        if ($vm.PowerState -ne "PoweredOff") 
            {

                do {
                #Wait 5 seconds
                Start-Sleep -s 5
                #Check the power status again
                $VM = Get-VM -Name $Script:ServerName
                $status = $VM.PowerState
                }until($status -eq "PoweredOff")
            }

If ($status -eq "PoweredOff"){
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "poweroff manually to conintue" $Cred.UserName -ForegroundColor Yellow
Read-Host "Press enter to conitnue once powered off"
return
#we need to roll back - critical error.

}
}
function InvokeShutdown{
Write-Host "Shutting Down $script:ServerName " -NoNewline
if (!$Script:cred){
$job = Invoke-Command -ComputerName $ServerName -ScriptBlock {shutdown -s -t 5} -AsJob -JobName Shutdown
}else{
$Job = Invoke-Command -ComputerName $ServerName -ScriptBlock {shutdown -s -t 5} -AsJob -JobName ShutDown -Credential $cred
}

$vm = Get-VM -Name $script:ServerName
        if ($vm.PowerState -ne "PoweredOff") 
            {

                do {
                #Wait 5 seconds
                Start-Sleep -s 5
                #Check the power status again
                $VM = Get-VM -Name $Script:ServerName
                $status = $VM.PowerState
                }until($status -eq "PoweredOff")
            }
$status = $VM.PowerState
If ($status -eq "PoweredOff"){
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "poweron manually to conintue" $Cred.UserName -ForegroundColor Yellow
Read-Host "Press enter to conitnue once powered on"
return

}
}
function changebios {
Try{
Write-Host "Changing from legacy bios to UEFI" -NoNewline
$vm = Get-VM $script:Servername
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi
$vm.ExtensionData.ReconfigVM($spec)
Write-Host @GreenTick
Write-Host " (Success)"
return
}
catch{
#need to sort error handling here.
}
}
function RestoreDriveLetters{
#call function to test connection first
TestWinRM
Write-Host "Restoring Drive Letters on $ServerName " -NoNewline
#try use session credentials first to prevent credential prompts and less frustrating run.
if (!$Script:cred){
$Job = Invoke-Command -ComputerName $script:ServerName -FilePath C:\Scripts\RestoreDriveLetters.ps1 -AsJob -JobName RestoreDriveLetters
}else{
$Job = Invoke-Command -ComputerName $ServerName -FilePath C:\Scripts\RestoreDriveLetters.ps1 -AsJob -JobName RestoreDriveLetters -Credential $Script:cred
}

Wait-Job $Job | Out-Null

#$JobResult =  $Job | Receive-Job

If ($Job.state -eq "Completed"){
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "There was a problem, with your credentials accessing this server" $Cred -ForegroundColor Yellow
   credentials
   RestoreDriveLetters

}
}
function TestWinRM {
#testnetconnection is a function not a commandlet so information level and information actions dont work, heres the workaround, not sure if test-connection works on all PS versions yet.
#so implementing this work around for now.
$OriginalProgressPreference = $Global:ProgressPreference
$Global:ProgressPreference = 'SilentlyContinue'
#need to add a timeout function to this function in order to initiate psexec resolution for enabling winrm
$Connection = Test-NetConnection $script:ServerName -port 5985 -InformationLevel Quiet -InformationAction Ignore 
if ($Connection -ne $True) 
            {
            Write-Host "Waiting for connection to re-establish on" $script:ServerName -ForegroundColor Yellow

                do {
                #Wait 5 seconds
                Start-Sleep -s 5
                #Check the power status again
                $Connection = Test-NetConnection $ServerName -port 5985 -InformationLevel Quiet -InformationAction Ignore
                $Connectionstatus = $Connection
                }until($Connectionstatus -eq $true)
            }
$Global:ProgressPreference = $OriginalProgressPreference
}

function restorewinre{
write-host "restoring windows recovery image to original" -NoNewline
$Job = Invoke-Command -ComputerName $ServerName -FilePath C:\Scripts\RestoreRecovery.ps1 -AsJob -JobName RestoreWinre -Credential $Script:cred

Wait-Job $Job | Out-Null

#$JobResult =  $Job | Receive-Job

If ($Job.state -eq "Completed"){
Write-Host @GreenTick
Write-Host " (Success)"
return
}else{
Write-Host @RedCross
Write-Host " (Failed)"
write-host "There was an unhandled error, please raise on TFS" -ForegroundColor Yellow
write-host "Restore to snapshot, while this is investigated" -ForegroundColor Yellow
Read-Host "press enter key to exit program"
exit
}
}
function checkpowerstate{
#check if vm is powered on or not
#TO do instead of calling poweron at begining :P
}
function snapvm{
write-host "Taking a snapshot of " $script:Servername " " -NoNewline
Try{New-Snapshot -VM $script:Servername -Name BeforeInvokeScript | Out-Null #non quiesced, need to create a function, to do quiesced ones then if failed do none.
Write-Host @GreenTick
Write-Host " (Success)"
}
catch {Write-Host @RedCross
Write-Host " (Failed)"
Write-Host "Unhandled Exception - record on TFS" -ForegroundColor Yellow
exit
}

}

$banner = @'
███╗   ███╗██████╗ ██████╗ ██████╗  ██████╗ ██████╗ ████████╗
████╗ ████║██╔══██╗██╔══██╗╚════██╗██╔════╝ ██╔══██╗╚══██╔══╝
██╔████╔██║██████╔╝██████╔╝ █████╔╝██║  ███╗██████╔╝   ██║   
██║╚██╔╝██║██╔══██╗██╔══██╗██╔═══╝ ██║   ██║██╔═══╝    ██║   
██║ ╚═╝ ██║██████╔╝██║  ██║███████╗╚██████╔╝██║        ██║   
╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝        ╚═╝   
                                                                              
Last Updated 15/10/2024
Author: Gavin Pickles
'@

Write-Host $banner


connect-vsphere
get-vmname
#need to check server is powered on before copying files & testing creds
PowerOnVMwareVM
#need a check for winRM enabled
TestWinRM
#if check fails we need to inititate configuration to enable winRM via psexec
credentials
#Check server has enough space on C:\ to run operations before taking a snap.
checkspace
#snap server.
snapvm
#copy files
copyfiles
#run script
RunDiskConversion
InvokeShutdown
#poweron server for system disk to be converted.
PowerOnVMwareVM
WaitSystemDisk
#change VM to EFI Bios
ChangeBios
#powerbackon
PowerOnVMwareVM
#Change drives here
RestoreDriveLetters
#change recovery back to the old version.
restorewinre

Read-Host "Press enter to exit"