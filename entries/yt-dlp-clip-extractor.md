# yt-dlp Clip Extractor

*Fast interactive terminal GUI & CLI to extract timestamped video/audio clips from YouTube without downloading full videos.*

## Problem

Downloading an entire 1- to 3-hour YouTube video just to grab a 2-minute section wastes bandwidth, disk space, and time. Constructing the raw `yt-dlp` command manually with `--download-sections`, custom stream selector strings, cookie extraction flags, and ffmpeg loglevel flags is cumbersome and error-prone.

## Solution

A Python CLI tool (`yt-clip`) that wraps `yt-dlp` and `ffmpeg`. It supports both an interactive terminal wizard mode (prompting for URL, timestamp or duration, target quality, and output name) and non-interactive command-line arguments.

Under the hood, it uses:
- `yt-dlp --download-sections "*START-END"` to fetch only the needed chunks from YouTube.
- Node.js runtime support (`--js-runtimes node`) if available for extraction challenges.
- Automatic Firefox cookie fallback for HD streams (`1080p`, `720p`, `best`) if `~/.mozilla/firefox` exists and no cookies were manually specified.
- `youtube:player_client=android,web` extractor fallback when cookies are not provided.
- Post-download resolution verification using `ffprobe`.

## Code

> Full script: [`scripts/yt-dlp-clip-extractor/clip.py`](../scripts/yt-dlp-clip-extractor/clip.py)

### Usage

#### Interactive Mode
Run without arguments (or with just a URL) to trigger interactive prompts:
```bash
yt-clip
# or prefill the URL:
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID"
```

##### Quick Look at the Menu Flow
1. **URL Prompt**: Enter/confirm YouTube URL. Validates and fetches metadata (title, duration). If metadata retrieval fails, prompts again.
2. **Start Time**: Timestamp in `HH:MM:SS`, `MM:SS`, or seconds. Type `b` or `back` at any step to backtrack.
3. **End Time or Duration**: Specify an end timestamp (enforcing `end > start`) or clip duration (e.g., `3m`).
4. **Resolution/Quality Selection**: Choose target resolution (`best`, `1080p`, `720p`, `480p`, `360p`, `audio`).
5. **Output Filename**: Pre-fills a clean sanitized filename template for customization.
6. **Action Selector**: Download summary confirmation providing:
   - `[1] Download now` (default)
   - `[2] Edit settings` (loops back through the steps to refine parameters)
   - `[3] Cancel & Exit`

#### Non-Interactive CLI Mode
```bash
# Extract 15:00 to 18:00 in 1080p using Firefox cookies
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 15:00 -e 18:00 -q 1080p --cookies firefox

# Extract 3 minutes starting at 15:00 in 720p with custom output filename
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 15:00 -d 3m -q 720p -o clip.mp4

# Extract audio only as MP3
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 01:00:00 -d 45s -q audio -o highlight.mp3

# Extract with frame-accurate cuts by forcing keyframe re-encoding
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 05:10 -d 30s --reencode
```

#### CLI Options
- `url`: YouTube video URL.
- `-s, --start`: Start timestamp (`HH:MM:SS`, `MM:SS`, or seconds). Defaults to `00:00:00`.
- `-e, --end`: End timestamp (`HH:MM:SS`, `MM:SS`, or seconds). Must be after `--start`.
- `-d, --duration`: Duration from start time (e.g., `03:00`, `180s`, or `3m`). Mutually exclusive with `-e`.
- `-q, --quality`: Video resolution/quality (`best`, `1080p`, `720p`, `480p`, `360p`, `audio`).
- `-o, --output`: Output filename or template.
- `--cookies`: Browser to extract cookies from (e.g., `firefox`, `chrome`, `brave`).
- `--format`: Custom yt-dlp format specification string.
- `--reencode`: Force video re-encoding at cuts (`--force-keyframes-at-cuts`) for frame-precise start/end points.
- `-i, --interactive`: Force interactive mode even when arguments are passed.

## Notes

- **Dependencies**: Requires `yt-dlp` and `ffmpeg` in your `PATH`. `node` (for JavaScript challenge solving) and `ffprobe` (for downloaded resolution verification) are optional but detected automatically.
- **YouTube Throttling / Bot Detection**: Using `--cookies firefox` (or letting the interactive mode pick it up if `~/.mozilla/firefox` exists) prevents bot check blocks on HD streams. If cookies are not supplied, the script injects `--extractor-args "youtube:player_client=android,web"`.
- **Duration / Timestamp formats**: The script parses `HH:MM:SS`, `MM:SS`, `Xm`, `Xs`, and `Xh` strings into seconds seamlessly.
- **HLS/DASH verbosity**: Suppresses noisy PTS and HLS segment ffmpeg logs by passing `--downloader-args "ffmpeg:-loglevel error"`.
