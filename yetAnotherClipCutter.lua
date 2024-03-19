---SETTINGS---------------------------------------------------
--------------------------------------------------------------

-- SET THE FOLDER YOU WANT BELOW - for example "C:\\Users\\you\\Desktop\\" 
-- Yes it needs to have double backslash like this and end on \\ idk why
target_path = ""

-- SET YOUR FFMPEG PATHFILE same as above, for example "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe"
-- Unless you have your environment variables set, then leave as is
-- (if you don't know what any of that means: https://www.wikihow.com/Install-FFmpeg-on-Windows)
ffmpeg_bin = "ffmpeg"

-- Set the keybindings for the start and end time of the clip
-- You can type key combinations like "ctrl+j" or "alt+g" - for "shift+h" type capital "H"
time_start_key = ";"
time_end_key = "'"
mode_switch_key = "\\"

-- Set your default cutting mode (by default it reencodes the file, this results in accurate cut with some usually unnoticable compression)
cut_mode = 1

-- Set the default output format (MP4 is the safest usually)
format = "mp4"

--------------------------------------------------------------
---SETTINGS END HERE------------------------------------------

-- Small function used to try ensuring that subtitle file is fully rendered by the time we start making the video file
-- I should get a signal from ffmpeg when it's done instead but idk how to do that
local function wait(seconds)
    local start = os.time()
    repeat until os.time() > start + seconds
end

-- This function saves the timestamp for where you want your clip to begin.
local function save_time_pos()
	-- First we actually save the timestamp from when the clip-start key is pressed
	time_pos_start = mp.get_property_number("time-pos")
	-- I think the time is in some arcane format so we need to do a bunch of processing to get it into a filename-friendly string
	-- I don't actually understand what happens here anymore
	local time_in_seconds = time_pos_start
    local time_seg = time_pos_start % 60
    local time_pos = time_pos_start - time_seg
    local time_hours = math.floor(time_pos / 3600)
    time_pos = time_pos - (time_hours * 3600)
    local time_minutes = time_pos/60
    time_seg,time_ms=string.format("%.04f", time_seg):match"([^.]*).(.*)"
	-- I omit writing out the "00:" for hour if the start time is less than hour into the video
	-- If you don't like my filename format and want different timestamps then you have to edit this ig
	if time_hours > 0 then
		timestamp_start = string.format("%02dh%02dm%02ds", time_hours, time_minutes, time_seg)
	else
		timestamp_start = string.format("%02dm%02ds", time_minutes, time_seg)
	end
	-- OSD print the information that a starting timestamp was made
	mp.osd_message(string.format("Starting timestamp: %s",timestamp_start))
end

-- If you want to make a cropped clip, well, here's what takes the parameters and prepares them into ffmpeg-friendly format
local function check_for_crop()
	-- This gets the crop information from the VF applied to your player and formats it for ffmpeg VF
	-- Thanks for this part of code from occivink's encode plugin (used under Unlicense license)
	filter = ""
	for _, vf in ipairs(mp.get_property_native("vf")) do
		local name = vf["name"]
		name = string.gsub(name, '^lavfi%-', '')
		if name == "crop" then
			local p = vf["params"]
			filter = string.format("crop=%d:%d:%d:%d,", p.w, p.h, p.x, p.y)
		end
	end
end

-- Crude function to select the cutting mode by scrolling through them with a key press and OSD print selected one
-- Probably due to a rewrite soon
local function mode_switch()
	if cut_mode ==  5 then
		cut_mode = 1
		mp.osd_message("1. MP4 reencode")
	elseif cut_mode == 1 then
		cut_mode = 2
		mp.osd_message("2. MP4 subtitle burn")
	elseif cut_mode == 2 then
		cut_mode = 3
		mp.osd_message("3. GIF resized")
	elseif cut_mode == 3 then
		cut_mode = 4
		mp.osd_message("4. GIF cropped")
	elseif cut_mode == 4 then
		cut_mode = 5
		mp.osd_message("5. MP4 copy")
	end
end

-- The main function
local function clipCutter()
	-- Check if starting time exists
	if time_pos_start ~= nil then
		-- Get the timestamp of video when the clip key was pressed
		time_pos_end = mp.get_property_number("time-pos")
		-- Check if start is before the end
		if time_pos_end > time_pos_start then
			-- Same filename-friendly timestamp formatting magic as seen in save_time_pos() function
			local time_in_seconds = time_pos_end
			local time_seg = time_pos_end % 60
			local time_pos = time_pos_end - time_seg
			local time_hours = math.floor(time_pos / 3600)
			time_pos = time_pos - (time_hours * 3600)
			local time_minutes = time_pos/60
			time_seg,time_ms=string.format("%.04f", time_seg):match"([^.]*).(.*)"
			if time_hours > 0 then
				timestamp_end = string.format("%02dh%02dm%02ds", time_hours, time_minutes, time_seg)
			else
				timestamp_end = string.format("%02dm%02ds", time_minutes, time_seg)
			end
			-- Tables of arguments to construct a final command from, they differ depending on whether you reencode or copy stream
			copystock_start = {
				"run",ffmpeg_bin,"-noaccurate_seek","-ss",tostring(time_pos_start),"-to",tostring(time_pos_end),
				"-i",mp.get_property("path"),"-avoid_negative_ts","make_zero"}
			copystock_end = {"-c","copy","-y"}
			reencodestock_start = {"run",ffmpeg_bin,"-ss",tostring(time_pos_start),"-to",tostring(time_pos_end),"-i",mp.get_property("path")}
			reencodestock_end = {"-c:v","libx264","-vf","format=yuv420p","-ac","2","-y"}
			-- Mapping ensures that clip is made out of what you were actually watching, especially important for files with multiple audio tracks
			-- We check if file has any audio or video tracks and set the mapping accordingly. This is another incredibly crude section that I should rewrite
			if mp.get_property_number("current-tracks/audio/id") and mp.get_property_number("current-tracks/video/id") then
				mapping = {
				"-map",string.format("0:v:%d",mp.get_property_number("current-tracks/video/id")-1),"-map",
				string.format("0:a:%d",mp.get_property_number("current-tracks/audio/id")-1),"-map_chapters","-1","-map_metadata","-1"}
			elseif mp.get_property_number("current-tracks/video/id") then
				mapping = {
				"-map",string.format("0:v:%d",mp.get_property_number("current-tracks/video/id")-1),"-map_chapters","-1","-map_metadata","-1"}
			else
				mapping = {
				"-map",string.format("0:a:%d",mp.get_property_number("current-tracks/audio/id")-1),"-map_chapters","-1","-map_metadata","-1"}
			end
			-- Send an OSD message that we're making a clip
			mp.osd_message(string.format("Making clip from %s to %s",timestamp_start,timestamp_end))
			-- Prepare and execute the proper command for each mode
			-- I realize that this is terribly unreadable and long and messy, I need to figure out how to make it easier to customize
			komenda = {}
			if cut_mode == 1 then
				format = "mp4"
				for _,i in ipairs(reencodestock_start) do table.insert(komenda,i) end
				for _,i in ipairs(mapping) do table.insert(komenda,i) end
				for _,i in ipairs(reencodestock_end) do table.insert(komenda,i) end
				table.insert(komenda,string.format(target_path.."%s_%s_%s.%s",mp.get_property("filename/no-ext"),timestamp_start,timestamp_end,format))
				mp.command_native_async(komenda)	
			elseif cut_mode == 2 then
				format = "mp4"
				for _,i in ipairs(reencodestock_start) do table.insert(komenda,i) end
				for _,i in ipairs{
					"-map",string.format("0:s:%d",mp.get_property_number("current-tracks/sub/id")-1),"-y","-map_chapters","-1","-map_metadata","-1",
					target_path.."clip_cutter_subtitle.ass"} do table.insert(komenda,i) end
				mp.command_native_async(komenda)	
				wait(5)
				subtitle_path = string.gsub(target_path,"\\","/").."clip_cutter_subtitle.ass"
				subtitle_path = string.gsub(subtitle_path,":","\\:")
				komenda = {}
				for _,i in ipairs(reencodestock_start) do table.insert(komenda,i) end
				for _,i in ipairs(mapping) do table.insert(komenda,i) end
				for _,i in ipairs{
					"-c:v","libx264","-vf","subtitles=\'"..subtitle_path.."\',format=yuv420p","-ac","2","-y",
					string.format(target_path.."%s_%s_%s.%s",mp.get_property("filename/no-ext"),timestamp_start,timestamp_end,format)} do table.insert(komenda,i) end
				mp.command_native_async(komenda)	
				wait(5)
				os.remove(target_path.."clip_cutter_subtitle.ass")
			elseif cut_mode == 3 then
				format = "gif"
				for _,i in ipairs(reencodestock_start) do table.insert(komenda,i) end
				for _,i in ipairs{"-vf","scale=-1:432:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"} do table.insert(komenda,i) end
				table.insert(komenda,"-y")
				table.insert(komenda,string.format(target_path.."%s_%s_%s.%s",mp.get_property("filename/no-ext"),timestamp_start,timestamp_end,format))
				mp.command_native_async(komenda)	
			elseif cut_mode == 4 then
				check_for_crop()
				format = "gif"
				for _,i in ipairs(reencodestock_start) do table.insert(komenda,i) end
				for _,i in ipairs{"-vf",string.format("%ssplit[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",filter)} do table.insert(komenda,i) end
				table.insert(komenda,"-y")
				table.insert(komenda,string.format(target_path.."%s_%s_%s.%s",mp.get_property("filename/no-ext"),timestamp_start,timestamp_end,format))
				mp.command_native_async(komenda)	
			elseif cut_mode == 5 then
				format = "mp4"
				for _,i in ipairs(copystock_start) do table.insert(komenda,i) end
				for _,i in ipairs(mapping) do table.insert(komenda,i) end
				for _,i in ipairs(copystock_end) do table.insert(komenda,i) end
				table.insert(komenda,string.format(target_path.."%s_%s_%s.%s",mp.get_property("filename/no-ext"),timestamp_start,timestamp_end,format))
				mp.command_native_async(komenda)	
			-- Fallback messages if something's wrong
			else
				mp.osd_message("Something's wrong, check your code")
			end
		else
			mp.osd_message(string.format("Start is same or later than current position. Current start: %s",timestamp_start))
		end
	else
		mp.osd_message("No starting position selected")
	end		
end

-- Add key bindings for all necessary commands
mp.add_key_binding(time_start_key, save_time_pos)
mp.add_key_binding(time_end_key, clipCutter)
mp.add_key_binding(mode_switch_key, mode_switch)