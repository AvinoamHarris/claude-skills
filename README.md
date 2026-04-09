# claude-skills

Personal Claude Code skills and babysitter processes library.

## Install on a new machine

```bash
git clone git@github.com:deedeeharris/claude-skills.git ~/claude-skills
cd ~/claude-skills
chmod +x install.sh
./install.sh
```

Skills are symlinked into `~/.claude/skills/` and processes into `~/.a5c/processes/`.
Edits in the repo are immediately live. `git push` to sync. `git pull` to update.

## Contents

### Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `bh` | `/bh` | Bug Hunter — scan, TDD-fix, conventions gate, code review, DoD gate, commit |
| `bh-forever` | `/bh-forever` | Continuous bug hunting loop until convergence score ≥ 90 |

### Processes

| Process | Description |
|---------|-------------|
| `bug-hunter.js` | Babysitter process driving the full BH pipeline |

## Usage

```
/bh              — run bug hunter (yolo, fully autonomous)
/bh interactive  — run with breakpoints
/bh-forever      — continuous convergence loop
```

## Adding a new skill

```bash
cp -r ~/.claude/skills/my-skill ~/claude-skills/skills/
cd ~/claude-skills && git add . && git commit -m "add my-skill" && git push
```
