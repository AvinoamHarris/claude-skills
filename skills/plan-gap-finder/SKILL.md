---
name: plan-gap-finder
description: Use when asked to find gaps between a plan file and the actual codebase. Spawns parallel Claude subagents (one per codebase area: backend, frontend, tests, infrastructure, scripts) each cross-referencing the plan against real code. Aggregates into a structured gap report: planned-but-missing, implemented-but-not-planned, and partial implementations. Works in any git repo.
---

# Plan Gap Finder

**Announce at start:** "I'm using the plan-gap-finder skill to cross-reference the plan against the codebase with parallel agents."

## What This Does

Spawns parallel Claude subagents to scan different areas of the codebase and cross-reference each area against the plan file. Each agent reports three categories:

- **Planned but missing** - plan says it should exist, code does not implement it
- **Implemented but not planned** - code exists, plan does not mention it
- **Partial** - partially implemented or mismatched API/signature/behavior

The results are aggregated into one consolidated gap report.

## How to Invoke

```
/plan-gap-finder [path-to-plan.md]
```

If no path is given, auto-detect the most recently modified plan file.

---

## Steps

### Step 1: Find the Plan File

If the user provided a path, use it directly.

Otherwise, auto-detect in this order:
```bash
ls -t docs/superpowers/plans/*.md 2>/dev/null | head -1
ls -t docs/plans/*.md 2>/dev/null | head -1
find docs/ -name "*plan*" -o -name "*spec*" -o -name "*design*" 2>/dev/null | head -5
```

Confirm with the user: "Found plan at `<path>`. Scanning codebase for gaps."

If no plan found, ask the user to provide the path.

### Step 2: Read the Plan

Read the plan file in full. Extract:
- All tasks, components, files, APIs, endpoints, data models, and behaviors mentioned
- Technical decisions and constraints stated in the plan

Keep the full plan content in context -- you will embed it verbatim in each subagent prompt.

### Step 3: Discover Codebase Structure

```bash
ls -la
find . -maxdepth 3 -type d   -not -path '*/node_modules/*'   -not -path '*/.git/*'   -not -path '*/__pycache__/*'   -not -path '*/.venv/*'   -not -path '*/dist/*'   -not -path '*/build/*'   2>/dev/null | head -60
```

Partition into scan areas (skip areas that do not exist):

| Area | Typical paths |
|------|--------------|
| backend | backend/, server/, api/, app/ |
| frontend | frontend/, src/, client/, web/ |
| tests | tests/, test/, __tests__/, *.test.*, *.spec.* |
| infrastructure | docker-compose*, Dockerfile*, *.yaml, *.yml, terraform/, k8s/, .github/ |
| scripts | scripts/, bin/, tools/ |

### Step 4: Spawn Parallel Gap-Finder Agents

Use the `Agent` tool to spawn all area agents **in a single message** (parallel execution).

For each active area, spawn one subagent with this prompt structure:

---

You are a gap-analysis agent for the [AREA] area of this codebase.

Your task: Cross-reference the plan below against the actual [AREA] code and find gaps.

Full Plan Content:
[PASTE FULL PLAN CONTENT HERE]

Your Search Area: Scan all files under [PATHS FOR THIS AREA]
Working directory: [ABSOLUTE CWD]

For each item the plan mentions that is relevant to [AREA]:
1. Does the code/file/function/endpoint/model actually exist?
2. If it exists, does it match the plan spec (correct API, behavior, types)?
3. Is it complete, or stubbed/TODO/placeholder?

Return exactly four sections:

PLANNED BUT MISSING
List each thing the plan says should exist in [AREA] but does not.
Format: - [TYPE] name/path: what the plan says it should be
If none: write "None found."

IMPLEMENTED BUT NOT PLANNED
List significant code in [AREA] the plan never mentions.
Skip boilerplate, imports, logging -- only flag non-trivial things.
Format: - [TYPE] name/path: brief description
If none: write "None found."

PARTIAL IMPLEMENTATIONS
List things that exist but do not fully match the plan.
Format: - [TYPE] name/path: plan says X, code does Y
If none: write "None found."

CONFIDENCE: HIGH / MEDIUM / LOW -- one sentence reason.

Be specific. Name files, functions, classes, endpoints.
Read actual code files before concluding anything is missing.

---

Spawn all area agents in ONE message so they run in parallel.

### Step 5: Aggregate the Results

Once all agents return, merge their reports:

1. **Deduplicate** - the same gap may appear from multiple agents
2. **Rank by severity:**
   - CRITICAL - plan explicitly marks as required or it is a core feature
   - HIGH - clearly in scope, zero implementation found
   - MEDIUM - partially implemented or ambiguous
   - LOW - implemented but not in the plan

### Step 6: Output the Gap Report

```
============================================================
  PLAN GAP REPORT
  Plan: <plan-file-path>
  Repo: <cwd>
  Date: <today>
  Areas scanned: <list>
============================================================

SUMMARY
-------
  Planned but missing:   X items
  Not in plan:           Y items
  Partial:               Z items
  Total gaps:            N

------------------------------------------------------------
  PLANNED BUT MISSING  (HIGH PRIORITY)
------------------------------------------------------------
[CRITICAL]
- ...
[HIGH]
- ...
[MEDIUM]
- ...

------------------------------------------------------------
  IMPLEMENTED BUT NOT PLANNED
------------------------------------------------------------
- ...

------------------------------------------------------------
  PARTIAL IMPLEMENTATIONS
------------------------------------------------------------
- ...

------------------------------------------------------------
  AGENT CONFIDENCE
------------------------------------------------------------
  backend:        HIGH/MEDIUM/LOW
  frontend:       HIGH/MEDIUM/LOW
  tests:          HIGH/MEDIUM/LOW
  infrastructure: HIGH/MEDIUM/LOW

------------------------------------------------------------
  RECOMMENDED NEXT STEPS
------------------------------------------------------------
1. ...
2. ...
============================================================
```

### Step 7: Offer Follow-Up Actions

After the report, offer:
- `/deep-verify-plan` - update the plan with these findings
- "Want me to open GitHub issues for each critical gap?"
- "Want me to create a TDD task list to close these gaps?"

---

## Rules

- **Read actual code** - agents must read files before declaring something missing. If a path is uncertain, use Glob.
- **No hallucination** - uncertain = LOW confidence, not an invented gap.
- **Parallel always** - all area agents launch in one message. Never sequential.
- **Adapt to repo** - skip areas that do not exist. Do not fabricate.
- **Plan is source of truth** - implemented-but-not-planned is informational, not necessarily wrong.
- **No fixes** - this skill finds gaps only. It does not implement anything.
