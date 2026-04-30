#!/usr/bin/env bash
# bootstrap.sh — first-run: create the langtalks notebook and seed all videos.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_env
nlm_check_auth || die "nlm auth failed"

CFG="$(read_config)"
CHANNEL_ID="$(jq -r '.channel_id' <<<"$CFG")"
CAP=200
[[ -n "$CHANNEL_ID" && "$CHANNEL_ID" != "null" ]] || die "config.channel_id missing"

log "fetching channel meta for $CHANNEL_ID"
CHAN_JSON="$(yt_api_get channels "part=contentDetails,snippet&id=${CHANNEL_ID}")" \
  || die "channels.list failed"
UPLOADS_ID="$(jq -r '.items[0].contentDetails.relatedPlaylists.uploads // empty' <<<"$CHAN_JSON")"
CHANNEL_TITLE="$(jq -r '.items[0].snippet.title // empty' <<<"$CHAN_JSON")"
[[ -n "$UPLOADS_ID" ]] || die "could not resolve uploads playlist id"
log "channel='$CHANNEL_TITLE' uploads_playlist=$UPLOADS_ID"

# Page through playlistItems.list, collect up to CAP videos.
VIDEOS_JSON='[]'
PAGE_TOKEN=""
PAGE=0
while :; do
  PAGE=$((PAGE+1))
  QS="part=snippet,contentDetails&maxResults=50&playlistId=${UPLOADS_ID}"
  [[ -n "$PAGE_TOKEN" ]] && QS="${QS}&pageToken=${PAGE_TOKEN}"
  RAW="$(yt_api_get playlistItems "$QS")" || die "playlistItems.list failed page=$PAGE"
  PAGE_VIDS="$(jq -c '[ .items[]? | {
      id: (.contentDetails.videoId // .snippet.resourceId.videoId),
      title: .snippet.title,
      published_at: (.contentDetails.videoPublishedAt // .snippet.publishedAt),
      url: ("https://www.youtube.com/watch?v=" + (.contentDetails.videoId // .snippet.resourceId.videoId))
    } | select(.id != null) ]' <<<"$RAW")"
  COUNT="$(jq 'length' <<<"$PAGE_VIDS")"
  log "page=$PAGE got=$COUNT total_so_far=$(jq 'length' <<<"$VIDEOS_JSON")"
  VIDEOS_JSON="$(jq -c --argjson add "$PAGE_VIDS" '. + $add' <<<"$VIDEOS_JSON")"
  TOTAL="$(jq 'length' <<<"$VIDEOS_JSON")"
  PAGE_TOKEN="$(jq -r '.nextPageToken // empty' <<<"$RAW")"
  if [[ -z "$PAGE_TOKEN" ]] || [[ "$TOTAL" -ge "$CAP" ]]; then
    break
  fi
done

# Trim to cap
VIDEOS_JSON="$(jq -c ".[:${CAP}]" <<<"$VIDEOS_JSON")"
TOTAL="$(jq 'length' <<<"$VIDEOS_JSON")"
log "collected $TOTAL videos (capped at $CAP)"

# Resolve / create notebook.
STATE="$(read_state)"
NB_ID="$(jq -r '.notebook.nb_id // empty' <<<"$STATE")"
REUSE=0
if [[ -n "$NB_ID" ]]; then
  if nlm notebook get "$NB_ID" >/dev/null 2>&1; then
    log "reusing existing notebook nb_id=$NB_ID"
    REUSE=1
  else
    log "stale nb_id=$NB_ID — will create new notebook"
    NB_ID=""
  fi
fi

if [[ -z "$NB_ID" ]]; then
  log "creating notebook 'langtalks'"
  CREATE_OUT="$(nlm notebook create "langtalks" 2>&1 || true)"
  if printf '%s' "$CREATE_OUT" | jq -e '.id // .notebook_id // .nb_id' >/dev/null 2>&1; then
    NB_ID="$(printf '%s' "$CREATE_OUT" | jq -r '.id // .notebook_id // .nb_id')"
  fi
  if [[ -z "$NB_ID" ]]; then
    NB_ID="$(printf '%s' "$CREATE_OUT" | grep -Eo 'nb_id=[A-Za-z0-9_-]+' | head -n1 | cut -d= -f2 || true)"
  fi
  if [[ -z "$NB_ID" ]]; then
    NB_ID="$(printf '%s' "$CREATE_OUT" | grep -Eo 'notebook/[A-Za-z0-9_-]+' | head -n1 | awk -F/ '{print $NF}' || true)"
  fi
  if [[ -z "$NB_ID" ]]; then
    NB_ID="$(printf '%s' "$CREATE_OUT" | grep -Eo '[0-9a-fA-F_-]{16,}' | head -n1 || true)"
  fi
  [[ -n "$NB_ID" ]] || die "could not parse nb_id from create output: $CREATE_OUT"
fi
log "nb_id=$NB_ID"

# Existing video_ids in state (only meaningful when reusing).
EXISTING_IDS_JSON='[]'
if [[ "$REUSE" == "1" ]]; then
  EXISTING_IDS_JSON="$(jq -c '.notebook.video_ids // []' <<<"$STATE")"
fi

ATTEMPTED='[]'
ADDED=0
FAILED=0
i=0
while IFS= read -r vid; do
  [[ -z "$vid" ]] && continue
  VID_ID="$(jq -r '.id' <<<"$vid")"
  VURL="$(jq -r '.url' <<<"$vid")"
  i=$((i+1))
  ATTEMPTED="$(jq -c --arg v "$VID_ID" '. + [$v]' <<<"$ATTEMPTED")"
  # Skip if already in state.
  if jq -e --arg v "$VID_ID" 'index($v)' <<<"$EXISTING_IDS_JSON" >/dev/null 2>&1; then
    continue
  fi
  if nlm source add "$NB_ID" --youtube "$VURL" >/dev/null 2>&1; then
    ADDED=$((ADDED+1))
  else
    FAILED=$((FAILED+1))
    log "warn: failed to add $VURL"
  fi
  if (( i % 10 == 0 )); then
    log "progress: $i/$TOTAL added=$ADDED failed=$FAILED"
  fi
done < <(jq -c '.[]' <<<"$VIDEOS_JSON")

# Merge attempted ids with existing.
ALL_IDS="$(jq -c -n --argjson a "$EXISTING_IDS_JSON" --argjson b "$ATTEMPTED" '$a + $b | unique')"
TOTAL_IN_STATE="$(jq 'length' <<<"$ALL_IDS")"

# v2: build videos_meta map { <yt_id>: {url, title, published_at} } from VIDEOS_JSON.
# Preserves existing entries (in case future runs only add some).
EXISTING_META="$(jq -c '.notebook.videos_meta // {}' <<<"$STATE")"
VIDEOS_META="$(jq -c --argjson prev "$EXISTING_META" '
  reduce .[] as $v ($prev;
    .[$v.id] = { url: $v.url, title: $v.title, published_at: $v.published_at }
  )
' <<<"$VIDEOS_JSON")"

NOW="$(now_iso)"
NEW_STATE="$(jq -n \
  --arg nb "$NB_ID" \
  --arg cid "$CHANNEL_ID" \
  --arg up "$UPLOADS_ID" \
  --arg ct "$CHANNEL_TITLE" \
  --arg now "$NOW" \
  --argjson vids "$ALL_IDS" \
  --argjson meta "$VIDEOS_META" \
  --arg created "$(jq -r '.notebook.created_at // empty' <<<"$STATE")" '
  {
    notebook: {
      nb_id: $nb,
      channel_id: $cid,
      uploads_playlist_id: $up,
      channel_title: $ct,
      video_ids: $vids,
      videos_meta: $meta,
      created_at: (if $created == "" then $now else $created end),
      last_refresh: $now
    }
  }
')"
write_state_atomic "$NEW_STATE"

printf 'nb_id=%s\n' "$NB_ID"
printf 'videos_added=%s\n' "$ADDED"
printf 'videos_failed=%s\n' "$FAILED"
printf 'total_in_state=%s\n' "$TOTAL_IN_STATE"
