#!/usr/bin/env bash
# install.sh — set up claude-skills on any machine
# Usage: ./install.sh
# Symlinks skills and processes from this repo into the right locations.

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_TARGET="${HOME}/.claude/skills"
PROCESSES_TARGET="${HOME}/.a5c/processes"

echo "=> claude-skills installer"
echo "   repo: $REPO_DIR"
echo ""

# Create target directories if they don't exist
mkdir -p "$SKILLS_TARGET"
mkdir -p "$PROCESSES_TARGET"

# Symlink each skill
echo "=> linking skills..."
for skill_dir in "$REPO_DIR/skills"/*/; do
  skill_name="$(basename "$skill_dir")"
  target="$SKILLS_TARGET/$skill_name"

  if [ -L "$target" ]; then
    echo "   already linked: $skill_name"
  elif [ -d "$target" ]; then
    echo "   ⚠️  $skill_name exists as a real directory — skipping (remove it manually to link)"
  else
    ln -s "$skill_dir" "$target"
    echo "   linked: $skill_name -> $target"
  fi
done

# Symlink each process
echo ""
echo "=> linking processes..."
for process_file in "$REPO_DIR/processes"/*.js; do
  [ -f "$process_file" ] || continue
  process_name="$(basename "$process_file")"
  target="$PROCESSES_TARGET/$process_name"

  if [ -L "$target" ]; then
    echo "   already linked: $process_name"
  elif [ -f "$target" ]; then
    echo "   ⚠️  $process_name exists as a real file — skipping (remove it manually to link)"
  else
    ln -s "$process_file" "$target"
    echo "   linked: $process_name -> $target"
  fi
done

echo ""
echo "✓ Done. Skills and processes are live in Claude Code."
echo "  To update: git pull (symlinks auto-reflect changes)"
