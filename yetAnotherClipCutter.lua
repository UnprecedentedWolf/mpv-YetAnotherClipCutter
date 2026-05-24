local mp = require("mp")
local options = require("mp.options")
local msg = require("mp.msg")

-- Default options (now without hardcoded modes)
local opts = {
    target_path = "",
    ffmpeg_bin = "",
    time_start_key = "",
    time_end_key = "",
    mode_switch_key = ""
}

-- Native mpv option parser
options.read_options(opts, mp.get_script_name())

-- Local state variables
local time_pos_start = nil
local timestamp_start = nil

local modes = {}
local current_mode_idx = 1

-- Load custom modes from the same config file
local function load_custom_modes()
    local conf_path = mp.command_native({"expand-path", "~~/script-opts/" .. mp.get_script_name() .. ".conf"})
    local f = io.open(conf_path, "r")
    if not f then
        modes = { { name = "MP4 reencode", args = "-c:v libx264 -vf scale=-1:720,format=yuv420p -ac 2 -y", ext = "mp4" } }
        return
    end

    local pending_name = nil
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$") -- trim whitespace
        if line ~= "" and not line:match("^#") then
            if not pending_name then
                -- check if it's a key=value line
                if not line:match("^[%w_.-]+%s*=") then
                    pending_name = line
                end
            else
                local ext = line:match("%.([^%s]+)$")
                if ext then
                    local args = line:sub(1, -(#ext + 2)):match("^%s*(.-)%s*$")
                    table.insert(modes, { name = pending_name, args = args, ext = ext })
                else
                    table.insert(modes, { name = pending_name, args = line, ext = "mp4" })
                end
                pending_name = nil
            end
        end
    end
    f:close()
    
    if #modes == 0 then
        table.insert(modes, { name = "MP4 reencode", args = "-c:v libx264 -vf scale=-1:720,format=yuv420p -ac 2 -y", ext = "mp4" })
    end
end
load_custom_modes()

-- Helper to format time-pos into a filename-friendly string
local function format_timestamp(time_pos)
    local time_seg = time_pos % 60
    local time_clean = time_pos - time_seg
    local time_hours = math.floor(time_clean / 3600)
    time_clean = time_clean - (time_hours * 3600)
    local time_minutes = time_clean / 60
    
    local seg_str = string.format("%.04f", time_seg)
    local seg_whole, _ = seg_str:match("([^.]*).(.*)")
    
    if time_hours > 0 then
        return string.format("%02dh%02dm%02ds", time_hours, time_minutes, seg_whole)
    else
        return string.format("%02dm%02ds", time_minutes, seg_whole)
    end
end

-- Helper to append a table of arguments to another table
local function append_args(target, source)
    for _, v in ipairs(source) do
        table.insert(target, v)
    end
end

-- Quote-aware argument string parser
local function parse_command_string(str)
    local args = {}
    local current = ""
    local in_quotes = false
    local quote_char = ""
    
    for i = 1, #str do
        local c = str:sub(i, i)
        if in_quotes then
            current = current .. c
            if c == quote_char then
                in_quotes = false
            end
        else
            if c == " " then
                if current ~= "" then
                    table.insert(args, current)
                    current = ""
                end
            elseif c == '"' or c == "'" then
                in_quotes = true
                quote_char = c
                current = current .. c
            else
                current = current .. c
            end
        end
    end
    if current ~= "" then table.insert(args, current) end
    
    local parsed_args = {}
    for _, arg in ipairs(args) do
        if (arg:sub(1,1) == '"' and arg:sub(-1,-1) == '"') or (arg:sub(1,1) == "'" and arg:sub(-1,-1) == "'") then
            arg = arg:sub(2, -2)
        end
        table.insert(parsed_args, arg)
    end
    return parsed_args
end

local function save_time_pos()
    time_pos_start = mp.get_property_number("time-pos")
    if not time_pos_start then return end
    timestamp_start = format_timestamp(time_pos_start)
    mp.osd_message(string.format("Starting timestamp: %s", timestamp_start))
end

local function check_for_crop()
    local filter = ""
    local vfs = mp.get_property_native("vf") or {}
    for _, vf in ipairs(vfs) do
        local name = string.gsub(vf["name"] or "", '^lavfi%-', '')
        if name == "crop" then
            local p = vf["params"] or {}
            if p.w and p.h and p.x and p.y then
                filter = string.format("crop=%d:%d:%d:%d,", p.w, p.h, p.x, p.y)
            end
        end
    end
    return filter
end

local function mode_switch()
    current_mode_idx = (current_mode_idx % #modes) + 1
    mp.osd_message(string.format("%d. %s", current_mode_idx, modes[current_mode_idx].name))
end

local function make_on_clip_finished(filename, mode_name)
    return function(success, result, error)
        if success and result and result.status == 0 then
            mp.osd_message(string.format("%s finished! %s", mode_name, filename), 3)
        else
            mp.osd_message(string.format("Clip creation failed!\nFile: %s\nMode: %s", filename, mode_name), 5)
        end
    end
end

local function run_subprocess(args, callback)
    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        args = args
    }, callback)
end

local function clipCutter()
    if not time_pos_start then
        mp.osd_message("No starting position selected")
        return
    end

    local time_pos_end = mp.get_property_number("time-pos")
    if not time_pos_end or time_pos_end <= time_pos_start then
        mp.osd_message(string.format("Start is same or later than current position. Current start: %s", timestamp_start))
        return
    end

    local mode = modes[current_mode_idx]
    local timestamp_end = format_timestamp(time_pos_end)
    mp.osd_message(string.format("Making clip from %s to %s", timestamp_start, timestamp_end))
    local current_file = mp.get_property("path")
    local filename_no_ext = mp.get_property("filename/no-ext")
    local out_name = string.format("%s_%s_%s.%s", filename_no_ext, timestamp_start, timestamp_end, mode.ext)
    local out_path = opts.target_path .. out_name
    
    local absolute_out_path = out_path
    if not (out_path:match("^%a+:") or out_path:match("^\\\\") or out_path:match("^/")) then
        local pwd = mp.get_property("working-directory", "")
        if pwd ~= "" then
            local sep = pwd:match("[\\/]$") and "" or "\\"
            absolute_out_path = pwd .. sep .. out_path
        end
    end
    
    local display_path = absolute_out_path:gsub("\\+", "\\")
    if absolute_out_path:match("^\\\\") then
        display_path = "\\" .. display_path
    end

    -- Determine track mapping
    local mapping = {}
    local vid = mp.get_property_number("current-tracks/video/id")
    local aid = mp.get_property_number("current-tracks/audio/id")
    
    if mode.ext == "gif" or mode.ext == "webp" then
        if vid then append_args(mapping, { "-map", string.format("0:v:%d", vid - 1) }) end
    else
        if vid and aid then
            append_args(mapping, { "-map", string.format("0:v:%d", vid - 1), "-map", string.format("0:a:%d", aid - 1) })
        elseif vid then
            append_args(mapping, { "-map", string.format("0:v:%d", vid - 1) })
        elseif aid then
            append_args(mapping, { "-map", string.format("0:a:%d", aid - 1) })
        end
    end
    append_args(mapping, { "-map_chapters", "-1", "-map_metadata", "-1" })

    -- Base Input Arguments
    local args_base = { opts.ffmpeg_bin }
    local is_copy = mode.args:match("-c%s+copy")
    if is_copy then append_args(args_base, { "-noaccurate_seek" }) end
    append_args(args_base, { "-ss", tostring(time_pos_start), "-to", tostring(time_pos_end), "-i", current_file })
    if is_copy then append_args(args_base, { "-avoid_negative_ts", "make_zero" }) end

    -- Prepare Custom Arguments
    local args_str = mode.args
    
    -- Replace {crop} placeholder
    if args_str:match("{crop}") then
        local crop_filter = check_for_crop()
        args_str = args_str:gsub("{crop}", crop_filter)
    end
    
    -- Subtitle Pass
    local has_subtitles = args_str:match("{subtitles}")
    local sub_path_to_remove = nil
    
    if has_subtitles then
        local sub_id = mp.get_property_number("current-tracks/sub/id")
        if not sub_id then
            mp.osd_message("No subtitle track selected!")
            return
        end
        local sub_path = opts.target_path .. "clip_cutter_subtitle.ass"
        
        local sub_extract_cmd = {}
        append_args(sub_extract_cmd, args_base)
        append_args(sub_extract_cmd, { "-map", string.format("0:s:%d", sub_id - 1), "-y", "-map_chapters", "-1", "-map_metadata", "-1", sub_path })
        mp.command_native({ name = "subprocess", playback_only = false, args = sub_extract_cmd })
        
        local subtitle_vf_path = string.gsub(sub_path, "\\", "/")
        subtitle_vf_path = string.gsub(subtitle_vf_path, ":", "\\:")
        
        args_str = args_str:gsub("{subtitles}", "subtitles='" .. subtitle_vf_path .. "'")
        sub_path_to_remove = sub_path
    end
    
    -- Final command assembly
    local komenda = {}
    append_args(komenda, args_base)
    append_args(komenda, mapping)
    append_args(komenda, parse_command_string(args_str))
    table.insert(komenda, out_path)
    
    -- Run
    local cb = make_on_clip_finished(display_path, mode.name)
    run_subprocess(komenda, function(success, result, error)
        cb(success, result, error)
        if sub_path_to_remove then
            os.remove(sub_path_to_remove)
        end
    end)
end

-- Keybindings
mp.add_key_binding(opts.time_start_key, "save_time_pos", save_time_pos)
mp.add_key_binding(opts.time_end_key, "clipCutter", clipCutter)
mp.add_key_binding(opts.mode_switch_key, "mode_switch", mode_switch)
