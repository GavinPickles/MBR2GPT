Function FixDisk {
$script:CatchInitiated = $false
$CurrentDrives = Get-Volume | ForEach-Object {
    $VolObj = $_
    $ParObj = Get-Partition | Where-Object { $_.AccessPaths -contains $VolObj.Path }
    if ( $ParObj ) {
        #$VolObj | Select-Object -Property FileSystemLabel, Size, SizeRemaining
        #$ParObj | Select-Object -Property DriveLetter, DiskNumber, PartitionNumber, DiskID
        $CurrentDrives = "" | Select FileSystemLabel, Size, SizeRemaining, DriveLetter, DiskNumber, PartitionNumber, DiskID
        $CurrentDrives.FileSystemLabel = $volobj.FileSystemLabel
        $CurrentDrives.Size = $volobj.Size
        $CurrentDrives.SizeRemaining = $volobj.SizeRemaining
        $CurrentDrives.DriveLetter = $ParObj.DriveLetter
        $CurrentDrives.DiskNumber = $ParObj.DiskNumber
        $CurrentDrives.PartitionNumber = $ParObj.PartitionNumber
        $CurrentDrives.DiskID = $ParObj.DiskId
        $CurrentDrives | select *
    }
}

$DesiredDriveMappings = Import-Csv C:\Prestage\Disks.csv
 
$compare = Compare-Object $DesiredDriveMappings $CurrentDrives -Property driveletter, disknumber, partitionnumber

foreach ($entry in $compare | Where-Object sideindicator -eq "<="){
#this needs to run elevated or it will fail
#also need to check desired drive letter is available.
try{
Get-Partition -DiskNumber $entry.diskNumber -PartitionNumber $entry.partitionNumber | Set-Partition -NewDriveLetter $entry.driveletter -ErrorAction Stop #needed to specify error action or catch wouldn't trigger
}
catch{$ErrorMessage = $_.Exception.Message
    #Lets find an available drive letter to use that isn't a desired one or one in use
    $used  = Get-PSDrive | Select-Object -Expand Name |  Where-Object { $_.Length -eq 1 }
    $drive = 90..65 | ForEach-Object { [string][char]$_ } | Where-Object { $used -notcontains $_ -and $DesiredDriveMappings.driveletter } | Select-Object -First 1
    Get-Partition -DiskNumber $entry.diskNumber -PartitionNumber $entry.partitionNumber | Set-Partition -NewDriveLetter $drive
    $script:CatchInitiated = $true
    continue
}
}
}

function catchcheck{
if ($script:CatchInitiated -eq $true)
{
    FixDisk
}
}

fixdisk
CatchCheck