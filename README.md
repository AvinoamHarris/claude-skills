# claude-skills

Personal Claude Code skills and babysitter processes library.

## Install on a new machine

```bash
git clone git@github.com:YOUR_USERNAME/claude-skills.git ~/claude-skills
cd ~/claude-skills
chmod +x install.sh
./install.sh
```

That's it. Skills are symlinked into `~/.claude/skills/` and processes into `~/.a5c/processes/`.
Edits in the repo are immediately live. `git push` to sync. `git pull` to update.

## Contents

### Skills

| Skill | Description |
|-------|-------------|
| `bh` | Bug Hunter — scan, TDD-fix, conventions gate, code review, DoD gate, commit |
| `bh-forever` | Continuous bug hunting loop until convergence score ≥ 90 |
| `babysitter` | Core babysitter orchestration |
| `babysitter-breakpoint` | Breakpoint API for interactive babysitter runs |
| `babysitter-score` | Fix confidence scoring phase |

### Processes

| Process | Description |
|---------|-------------|
| `bug-hunter.js` | Babysitter process driving the full BH pipeline |

## Usage

```
/bh              — run bug hunter (yolo mode, fully autonomous)
/bh interactive  — run bug hunter with breakpoints
/bh-forever      — continuous convergence loop
```

## Adding a new skill

1. Create `skills/my-skill/SKILL.md` in this repo
2. Re-run `./install.sh` (it will symlink the new skill)
3. `git add . && git commit && git push`
