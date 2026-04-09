---
name: bh-forever
description: Use when the user wants to run continuous autonomous bug hunting with TDD and convergence scoring until the codebase reaches production quality. Triggers on "bh forever", "hunt bugs forever", "fix everything until done", "converge to quality", or any request for a never-ending self-improving bug fix loop.
---

# BH Forever — Continuous Bug Hunt + TDD + Convergence

Runs `babysitter:forever` wrapping the `bh` bug-hunter process with TDD gates, conventions,
autonomous code review, DoD binary gate, and a macro convergence score. Loops until the
codebase converges or a human decision is needed.

## When to Use

- "Run bh forever until the project is clean"
- "Keep fixing bugs until convergence"
- "Self-improving loop — fix everything without cheating"
- Any request for sustained autonomous quality improvement

## How to Invoke

Invoke `babysitter:forever` with this prompt (substitute `<CWD>` with actual path):

```
/babysitter:forever

Run continuous bug-hunter + TDD cycles on <CWD> until convergence.

Each cycle:

1. Branch pre-check — verify clean working tree, not on main/master directly,
   no unresolved merge conflicts. Halt the cycle if dirty.

2. Run the bug-hunter process:
   ~/.a5c/processes/bug-hunter.js
   Inputs: projectDir=<CWD>, autoFix=true, maxIterations=5, fixConfidenceTarget=85,
           tdd=true, conventionsCmd=auto-detect

3. TDD gate — enforce on EVERY fix (no exceptions):
   - Write a failing test that reproduces the exact bug (RED)
   - Fix the bug (GREEN)
   - Verify test passes + no regressions (REFACTOR)
   - Only proceed after the test is green

4. Conventions gate — auto-detect and run all that apply:
   - ESLint     (.eslintrc* present)  → eslint . --max-warnings 0
   - Prettier   (.prettierrc* present) → prettier --check .
   - TypeScript (tsconfig.json present) → tsc --noEmit
   - Project check (check script in package.json) → npm run check
   All must pass. Any failure blocks the cycle — fix and re-run.

5. Code review — run 3 angles IN PARALLEL, fully autonomous:
   - General:  correctness, logic errors, edge cases, null safety, error handling
   - Security: injection, auth bypass, data exposure, unsafe ops, OWASP top 10
   - Quality:  readability, duplication, naming, unnecessary complexity
   BLOCK from any angle → feed findings back as fix context, re-fix, re-review.
   WARN → logged only, does not block.

6. DoD binary gate — all 10 must be YES before commit:
   1. Does every fix address its proven root cause — not just a symptom?
   2. Was a failing test written before the fix was applied (TDD red step)?
   3. Do all new tests pass?
   4. Are there zero regressions in the existing test suite?
   5. Does the build compile with zero errors and zero warnings?
   6. Do all conventions checks pass (ESLint, Prettier, tsc, project check)?
   7. Is the fix confidence score at or above the target?
   8. Did all code review angles pass or warn (no BLOCKs)?
   9. Are all affected code paths covered by the fix?
   10. Is the fix safe — no broken callers, no unintended API surface changes?
   Any NO → feed back as fix context, re-fix, re-gate.

7. Commit — with bug IDs in commit message.

8. Compute convergence score (0–100):
   - Bug delta        (30%) — fewer bugs than previous cycle?
   - Fix confidence   (25%) — average fixConfidenceTarget score this cycle
   - Test coverage    (25%) — coverage % on modified files (pytest-cov / vitest --coverage)
   - Regression rate  (20%) — zero regressions = full points

9. Append score to .a5c/convergence-log.json:
   { "cycle": N, "score": X, "timestamp": "...", "bugsFound": N, "bugsFixed": N }

10. Start next cycle immediately.

Stop when:
- Score >= 90 for 3 consecutive cycles → converged, done
- Score plateau: < 3 points improvement over last 3 cycles → breakpoint, wait for human
- A fix requires an architectural decision → breakpoint, wait for human
- 0 bugs found × 3 cycles → auto-stop, report done

No cheating rules:
- Never write the test after the fix
- Never silence errors with eslint-disable or `as any` casts
- Never delete a failing test
- Never use empty catch blocks to hide errors
- Never skip a conventions or DoD gate — all gates run every cycle
```

## Convergence Score Reference

| Score | Meaning |
|-------|---------|
| < 50  | Active regression — something is getting worse |
| 50–70 | Real progress but significant bugs remain |
| 70–85 | Good shape, closing in |
| 85–90 | Near production quality |
| ≥ 90  | Converged — stop |

## Stop Conditions

| Condition | Action |
|-----------|--------|
| Score ≥ 90 × 3 cycles | Auto-stop, report done |
| Score plateau (< 3 pts / 3 cycles) | Breakpoint → human decides |
| Architectural decision needed | Breakpoint → human decides |
| 0 bugs found × 3 cycles | Auto-stop, report done |

## What Prevents Infinite Spinning

- **Branch pre-check** — dirty state halts the cycle before any damage is done
- **TDD gate** — forces proof-of-bug before touching code
- **Conventions gate** — lint/format/type errors block commit, not just warning
- **Fix confidence scoring** — bh's 4-dimension scoring rejects low-quality fixes
- **Autonomous code review** — 3-angle parallel review blocks on BLOCK findings
- **DoD binary gate** — 10 hard yes/no questions, all must pass before commit
- **Convergence plateau check** — detects when looping produces no real progress
- **One fix per cycle commit** — gives next cycle a clean baseline via git history

## Files Written

| File | Contents |
|------|----------|
| `.a5c/convergence-log.json` | Per-cycle score history |
| `.a5c/runs/<runId>/` | Full babysitter journal |
| Git commits | One per fix batch, tagged with bug IDs |
