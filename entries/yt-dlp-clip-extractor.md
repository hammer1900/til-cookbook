# yt-dlp Clip Extractor

*Fast interactive terminal GUI & CLI to extract timestamped video/audio clips or full videos from YouTube without hassle.*

## Problem

Downloading an entire 1- to 3-hour YouTube video just to grab a 2-minute section wastes bandwidth, disk space, and time. Constructing the raw `yt-dlp` command manually with `--download-sections`, custom stream selector strings, cookie extraction flags, progress templates, and ffmpeg loglevel flags is cumbersome and error-prone.

## Solution

A Python CLI tool (`yt-clip`) that wraps `yt-dlp` and `ffmpeg`. It supports both an interactive terminal wizard mode (prompting for URL, range/full download, flexible timestamps or duration, dynamically detected quality options, and output name) and non-interactive command-line arguments.

Under the hood, it features:
- **Flexible Time Parsing**: Regex-based parser supporting compound units (`1h30m15s`, `7m30s`, `45s`, `1.5m`), standard colon formats (`01:23:45`, `23:45`, `7:00`), and plain seconds.
- **Dynamic Quality Metadata**: Queries video formats upfront via `yt-dlp --dump-single-json` to populate interactive quality options with actual available resolutions (e.g. 4K UHD, 2K QHD, 1080p, 720p).
- **Full Video or Clip Selection**: Seamlessly choose between downloading a targeted section (`--download-sections`) or the full video (`-F, --full`).
- **Live Progress & Streaming**: Streams download output directly to terminal with native `--progress` and `--progress-template` metrics, suppressing noisy HLS segment warnings while preserving FFmpeg stats.
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
1. **URL Prompt**: Enter/confirm YouTube URL. Fetches title, formatted duration, and available stream resolutions dynamically.
2. **Range Selection**:
   - `[1] Clip a specific section` (proceeds to start/end timestamp prompts)
   - `[2] Full video` (downloads full video without slicing)
3. **Start Time**: Timestamp in `HH:MM:SS`, `MM:SS`, compound units (e.g., `1h30m`, `7m30s`), or seconds. (Type `b` or `back` at any step to backtrack).
4. **End Time or Duration**: Specify an end timestamp (enforcing `end > start`) or clip duration (e.g., `3m`, `45s`, `1.5m`).
5. **Resolution/Quality Selection**: Dynamically generated from available video heights (e.g. `best`, `2160p (4K UHD)`, `1440p (2K QHD)`, `1080p Full HD`, `720p HD`, `audio`).
6. **Output Filename**: Pre-fills a clean sanitized filename template for customization.
7. **Action Selector**: Download summary confirmation providing:
   - `[1] Download now` (default)
   - `[2] Edit settings` (loops back through the steps to refine parameters)
   - `[3] Cancel & Exit`

#### Non-Interactive CLI Mode
```bash
# Download full video directly
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -F -q 1080p

# Extract 15:00 to 18:00 in 1080p using Firefox cookies
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 15:00 -e 18:00 -q 1080p --cookies firefox

# Extract 3 minutes starting at 15:00 in 720p with custom output filename
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 15:00 -d 3m -q 720p -o clip.mp4

# Extract compound unit timestamps (1h30m start, 45s duration)
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 1h30m -d 45s -q best

# Extract audio only as MP3
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 01:00:00 -d 45s -q audio -o highlight.mp3

# Extract with frame-accurate cuts by forcing keyframe re-encoding
yt-clip "https://www.youtube.com/watch?v=VIDEO_ID" -s 05:10 -d 30s --reencode
```

#### CLI Options
- `url`: YouTube video URL.
- `-F, --full`: Download the full video (bypasses clip range prompts / `--download-sections`).
- `-s, --start`: Start timestamp (`HH:MM:SS`, `MM:SS`, compound units like `1h30m`, or seconds). Defaults to `00:00:00`.
- `-e, --end`: End timestamp (`HH:MM:SS`, `MM:SS`, compound units, or seconds). Must be after `--start`.
- `-d, --duration`: Duration from start time (e.g., `03:00`, `180s`, `3m`, or `1.5m`). Mutually exclusive with `-e`.
- `-q, --quality`: Video resolution/quality (`best`, `2160p`, `1440p`, `1080p`, `720p`, `480p`, `360p`, `audio`).
- `-o, --output`: Output filename or template.
- `--cookies`: Browser to extract cookies from (e.g., `firefox`, `chrome`, `brave`).
- `--format`: Custom yt-dlp format specification string.
- `--reencode`: Force video re-encoding at cuts (`--force-keyframes-at-cuts`) for frame-precise start/end points.
- `-i, --interactive`: Force interactive mode even when arguments are passed.

## Notes

- **Dependencies**: Requires `yt-dlp` and `ffmpeg` in your `PATH`. `node` (for JavaScript challenge solving) and `ffprobe` (for downloaded resolution verification) are optional but detected automatically.
- **YouTube Throttling / Bot Detection**: Using `--cookies firefox` (or letting the interactive mode pick it up if `~/.mozilla/firefox` exists) prevents bot check blocks on HD streams. If cookies are not supplied, the script injects `--extractor-args "youtube:player_client=android,web"`.
- **Duration / Timestamp formats**: The script parses `HH:MM:SS`, `MM:SS`, `Xh`, `Xm`, `Xs`, and compound strings (like `1h30m15s` or `1.5m`) into seconds seamlessly.
- **Download Metrics & Verbosity**: Displays real-time download speeds and ETA while keeping ffmpeg output tidy via `--downloader-args "ffmpeg:-loglevel error"`.
