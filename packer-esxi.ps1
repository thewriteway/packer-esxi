# exit on any error
$ErrorActionPreference = "Stop"

# configuration
$env:PACKER_CACHE_DIR = ""
$env:PACKER_NO_COLOR = "true"

# calculate variables
$scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
$scriptName = [System.IO.Path]::GetFileName($scriptPath)
$scriptFolder = [System.IO.Path]::GetDirectoryName($scriptPath)
$workFolder = "C:\\tmp\\packer"
$tmpFolder = "$workFolder\\$(Get-Date -Format 'yyyyMMddHHmmss')"
$packerFile = "$tmpFolder\\packer.json"
$preseedFile = "$tmpFolder\\preseed.cfg"
$bootstrapFile = "$tmpFolder\\bootstrap.sh"

# --------------------------------------------------------
# Function for creating log entries on the console
# --------------------------------------------------------
# $1 - Log level
# $2 - Log text
# --------------------------------------------------------
function log {
    param (
        [string]$level,
        [string]$text
    )
    $now = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    Write-Host "$now [$level] $text`n"
}

# ---------------------------------------------------------------
# Function for printing the usage of this script
# ---------------------------------------------------------------
function usage {
    Write-Host @"
Usage:
  $($scriptName) [Options] <Args>

Options:
  --esxi-server         <server>        The ESXi server
  --esxi-username       <username>      The ESXi username
  --esxi-password       <password>      The ESXi password
  --esxi-datastore      <datastore>     The ESXi datastore
  --vm-name             <name>          The VM name
  --vm-cores            <cores>         The number of virtual CPU Cores of the VM
  --vm-ram-size         <ram>           The RAM size of the VM (in MB)
  --vm-disk-size        <disk>          The Disk size of the VM (in GB)
  --vm-network          <network>       The Network name of the VM
  --os-type             <os>            The type of the OS
  --os-proxy            <proxy>         The proxy of the OS
  --os-username         <username>      The username of the OS
  --os-password         <password>      The password of the OS
  --os-domain           <domain>        The network domain of the OS
  --os-keyboard-layout  <layout>        The keyboard layout of the OS
  --os-locale           <locale>        The locale of the OS
  --os-timezone         <timezone>      The timezone of the OS
  --os-docker           <boolean>       Install docker engine in the OS
  --help                                Print this help text

Example:
  $($scriptName) --esxi-server esxi.my.domain `
     --esxi-username root `
     --esxi-password my-password `
     --esxi-datastore my-datastore `
     --vm-name my-vm `
     --vm-cores 1 `
     --vm-ram-size  512 `
     --vm-disk-size 10 `
     --vm-network "VM Network" `
     --os-type ubuntu-trusty `
     --os-proxy none | http://10.10.10.1:3128/ `
     --os-username my-username `
     --os-password my-password `
     --os-domain my.domain `
     --os-locale de_DE.UTF-8 `
     --os-keyboard-layout de `
     --os-timezone Europe/Berlin `
     --os-docker true
"@
    exit 1
}

# print application title
Write-Host "`n--------------------------"
Write-Host "Packer ESXi VM Provisioner"
Write-Host "--------------------------`n"

# get command line arguments
$argsList = @{}
$argument = ""
for ($i = 0; $i -lt $args.Length; $i++) {
    if ($args[$i] -like '--*') {
        $argument = $args[$i]
    } else {
        $argsList[$argument] = $args[$i]
    }
}

# read arguments from user input if not specified
log "INFO" "Reading arguments from user input if not specified"
if (-not $argsList["--esxi-server"]) { $argsList["--esxi-server"] = Read-Host "ESXi Server" }
if (-not $argsList["--esxi-username"]) { $argsList["--esxi-username"] = Read-Host "ESXi Username" }
if (-not $argsList["--esxi-password"]) { $argsList["--esxi-password"] = Read-Host -AsSecureString "ESXi Password" }
if (-not $argsList["--esxi-datastore"]) { $argsList["--esxi-datastore"] = Read-Host "ESXi Datastore" }
if (-not $argsList["--vm-name"]) { $argsList["--vm-name"] = Read-Host "VM Name" }
if (-not $argsList["--vm-cores"]) { $argsList["--vm-cores"] = Read-Host "VM CPU Cores" }
if (-not $argsList["--vm-ram-size"]) { $argsList["--vm-ram-size"] = Read-Host "VM RAM Size (in MB)" }
if (-not $argsList["--vm-disk-size"]) { $argsList["--vm-disk-size"] = Read-Host "VM Disk Size (in GB)" }
if (-not $argsList["--vm-network"]) { $argsList["--vm-network"] = Read-Host "VM Network" }
if (-not $argsList["--os-type"]) { $argsList["--os-type"] = Read-Host "OS Type" }
if (-not $argsList["--os-proxy"]) { $argsList["--os-proxy"] = Read-Host "OS Proxy" }
if (-not $argsList["--os-username"]) { $argsList["--os-username"] = Read-Host "OS Username" }
if (-not $argsList["--os-password"]) { $argsList["--os-password"] = Read-Host -AsSecureString "OS Password" }
if (-not $argsList["--os-domain"]) { $argsList["--os-domain"] = Read-Host "OS Domain" }
if (-not $argsList["--os-keyboard-layout"]) { $argsList["--os-keyboard-layout"] = Read-Host "OS Keyboard Layout" }
if (-not $argsList["--os-locale"]) { $argsList["--os-locale"] = Read-Host "OS Locale" }
if (-not $argsList["--os-timezone"]) { $argsList["--os-timezone"] = Read-Host "OS Timezone" }
if (-not $argsList["--os-docker"]) { $argsList["--os-docker"] = Read-Host "OS Docker" }

# reset proxy server variable if not a valid address
if ($argsList["--os-proxy"] -notmatch '^http') {
    $argsList["--os-proxy"] = ""
}

# calculate vm disk size in MB
log "INFO" "Calculating VM disk size from Gigabytes to Megabytes"
$vmDiskSizeMB = [int]$argsList["--vm-disk-size"] * 1000

# create temp folder
log "INFO" "Creating temp folder '$tmpFolder'"
New-Item -ItemType Directory -Force -Path $tmpFolder

# copy template files to temp folder
$templateFolder = "$scriptFolder\templates\$($argsList["--os-type"])"
log "INFO" "Copying files from template folder '$templateFolder' to temp folder '$tmpFolder'"
Copy-Item -Path "$templateFolder\*" -Destination $tmpFolder -Force

# replace variables in template files
log "INFO" "Replacing variables in template files"
@( $packerFile, $preseedFile, $bootstrapFile ) | ForEach-Object {
    (Get-Content -Path $_) | ForEach-Object {
        $_ -replace '\${esxiServer}', $argsList["--esxi-server"] `
           -replace '\${esxiUsername}', $argsList["--esxi-username"] `
           -replace '\${esxiPassword}', $argsList["--esxi-password"] `
           -replace '\${esxiDatastore}', $argsList["--esxi-datastore"] `
           -replace '\${vmName}', $argsList["--vm-name"] `
           -replace '\${vmCores}', $argsList["--vm-cores"] `
           -replace '\${vmRamSize}', $argsList["--vm-ram-size"] `
           -replace '\${vmDiskSize}', $vmDiskSizeMB `
           -replace '\${vmNetwork}', $argsList["--vm-network"] `
           -replace '\${osType}', $argsList["--os-type"] `
           -replace '\${osProxy}', $argsList["--os-proxy"] `
           -replace '\${osUsername}', $argsList["--os-username"] `
           -replace '\${osPassword}', $argsList["--os-password"] `
           -replace '\${osDomain}', $argsList["--os-domain"] `
           -replace '\${osKeyboardLayout}', $argsList["--os-keyboard-layout"] `
           -replace '\${osLocale}', $argsList["--os-locale"] `
           -replace '\${osTimezone}', $argsList["--os-timezone"] `
           -replace '\${osDocker}', $argsList["--os-docker"] `
           -replace '\${tmpFolder}', $tmpFolder
    } | Set-Content -Path $_
}

# create esxi vm with packer
log "INFO" "Creating VM with packer from file '$packerFile'"
.\packer.exe build $packerFile

# cleanup work folder
log "INFO" "Cleaning up work folder '$workFolder'"
if (Test-Path $workFolder) {
    Remove-Item -Recurse -Force -Path $workFolder
}

# get esxi vm id
log "INFO" "Getting VM ID from VM with name '$($argsList["--vm-name"])'"
$vmId = sshpass -p $argsList["--esxi-password"] ssh -o StrictHostKeyChecking=no $argsList["--esxi-username"]@$argsList["--esxi-server"] vim-cmd vmsvc/getallvms | Select-String -Pattern $argsList["--vm-name"] | ForEach-Object { $_.ToString().Split(' ')[0] }

# power on esxi vm
log "INFO" "Powering on VM with ID '$vmId'"
sshpass -p $argsList["--esxi-password"] ssh -o StrictHostKeyChecking=no $argsList["--esxi-username"]@$argsList["--esxi-server"] vim-cmd vmsvc/power.on $vmId
