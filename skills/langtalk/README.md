# langtalk

Hybrid LLM-engineering research skill. Combines a **persistent NotebookLM notebook** seeded with the [Langtalks podcast](https://www.youtube.com/@langtalks) corpus with **live web search**, returning a single synthesized answer where every claim is tagged inline with its origin (`[LT*]` for Langtalks, `[W*]` for web).

Best for **architecture-planning, trade-off, and lessons-learned questions** in LLM engineering — where named-practitioner provenance from Israeli production engineers complements broad web context.

**Upstream / standalone repo:** https://github.com/yehuda-yu/langtalk-claude-skill (full README + eval methodology + results).

---

## Quick setup (one-time)

After `install.sh` symlinks this skill into `~/.claude/skills/langtalk/`:

```bash
# 1. YouTube Data API key (https://console.cloud.google.com/apis/credentials)
cp ~/.claude/skills/langtalk/.env.example ~/.claude/skills/langtalk/.env
# edit .env, paste your YOUTUBE_API_KEY

# 2. State file
cp ~/.claude/skills/langtalk/state.json.example ~/.claude/skills/langtalk/state.json

# 3. NotebookLM CLI auth (one-time browser login) — install via:
#    pipx install notebooklm-mcp-cli   (or uvx — see https://github.com/oren-hofman/notebooklm-mcp-cli)
nlm login

# 4. Bootstrap — creates the persistent NLM notebook and seeds Langtalks episodes (~5 min, idempotent)
bash ~/.claude/skills/langtalk/router.sh bootstrap
```

## Usage

```text
/langtalk "I'm building an embedding-based ranking system. Should I embed paragraphs or extract entities?"
```

Or natural language: `Use langtalk to explain reranking and help me plan the architecture.`

| Command | What it does |
|---|---|
| `/langtalk "<question>"` | **Default** — hybrid (web + skill, synthesized). |
| `/langtalk skill-only "<question>"` | Pure Langtalks-only mode (no web). |
| `/langtalk web-only "<question>"` | Pure web-only mode (skip podcast). |
| `/langtalk update` | Pull new Langtalks episodes into the notebook. |
| `/langtalk status` | Show notebook id, source count, last refresh. |
| `/langtalk bootstrap` | First-run setup. Idempotent. |

## How it works

When you type `/langtalk "<question>"`, Claude Code (per `SKILL.md`) fires two tools in parallel:
1. `bash router.sh "<question>"` — auto-refreshes if stale, queries the persistent NLM notebook, returns answer + citations + 1-line sources footer with YouTube URLs.
2. `WebSearch` — fetches 4-7 current sources (last 18 months).

Then Claude Code synthesizes both into a single 500-700 word answer where every claim is tagged inline (`[LT*]` for Langtalks, `[W*]` for web), followed by a unified sources footer and a 1-line "what came from where" summary.

## Eval (vs pure web search)

On a sealed 6-question test set with a blind LLM judge:

| Track | mean (/50) | wins (of 6) | meanΔ vs web |
|---|---|---|---|
| **Hybrid** | **44.17** | **5.5** | **+3.50** |
| Web-only | 40.67 | 0.5 | — |
| Skill-only | 32.17 | 0 | −8.50 |

Hybrid never lost to web. Paired t-test: t=4.34, p≈0.0074, 95% CI [+1.43, +5.57]. Honest caveats apply (small n, single LLM judge, verbosity bias). Full methodology, qbank, judgments, and audit at the [upstream repo's eval/](https://github.com/yehuda-yu/langtalk-claude-skill/tree/main/eval).

## Prerequisites

| Requirement | Why |
|---|---|
| `bash`, `jq`, `curl`, `python3` | Core dependencies for the skill scripts |
| [`nlm` CLI](https://github.com/oren-hofman/notebooklm-mcp-cli) | NotebookLM client. Install via pipx/uvx, then `nlm login` once. |
| YouTube Data API v3 key | For pulling channel uploads. Free tier (10K/day) is plenty. |

## License

MIT — see upstream repo for full text.
