#Script to restore the old recovery wim.
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


    Write-Host "Copying original winre image to to C:\WindowsRE" -ForegroundColor Yellow
    Copy-Item -Path C:\Prestage\WindowsRE -Destination C:\WindowsRecovery -Recurse -Force
    #again could add in furthe validation to check files had copied successfully (perhaps hash check etc, but probably overkill) additionally the folder will apear empty in explorer unless hide os files is unticked.
    #unmount the recovery volume
    Write-Host "Copy complete" -ForegroundColor Green

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
                Write-Host "mounting original winre image" -ForegroundColor Yellow
            $Customwim = (C:\Windows\System32\ReAgentc.exe /setreimage /path C:\WindowsRecovery) -join "`r`n"
            #Enable
            Write-Host "Enabling recovery agent" -ForegroundColor Yellow
            $Enable = (C:\Windows\System32\ReAgentc.exe /enable) -join "`r`n" 
            #Set as next boot
            Get-RecoveryAgent
            $Output 
           # }
        #}


}else{
    #add this to logs in addition.
    Write-Host "Recovery not enabled on this device, moving on" -ForegroundColor Yellow
}

