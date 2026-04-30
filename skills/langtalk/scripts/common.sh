#!/usr/bin/env bash
# common.sh — shared helpers for the langtalk skill.
# Source me; do not execute directly.
set -euo pipefail

# SKILL_DIR is where the bash code lives (read-only when installed as a plugin).
SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="$SKILL_DIR/config.json"

# Writable state + secrets:
# - When installed as a Claude Code plugin, $CLAUDE_PLUGIN_DATA points at a
#   persistent dir that survives plugin updates. Use it for state.json + .env.
# - In standalone install (~/.claude/skills/langtalk), keep them next to SKILL_DIR.
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA"
  STATE_FILE="$CLAUDE_PLUGIN_DATA/state.json"
  ENV_FILE="$CLAUDE_PLUGIN_DATA/.env"
  # First-run: seed state from the bundled example so bootstrap can write it.
  [[ -f "$STATE_FILE" ]] || cp "$SKILL_DIR/state.json.example" "$STATE_FILE" 2>/dev/null || true
else
  STATE_FILE="$SKILL_DIR/state.json"
  ENV_FILE="$SKILL_DIR/.env"
fi

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

die() {
  log "FATAL: $*"
  exit 1
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

urlencode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
  [[ -n "${YOUTUBE_API_KEY:-}" ]] || die "YOUTUBE_API_KEY is not set (expected in $ENV_FILE)"
}

nlm_check_auth() {
  local out err
  out="$(mktemp)"
  err="$(mktemp)"
  # Some nlm builds emit auth banners to stdout, others to stderr — capture both.
  nlm notebook list >"$out" 2>"$err" || true
  if grep -qE "Authentication (expired|Error)" "$out" "$err"; then
    echo "[ERROR] nlm auth expired — run: nlm login" >&2
    rm -f "$out" "$err"
    return 1
  fi
  rm -f "$out" "$err"
  return 0
}

yt_api_get() {
  # yt_api_get <endpoint> <querystring-without-key>
  # Returns body on stdout, non-zero on HTTP error or quotaExceeded.
  local endpoint="$1"
  local qs="${2:-}"
  local base="https://www.googleapis.com/youtube/v3"
  local url
  if [[ -n "$qs" ]]; then
    url="${base}/${endpoint}?${qs}&key=${YOUTUBE_API_KEY}"
  else
    url="${base}/${endpoint}?key=${YOUTUBE_API_KEY}"
  fi
  local resp
  # --fail-with-body: non-zero exit on HTTP >=400 but still emit body.
  # MSYS path-conv hostile to -o, so capture from stdout instead.
  if ! resp="$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
        curl -sSL --globoff --max-time 15 --fail-with-body \
          -H 'Accept: application/json' \
          --url "$url")"; then
    log "yt_api_get: curl/HTTP error for $endpoint"
    [[ -n "$resp" ]] && printf '%s\n' "$resp" >&2
    return 1
  fi
  if printf '%s' "$resp" | grep -q 'quotaExceeded'; then
    log "yt_api_get: quotaExceeded"
    return 1
  fi
  printf '%s' "$resp"
  return 0
}

read_state() {
  [[ -f "$STATE_FILE" ]] || printf '{ "notebook": null }' > "$STATE_FILE"
  cat "$STATE_FILE"
}

read_config() {
  [[ -f "$CONFIG_FILE" ]] || die "config.json missing at $CONFIG_FILE"
  cat "$CONFIG_FILE"
}

write_state_atomic() {
  # Accepts JSON document on stdin or as $1. Writes atomically (tmp → mv).
  local tmp="$STATE_FILE.tmp"
  if [[ $# -ge 1 ]]; then
    printf '%s' "$1" | jq '.' > "$tmp"
  else
    jq '.' > "$tmp"
  fi
  mv "$tmp" "$STATE_FILE"
}

iso_older_than() {
  # iso_older_than <iso> <days>  → "1" if older than days, else "0"
  python3 - "$1" "$2" <<'PY'
import sys, datetime
try:
    t = datetime.datetime.strptime(sys.argv[1].replace("Z",""), "%Y-%m-%dT%H:%M:%S")
except Exception:
    print("1"); sys.exit(0)
days = int(sys.argv[2])
age = (datetime.datetime.utcnow() - t).total_seconds() / 86400.0
print("1" if age > days else "0")
PY
}

days_since() {
  # days_since <iso> → integer days (floor) since the timestamp.
  python3 - "$1" <<'PY'
import sys, datetime
try:
    t = datetime.datetime.strptime(sys.argv[1].replace("Z",""), "%Y-%m-%dT%H:%M:%S")
except Exception:
    print("-1"); sys.exit(0)
age = (datetime.datetime.utcnow() - t).total_seconds() / 86400.0
print(int(age))
PY
}
