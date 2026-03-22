#################################################################################
#########                                                               #########
#########                 7 Days to Die Mod Downloader                  #########
#########                         Version 1.0                           #########
#########===============================================================#########
#########  Copyright (c) 2026 SingleSidedPCB <singlesidedpcb@gmail.com> #########
######### Licensed under the MIT License. See /LICENSE for details.     #########
#################################################################################
# ==================== CONFIG (easy to change for other packs) ==================
$modName          = "War3zukAIO" # Short clean name for folder/log/GUI
$repoUrl          = "https://dev.azure.com/war3zuk/War3zuk-AIO-Mod-Launcher-v2/_git/War3zuk-AIO-Mod-Launcher-v2"
$gameName         = "7 Days to Die"
$gameEXE          = "7DaysToDie.exe"
$copyBaseName     = "7D2D-$modName"
# ==============================================================================
$gitPortableUrl  = "https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.1/PortableGit-2.53.0-64-bit.7z.exe"
$appName         = "$gameName Mod Downloader ($modName)"
$appVersion      = "1.0"
$logFileName     = "$modName.log"
$scriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$localRepoPath   = Join-Path $scriptDir "$modName-Repo"
$jsonFile        = Join-Path $scriptDir "$modName-settings.json"
$gitCMD          = Join-Path $scriptDir 'PortableGit\cmd\git.exe'
# ==============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# ==================== Functions ===============================================
# Function to check if Git or Portable Git is installed
function Get-GitCommand {
    # First: Check if normal Git is already in PATH
    try {
        $null = & git --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "git"
        }
    } catch {}

    # No system Git, prompt user to install Portable Git
    $msg = "Portable Git not found (Required).`n`nWould you like me to download and install it now?"
    $answer = [System.Windows.Forms.MessageBox]::Show($msg, "Git Required", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)

    if ($answer -eq 'No') { [System.Windows.Forms.MessageBox]::Show( "The script cannot run without Git.`n`nPlease install Git and try again.", "Git Required", 
							[System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error); exit
	}

    # User said Yes. download, extract and install portable git
    Write-Host "Downloading Portable Git..."
    $gitInstallerPath = Join-Path $scriptDir 'PortableGit-2.53.0-64-bit.7z.exe'
    Start-BitsTransfer -Source $gitPortableUrl -Destination $gitInstallerPath
    Write-Host "Extracting Portable Git..."
    Start-Process -FilePath $gitInstallerPath -ArgumentList "-y -o.\PortableGit" -NoNewWindow -Wait
    Remove-Item $gitInstallerPath -Force -ErrorAction SilentlyContinue
    Write-Host "Portable Git installed, Installer file Removed"
    return (Join-Path $scriptDir 'PortableGit\cmd\git.exe')
}

# Function to get Steam installation path from the registry
function Get-SteamPath {
    $steamInstallPath = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
    if (-not (Test-Path -Path $steamInstallPath)) { return $null }
    $steamPath = (Get-ItemProperty -Path $steamInstallPath -Name "InstallPath").InstallPath
    $libraryFoldersPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    if (-not (Test-Path -Path $libraryFoldersPath)) { return $null }

    $libraryFolders = Select-String -Path $libraryFoldersPath -Pattern '"path"' | ForEach-Object {
        if ($_ -match '"path"\s+"([^"]+)"') { $matches[1] -replace '\\\\', '\' | ForEach-Object { $_.Trim() } }
		}

    foreach ($folderPath in $libraryFolders) {
        $gamePath = Join-Path $folderPath "steamapps\common\$gameName"
        if (Test-Path (Join-Path $gamePath $gameEXE)) { return $gamePath }
    }
    return $null
}

# Function to Load settings from JSON file
function Load-Settings {
    if (Test-Path $jsonFile) { Get-Content $jsonFile | ConvertFrom-Json }
    else { @{ installPath = $null; SelectedCommit = $null } }
}

# Function to Save settings to JSON file
function Save-Settings {
    param($settings)
    $settings | ConvertTo-Json | Set-Content $jsonFile
}

# Git Function to populate the dropdown with commit versions
function Populate-CommitDropdown { param($comboBox, $settings)
    & $gitCMD -C $localRepoPath fetch --filter=blob:none --prune --no-tags origin
    $comboBox.Items.Clear()
    $out = & $gitCMD -C $localRepoPath log --pretty=format:"[%h] %s %ad" -n 30 origin/main --date=short
    $comboBox.Items.AddRange(($out -split "`n"))

    if ($settings.SelectedCommit) {
        for ($i = 0; $i -lt $comboBox.Items.Count; $i++) {
            $item = $comboBox.Items[$i].ToString()
            if ($item -match $settings.SelectedCommit) {
                if ($item -notmatch '\(current\)') { $comboBox.Items[$i] = $item + " (current)" }
                $comboBox.SelectedIndex = $i
                break
            }
        }
    }
    if ($comboBox.SelectedIndex -eq -1 -and $comboBox.Items.Count -gt 0) { $comboBox.SelectedIndex = 0 }
	Update-UpdateNotification
}

# git Function to download the selected version
function Checkout-SelectedCommit { param($selectedDisplay)
    if ($selectedDisplay -match '([0-9a-f]{7,40})') { $id = $matches[1] } else { $id = ($selectedDisplay.Split(" "))[0] }
    try {
        & $gitCMD -C $localRepoPath rev-parse --verify "$id^{commit}"
        if ($LASTEXITCODE -ne 0) {
            & $gitCMD -C $localRepoPath fetch --filter=blob:none --prune --tags origin
            if ($LASTEXITCODE -ne 0) { return $false }
            & $gitCMD -C $localRepoPath rev-parse --verify "$id^{commit}"
            if ($LASTEXITCODE -ne 0) { return $false }
        }
        & $gitCMD -C $localRepoPath checkout --force --detach $id
		& $gitCMD -C $localRepoPath gc --auto --prune=now # keep the local repo cleaned up
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

# Function to Update the Status messages
function Update-Status {
    $gameOK = $settings.installPath -and (Test-Path $settings.installPath)
    $modsOK = $gameOK -and (Test-Path (Join-Path $localRepoPath "Mods"))
	$symOK  = $gameOK -and ((Get-Item (Join-Path $settings.installPath "Mods") -EA SilentlyContinue).Attributes -band [System.IO.FileAttributes]::ReparsePoint)

    # Game Copy label
    if ($gameOK) { $lblGame.Text = "Game Copy: Installed"; $lblGame.ForeColor = 'Green'; $lblMods.Visible = $true }
    else { $lblGame.Text = "Game Copy: Click 'Copy Game' first"; $lblGame.ForeColor = 'Red'; return }
    # Mods label (only visible after game is copied)
	if ($modsOK) { $lblMods.Text = "Mods: Ready"; $lblMods.ForeColor = 'Green'; $lblReady.Visible = $true }
    else { $lblMods.Text = "Mods: Select a version and click 'Update Mod'"; $lblMods.ForeColor = 'Red'; return }
	# Ready to Play label (only visible when game and mods are good)
	if ($symOK) { $lblReady.Text = "Ready to Play!"; $lblReady.ForeColor = 'Green' }
	# Catch incase the sym linked Mods folder is broken from an uninstall
	else { $lblReady.Text = "SymLink Broken. click 'Update Mod' to repair"; $lblReady.ForeColor = 'Red'	}
}

# Function to notify if a newer Mod version is availible
function Update-UpdateNotification {
    if ($commitDropdown.SelectedIndex -ge 0 -and $commitDropdown.Items.Count -gt 0) {
        $currentIsLatest = $commitDropdown.SelectedIndex -eq 0
        $lblUpdateAvailable.Visible = -not $currentIsLatest
    } else { $lblUpdateAvailable.Visible = $false }
}

# ==================== Main Execution Start ====================================
Wriet-Host "Welcome to the "
$gitCMD = Get-GitCommand
$settings = Load-Settings

# First-run micro repo clone to get availible commits
if (-not (Test-Path "$localRepoPath\.git\FETCH_HEAD")) {
    if (-not (Test-Path $localRepoPath)) { New-Item -ItemType Directory -Path $localRepoPath | Out-Null }
    & $gitCMD clone --progress --no-checkout --filter=blob:none --depth 30 --single-branch --branch main --no-tags $repoUrl $localRepoPath
	Write-Host "Local repo created and version information downloaded"
}

# ==================== FORM CREATION ==========================================
$form = New-Object System.Windows.Forms.Form
$form.StartPosition = 'CenterScreen'
$form.Text = $appName
$form.Size = New-Object System.Drawing.Size(480, 340)

# Steam path label
$steamPath = Get-SteamPath # get Steam Library path every run incase game is moved
if ($steamPath -and (Test-Path $steamPath)) {
    $gamePathLabel = New-Object System.Windows.Forms.Label
    $gamePathLabel.Text = "Steam Game Path: $steamPath"
    $gamePathLabel.Location = New-Object System.Drawing.Point(10, 10)
    $gamePathLabel.Size = New-Object System.Drawing.Size(440, 30)
    $form.Controls.Add($gamePathLabel)
}

# Copy Label
$copyPathLabel = New-Object System.Windows.Forms.Label
$copyPathLabel.Text = "Copy to (Folder):"
$copyPathLabel.Location = New-Object System.Drawing.Point(10, 40)
$copyPathLabel.Size = New-Object System.Drawing.Size(90, 20)
$form.Controls.Add($copyPathLabel)

# Copy Path box
$copyPathBox = New-Object System.Windows.Forms.TextBox
$copyPathBox.Location = New-Object System.Drawing.Point(100, 40)
$copyPathBox.Size = New-Object System.Drawing.Size(240, 20)
	if ($settings.installPath) { $copyPathBox.Text = $settings.installPath }
	else { $copyPathBox.Text = Join-Path $scriptDir $copyBaseName }
#	else ($steamPath) { $copyPathBox.Text = Join-Path (Split-Path $steamPath -Qualifier) $copyBaseName }
$form.Controls.Add($copyPathBox)

# Copy Browse button
$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse..."
$browseButton.Location = New-Object System.Drawing.Point(350, 38)
$browseButton.Size = New-Object System.Drawing.Size(75, 24)
$form.Controls.Add($browseButton)

# Copy button
$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = "Copy Game"
$copyButton.Location = New-Object System.Drawing.Point(180, 70)
$copyButton.Size = New-Object System.Drawing.Size(75, 24)
$form.Controls.Add($copyButton)

# Commit selection dropdown
$commitDropdown = New-Object System.Windows.Forms.ComboBox
$commitDropdown.Location = New-Object System.Drawing.Point(100, 130)
$commitDropdown.Size = New-Object System.Drawing.Size(320, 30)
$form.Controls.Add($commitDropdown)

#Mod update availible label
$lblUpdateAvailable = New-Object System.Windows.Forms.Label
$lblUpdateAvailable.Location = New-Object System.Drawing.Point(120, 105)  # adjust Y to sit just above dropdown
$lblUpdateAvailable.Size = New-Object System.Drawing.Size(300, 20)
$lblUpdateAvailable.ForeColor = 'DarkOrange'
$lblUpdateAvailable.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 8, [System.Drawing.FontStyle]::Bold)
$lblUpdateAvailable.Text = "Newer version available"
$lblUpdateAvailable.Visible = $false
$form.Controls.Add($lblUpdateAvailable)

# Update Mod button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = "Update Mod"
$updateButton.Size = New-Object System.Drawing.Size(75, 30)
$updateButton.Location = New-Object System.Drawing.Point(10, 130)
$form.Controls.Add($updateButton)

# Play button (with --self-contained and logfile)
$playButton = New-Object System.Windows.Forms.Button
$playButton.Text = "Play"
$playButton.Size = New-Object System.Drawing.Size(75, 30)
$playButton.Location = New-Object System.Drawing.Point(10, 170)
$form.Controls.Add($playButton)

# Add Shortcut button
$shortcutButton = New-Object System.Windows.Forms.Button
$shortcutButton.Text = "Add Shortcut to Desktop"
$shortcutButton.Size = New-Object System.Drawing.Size(140, 30)
$shortcutButton.Location = New-Object System.Drawing.Point(100, 170)
$form.Controls.Add($shortcutButton)

# Uninstall button
$uninstallButton = New-Object System.Windows.Forms.Button
$uninstallButton.Text = "Uninstall"
$uninstallButton.ForeColor = 'Red'
$uninstallButton.Size = New-Object System.Drawing.Size(75, 30)
$uninstallButton.Location = New-Object System.Drawing.Point(255, 170)
$form.Controls.Add($uninstallButton)

# Game Copy status label
$lblGame = New-Object System.Windows.Forms.Label
$lblGame.Location = New-Object System.Drawing.Point(20, 205)
$lblGame.Size = New-Object System.Drawing.Size(440, 20)
$lblGame.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblGame)

# Mod Download status label
$lblMods = New-Object System.Windows.Forms.Label
$lblMods.Location = New-Object System.Drawing.Point(20, 230)
$lblMods.Size = New-Object System.Drawing.Size(440, 20)
$lblMods.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12, [System.Drawing.FontStyle]::Bold)
$lblMods.Visible = $false         # hidden until game is copied
$form.Controls.Add($lblMods)

# Ready to Play status label
$lblReady = New-Object System.Windows.Forms.Label
$lblReady.Location = New-Object System.Drawing.Point(20, 255)
$lblReady.Size = New-Object System.Drawing.Size(440, 20)
$lblReady.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12, [System.Drawing.FontStyle]::Bold)
$lblReady.Visible = $false        # hidden until everything is ready
$form.Controls.Add($lblReady)

# version Label
$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = "v $appVersion by SingleSidedPCB"
$versionLabel.Location = New-Object System.Drawing.Point(370, 265)
$versionLabel.Size = New-Object System.Drawing.Size(88, 28)
$form.Controls.Add($versionLabel)

# Populate commit version dropdown at startup
try { Populate-CommitDropdown $commitDropdown $settings } catch { Write-Host "Populate failed: $_" }

# ==================== BUTTON HANDLERS ========================================
$browseButton.Add_Click({
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fb.ShowDialog() -eq 'OK') { $copyPathBox.Text = Join-Path $fb.SelectedPath $copyBaseName }
})

$copyButton.Add_Click({
    $copyFolderPath = $copyPathBox.Text.Trim()
    if (-not $copyFolderPath) { [System.Windows.Forms.MessageBox]::Show("Please enter a copy path.", "Error"); return }

    if (Test-Path $copyFolderPath) {
        if (Get-ChildItem -Path $copyFolderPath -Force -ErrorAction SilentlyContinue) {
            [System.Windows.Forms.MessageBox]::Show("$copyFolderPath`n`nis not empty, Copy canceled.`n`nUninstall the game copy or choose a different folder.", 
                "Folder Not Empty", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning); return }
    }

    if (-not (Test-Path $copyFolderPath)) { New-Item -ItemType Directory -Path $copyFolderPath | Out-Null }
    $settings.installPath = $copyFolderPath
    Save-Settings $settings

    $waiting = New-Object System.Windows.Forms.Form
    $waiting.Text = "Copying Game"
    $waiting.Size = New-Object System.Drawing.Size(300,100)
    $waiting.StartPosition = 'CenterScreen'
    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = "Copying Please Wait..."; $lbl.Dock = 'Fill'; $lbl.TextAlign = 'MiddleCenter'
    $waiting.Controls.Add($lbl)
    $waiting.Show(); $waiting.Refresh()

    try {
        $args = @("`"$($steamPath)`"", "`"$copyFolderPath`"", '/E','/Z','/R:2','/W:5','/XD','Mods','.git','/NFL','/NDL','/NJH','/NC','/NS')
        $proc = Start-Process robocopy.exe -ArgumentList $args -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -gt 7) { throw "Robocopy failed (exit $($proc.ExitCode))" }

		Update-Status
		[System.Windows.Forms.MessageBox]::Show("Game copy complete!`n`nNext: click Update Mod to install mods.", "Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed: $_", "Error")
    } finally { $waiting.Close() }
})

$updateButton.Add_Click({
    if (-not $settings.installPath -or -not (Test-Path $settings.installPath)) {
        [System.Windows.Forms.MessageBox]::Show("Please click 'Copy Game' first!", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    if ($commitDropdown.SelectedIndex -lt 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a version from the dropdown.", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $selectedDisplay = $commitDropdown.SelectedItem.ToString()

    # Waiting form
    $waitingForm = New-Object System.Windows.Forms.Form
    $waitingForm.Text = "Updating Mod"
    $waitingForm.Size = New-Object System.Drawing.Size(300,100)
    $waitingForm.StartPosition = 'CenterScreen'
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Updating Please Wait..."
    $label.AutoSize = $false
    $label.TextAlign = 'MiddleCenter'
    $label.Dock = 'Fill'
    $waitingForm.Controls.Add($label)
    $waitingForm.Show()
    $waitingForm.Refresh()

    try {
        if (Checkout-SelectedCommit $selectedDisplay) {
            if ($selectedDisplay -match '([0-9a-f]{7,40})') {
                $settings.SelectedCommit = $matches[1]
                Save-Settings $settings
            }

            # 2. Create symlink + one-time Harmony Check/Copy (only on first successful update)
			if (-not (Test-Path (Join-Path $settings.installPath "Mods")) -or -not ((Get-Item (Join-Path $settings.installPath "Mods")).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
				if (Test-Path (Join-Path $settings.installPath "Mods")) { Remove-Item (Join-Path $settings.installPath "Mods") -Recurse -Force }
				New-Item -ItemType SymbolicLink -Path (Join-Path $settings.installPath "Mods") -Target (Join-Path $localRepoPath "Mods") | Out-Null
				
                $harmonySteam = Join-Path $steamPath "Mods\0_TFP_Harmony"
                $harmonyGame  = Join-Path $settings.installPath "Mods\0_TFP_Harmony"
                if ((Test-Path $harmonySteam) -and -not (Test-Path $harmonyGame)) {
                    Copy-Item $harmonySteam $harmonyGame -Recurse -Force
                }
			}

            Populate-CommitDropdown $commitDropdown $settings
            Update-Status
			Update-UpdateNotification
            [System.Windows.Forms.MessageBox]::Show("Mod updated successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    } catch { [System.Windows.Forms.MessageBox]::Show("Update failed: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } finally { $waitingForm.Close() }
})

$playButton.Add_Click({
    if (-not $settings.installPath) { [System.Windows.Forms.MessageBox]::Show("Please click Copy Game first!"); return }
    $exe = Join-Path $settings.installPath $gameEXE
    if (Test-Path $exe) {
        Start-Process $exe -ArgumentList "--self-contained -logfile=$logFileName" -WorkingDirectory (Split-Path $exe -Parent)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Game executable not found.", "Error")
    }
})

$shortcutButton.Add_Click({
    if (-not $settings.installPath) { [System.Windows.Forms.MessageBox]::Show("Please click Copy Game first!"); return }
    $exe = Join-Path $settings.installPath $gameEXE
    $desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) "$gameEXE.lnk"
    $Wsh = New-Object -ComObject WScript.Shell
    $sc = $Wsh.CreateShortcut($desktop)
    $sc.TargetPath = $exe
    $sc.WorkingDirectory = Split-Path $exe -Parent
    $sc.Arguments = "--self-contained -logfile=$logFileName"
    $sc.IconLocation = "$exe,0"
    $sc.Save()
    [System.Windows.Forms.MessageBox]::Show("Shortcut created with --self-contained and correct log file.", "Success")
})

$uninstallButton.Add_Click({
    if (-not $settings.installPath) { [System.Windows.Forms.MessageBox]::Show("Nothing to uninstall yet."); return }

    $uForm = New-Object System.Windows.Forms.Form
    $uForm.Text = "Uninstall Confirmation"
    $uForm.Size = New-Object System.Drawing.Size(420, 280)
    $uForm.StartPosition = 'CenterScreen'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "WARNING - THIS CANNOT BE UNDONE`nBACKUP ANY CUSTOM MOD FOLDERS NOW`nBACKUP ANY SAVES NOW - WARNING`n`nSelect what to delete:"
    $lbl.Location = New-Object System.Drawing.Point(20,20)
    $lbl.Size = New-Object System.Drawing.Size(380,60)
    $uForm.Controls.Add($lbl)

    $cbGame   = New-Object System.Windows.Forms.CheckBox
	$cbGame.Text = "Delete game copy folder ($($settings.installPath))"
	$cbGame.Location = New-Object System.Drawing.Point(30,90)
	$cbGame.AutoSize = $true
	$cbGame.Checked = $false
	$uForm.Controls.Add($cbGame)
	
    $cbRepo   = New-Object System.Windows.Forms.CheckBox
	$cbRepo.Text = "Delete local mod repository ($($localRepoPath))"
	$cbRepo.Location = New-Object System.Drawing.Point(30,120)
	$cbRepo.AutoSize = $true
	$cbRepo.Checked = $false
	$uForm.Controls.Add($cbRepo)
	
	if ($gitCMD -ne 'git') {
	$cbGit = New-Object System.Windows.Forms.CheckBox
	$cbGit.Text = "Delete Portable Git"
	$cbGit.Location = New-Object System.Drawing.Point(30,150)
	$cbGit.AutoSize = $true; $cbGit.Checked = $false
	$uForm.Controls.Add($cbGit)
	}

    $btnCancel = New-Object System.Windows.Forms.Button
	$btnCancel.Text = "Cancel"
	$btnCancel.Location = New-Object System.Drawing.Point(80,200)
	$btnCancel.DialogResult = 'Cancel'
	$uForm.Controls.Add($btnCancel)
    $btnOK     = New-Object System.Windows.Forms.Button
	$btnOK.Text = "Proceed"
	$btnOK.Location = New-Object System.Drawing.Point(220,200)
	$btnOK.DialogResult = 'OK'
	$uForm.Controls.Add($btnOK)

    if ($uForm.ShowDialog() -eq 'OK') {
        if ($cbGame.Checked) {
            Remove-Item $settings.installPath -Recurse -Force -ErrorAction SilentlyContinue
			$settings.installPath = $null
			Save-Settings $settings
        }
        if ($cbRepo.Checked) { 
			Remove-Item $localRepoPath -Recurse -Force -ErrorAction SilentlyContinue
            $settings.SelectedCommit = $null
            Save-Settings $settings
		}
        if ($cbGit.Checked)  { Remove-Item (Join-Path $scriptDir "PortableGit") -Recurse -Force -ErrorAction SilentlyContinue }

        [System.Windows.Forms.MessageBox]::Show("Cleanup complete!`n`nScript will now close.`nRe-run it to start fresh.", "Success")
        
        $form.Close()          # properly close the main form
        [Environment]::Exit(0) # force script end
    }
})

$form.Add_Shown({ Update-Status; Update-UpdateNotification; $form.Activate() })
[void]$form.ShowDialog()
