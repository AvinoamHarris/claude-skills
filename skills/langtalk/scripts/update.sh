#!/usr/bin/env bash
# update.sh — incremental refresh: add new uploads since last refresh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_env
nlm_check_auth || die "nlm auth failed"

CFG="$(read_config)"
MAX_VIDS="$(jq -r '.videos_per_update_max // 50' <<<"$CFG")"

STATE="$(read_state)"
NB_ID="$(jq -r '.notebook.nb_id // empty' <<<"$STATE")"
[[ -n "$NB_ID" ]] || die "no notebook in state — run /langtalk bootstrap first"

UPLOADS_ID="$(jq -r '.notebook.uploads_playlist_id // empty' <<<"$STATE")"
CHANNEL_ID="$(jq -r '.notebook.channel_id // empty' <<<"$STATE")"
[[ -n "$UPLOADS_ID" ]] || die "uploads_playlist_id missing in state — re-run bootstrap"

KNOWN_IDS="$(jq -c '.notebook.video_ids // []' <<<"$STATE")"

# Page playlistItems.list collecting up to MAX_VIDS latest videos.
LATEST_JSON='[]'
PAGE_TOKEN=""
while :; do
  QS="part=snippet,contentDetails&maxResults=50&playlistId=${UPLOADS_ID}"
  [[ -n "$PAGE_TOKEN" ]] && QS="${QS}&pageToken=${PAGE_TOKEN}"
  RAW="$(yt_api_get playlistItems "$QS")" || die "playlistItems.list failed"
  PAGE_VIDS="$(jq -c '[ .items[]? | {
      id: (.contentDetails.videoId // .snippet.resourceId.videoId),
      title: .snippet.title,
      published_at: (.contentDetails.videoPublishedAt // .snippet.publishedAt),
      url: ("https://www.youtube.com/watch?v=" + (.contentDetails.videoId // .snippet.resourceId.videoId))
    } | select(.id != null) ]' <<<"$RAW")"
  LATEST_JSON="$(jq -c --argjson add "$PAGE_VIDS" '. + $add' <<<"$LATEST_JSON")"
  TOTAL="$(jq 'length' <<<"$LATEST_JSON")"
  PAGE_TOKEN="$(jq -r '.nextPageToken // empty' <<<"$RAW")"
  if [[ -z "$PAGE_TOKEN" ]] || [[ "$TOTAL" -ge "$MAX_VIDS" ]]; then
    break
  fi
done
LATEST_JSON="$(jq -c ".[:${MAX_VIDS}]" <<<"$LATEST_JSON")"

# Compute new_ids = latest - known.
NEW_VIDS_JSON="$(jq -c --argjson known "$KNOWN_IDS" '
  map(select(.id as $i | ($known | index($i)) | not))
' <<<"$LATEST_JSON")"
EXISTING="$(jq -c --argjson known "$KNOWN_IDS" '
  map(select(.id as $i | ($known | index($i)) != null))
' <<<"$LATEST_JSON")"
EXISTING_COUNT="$(jq 'length' <<<"$EXISTING")"
NEW_COUNT="$(jq 'length' <<<"$NEW_VIDS_JSON")"
log "channel=$CHANNEL_ID latest_pulled=$(jq 'length' <<<"$LATEST_JSON") new=$NEW_COUNT existing=$EXISTING_COUNT"

ADDED=0
FAILED=0
ALL_IDS="$KNOWN_IDS"
while IFS= read -r vid; do
  [[ -z "$vid" ]] && continue
  VID_ID="$(jq -r '.id' <<<"$vid")"
  VURL="$(jq -r '.url' <<<"$vid")"
  if nlm source add "$NB_ID" --youtube "$VURL" >/dev/null 2>&1; then
    ALL_IDS="$(jq -c --arg v "$VID_ID" '. + [$v]' <<<"$ALL_IDS")"
    ADDED=$((ADDED+1))
  else
    FAILED=$((FAILED+1))
    log "warn: failed to add $VURL"
  fi
done < <(jq -c '.[]' <<<"$NEW_VIDS_JSON")

NOW="$(now_iso)"
NEW_STATE="$(jq \
  --arg now "$NOW" \
  --argjson vids "$ALL_IDS" '
  .notebook.video_ids = $vids
  | .notebook.last_refresh = $now
' <<<"$STATE")"
write_state_atomic "$NEW_STATE"

printf 'new_added=%s\n' "$ADDED"
printf 'existing=%s\n' "$EXISTING_COUNT"
printf 'failed=%s\n' "$FAILED"
printf 'last_refresh=%s\n' "$NOW"
