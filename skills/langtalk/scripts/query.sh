#!/usr/bin/env bash
# query.sh — answer a question against the langtalks notebook with citations.
# Usage: query.sh "<question>"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

QUESTION="${*:-}"
[[ -n "$QUESTION" ]] || die "usage: query.sh \"<question>\""

load_env
nlm_check_auth || die "nlm auth failed"

CFG="$(read_config)"
FRESH_DAYS="$(jq -r '.freshness_days // 7' <<<"$CFG")"
AUTO_REFRESH="$(jq -r '.auto_refresh_in_query // true' <<<"$CFG")"
MAX_LISTED="$(jq -r '.transparency_max_sources_listed // 12' <<<"$CFG")"

STATE="$(read_state)"
NB_ID="$(jq -r '.notebook.nb_id // empty' <<<"$STATE")"
[[ -n "$NB_ID" ]] || die "no notebook in state — run /langtalk bootstrap first"

LAST_REFRESH="$(jq -r '.notebook.last_refresh // ""' <<<"$STATE")"
if [[ "$AUTO_REFRESH" == "true" && -n "$LAST_REFRESH" ]]; then
  if [[ "$(iso_older_than "$LAST_REFRESH" "$FRESH_DAYS")" == "1" ]]; then
    log "[auto-refresh] running update before query (last_refresh=$LAST_REFRESH > ${FRESH_DAYS}d)"
    if bash "$SCRIPT_DIR/update.sh" >&2; then
      STATE="$(read_state)"
      LAST_REFRESH="$(jq -r '.notebook.last_refresh // ""' <<<"$STATE")"
    else
      log "[auto-refresh] update failed — continuing with stale notebook"
    fi
  fi
fi

log "querying nb=$NB_ID"
RAW="$(nlm notebook query "$NB_ID" "$QUESTION" --json 2>/dev/null || true)"

# Parse the --json envelope: { value: { answer, citations: {n:source_id}, references:[...], sources_used:[...] } }
ANSWER_TEXT=""
CITATIONS_MAP='{}'
if printf '%s' "$RAW" | jq -e '.value.answer' >/dev/null 2>&1; then
  ANSWER_TEXT="$(printf '%s' "$RAW" | jq -r '.value.answer // ""')"
  CITATIONS_MAP="$(printf '%s' "$RAW" | jq -c '.value.citations // {}')"
else
  log "warn: --json envelope missing; falling back to raw text"
  ANSWER_TEXT="$(printf '%s' "$RAW" | jq -r '.value.answer // .answer // .text // .' 2>/dev/null || printf '%s' "$RAW")"
fi

# R1+R2: pull the notebook's source list (already has titles like "12 - Fine-tuning | Mike Erlihson").
SOURCES_RAW="$(nlm source list "$NB_ID" --json 2>/dev/null || nlm source list "$NB_ID" 2>/dev/null || echo '[]')"
SOURCES_MAP='{}'
if printf '%s' "$SOURCES_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
  SOURCES_MAP="$(printf '%s' "$SOURCES_RAW" | jq -c '
    [ .[] | { (.id | tostring): { title: (.title // "(untitled)"), url: (.url // ""), type: (.type // "") } } ]
    | add // {}
  ')"
fi

VIDEO_IDS_JSON="$(jq -c '.notebook.video_ids // []' <<<"$STATE")"
TOTAL_SOURCES="$(jq 'length' <<<"$VIDEO_IDS_JSON")"
VIDEOS_META_JSON="$(jq -c '.notebook.videos_meta // {}' <<<"$STATE")"

# Print the answer body.
printf '%s\n\n' "$ANSWER_TEXT"

# Build cited list: for each cited source, enrich title (from nlm) AND url (from cached videos_meta via title-match).
# Title-match: nlm titles like "12 - Fine-tuning | Mike Erlihson" appear verbatim in YouTube playlist titles.
CITED_JSON="$(jq -c \
  --argjson srcs "$SOURCES_MAP" \
  --argjson meta "$VIDEOS_META_JSON" '
  # Build title -> url map from videos_meta values.
  ($meta | to_entries | map({key: .value.title, value: .value.url}) | from_entries) as $title2url
  |
  to_entries
  | map(select(.value != null))
  | map({n: (.key | tonumber? // 0), source_id: .value})
  | sort_by(.n)
  | map(
      . as $c
      | ($srcs[$c.source_id] // {title: "(unknown)", url: "", type: ""}) as $m
      | $c + {
          title: $m.title,
          url: ( if ($m.url | (. // "" | length > 0)) then $m.url else ($title2url[$m.title] // "") end )
        }
    )
' <<<"$CITATIONS_MAP")"

CITED_COUNT="$(jq 'length' <<<"$CITED_JSON")"
UNIQUE_EPS="$(jq '[.[].title] | unique | length' <<<"$CITED_JSON" 2>/dev/null || echo 0)"

# Compact 1-3 sentence sources block.
if [[ "$CITED_COUNT" == "0" ]]; then
  printf '_Sources: NotebookLM did not return inline citations for this answer; the langtalks notebook holds %s episodes — re-ask for a more specific question to surface citations._\n' "$TOTAL_SOURCES"
else
  # Pick the top 2 distinct cited episodes (by first appearance) for the inline list.
  TOP_TWO="$(jq -c '
    [ .[] | {title, url} ]
    | unique_by(.title)
    | .[0:2]
  ' <<<"$CITED_JSON")"
  L1=""; L2=""
  T1="$(jq -r '.[0].title // ""' <<<"$TOP_TWO")"
  U1="$(jq -r '.[0].url // ""'   <<<"$TOP_TWO")"
  T2="$(jq -r '.[1].title // ""' <<<"$TOP_TWO")"
  U2="$(jq -r '.[1].url // ""'   <<<"$TOP_TWO")"
  if [[ -n "$T1" ]]; then
    if [[ -n "$U1" && "$U1" != "null" ]]; then L1="\"$T1\" ($U1)"; else L1="\"$T1\""; fi
  fi
  if [[ -n "$T2" ]]; then
    if [[ -n "$U2" && "$U2" != "null" ]]; then L2="\"$T2\" ($U2)"; else L2="\"$T2\""; fi
  fi

  if [[ "$UNIQUE_EPS" -le 2 ]]; then
    printf '_Sources: %s' "$L1"
    [[ -n "$L2" ]] && printf '; %s' "$L2"
    printf ' (langtalks NB, last refreshed %s)._\n' "${LAST_REFRESH:-n/a}"
  else
    REST=$((UNIQUE_EPS - 2))
    printf '_Sources: %s; %s; +%s more episodes cited (%s/%s NB sources used, last refreshed %s)._\n' \
      "$L1" "$L2" "$REST" "$CITED_COUNT" "$TOTAL_SOURCES" "${LAST_REFRESH:-n/a}"
  fi
fi
