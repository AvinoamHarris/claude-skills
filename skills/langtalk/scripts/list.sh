#!/usr/bin/env bash
# list.sh — print notebook status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

CFG="$(read_config)"
HANDLE="$(jq -r '.channel_handle' <<<"$CFG")"
FRESH_DAYS="$(jq -r '.freshness_days // 7' <<<"$CFG")"

STATE="$(read_state)"
NB_ID="$(jq -r '.notebook.nb_id // ""' <<<"$STATE")"

if [[ -z "$NB_ID" ]]; then
  printf 'No notebook yet. Run: /langtalk bootstrap\n'
  exit 0
fi

CHAN_TITLE="$(jq -r '.notebook.channel_title // "?"' <<<"$STATE")"
TOTAL="$(jq '.notebook.video_ids | length' <<<"$STATE")"
LAST="$(jq -r '.notebook.last_refresh // ""' <<<"$STATE")"

DAYS=-1
STATUS="UNKNOWN"
if [[ -n "$LAST" ]]; then
  DAYS="$(days_since "$LAST")"
  if [[ "$(iso_older_than "$LAST" "$FRESH_DAYS")" == "0" ]]; then
    STATUS="FRESH"
  else
    STATUS="STALE"
  fi
fi

printf 'nb_id:                    %s\n' "$NB_ID"
printf 'channel_handle:           %s\n' "$HANDLE"
printf 'channel_title:            %s\n' "$CHAN_TITLE"
printf 'total_sources_in_state:   %s\n' "$TOTAL"
printf 'last_refresh:             %s\n' "${LAST:-n/a}"
printf 'days_since_refresh:       %s\n' "$DAYS"
printf 'freshness_status:         %s (threshold=%sd)\n' "$STATUS" "$FRESH_DAYS"
