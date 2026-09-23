# LeLeVC_YouTube Downloader 1.0 - original author: LeLeVC
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [switch]$Update
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

function Test-RequiredTool([string]$Name) {
    $local = Join-Path $InstallDir ($Name + '.exe')
    return (Test-Path -LiteralPath $local -PathType Leaf) -or [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}
function Get-MissingTools {
    @('yt-dlp', 'ffmpeg', 'ffprobe', 'deno') | Where-Object { -not (Test-RequiredTool $_) }
}
function Get-ToolVersion([string]$Name) {
    $local = Join-Path $InstallDir ($Name + '.exe')
    $command = if (Test-Path -LiteralPath $local -PathType Leaf) { $local } else { (Get-Command $Name -ErrorAction SilentlyContinue).Source }
    if (-not $command) { return 'missing' }
    try {
        $lines = if ($Name -in @('ffmpeg', 'ffprobe')) { & $command -version 2>$null } else { & $command --version 2>$null }
        $first = @($lines)[0]
        if ($Name -eq 'deno' -and $first -match '^deno\s+([^\s]+)') { return $Matches[1] }
        if ($Name -in @('ffmpeg', 'ffprobe') -and $first -match '^\S+ version\s+([^\s]+)') { return $Matches[1] }
        return ([string]$first).Trim()
    } catch { return 'unknown' }
}
function Get-ExpectedHash([string]$Text, [string]$FileName) {
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match ('(?i)^\s*([a-f0-9]{64})\s+\*?' + [regex]::Escape($FileName) + '\s*$')) { return $Matches[1].ToLowerInvariant() }
    }
    if ($Text -match '(?i)\b([a-f0-9]{64})\b') { return $Matches[1].ToLowerInvariant() }
    throw "No SHA-256 checksum found for $FileName."
}
function Confirm-Hash([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected.ToLowerInvariant()) { throw "Checksum verification failed for $([IO.Path]::GetFileName($Path))." }
}

$form = New-Object Windows.Forms.Form
$form.Text = if ($Update) { 'LeLeVC_YouTube Downloader - Tool updates' } else { 'LeLeVC_YouTube Downloader - Required tools' }
$form.ClientSize = New-Object Drawing.Size(680, 430)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$heading = New-Object Windows.Forms.Label
$heading.Text = if ($Update) { 'Update tools' } else { 'Required tools are missing' }
$heading.Font = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
$heading.SetBounds(18, 16, 640, 32)
$description = New-Object Windows.Forms.Label
$description.Text = if ($Update) {
    "Select tools to update. Updating yt-dlp is the recommended first step`r`nwhen downloads from YouTube stop working."
} else {
    "The downloader needs yt-dlp, FFmpeg/FFprobe and Deno.`r`nThey will be downloaded directly from their official release locations."
}
$description.SetBounds(18, 58, 640, 52)
$selection = New-Object Windows.Forms.CheckedListBox
$selection.SetBounds(18, 112, 644, 70)
$selection.CheckOnClick = $true
$selection.HorizontalScrollbar = $true
$null = $selection.Items.Add('yt-dlp - waiting for version check')
$null = $selection.Items.Add('Deno - waiting for version check')
$null = $selection.Items.Add('FFmpeg / FFprobe - waiting for version check')
$licenseInfo = New-Object Windows.Forms.TextBox
$licenseInfo.Multiline = $true
$licenseInfo.ReadOnly = $true
$licenseInfo.ScrollBars = 'Vertical'
$licenseInfo.SetBounds(18, 190, 644, 106)
$licenseInfo.Text = @"
Sources and licenses:
yt-dlp: official GitHub releases; standalone Windows build is GPLv3+.
https://github.com/yt-dlp/yt-dlp

FFmpeg/FFprobe: release essentials build linked by ffmpeg.org; GPLv3.
https://www.gyan.dev/ffmpeg/builds/

Deno: official GitHub releases; MIT license.
https://github.com/denoland/deno
"@
$status = New-Object Windows.Forms.Label
$status.Text = 'Ready to download.'
$status.SetBounds(18, 308, 644, 26)
$progress = New-Object Windows.Forms.ProgressBar
$progress.SetBounds(18, 338, 644, 24)
$progress.Minimum = 0; $progress.Maximum = 100
$download = New-Object Windows.Forms.Button
$download.Text = if ($Update) { 'Update selected tools' } else { 'Download required tools' }
$download.SetBounds(350, 380, 200, 34)
$checkAgain = New-Object Windows.Forms.Button
$checkAgain.Text = 'Check again'
$checkAgain.SetBounds(18, 380, 130, 34)
$checkAgain.Visible = [bool]$Update
$cancel = New-Object Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.SetBounds(558, 380, 104, 34)
$cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $cancel
$form.Controls.AddRange(@($heading, $description, $selection, $licenseInfo, $status, $progress, $checkAgain, $download, $cancel))

$missing = @(Get-MissingTools)
if ($Update) {
    $selection.SetItemChecked(0, $false)
} else {
    $selection.Items[0] = 'yt-dlp (installed: ' + (Get-ToolVersion 'yt-dlp') + ')'
    $selection.Items[1] = 'Deno (installed: ' + (Get-ToolVersion 'deno') + ')'
    $selection.Items[2] = 'FFmpeg / FFprobe (installed: ' + (Get-ToolVersion 'ffmpeg') + ')'
    $selection.SetItemChecked(0, $missing -contains 'yt-dlp')
    $selection.SetItemChecked(1, $missing -contains 'deno')
    $selection.SetItemChecked(2, ($missing -contains 'ffmpeg') -or ($missing -contains 'ffprobe'))
    $selection.Enabled = $false
}
$checkUpdates = {
    $checkAgain.Enabled = $false
    $download.Enabled = $false
    $checkAgain.Enabled = $false
    $status.Text = 'Checking current tool versions...'
    $progress.Style = 'Marquee'
    [Windows.Forms.Application]::DoEvents()
    $webCheck = New-Object Net.WebClient
    $webCheck.Headers['User-Agent'] = 'LeLeVC-YouTube-Downloader'
    try {
        $queries = @(
            @{ Name = 'yt-dlp'; Display = 'yt-dlp'; Url = 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'; Json = $true },
            @{ Name = 'deno'; Display = 'Deno'; Url = 'https://dl.deno.land/release-latest.txt'; Json = $false },
            @{ Name = 'ffmpeg'; Display = 'FFmpeg / FFprobe'; Url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.ver'; Json = $false }
        )
        $failed = 0
        for ($i = 0; $i -lt $queries.Count; $i++) {
            $query = $queries[$i]
            $installed = Get-ToolVersion $query.Name
            $latest = $null
            $toolStatus = 'Unable to check'
            try {
                $task = $webCheck.DownloadStringTaskAsync([Uri]$query.Url)
                while (-not $task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
                if ($task.IsFaulted) { throw $task.Exception.GetBaseException() }
                if ($query.Json) { $latest = ($task.Result | ConvertFrom-Json).tag_name.Trim() }
                else { $latest = $task.Result.Trim() }
                $latest = ($latest -replace '^v', '').Trim()
                if (-not $latest) { throw 'Empty version response.' }
                $installedComparable = ($installed -replace '^v', '').Trim()
                $isCurrent = $installedComparable -eq $latest -or $installedComparable -match ('^' + [regex]::Escape($latest) + '(?:[-+]|$)')
                if ($installed -eq 'missing') { $toolStatus = 'Update available' }
                elseif ($installed -eq 'unknown') { $toolStatus = 'Unable to check' }
                elseif ($isCurrent) { $toolStatus = 'Up to date' }
                else { $toolStatus = 'Update available' }
            } catch { $failed++; $toolStatus = 'Unable to check' }
            $latestDisplay = if ($latest) { $latest } else { 'unavailable' }
            $selection.Items[$i] = "$($query.Display) | installed: $installed | latest: $latestDisplay | $toolStatus"
            $selection.SetItemChecked($i, $toolStatus -eq 'Update available')
            [Windows.Forms.Application]::DoEvents()
        }
        $status.Text = if ($failed) { 'Version check finished. Some online information was unavailable.' } else { 'Version check finished.' }
    } finally {
        $webCheck.Dispose()
        $progress.Style = 'Blocks'
        $progress.Value = 0
        $download.Enabled = $true
        $checkAgain.Enabled = $true
    }
}
$checkAgain.Add_Click({ & $checkUpdates })
$form.Add_Shown({ if ($Update) { & $checkUpdates } })
$download.Add_Click({
    $updateYtDlp = $selection.GetItemChecked(0)
    $updateDeno = $selection.GetItemChecked(1)
    $updateFfmpeg = $selection.GetItemChecked(2)
    if (-not $updateYtDlp -and -not $updateDeno -and -not $updateFfmpeg) {
        $status.Text = 'Select at least one tool.'
        return
    }
    $download.Enabled = $false
    $checkAgain.Enabled = $false
    $cancel.Enabled = $false
    $form.ControlBox = $false
    $work = Join-Path ([IO.Path]::GetTempPath()) ('REAPER-YT-tools-' + [guid]::NewGuid().ToString('N'))
    try {
        $null = [IO.Directory]::CreateDirectory($work)
        $null = [IO.Directory]::CreateDirectory($InstallDir)
        $licenses = Join-Path $InstallDir 'licenses'
        $null = [IO.Directory]::CreateDirectory($licenses)
        $web = New-Object Net.WebClient
        $web.Headers['User-Agent'] = 'LeLeVC-YouTube-Downloader'
        # Pump events only in the download wait loop. Pumping inside this callback
        # can recursively dispatch progress events until PowerShell's stack overflows.
        $web.add_DownloadProgressChanged({ param($sender, $event) $progress.Value = $event.ProgressPercentage })
        $downloadFile = {
            param([string]$Label, [string]$Url, [string]$Path)
            $status.Text = 'Downloading ' + $Label + '...'
            $progress.Value = 0
            $task = $web.DownloadFileTaskAsync([Uri]$Url, $Path)
            while (-not $task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
            if ($task.IsFaulted) { throw $task.Exception.GetBaseException() }
        }
        $downloadText = {
            param([string]$Url)
            $task = $web.DownloadStringTaskAsync([Uri]$Url)
            while (-not $task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
            if ($task.IsFaulted) { throw $task.Exception.GetBaseException() }
            return $task.Result
        }

        if ($updateYtDlp) {
            $file = Join-Path $work 'yt-dlp.exe'
            & $downloadFile 'yt-dlp' 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' $file
            $sums = & $downloadText 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS'
            Confirm-Hash $file (Get-ExpectedHash $sums 'yt-dlp.exe')
            [IO.File]::WriteAllText((Join-Path $licenses 'yt-dlp-LICENSE.txt'), (& $downloadText 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/LICENSE'), $utf8)
            [IO.File]::WriteAllText((Join-Path $licenses 'yt-dlp-THIRD_PARTY_LICENSES.txt'), (& $downloadText 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/THIRD_PARTY_LICENSES.txt'), $utf8)
            Copy-Item -LiteralPath $file -Destination (Join-Path $InstallDir 'yt-dlp.exe') -Force
        }

        if ($updateDeno) {
            $archive = Join-Path $work 'deno.zip'
            $denoName = 'deno-x86_64-pc-windows-msvc.zip'
            & $downloadFile 'Deno' ('https://github.com/denoland/deno/releases/latest/download/' + $denoName) $archive
            $sumText = & $downloadText ('https://github.com/denoland/deno/releases/latest/download/' + $denoName + '.sha256sum')
            Confirm-Hash $archive (Get-ExpectedHash $sumText $denoName)
            $expanded = Join-Path $work 'deno'
            Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
            [IO.File]::WriteAllText((Join-Path $licenses 'Deno-LICENSE.md'), (& $downloadText 'https://raw.githubusercontent.com/denoland/deno/main/LICENSE.md'), $utf8)
            Copy-Item -LiteralPath (Join-Path $expanded 'deno.exe') -Destination (Join-Path $InstallDir 'deno.exe') -Force
        }

        if ($updateFfmpeg) {
            $archive = Join-Path $work 'ffmpeg-release-essentials.zip'
            $archiveName = 'ffmpeg-release-essentials.zip'
            & $downloadFile 'FFmpeg' 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $archive
            $sumText = & $downloadText 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256'
            Confirm-Hash $archive (Get-ExpectedHash $sumText $archiveName)
            $expanded = Join-Path $work 'ffmpeg'
            Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
            $ffmpeg = Get-ChildItem -LiteralPath $expanded -Filter ffmpeg.exe -Recurse | Select-Object -First 1
            $ffprobe = Get-ChildItem -LiteralPath $expanded -Filter ffprobe.exe -Recurse | Select-Object -First 1
            if (-not $ffmpeg -or -not $ffprobe) { throw 'FFmpeg archive does not contain the required executables.' }
            Copy-Item -LiteralPath $ffmpeg.FullName -Destination (Join-Path $InstallDir 'ffmpeg.exe') -Force
            Copy-Item -LiteralPath $ffprobe.FullName -Destination (Join-Path $InstallDir 'ffprobe.exe') -Force
            $ffLicenseDir = Join-Path $licenses 'ffmpeg'
            $null = [IO.Directory]::CreateDirectory($ffLicenseDir)
            Get-ChildItem -LiteralPath $expanded -File -Recurse | Where-Object { $_.Name -match '^(LICENSE|COPYING|README)' } | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $ffLicenseDir $_.Name) -Force
            }
            [IO.File]::WriteAllText((Join-Path $ffLicenseDir 'SOURCE.txt'), "Binary and checksum: https://www.gyan.dev/ffmpeg/builds/`r`nSource project: https://ffmpeg.org/download.html", $utf8)
        }

        $stillMissing = @(Get-MissingTools)
        if ($stillMissing.Count) { throw ('Installation incomplete. Missing: ' + ($stillMissing -join ', ')) }
        $notice = @"
These tools were downloaded directly from their upstream release locations:
yt-dlp: https://github.com/yt-dlp/yt-dlp
FFmpeg: https://www.gyan.dev/ffmpeg/builds/
Deno: https://github.com/denoland/deno

License texts are stored in the licenses folder.
"@
        [IO.File]::WriteAllText((Join-Path $licenses 'THIRD-PARTY-NOTICES.txt'), $notice, $utf8)
        $status.Text = 'Installation complete.'
        $progress.Value = 100
        [Windows.Forms.Application]::DoEvents()
        $form.DialogResult = [Windows.Forms.DialogResult]::OK
        $form.Close()
    } catch {
        $status.Text = 'Installation failed: ' + $_.Exception.Message
        $progress.Value = 0
        $download.Enabled = $true
        $checkAgain.Enabled = $true
        $cancel.Enabled = $true
        $form.ControlBox = $true
    } finally {
        if ($web) { $web.Dispose() }
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
})

$answer = $form.ShowDialog()
$form.Dispose()
if ($answer -eq [Windows.Forms.DialogResult]::OK) { exit 0 }
exit 2
