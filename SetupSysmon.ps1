# Declare variables
$SysmonDownloadDir = "C:\Sysmon"
$SysmonConfigFile = "sysmon.xml"
$SysmonZipFile = "sysmon.zip"

$SysmonConfigFilePath = "$SysmonDownloadDir\$SysmonConfigFile"
$SysmonZipFilePath = "$SysmonDownloadDir\$SysmonZipFile"

$XMLDownloadPath = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"
$ZipDownloadPath = "https://download.sysinternals.com/files/Sysmon.zip"

$CheckForUpdatedVersion = $True
$InstallNewVersion = $True

# Reset variables
$InstallSysmonAsaService = $False
$ReconfigureSysmon = $False

Function Get-ProcessBit {
    Begin {} 
    Process { 
        If ($([Environment]::Is64BitProcess)) {
            Return "64-bit"
        } else {
            Return "32-bit"
        }
    }
    End {}
}

$ProcessBit = Get-ProcessBit

Write-Output "Create Sysmon folder if missing"
If (-Not (Test-Path ($SysmonDownloadDir))) { 
    New-Item -Path $SysmonDownloadDir -ItemType Directory 
    Write-Output "- Folder created"
} Else {
    Write-Output "- Folder exists"
}

Write-Output "Check if Sysmon is running as a service"
If ((Get-Service Sysmon -ErrorAction SilentlyContinue) -or (Get-Service Sysmon64 -ErrorAction SilentlyContinue)) {
    If (Get-Service Sysmon -ErrorAction SilentlyContinue) {
        Write-Output "- 32-Bit Service found"
        $SysmonServiceDetails = Get-WmiObject win32_service | ?{$_.Name -eq 'Sysmon'} | select Name, DisplayName, State, PathName
    } Else {
        Write-Output "- 64-Bit Service found"
        $SysmonServiceDetails = Get-WmiObject win32_service | ?{$_.Name -eq 'Sysmon64'} | select Name, DisplayName, State, PathName
    }
} Else {
    Write-Output "- Service not found, will install it"
    $InstallSysmonAsaService = $True
}

Write-Output "Download Sysmon executable if it doesn't exist"
If (-Not (Test-Path ("$SysmonDownloadDir\Sysmon.exe"))) {
    Write-Output "- Sysmon not detected, will download and install"
    Invoke-WebRequest -Uri "$ZipDownloadPath" -OutFile "$SysmonZipFilePath"
    If (Test-Path ("$SysmonZipFilePath")) {
        Get-Item "$SysmonZipFilePath" | Unblock-File
        Expand-Archive "$SysmonZipFilePath" -DestinationPath $SysmonDownloadDir
        #Remove-Item "$SysmonDir\Sysmon.zip" -Force
        $InstallSysmonAsaService = $True
    } Else {
        Write-Output "- Something went wrong, quitting"
        Break
    }
} Else {
    Write-Output "- Sysmon already exist"

}

# Declare webClient
$wc = [System.Net.WebClient]::new()

Write-Output "Get Hash from online sysmon config"
$GithubFileHash = Get-FileHash -InputStream ($wc.OpenRead($XMLDownloadPath))

If (Test-Path -Path "$SysmonConfigFilePath") {
    Write-Output "Get Hash from local sysmon config"
    $ConfigFileHash = Get-FileHash -Path "$SysmonConfigFilePath"

    Write-Output "Compare Hashes and download if needed"
    If ($GithubFileHash.Hash -ne $ConfigFileHash.Hash) {
        Write-Output "- Installing a newer Config"
        Invoke-WebRequest -Uri $XMLDownloadPath  -OutFile "$SysmonConfigFilePath"
        $ReconfigureSysmon = $True
    } Else {
        Write-Output "- Hash was the same"
    }

} Else {
    Write-Output "No local sysmon config exists, downloading"
    Invoke-WebRequest -Uri $XMLDownloadPath  -OutFile "$SysmonConfigFilePath"
    $ReconfigureSysmon = $True
}

If ($InstallSysmonAsaService) {
    Write-Output "Installing Sysmon as a service"
    If ($ProcessBit -eq "64-Bit") {
        Write-Output "- Using 64-Bit version"
        & "$SysmonDownloadDir\Sysmon64.exe" -accepteula -i "$SysmonConfigFilePath"
    } Else {
        Write-Output "- Using 32-Bit version"
        & "$SysmonDownloadDir\Sysmon.exe" -accepteula -i "$SysmonConfigFilePath"
    }
} ElseIf ($ReconfigureSysmon) {
    Write-Output "Reconfigure Sysmon service to use the latest Config file"
    & $SysmonServiceDetails.PathName -c "$SysmonConfigFilePath"
    #Restart-Service Sysmon
} Else {
    Write-Output "Nothing updated"
}

If ($CheckForUpdatedVersion -and $InstallSysmonAsaService -eq $False) {
    Write-Output "Checking for updated version"
    Invoke-WebRequest -Uri "$ZipDownloadPath" -OutFile "$SysmonZipFilePath"
    If (Test-Path ("$SysmonZipFilePath")) {
        Get-Item "$SysmonZipFilePath" | Unblock-File
        Expand-Archive "$SysmonZipFilePath" -DestinationPath $SysmonDownloadDir -Force
    }

    $ServiceExeFileHash = Get-FileHash -Path "$($SysmonServiceDetails.PathName)"
    $DownloadedExeFileHash = Get-FileHash -Path "$SysmonDownloadDir\$($SysmonServiceDetails.Name).exe"
    If ($ServiceExeFileHash.Hash -ne $DownloadedExeFileHash.Hash) {
        Write-Output "- New version available"
        If ($InstallNewVersion) {
            Write-Output "-- Installing new version"
            & $SysmonServiceDetails.PathName -u
            Start-Sleep -Seconds 5
            & "$SysmonDownloadDir\$($SysmonServiceDetails.Name).exe" -accepteula -i "$SysmonConfigFilePath"
        } Else {
            Write-Output "-- Skip updating"
        }
    } Else {
        Write-Output "- Latest version installed"
    }
}

Write-Output "Script completed"
