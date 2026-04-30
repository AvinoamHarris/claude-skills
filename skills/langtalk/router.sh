#!/usr/bin/env bash
# router.sh — /langtalk skill entry point.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SKILL_DIR/scripts"

print_help() {
  cat <<'EOF'
/langtalk — Langtalks podcast consultant (single channel, persistent NotebookLM notebook)

Usage:
  /langtalk "<question>"        Ask the notebook (auto-refreshes if stale).
  /langtalk update              Pull new uploads since last refresh.
  /langtalk status              Show notebook id, source count, freshness.
  /langtalk bootstrap           First-run: create notebook and seed all videos.
EOF
}

if [[ $# -eq 0 ]]; then
  print_help
  exit 0
fi

cmd="$1"

case "$cmd" in
  -h|--help|help)
    print_help
    exit 0
    ;;
  bootstrap)
    exec bash "$SCRIPTS_DIR/bootstrap.sh"
    ;;
  update)
    exec bash "$SCRIPTS_DIR/update.sh"
    ;;
  status)
    exec bash "$SCRIPTS_DIR/list.sh"
    ;;
  *)
    exec bash "$SCRIPTS_DIR/query.sh" "$*"
    ;;
esac
