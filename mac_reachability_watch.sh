#!/usr/bin/env zsh
# mac_reachability_watch.sh
# Checks reachability of multiple Macs and renders a small TUI.
# Exits when all hosts are reachable in the same check.
setopt errexit nounset pipefail

HOSTS=(
  "joe.sstools.co"
  "gordon.sstools.co"
  "cameron.sstools.co"
)

# --- UI helpers ---
supports_tput() { command -v tput >/dev/null 2>&1 }
supports_nc()   { command -v nc   >/dev/null 2>&1 }

if supports_tput; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_DIM="$(tput dim 2>/dev/null || printf '\033[2m')"
else
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
fi

C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_GRAY=$'\033[90m'

SPIN_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# Shared state — accessed by both draw() and main()
typeset -A states
typeset -A details

cleanup() {
  [[ -n "${_KEY_WATCHER_PID:-}" ]] && kill "$_KEY_WATCHER_PID" 2>/dev/null || true
  printf "%s" "${C_RESET}"
  if supports_tput; then tput cnorm >/dev/null 2>&1 || true; fi
  stty icanon 2>/dev/null || true
  printf "\n"
}
trap cleanup EXIT INT TERM

# hide cursor
if supports_tput; then tput civis >/dev/null 2>&1 || true; fi

# Switch to cbreak (non-canonical) mode so ESC is delivered immediately
# without waiting for Enter. This does NOT disable echo, so Ghostty's
# Secure Input is not triggered.
stty -icanon min 1 time 0 2>/dev/null || true

# Clear screen once
printf "\033[2J\033[H"

# Background key watcher: reads /dev/tty directly so it works even while
# the main loop is blocked in ping/nc/sleep. Sends SIGINT on ESC.
_MAIN_PID=$$
_key_watcher() {
  local k
  while IFS= read -rk1 k < /dev/tty 2>/dev/null; do
    [[ "$k" == $'\e' ]] && kill -INT "$_MAIN_PID" 2>/dev/null && return
  done
}
_key_watcher &
_KEY_WATCHER_PID=$!

# Try ICMP ping with a short timeout (macOS: -W is in milliseconds)
ping_check() {
  local host="$1"
  local out
  if out="$(ping -n -c 1 -W 1000 "$host" 2>/dev/null)"; then
    # Parse latency: look for 'time=XX.XXX ms'
    local ms
    ms="$(echo "$out" | awk -F'time=' 'NF>1{print $2}' | awk '{print $1}' | head -n1)"
    if [[ -n "${ms:-}" ]]; then
      echo "ok|icmp|${ms}ms"
    else
      echo "ok|icmp|?"
    fi
    return 0
  fi
  return 1
}

# Try a fast TCP connect to common ports in case ICMP is blocked.
tcp_check() {
  local host="$1"
  local ports=(22 445 5900) # SSH, SMB, Screen Sharing
  if ! supports_nc; then
    return 1
  fi
  for p in "${ports[@]}"; do
    # macOS nc: -G sets timeout for connect; -z is scan mode; -w is overall timeout
    if nc -G 1 -w 1 -z "$host" "$p" >/dev/null 2>&1; then
      echo "ok|tcp|:${p}"
      return 0
    fi
  done
  return 1
}

check_host() {
  local host="$1"
  local res
  if res="$(ping_check "$host")"; then
    echo "$res"
    return 0
  fi
  if res="$(tcp_check "$host")"; then
    echo "$res"
    return 0
  fi
  # Encode failure in output, not exit code — prevents errexit from firing in the caller.
  echo "fail|—|—"
}

draw() {
  local status_line="$1"

  # Move cursor to top-left without clearing scrollback
  printf "\033[H"

  printf "%s%sMac Reachability Watch%s  %s%s%s\033[K\n" \
    "${C_BOLD}" "${C_CYAN}" "${C_RESET}" "${C_DIM}" "$(date +"%Y-%m-%d %H:%M:%S")" "${C_RESET}"
  printf "%s%sPress ESC or Ctrl-C to quit%s\033[K\n\033[K\n" "${C_DIM}" "${C_GRAY}" "${C_RESET}"

  printf "%s\033[K\n" "$status_line"
  printf "\033[K\n"

  # Table header
  printf "%s%-3s  %-22s  %-10s  %-10s%s\033[K\n" "${C_DIM}${C_GRAY}" " " "HOST" "METHOD" "DETAIL" "${C_RESET}"
  printf "%s\033[K\n" "${C_DIM}${C_GRAY}--------------------------------------------------------------${C_RESET}"

  for host in "${HOSTS[@]}"; do
    local st="${states[$host]:-checking}"
    local det="${details[$host]:-—|—}"
    local method="${det%%|*}"
    local detail="${det#*|}"

    local dot="●"
    local color="$C_YELLOW"
    local label="CHECKING"
    if [[ "$st" == "ok" ]]; then
      color="$C_GREEN"; label="OK"
    elif [[ "$st" == "fail" ]]; then
      color="$C_RED"; label="DOWN"
    fi

    printf "%s%-3s%s  %-22s  %-10s  %-10s  %s%s%s\033[K\n" \
      "${color}" "${dot}" "${C_RESET}" \
      "${host}" "${method}" "${detail}" \
      "${C_DIM}" "${label}" "${C_RESET}"
  done

  # Clear any stale content below the drawn lines.
  printf "\033[J"
}

main() {
  local interval="${1:-1}"  # seconds
  local spin_i=0

  while true; do
    # Zsh arrays are 1-indexed; +1 maps the 0-based modulo into range 1..N.
    local spin="${SPIN_CHARS[$((spin_i % ${#SPIN_CHARS[@]} + 1))]}"
    spin_i=$((spin_i + 1))

    local all_ok=1
    local status_line="${C_DIM}${C_GRAY}${spin} Checking ${#HOSTS[@]} hosts...${C_RESET}"

    # Mark as checking before running checks (makes UI feel alive)
    for host in "${HOSTS[@]}"; do
      states[$host]="checking"
      details[$host]="—|—"
    done
    draw "$status_line"

    for host in "${HOSTS[@]}"; do
      local r
      r="$(check_host "$host")"
      local st="${r%%|*}"
      local rest="${r#*|}"      # method|detail
      local method="${rest%%|*}"
      local detail="${rest#*|}"

      if [[ "$st" == "ok" ]]; then
        states[$host]="ok"
      else
        states[$host]="fail"
        all_ok=0
      fi
      details[$host]="${method}|${detail}"
      draw "$status_line"
    done

    if [[ "$all_ok" -eq 1 ]]; then
      draw "${C_GREEN}${C_BOLD}✔ All hosts reachable. Exiting.${C_RESET}"
      printf "\n"
      exit 0
    fi

    draw "${C_YELLOW}${C_BOLD}⚠ Some hosts unreachable. Retrying every ${interval}s...${C_RESET}"
    sleep "$interval"
  done
}

main "${1:-1}"
