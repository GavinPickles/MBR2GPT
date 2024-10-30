#Script to convert MBR disks using different tools depending on wheter it's a system disk or non system disk.
#Last Updated: 15/02/2020 - Gavin Pickles
$Stopwatch = [system.diagnostics.stopwatch]::StartNew()


function Get-RecoveryAgent {
#Used to capture prior recovery partition such as;
        # ----Windows RE status:         Enabled
        # ----Windows RE location:       \\?\GLOBALROOT\device\harddisk0\partition4\Recovery\WindowsRE

#We will need to use regex to turn output into an object.
$Command = (C:\Windows\System32\ReAgentc.exe /info) -join "`r`n" 

#regex
$regex = @'
[ \t]+(.*)(:. *)(.*)
'@

#Use regex to grab fields
$Query = [regex]::matches($Command, $Regex) | ForEach-Object {
        [PSCustomObject] @{
         'Feild'       = ($_.Groups[1].Value)
         'Output'      = ($_.Groups[3].Value)
        }
}

 #reformating the object from above for dot sourcing.

$script:Output =  [PSCustomObject] @{
         $Query[0].feild = $Query[0].Output
         $Query[1].feild = $Query[1].Output
         $Query[2].feild = $Query[2].Output
         $Query[3].feild = $Query[3].Output
         $Query[4].feild = $Query[4].Output
         $Query[5].feild = $Query[5].Output
         $Query[6].feild = $Query[6].Output
         }
}

Get-RecoveryAgent

#Now we've run the above function we need to mount the recovery volume and save the exisiting Winre.wim so we can take a backup & change its location later.
#This is due to the fact that we will be using a custom wim in order to make the conversion from MBR2GPT offline.

#Check recovery is even enabled;
write-host "Checking if recovery is enabled on this device." -ForegroundColor Yellow
if ($Output.'Windows RE status' -match 'Enabled'){
    Write-Host "Recovery is enabled" -ForegroundColor Green
    #Get recovery volume - get from our function as may not be always where we think it is so better to find from reagentc
$regex = @'
(\w*)(\d)
'@
    $command = $Output.'Windows RE location'
    $Query = [regex]::matches($command, $Regex) | ForEach-Object {
             [PSCustomObject] @{
             'Feild'       = ($_.Groups[1].Value)
             'Output'      = ($_.Groups[2].Value)
            }
    }

    $recoverydisk =  [PSCustomObject] @{
             $Query[0].feild = $Query[0].Output
             $Query[1].feild = $Query[1].Output
             }


    #Mount Partiton to grab recovery wim - Lets find an available drive letter to use
    $used  = Get-PSDrive | Select-Object -Expand Name |
         Where-Object { $_.Length -eq 1 }
    $drive = 90..65 | ForEach-Object { [string][char]$_ } |
         Where-Object { $used -notcontains $_ } |
         Select-Object -First 1
    #fix string for paths
    [string]$drive = "$drive"+":"

    Write-Host "Mounting recovery partition" -ForegroundColor Yellow
    add-PartitionAccessPath -DiskNumber $recoverydisk.harddisk -PartitionNumber $recoverydisk.partition -AccessPath $drive
    #Further validation here could check path?
    #Get-ChildItem -path Z:\Recovery\* -Recurse -force
    Write-Host "Copying Windows recovery over to C:\prestage" -ForegroundColor Yellow
    Copy-Item -Path $drive\Recovery\* -Destination C:\Prestage -Recurse -Force
    #again could add in furthe validation to check files had copied successfully (perhaps hash check etc, but probably overkill) additionally the folder will apear empty in explorer unless hide os files is unticked.
    #unmount the recovery volume
    Write-Host "Copy complete" -ForegroundColor Green
    remove-PartitionAccessPath -DiskNumber $recoverydisk.harddisk -PartitionNumber $recoverydisk.partition -AccessPath $drive
    Write-Host "unmounted recovery partition" -ForegroundColor Yellow

    #Mount our custom recovery wim.
    #first we need to disable recovery environment in order to mount our custom wim.
    Write-Host "Disabling winre" -ForegroundColor Yellow
    $Disable = (C:\Windows\System32\ReAgentc.exe /disable) -join "`r`n" 
    #check if the above has run, might have to set conditions if this doesnt run async
        #if ($Disable -eq $true) {
        #Run our function for info
        #Get-RecoveryAgent
            #if ($Output.'Windows RE status' -eq "Disabled"){
            #mount our wim.
                Write-Host "mounting custom wim" -ForegroundColor Yellow
            $Customwim = (C:\Windows\System32\ReAgentc.exe /setreimage /path C:\Prestage\CustomBoot) -join "`r`n"
            #Enable
            Write-Host "Enabling recovery agent" -ForegroundColor Yellow
            $Enable = (C:\Windows\System32\ReAgentc.exe /enable) -join "`r`n" 
            #Set as next boot
            Write-Host "Setting custom wim as boot option on reboot" -ForegroundColor Yellow
            $boot = (C:\Windows\System32\ReAgentc.exe /boottore) -join "`r`n" 
            Get-RecoveryAgent
            $Output 
           # }
        #}


}else{
    #add this to logs in addition.
    Write-Host "Recovery not enabled on this device, moving on" -ForegroundColor Yellow
}



#Set system volume name to SYSTEM - so we can ensure winpe can detect correct drive later as drive letters are different depending on number of volumes
Set-Volume -DriveLetter C -NewFileSystemLabel "SYSTEM"

$Disks = Get-Volume | ForEach-Object {
    $VolObj = $_
    $ParObj = Get-Partition | Where-Object { $_.AccessPaths -contains $VolObj.Path }
    if ( $ParObj ) {
        #$VolObj | Select-Object -Property FileSystemLabel, Size, SizeRemaining
        #$ParObj | Select-Object -Property DriveLetter, DiskNumber, PartitionNumber, DiskID
        $Disks = "" | Select FileSystemLabel, Size, SizeRemaining, DriveLetter, DiskNumber, PartitionNumber, DiskID
        $Disks.FileSystemLabel = $volobj.FileSystemLabel
        $Disks.Size = $volobj.Size
        $Disks.SizeRemaining = $volobj.SizeRemaining
        $Disks.DriveLetter = $ParObj.DriveLetter
        $Disks.DiskNumber = $ParObj.DiskNumber
        $Disks.PartitionNumber = $ParObj.PartitionNumber
        $Disks.DiskID = $ParObj.DiskId
        $disks | select *
    }
}

$disks | Export-Csv -NoTypeInformation -Path C:\Prestage\Config\Disks.csv -NoClobber

#get network adapaters & output to file, for after conversion.
$Network = Get-NetIPConfiguration | Select-Object @{N="InterfaceAlias";E={$_.InterfaceAlias}},
    @{N="InterfaceIndex";E={$_.InterfaceIndex}},
    @{N="InterfaceDescription";E={$_.InterfaceDescription}},
    @{N="NetProfile.Name";E={$_.NetProfile.Name}},
    @{N="IPv4Address";E={$_.IPv4Address}},
    @{N="IPv4DefaultGateway";E={$_.IPv4DefaultGateway.NextHop}},
    @{N="DNSServer";E={%{$_.DNSServer.ServerAddresses}}} | ConvertTo-Csv -NoTypeInformation

$Network | Out-File C:\prestage\Config\Network.csv -Encoding utf8 -NoClobber


#Use GPTGEN to convert non system disks while powered on, using the above code to prevent any system disk from being converted this way (As it's not supported & doesnt create the EFI Boot partition)
$MBRdisks = get-disk | Where-Object {($_.PartitionStyle -eq 'MBR') -and $_.IsSystem -eq $false}

#gptgen.exe -w \\.\physicaldriveX - reboot required to take effect

foreach ($MBRDisk in $MBRdisks){

$Disk = $MBRdisk.Number
$a=(C:\Prestage\gptgen.exe -w "\\.\physicaldrive$Disk")
    if ($a[6] -match 'Success!'){
    write-host "Successfully converted disk" $Disk
    Get-Partition | Where-Object disknumber -eq $Disk | select * | Get-Volume | Select-Object DriveLetter, FileSystemLabel, HealthStatus, SizeRemaining, Size | fl
    }else{
    write-host "Failure converting disk" $Disk
    Get-Partition | Where-Object disknumber -eq $Disk | select * | Get-Volume | Select-Object DriveLetter, FileSystemLabel, HealthStatus, SizeRemaining, Size | fl
    }

}