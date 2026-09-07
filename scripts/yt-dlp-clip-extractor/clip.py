#!/usr/bin/env python3
"""
yt-clip: Fast Interactive Terminal GUI & CLI for downloading targeted clips from YouTube videos.
"""

import sys
import os
import re
import shutil
import subprocess
import argparse

# --- Color Formatting Helpers ---
COLOR = sys.stdout.isatty() and sys.stderr.isatty()

def c(text, code):
    if not COLOR:
        return text
    return f"\033[{code}m{text}\033[0m"

BOLD = "1"
GREEN = "32"
CYAN = "36"
YELLOW = "33"
RED = "31"
MAGENTA = "35"

def print_banner():
    print(c("""
╔═════════════════════════════════════════════════════════════╗
║                   🎬 YT-CLIP DOWNLOADER                     ║
║         Extract video clips without full downloads          ║
╚═════════════════════════════════════════════════════════════╝
    """, CYAN + ";" + BOLD))

def check_dependencies():
    ytdlp = shutil.which("yt-dlp")
    ffmpeg = shutil.which("ffmpeg")
    node = shutil.which("node")
    ffprobe = shutil.which("ffprobe")
    
    if not ytdlp:
        print(c("❌ Error: 'yt-dlp' is not installed or not found in PATH.", RED))
        sys.exit(1)
    if not ffmpeg:
        print(c("❌ Error: 'ffmpeg' is not installed or not found in PATH.", RED))
        sys.exit(1)
    return ytdlp, node, ffprobe

def parse_time_to_seconds(t_str):
    """Parses standard HH:MM:SS, MM:SS, 3m, 180s, or seconds string into total seconds."""
    t_str = str(t_str).strip().lower()
    if not t_str:
        return 0.0
    if t_str.endswith("s"):
        return float(t_str[:-1])
    if t_str.endswith("m"):
        return float(t_str[:-1]) * 60
    if t_str.endswith("h"):
        return float(t_str[:-1]) * 3600

    parts = [float(p) for p in t_str.split(":")]
    if len(parts) == 1:
        return parts[0]
    elif len(parts) == 2:
        return parts[0] * 60 + parts[1]
    elif len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    else:
        raise ValueError(f"Invalid timestamp format: '{t_str}'")

def format_seconds(seconds):
    """Formats total seconds into HH:MM:SS format."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"

def fetch_video_metadata(ytdlp_bin, node_bin, url, browser_cookie=None):
    """Fast fetch for video title and duration."""
    cmd = [ytdlp_bin]
    if node_bin:
        cmd.extend(["--js-runtimes", "node"])
    if browser_cookie:
        cmd.extend(["--cookies-from-browser", browser_cookie])
    cmd.extend([
        "--no-warnings",
        "--print", "%(title)s",
        "--print", "%(duration>%H:%M:%S|Unknown)s",
        url
    ])
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        lines = [line.strip() for line in res.stdout.strip().split("\n") if line.strip()]
        title = lines[0] if len(lines) > 0 else "Unknown Title"
        duration = lines[1] if len(lines) > 1 else "Unknown"
        return title, duration
    except subprocess.CalledProcessError:
        return None, None

def verify_file_resolution(ffprobe_bin, filepath):
    """Uses ffprobe to verify actual video resolution of downloaded clip."""
    if not ffprobe_bin or not os.path.exists(filepath):
        return None
    cmd = [
        ffprobe_bin, "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "csv=s=x:p=0",
        filepath
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        dims = res.stdout.strip()
        if "x" in dims:
            w, h = dims.split("x")
            return f"{w}x{h} ({h}p)"
    except Exception:
        pass
    return None

class Backtrack(Exception):
    """Raised when user enters 'b' or 'back' to return to previous step."""
    pass

def prompt_user(prompt_text, default_val=None, validator=None, allow_back=False):
    while True:
        if default_val is not None:
            display_prompt = f"{prompt_text} [{c(str(default_val), YELLOW)}]: "
        else:
            display_prompt = f"{prompt_text}: "
        
        try:
            val = input(display_prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n" + c("Aborted.", RED))
            sys.exit(0)
            
        if allow_back and val.lower() in ("b", "back"):
            raise Backtrack()

        if not val and default_val is not None:
            return default_val
        
        if not val and default_val is None:
            print(c("⚠️ Value cannot be empty. Please enter a value.", RED))
            continue

        if validator:
            try:
                validated = validator(val)
                return validated
            except Exception as e:
                print(c(f"⚠️ Invalid input: {e}", RED))
                continue
        return val

def interactive_mode(ytdlp_bin, node_bin, default_url="", browser_cookie=None):
    print_banner()
    
    step = 1
    url = default_url or ""
    title = None
    duration = None
    start_sec = 0.0
    start_fmt = "00:00:00"
    end_type_choice = "1"
    end_sec = 180.0
    end_fmt = "00:03:00"
    dur_str = "3m"
    end_str = None
    selected_quality = "best"
    q_choice = "1"
    out_file = ""
    active_cookie = browser_cookie

    def validate_url(u):
        if not u.startswith("http://") and not u.startswith("https://"):
            raise ValueError("URL must start with http:// or https://")
        return u

    options = [
        ("best", "Best Quality (Highest video + audio resolution)"),
        ("1080p", "1080p Full HD"),
        ("720p", "720p HD"),
        ("480p", "480p Standard"),
        ("360p", "360p Fast Cut (Instant download)"),
        ("audio", "Audio Only (MP3 clip)")
    ]

    while True:
        if step == 1:
            entered_url = prompt_user(
                "🔗 Enter YouTube Video URL",
                default_val=url if url else None,
                validator=validate_url,
                allow_back=False
            )
            print(c("\n⚡ Fetching video info...", MAGENTA))
            fetched_title, fetched_duration = fetch_video_metadata(ytdlp_bin, node_bin, entered_url, active_cookie)
            if not fetched_title:
                print(c("⚠️ Could not fetch video metadata. Please check the URL.", RED))
                continue
            url = entered_url
            title = fetched_title
            duration = fetched_duration
            print(c(f"📹 Title   : ", BOLD) + c(title, GREEN))
            print(c(f"⏱️ Duration: ", BOLD) + c(duration, GREEN))
            step = 2

        elif step == 2:
            print("\n" + c("--- Time Selection ---", BOLD) + c(" (Type 'b' to go back)", YELLOW))
            print("Formats accepted: HH:MM:SS (e.g. 00:15:00), MM:SS (e.g. 15:00), or seconds (e.g. 900)")
            try:
                start_input = prompt_user(
                    "▶️ Start time",
                    default_val=start_fmt,
                    validator=parse_time_to_seconds,
                    allow_back=True
                )
                start_sec = parse_time_to_seconds(start_input)
                start_fmt = format_seconds(start_sec)
                step = 3
            except Backtrack:
                step = 1

        elif step == 3:
            print("\n" + c("--- End Point Selection ---", BOLD) + c(" (Type 'b' to go back)", YELLOW))
            print("Choose end point type:")
            print("  1) Specify End Time (e.g. 00:18:00)")
            print("  2) Specify Duration (e.g. 3m or 03:00)")
            try:
                choice = prompt_user("Select option [1/2]", default_val=end_type_choice, allow_back=True)
                if choice not in ["1", "2"]:
                    choice = "1"
                end_type_choice = choice

                if end_type_choice == "2":
                    while True:
                        dur_input = prompt_user("⏱️ Clip duration", default_val=dur_str, validator=parse_time_to_seconds, allow_back=True)
                        parsed_dur = parse_time_to_seconds(dur_input)
                        if parsed_dur <= 0:
                            print(c("⚠️ Clip duration must be greater than 0s.", RED))
                            continue
                        dur_str = dur_input
                        end_sec = start_sec + parsed_dur
                        end_fmt = format_seconds(end_sec)
                        break
                else:
                    default_end = end_str if end_str and parse_time_to_seconds(end_str) > start_sec else format_seconds(start_sec + 180)
                    while True:
                        end_input = prompt_user("⏹️ End time", default_val=default_end, validator=parse_time_to_seconds, allow_back=True)
                        parsed_end = parse_time_to_seconds(end_input)
                        if parsed_end <= start_sec:
                            print(c(f"⚠️ End time ({format_seconds(parsed_end)}) must be after start time ({start_fmt}). Please enter a valid end time.", RED))
                            continue
                        end_str = end_input
                        end_sec = parsed_end
                        end_fmt = format_seconds(end_sec)
                        break
                step = 4
            except Backtrack:
                step = 2

        elif step == 4:
            print("\n" + c("--- Resolution & Quality Selection ---", BOLD) + c(" (Type 'b' to go back)", YELLOW))
            for idx, (val, desc) in enumerate(options, 1):
                print(f"  {idx}) {desc}")

            try:
                q_in = prompt_user("Select resolution/quality option [1-6]", default_val=q_choice, allow_back=True)
                try:
                    q_idx = int(q_in) - 1
                    if 0 <= q_idx < len(options):
                        selected_quality = options[q_idx][0]
                        q_choice = str(q_idx + 1)
                    else:
                        selected_quality = "best"
                        q_choice = "1"
                except ValueError:
                    selected_quality = "best"
                    q_choice = "1"

                if selected_quality in ["1080p", "720p", "best"] and not active_cookie:
                    if os.path.exists(os.path.expanduser("~/.mozilla/firefox")):
                        active_cookie = "firefox"
                step = 5
            except Backtrack:
                step = 3

        elif step == 5:
            clean_title = re.sub(r'[^\w\s-]', '', title).strip().replace(' ', '_') if title else "yt_clip"
            if len(clean_title) > 30:
                clean_title = clean_title[:30]
            clean_start = start_fmt.replace(":", "-")
            clean_end = end_fmt.replace(":", "-")
            
            ext = "mp3" if selected_quality == "audio" else "mp4"
            default_out = f"{clean_title}_[{clean_start}_to_{clean_end}_{selected_quality}].{ext}"

            try:
                out_file = prompt_user("💾 Output filename", default_val=out_file or default_out, allow_back=True)
                step = 6
            except Backtrack:
                step = 4

        elif step == 6:
            print("\n" + c("════════════════════ DOWNLOADING SUMMARY ════════════════════", CYAN))
            print(f"  URL        : {url}")
            print(f"  Range      : {start_fmt} ➔ {end_fmt} (Duration: {format_seconds(end_sec - start_sec)})")
            print(f"  Resolution : {selected_quality}")
            print(f"  Cookies    : {active_cookie or 'None'}")
            print(f"  Output     : {out_file}")
            print(c("═══════════════════════════════════════════════════════════════", CYAN))
            
            print("\nActions:")
            print("  1) Download now (default)")
            print("  2) Edit settings")
            print("  3) Cancel & Exit")

            try:
                action = prompt_user("Select action [1-3]", default_val="1", allow_back=True)
            except Backtrack:
                step = 5
                continue

            if action in ["1", "download", "d"]:
                return url, start_fmt, end_fmt, selected_quality, out_file, active_cookie
            elif action in ["2", "edit", "e"]:
                step = 1
            elif action in ["3", "cancel", "c", "exit", "q"]:
                print(c("Cancelled.", YELLOW))
                sys.exit(0)
            else:
                return url, start_fmt, end_fmt, selected_quality, out_file, active_cookie

def build_ytdlp_cmd(ytdlp_bin, node_bin, url, start_fmt, end_fmt, quality, output_filename, browser_cookie=None, custom_format=None, force_reencode=False):
    cmd = [ytdlp_bin]

    if node_bin:
        cmd.extend(["--js-runtimes", "node"])
    
    if browser_cookie:
        cmd.extend(["--cookies-from-browser", browser_cookie])
    else:
        cmd.extend(["--extractor-args", "youtube:player_client=android,web"])

    cmd.extend(["--download-sections", f"*{start_fmt}-{end_fmt}"])
    
    # Quiet down external downloader stderr verbosity (HLS segments & PTS warnings)
    cmd.extend(["--downloader-args", "ffmpeg:-loglevel error"])

    if force_reencode:
        cmd.append("--force-keyframes-at-cuts")

    if custom_format:
        cmd.extend(["-f", custom_format])
    elif quality == "best":
        cmd.extend(["-f", "bv*+ba/b", "--merge-output-format", "mp4"])
    elif quality == "audio":
        cmd.extend(["-f", "bestaudio/best", "-x", "--audio-format", "mp3"])
    elif quality and quality.endswith("p"):
        height = quality[:-1]
        fmt_spec = f"bestvideo[height<={height}]+bestaudio/best[height<={height}]/18/best"
        cmd.extend(["-f", fmt_spec, "--merge-output-format", "mp4"])
    elif quality == "default":
        cmd.extend(["-f", "18/best"])

    if output_filename:
        cmd.extend(["-o", output_filename])
    else:
        clean_start = start_fmt.replace(":", "-")
        clean_end = end_fmt.replace(":", "-")
        cmd.extend(["-o", f"%(title)s_[{clean_start}_to_{clean_end}].%(ext)s"])

    cmd.append(url)
    return cmd

def parse_cli_args():
    parser = argparse.ArgumentParser(
        description="yt-clip: Fast Interactive CLI tool for downloading YouTube video clips with resolution selection.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  yt-clip                                                     # Fast interactive TUI mode
  yt-clip "https://www.youtube.com/watch?v=ks0aesq0wuw"        # Interactive mode with URL pre-filled
  yt-clip "https://www.youtube.com/watch?v=ks0aesq0wuw" -s 15:00 -e 18:00 -q 1080p --cookies firefox
  yt-clip "https://www.youtube.com/watch?v=ks0aesq0wuw" -s 15:00 -d 3m -q 720p -o clip.mp4
        """
    )
    
    parser.add_argument("url", nargs="?", help="YouTube video URL")
    parser.add_argument("-s", "--start", help="Start timestamp (e.g. 00:15:00 or 15:00)")
    
    time_group = parser.add_mutually_exclusive_group()
    time_group.add_argument("-e", "--end", help="End timestamp (e.g. 00:18:00 or 18:00)")
    time_group.add_argument("-d", "--duration", help="Clip duration from start time (e.g. 03:00 or 180s or 3m)")
    
    parser.add_argument("-o", "--output", help="Output filename or template")
    parser.add_argument("-q", "--quality", help="Video resolution/quality target (e.g. 1080p, 720p, 480p, 360p, best, audio)")
    parser.add_argument("--cookies", help="Browser to extract cookies from (e.g. firefox, chrome, brave)")
    parser.add_argument("--format", help="Custom yt-dlp format specification")
    parser.add_argument("--reencode", action="store_true", help="Force video re-encoding at cuts for frame-precise start/end points")
    parser.add_argument("-i", "--interactive", action="store_true", help="Force interactive mode")

    return parser.parse_args()

def main():
    args = parse_cli_args()
    ytdlp_bin, node_bin, ffprobe_bin = check_dependencies()

    is_interactive = args.interactive or (not args.url) or (args.url and not (args.start or args.end or args.duration))

    if is_interactive:
        url, start_fmt, end_fmt, quality, out_file, browser_cookie = interactive_mode(
            ytdlp_bin, node_bin, default_url=args.url or "", browser_cookie=args.cookies
        )
        force_reenc = False
        custom_fmt = None
    else:
        url = args.url
        start_sec = parse_time_to_seconds(args.start) if args.start else 0.0
        start_fmt = format_seconds(start_sec)
        
        if args.end:
            end_sec = parse_time_to_seconds(args.end)
        elif args.duration:
            end_sec = start_sec + parse_time_to_seconds(args.duration)
        else:
            end_sec = start_sec + 180.0

        if end_sec <= start_sec:
            print(c(f"❌ Error: End time ({format_seconds(end_sec)}) must be greater than start time ({start_fmt}).", RED))
            sys.exit(1)
            
        end_fmt = format_seconds(end_sec)
        quality = args.quality or "best"
        out_file = args.output
        browser_cookie = args.cookies
        force_reenc = args.reencode
        custom_fmt = args.format

    print("\n" + c("⚡ Initializing fast download...", GREEN))
    cmd = build_ytdlp_cmd(
        ytdlp_bin, node_bin, url, start_fmt, end_fmt, quality, out_file,
        browser_cookie=browser_cookie, custom_format=custom_fmt, force_reencode=force_reenc
    )

    try:
        res = subprocess.run(cmd)
        if res.returncode == 0:
            print("\n" + c("✅ Clip downloaded successfully!", GREEN + ";" + BOLD))
            if out_file and os.path.exists(out_file):
                actual_res = verify_file_resolution(ffprobe_bin, out_file)
                if actual_res:
                    print(c(f"📹 Actual Output Resolution: ", BOLD) + c(actual_res, GREEN))
        else:
            print("\n" + c(f"❌ Download failed with exit code {res.returncode}", RED))
        sys.exit(res.returncode)
    except KeyboardInterrupt:
        print("\n" + c("Download interrupted by user.", YELLOW))
        sys.exit(130)

if __name__ == "__main__":
    main()
