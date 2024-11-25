$isoLetter = "F"
$vhdxFileName = "Windows11.vhdx"
$vhdxFilePath = "D:\ALLE programme jetzt hier\Hyper-V"
$vhdxSizeGB = 128
$efiSizeMB = 512
$efiletter = "Z"
$windowsletter = "I"
$index = 5
$diskNumber = 2
$cpuCores = 2
$ramSize = 4GB
$networkSwitch = "Default Switch"
$vmName = "Windows11VM"

Function Show-Output {
    Param([string]$message)
    Write-Host "$message"
}

Function Show-Progress {
    Param([int]$percent)
    $barLength = 50
    $progress = "=" * ($percent / 2)
    $spaces = " " * ($barLength - $progress.Length)
    Write-Host -NoNewline "r[$progress$spaces] $percent%"
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
        Show-Output "Listing available disks..."
        $disks = Get-Disk | Where-Object { $_.OperationalStatus -eq "OK" }
        If ($disks.Count -eq 0) {
            Show-Output "No disks found or disks are not operational."
        } else {
            $disks | ForEach-Object { Show-Output "Disk $($_.Number): $($_.Model) - $($_.Size / 1GB) GB" }
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
        Show-Output "Checking available Windows image indexes..."
        $installFilePath = "${isoLetter}:\sources\install.wim"
        if (-not (Test-Path $installFilePath)) {
            $installFilePath = "${isoLetter}:\sources\install.esd"
            if (-not (Test-Path $installFilePath)) {
                Show-Output "No install.wim or install.esd file found. Please verify your ISO contents."
                return
            }
        }
        Show-Output "Using installation file: $installFilePath"
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
        Show-Output "Creating VHDX file..."
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        if (-not (Test-Path -Path (Split-Path $vhdxPath -Parent))) {
            Show-Output "The specified directory does not exist. Creating directory..."
            New-Item -ItemType Directory -Force -Path (Split-Path $vhdxPath -Parent)
        }
        $vhdxSizeBytes = $vhdxSizeGB * 1GB
        Show-Output "Creating VHDX with size $vhdxSizeGB GB ($vhdxSizeBytes bytes)..."
        New-VHD -Path $vhdxPath -SizeBytes $vhdxSizeBytes -Dynamic
        Mount-VHD -Path $vhdxPath
        Show-Output "VHDX created successfully."
    }
    Catch {
        Show-Output "Error creating VHDX: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Apply-WindowsImage {
    Try {
        Show-Output "WARNING: Make sure the correct disk number ($diskNumber) is configured in the script!"
        $confirmation = Read-Host "Press Enter to continue or press Ctrl + C to cancel"
        if ($confirmation -eq "cancel") {
            Show-Output "Operation canceled."
            return
        }
        Show-Output "Preparing the disk with DiskPart..."
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
        Show-Output "Disk prepared. Applying Windows image..."
        $installFilePath = "${isoLetter}:\sources\install.wim"
        if (-not (Test-Path $installFilePath)) {
            $installFilePath = "${isoLetter}:\sources\install.esd"
            if (-not (Test-Path $installFilePath)) {
                Show-Output "No install.wim or install.esd file found. Please verify your ISO contents."
                return
            }
        }
        Show-Output "Running DISM command..."
        $dismCommand = "dism /apply-image /imagefile:${isoLetter}:\sources\install.wim /index:$index /applydir:${windowsletter}:\ "
        Invoke-Expression $dismCommand
        Show-Output "Windows image applied successfully."
        $bcdbootCommand = "bcdboot ${windowsletter}:\Windows /s ${efiletter}: /f UEFI"
        Invoke-Expression $bcdbootCommand
        Show-Output "BCDBoot command executed successfully."
    }
    Catch {
        Show-Output "Error applying Windows image: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Unmount-Everything {
    Try {
        Show-Output "Unmounting all drives and partitions..."
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        Dismount-VHD -Path $vhdxPath
        $allDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.IsNetwork -eq $false }
        foreach ($drive in $allDrives) {
            if ($drive.Name -ne $isoLetter) {
                Remove-PSDrive -Name $drive.Name -Force
                Show-Output "Unmounted drive $($drive.Name):"
            }
        }
        Show-Output "Unmounting complete."
    }
    Catch {
        Show-Output "Error unmounting drives: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Function Create-HyperVVM {
    Try {
        Show-Output "Creating Hyper-V VM with existing VHDX..."
        $vmMemory = $ramSize
        $vmProcessorCount = $cpuCores
        $switchName = $networkSwitch
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        If (-not (Test-Path $vhdxPath)) {
            Show-Output "Error: VHDX file does not exist at $vhdxPath"
            return
        }
        New-VM -Name $vmName -MemoryStartupBytes $vmMemory -Generation 2 -SwitchName $switchName -Path $vhdxFilePath
        Add-VMHardDiskDrive -VMName $vmName -Path $vhdxPath
        Set-VMProcessor -VMName $vmName -Count $vmProcessorCount
        Show-Output "Hyper-V VM '$vmName' created successfully with existing VHDX."
        Start-VM -Name $vmName
        Show-Output "VM '$vmName' is now starting."
        Show-Output "Connecting to the VM '$vmName'..."
        vmconnect localhost $vmName
    }
    Catch {
        Show-Output "Error creating Hyper-V VM: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

Show-Menu
