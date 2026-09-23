# LeLeVC_YouTube Downloader 1.0 - original author: LeLeVC
param([Parameter(Mandatory = $true)][string]$JobDir, [string]$CancelFile = '')
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-JobText([string]$Name, [string]$Value) {
    [IO.File]::WriteAllText((Join-Path $JobDir $Name), $Value, $utf8)
}
$workerStarted = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
Write-JobText 'worker-pid.txt' ("$PID`n$workerStarted")
if ((Test-Path -LiteralPath (Join-Path $JobDir 'cancel.txt')) -or ($CancelFile -and (Test-Path -LiteralPath $CancelFile))) { exit 0 }
function Set-Progress([string]$Stage, [double]$Percent = -1, [string]$Details = '') {
    # Progress is advisory: a concurrent read must never abort the download.
    try { Write-JobText 'progress.txt' ($Stage + "`n" + $Percent.ToString([Globalization.CultureInfo]::InvariantCulture) + "`n" + $Details) } catch { }
}
function Format-ByteCount([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:0.##} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:0.##} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:0.##} KB' -f ($Bytes / 1KB)) }
    return ('{0:0} B' -f $Bytes)
}
function Update-DownloadProgress([string]$Line) {
    if ($Line -match '^REAPER_PROGRESS\|([^|]+)\|\s*([0-9.]+)%\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)$') {
        $stage = if ($Matches[1] -eq 'none') { 'Downloading audio' } else { 'Downloading video' }
        $percent = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        $values = @($Matches[3], $Matches[4], $Matches[5], $Matches[6])
        $numbers = foreach ($value in $values) {
            [double]$number = 0
            if ([double]::TryParse($value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { $number } else { 0 }
        }
        $downloaded = $numbers[0]
        $total = if ($numbers[1] -gt 0) { $numbers[1] } else { $numbers[2] }
        $speed = $numbers[3]
        $details = if ($downloaded -gt 0) {
            'Downloaded ' + (Format-ByteCount $downloaded) + $(if ($total -gt 0) { ' / ' + $(if ($numbers[1] -le 0) { '~' } else { '' }) + (Format-ByteCount $total) } else { '' })
        } else { '' }
        if ($speed -gt 0) { $details += $(if ($details) { '  |  ' } else { '' }) + 'Speed ' + (Format-ByteCount $speed) + '/s' }
        Set-Progress $stage ([Math]::Min(100.0, [Math]::Max(0.0, $percent))) $details
    } elseif ($Line -match '^REAPER_STAGE\|') {
        Set-Progress 'Processing / merging media'
    } elseif ($Line -match '^\[info\].*Downloading .*time ranges?:') {
        Set-Progress 'Downloading selected section'
    } elseif ($Line -match '\btime=(\d+):(\d+):(\d+(?:\.\d+)?)') {
        # Section downloads are handled by FFmpeg. Audio progress lines have no
        # frame= field, so read the output time directly for both media types.
        try {
            $elapsed = [double]$Matches[1] * 3600 + [double]$Matches[2] * 60 +
                [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
            $durationPath = Join-Path $JobDir 'source-duration.txt'
            [double]$sourceDuration = 0
            if ((Test-Path -LiteralPath $durationPath) -and
                [double]::TryParse(([IO.File]::ReadAllText($durationPath, $utf8).Trim()), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$sourceDuration)) {
                $sectionDuration = $sourceDuration - $script:DownloadStartSeconds
                $details = @()
                if ($Line -match 'size=\s*(\d+)KiB') {
                    $details += 'Output ' + (Format-ByteCount ([double]$Matches[1] * 1KB))
                }
                if ($Line -match 'speed=\s*([0-9.]+)x') {
                    $details += 'Processing speed ' + $Matches[1] + 'x realtime'
                }
                if ($sectionDuration -gt 0) {
                    Set-Progress 'Downloading selected section' ([Math]::Min(99.0, $elapsed / $sectionDuration * 100.0)) ($details -join '  |  ')
                } else { Set-Progress 'Downloading selected section' -1 ($details -join '  |  ') }
            } else { Set-Progress 'Downloading selected section' }
        } catch { Set-Progress 'Downloading selected section' }
    }
}
function Invoke-Download([string]$Executable, [string[]]$Arguments) {
    Set-Progress 'Connecting to YouTube'
    $writer = New-Object IO.StreamWriter((Join-Path $JobDir 'download.log'), $false, $utf8)
    try {
        & $Executable @Arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $writer.WriteLine($line)
            $writer.Flush()
            Update-DownloadProgress $line
        }
        $code = $LASTEXITCODE
    } finally { $writer.Dispose() }
    Set-Progress 'Finishing download'
    return $code
}
function Find-Tool([string]$Name) {
    $local = Join-Path $PSScriptRoot "tools\$Name.exe"
    if (Test-Path -LiteralPath $local) { return $local }
    $command = Get-Command "$Name.exe" -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Brak $Name.exe. Umiesc go w folderze tools obok skryptu. Patrz README.md."
}
function Add-Warning([string]$Value) {
    $warningPath = Join-Path $JobDir 'warning.txt'
    $existing = if (Test-Path -LiteralPath $warningPath) { [IO.File]::ReadAllText($warningPath, $utf8).Trim() } else { '' }
    Write-JobText 'warning.txt' (($existing, $Value | Where-Object { $_ }) -join "`n")
}
function Copy-Secondary([string]$File, [string]$Destination, [string]$PrimaryDestination) {
    if ([string]::IsNullOrWhiteSpace($Destination)) { return }
    if (-not [IO.Path]::IsPathRooted($Destination) -or $Destination -match '[\r\n"]') {
        throw 'Nieprawidlowa sciezka dodatkowej kopii.'
    }
    $secondaryFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
    $primaryFull = [IO.Path]::GetFullPath($PrimaryDestination).TrimEnd('\', '/')
    if ($secondaryFull.Equals($primaryFull, [StringComparison]::OrdinalIgnoreCase)) { return }
    Set-Progress 'Saving additional copy'
    try {
        $null = [IO.Directory]::CreateDirectory($secondaryFull)
        Copy-Item -LiteralPath $File -Destination (Join-Path $secondaryFull ([IO.Path]::GetFileName($File))) -Force -ErrorAction Stop
    } catch {
        Add-Warning ('Film zostal pobrany, ale nie udalo sie zapisac dodatkowej kopii w: ' + $secondaryFull)
    }
}
function Get-VideoFormat([string]$Quality, [string]$Codec) {
    if ($Quality -notin @('360', '480', '720', '1080', '1440', '2160', 'best')) {
        throw 'Nieprawidlowa jakosc wideo.'
    }
    $codecFilter = switch ($Codec) {
        'auto' { '' }
        'av1' { '[vcodec^=av01]' }
        'vp9' { '[vcodec^=vp9]' }
        'h264' { '[vcodec^=avc1]' }
        default { throw 'Nieprawidlowy kodek wideo.' }
    }
    $heightFilter = ''
    if ($Quality -ne 'best') { $heightFilter = "[height<=$Quality]" }
    # Both alternatives honor the chosen codec and resolution limit. Keep AAC audio.
    return "bv$codecFilter$heightFilter+ba[acodec^=mp4a]/b$codecFilter$heightFilter[acodec^=mp4a]"
}
function New-StillVideo([string]$Audio, [string]$Thumbnail, [string]$Destination, [string]$Encoder, [string]$Probe) {
    if (-not (Test-Path -LiteralPath $Thumbnail -PathType Leaf)) {
        throw 'Nie znaleziono miniatury filmu. Nie mozna utworzyc statycznego wideo.'
    }
    $imageJson = & $Probe -v error -select_streams v:0 -show_entries stream=width,height -of json $Thumbnail 2> (Join-Path $JobDir 'image-probe.log')
    if ($LASTEXITCODE -ne 0) { throw 'Nie mozna odczytac miniatury.' }
    $dimensions = ($imageJson -join "`n" | ConvertFrom-Json).streams | Select-Object -First 1
    if ($dimensions.width -le 0 -or $dimensions.height -le 0) { throw 'Nieprawidlowe wymiary miniatury.' }
    # Cover always uses the fixed 360p video resolution.
    $width = 640
    $height = 360
    $name = [IO.Path]::GetFileNameWithoutExtension($Audio)
    $outputFile = Join-Path $Destination "$name [${height}p] [H.264] [static].mp4"
    Write-JobText 'filename.txt' $outputFile
    if (Test-Path -LiteralPath $outputFile -PathType Leaf) { return $outputFile }
    $audioCodec = & $Probe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $Audio 2> (Join-Path $JobDir 'audio-probe.log')
    if ($LASTEXITCODE -ne 0 -or -not $audioCodec) { throw 'Nie mozna odczytac sciezki dzwiekowej.' }
    # Preserve the original audio packets for every codec; never encode audio.
    $audioArgs = @('-c:a', 'copy')
    # Encode into the job directory; publish only after successful completion.
    $temporaryVideo = Join-Path $JobDir 'still-output.mp4'
    $duration = & $Probe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $Audio 2> (Join-Path $JobDir 'duration-probe.log')
    if ($LASTEXITCODE -eq 0) { Write-JobText 'duration.txt' (($duration -join '').Trim()) }
    Set-Progress 'Creating Cover video'
    & $Encoder -hide_banner -loglevel error -nostdin -n -progress (Join-Path $JobDir 'encode-progress.txt') -nostats -loop 1 -framerate 1 -i $Thumbnail -i $Audio -map 0:v:0 -map 1:a:0 -vf "scale=${width}:${height},setsar=1" -c:v libx264 -preset veryfast -tune stillimage -crf 20 -pix_fmt yuv420p @audioArgs -shortest -movflags +faststart $temporaryVideo 2> (Join-Path $JobDir 'encode.log')
    if ($LASTEXITCODE -ne 0) { throw 'Nie mozna utworzyc Cover z oryginalnym dzwiekiem. Dzwiek nie zostal przekodowany. Szczegoly w encode.log.' }
    Move-Item -LiteralPath $temporaryVideo -Destination $outputFile -ErrorAction Stop
    return $outputFile
}
function New-AudioOutput([string]$Audio, [string]$Destination, [string]$Mode, [string]$StartSuffix, [string]$Encoder, [string]$Probe) {
    $audioJson = & $Probe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate -of json $Audio 2> (Join-Path $JobDir 'audio-output-probe.log')
    if ($LASTEXITCODE -ne 0) { throw 'Nie mozna odczytac pobranej sciezki dzwiekowej.' }
    $audioInfo = ($audioJson -join "`n" | ConvertFrom-Json).streams | Select-Object -First 1
    [int]$sampleRate = 0
    if (-not $audioInfo -or -not [int]::TryParse([string]$audioInfo.sample_rate, [ref]$sampleRate) -or $sampleRate -le 0) {
        throw 'Nie mozna odczytac czestotliwosci probkowania dzwieku.'
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($Audio)
    $rateNumber = ([double]$sampleRate / 1000).ToString('0.#', [Globalization.CultureInfo]::InvariantCulture)
    $rateLabel = $rateNumber + 'kHz'
    if ($Mode -eq 'audio_original') {
        $codecLabel = switch ([string]$audioInfo.codec_name) {
            'aac' { 'AAC' }
            'opus' { 'Opus' }
            'vorbis' { 'Vorbis' }
            'mp3' { 'MP3' }
            default { ([string]$audioInfo.codec_name).ToUpperInvariant() }
        }
        if (-not $codecLabel) { $codecLabel = 'audio' }
        $extension = [IO.Path]::GetExtension($Audio)
        $outputFile = Join-Path $Destination ($name + ' [audio] [' + $codecLabel + ']' + $StartSuffix + $extension)
        Write-JobText 'filename.txt' $outputFile
        if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf)) {
            Move-Item -LiteralPath $Audio -Destination $outputFile -ErrorAction Stop
        }
        return $outputFile
    }
    $isWave = $Mode -eq 'audio_wav'
    $formatLabel = if ($isWave) { 'PCM 24-bit' } else { 'FLAC 24-bit' }
    $extension = if ($isWave) { '.wav' } else { '.flac' }
    $outputFile = Join-Path $Destination ($name + ' [audio] [' + $formatLabel + '] [' + $rateLabel + ']' + $StartSuffix + $extension)
    Write-JobText 'filename.txt' $outputFile
    if (Test-Path -LiteralPath $outputFile -PathType Leaf) { return $outputFile }
    $temporaryOutput = Join-Path $JobDir ('audio-output' + $extension)
    Set-Progress $(if ($isWave) { 'Converting audio to WAV' } else { 'Converting audio to FLAC' })
    if ($isWave) {
        & $Encoder -hide_banner -loglevel error -nostdin -n -i $Audio -map 0:a:0 -vn -c:a pcm_s24le $temporaryOutput 2> (Join-Path $JobDir 'audio-convert.log')
    } else {
        & $Encoder -hide_banner -loglevel error -nostdin -n -i $Audio -map 0:a:0 -vn -c:a flac -sample_fmt s32 -bits_per_raw_sample 24 -compression_level 8 $temporaryOutput 2> (Join-Path $JobDir 'audio-convert.log')
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryOutput -PathType Leaf)) {
        throw 'Nie mozna utworzyc wybranego pliku audio. Szczegoly w audio-convert.log.'
    }
    Move-Item -LiteralPath $temporaryOutput -Destination $outputFile -ErrorAction Stop
    return $outputFile
}
function Write-QualityReport([string]$File, [string]$Probe, [string]$Requested) {
    # Read the actual file, including previously downloaded files reused by yt-dlp.
    try {
        $heightText = & $Probe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 $File 2> (Join-Path $JobDir 'probe.log')
        $probeExit = $LASTEXITCODE
        $height = 0
        if ($probeExit -ne 0 -or -not [int]::TryParse(($heightText -join '').Trim(), [ref]$height) -or $height -le 0) {
            throw 'Nie mozna odczytac wysokosci obrazu.'
        }
        Write-JobText 'actual-height.txt' ([string]$height)
        if ($Requested -ne 'best' -and $height -ne [int]$Requested) {
            Write-JobText 'warning.txt' ("Uwaga: pobrano inna jakosc niz wybrana.`n`nWybrano: ${Requested}p`nPobrano: ${height}p`n`nWybrana rozdzielczosc moze nie byc dostepna dla tego filmu lub wybranego kodeka. Mozesz sprobowac kodeka Automatyczny.`n`nPobrany plik zostanie uzyty do importu.")
        }
    } catch {
        Write-JobText 'warning.txt' "Film zostal pobrany, ale nie udalo sie sprawdzic jego rzeczywistej rozdzielczosci. Szczegoly w probe.log."
    }
}
try {
    Write-JobText 'started.txt' '1'
    Set-Progress 'Preparing download'
    $request = [IO.File]::ReadAllLines((Join-Path $JobDir 'request.txt'), $utf8)
    if ($request.Count -lt 2 -or $request.Count -gt 7 -or $request[0] -notmatch '^https://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{11}$') {
        throw 'Nieprawidlowe zadanie pobierania.'
    }
    $url = $request[0]
    $destination = $request[1]
    $quality = 'best'
    if ($request.Count -ge 3) { $quality = $request[2] }
    $codec = 'h264' # Compatibility with requests from versions before 1.3.
    if ($request.Count -ge 4) { $codec = $request[3] }
    $mode = 'video'
    if ($request.Count -ge 5) { $mode = $request[4] }
    $secondaryDestination = ''
    if ($request.Count -ge 6) { $secondaryDestination = $request[5] }
    [long]$startSeconds = 0
    if ($request.Count -ge 7 -and -not [long]::TryParse($request[6], [ref]$startSeconds)) { throw 'Nieprawidlowy czas rozpoczecia.' }
    if ($startSeconds -lt 0 -or $startSeconds -gt 315576000) { throw 'Nieprawidlowy czas rozpoczecia.' }
    $sectionArguments = @()
    $startSuffix = ''
    if ($startSeconds -gt 0) {
        $sectionArguments = @('--download-sections', ('*' + $startSeconds + '-inf'))
        $span = [TimeSpan]::FromSeconds($startSeconds)
        $startSuffix = ' [from {0:00}h{1:00}m{2:00}s]' -f [Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
    }
    $script:DownloadStartSeconds = $startSeconds
    if ($mode -notin @('video', 'still', 'audio_original', 'audio_wav', 'audio_flac')) { throw 'Nieprawidlowy tryb pobierania.' }
    $format = Get-VideoFormat $quality $codec
    $yt = Find-Tool 'yt-dlp'
    $ffmpeg = Find-Tool 'ffmpeg'
    $ffprobe = Find-Tool 'ffprobe'
    $deno = Find-Tool 'deno'
    $null = [IO.Directory]::CreateDirectory($destination)
    $result = Join-Path $JobDir 'result.txt'
    if ($mode -in @('audio_original', 'audio_wav', 'audio_flac')) {
        $mediaDir = Join-Path $JobDir 'audio-media'
        $null = [IO.Directory]::CreateDirectory($mediaDir)
        $audioResult = Join-Path $JobDir 'audio-path.txt'
        $audioArguments = @(
            '--ignore-config', '--no-playlist', '--no-overwrites', '--newline', '--progress',
            '--progress-template', 'download:REAPER_PROGRESS|%(info.vcodec)s|%(progress._percent_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s',
            '--progress-template', 'postprocess:REAPER_STAGE|processing',
            '--windows-filenames', '--encoding', 'utf-8',
            '--socket-timeout', '30', '--retries', '3', '--fragment-retries', '3',
            '--match-filters', '!is_live', '--ffmpeg-location', (Split-Path -Parent $ffmpeg),
            '--js-runtimes', "deno:$deno", '-f', 'ba'
        ) + $sectionArguments + @(
            '-P', $mediaDir, '-o', '%(title)s.%(ext)s',
            '--print-to-file', 'before_dl:%(duration)s', (Join-Path $JobDir 'source-duration.txt'),
            '--print-to-file', 'after_move:%(title)s', (Join-Path $JobDir 'title.txt'),
            '--print-to-file', 'after_move:filepath', $audioResult, '--', $url
        )
        $ErrorActionPreference = 'Continue'
        $exitCode = Invoke-Download $yt $audioArguments
        $ErrorActionPreference = 'Stop'
        if ($exitCode -ne 0) { throw 'Blad pobierania dzwieku. Szczegoly w download.log.' }
        if (-not (Test-Path -LiteralPath $audioResult -PathType Leaf)) { throw 'Brak sciezki pobranego dzwieku.' }
        $audioPath = [IO.File]::ReadAllText($audioResult, $utf8).TrimEnd("`r", "`n")
        if (-not (Test-Path -LiteralPath $audioPath -PathType Leaf)) { throw 'Pobrany plik dzwiekowy nie istnieje.' }
        $file = New-AudioOutput $audioPath $destination $mode $startSuffix $ffmpeg $ffprobe
        Copy-Secondary $file $secondaryDestination $destination
        Write-JobText 'result.txt' $file
        Write-JobText 'done.txt' 'OK'
        exit 0
    }
    if ($mode -eq 'still') {
        $mediaDir = Join-Path $JobDir 'media'
        $null = [IO.Directory]::CreateDirectory($mediaDir)
        $audioResult = Join-Path $JobDir 'audio-path.txt'
        $stillArguments = @(
            '--ignore-config', '--no-playlist', '--no-overwrites', '--newline', '--progress',
            '--progress-template', 'download:REAPER_PROGRESS|%(info.vcodec)s|%(progress._percent_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s',
            '--progress-template', 'postprocess:REAPER_STAGE|processing',
            '--windows-filenames', '--encoding', 'utf-8',
            '--socket-timeout', '30', '--retries', '3', '--fragment-retries', '3',
            '--match-filters', '!is_live', '--ffmpeg-location', (Split-Path -Parent $ffmpeg),
            '--js-runtimes', "deno:$deno", '-f', 'ba[acodec^=mp4a]/ba',
            '--write-thumbnail', '--convert-thumbnails', 'jpg'
        ) + $sectionArguments + @(
            '-P', $mediaDir, '-o', ('%(title)s' + $startSuffix + '.%(ext)s'),
            '--print-to-file', 'before_dl:%(duration)s', (Join-Path $JobDir 'source-duration.txt'),
            '--print-to-file', 'after_move:%(title)s', (Join-Path $JobDir 'title.txt'),
            '--print-to-file', 'after_move:filepath', $audioResult, '--', $url
        )
        $ErrorActionPreference = 'Continue'
        $exitCode = Invoke-Download $yt $stillArguments
        $ErrorActionPreference = 'Stop'
        if ($exitCode -ne 0) { throw 'Blad pobierania dzwieku lub miniatury. Szczegoly w download.log.' }
        $audioPath = [IO.File]::ReadAllText($audioResult, $utf8).TrimEnd("`r", "`n")
        $thumbnail = [IO.Path]::ChangeExtension($audioPath, '.jpg')
        $file = New-StillVideo $audioPath $thumbnail $destination $ffmpeg $ffprobe
        Copy-Secondary $file $secondaryDestination $destination
        Write-JobText 'result.txt' $file
        Write-JobText 'done.txt' 'OK'
        exit 0
    }
    # Preserve original video and audio streams; FFmpeg only merges/remuxes.
    $arguments = @(
        '--ignore-config', '--no-playlist', '--no-overwrites', '--newline', '--progress',
        '--progress-template', 'download:REAPER_PROGRESS|%(info.vcodec)s|%(progress._percent_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s',
        '--progress-template', 'postprocess:REAPER_STAGE|processing',
        '--windows-filenames', '--encoding', 'utf-8',
        '--socket-timeout', '30', '--retries', '3', '--fragment-retries', '3',
        '--match-filters', '!is_live',
        '--ffmpeg-location', (Split-Path -Parent $ffmpeg),
        '--js-runtimes', "deno:$deno",
        '-f', $format,
        '-S', 'res'
    ) + $sectionArguments + @(
        '--merge-output-format', 'mp4',
        '--remux-video', 'mp4',
        '--print-to-file', 'before_dl:filename', (Join-Path $JobDir 'filename.txt'),
        '--print-to-file', 'before_dl:%(duration)s', (Join-Path $JobDir 'source-duration.txt'),
        '-P', $destination, '-o', ('%(title)s [%(height)sp] [%(vcodec)s] [%(fps)sfps]' + $startSuffix + '.%(ext)s'),
        '--print-to-file', 'after_move:%(title)s', (Join-Path $JobDir 'title.txt'),
        '--print-to-file', 'after_move:filepath', $result, '--', $url
    )
    # Argument array: URL and paths are data, never evaluated as PowerShell code.
    $ErrorActionPreference = 'Continue'
    $exitCode = Invoke-Download $yt $arguments
    $ErrorActionPreference = 'Stop'
    if ($exitCode -ne 0) { throw "yt-dlp zakonczyl pobieranie z kodem $exitCode. Wybor: $quality / $codec. Jesli wybrany kodek lub dzwiek AAC nie jest dostepny, pobieranie nie moze sie zakonczyc. Sprobuj kodeka Automatyczny. Szczegoly w download.log." }
    if (-not (Test-Path -LiteralPath $result)) { throw 'Brak sciezki pobranego filmu.' }
    $file = [IO.File]::ReadAllText($result, $utf8).TrimEnd("`r", "`n")
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Pobrany plik nie istnieje.' }
    Set-Progress 'Checking downloaded video'
    Write-QualityReport $file $ffprobe $quality
    Copy-Secondary $file $secondaryDestination $destination
    Write-JobText 'done.txt' 'OK'
} catch {
    $errorMessage = $_.Exception.Message
    if ($errorMessage -match '(?i)yt-dlp|youtube|pobierania dzwieku|pobierania.*miniatury') {
        $errorMessage += "`n`nYouTube may have changed. Run the script again and use Tool updates on the first page; update yt-dlp first."
    }
    Write-JobText 'error.txt' $errorMessage
    Write-JobText 'done.txt' 'ERROR'
    exit 1
}
