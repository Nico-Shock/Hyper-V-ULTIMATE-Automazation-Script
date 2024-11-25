$isoLetter = "E"
$vhdxFileName = "Windows11.vhdx"
$vhdxFilePath = "D:\ALLE programme jetzt hier\Hyper-V"
$vhdxSizeGB = 128
$efiSizeMB = 512
$efiletter = "U"
$windowsletter = "I"
$index = 5
$diskNumber = 2
$cpuCores = 2
$ramSize = 4GB
$networkSwitch = "Default Switch"
$vmName = "Windows11"

Function Show-Output {
    Param([string]$message)
    Write-Host "$message"
}

Function Show-Menu {
    Clear
    Show-Output "Please choose an option:"
    Show-Output "1: Check Disk"
    Show-Output "2: Show Windows Version (Index)"
    Show-Output "3: Create VHDX"
    Show-Output "4: Apply Windows Image"
    Show-Output "5: Unmount Everything"
    Show-Output "6: Create Hyper-V VM"
    Show-Output "7: Delete VHDX"
    Show-Output "8: Exit"
    $choice = Read-Host "Enter your choice (1-8)"
    Switch ($choice) {
        1 { Check-Disk }
        2 { Show-WindowsVersion }
        3 { Create-VHDX }
        4 { Apply-WindowsImage }
        5 { Unmount-Everything }
        6 { Create-HyperVVM }
        7 { Delete-VHDX }
        8 { Exit }
    }
}

Function Check-Disk {
    Try {
        $disks = Get-Disk | Where-Object { $_.OperationalStatus -eq "OK" }
        If ($disks.Count -eq 0) {
            Show-Output "No disks found or disks are not operational."
        } else {
            $disks | ForEach-Object { Show-Output "Disk $($_.Number): $($_.Model) - $($_.Size / 1GB) GB" }
            Show-Output "Check disk numbers carefully before selecting a target disk!"
        }
    }
    Catch {
        Show-Output "Error displaying disks: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Show-WindowsVersion {
    Try {
        $installFilePath = "${isoLetter}:\sources\install.wim"
        if (-not (Test-Path $installFilePath)) {
            $installFilePath = "${isoLetter}:\sources\install.esd"
            if (-not (Test-Path $installFilePath)) {
                Show-Output "No install.wim or install.esd file found. Please verify your ISO contents."
                return
            }
        }
        dism /Get-ImageInfo /ImageFile:$installFilePath | Out-Host
    }
    Catch {
        Show-Output "Error displaying Windows versions: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Create-VHDX {
    Try {
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        if (-not (Test-Path -Path (Split-Path $vhdxPath -Parent))) {
            New-Item -ItemType Directory -Force -Path (Split-Path $vhdxPath -Parent)
        }
        $vhdxSizeBytes = $vhdxSizeGB * 1GB
        New-VHD -Path $vhdxPath -SizeBytes $vhdxSizeBytes -Dynamic
        Mount-VHD -Path $vhdxPath
        Show-Output "VHDX created and mounted successfully."
    }
    Catch {
        Show-Output "Error creating VHDX: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Apply-WindowsImage {
    Show-Output "Warning: Ensure the disk number $diskNumber is correct before proceeding!"
    $confirmation = Read-Host "Type 'yes' to continue, or 'no' to cancel"
    if ($confirmation -ne "yes") {
        Show-Output "Operation cancelled by user."
        Show-Menu
        return
    }
    Try {
        $diskpartScript = @"
select disk $diskNumber
clean
convert gpt
create partition efi size=$efiSizeMB
format fs=fat32 quick
assign letter=$efiletter
create partition primary
format fs=ntfs quick
assign letter=$windowsletter
exit
"@
        $diskpartScript | diskpart
        $installFilePath = "${isoLetter}:\sources\install.wim"
        if (-not (Test-Path $installFilePath)) {
            $installFilePath = "${isoLetter}:\sources\install.esd"
            if (-not (Test-Path $installFilePath)) {
                Show-Output "No install.wim or install.esd file found. Please verify your ISO contents."
                return
            }
        }
        dism /apply-image /imagefile:$installFilePath /index:$index /applydir:${windowsletter}:\
        bcdboot ${windowsletter}:\Windows /s ${efiletter}: /f UEFI
        Show-Output "Windows image applied successfully."
    }
    Catch {
        Show-Output "Error applying Windows image: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Unmount-Everything {
    Try {
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        $mountedVHD = Get-VHD -Path $vhdxPath | Where-Object { $_.Attached -eq $true }
        if ($mountedVHD) {
            Dismount-VHD -Path $vhdxPath
        }
        $allDrives = Get-Volume | Where-Object { $_.DriveLetter -notlike $isoLetter }
        foreach ($drive in $allDrives) {
            Remove-Partition -DriveLetter $drive.DriveLetter -Force
        }
        Show-Output "All drives successfully unmounted."
    }
    Catch {
        Show-Output "Error unmounting drives: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Create-HyperVVM {
    Try {
        $existingVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($existingVM) {
            Show-Output "Error: A VM with the name '$vmName' already exists. Please rename or delete the existing VM before proceeding."
            return
        }
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        If (-not (Test-Path $vhdxPath)) {
            Show-Output "Error: VHDX file does not exist at $vhdxPath"
            return
        }
        New-VM -Name $vmName -MemoryStartupBytes $ramSize -Generation 2 -SwitchName $networkSwitch -Path $vhdxFilePath
        Add-VMHardDiskDrive -VMName $vmName -Path $vhdxPath
        Set-VMProcessor -VMName $vmName -Count $cpuCores
        Set-VM -VMName $vmName -AutomaticCheckpointsEnabled $false
        Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false
        Start-VM -Name $vmName
        vmconnect localhost $vmName
        Show-Output "Hyper-V VM created, configured, and started successfully."
    }
    Catch {
        Show-Output "Error creating Hyper-V VM: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Delete-VHDX {
    Try {
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        Remove-Item -Path $vhdxPath -Force
        Show-Output "VHDX file deleted successfully."
    }
    Catch {
        Show-Output "Error deleting VHDX: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Show-Menu
