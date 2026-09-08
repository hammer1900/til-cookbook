#!/usr/bin/env bash
#
# dev.sh - Automated scrcpy wireless debugging launcher over dedicated hotspot
#
# Connects to Android device over a dedicated Wi-Fi dongle (dongle0 / DevNet),
# automatically discovering the phone's IP and dynamic Android 11+ wireless
# debugging port before launching an optimized scrcpy session.
#

set -eo pipefail

INTERFACE="dongle0"
PROFILE_NAME="DevNet"
DEFAULT_SUBNET="10.42.0.0/24"
PORT_RANGE="30000-49999"

COLOR_RESET="\033[0m"
COLOR_BOLD="\033[1m"
COLOR_INFO="\033[38;5;39m"
COLOR_SUCCESS="\033[38;5;42m"
COLOR_WARN="\033[38;5;214m"
COLOR_ERROR="\033[38;5;196m"
COLOR_MUTED="\033[38;5;244m"

log_info() {
    printf "${COLOR_INFO}${COLOR_BOLD}[INFO]${COLOR_RESET} %s\n" "$*" >&2
}

log_success() {
    printf "${COLOR_SUCCESS}${COLOR_BOLD}[SUCCESS]${COLOR_RESET} %s\n" "$*" >&2
}

log_warn() {
    printf "${COLOR_WARN}${COLOR_BOLD}[WARN]${COLOR_RESET} %s\n" "$*" >&2
}

log_error() {
    printf "${COLOR_ERROR}${COLOR_BOLD}[ERROR]${COLOR_RESET} %s\n" "$*" >&2
}

CONNECTED_TARGET=""
CLEANUP_DONE=0

cleanup() {
    if [[ $CLEANUP_DONE -eq 1 ]]; then
        return
    fi
    CLEANUP_DONE=1

    printf "\033[?25h" >&2 2>/dev/null || true

    if [[ -n "$CONNECTED_TARGET" ]]; then
        printf "\n" >&2
        log_info "Disconnecting ADB session for ${CONNECTED_TARGET}..."
        adb disconnect "$CONNECTED_TARGET" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT INT TERM

show_help() {
    cat <<EOF
${COLOR_BOLD}Usage:${COLOR_RESET} $(basename "$0") [OPTIONS] [-- SCRCPY_OPTIONS]

${COLOR_BOLD}Description:${COLOR_RESET}
  Automates wireless scrcpy connection to an Android device over the dedicated
  '${PROFILE_NAME}' (${INTERFACE}) hotspot subnet, discovering dynamic wireless
  debugging ports automatically.

${COLOR_BOLD}Options:${COLOR_RESET}
  -p, --ip <IP>            Target phone IP address (skips network discovery)
      --port <PORT>        Target wireless debugging port (skips port scan)
  -q, --quality <PRESET>   Video quality preset: low | med | high | max
                           (default: high -> 1024p, 60fps, 6 Mbps)
      --audio              Enable audio streaming (disabled by default for low latency)
      --keep-screen-on     Keep phone screen awake without turning screen off
  -h, --help               Show this help message and exit

${COLOR_BOLD}Quality Presets:${COLOR_RESET}
  low                      720p, 30 fps, 2 Mbps (ultra low latency / weak signal)
  med                      1024p, 60 fps, 4 Mbps
  high                     1024p, 60 fps, 6 Mbps (recommended default)
  max                      Native resolution, 60 fps, 12 Mbps

${COLOR_BOLD}Custom Scrcpy Arguments:${COLOR_RESET}
  Pass any native scrcpy flags after '--'.
  Example: $(basename "$0") -- --turn-screen-off --stay-awake --record=demo.mp4

EOF
}

check_dependencies() {
    local missing=()
    for cmd in adb scrcpy nmap nmcli ip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_info "Please install missing packages via your package manager:"
        log_info "  sudo apt update && sudo apt install android-tools-adb scrcpy nmap network-manager iproute2"
        exit 1
    fi
}


ensure_interface_up() {
    log_info "Checking '${INTERFACE}' interface and '${PROFILE_NAME}' hotspot status..."

    local if_up=0
    if ip link show "$INTERFACE" >/dev/null 2>&1; then
        local state
        state=$(ip -brief link show "$INTERFACE" 2>/dev/null | awk '{print $2}')
        if [[ "$state" == "UP" ]]; then
            if_up=1
        fi
    fi

    if [[ $if_up -eq 0 ]]; then
        log_warn "Interface '${INTERFACE}' is down or inactive. Bringing up '${PROFILE_NAME}'..."
        if ! nmcli con up "$PROFILE_NAME" >/dev/null 2>&1; then
            log_error "Failed to activate NetworkManager connection '${PROFILE_NAME}' on '${INTERFACE}'."
            echo "" >&2
            log_warn "Troubleshooting Steps:"
            log_warn "1. Ensure the Tenda USB Wi-Fi dongle is firmly connected."
            log_warn "2. If a kernel update broke the Wi-Fi driver, run your recovery script:"
            log_warn "   sudo /usr/local/bin/fix-dongle.sh"
            log_warn "   (or check systemctl status fix-dongle.timer)"
            log_warn "3. Verify the hotspot profile: nmcli connection show '${PROFILE_NAME}'"
            exit 1
        fi
    fi

    log_success "Hotspot '${PROFILE_NAME}' is active on '${INTERFACE}'."
}

discover_ip() {
    local manual_ip="$1"
    if [[ -n "$manual_ip" ]]; then
        echo "$manual_ip"
        return 0
    fi

    log_info "Discovering connected devices on subnet ${DEFAULT_SUBNET}..."

    ping -b -c 2 -W 1 -I "$INTERFACE" 10.42.0.255 >/dev/null 2>&1 || true
    nmap -sn -n --send-ip "$DEFAULT_SUBNET" -e "$INTERFACE" >/dev/null 2>&1 || true

    local host_ip
    host_ip=$(ip -4 addr show dev "$INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
    [[ -z "$host_ip" ]] && host_ip="10.42.0.1"

    local raw_ips=()
    while IFS= read -r ip_found; do
        [[ -z "$ip_found" ]] && continue
        if [[ "$ip_found" =~ ^10\.42\.0\.([0-9]+)$ ]]; then
            local octet="${BASH_REMATCH[1]}"
            if (( octet > 0 && octet < 255 )) && [[ "$ip_found" != "$host_ip" && "$ip_found" != "10.42.0.1" ]]; then
                raw_ips+=("$ip_found")
            fi
        fi
    done < <(
        {
            ip -4 neigh show dev "$INTERFACE" nud reachable nud stale nud delay nud permanent 2>/dev/null | awk '{print $1}'
            cat "/var/lib/NetworkManager/dnsmasq-${INTERFACE}.leases" 2>/dev/null | awk '{print $3}' || true
            cat /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3}' || true
        }
    )

    local candidates=()
    if [[ ${#raw_ips[@]} -gt 0 ]]; then
        while IFS= read -r ip_item; do
            [[ -n "$ip_item" ]] && candidates+=("$ip_item")
        done < <(printf "%s\n" "${raw_ips[@]}" | sort -u -t. -k4 -n)
    fi

    if [[ ${#candidates[@]} -eq 0 ]]; then
        log_error "No reachable devices found on the subnet."
        echo "" >&2
        log_warn "Troubleshooting Steps:"
        log_warn "1. Confirm your Android phone is connected to the '${PROFILE_NAME}' Wi-Fi network."
        log_warn "2. If your phone has a static IP configured, pass it with: $(basename "$0") -p <IP>"
        exit 1
    elif [[ ${#candidates[@]} -eq 1 ]]; then
        log_success "Auto-selected single discovered device: ${COLOR_BOLD}${candidates[0]}${COLOR_RESET}"
        echo "${candidates[0]}"
    else
        log_info "Multiple devices found on '${INTERFACE}':"
        for i in "${!candidates[@]}"; do
            printf "  ${COLOR_BOLD}[%d]${COLOR_RESET} %s\n" "$((i + 1))" "${candidates[$i]}" >&2
        done
        local choice
        while true; do
            read -r -p "$(printf "${COLOR_INFO}?${COLOR_RESET} Select device [1-%d]: " "${#candidates[@]}")" choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
                local selected="${candidates[$((choice - 1))]}"
                log_success "Selected device: ${selected}"
                echo "$selected"
                return 0
            fi
            log_warn "Invalid selection. Please enter a number between 1 and ${#candidates[@]}."
        done
    fi
}

discover_port() {
    local target_ip="$1"
    local manual_port="$2"

    if [[ -n "$manual_port" ]]; then
        echo "$manual_port"
        return 0
    fi

    log_info "Scanning for wireless debugging port on ${target_ip} (${PORT_RANGE})..."

    local scan_output_file
    scan_output_file=$(mktemp)

    (
        nmap -p "$PORT_RANGE" -T4 --open -n "$target_ip" -oG - > "$scan_output_file" 2>/dev/null
    ) &
    local nmap_pid=$!

    local spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local idx=0
    printf "\033[?25l" >&2
    while kill -0 "$nmap_pid" 2>/dev/null; do
        printf "\r${COLOR_INFO}%s${COLOR_RESET} Scanning dynamic ports... " "${spin_chars[$idx]}" >&2
        idx=$(( (idx + 1) % ${#spin_chars[@]} ))
        sleep 0.1
    done
    wait "$nmap_pid" || true
    printf "\r\033[K\033[?25h" >&2

    local open_ports=()
    while IFS= read -r port; do
        if [[ -n "$port" && "$port" =~ ^[0-9]+$ ]]; then
            open_ports+=("$port")
        fi
    done < <(grep -oP '\d+(?=/open/tcp)' "$scan_output_file" || true)

    rm -f "$scan_output_file"

    if [[ ${#open_ports[@]} -eq 0 ]]; then
        log_error "No open wireless debugging port found on ${target_ip} in range ${PORT_RANGE}."
        echo "" >&2
        log_warn "Troubleshooting Steps:"
        log_warn "1. Open Android Developer options -> Wireless debugging."
        log_warn "2. Ensure 'Wireless debugging' toggle is turned ON."
        log_warn "3. Verify your device is connected to '${PROFILE_NAME}'."
        exit 1
    elif [[ ${#open_ports[@]} -eq 1 ]]; then
        log_success "Found active wireless debugging port: ${COLOR_BOLD}${open_ports[0]}${COLOR_RESET}"
        echo "${open_ports[0]}"
    else
        log_info "Multiple open ports detected: ${open_ports[*]}"
        local selected_port="${open_ports[0]}"
        log_info "Attempting port ${selected_port}..."
        echo "$selected_port"
    fi
}

connect_adb() {
    local target_ip="$1"
    local target_port="$2"
    local endpoint="${target_ip}:${target_port}"

    log_info "Connecting ADB to ${COLOR_BOLD}${endpoint}${COLOR_RESET}..."

    adb disconnect "$target_ip" >/dev/null 2>&1 || true
    adb disconnect "$endpoint" >/dev/null 2>&1 || true

    local conn_res
    conn_res=$(adb connect "$endpoint" 2>&1 || true)

    if echo "$conn_res" | grep -qi "connected to"; then
        log_success "ADB successfully connected to ${endpoint}."
        CONNECTED_TARGET="$endpoint"
    elif echo "$conn_res" | grep -qi "already connected"; then
        log_success "ADB already connected to ${endpoint}."
        CONNECTED_TARGET="$endpoint"
    elif echo "$conn_res" | grep -qi "unauthorized"; then
        log_warn "Device reports ${COLOR_BOLD}UNAUTHORIZED${COLOR_RESET}."
        log_warn "Check your phone's screen and tap 'Always allow from this computer' -> 'Allow'."
        CONNECTED_TARGET="$endpoint"
        sleep 2
    else
        log_error "Failed to connect ADB: ${conn_res}"
        exit 1
    fi
}

main() {
    local target_ip=""
    local target_port=""
    local quality="high"
    local enable_audio=0
    local keep_screen_on=0
    local extra_scrcpy_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -q|--quality)
                if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
                    log_error "Option '$1' requires an argument (low | med | high | max)."
                    exit 1
                fi
                case "$2" in
                    low|med|high|max)
                        quality="$2"
                        ;;
                    *)
                        log_error "Invalid quality preset '$2'. Expected one of: low, med, high, max."
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -p|--ip)
                if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
                    log_error "Option '$1' requires an IP address argument."
                    exit 1
                fi
                target_ip="$2"
                shift 2
                ;;
            --port)
                if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
                    log_error "Option '$1' requires a port number argument."
                    exit 1
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 || "$2" -gt 65535 ]]; then
                    log_error "Invalid port number '$2'. Must be between 1 and 65535."
                    exit 1
                fi
                target_port="$2"
                shift 2
                ;;
            --audio)
                enable_audio=1
                shift
                ;;
            --keep-screen-on)
                keep_screen_on=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    extra_scrcpy_args+=("$1")
                    shift
                done
                break
                ;;
            *)
                log_error "Unknown option: $1"
                echo "" >&2
                show_help
                exit 1
                ;;
        esac
    done

    check_dependencies
    ensure_interface_up

    local final_ip
    final_ip=$(discover_ip "$target_ip")

    local final_port
    final_port=$(discover_port "$final_ip" "$target_port")

    connect_adb "$final_ip" "$final_port"

    local scrcpy_flags=(
        "-s" "${final_ip}:${final_port}"
        "--video-codec=h264"
        "--video-buffer=10"
    )

    if [[ $keep_screen_on -eq 0 ]]; then
        scrcpy_flags+=("-S" "-Sw")
    else
        scrcpy_flags+=("-w")
    fi

    if [[ $enable_audio -eq 0 ]]; then
        scrcpy_flags+=("--no-audio")
    fi

    case "$quality" in
        low)
            scrcpy_flags+=("-b" "2M" "--max-size" "720" "--max-fps" "30")
            ;;
        med)
            scrcpy_flags+=("-b" "4M" "--max-size" "1024" "--max-fps" "60")
            ;;
        high)
            scrcpy_flags+=("-b" "6M" "--max-size" "1024" "--max-fps" "60")
            ;;
        max)
            scrcpy_flags+=("-b" "12M" "--max-fps" "60")
            ;;
        *)
            log_warn "Unknown quality preset '$quality'. Defaulting to 'high'."
            scrcpy_flags+=("-b" "6M" "--max-size" "1024" "--max-fps" "60")
            ;;
    esac

    if [[ ${#extra_scrcpy_args[@]} -gt 0 ]]; then
        scrcpy_flags+=("${extra_scrcpy_args[@]}")
    fi

    log_info "Launching scrcpy session (Quality: ${quality})..."
    printf "${COLOR_MUTED}scrcpy %s${COLOR_RESET}\n\n" "${scrcpy_flags[*]}" >&2

    scrcpy "${scrcpy_flags[@]}" || {
        local exit_code=$?
        if [[ $exit_code -ne 0 && $exit_code -ne 130 ]]; then
            log_warn "scrcpy exited with status $exit_code"
        fi
    }
}

main "$@"

