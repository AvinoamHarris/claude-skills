---
name: langtalk
description: Hybrid LLM-engineering research — synthesizes a podcast-grounded answer from the Langtalks corpus with current web search results. Triggers on /langtalk, "langtalks", "what does langtalks say about", and LLM-system architecture/trade-off questions where named-practitioner provenance matters.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch
---

# /langtalk — Hybrid Langtalks + Web research consultant

Combines two sources for every LLM-engineering question:
1. **Langtalks** — single-channel persistent NotebookLM notebook seeded with every public episode of the Langtalks podcast (channel `@langtalks`, id `UCWPBxQSxychk2M49Fuoq-5A`). Provides Israeli-practitioner production stories, named guests, Hebrew quotes, lessons-learned.
2. **Web** — current technical sources (papers, blogs, vendor docs, benchmarks). Provides recency, breadth, quantitative depth.

The skill returns a **single synthesized answer** in which every claim is tagged inline with its origin (`[LT*]` for Langtalks, `[W*]` for web), plus a unified sources footer.

## Architecture (one notebook, forever)

- **One** persistent NLM notebook per install, identified by `state.json → notebook.nb_id`.
- Channel id pinned in `config.json`. **No ad-hoc discovery.**
- `bootstrap` seeds the notebook from the channel's upload history (cap 200).
- `update` adds new uploads since `last_refresh`. Old sources never removed.
- Queries auto-refresh if `now - last_refresh > freshness_days` (default 7).

## Subcommands

| Command | What it does |
|---|---|
| `/langtalk "<question>"` | (default) **Hybrid mode** — fires the langtalks query AND a parallel web search, then synthesizes. |
| `/langtalk skill-only "<question>"` | Skip the web layer; pure langtalks notebook output. |
| `/langtalk web-only "<question>"` | Skip the langtalks layer; pure web search. |
| `/langtalk update` | Pull new Langtalks uploads into the notebook. |
| `/langtalk status` | Print notebook id, source count, freshness. |
| `/langtalk bootstrap` | First-run only: create the notebook and seed all videos. |

## How Claude should invoke this skill (hybrid default)

When `$ARGUMENTS` is a free-form question (not a subcommand), Claude MUST execute the hybrid flow:

### Step 1 — Run langtalks AND web search in parallel

In a single message, fire both tool calls in parallel:

**Tool 1 — `Bash` to invoke the langtalks layer:**
```bash
# Plugin install: ${CLAUDE_PLUGIN_ROOT} is set by Claude Code.
# Standalone install: fall back to ~/.claude/skills/langtalk.
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/consult}"
SKILL_DIR="${SKILL_DIR:-$HOME/.claude/skills/langtalk}"
cd "$SKILL_DIR"
ENV_FILE="${CLAUDE_PLUGIN_DATA:-$SKILL_DIR}/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }
bash ./router.sh "$ARGUMENTS"
```
This returns: an answer body with `[n]` citations + a compact `_Sources: ..._` italic footer with 1-2 episode URLs.

**Tool 2 — `WebSearch` for the same question:**
Search the web for 4-7 high-quality sources (papers, vendor docs, technical blogs) published in the last 18 months. Capture title, URL, and published_at where available.

### Step 2 — Synthesize a unified answer

Combine both into ONE flowing answer of 400-800 words. **Every substantive claim must be tagged inline** with its origin:
- `[LT1]`, `[LT2]`, ... — claims from Langtalks (renumber from langtalks's `[n]` to the unified scheme)
- `[W1]`, `[W2]`, ... — claims from web sources

Synthesis rules:
- **Lead with whichever source has the strongest material for that paragraph.** Don't artificially split or alternate.
- When both sources agree, tag both: `... cross-encoders generally outperform bi-encoders for the final reranking pass [LT1, W2].`
- When they disagree or one is silent, tag the source that's making the claim. Do NOT fabricate web support for a langtalks claim or vice versa.
- Preserve direct Hebrew quotes from langtalks when they add color (with English glosses), but keep them tight — don't dump entire transcripts.
- If langtalks returned an empty answer or NLM timed out, fall back to web-only and note `(langtalks layer unavailable: <reason>)` in the footer.
- If WebSearch returns nothing useful, fall back to langtalks-only and say so.

### Step 3 — Print a unified sources footer

After the answer, print:

```
--- WHERE THIS CAME FROM ---
LangTalks (<n> episodes cited):
  [LT1] "<episode title>" — <YouTube URL>
  [LT2] ...

Web (<n> sources):
  [W1] <title> — <publisher/year> — <URL>
  [W2] ...

LangTalks notebook last refreshed: <iso>
```

Keep the footer compact. List only sources that were actually tagged in the answer (not every source consulted).

### Step 4 — One-line "what came from where" summary

End with a single italic sentence summarizing the split, e.g.:
> _Web supplied the technical primitives, model names, and 2025-2026 benchmarks; LangTalks supplied the production trade-offs and Israeli-practitioner workflows._

This is the user's quick orientation: at a glance, they see which source pulled the load.

## Subcommand variants

- `/langtalk skill-only "<q>"` — run only `router.sh "<q>"`, pass the langtalks output through verbatim. No WebSearch.
- `/langtalk web-only "<q>"` — run only WebSearch. No langtalks. Useful when the user knows the topic isn't podcast-relevant.
- `/langtalk update` / `status` / `bootstrap` — passthrough to `router.sh <subcmd>`. No web layer involved.

## When to use the default (hybrid) mode

- Planning an LLM/agent system — wants production-grade trade-off advice.
- Trade-off questions ("X vs Y") — wants both textbook and practitioner views.
- Lessons-learned questions — wants both general industry consensus and specific practitioner stories.

## When NOT to use

- Pure factual lookups (just use WebSearch directly — overkill to fire the podcast layer).
- Code-completion, debugging, command-syntax questions.
- Topics outside LLM/AI engineering.

## Files

- `config.json` — channel id, freshness policy, caps.
- `state.json` — `{ notebook: { nb_id, video_ids, videos_meta, last_refresh, ... } }`.
- `.env` — `YOUTUBE_API_KEY=…` (gitignored; never echo).
- `scripts/common.sh` — shared helpers (env, nlm auth, YT API, atomic state).
- `scripts/bootstrap.sh` — first-run seeding (now also caches `videos_meta`: title + url + published_at per video).
- `scripts/update.sh` — incremental refresh.
- `scripts/query.sh` — langtalks-only answer with `[n]` citations + compact sources footer.
- `scripts/list.sh` — status output.
- `router.sh` — entry point. Dispatches subcommands; for free-form questions returns langtalks-only output (the bash layer cannot synthesize with web — the LLM does that per Step 2 above).

## Important: synthesis happens in Claude Code, not in bash

The bash skill provides ONE half (langtalks) as a primitive. Web search is a Claude Code tool (`WebSearch`). The hybrid synthesis is performed by Claude Code reading both tool outputs and weaving them. Do not try to call WebSearch from inside `query.sh` — it's an LLM tool, not a CLI.
