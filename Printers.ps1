# Try to run as admin

param([switch]$Elevated)
function Test-Admin {
  $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
  $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if ((Test-Admin) -eq $false)  {
    if ($elevated) 
    {
        # tried to elevate, did not work, aborting
    } 
    else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
}
exit
}
'running with full privileges'


# Function to get list of servers
Function Get-Servers {
    # This version pulls all DCs
    # Then prompts the user to select one ore more
    $getdomain = [System.Directoryservices.Activedirectory.Domain]::GetCurrentDomain()
    $SelectedServers = $getdomain | ForEach-Object {$_.DomainControllers} | 
    ForEach-Object {
      $hEntry= [System.Net.Dns]::GetHostByName($_.Name)
      New-Object -TypeName PSObject -Property @{
          Name = $_.Name
          IPAddress = $hEntry.AddressList[0].IPAddressToString
         }
    }  | Out-GridView -PassThru -Title "Select server to view shared printers"
    Return $SelectedServers
}

# Function to get list of printers when provided with $Servers
Function Get-Printers {
# This function retreives all shared printers from
# Each server provided in $Servers
# Then prompts the user to select a subset of printers
# That subset of printers is then returned
param($Servers)
    $allprinters = @() 
        foreach( $server in $Servers.name ){ 
        Write-Host "checking $server ..." 
        $printer = $null 
        $printers = $null 
        $printers = Get-WmiObject -class Win32_Printer -computername $server 
        $printer = $printers | where-object {$_.shared} 
        $allprinters += $printer 
    }
    $SelectedPrinters = $allprinters | Out-GridView -PassThru -Title "Select printers to install"
    return $SelectedPrinters
}

# Function to add printers
function Add-Printers {
    param($PrintersToAdd)
    foreach ( $Printer in $PrintersToAdd ) {
        $PrinterShare = """\\$($printer.systemname)\$($printer.ShareName)"""
        write-host "Adding $printerShare"
        cmd /c "rundll32 printui.dll,PrintUIEntry /q /ga /n$printershare"
    }

}

# Function called when user selects option to add new printers
Function Add-NewPrinters {
    # Get servers 
    $Servers = Get-Servers
    
    # Get printers from selected servers
    $PrintersToAdd = Get-Printers -Servers $Servers

    # Install Selected Printers
    if ($PrintersToAdd.count -ge 1){ 
        add-printers -PrintersToAdd $PrintersToAdd

        write-host "Restarting Spooler service..."
        restart-service spooler
        read-host -Prompt "Press any key to continue"
    } 
    else {
        write-host "No printers to add..."
        read-host -Prompt "Press any key to continue"
    }
}

# Function called when user selects option to remove printers
Function Remove-CurrentPrinters {
    # Get current network installed printers
    $InstalledNetPrinters = get-printer | Where-Object {$_.type -eq "Connection"}

    $PrintersToRemove = $InstalledNetPrinters | Out-GridView -PassThru -Title "Select printers to remove"

    foreach ($PrinterToRemove in $PrintersToRemove.name) {
        Write-Host "Removing $PrinterToRemove"
        cmd /c "rundll32 printui.dll,PrintUIEntry /q /gd /n""$PrinterToRemove"""
        remove-printer $PrinterToRemove -ErrorAction SilentlyContinue
    }
    write-host "Restarting Spooler service..."
    restart-service spooler -PassThru
}


# Promt to see if we're adding or removing printers
$Title = "Add or Remove Printers"
$Info = "Do you want to add new printers or remove existing?"
 
$options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Add", "&Remove", "&Quit")
[int]$defaultchoice = 2
$opt = $host.UI.PromptForChoice($Title , $Info , $Options,$defaultchoice)
switch($opt)
{
    0 { Add-NewPrinters}
    1 { Remove-CurrentPrinters}
    2 { Write-Host "Good Bye!!!" -ForegroundColor Green}
}