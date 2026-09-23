-- @description LeLeVC_YouTube Downloader
-- @version 1.0
-- @author LeLeVC
-- Requires YouTube-downloader.ps1 beside this file. See README.md.
local r = reaper
local title = 'LeLeVC_YouTube Downloader'
local function message(s) r.MB(s, title, 0) end
if not r.GetOS():match('Win') then
  message('Ta wersja skryptu wymaga Windows.'); return
end
local base = debug.getinfo(1, 'S').source:sub(2):match('^(.*[\\/])')
local worker = base .. 'YouTube-downloader.ps1'
if not r.file_exists(worker) then message('Brak pliku: ' .. worker); return end
-- Keep the legacy namespace so the public rename preserves history and preferences.
local history_section = 'Lech_Reaper YouTube Downloader'
if r.GetExtState(history_section, 'active_instance') ~= '' then
  message('Downloader is already open. Use the existing window.'); return
end
local instance_id = r.genGuid()
local dialog_dir

r.SetExtState(history_section, 'active_instance', instance_id, false)
r.atexit(function()


  if dialog_dir then
    local cancel = io.open(dialog_dir .. '\\cancel.txt', 'wb')
    if cancel then cancel:write('1'); cancel:close() end
  end
  if r.GetExtState(history_section, 'active_instance') == instance_id then
    r.DeleteExtState(history_section, 'active_instance', false)
  end
end)
local function load_history()
  local entries, seen = {}, {}
  for url in r.GetExtState(history_section, 'download_history'):gmatch('[^\r\n]+') do
    local video_id = url:match('^https://www%.youtube%.com/watch%?v=([%w_-]+)$')
    if video_id and #video_id == 11 and not seen[url] then
      entries[#entries + 1], seen[url] = url, true
      if #entries == 10 then break end
    end
  end
  return entries
end
local function save_history(video_id, video_title)
  if video_title and video_title ~= '' then
    r.SetExtState(history_section, 'title_' .. video_id, video_title:gsub('[\r\n\t]', ' '), true)
  end
  local url = 'https://www.youtube.com/watch?v=' .. video_id
  local entries = {url}
  -- Read again on completion, so other downloads completed meanwhile are retained.
  for _, previous in ipairs(load_history()) do
    if previous ~= url and #entries < 10 then entries[#entries + 1] = previous end
  end
  r.SetExtState(history_section, 'download_history', table.concat(entries, '\n'), true)
end
-- One flat list: every entry maps directly to a complete download preset.
local options = {
  {label = 'Audio - Original', mode = 'audio_original', quality = 'best', codec = 'auto',
   quality_label = 'Audio', codec_label = 'Original'},
  {label = 'Audio - WAV (24-bit)', mode = 'audio_wav', quality = 'best', codec = 'auto',
   quality_label = 'Audio', codec_label = 'WAV 24-bit'},
  {label = 'Audio - FLAC (24-bit)', mode = 'audio_flac', quality = 'best', codec = 'auto',
   quality_label = 'Audio', codec_label = 'FLAC 24-bit'},
  {label = 'Cover', mode = 'still', quality = 'best', codec = 'h264',
   quality_label = 'Cover', codec_label = 'H.264 / static'}
}
local resolutions = {
  {'360', '360p'}, {'480', '480p'}, {'720', '720p HD'},
  {'1080', '1080p Full HD'}, {'1440', '1440p 2K'}, {'2160', '2160p 4K'},
  {'best', 'Best available'}
}
local codecs = {{'auto', 'Auto'}, {'av1', 'AV1'}, {'vp9', 'VP9'}, {'h264', 'H.264'}}
for _, resolution in ipairs(resolutions) do
  for _, encoding in ipairs(codecs) do
    if encoding[1] ~= 'h264' or (resolution[1] ~= '1440' and resolution[1] ~= '2160') then
      options[#options + 1] = {
        label = resolution[2] .. ' - ' .. encoding[2], mode = 'video',
        quality = resolution[1], codec = encoding[1],
        quality_label = resolution[2], codec_label = encoding[2]
      }
    end
  end
end

local function download(input, folder, selection, secondary_folder, project_folder_name, mute_mode, import_position, request_id)
input = input:match('^%s*(.-)%s*$')
local host, path = input:match('^https?://([^/]+)/(.*)$')
host = host and host:lower()
local id
if host == 'youtu.be' then
  id = path:match('^([%w_-]+)')
elseif host == 'youtube.com' or host == 'www.youtube.com' or host == 'm.youtube.com' or host == 'music.youtube.com' then
  id = path:match('[?&]v=([%w_-]+)') or path:match('^shorts/([%w_-]+)') or path:match('^live/([%w_-]+)') or path:match('^embed/([%w_-]+)')
end
if not id or #id ~= 11 then message('Wklej link do pojedynczego filmu YouTube.'); return end
local function parse_start_time(value)
  if not value then return 0 end
  value = value:lower():gsub('%%3a', ':')
  if value:match('^%d+$') then return tonumber(value) or 0 end
  local h, m, s = value:match('^(%d+):(%d+):(%d+)$')
  if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) end
  m, s = value:match('^(%d+):(%d+)$')
  if m then return tonumber(m) * 60 + tonumber(s) end
  local total, found = 0, false
  for amount, unit in value:gmatch('(%d+)([hms])') do
    found = true
    total = total + tonumber(amount) * (unit == 'h' and 3600 or unit == 'm' and 60 or 1)
  end
  return found and total or 0
end
local time_value = input:match('[?&#]t=([^&#]+)') or input:match('[?&#]start=([^&#]+)')
local start_seconds = math.floor(parse_start_time(time_value))
local option = options[selection]
if not option then return end
local mode, quality, codec = option.mode, option.quality, option.codec
local quality_label, codec_label = option.quality_label, option.codec_label
local project, project_file = r.EnumProjects(-1, '')
local position = import_position == 'start' and 0 or r.GetCursorPositionEx(project)
local target_track_guid
if import_position == 'track_end' then
  local selected_track = r.GetSelectedTrack(project, 0)
  if not selected_track then message('Zaznacz sciezke docelowa przed rozpoczeciem pobierania.'); return end
  target_track_guid = r.GetTrackGUID(selected_track)
end
local project_folder = project_file:match('^(.*)[\\/]')
if project_folder then
  project_folder_name = (project_folder_name or 'Downloaded'):match('^%s*(.-)%s*$')
  if project_folder_name == '' or project_folder_name == '.' or project_folder_name == '..' or project_folder_name:find('[<>:"/\\|%?%*\r\n]') or project_folder_name:match('[%. ]$') then
    message('Podaj prawidlowa nazwe folderu pobierania projektu.'); return
  end
  folder = project_folder .. '\\' .. project_folder_name
end
if not folder or folder:find('[\r\n"]') or not (folder:match('^%a:[\\/]') or folder:match('^\\\\')) then
  message('Podaj pelna sciezke folderu Windows.'); return
end
if not project_folder then secondary_folder = nil end
if secondary_folder and secondary_folder ~= '' and (secondary_folder:find('[\r\n"]') or not (secondary_folder:match('^%a:[\\/]') or secondary_folder:match('^\\\\'))) then
  message('Podaj pelna sciezke dodatkowego folderu Windows.'); return
end
-- Save directly in the selected folder, including Cover videos.
local job = (os.getenv('TEMP') or base) .. '\\REAPER-YT-' .. r.genGuid():gsub('[{}]', '')
r.RecursiveCreateDirectory(job, 0)
local function write(name, data)
  local f, err = io.open(job .. '\\' .. name, 'wb')
  if not f then error(err) end
  f:write(data); f:close()
end
local function read(name)
  local f = io.open(job .. '\\' .. name, 'rb')
  if not f then return nil end
  local data = f:read('*a'); f:close(); return data
end
local request = 'https://www.youtube.com/watch?v=' .. id .. '\n' .. folder .. '\n' .. quality .. '\n' .. codec .. '\n' .. mode
  .. '\n' .. (secondary_folder or '') .. '\n' .. tostring(start_seconds)
local saved, err = pcall(write, 'request.txt', request)
if not saved then message('Nie mozna zapisac zadania: ' .. tostring(err)); return end
local cancel_file = dialog_dir .. '/cancel-' .. request_id .. '.txt'
if r.file_exists(cancel_file) then return true end
local handoff = io.open(dialog_dir .. '/job-dir.txt', 'wb')
if handoff then handoff:write(job); handoff:close() end
local function quote(s) return '"' .. s .. '"' end
local ps = (os.getenv('SystemRoot') or 'C:\\Windows') .. '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
local launched = r.ExecProcess(quote(ps) .. ' -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File '
  .. quote(worker) .. ' -JobDir ' .. quote(job) .. ' -CancelFile ' .. quote(cancel_file), -2)
if not launched or launched == '' then message('Nie mozna uruchomic PowerShell.'); return end
local function notify_ui(value)
  local f = io.open(dialog_dir .. '/download-result.txt', 'wb')
  if f then f:write(value); f:close() end
end
local started = r.time_precise()
local function poll()
  if read('cancel.txt') or r.file_exists(cancel_file) then return end
  local status = read('done.txt')
  if status then
    if status ~= 'OK' then
      notify_ui((read('error.txt') or 'Download failed.') .. '\nLog: ' .. job .. '/download.log'); return
    end
    local file = (read('result.txt') or ''):gsub('[\r\n]+$', '')
    if file == '' or not r.file_exists(file) then notify_ui('Downloaded file not found.'); return end
    save_history(id, read('title.txt'))
    local warning = read('warning.txt') or ''
    if r.EnumProjects(-1, '') ~= project then
      notify_ui('Download complete. Project changed; import this file manually:\n' .. file .. '\n' .. warning); return
    end
    local target_track
    if target_track_guid then
      for track_index = 0, r.CountTracks(project) - 1 do
        local candidate = r.GetTrack(project, track_index)
        if r.GetTrackGUID(candidate) == target_track_guid then target_track = candidate; break end
      end
      if not target_track then
        notify_ui('Download complete. The selected destination track no longer exists; import this file manually:\n' .. file .. '\n' .. warning); return
      end
      position = 0
      for item_index = 0, r.CountTrackMediaItems(target_track) - 1 do
        local track_item = r.GetTrackMediaItem(target_track, item_index)
        position = math.max(position, r.GetMediaItemInfo_Value(track_item, 'D_POSITION') + r.GetMediaItemInfo_Value(track_item, 'D_LENGTH'))
      end
    end
    local current = r.GetCursorPositionEx(project)
    local existing_items = {}
    for item_index = 0, r.CountMediaItems(project) - 1 do
      existing_items[tostring(r.GetMediaItem(project, item_index))] = true
    end
    if read('cancel.txt') or r.file_exists(cancel_file) then return end
    r.Undo_BeginBlock2(project)
    r.SetEditCurPos2(project, position, false, false)
    local protected_track
    local original_track_mute
    if target_track then
      r.SetOnlyTrackSelected(target_track)
      if mute_mode then
        protected_track = target_track
        original_track_mute = r.GetMediaTrackInfo_Value(target_track, 'B_MUTE')
        r.SetMediaTrackInfo_Value(target_track, 'B_MUTE', 1)
      end
    elseif mute_mode then
      local track_index = r.CountTracks(project)
      r.InsertTrackAtIndex(track_index, true)
      protected_track = r.GetTrack(project, track_index)
      r.SetMediaTrackInfo_Value(protected_track, 'B_MUTE', 1)
      r.SetOnlyTrackSelected(protected_track)
    end
    local inserted = r.InsertMedia(file, (target_track or mute_mode) and 0 or 1)
    if inserted > 0 then
      if mute_mode == 'item' or mute_mode == 'both' then
        for item_index = 0, r.CountMediaItems(project) - 1 do
          local item = r.GetMediaItem(project, item_index)
          if not existing_items[tostring(item)] then r.SetMediaItemInfo_Value(item, 'B_MUTE', 1) end
        end
      end
      if mute_mode == 'item' then r.SetMediaTrackInfo_Value(protected_track, 'B_MUTE', original_track_mute or 0) end
    elseif protected_track then
      if target_track then r.SetMediaTrackInfo_Value(target_track, 'B_MUTE', original_track_mute or 0)
      else r.DeleteTrack(protected_track) end
    end
    r.SetEditCurPos2(project, current, false, false)
    r.Undo_EndBlock2(project, 'Wstaw wideo z YouTube', -1)
    r.UpdateArrange()
    notify_ui((inserted > 0 and 'Complete - imported into REAPER.' or 'Downloaded, but import failed. Check the REAPER video decoder.') .. '\n' .. file .. '\n' .. warning)
    return
  end
  if r.time_precise() - started > 45 and not read('started.txt') then
    notify_ui('Download process did not start. Check PowerShell.'); return
  end
  r.defer(poll)
end
r.defer(poll)
return true
end -- download

-- Native URL field and history share one window. Polling keeps REAPER responsive.
local dialog_script = base .. 'YouTube-link-dialog.ps1'
if not r.file_exists(dialog_script) then message('Missing file: ' .. dialog_script); return end
dialog_dir = (os.getenv('TEMP') or base) .. '\\REAPER-YT-dialog-' .. r.genGuid():gsub('[{}]', '')
r.RecursiveCreateDirectory(dialog_dir, 0)
local history_file, history_error = io.open(dialog_dir .. '\\history.txt', 'wb')
if not history_file then message('Cannot open history: ' .. tostring(history_error)); return end
for _, url in ipairs(load_history()) do
  local video_id = url:match('v=([%w_-]+)$')
  local video_title = r.GetExtState(history_section, 'title_' .. video_id):gsub('[\r\n\t]', ' ')
  history_file:write(url .. '\t' .. video_title .. '\n')
end
history_file:close()
local options_file = io.open(dialog_dir .. '/options.txt', 'wb')
if not options_file then message('Cannot initialize download options.'); return end
for _, option in ipairs(options) do options_file:write(option.label .. '\n') end
options_file:close()
local _, initial_project_file = r.EnumProjects(-1, '')
local initial_folder = initial_project_file:match('^(.*)[\\/]')
local folder_file = io.open(dialog_dir .. '\\project-folder.txt', 'wb')
if not folder_file then message('Cannot initialize download folder.'); return end
folder_file:write(initial_folder or '')
folder_file:close()
local default_file = io.open(dialog_dir .. '\\default-folder.txt', 'wb')
if not default_file then message('Cannot read folder preference.'); return end
default_file:write(r.GetExtState(history_section, 'unsaved_download_folder'))
default_file:close()
local geometry_file = io.open(dialog_dir .. '\\window.txt', 'wb')
if geometry_file then geometry_file:write(r.GetExtState(history_section, 'main_window')); geometry_file:close() end
local function read_dialog(name)
  local file = io.open(dialog_dir .. '\\' .. name, 'rb')
  if not file then return nil end
  local content = file:read('*a'); file:close(); return content
end
local function quote_path(path) return '"' .. path .. '"' end
local powershell = (os.getenv('SystemRoot') or 'C:\\Windows') .. '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
local launch = r.ExecProcess(quote_path(powershell) .. ' -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File '
  .. quote_path(dialog_script) .. ' -DialogDir ' .. quote_path(dialog_dir), -2)
if not launch or launch == '' then message('Cannot open download window.'); return end
local launched_at = r.time_precise()
local last_request_id
local function wait_for_input()
  local request_id = read_dialog('start-download.txt')
  if request_id and request_id:match('^[%w%-]+$') and request_id ~= last_request_id and not read_dialog('done.txt') then
    last_request_id = request_id
    local preferred = read_dialog('remember-folder.txt')
    if preferred and preferred ~= '' then r.SetExtState(history_section, 'unsaved_download_folder', preferred, true) end
    local mute_mode = read_dialog('mute-mode.txt')
    if mute_mode == 'none' then mute_mode = nil end
    if mute_mode ~= nil and mute_mode ~= 'item' and mute_mode ~= 'track' and mute_mode ~= 'both' then mute_mode = nil end
    local import_position = read_dialog('import-position.txt')
    if import_position ~= 'start' and import_position ~= 'track_end' then import_position = 'cursor' end
    local ok, launched = pcall(download, read_dialog('url.txt') or '', read_dialog('folder.txt'), tonumber(read_dialog('option.txt') or ''), read_dialog('secondary-folder.txt'), read_dialog('project-folder-name.txt'), mute_mode, import_position, request_id)
    if not ok or not launched then
      local f = io.open(dialog_dir .. '/download-result.txt', 'wb')
      if f then f:write(ok and 'Download could not start. Check the URL and folder.' or tostring(launched)); f:close() end
    end
  end
  local status = read_dialog('done.txt')
  if status then
    local geometry = read_dialog('window-result.txt')
    if geometry and geometry:match('^-?%d+,-?%d+,%d+,%d+,[01]$') then
      r.SetExtState(history_section, 'main_window', geometry, true)
    end
    -- Apply edits even when Cancel or the window close button was used.
    local removed = {}
    for url in (read_dialog('removed.txt') or ''):gmatch('[^\r\n]+') do
      removed[url] = true
      local removed_id = url:match('^https://www%.youtube%.com/watch%?v=([%w_-]+)$')
      if removed_id and #removed_id == 11 then r.DeleteExtState(history_section, 'title_' .. removed_id, true) end
    end
    local remaining = {}
    for _, url in ipairs(load_history()) do
      if not removed[url] then remaining[#remaining + 1] = url end
    end
    r.SetExtState(history_section, 'download_history', table.concat(remaining, '\n'), true)
    for line in (read_dialog('titles.txt') or ''):gmatch('[^\r\n]+') do
      local video_id, video_title = line:match('^https://www%.youtube%.com/watch%?v=([%w_-]+)\t(.+)$')
      if video_id and #video_id == 11 then r.SetExtState(history_section, 'title_' .. video_id, video_title, true) end
    end
    if status == 'OK' then
      local preferred_folder = read_dialog('remember-folder.txt')
      if preferred_folder and not preferred_folder:find('[\r\n"]') and (preferred_folder:match('^%a:[\\/]') or preferred_folder:match('^\\\\')) then
        r.SetExtState(history_section, 'unsaved_download_folder', preferred_folder, true)
      end
      local url = read_dialog('url.txt')
      -- Downloads are started by the third-page request, not by closing the form.
    elseif status == 'ERROR' then
      message(read_dialog('error.txt') or 'Cannot open download window.')
    end
    return
  end
  if r.time_precise() - launched_at > 45 and not read_dialog('started.txt') then
    message('The download window did not start. Check PowerShell.'); return
  end
  r.defer(wait_for_input)
end
r.defer(wait_for_input)
