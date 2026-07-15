---
type: fix
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
date: 2026-07-15
branch: feat-one-shot-scratch-path-collision
---

# fix: Collision-free scratch paths in agent-facing guidance

## Overview

Soleur's agent-facing guidance prescribes **deterministic** `/tmp` paths for capturing
command output. Because the prescribed path is a pure function of the *script name* (or a
`<placeholder>` template), every concurrent session following the guidance writes to the
**same file by construction**. With parallel worktrees as the documented, intended workflow
(16 worktrees present at this session's start — verified via `git worktree list | wc -l`),
sessions silently truncate (`>`) and interleave each other's output.

The failure is **not** a lost log. It is a **false signal on load-bearing pass/fail
evidence**: the log you read to learn *which* suite failed and *why* may belong to another
session. The benign direction costs a ~10-minute re-run. The dangerous inverse — reading a
sibling's GREEN log and concluding your own run passed — chains a false PASS into ship.

`scripts/test-all.sh` is **not** at fault. Verified: `grep -nE '/tmp/|mktemp|TMPDIR'
scripts/test-all.sh` exits 1 (zero hits). It writes nothing to `/tmp`. This is purely a
defect in the **prose that tells agents how to capture output** — guidance that shapes every
future session. Therefore the **guard matters more than the individual edits**.

**This plan is docs + one test. It touches no product code.**

---

## Research Reconciliation — Brief vs. Codebase

The brief explicitly instructed: *"RE-DERIVE IT — do not trust this list"* and *"The plan
itself must not prescribe a literal command it has not verified."* Every claim was re-run.
Four divergences found:

| Brief's claim | Reality (verified) | Plan response |
|---|---|---|
| Offender set is **7 sites / 5 files**, found via `grep -rnE '> ?/tmp/[A-Za-z0-9_.-]+\.(log\|txt\|json\|diff\|out)'` | **18 occurrences / 8 files.** That regex's char class `[A-Za-z0-9_.-]` **excludes `<`**, so it is blind to every `<placeholder>` form — **including `work/SKILL.md:607`, the canonical offender itself** (`/tmp/<script>.log`). It also misses `work:210`, `review:982`, `schedule:472`, `merge-pr:154-155`, `ship:1855`, `preflight:114`. | Authoritative work-list below is re-derived with a **placeholder-aware** regex. This is the single most load-bearing finding: **a guard built on the brief's suggested regex could never go red on the line that causes the class.** |
| Offender files: qa, ship, plan, preflight | **Also `review/SKILL.md:982`, `work/SKILL.md:210`, `merge-pr/SKILL.md:154-155`, `schedule/SKILL.md:472`** — four files the brief never listed. | Folded into the work-list. `review:982` is re-classified as the **highest-severity** site (see below) — it is a restore-source, not a log. |
| `.claude/logs/approvals.jsonl` + `.claude/.rule-incidents.jsonl` are "full of" ad-hoc deterministic paths | **True, but not reproducible from this worktree.** Both files are **untracked** (`git ls-files` → `tracked-count: 0`) and exist only in the main checkout. From the worktree the cited paths return **zero**. In the main checkout they are real: `/tmp/tfapply-host.log` ×6, `/tmp/fh-apply.log` ×4, `/tmp/tfapply-zot.log` ×6, ~30 distinct ad-hoc paths. | Corroboration is **directionally sound and retained as motivation**, but is **local, untracked state** → it **must not gate any AC**. No AC depends on it. (Also honors `hr-when-in-a-worktree-never-read-from-bare`: the plan prescribes no read from the bare/main checkout.) |
| 14 worktrees at session start | **16** (`git worktree list \| wc -l`). | Directional claim holds and strengthens; cited as 16. |

---

## The Core Decision — scratch mechanism

**Chosen: (a) `mktemp`, capturing the path in a variable and echoing it.**

### Why the alternatives lose — verified, not assumed

**(b) `$CLAUDE_CODE_SESSION_ID` — DISQUALIFIED.**
It *is* present in a Claude Code session (verified live: `65ab4ca8-337f-4166-a200-15417f0b8b8a`).
But `plugins/soleur/lib/harness.ts` — the harness-detection surface — resolves the harness via
`detectHarness()` with order **`CLAUDECODE` → `GROK_*` markers → process heuristics**
(`harness.ts:66-79`). It **never reads `CLAUDE_CODE_SESSION_ID`**. Under Grok Build
(`GROK_HOME`/`GROK_AGENT`/… set, `CLAUDECODE` unset), and under headless/CI, the variable is
absent → the guidance line degrades to `/tmp/-test-all.log`: **a new shared path — the same bug
wearing a disguise**, exactly as the brief warned. Adding the mandatory fallback
(`${CLAUDE_CODE_SESSION_ID:-$(mktemp -u)}`) makes it strictly more complex than `mktemp` for
zero benefit.

**(c) Harness scratchpad dir — VERIFIED MECHANICALLY UNREACHABLE.**
The brief's insight is half-right and worth honoring: the Claude Code system prompt *does*
mandate a session-scoped scratchpad and explicitly says to use it **instead of** `/tmp`. So
these skills **do** contradict standing policy. But the resolution cannot be "point at it":
`env | grep -F '65ab4ca8-337f-4166-a200-15417f0b8b8a'` returns **only `CLAUDE_CODE_SESSION_ID`** —
the session-id *component*. The scratchpad **path** itself
(`/tmp/claude-1001/<slug>/<session-id>/scratchpad`) is exposed in **no environment variable**.
It exists **only as system-prompt text**, so a SKILL.md **cannot reference it mechanically** —
there is no `$SCRATCHPAD` to write.

### Why `mktemp` wins

1. **It is already the repo's dominant convention** — this is a consistency fix, not a new
   pattern: `ship/SKILL.md:564,953,1038,1164` (`PR_BODY_FILE=$(mktemp); trap 'rm -f
   "$PR_BODY_FILE"' EXIT INT TERM`), `preflight/SKILL.md:82,94` (with `umask 077`),
   `legal-generate:54`, `incident:219`, `work:622`, and 15+ files under `scripts/`.
   `plan/SKILL.md:971` *already* prescribes the tempfile shape as a Sharp Edge.
2. **Portable with no env dependency** — works identically under Claude Code, Grok Build,
   headless, and CI. Nothing to degrade.
3. **It honors the scratchpad policy without depending on it.** `mktemp` respects `$TMPDIR`.
   `TMPDIR` is currently **UNSET** (verified) → `mktemp` falls back to `/tmp` with a *unique*
   name (safe). A harness that points `TMPDIR` at the session scratchpad gets
   scratchpad-placement **for free**, with no guidance change. This is the honest synthesis of
   option (c): mktemp is the only choice that satisfies the scratchpad policy *where it exists*
   and degrades safely *everywhere else*.

**The honest trade-off:** the path is unpredictable, so the operator cannot guess where the
log went. This is a real cost and the guidance **must** pay it explicitly — capture the path
in a variable and **echo it alongside the exit code**. Every prescribed form below does this.

### Live-verified prescribed form (Requirement 3 — intent preserved)

Run in this worktree before being written into the plan:

```bash
log=$(mktemp -t test-all.XXXXXXXX.log)
bash scripts/test-all.sh > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"
# inspect rc FIRST; only then grep/tail "$log" for context
```

Verification output (with a stub exiting 3 in place of the suite):
`mktemp -t` → `/tmp/test-all.7AJjXBez.log`; `EXIT=3 LOG=/tmp/test-all.7AJjXBez.log`.

**Both original properties hold, and the tail-masking guard is NOT regressed:**
- `rc=$?` is captured **explicitly** from the run's own process, immediately after it.
- The load-bearing exit code is **never** piped through `| tail` (which would report `tail`'s
  always-0 exit — the original bug from PR #4011).
- `EXIT=3` was preserved through the redirect, proving non-zero survives.
- **New:** `LOG=$log` is echoed, so the log is findable — paying mktemp's cost explicitly.

Prior art for the intent being preserved:
`knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`
(§1 is what `work/SKILL.md:607` implements). **Verified present** on disk.

`ship/SKILL.md:1188` already ships the correct `rc=$?; echo "EXIT=$rc"` idiom — confirming the
fix is a **path swap, not an idiom rewrite**. That is the template for every prescriptive site.

---

## Authoritative work-list (grep-enumerated, re-derived)

Command (placeholder-aware — note `<>` in the class, which the brief's regex omitted):

```bash
grep -rnoE '(>>?|&>)[[:space:]]*/tmp/[A-Za-z0-9_.<>$*{}-]+' plugins/soleur/skills/*/SKILL.md
```

Result: **18 occurrences / 8 files.** Per-file counts (verified): `work` 4, `preflight` 3,
`qa` 2, `merge-pr` 2, `ship` 2, `plan` 1, `review` 1, `schedule` 1.

A companion fenced-vs-prose classifier (`awk` fence-state machine) was run to separate
prescribed commands from prose *about* the hazard — the distinction the guard must respect.

### Class A — PRESCRIPTIVE TEMPLATE (fix; worst class)

A `<placeholder>` path is a **pure function of its input**, so every session instantiating the
template collides. These are invisible to the brief's regex.

| Site | Current | Note |
|---|---|---|
| `work/SKILL.md:607` | `bash <script> > /tmp/<script>.log 2>&1; rc=$?` | **The canonical offender — the line that CAUSES the class.** |
| `work/SKILL.md:210` | `git diff > /tmp/<task>.diff` then summarize | Second template offender in the same file. |
| `review/SKILL.md:982` | `cp <file> /tmp/<file>.bak` before the mutation loop, **restore from that copy** | **Highest severity.** Not a log — a **restore source**. Two sessions reviewing the same file (parallel review agents are routine) → one restores the **other's** backup. Silent content corruption, not a misleading log. |

### Class B — PRESCRIPTIVE LITERAL (fix)

Fixed path → every session collides.

| Site | Current |
|---|---|
| `qa/SKILL.md:46` | `> /tmp/qa-dev-server.log 2>&1 &` (log path only — see scope note) |
| `qa/SKILL.md:82` | `>/tmp/qa-pw-install.log 2>&1` |
| `ship/SKILL.md:1188` | `> /tmp/grok-pre-push-gate.log 2>&1; rc=$?; echo "EXIT=$rc"` (idiom already correct) |
| `ship/SKILL.md:1855` | `{ echo "..."; } > /tmp/follow-through-body.md` |
| `plan/SKILL.md:229` | `--json … > /tmp/open-review-issues.json` |
| `preflight/SKILL.md:373` | `… > /tmp/preflight-candidates.txt` (reads `/tmp/preflight-login.html`) |
| `preflight/SKILL.md:688` | `awk … "$PLAN_PATH" > /tmp/preflight-observability.txt` |
| `merge-pr/SKILL.md:154,155` | `git show :2:… > /tmp/changelog-ours.md`, `:3:… > /tmp/changelog-theirs.md` |
| `schedule/SKILL.md:472` | `… 2>/tmp/merge.err` |

`preflight` note: this skill **already** models the right instinct at `:34`
(`PREFLIGHT_TMP="$(git rev-parse --git-dir)"`) precisely because `.git/...` literals *"silently
broke in worktrees"* (`preflight:38`). The `/tmp/` literals at `:373`/`:688` are the same bug
class the skill already fixed one layer up — align them with the existing `PREFLIGHT_TMP`
pattern or `mktemp`, whichever the site reads more naturally.

### Class C — PROSE ABOUT THE HAZARD (do **NOT** rewrite)

These *document* the failure mode; the `/tmp` literal is the subject of the sentence, not a
prescription. Rewriting them would be noise, and they are exactly what a bare-token grep
false-matches. **→ Guard allowlist, each with a mandatory reason string.**

| Site | Why waived |
|---|---|
| `work/SKILL.md:611` | Explains the `run_in_background` + `> /tmp/log` exit-masking trap. Quoting the broken form is the point. |
| `work/SKILL.md:982` | Explains the heredoc-inside-hook-gated-`gh` trap (`cat > /tmp/body.md <<EOF`). Illustrative. |
| `preflight/SKILL.md:114` | An **edit-time, same-invocation** verification one-liner (`> /tmp/A.txt`, `> /tmp/B.txt`, `diff -u`) — written and read back by the same command. Per the brief's sharp edge, **not a defect**. |

### Sharp edge honored — not every `/tmp` use is a defect

Per the brief: a fixture written and read back by the **same command in the same invocation**
is fine. The defect is a **deterministic path that OUTLIVES the command** and is written by
**concurrent sessions**. Class C is not mass-rewritten. Total edited sites: **12 of 18** — the
diff stays small and the real fix stays legible.

---

## Scope decision — `qa/SKILL.md:46` dev server

The brief asks explicitly whether this is in scope. **Split, and here is why:**

- **IN SCOPE — the log path.** `> /tmp/qa-dev-server.log` is the same one-line defect as every
  other Class B site. Excluding it would leave a hole in the class the guard then flags.
- **OUT OF SCOPE — the port-3000 race.** Different root cause (a shared **network** resource,
  not a filesystem path), different fix (dynamic port allocation + a PID/port handshake so the
  Playwright client targets the right server), different blast radius (two dev servers, one
  wins the bind; the loser's log is *correct* and reports `EADDRINUSE`). Folding it in would
  produce a large diff with low signal-to-noise and **bury the real fix** — the brief's own
  sharp edge. **Disposition:** file a tracking issue at ship time
  (`wg-when-deferring-a-capability-create-a`). The log-path fix is strictly additive to any
  future port fix and does not conflict with it.

Note the log fix also **improves** the port situation as a side effect: with unique log paths,
a session that loses the port bind now reads *its own* `EADDRINUSE` instead of a sibling's
healthy startup log — turning a silent confusion into a legible error.

---

## The Guard

### Home: `plugins/soleur/test/scratch-path-collision.test.ts` (bun test)

**Claim verified independently, as the brief required:**
- `scripts/test-all.sh:223` runs `run_suite "plugins/soleur" bun test plugins/soleur/` —
  **whole-directory**. `plugins/soleur/test/` currently holds **46** `*.test.ts` files, all
  auto-discovered. **A `.ts` test here needs no registration.** ✅
- The `tests/scripts/` alternative would require **hand-registration**. `test-all.sh:~144-150`
  says so in its own words: *"Registered HERE because nothing auto-discovers `tests/scripts/` —
  the bash `*.test.sh` glob further down does NOT include it … Without this line the gate …
  ships with zero coverage."* The glob at `~:218` excludes the dir.

**Decision:** bun `.ts` under `plugins/soleur/test/`. It is auto-discovered (no dead-test
risk), it is where every sibling *prose-scanning* guard already lives, and it removes the
hand-registration failure mode entirely. **No `scripts/test-all.sh` edit is required** — and
because none is required, none will be made (SCOPE forbids it).

### Design

Modeled on `plugins/soleur/test/stock-preflight-coverage.test.ts` (the repo's canonical
allowlist + floor + non-vacuity guard) and `marketing-content-drift.test.ts` (prose sweep +
offender reporting). Enumerate via the shared helper
`discoverSkills()` from `plugins/soleur/test/helpers.ts` (`Glob("skills/*/SKILL.md")`), rooted
`resolve(import.meta.dir, "../../..")`.

1. **Anchor on the SYNTACTIC WRITE CONSTRUCT, never a bare token.**
   Match `(>>?|&>)\s*/tmp/<path>` — a redirect into a `/tmp` literal. A bare `/tmp` grep
   false-matches prose **and the guard's own documentation**. This exact class has bitten
   repeatedly in this repo (a `sourcesGate` satisfied by a `# shellcheck source=` **comment**;
   a ledger AC greping its own correction prose). The repo already states the principle at
   `stock-preflight-coverage.test.ts:218-228`: *"a bare token grep is useless here … Assert the
   syntactic construct instead."*

   **Live proof this class is real, observed while writing this plan:** the first write of this
   very plan file was **BLOCKED** by `.claude/hooks/iac-plan-write-guard.sh`. Its Infrastructure
   section said, in prose, that the plan contains *no* operator-SSH and *no* Doppler-write step —
   and by naming those tokens in order to negate them, it matched the hook's
   `grep -qiE '\bssh\s+(root|deploy|ubuntu|admin)@'` and `grep -qiE '\bdoppler\s+secrets\s+set\b'`.
   A guard greping bare tokens flagged a plan for a violation whose **absence** it was asserting.
   That is exactly the failure mode this guard must not reproduce.

2. **The path character class MUST include placeholder metacharacters** — `<>$*{}` alongside
   `[A-Za-z0-9_.-]`. **This is the finding that makes or breaks the guard.** With the brief's
   narrower class, `work:607` (`/tmp/<script>.log`) — *the line that causes the entire class* —
   is invisible, and the guard cannot go red on its own root cause.

3. **Allowlist:** `Map<string, string>` keyed `"<skill>/SKILL.md:<line-anchor>"` → **mandatory
   reason string**, seeded with exactly the three Class C sites. Silence is not an option: a new
   redirect must either use `mktemp` or be explicitly waived with a stated reason.

4. **Cardinality floor (anti-vacuity):** a guard that extracts zero sites passes vacuously.
   Assert `candidates.length >= MIN_SCANNED_SITES` with a `(non-vacuity)` test name (house
   convention). Set the floor from the **post-fix** count, `>=` not `==`, so the number is not
   brittle. Also assert `discoverSkills().length` is non-zero — if the glob silently returns
   nothing, every assertion below it is meaningless.

5. **Anti-rot:** mirror `stock-preflight-coverage.test.ts` — assert **no allowlist entry is
   stale** (every waived anchor still resolves to a real matching line). A waiver for a line
   that no longer exists is a lie that hides the next regression.

6. **Reporting:** collect `offenders[]`, then one `throw new Error` naming file:line, the
   offending text, **and the allowlist constant to extend** — the repo's dominant idiom.

### Mutation test (mandatory — a guard that cannot go red is worse than no guard)

Per the brief and `2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md`, mutate
**each drift class** and confirm a **clear message** prints, not just `exit 1`. Inject → confirm
RED → restore, for **all four**:

| # | Injected mutation | Must go RED because |
|---|---|---|
| M1 | `echo 'bash x > /tmp/mutant.log 2>&1' >> <a skill>` | Literal form is caught. |
| M2 | `echo 'bash x > /tmp/<mutant>.log 2>&1' >> <a skill>` | **Placeholder form is caught** — the class the brief's regex misses. Non-negotiable. |
| M3 | Delete an allowlist entry while its Class C line still exists | The allowlist is load-bearing, not decorative. |
| M4 | Point the skill glob at an empty dir | The **floor** fires (vacuity is caught). |

Restore working tree after each; confirm GREEN at the end.

### Why no new AGENTS.md rule

Measured, not assumed: `B_ALWAYS = wc -c AGENTS.md + AGENTS.core.md = **22868 / 23000** →
**132 bytes headroom**. A pointer (~50-60 B) would technically fit, but:
(a) the **test is the stronger guard** — it goes red in CI; a rule is prose that must be read
and remembered; (b) spending scarce always-loaded budget on something a test already enforces
is a poor trade; (c) `lint_union` couples pointer↔body 1:1, so the rule costs always-loaded
bytes forever. **Decision: no AGENTS rule.** The corrected guidance lives where it is already
read (the skills themselves) and is enforced mechanically.

---

## Implementation Phases

Phase order is load-bearing: the **guard's allowlist depends on which sites remain**, so the
fixes land before the guard's floor/allowlist are finalized.

### Phase 1 — Fix the cause (`work/SKILL.md`)
1. `work/SKILL.md:607` — replace `/tmp/<script>.log` with the live-verified `mktemp` form.
   **Preserve verbatim:** the `set -o pipefail` explanation, explicit `rc=$?`, the never-`| tail`
   -a-load-bearing-exit-code guard, and the `#4011` **Why**. Add `LOG=$log` to the echo.
2. `work/SKILL.md:210` — `git diff > /tmp/<task>.diff` → `d=$(mktemp -t task.XXXXXXXX.diff); git
   diff > "$d"; echo "DIFF=$d"`. Preserve the output-discipline intent (cite the path, don't
   paste the diff).
3. Leave `:611` and `:982` **untouched** (Class C).

### Phase 2 — Fix the highest-severity site (`review/SKILL.md:982`)
`cp <file> /tmp/<file>.bak` → `bak=$(mktemp -t review-bak.XXXXXXXX); cp <file> "$bak"` and
restore from `"$bak"`. Call out in the prose that the backup must be **session-unique** because
it is a **restore source** — a collision silently restores another session's content.

### Phase 3 — Sweep remaining Class B sites
`qa:46` (log path only), `qa:82`, `ship:1188`, `ship:1855`, `plan:229`, `preflight:373`,
`preflight:688`, `merge-pr:154,155`, `schedule:472`. Adopt each skill's local idiom: `mktemp`,
or `PREFLIGHT_TMP` where preflight already establishes it. Where a `trap 'rm -f …' EXIT INT
TERM` is the local convention (`ship:564`), match it.

### Phase 4 — Author the guard (RED first)
Write `plugins/soleur/test/scratch-path-collision.test.ts` per the design above. Confirm it is
**RED against pre-fix state** (`git stash` or a scratch fixture) and **GREEN after** Phases 1-3.

### Phase 5 — Mutation-test the guard
Execute M1-M4. Confirm each goes RED **with a clear, actionable message**; restore; end GREEN.

### Phase 6 — Full-suite exit gate
```bash
log=$(mktemp -t test-all.XXXXXXXX.log)
bash scripts/test-all.sh > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"
```
Inspect `rc` first, then grep `"$log"` for context. (Dogfoods the very fix this plan ships.)

---

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/skills/work/SKILL.md` | `:607` canonical fix; `:210` template fix. `:611`, `:982` untouched. |
| `plugins/soleur/skills/review/SKILL.md` | `:982` `.bak` restore-source fix. |
| `plugins/soleur/skills/qa/SKILL.md` | `:46` log path (port race scoped out); `:82`. |
| `plugins/soleur/skills/ship/SKILL.md` | `:1188`, `:1855`. |
| `plugins/soleur/skills/preflight/SKILL.md` | `:373`, `:688`. `:114` untouched (Class C). |
| `plugins/soleur/skills/plan/SKILL.md` | `:229`. |
| `plugins/soleur/skills/merge-pr/SKILL.md` | `:154`, `:155`. |
| `plugins/soleur/skills/schedule/SKILL.md` | `:472`. |

## Files to Create

| File | Purpose |
|---|---|
| `plugins/soleur/test/scratch-path-collision.test.ts` | The guard. Auto-discovered by `test-all.sh:223`; **no registration needed**. |

**Explicitly NOT edited:** `scripts/test-all.sh` (clean, and no registration required — verified),
and no product code.

---

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — Cause fixed.** `grep -c '/tmp/<script>.log' plugins/soleur/skills/work/SKILL.md` → `0`.
2. **AC2 — Intent preserved (tail-masking NOT regressed).** The rewritten `work/SKILL.md:607`
   bullet still contains **all** of: `pipefail`, `rc=$?`, and the `#4011` **Why** citation.
   Verify: the bullet matches `rc=\$\?` **and** `pipefail` **and** `4011`.
3. **AC3 — No `| tail` on a load-bearing exit code** is introduced by any edited line.
4. **AC4 — Path is echoed.** Every prescriptive `mktemp` form introduced echoes its path
   (`LOG=`/`DIFF=`/equivalent) so the operator can find the artifact — mktemp's cost is paid.
5. **AC5 — Class A+B swept.** The placeholder-aware regex
   `(>>?|&>)[[:space:]]*/tmp/[A-Za-z0-9_.<>$*{}-]+` over `plugins/soleur/skills/*/SKILL.md`
   returns **only** the 3 allowlisted Class C anchors (`work:611`, `work:982`, `preflight:114`)
   — i.e. **4 occurrences** (preflight:114 carries two: `/tmp/A.txt`, `/tmp/B.txt`).
   *Derivation:* 18 total − 14 occurrences across the 12 fixed sites = 4 remaining.
   The **guard itself is the canonical assertion**; this AC is the human-readable form.
6. **AC6 — Guard is red on the cause.** With `work/SKILL.md:607` reverted to its pre-fix text,
   `bun test plugins/soleur/test/scratch-path-collision.test.ts` **FAILS** and names
   `work/SKILL.md:607`. *(This is the AC the brief's own regex would have made unsatisfiable.)*
7. **AC7 — Mutation matrix.** M1-M4 each produce a **RED with a clear message**; tree restored;
   final state GREEN. Evidence pasted in the PR body.
8. **AC8 — Non-vacuity floor.** The guard asserts `discoverSkills().length > 0` **and**
   `candidates.length >= MIN_SCANNED_SITES` (`>=`, not `==`). Deleting all skills, or pointing
   the glob at an empty dir, makes it **FAIL**, not pass.
9. **AC9 — Allowlist states the truth.** Every allowlist entry carries a non-empty reason string
   and resolves to a real matching line (no stale waivers).
10. **AC10 — Guard is auto-discovered (ships live, not dead).**
    `bun test plugins/soleur/` includes `scratch-path-collision` in its run, with **no** edit to
    `scripts/test-all.sh`.
11. **AC11 — Full suite green.** `test-all.sh` `EXIT=0`, captured via a `mktemp` path per the
    new guidance.
12. **AC12 — Scope respected.** `git diff --name-only origin/main...HEAD` contains **no**
    product-code paths, **no** `scripts/test-all.sh`, and touches only the 8 SKILL.md files, the
    new test, and `knowledge-base/project/{plans,specs}/`.

### Post-merge (operator)

None. Everything is verifiable pre-merge in CI.
*(Automation note: the deferred qa port-3000 race is filed as a tracking issue by `/ship`, not
executed by a human.)*

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. This is agent-facing
guidance plus one CI test. The realistic failure is a **guard that cannot go red** (the exact
trap the brief names) — which would leave the class silently un-enforced. AC6 + the M1-M4
mutation matrix exist specifically to make that failure impossible to ship.

**If this leaks, the user's data/workflow/money is exposed via:** no exposure vector. No
regulated data, no secrets, no network surface, no PII. The change **reduces** cross-session
information bleed (one session's output landing in another's file), and `review:982`'s fix
removes a cross-session **content-corruption** vector.

**Brand-survival threshold:** `none` — no user-facing surface, no data path.
**Reason (required for `none`):** the diff touches only agent-facing markdown prose and one
CI-only test file; it reaches no sensitive path (no schema, migration, auth flow, API route, or
`.sql`), no runtime, and no user data.

---

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal engineering tooling/guidance change. No UI
surface (`Files to Create`/`Files to Edit` contain no `components/**/*.tsx`, `app/**/page.tsx`,
or `app/**/layout.tsx` → the mechanical UI-surface override does not fire; Product/UX Gate
skipped correctly). No product, marketing, legal, finance, sales, or support surface.

## GDPR / Compliance Gate

**Skipped — no regulated-data surface.** The diff touches no schema, migration, auth flow, API
route, or `.sql` file. None of the expansion triggers fire: (a) no LLM/external-API processing
of operator data is added; (b) brand-survival threshold is `none`, not `single-user incident`;
(c) no new cron/workflow reading `learnings/` or `specs/`; (d) no new artifact-distribution
surface.

## Infrastructure (IaC)

**Skipped — this plan introduces no infrastructure.** Phase 2.8's detection classes were each
checked against the plan body and none fire: no remote-shell provisioning step, no secret-manager
**write** (no secret is created or mutated; none is even read), no service-manager unit or
first-boot config, no scheduled-job registration, no vendor console/click-path, and no new vendor
account. The change is confined to agent-facing markdown under `plugins/soleur/skills/` plus one
CI test file under `plugins/soleur/test/`. There is no server, DNS record, TLS cert, firewall
rule, or monitoring webhook in scope, so there is no Terraform root to extend and no apply path.

> **Note for reviewers:** this section is deliberately written *without* reproducing the
> guard's literal trigger tokens. Naming them — even to assert their absence — false-matches
> `.claude/hooks/iac-plan-write-guard.sh` (it greps bare tokens, case-insensitively). The
> sanctioned `iac-routing-ack` opt-out was **not** used: it emits a `bypass` telemetry event,
> and recording a bypass for a plan with zero infrastructure would pollute the incident log
> with a false positive. Rewriting the prose is the honest fix. This episode is cited as live
> evidence in **The Guard → §1**.

## Observability

**Skipped — pure-docs + a CI test.** `Files to Edit` contains no file under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface (the
Phase 2.8 trigger set does not fire). The new file is `plugins/soleur/test/*.test.ts` — a CI
test, not a runtime surface. There is no error path, log call, or failure mode to route to
Sentry/Better Stack.

*(Note: the guard's own "liveness" — the risk it ships dead — is the real analogue here, and it
is covered structurally by AC10 (auto-discovery, no registration) and AC8 (non-vacuity floor)
rather than by runtime telemetry.)*

## Architecture Decision (ADR/C4)

**No ADR required.** This is a workflow/tooling convention fix enforced by a test — not an
architectural decision about the product system. It moves no ownership/tenancy boundary,
introduces no substrate or integration pattern, changes no resolver/dispatch/trust boundary,
and reverses no existing ADR. A competent engineer reading the existing ADRs + C4 would **not**
be misled about the system after this ships.

**No C4 impact — enumeration cited (per the completeness mandate).** All three model files were
read: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Checked,
and found nothing added or falsified:
- **(a) External human actors** — none added. No correspondent, reviewer, or end recipient
  enters the system; the only human is the operator, already modeled.
- **(b) External systems / vendors** — none added. No inbound webhook, outbound API, or
  third-party store. `mktemp` is a coreutil on the local filesystem.
- **(c) Containers / data stores** — none touched. `/tmp` scratch is **ephemeral local
  process-scratch**, not a modeled data store, and was not modeled before this change either.
- **(d) Actor↔surface access relationships** — unchanged. No sharing/ownership semantics move;
  no element description is falsified by this diff.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` → **62** open issues;
each of the 9 candidate paths was matched against issue bodies via standalone `jq --arg`.

- **#4133** — *follow-through(#4116): Schema parity test for `## Observability` block* — touches
  `skills/plan/SKILL.md`. **Disposition: Acknowledge.** Different concern: #4133 governs the
  Observability block's **schema**; this plan edits `plan/SKILL.md:229`, an unrelated scratch
  path in the code-review-overlap step. No shared lines, no fold-in value, no conflict. #4133
  remains open.

No other overlaps across `work`, `qa`, `ship`, `preflight`, `review`, `merge-pr`, `schedule`
SKILL.md, or `scripts/test-all.sh`.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Guard can't go red on its own root cause** — the brief's suggested regex excludes `<`, making `work:607` invisible. | Placeholder-aware char class `[A-Za-z0-9_.<>$*{}-]`; **AC6** asserts RED on the reverted cause; **M2** mutation-tests the placeholder form specifically. |
| **Guard passes vacuously** (glob returns zero). | Cardinality floor + `discoverSkills().length > 0`, `(non-vacuity)` test; **M4** proves it fires. |
| **Bare-token grep false-matches prose / the guard's own docs.** | Anchor on the syntactic redirect construct; 3 Class C sites explicitly allowlisted with reasons; repo precedent `stock-preflight-coverage.test.ts:218-228`; **plus the live `iac-plan-write-guard.sh` episode above as a worked example of the failure.** |
| **Guard ships dead** (unregistered). | Home is `plugins/soleur/test/*.ts`, auto-discovered by `test-all.sh:223` (verified: 46 siblings). **AC10** asserts it runs with no `test-all.sh` edit. |
| **Tail-masking guard regressed while fixing the path.** | **AC2** asserts `pipefail` + `rc=$?` + `#4011` all survive; **AC3** forbids new `\| tail` on a load-bearing exit; the form was **live-verified** to preserve `EXIT=3`. |
| **mktemp's unpredictable path hides the log from the operator.** | Every prescribed form echoes `LOG=$log` / `DIFF=$d`; **AC4** enforces it. |
| **Over-broad rewrite buries the real fix.** | Class C excluded by construction; 12 of 18 occurrences edited; scope note for the qa port race. |
| **Allowlist rots** into a permanent silent waiver. | Anti-rot test: every entry must resolve to a real line and carry a reason (`stock-preflight-coverage` precedent); **AC9**. |
| **Litter:** mktemp files accumulate in `/tmp`. | Match the local `trap 'rm -f "$f"' EXIT INT TERM` convention (`ship:564`) where the site is a short-lived fixture. Long-lived logs (test-all, dev server) are deliberately **kept** — they are the diagnostic artifact — and `/tmp` is tmpfs-cleared on reboot. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is
  `none` **with the mandatory non-empty reason** (required because `none` must justify itself).
- **Do not "fix" this by telling the operator to avoid parallel sessions.** Parallel worktrees
  are the documented, intended workflow (16 live at session start). Any proposed change that
  serializes sessions is out of scope and wrong.
- **`work:607` is invisible to the obvious regex.** Anyone re-deriving this work-list with
  `[A-Za-z0-9_.-]` will conclude the canonical offender is already fixed. Always include the
  placeholder metacharacters.
- **`review:982` is not a log.** It is a **restore source**. Reviewers may pattern-match it to
  the log sites and wave it through as low-severity; it is the opposite — a collision there
  silently restores another session's file content.
- **`preflight:114` is a decoy.** It looks like two Class B violations (`/tmp/A.txt`,
  `/tmp/B.txt`) but is a same-invocation write-then-read verification one-liner. Allowlist it;
  do not rewrite it.
- **Writing this plan's own "no infrastructure" section trips `iac-plan-write-guard.sh`** if you
  name its trigger tokens to negate them. Describe the classes abstractly. Do **not** reach for
  the `iac-routing-ack` opt-out — it records a `bypass` incident, which is false for a plan with
  no infrastructure.
- The corroborating `.claude/logs/approvals.jsonl` / `.claude/.rule-incidents.jsonl` evidence is
  **untracked, main-checkout-only** state. It is real (verified: `/tmp/tfapply-host.log` ×6,
  `/tmp/fh-apply.log` ×4) but **not reproducible from a worktree or a fresh clone** — never let
  an AC depend on it, and do not read it from the bare repo during `/work`
  (`hr-when-in-a-worktree-never-read-from-bare`).
