---
name: deep-plan
description: Use when asked to verify, improve, or sharpen a plan file using deep plan verification. Runs the deep-plan-verification babysitter process (yolo mode) on a plan file — no coding, no implementation, only iterative plan QA. Shows before/after diff and final quality score at the end.
---

# Deep Plan Verification Skill

**Announce at start:** "I'm using the deep-plan skill to run iterative plan verification."

## What This Does

Runs the `deep-plan-verification.js` babysitter process against a plan file. This does **zero implementation** — it only improves the plan document itself through iterative QA:

- 6-dimension parallel gap scanning (implementation, security, edge-cases, testing, deployment, architecture)
- Dedup + prove-gaps filter (removes phantom gaps before answering)
- Self-answer all real gaps as a senior dev grounded in actual code
- 3-judge review of answers (Implementer / Skeptic / Completeness) — 2/3 must pass
- Consistency gate — ensures new additions don't contradict existing plan
- Quality score (8 dimensions, target 95/100)
- Repeat until score >= 95 or max 10 iterations

## How to Invoke

```
/deep-plan [path-to-plan.md]
```

If no path is given, auto-detect the most recently modified plan in `docs/superpowers/plans/`.

## Steps

**Step 1: Find the plan file**

If user provided a path, use it. Otherwise:
```bash
ls -t docs/superpowers/plans/*.md 2>/dev/null | head -1
```
Confirm with the user: "Found plan: `<path>`. Running deep verification on it."

If no plan found anywhere, ask the user to provide the path.

**Step 2: Snapshot the plan (before state)**

```bash
cp "<plan-file>" "<plan-file>.before-deep-plan"
```

**Step 3: Invoke babysitter yolo**

Use skill `babysitter:yolo`:

```
/babysitter:yolo Run the deep-plan-verification process.
  Process file: ~/.a5c/processes/deep-plan-verification.js
  Inputs: planFile=<absolute-path-to-plan>, projectRoot=<CWD>, requireApproval=false, taskDescription=Deep plan verification — improve plan quality to 95/100 across 8 dimensions
```

**CRITICAL: Do NOT write any code, create any files beyond the plan update, or implement anything. This run is plan-only.**

**Step 4: Show the diff (after state)**

After babysitter completes:

```bash
diff "<plan-file>.before-deep-plan" "<plan-file>" || true
```

If no diff: "No changes were made to the plan."

If diff exists, present it clearly:
- Summary: how many lines added/removed
- Key additions (new sections, new decisions, new answers)
- Final quality score from the last babysitter output

**Step 5: Clean up snapshot**

```bash
rm "<plan-file>.before-deep-plan"
```

**Step 6: Report to user**

Summarize:
- Final quality score (e.g., "Score: 97/100 after 3 iterations")
- Number of gaps found and answered
- Key improvements made to the plan
- Whether the plan is ready for implementation

## Rules

- **NO implementation** — never write production code, create source files, or run build commands
- **NO shortcuts** — do not skip babysitter orchestration; every phase must run through babysitter
- **Plan file only** — the only file that should change is the plan `.md` file itself
- Babysitter handles all orchestration; do not short-circuit it
