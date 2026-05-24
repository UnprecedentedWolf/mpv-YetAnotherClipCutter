# Yet Another Clip Cutter for MPV
"Why make yet another clip-cutting plugin?" I've been unable to configure any pre-existing plugins for my specific needs (either because of their limitations, or because I simply didn't understand their configuration formats). My goal has been to create a simple conduit between MPV and FFMPEG and that's how it started. 

### Getting started
Download and put yetAnotherClipCutter.lua into your mpv/mpv/scripts folder and yetAnotherClipCutter.conf into mpv/mpv/script-opts folder. If you don't have ffmpeg in your PATH, you'll need to go to the .conf file and specify the path to your ffmpeg.exe (if you don't have ffmpeg.exe on your pc, get it from https://ffmpeg.org/). While you're at it, you can set your key bindings and where you want your clips to be saved.

### What does it do out of the box?
Here's the type of clips you can make by default:
1) a simple reencoded H264 MP4 with accuracy down to the frame you timestamped
2) same thing but burning in your current subtitle track
3) a resized 432p gif
4) a cropped gif (works with cropping with e.g. [occivink/mpv-scripts/crop.lua](https://github.com/occivink/mpv-scripts/blob/d0390c8e802c2e888ff4a2e1d5e4fb040f855b89/scripts/crop.lua))
5) a non-reencoded MP4, using nearest keyframe as starting point

Note it only works for local files - I don't know of a method to pass a chunk of video streamed via yt-dlp to ffmpeg.

### Customizing
You can add and remove clipping modes the same way you would write the ffmpeg commands inside the .conf file. Maybe you'll find this [cheat sheet](https://gist.github.com/steven2358/ba153c642fe2bb1e47485962df07c730) or this [tutorial](https://research.mach1.tech/tutorials/ffmpeg-useful-commands/) useful - otherwise dive into the [documentation](https://ffmpeg.org/ffmpeg.html), or just do a web search.

You shouldn't need to ever touch the .lua file unless you want to make some sort of architectural changes I can't think of.
