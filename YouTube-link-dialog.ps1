# LeLeVC_YouTube Downloader 1.0 - original author: LeLeVC
# Legacy SettingsDir and mutex names intentionally preserve existing settings and locking.
param(
    [Parameter(Mandatory = $true)][string]$DialogDir,
    [string]$SettingsDir = (Join-Path $env:LOCALAPPDATA 'Lech_Reaper YouTube Downloader')
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
function Save-Text([string]$Name, [string]$Value) {
    [IO.File]::WriteAllText((Join-Path $DialogDir $Name), $Value, $utf8)
}
try {
    Save-Text 'started.txt' '1'
    $dialogMutex = New-Object Threading.Mutex($false, 'Local\Lech_Reaper_YouTube_Downloader_Dialog')
    try { $ownsMutex = $dialogMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { Save-Text 'done.txt' 'CANCEL'; exit 0 }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
public class DownloaderUrlBox : System.Windows.Forms.TextBox {
  public event EventHandler Pasted;
  protected override void WndProc(ref System.Windows.Forms.Message m) {
    bool paste = m.Msg == 0x0302;
    base.WndProc(ref m);
    if (paste && Pasted != null) Pasted(this, EventArgs.Empty);
  }
}
'@
    [Windows.Forms.Application]::EnableVisualStyles()
    $toolsDir = Join-Path $PSScriptRoot 'tools'
    $toolMissing = @('yt-dlp', 'ffmpeg', 'ffprobe', 'deno') | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $toolsDir ($_ + '.exe')) -PathType Leaf) -and -not (Get-Command $_ -ErrorAction SilentlyContinue)
    }
    if ($toolMissing.Count) {
        $installer = Join-Path $PSScriptRoot 'Install-tools.ps1'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Missing Install-tools.ps1.' }
        $powerShellExe = (Get-Process -Id $PID).Path
        $installerProcess = Start-Process -FilePath $powerShellExe -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $installer + '"'), '-InstallDir', ('"' + $toolsDir + '"')) -Wait -PassThru
        if ($installerProcess.ExitCode -ne 0) { Save-Text 'done.txt' 'CANCEL'; exit 0 }
        $toolMissing = @('yt-dlp', 'ffmpeg', 'ffprobe', 'deno') | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $toolsDir ($_ + '.exe')) -PathType Leaf) -and -not (Get-Command $_ -ErrorAction SilentlyContinue)
        }
        if ($toolMissing.Count) { throw ('Required tools are still missing: ' + ($toolMissing -join ', ')) }
    }
    $form = New-Object Windows.Forms.Form
    $form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Font
    $form.Text = 'LeLeVC_YouTube Downloader'
    $form.ClientSize = New-Object Drawing.Size(900, 456)
    $form.FormBorderStyle = 'Sizable'
    $form.MaximizeBox = $true
    $form.MinimizeBox = $true
    $form.StartPosition = 'CenterScreen'
    # Respect larger Windows UI text while keeping the current readable baseline.
    $systemFont = [Drawing.SystemFonts]::MessageBoxFont
    $form.Font = New-Object Drawing.Font($systemFont.FontFamily, [Math]::Max(10.0, $systemFont.SizeInPoints), $systemFont.Style)
    $label = New-Object Windows.Forms.Label
    $label.Text = 'YouTube URL'
    $label.SetBounds(16, 12, 300, 24)
    $startTimeLabel = New-Object Windows.Forms.Label
    $startTimeLabel.Text = ''
    $startTimeLabel.ForeColor = [Drawing.Color]::DarkGreen
    $startTimeLabel.TextAlign = 'MiddleRight'
    $startTimeLabel.SetBounds(330, 12, 400, 24)
    $startTimeLabel.Anchor = 'Top,Right'
    $urlBox = New-Object DownloaderUrlBox
    $urlBox.SetBounds(16, 40, 868, 28)
    $urlBox.TabIndex = 0
    $historyLabel = New-Object Windows.Forms.Label
    $historyLabel.Text = 'Recent downloads'
    $historyLabel.SetBounds(16, 228, 668, 24)
    $list = New-Object Windows.Forms.DataGridView
    $list.SetBounds(16, 256, 868, 134)
    $list.TabIndex = 1
    $list.ReadOnly = $true
    $list.AllowUserToAddRows = $false
    $list.AllowUserToDeleteRows = $false
    $list.AllowUserToResizeRows = $false
    $list.RowHeadersVisible = $false
    $list.MultiSelect = $false
    $list.SelectionMode = 'FullRowSelect'
    $list.AutoSizeColumnsMode = 'Fill'
    $list.RowTemplate.Height = 25
    $null = $list.Columns.Add('Title', 'Video title')
    $null = $list.Columns.Add('Url', 'YouTube URL')
    $deleteColumn = New-Object Windows.Forms.DataGridViewButtonColumn
    $deleteColumn.Name = 'Delete'
    $deleteColumn.HeaderText = ''
    $deleteColumn.Text = 'Delete'
    $deleteColumn.UseColumnTextForButtonValue = $true
    $null = $list.Columns.Add($deleteColumn)
    $list.Columns[0].FillWeight = 45
    $list.Columns[1].FillWeight = 45
    $list.Columns[2].FillWeight = 10
    foreach ($column in $list.Columns) { $column.SortMode = 'NotSortable' }
    $removed = New-Object 'System.Collections.Generic.List[string]'
    $lookups = New-Object System.Collections.ArrayList
    $history = [IO.File]::ReadAllLines((Join-Path $DialogDir 'history.txt'), $utf8)
    foreach ($line in $history) {
        $parts = $line -split "`t", 2
        $url = $parts[0]
        $videoTitle = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        if ($url -match '^https://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}$' -and $list.Rows.Count -lt 10) {
            $rowIndex = $list.Rows.Add($videoTitle, $url)
            if ([string]::IsNullOrWhiteSpace($videoTitle)) {
                $list.Rows[$rowIndex].Cells[0].Value = 'Loading title...'
                # Fetch legacy titles in background; editing and pasting remain responsive.
                $lookup = [PowerShell]::Create()
                $null = $lookup.AddScript({ param($videoUrl)
                    $ErrorActionPreference = 'Stop'
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    $endpoint = 'https://www.youtube.com/oembed?format=json&url=' + [Uri]::EscapeDataString($videoUrl)
                    try { (Invoke-RestMethod -Uri $endpoint -TimeoutSec 8).title } catch { '' }
                }).AddArgument($url)
                $null = $lookups.Add(@{Pipe=$lookup; Handle=$lookup.BeginInvoke(); Url=$url})
            }
        }
    }
    if ($list.Rows.Count -eq 0) { $historyLabel.Text = 'Recent downloads - no downloads yet' }
    $copyMenu = New-Object Windows.Forms.ContextMenuStrip
    $copyTitleItem = $copyMenu.Items.Add('Copy title')
    $copyTitleItem.Add_Click({
        if ($copyMenu.Tag) { [Windows.Forms.Clipboard]::SetText([string]$copyMenu.Tag.Cells[0].Value) }
    })
    $copyUrlItem = $copyMenu.Items.Add('Copy URL')
    $copyUrlItem.Add_Click({
        if ($copyMenu.Tag) { [Windows.Forms.Clipboard]::SetText([string]$copyMenu.Tag.Cells[1].Value) }
    })
    $list.Add_CellMouseClick({ param($sender, $event)
        if ($event.RowIndex -lt 0) { return }
        $row = $list.Rows[$event.RowIndex]
        $url = [string]$row.Cells[1].Value
        if ($event.Button -eq [Windows.Forms.MouseButtons]::Right) {
            if ($event.ColumnIndex -eq 0 -or $event.ColumnIndex -eq 1) {
                $copyMenu.Tag = $row
                $videoTitle = [string]$row.Cells[0].Value
                $copyTitleItem.Enabled = $videoTitle -and $videoTitle -notin @('Loading title...', 'Title unavailable')
                $copyMenu.Show([Windows.Forms.Cursor]::Position)
            }
            return
        }
        if ($event.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
        if ($event.ColumnIndex -eq 2) {
            $removed.Add($url)
            $list.Rows.RemoveAt($event.RowIndex)
        } elseif ($event.ColumnIndex -eq 0 -or $event.ColumnIndex -eq 1) {
            $urlBox.Text = $url
            $urlBox.SelectAll()
            & $processPastedLink
        }
    })
    $clear = New-Object Windows.Forms.Button
    $clear.Text = 'Clear history'
    $clear.SetBounds(16, 410, 140, 30)
    $clear.Add_Click({
        foreach ($row in $list.Rows) { $removed.Add([string]$row.Cells[1].Value) }
        $list.Rows.Clear()
        $historyLabel.Text = 'Recent downloads - no downloads yet'
    })
    $toolUpdates = New-Object Windows.Forms.Button
    $toolUpdates.Text = 'Tool updates'
    $toolUpdates.SetBounds(752, 7, 132, 30)
    $toolUpdates.Add_Click({
        & $saveWindow
        $form.Hide()
        try {
            $installer = Join-Path $PSScriptRoot 'Install-tools.ps1'
            $powerShellExe = (Get-Process -Id $PID).Path
            $null = Start-Process -FilePath $powerShellExe -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $installer + '"'), '-InstallDir', ('"' + $toolsDir + '"'), '-Update') -Wait -PassThru
        } finally {
            $form.Show()
            $form.Activate()
        }
    })
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 200
    $timer.Add_Tick({
        if ($uiState -and $uiState.Page -eq 'progress') { & $updateProgress }
        if (Test-Path -LiteralPath (Join-Path $DialogDir 'cancel.txt')) {
            $form.DialogResult = [Windows.Forms.DialogResult]::Cancel
            $form.Close()
            return
        }
        for ($i = $lookups.Count - 1; $i -ge 0; $i--) {
            $lookup = $lookups[$i]
            if ($lookup.Handle.IsCompleted) {
                $value = ($lookup.Pipe.EndInvoke($lookup.Handle) -join '').Trim() -replace '[\r\n\t]', ' '
                foreach ($row in $list.Rows) {
                    if ([string]$row.Cells[1].Value -eq $lookup.Url) {
                        $row.Cells[0].Value = if ($value) { $value } else { 'Title unavailable' }
                    }
                }
                $lookup.Pipe.Dispose()
                $lookups.RemoveAt($i)
            }
        }
    })
    $timer.Start()
    $next = New-Object Windows.Forms.Button
    $next.Text = 'Continue'
    $next.SetBounds(668, 410, 104, 30)
    $next.TabIndex = 2
    $uiState = @{ Page = 'link' }
    $startDownload = {
        if ($uiState.Page -ne 'options' -or $qualityList.SelectedIndex -lt 0) { return }
        foreach ($name in @('download-result.txt', 'job-dir.txt')) {
            $oldPath = Join-Path $DialogDir $name
            if (Test-Path -LiteralPath $oldPath) { Remove-Item -LiteralPath $oldPath }
        }
        $uiState.RequestId = [guid]::NewGuid().ToString('N')
        Save-Text 'url.txt' $urlBox.Text.Trim()
        Save-Text 'folder.txt' $folderBox.Text.Trim()
        Save-Text 'project-folder-name.txt' $(if ($projectFolder) { $projectFolderNameBox.Text.Trim() } else { '' })
        Save-Text 'option.txt' ([string]($qualityList.SelectedIndex + 1))
        Save-Text 'secondary-folder.txt' $(if ($projectFolder -and $secondaryCopy.Checked) { $secondaryFolderBox.Text.Trim() } else { '' })
        Save-Text 'mute-mode.txt' @('none', 'item', 'track', 'both')[$muteMode.SelectedIndex]
        Save-Text 'import-position.txt' @('start', 'cursor', 'track_end')[$importPosition.SelectedIndex]
        if ($rememberFolder.Checked -and -not $projectFolder) { Save-Text 'remember-folder.txt' $folderBox.Text.Trim() }
        & $showProgress
        Save-Text 'start-download.txt' $uiState.RequestId
    }
    $next.Add_Click({
        if ($uiState.Page -eq 'progress') { $form.Close(); return }
        if ($uiState.Page -eq 'options') {
            if ($qualityList.SelectedIndex -lt 0) { $qualityList.Focus(); return }
            & $startDownload
            return
        }
        if (-not [string]::IsNullOrWhiteSpace($urlBox.Text)) {
            if ($projectFolder -and -not (& $isValidProjectFolderName $projectFolderNameBox.Text)) {
                [Windows.Forms.MessageBox]::Show($form, 'Enter a valid project download folder name.', $form.Text) | Out-Null
                return
            }
            if ([string]::IsNullOrWhiteSpace($folderBox.Text) -or -not [IO.Path]::IsPathRooted($folderBox.Text) -or $folderBox.Text -match '[\r\n"]') {
                [Windows.Forms.MessageBox]::Show($form, 'Select a valid download folder.', $form.Text) | Out-Null
                return
            }
            if ($projectFolder -and $secondaryCopy.Checked -and ([string]::IsNullOrWhiteSpace($secondaryFolderBox.Text) -or -not [IO.Path]::IsPathRooted($secondaryFolderBox.Text) -or $secondaryFolderBox.Text -match '[\r\n"]')) {
                [Windows.Forms.MessageBox]::Show($form, 'Select a valid additional copy folder.', $form.Text) | Out-Null
                return
            }
            & $continueFromLink
        } else { $urlBox.Focus() }
    })
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.SetBounds(780, 410, 104, 30)
    $cancel.TabIndex = 3
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.AcceptButton = $next
    $form.CancelButton = $cancel
    $form.Controls.AddRange(@($label, $startTimeLabel, $urlBox, $historyLabel, $list, $clear, $toolUpdates, $next, $cancel))
    # Explorer's registered Downloads location also handles redirected/localized folders.
    $projectFolder = [IO.File]::ReadAllText((Join-Path $DialogDir 'project-folder.txt'), $utf8).Trim()
    $null = [IO.Directory]::CreateDirectory($SettingsDir)
    $projectFolderNamePreference = Join-Path $SettingsDir 'project-folder-name.txt'
    $projectFolderName = 'Downloaded'
    if (Test-Path -LiteralPath $projectFolderNamePreference) {
        $savedProjectFolderName = [IO.File]::ReadAllText($projectFolderNamePreference, $utf8).Trim()
        if ($savedProjectFolderName) { $projectFolderName = $savedProjectFolderName }
    }
    $defaultFolder = if ($projectFolder) { Join-Path $projectFolder $projectFolderName } else { '' }
    $preferencePath = Join-Path $DialogDir 'default-folder.txt'
    if (-not $defaultFolder -and (Test-Path -LiteralPath $preferencePath)) {
        $defaultFolder = [IO.File]::ReadAllText($preferencePath, $utf8).Trim()
    }
    if (-not $defaultFolder) {
        $key = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
        $defaultFolder = [Environment]::ExpandEnvironmentVariables([string]$key.'{374DE290-123F-4565-9164-39C4925E467B}')
        if (-not $defaultFolder) { $defaultFolder = Join-Path $env:USERPROFILE 'Downloads' }
    }
    $form.ClientSize = New-Object Drawing.Size(900, 568)
    $folderLabel = New-Object Windows.Forms.Label
    $folderLabel.Text = 'Download folder'
    $folderLabel.SetBounds(16, 410, 130, 24)
    $projectFolderNameBox = New-Object Windows.Forms.TextBox
    $projectFolderNameBox.SetBounds(150, 406, 354, 28)
    $projectFolderNameBox.Text = $projectFolderName
    $projectFolderNameBox.Visible = [bool]$projectFolder
    $folderBox = New-Object Windows.Forms.TextBox
    $folderBox.SetBounds(16, 438, 744, 28)
    $folderBox.Text = $defaultFolder
    $browse = New-Object Windows.Forms.Button
    $browse.Text = 'Browse...'
    $browse.SetBounds(772, 436, 112, 30)
    $browse.Add_Click({
        $picker = New-Object Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Select download folder'
        $picker.SelectedPath = $folderBox.Text
        $picker.ShowNewFolderButton = $true
        if ($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) { $folderBox.Text = $picker.SelectedPath }
        $picker.Dispose()
    })
    $rememberFolder = New-Object Windows.Forms.CheckBox
    $rememberFolder.Text = 'Use as default folder for unsaved projects'
    $rememberFolder.SetBounds(16, 476, 600, 26)
    $rememberFolder.AutoSize = $true
    $rememberFolder.Enabled = -not [bool]$projectFolder
    if ($projectFolder) {
        $folderBox.ReadOnly = $true
        $browse.Enabled = $false
        $rememberFolder.Text = 'Saved project: files go to the Downloaded folder'
    }
    $isValidProjectFolderName = {
        param([string]$Value)
        $name = $Value.Trim()
        return $name -ne '' -and $name -notin @('.', '..') -and
            $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0 -and
            $name -notmatch '[\. ]$' -and
            $name -notmatch '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$'
    }
    $projectFolderNameBox.Add_TextChanged({
        if ($projectFolder) { $folderBox.Text = Join-Path $projectFolder $projectFolderNameBox.Text.Trim() }
    })
    $secondaryCopy = New-Object Windows.Forms.CheckBox
    $secondaryCopy.Text = 'Also save a copy to'
    $secondaryCopy.SetBounds(16, 476, 210, 26)
    $secondaryCopy.AutoSize = $true
    $secondaryCopy.Visible = [bool]$projectFolder
    $secondaryFolderBox = New-Object Windows.Forms.TextBox
    $secondaryFolderBox.SetBounds(228, 476, 532, 28)
    $secondaryFolderBox.Visible = [bool]$projectFolder
    $secondaryBrowse = New-Object Windows.Forms.Button
    $secondaryBrowse.Text = 'Browse...'
    $secondaryBrowse.SetBounds(772, 474, 112, 30)
    $secondaryBrowse.Visible = [bool]$projectFolder
    $null = [IO.Directory]::CreateDirectory($SettingsDir)
    $secondaryPreferencePath = Join-Path $SettingsDir 'secondary-folder.txt'
    $secondaryEnabledPath = Join-Path $SettingsDir 'secondary-enabled.txt'
    if (Test-Path -LiteralPath $secondaryPreferencePath) {
        $secondaryFolderBox.Text = [IO.File]::ReadAllText($secondaryPreferencePath, $utf8).Trim()
    }
    if (Test-Path -LiteralPath $secondaryEnabledPath) {
        $secondaryCopy.Checked = [IO.File]::ReadAllText($secondaryEnabledPath, $utf8).Trim() -eq '1'
    }
    $updateSecondaryControls = {
        $secondaryFolderBox.Enabled = $secondaryCopy.Checked
        $secondaryBrowse.Enabled = $secondaryCopy.Checked
    }
    $secondaryCopy.Add_CheckedChanged({
        [IO.File]::WriteAllText($secondaryEnabledPath, [string][int]$secondaryCopy.Checked, $utf8)
        & $updateSecondaryControls
    })
    $secondaryFolderBox.Add_TextChanged({
        if ($projectFolder) { [IO.File]::WriteAllText($secondaryPreferencePath, $secondaryFolderBox.Text, $utf8) }
    })
    $secondaryBrowse.Add_Click({
        $picker = New-Object Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Select additional copy folder'
        $picker.SelectedPath = $secondaryFolderBox.Text
        $picker.ShowNewFolderButton = $true
        if ($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) { $secondaryFolderBox.Text = $picker.SelectedPath }
        $picker.Dispose()
    })
    & $updateSecondaryControls
    if ($projectFolder) { $rememberFolder.Visible = $false }
    $clear.Top = 522
    $next.Top = 522
    $cancel.Top = 522
    $form.Controls.AddRange(@($folderLabel, $projectFolderNameBox, $folderBox, $browse, $rememberFolder, $secondaryCopy, $secondaryFolderBox, $secondaryBrowse))
    # Keep the vertical space needed by all controls, while allowing a narrower window.
    $form.MinimumSize = New-Object Drawing.Size(740, $form.Size.Height)
    $urlBox.Anchor = 'Top,Left,Right'
    $list.Anchor = 'Top,Bottom,Left,Right'
    $folderLabel.Anchor = 'Bottom,Left'
    $projectFolderNameBox.Anchor = 'Bottom,Left'
    $folderBox.Anchor = 'Bottom,Left,Right'
    $browse.Anchor = 'Bottom,Right'
    $rememberFolder.Anchor = 'Bottom,Left'
    $secondaryCopy.Anchor = 'Bottom,Left'
    $secondaryFolderBox.Anchor = 'Bottom,Left,Right'
    $secondaryBrowse.Anchor = 'Bottom,Right'
    $clear.Anchor = 'Bottom,Left'
    $toolUpdates.Anchor = 'Top,Right'
    $next.Anchor = 'Bottom,Right'
    $cancel.Anchor = 'Bottom,Right'
    $autoContinue = New-Object Windows.Forms.CheckBox
    $autoContinue.Text = 'Go to the next step after pasting or choosing a link'
    $autoContinue.SetBounds(16, 104, 680, 26)
    $autoContinue.AutoSize = $true
    $autoContinue.Anchor = 'Top,Left'
    $null = [IO.Directory]::CreateDirectory($SettingsDir)
    $autoContinuePath = Join-Path $SettingsDir 'auto-continue.txt'
    if (Test-Path -LiteralPath $autoContinuePath) {
        $autoContinue.Checked = [IO.File]::ReadAllText($autoContinuePath).Trim() -eq '1'
    }
    $autoContinue.Add_CheckedChanged({
        [IO.File]::WriteAllText($autoContinuePath, [string][int]$autoContinue.Checked, $utf8)
    })
    $autoQuality = New-Object Windows.Forms.CheckBox
    $autoQuality.Text = 'Use automatic quality (skip quality selection)'
    $autoQuality.SetBounds(16, 132, 680, 26)
    $autoQuality.AutoSize = $true
    $autoQuality.Anchor = 'Top,Left'
    $autoQualityPath = Join-Path $SettingsDir 'auto-quality.txt'
    if (Test-Path -LiteralPath $autoQualityPath) {
        $autoQuality.Checked = [IO.File]::ReadAllText($autoQualityPath).Trim() -eq '1'
    }
    $autoQuality.Add_CheckedChanged({
        [IO.File]::WriteAllText($autoQualityPath, [string][int]$autoQuality.Checked, $utf8)
    })
    $autoClipboard = New-Object Windows.Forms.CheckBox
    $autoClipboard.Text = 'Paste YouTube link from clipboard on startup'
    $autoClipboard.SetBounds(16, 76, 680, 26)
    $autoClipboard.AutoSize = $true
    $autoClipboard.Anchor = 'Top,Left'
    $autoClipboardPath = Join-Path $SettingsDir 'clipboard-on-startup.txt'
    if (Test-Path -LiteralPath $autoClipboardPath) {
        $autoClipboard.Checked = [IO.File]::ReadAllText($autoClipboardPath).Trim() -eq '1'
    }
    $autoClipboard.Add_CheckedChanged({
        [IO.File]::WriteAllText($autoClipboardPath, [string][int]$autoClipboard.Checked, $utf8)
    })
    $muteModeLabel = New-Object Windows.Forms.Label
    $muteModeLabel.Text = 'Mute after import'
    $muteModeLabel.SetBounds(16, 164, 130, 26)
    $muteMode = New-Object Windows.Forms.ComboBox
    $muteMode.DropDownStyle = 'DropDownList'
    $muteMode.SetBounds(150, 160, 530, 30)
    $null = $muteMode.Items.Add('None')
    $null = $muteMode.Items.Add('Item')
    $null = $muteMode.Items.Add('Track')
    $null = $muteMode.Items.Add('Item and track')
    # Use a new preference name so this four-option version starts at None.
    $muteModePath = Join-Path $SettingsDir 'mute-mode-v2.txt'
    $muteMode.SelectedIndex = 0
    if (Test-Path -LiteralPath $muteModePath) {
        $savedMuteMode = [IO.File]::ReadAllText($muteModePath, $utf8).Trim()
        if ($savedMuteMode -eq 'item') { $muteMode.SelectedIndex = 1 }
        if ($savedMuteMode -eq 'track') { $muteMode.SelectedIndex = 2 }
        if ($savedMuteMode -eq 'both') { $muteMode.SelectedIndex = 3 }
    }
    $muteMode.Add_SelectedIndexChanged({
        [IO.File]::WriteAllText($muteModePath, @('none', 'item', 'track', 'both')[$muteMode.SelectedIndex], $utf8)
    })
    $importPositionLabel = New-Object Windows.Forms.Label
    $importPositionLabel.Text = 'Import position'
    $importPositionLabel.SetBounds(16, 192, 130, 26)
    $importPosition = New-Object Windows.Forms.ComboBox
    $importPosition.DropDownStyle = 'DropDownList'
    $importPosition.SetBounds(150, 188, 530, 30)
    $null = $importPosition.Items.Add('Timeline start (1.1.00) - new track')
    $null = $importPosition.Items.Add('Edit cursor when download started - new track')
    $null = $importPosition.Items.Add('End of selected track')
    $importPositionPath = Join-Path $SettingsDir 'import-position.txt'
    $importPosition.SelectedIndex = 1
    if (Test-Path -LiteralPath $importPositionPath) {
        $savedImportPosition = [IO.File]::ReadAllText($importPositionPath, $utf8).Trim()
        if ($savedImportPosition -eq 'start') { $importPosition.SelectedIndex = 0 }
        if ($savedImportPosition -eq 'track_end') { $importPosition.SelectedIndex = 2 }
    }
    $importPosition.Add_SelectedIndexChanged({
        [IO.File]::WriteAllText($importPositionPath, @('start', 'cursor', 'track_end')[$importPosition.SelectedIndex], $utf8)
    })
    $form.Controls.AddRange(@($autoClipboard, $autoContinue, $autoQuality, $muteModeLabel, $muteMode, $importPositionLabel, $importPosition))
    $resizeInputs = {
        $right = $form.ClientSize.Width - 16
        $toolUpdates.Left = $right - $toolUpdates.Width
        $label.Width = 190
        $startTimeLabel.Left = 210
        $startTimeLabel.Width = [Math]::Max(100, $toolUpdates.Left - $startTimeLabel.Left - 8)
        $muteMode.Width = [Math]::Max(100, $right - $muteMode.Left)
        $importPosition.Width = [Math]::Max(100, $right - $importPosition.Left)
        $projectFolderNameBox.Width = [Math]::Max(100, [Math]::Min(354, $right - $projectFolderNameBox.Left))
    }
    $form.Add_Resize($resizeInputs)
    & $resizeInputs
    # All pages live in the same form and keep the same window geometry.
    $linkControls = @($label, $startTimeLabel, $urlBox, $autoContinue, $autoQuality, $autoClipboard, $muteModeLabel, $muteMode, $importPositionLabel, $importPosition, $historyLabel, $list, $clear, $toolUpdates, $folderLabel, $projectFolderNameBox, $folderBox, $browse, $rememberFolder, $secondaryCopy, $secondaryFolderBox, $secondaryBrowse)
    $getStartSeconds = {
        param([string]$Url)
        $match = [regex]::Match($Url, '(?:[?&#](?:t|start)=)([^&#]+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { return 0 }
        $value = [Uri]::UnescapeDataString($match.Groups[1].Value).ToLowerInvariant()
        [long]$seconds = 0
        if ([long]::TryParse($value, [ref]$seconds)) { return [Math]::Max(0, $seconds) }
        if ($value -match '^(\d+):(\d+):(\d+)$') { return [long]$Matches[1] * 3600 + [long]$Matches[2] * 60 + [long]$Matches[3] }
        if ($value -match '^(\d+):(\d+)$') { return [long]$Matches[1] * 60 + [long]$Matches[2] }
        $parts = [regex]::Matches($value, '(\d+)([hms])')
        if (-not $parts.Count) { return 0 }
        foreach ($part in $parts) {
            $amount = [long]$part.Groups[1].Value
            $seconds += $amount * $(switch ($part.Groups[2].Value) { 'h' { 3600 } 'm' { 60 } default { 1 } })
        }
        return $seconds
    }
    $updateStartTime = {
        $seconds = & $getStartSeconds $urlBox.Text.Trim()
        if ($seconds -gt 0) {
            $startTimeLabel.Text = 'Start detected: ' + [TimeSpan]::FromSeconds($seconds).ToString('hh\:mm\:ss')
        } else { $startTimeLabel.Text = '' }
    }
    $urlBox.Add_TextChanged($updateStartTime)
    & $updateStartTime
    $qualityLabel = New-Object Windows.Forms.Label
    $qualityLabel.Text = 'Select quality and codec'
    $qualityLabel.SetBounds(16, 14, 868, 26)
    $qualityLabel.Anchor = 'Top,Left,Right'
    $qualityList = New-Object Windows.Forms.ListBox
    $qualityList.SetBounds(16, 48, 868, 454)
    $qualityList.Anchor = 'Top,Bottom,Left,Right'
    $qualityList.IntegralHeight = $false
    $qualityList.HorizontalScrollbar = $true
    $qualityList.TabIndex = 0
    foreach ($optionLabel in [IO.File]::ReadAllLines((Join-Path $DialogDir 'options.txt'), $utf8)) {
        if ($optionLabel) { $null = $qualityList.Items.Add($optionLabel) }
    }
    $back = New-Object Windows.Forms.Button
    $back.Text = 'Back'
    $back.SetBounds(16, 522, 104, 30)
    $back.Anchor = 'Bottom,Left'
    $optionControls = @($qualityLabel, $qualityList, $back)
    $form.Controls.AddRange($optionControls)
    foreach ($control in $optionControls) { $control.Visible = $false }
    $showOptions = {
        $copyMenu.Close()
        foreach ($control in $linkControls) { $control.Visible = $false }
        foreach ($control in $optionControls) { $control.Visible = $true }
        $uiState.Page = 'options'
        $next.Visible = $false
        $qualityList.Focus()
    }
    $continueFromLink = {
        if ($autoQuality.Checked) {
            $automaticIndex = $qualityList.Items.IndexOf('Best available - Auto')
            if ($automaticIndex -lt 0) {
                [Windows.Forms.MessageBox]::Show($form, 'Automatic quality is unavailable.', $form.Text) | Out-Null
                return
            }
            $qualityList.SelectedIndex = $automaticIndex
            & $showOptions
            & $startDownload
        } else {
            & $showOptions
        }
    }
    $processPastedLink = {
        if (-not $autoContinue.Checked -or $uiState.Page -ne 'link') { return }
        $pastedUrl = $urlBox.Text.Trim()
        $validUrl = $pastedUrl -match '^https?://youtu\.be/[A-Za-z0-9_-]{11}(?:[?&#/].*)?$' -or
            $pastedUrl -match '^https?://(?:(?:www|m|music)\.)?youtube\.com/(?:(?:shorts|live|embed)/[A-Za-z0-9_-]{11}(?:[?&#/].*)?|watch\?(?:[^#]*&)?v=[A-Za-z0-9_-]{11}(?:[&#].*)?)$'
        $validFolder = -not [string]::IsNullOrWhiteSpace($folderBox.Text) -and
            [IO.Path]::IsPathRooted($folderBox.Text) -and $folderBox.Text -notmatch '[\r\n"]'
        $validProjectName = -not $projectFolder -or (& $isValidProjectFolderName $projectFolderNameBox.Text)
        $validSecondary = -not $projectFolder -or -not $secondaryCopy.Checked -or
            (-not [string]::IsNullOrWhiteSpace($secondaryFolderBox.Text) -and [IO.Path]::IsPathRooted($secondaryFolderBox.Text) -and $secondaryFolderBox.Text -notmatch '[\r\n"]')
        if ($validUrl -and $validFolder -and $validProjectName -and $validSecondary) { & $continueFromLink }
    }
    $urlBox.Add_Pasted({
        & $processPastedLink
    })
    $back.Add_Click({
        if ($uiState.Page -eq 'progress') { & $stopDownload }
        foreach ($control in $progressControls) { $control.Visible = $false }
        foreach ($control in $optionControls) { $control.Visible = $false }
        foreach ($control in $linkControls) { $control.Visible = $true }
        $rememberFolder.Visible = -not [bool]$projectFolder
        $projectFolderNameBox.Visible = [bool]$projectFolder
        $secondaryCopy.Visible = [bool]$projectFolder
        $secondaryFolderBox.Visible = [bool]$projectFolder
        $secondaryBrowse.Visible = [bool]$projectFolder
        $uiState.Page = 'link'
        $next.Visible = $true
        $next.Text = 'Continue'
        $next.Enabled = $true
        $cancel.Visible = $true
        $urlBox.Focus()
    })
    $qualityList.Add_SelectedIndexChanged({
        if ($uiState.Page -eq 'options') { $next.Enabled = $qualityList.SelectedIndex -ge 0 }
    })
    $qualityList.Add_MouseClick({ param($sender, $event)
        if ($event.Button -ne [Windows.Forms.MouseButtons]::Left -or $uiState.Page -ne 'options') { return }
        $index = $qualityList.IndexFromPoint($event.Location)
        if ($index -lt 0) { return }
        $qualityList.SelectedIndex = $index
        & $startDownload
    })
    $fileLabel = New-Object Windows.Forms.TextBox
    $fileLabel.Multiline = $true
    $fileLabel.ReadOnly = $true
    $fileLabel.BorderStyle = 'None'
    $fileLabel.BackColor = $form.BackColor
    $fileLabel.Text = 'Reading video information...'
    $fileLabel.SetBounds(16, 20, 868, 84)
    $fileLabel.Anchor = 'Top,Left,Right'
    $stageLabel = New-Object Windows.Forms.Label
    $stageLabel.SetBounds(16, 120, 868, 28)
    $stageLabel.Anchor = 'Top,Left,Right'
    $progressBar = New-Object Windows.Forms.ProgressBar
    $progressBar.SetBounds(16, 158, 868, 24)
    $progressBar.Anchor = 'Top,Left,Right'
    $progressBar.Style = 'Marquee'
    $downloadStats = New-Object Windows.Forms.Label
    $downloadStats.SetBounds(16, 192, 868, 26)
    $downloadStats.Anchor = 'Top,Left,Right'
    $elapsedLabel = New-Object Windows.Forms.Label
    $elapsedLabel.SetBounds(16, 222, 868, 26)
    $elapsedLabel.Anchor = 'Top,Left,Right'
    $resultBox = New-Object Windows.Forms.TextBox
    $resultBox.Multiline = $true
    $resultBox.ReadOnly = $true
    $resultBox.ScrollBars = 'Vertical'
    $resultBox.SetBounds(16, 258, 868, 244)
    $resultBox.Anchor = 'Top,Bottom,Left,Right'
    $closeWhenFinished = New-Object Windows.Forms.CheckBox
    $closeWhenFinished.Text = 'Close when finished'
    $closeWhenFinished.SetBounds(136, 522, 300, 30)
    $closeWhenFinished.AutoSize = $true
    $closeWhenFinished.Anchor = 'Bottom,Left'
    $closeWhenFinishedPath = Join-Path $SettingsDir 'close-when-finished.txt'
    if (Test-Path -LiteralPath $closeWhenFinishedPath) {
        $closeWhenFinished.Checked = [IO.File]::ReadAllText($closeWhenFinishedPath).Trim() -eq '1'
    }
    $closeWhenFinished.Add_CheckedChanged({
        [IO.File]::WriteAllText($closeWhenFinishedPath, [string][int]$closeWhenFinished.Checked, $utf8)
        if ($closeWhenFinished.Checked -and $uiState.Finished -and $uiState.CanAutoClose) { $form.Close() }
    })
    $progressControls = @($fileLabel, $stageLabel, $progressBar, $downloadStats, $elapsedLabel, $resultBox, $closeWhenFinished, $back)
    $form.Controls.AddRange($progressControls)
    foreach ($control in $progressControls) { $control.Visible = $false }
    $showProgress = {
        foreach ($control in $optionControls) { $control.Visible = $false }
        foreach ($control in $progressControls) { $control.Visible = $true }
        $uiState.Page = 'progress'
        $next.Visible = $true
        $uiState.Started = [DateTime]::UtcNow
        $uiState.Finished = $false
        $uiState.CanAutoClose = $false
        $next.Text = 'Close'
        $next.Enabled = $false
        $cancel.Text = 'Cancel'
        $stageLabel.Text = 'Preparing download...'
        $fileLabel.Text = 'Reading video information...'
        $progressBar.Value = 0
        $progressBar.Style = 'Marquee'
        $downloadStats.Text = ''
        $resultBox.Text = 'Back stops the download and returns to settings. Cancel or closing this window stops the download and closes the window.'
    }
    $updateProgress = {
        if ($uiState.Finished) { return }
        $elapsedLabel.Text = 'Elapsed: ' + [int]([DateTime]::UtcNow - $uiState.Started).TotalSeconds + ' s - progress is for the current stage'
        # The files are updated by another process; retry transient read conflicts next tick.
        try {
            $jobPathFile = Join-Path $DialogDir 'job-dir.txt'
            if (Test-Path -LiteralPath $jobPathFile) {
                $jobPath = [IO.File]::ReadAllText($jobPathFile, $utf8)
                if ($jobPath) {
                    $filenamePath = Join-Path $jobPath 'filename.txt'
                    if (Test-Path -LiteralPath $filenamePath) {
                        $names = [IO.File]::ReadAllLines($filenamePath, $utf8)
                        if ($names.Count) { $fileLabel.Text = [IO.Path]::GetFileName($names[-1]) }
                    }
                    $progressPath = Join-Path $jobPath 'progress.txt'
                    if (Test-Path -LiteralPath $progressPath) {
                        $progress = [IO.File]::ReadAllLines($progressPath, $utf8)
                        $downloadStats.Text = if ($progress.Count -ge 3) { $progress[2] } else { '' }
                        [double]$percent = -1
                        if ($progress.Count -ge 2 -and [double]::TryParse($progress[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$percent)) {
                            $stage = $progress[0]
                            if ($stage -eq 'Creating Cover video') {
                                $durationPath = Join-Path $jobPath 'duration.txt'
                                $encodePath = Join-Path $jobPath 'encode-progress.txt'
                                if ((Test-Path -LiteralPath $durationPath) -and (Test-Path -LiteralPath $encodePath)) {
                                    $duration = [double]::Parse([IO.File]::ReadAllText($durationPath), [Globalization.CultureInfo]::InvariantCulture)
                                    $tail = Get-Content -LiteralPath $encodePath -Tail 24
                                    $times = @($tail | Select-String '^out_time_us=(\d+)$')
                                    if ($duration -gt 0 -and $times.Count) { $percent = [Math]::Min(99.0, [double]$times[-1].Matches[0].Groups[1].Value / 1000000 / $duration * 100) }
                                }
                            }
                            if ($percent -ge 0) {
                                $progressBar.Style = 'Continuous'
                                $progressBar.Value = [int][Math]::Min(100.0, [Math]::Max(0.0, $percent))
                                $stageLabel.Text = $stage + (' - {0:0.0}%' -f $percent)
                            } else { $progressBar.Style = 'Marquee'; $stageLabel.Text = $stage + '...' }
                        }
                    }
                }
            }
            $completion = Join-Path $DialogDir 'download-result.txt'
            if (Test-Path -LiteralPath $completion) {
                $value = [IO.File]::ReadAllText($completion, $utf8)
                if ($value) {
                    $resultBox.Text = $value
                    $stageLabel.Text = 'Finished - see details below'
                    $progressBar.Style = 'Continuous'
                    if ($value -like 'Complete*' -or $value -like 'Download complete*') { $progressBar.Value = 100 }
                    $next.Enabled = $true
                    $cancel.Visible = $false
                    $uiState.Finished = $true
                    # Keep errors, warnings and manual-import instructions visible.
                    $uiState.CanAutoClose = $value -match '^Complete - imported into REAPER\.\r?\n[^\r\n]+\r?\n\s*$'
                    if ($closeWhenFinished.Checked -and $uiState.CanAutoClose) { $form.Close() }
                }
            }
        } catch { }
    }
    $null = [IO.Directory]::CreateDirectory($SettingsDir)
    $persistentGeometry = Join-Path $SettingsDir 'main-window.txt'
    $geometryPath = if (Test-Path -LiteralPath $persistentGeometry) { $persistentGeometry } else { Join-Path $DialogDir 'window.txt' }
    if (Test-Path -LiteralPath $geometryPath) {
        $geometry = [IO.File]::ReadAllText($geometryPath, $utf8).Trim()
        if ($geometry -match '^(-?\d+),(-?\d+),(\d+),(\d+),([01])$') {
            $x = [int]$Matches[1]; $y = [int]$Matches[2]
            $w = [Math]::Max($form.MinimumSize.Width, [int]$Matches[3]); $h = [Math]::Max($form.MinimumSize.Height, [int]$Matches[4])
            $maximized = $Matches[5] -eq '1'
            $rect = New-Object Drawing.Rectangle($x, $y, $w, $h)
            $area = [Windows.Forms.Screen]::FromRectangle($rect).WorkingArea
            $w = [Math]::Min($w, $area.Width); $h = [Math]::Min($h, $area.Height)
            $x = [Math]::Max($area.Left, [Math]::Min($x, $area.Right - $w))
            $y = [Math]::Max($area.Top, [Math]::Min($y, $area.Bottom - $h))
            $form.StartPosition = 'Manual'
            $form.SetBounds($x, $y, $w, $h)
            if ($maximized) { $form.WindowState = 'Maximized' }
        }
    }
    $saveWindow = {
        if (-not $form.Visible -or $form.WindowState -eq 'Minimized') { return }
        $bounds = if ($form.WindowState -eq 'Normal') { $form.Bounds } else { $form.RestoreBounds }
        $maximized = if ($form.WindowState -eq 'Maximized') { 1 } else { 0 }
        $value = "{0},{1},{2},{3},{4}" -f $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height, $maximized
        Save-Text 'window-result.txt' $value
        [IO.File]::WriteAllText($persistentGeometry, $value, $utf8)
    }
    $form.Add_ResizeEnd($saveWindow)
    $form.Add_Deactivate($saveWindow)
    $form.Add_FormClosing($saveWindow)
    $stopDownload = {
        if ($uiState.Page -ne 'progress' -or $uiState.Finished) { return }
        if ($uiState.RequestId) { Save-Text ('cancel-' + $uiState.RequestId + '.txt') '1' }
        try {
            $jobPathFile = Join-Path $DialogDir 'job-dir.txt'
            if (-not (Test-Path -LiteralPath $jobPathFile)) { return }
            $jobPath = [IO.File]::ReadAllText($jobPathFile, $utf8).Trim()
            if (-not $jobPath -or -not (Test-Path -LiteralPath $jobPath -PathType Container)) { return }
            # The worker checks this marker at startup; the REAPER poller also stops on it.
            [IO.File]::WriteAllText((Join-Path $jobPath 'cancel.txt'), '1', $utf8)
            $pidFile = Join-Path $jobPath 'worker-pid.txt'
            for ($attempt = 0; $attempt -lt 10 -and -not (Test-Path -LiteralPath $pidFile); $attempt++) {
                Start-Sleep -Milliseconds 100
            }
            if (-not (Test-Path -LiteralPath $pidFile)) { return }
            $identity = [IO.File]::ReadAllLines($pidFile, $utf8)
            [int]$workerProcessId = 0
            [long]$workerStarted = 0
            if ($identity.Count -lt 2 -or
                -not [int]::TryParse($identity[0], [ref]$workerProcessId) -or
                -not [long]::TryParse($identity[1], [ref]$workerStarted)) { return }
            $workerProcess = Get-Process -Id $workerProcessId -ErrorAction SilentlyContinue
            if ($workerProcess -and $workerProcess.StartTime.ToUniversalTime().Ticks -eq $workerStarted) {
                $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                $null = Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$workerProcessId, '/T', '/F') -Wait -PassThru -WindowStyle Hidden
            }
        } catch { }
    }
    $form.Add_FormClosing({ & $stopDownload })
    $form.Add_Shown({
        $form.Activate()
        if ($autoClipboard.Checked) {
            try {
                if ([Windows.Forms.Clipboard]::ContainsText()) {
                    $clipboardText = [Windows.Forms.Clipboard]::GetText().Trim()
                    $clipboardIsYoutube = $clipboardText -match '^https?://youtu\.be/[A-Za-z0-9_-]{11}(?:[?&#/].*)?$' -or
                        $clipboardText -match '^https?://(?:(?:www|m|music)\.)?youtube\.com/(?:(?:shorts|live|embed)/[A-Za-z0-9_-]{11}(?:[?&#/].*)?|watch\?(?:[^#]*&)?v=[A-Za-z0-9_-]{11}(?:[&#].*)?)$'
                    if ($clipboardIsYoutube) {
                        $urlBox.Text = $clipboardText
                        & $processPastedLink
                    }
                }
            } catch { }
        }
        if ($uiState.Page -eq 'link') { $urlBox.Focus() }
    })
    $answer = $form.ShowDialog()
    $timer.Stop()
    $timer.Dispose()
    foreach ($lookup in $lookups) { $lookup.Pipe.Stop(); $lookup.Pipe.Dispose() }
    Save-Text 'removed.txt' ($removed -join "`n")
    $titleLines = foreach ($row in $list.Rows) {
        $value = [string]$row.Cells[0].Value
        if ($value -and $value -notin @('Loading title...', 'Title unavailable')) {
            ([string]$row.Cells[1].Value) + "`t" + ($value -replace '[\r\n\t]', ' ')
        }
    }
    Save-Text 'titles.txt' ($titleLines -join "`n")
    if ($projectFolder -and (& $isValidProjectFolderName $projectFolderNameBox.Text)) {
        [IO.File]::WriteAllText($projectFolderNamePreference, $projectFolderNameBox.Text.Trim(), $utf8)
    }
    if ($answer -eq [Windows.Forms.DialogResult]::OK) {
        Save-Text 'option.txt' ([string]($qualityList.SelectedIndex + 1))
        Save-Text 'url.txt' $urlBox.Text.Trim()
        Save-Text 'folder.txt' $folderBox.Text.Trim()
        if ($rememberFolder.Checked -and -not $projectFolder) { Save-Text 'remember-folder.txt' $folderBox.Text.Trim() }
        Save-Text 'done.txt' 'OK'
    } else { Save-Text 'done.txt' 'CANCEL' }
    $form.Dispose()
    $copyMenu.Dispose()
} catch {
    Save-Text 'error.txt' $_.Exception.Message
    Save-Text 'done.txt' 'ERROR'
    exit 1
} finally {
    if ($ownsMutex) { $dialogMutex.ReleaseMutex() }
    if ($dialogMutex) { $dialogMutex.Dispose() }
}
