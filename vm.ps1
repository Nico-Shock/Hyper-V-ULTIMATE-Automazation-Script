# Konfiguration
$isoLetter = "G"               # ISO Laufwerksbuchstabe
$vhdxFileName = "Windows11.vhdx" # Standardname für das VHDX
$vhdxFilePath = "D:\ALLE programme jetzt hier\Hyper-V"  # Pfad für das VHDX
$vhdxSizeGB = 128              # Größe des VHDX in GB (Wert als Zahl)
$efiSizeMB = 512               # EFI-Partition (in MB)
$efiletter = "Z"               # EFI-Laufwerksbuchstabe
$windowsletter = "I"           # Ziel-Laufwerksbuchstabe
$index = 5                     # Standard-Index für install.wim oder install.esd
$diskNumber = 2                # Standard-Disknummer (kann angepasst werden)

Function Show-Output {
    Param([string]$message)
    Write-Host "$message"
}

Function Show-Progress {
    Param([int]$percent)
    
    # Berechnung der Fortschrittsanzeige
    $barLength = 50  # Länge der Fortschrittsanzeige in Zeichen
    $progress = "=" * ($percent / 2)  # Berechne die Anzahl der "=" basierend auf dem Fortschritt
    $spaces = " " * ($barLength - $progress.Length)  # Berechne die restlichen Leerzeichen
    
    # Zeige die Fortschrittsanzeige an
    Write-Host -NoNewline "`r[$progress$spaces] $percent%"  # Die `r sorgt dafür, dass die Ausgabe überschrieben wird
}

Function Show-Menu {
    Clear
    Show-Output "Please choose an option:"
    Show-Output "1: Check Disk"
    Show-Output "2: Show Windows Version (Index)"
    Show-Output "3: Create VHDX"
    Show-Output "4: Apply Windows Image"
    Show-Output "5: Unmount Everything"
    Show-Output "6: Delete VHDX"
    Show-Output "7: Exit"
    $choice = Read-Host "Enter your choice (1-7)"
    Switch ($choice) {
        1 { Check-Disk }
        2 { Show-WindowsVersion }
        3 { Create-VHDX }
        4 { Apply-WindowsImage }
        5 { Unmount-Everything }
        6 { Delete-VHDX }
        7 { Exit }
    }
}

# Option 1: Check Disk
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

# Option 2: Show Windows Version (Index)
Function Show-WindowsVersion {
    Try {
        Show-Output "`nChecking available Windows image indexes..."
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

# Option 3: Create VHDX
Function Create-VHDX {
    Try {
        Show-Output "Creating VHDX file..."
        $vhdxPath = "$vhdxFilePath\$vhdxFileName"
        if (-not (Test-Path -Path (Split-Path $vhdxPath -Parent))) {
            Show-Output "The specified directory does not exist. Creating directory..."
            New-Item -ItemType Directory -Force -Path (Split-Path $vhdxPath -Parent)
        }
        
        # Berechne die Größe des VHDX in Bytes
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

# Option 4: Apply Windows Image
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
        # DiskPart-Script ausführen
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

        # DISM-Befehl in PowerShell ausführen, ohne neues Fenster zu öffnen
        $dismCommand = "dism /apply-image /imagefile:${isoLetter}:\sources\install.wim /index:$index /applydir:${windowsletter}:\ "
        Invoke-Expression $dismCommand

        Show-Output "Windows image applied successfully."
    }
    Catch {
        Show-Output "Error applying Windows image: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

# Option 5: Unmount Everything
Function Unmount-Everything {
    Try {
        Show-Output "Unmounting all drives and partitions..."
        
        # Alle VHDX-Disk-Images dismounten
        Dismount-VHD -Path "$vhdxFilePath\$vhdxFileName"

        # Alle gemounteten Laufwerke finden und aushängen
        $allDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.IsNetwork -eq $false }
        
        foreach ($drive in $allDrives) {
            if ($drive.Name -ne $isoLetter) {  # Den ISO-Laufwerksbuchstaben überspringen
                Remove-PSDrive -Name $drive.Name
                Show-Output "Unmounted drive $($drive.Name):"
            }
        }
        
        # Alle Partitionen auf der Festplatte aushängen
        $partitions = Get-Partition | Where-Object { $_.DriveLetter }
        foreach ($partition in $partitions) {
            $partitionDriveLetter = $partition.DriveLetter
            Dismount-Volume -DriveLetter $partitionDriveLetter
            Show-Output "Unmounted partition $partitionDriveLetter"
        }

        # ISO-Image auch unmounten
        $isoDriveLetter = $isoLetter + ":"
        if (Test-Path $isoDriveLetter) {
            Remove-PSDrive -Name $isoLetter
            Show-Output "Unmounted ISO drive $isoLetter"
        }
    }
    Catch {
        Show-Output "Error unmounting everything: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

# Option 6: Delete VHDX
Function Delete-VHDX {
    Try {
        Show-Output "Deleting VHDX file..."
        Remove-Item -Path "$vhdxFilePath\$vhdxFileName" -Force
        Show-Output "VHDX file deleted successfully."
    }
    Catch {
        Show-Output "Error deleting VHDX file: $_"
    }
    Read-Host "Press Enter to return to the menu..."
    Show-Menu
}

# Menü starten
Show-Menu