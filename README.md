# Yet Another Clip Cutter for MPV
"Why make yet another clip-cutting plugin?" I've been unable to configure any pre-existing plugins for my specific needs (either because of their limitations, or because I simply didn't understand their configuration formats). My goal has been to create a simple conduit between MPV and FFMPEG and that's how it started. 

### What does it do out of the box?
After downloading and putting yetAnotherClipCutter.lua into your mpv/mpv/scripts folder, and then manually edditing the file to set your ffmpeg path, your desired clip output folder, and your preferred keybindings, the plugin will allow you to create one of 5 types of clips: 
1) a simple reencoded H264 MP4 with accuracy down to the frame you timestamped
2) same thing but burning in your current subtitle track
3) a resized 432p gif
4) a cropped gif (works with cropping with e.g. [occivink/mpv-scripts/crop.lua](https://github.com/occivink/mpv-scripts/blob/d0390c8e802c2e888ff4a2e1d5e4fb040f855b89/scripts/crop.lua))
5) a non-reencoded MP4, using nearest keyframe as starting point

### What's next?
My next goal is to simplify command formatting, so that anyone with knowledge of FFMPEG will be able to easily write their intended commands into plugin-friendly format without needing knowledge of LUA, mpv API or any other programming patterns. Then provide documentation for common cases and where to point people who don't know much about FFMPEG.
