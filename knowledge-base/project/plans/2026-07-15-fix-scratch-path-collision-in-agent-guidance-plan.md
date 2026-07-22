---
type: fix
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
date: 2026-07-15
branch: feat-one-shot-scratch-path-collision
---

# fix: Collision-free scratch paths in agent-facing guidance

> **Revision note (post-deepen-plan).** v1 of this plan anchored its enumeration and its guard on
> **redirect syntax** (`> /tmp/…`). A 5-agent review panel proved that is the *same class of error*
> v1 faults the brief for: it widened the *character class* but left the *construct anchor* narrow,
> so it missed every `-o` / `cp` write, and flagged its own "highest-severity" site **by accident**.
> v2 re-anchors on the **hazard** (a deterministic `/tmp` path that outlives the command), which
> changes the work-list (8 → 9 files), the guard's regex, and the ADR call. See
> §Research Reconciliation.

## Overview

Soleur's agent-facing guidance prescribes **deterministic** `/tmp` paths for capturing command
output. The prescribed path is a pure function of a script name (or a `<placeholder>` template),
so every concurrent session following the guidance writes to the **same file by construction**.
Parallel worktrees are the documented, intended workflow (**16** live at this session's start),
so sessions silently truncate (`>`) and interleave each other's output.

The failure is **not** a lost log. It is a **false signal on load-bearing pass/fail evidence**:
the log you read to learn *which* suite failed may belong to another session. The benign
direction costs a ~10-minute re-run. The dangerous inverse — reading a sibling's GREEN log and
concluding your own run passed — chains a false PASS into ship.

`scripts/test-all.sh` is **not** at fault (verified: `grep -nE '/tmp/|mktemp|TMPDIR'` exits 1,
zero hits). This is a defect in the **prose that tells agents how to capture output** — guidance
that shapes every future session. **The guard matters more than the individual edits.**

**Docs + one test + one ADR amendment. No product code.**

---

## Research Reconciliation

Every claim was re-run. Divergences from the brief **and from this plan's own v1**:

| Claim | Reality (verified) | Response |
|---|---|---|
| *(brief)* Offenders = 7 sites / 5 files via `grep -rnE '> ?/tmp/[A-Za-z0-9_.-]+\.(log\|txt\|json\|diff\|out)'` | The char class excludes `<`, so it is blind to every `<placeholder>` form — **including `work:607`, the canonical offender itself**. | Re-derived. **A guard on the brief's regex could never go red on its own root cause.** |
| *(v1 of this plan)* Offenders = 18 occurrences / 8 files via a redirect anchor | **Wrong in the same way, one level up.** A redirect anchor is blind to `-o`, `--output`, `cp`, `tee`, `unzip -d`. Missed: `preflight:369` (`curl -o /tmp/preflight-login.html`), `preflight:395`, `rclone:29` — **`rclone/SKILL.md` is a 9th file v1 never considered.** | **v2 anchors on the hazard, not the syntax.** Work-list below. |
| *(v1)* `review:982` is caught by the guard | **It matches by accident.** The construct is `cp <file> /tmp/<file>.bak` — `cp SRC DEST`, no redirect. The `>` v1 anchored on is `<file>`'s **closing bracket**. Verified: normalising to `cp "$f" /tmp/backup.bak` → guard returns **0**. | The plan's self-declared highest-severity site was protected by a coincidence. Fixed by the semantic anchor + fixture M5. |
| *(v1)* `preflight:373` is a standalone fix | `:369` **writes** `/tmp/preflight-login.html` via `curl -o`; `:373` **reads** it. v1 fixed only `:373` → session A's curl clobbers B's HTML between B's curl and B's grep, and B greps A's HTML **into a uniquely-named file**. **Strictly worse than today** — corruption wearing a private-looking filename. | **`:369` and `:373` are one atomic unit.** Fix both or neither. |
| *(v1)* `ux-audit` has 5 `/tmp` hits | **All 5 are `${GITHUB_WORKSPACE}/tmp/ux-audit/…` — already compliant.** A bare `/tmp/` pattern matched them as a **substring**. | **The guard must anchor `/tmp/` at a path boundary** or it false-flags the repo's own workspace-scoping precedent. `ux-audit` is out of the work-list. |
| *(v1)* `harness.ts` never reads `CLAUDE_CODE_SESSION_ID`, therefore (b) fails | True but a **non-sequitur** — `harness.ts` is a display/routing formatter; what *it* reads says nothing about shell env. And the implied "nothing reads it" is **false**: `compound/scripts/token-efficiency-report.sh:46` does. | (b) still fails, for the **portability** reason (below). Argument rebuilt; that same file supplies the best in-repo precedent. |
| *(brief)* `approvals.jsonl` / `.rule-incidents.jsonl` are full of ad-hoc paths | **True but untracked and main-checkout-only** (`git ls-files` → 0). Real there: `/tmp/tfapply-host.log` ×6, `/tmp/fh-apply.log` ×4, ~30 distinct paths. | Retained as motivation; **gates no AC**. Also drives the layering note below (this population is agent-improvised at *runtime* — no SKILL.md scan can ever catch it). |
| *(brief)* 14 worktrees | **16.** | Cited as 16. |
| *(v1)* No ADR required | **Wrong.** `ADR-009-git-worktree-isolation:20` claims *"Clean parallel development with **full isolation**."* This plan's thesis is that isolation **leaks through `/tmp`**. A competent engineer reading ADR-009 today **would** be misled on exactly this point. | **ADR-009 consequence amendment is an in-scope deliverable** (see §Architecture Decision). |

---

## The Core Decision — scratch mechanism

**Chosen: `mktemp` as the default, with an explicit criterion for the one alternative.**

### Why (b) `$CLAUDE_CODE_SESSION_ID` fails — portability, not `harness.ts`

It is present in a Claude Code session (verified: `65ab4ca8-…`). It is simply **a Claude Code
variable**: absent under Grok Build, headless, and CI. A guidance line depending on it degrades
to `/tmp/-test-all.log` — **a new shared path, the same bug in disguise**. With the mandatory
fallback (`${CLAUDE_CODE_SESSION_ID:-$(mktemp -u)}`) it is strictly more complex than `mktemp`
for zero benefit. *(No `harness.ts` citation: that file is a display formatter and proves
nothing here.)*

### Why (c) the harness scratchpad fails — not mechanically reachable

The standing Claude Code system prompt **does** mandate a session scratchpad and says to use it
**instead of** `/tmp` — so these skills genuinely contradict standing policy. But the resolution
cannot be "point at it": `env | grep -F '<session-id>'` returns **only
`CLAUDE_CODE_SESSION_ID`**; the scratchpad **path** is in no environment variable. It is
prompt text. A SKILL.md cannot write `> $SCRATCHPAD/x` — there is no such variable. (It is
*derivable* from the session id + a cwd slug, but that is brittle and Claude-only — the same
portability failure as (b).)

### Why `mktemp` — and the in-repo precedent that already litigated this

`compound/scripts/token-efficiency-report.sh` is the strongest precedent, and it argued this
exact thesis first: `:53` `TE_TMPDIR="${TE_TMPDIR:-$(mktemp -d)}"` with a `trap … EXIT INT TERM`
at `:54`, and `:36-39` documents **rejecting `$$`** because it is *"predictable across concurrent
runs in shared shells."* That is this plan's thesis, already decided in-repo.

`mktemp` is also the dominant convention: `ship:564,953,1038,1164`; `preflight:82,94` (with
`umask 077`); `legal-generate:54`; `incident:219`; `work:622`; 15+ files under `scripts/`.
`plan:971` already prescribes the tempfile shape as a Sharp Edge. Verified `0600` + `O_EXCL` +
unpredictable name → also closes the **symlink-clobber** class that `preflight:34-40` names.

**Honest cost:** the path is unguessable, so guidance **must** capture it in a variable and
**echo it**. Every prescribed form below does. A sharper cost the reviews surfaced: the Bash tool
does **not** persist shell state across calls (`work:609` documents this), so `log=$(mktemp)` in
call *N* is unrecoverable in call *N+1* except via the echoed literal. That is a real ergonomic
regression from a deterministic path, and it is what the criterion below exists to bound.

### The criterion (replaces v1's "whichever reads more naturally")

Two compliant mechanisms already exist in this repo. They are **not** competitors; they split on
**which concurrency domain collides**:

| Mechanism | Isolates across worktrees | Isolates *within* one worktree | Findable in a later Bash call |
|---|---|---|---|
| `$(git rev-parse --git-dir)/x` (`preflight:34`) | yes | **no** | **yes** |
| `${GITHUB_WORKSPACE}/tmp/…` (`ux-audit:75-124`) | yes | **no** | **yes** |
| `mktemp` | yes | **yes** | no (var only) |

> **Rule:** use `mktemp` when the artifact is consumed **within one Bash call**, or when
> concurrent agents share **one worktree**. Use a **git-dir / workspace-scoped** path when a
> **later, separate** call must locate the artifact **by name**.

`review:982` is the case that **refutes global git-dir adoption**: parallel review agents run in
the *same* worktree (`review:981` says so), so a git-dir-scoped `.bak` collides precisely where
severity is highest. Only `mktemp` isolates there.

**The guard enforces the invariant, not the mechanism** — it flags a deterministic `/tmp` path
and matches neither `"$log"` nor `"$PREFLIGHT_TMP/x"` nor `${GITHUB_WORKSPACE}/tmp/x`. Correct
coupling.

### `TMPDIR` — what is actually true

`mktemp` respects `$TMPDIR`. `TMPDIR` is **UNSET**, and **no harness sets it**. So today `mktemp`
lands in `/tmp` with a unique name: safe, but **not** in the scratchpad. v1 claimed this "honors
the scratchpad policy"; it does not — it *fails to violate it loudly*. Stated honestly here.
`.claude/settings.json` has an `env` block the repo controls, so pointing `TMPDIR` at a
gitignored repo-local scratch dir would make the synthesis real — **filed as follow-up, not
assumed** (needs verification that the harness applies `settings.json` `env` to Bash calls).

### Live-verified prescribed form (intent preserved)

```bash
log=$(mktemp -t test-all.XXXXXXXX.log)
bash scripts/test-all.sh > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"
# inspect rc FIRST; only then grep/tail "$log"
```

Verified live (stub exiting 3): `mktemp -t` → `/tmp/test-all.7AJjXBez.log`; output
`EXIT=3 LOG=/tmp/test-all.7AJjXBez.log`. **`rc` is captured explicitly from the run's own
process; the load-bearing exit is never piped through `| tail`** (the PR #4011 bug the line
exists to prevent); `EXIT=3` survived the redirect; `LOG=` pays mktemp's cost. Prior art:
`knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`
§1 (verified present). `ship:1188` already ships the correct `rc=$?` idiom → the fix is a
**path swap, not an idiom rewrite**.

---

## Authoritative work-list (hazard-anchored)

**Hazard:** a *deterministic* `/tmp` path (literal or `<placeholder>`) that **outlives the
command** and is written by **concurrent sessions**. Enumerated by write **semantics**
(redirect | `-o`/`--output` | `cp`/`mv`/`tee`/`unzip -d`), with `/tmp/` anchored at a **path
boundary** so `${GITHUB_WORKSPACE}/tmp/…` does not false-match.

### FIX — **18 occurrences / 16 lines / 9 files**

> **Do not be fooled by the coincidence:** v1 also reported "18", but that was a *different set*.
> v1's 18 = redirect-shaped matches **including** the 4 later waived, and **excluding**
> `preflight:369`, `preflight:395`, and `rclone:29` (×2). v2's 18 = the **fix set**, waivers
> already removed. Overlap is partial; the number is a collision, not a confirmation.
> Verified by explicit enumeration (per-line counts below sum to 18).

| Site | Construct | Note |
|---|---|---|
| `work:607` | redirect, template `/tmp/<script>.log` | **THE CAUSE.** Invisible to the brief's regex. |
| `work:210` | redirect, template `/tmp/<task>.diff` | Second template offender. |
| `review:982` | **`cp <file> /tmp/<file>.bak`** | **Highest severity — a *restore source*, not a log.** Two same-worktree review agents → one restores the **other's** content. Silent corruption. **Not a redirect** — v1's guard caught it by accident. |
| `preflight:369` | **`curl -o /tmp/preflight-login.html`** | **Atomic with `:373`** — writes what `:373` reads. Fixing `:373` alone is a **net regression**. |
| `preflight:373` | redirect → `/tmp/preflight-candidates.txt` | Atomic with `:369`. |
| `preflight:395` | **`curl -o "/tmp/preflight-chunks/${base}"`** | Missed by v1. |
| `preflight:688` | redirect → `/tmp/preflight-observability.txt` | |
| `qa:46` (**×2**) | redirect → `/tmp/qa-dev-server.log` | **Two occurrences on one line** (Doppler + no-Doppler branches). Fixing one leaves the other. Log path only — port race scoped out. |
| `qa:82` | redirect → `/tmp/qa-pw-install.log` | |
| `ship:1188` | redirect → `/tmp/grok-pre-push-gate.log` | `rc=$?` idiom already correct. |
| `ship:1855` | redirect → `/tmp/follow-through-body.md` | |
| `plan:229` | redirect → `/tmp/open-review-issues.json` | |
| `merge-pr:154`, `:155` | redirects → changelog ours/theirs | |
| `schedule:472` | redirect → `2>/tmp/merge.err` | |
| `rclone:29` | **`-o /tmp/rclone.zip` + `unzip -d /tmp` + `cp /tmp/rclone-*/rclone`** | **9th file — v1 never saw it.** |

Apply the **criterion**: `preflight:369/373/395/688` → `PREFLIGHT_TMP` (that skill already
establishes the cross-step cache at `:34`, and `:373`/`:688` are read by later calls). All
others → `mktemp`. Match the local `trap 'rm -f "$f"' EXIT INT TERM` convention (`ship:564`)
where the artifact is transient.

### WAIVE — Class C, prose *about* the hazard (allowlist, with honest reasons)

| Site | Reason string (mandatory) |
|---|---|
| `work:611` | Quotes the broken `> /tmp/log` form to explain the bg-exit-masking trap. Quoting it **is** the point. |
| `work:982` | Quotes `cat > /tmp/body.md <<EOF` to explain the hook-gated-heredoc trap. |
| `preflight:114` (×2) | Same-invocation `&&` chain (`> /tmp/A.txt && … > /tmp/B.txt && diff -u`). **Reason must read: "narrow race window, self-limiting, accepted"** — **not** "not a defect." Two concurrent preflights *can* interleave (fixed names); session 1's `diff -u` can read session 2's `A.txt`. Only the blast radius differs (a wrong diff at edit time, human-visible). *A waiver that misstates its justification is how the next reader talks themselves into a bad one.* |
| `frontend-anti-slop:76` | `"screenshot_ref": "/tmp/anti-slop/no-screenshot.png"` — a JSON **example value** in a schema sample, not a write. Classify at /work; waive with this reason or fix if it turns out to be prescriptive. |

### ALREADY COMPLIANT — must **not** be flagged

`ux-audit:75,77,122,124` (+1) — all `${GITHUB_WORKSPACE}/tmp/ux-audit/…`. Workspace-scoped, per
the criterion. This is the **false-positive** case the guard must stay green on (fixture M6).

### Known blind spots (stated, not hidden)

- `plugins/soleur/skills/incident/scripts/dry-run.sh:9` — `> /tmp/pir-dry-run.txt`. Same class,
  **outside** the guard's `skills/*/SKILL.md` glob. Out of scope; **follow-up issue** so the
  guard's "clean" is not mistaken for the class being dead one directory over.
- The `~30 ad-hoc paths` in `approvals.jsonl` are **agent-improvised at runtime**, instantiated
  from no SKILL.md. **No SKILL.md scan can ever catch them** — see §The Guard → *Layering*.

---

## Scope decision — `qa:46` dev server

- **IN — the log path** (both occurrences). Same one-line defect as every Class B site.
- **OUT — the port-3000 race.** Different root cause (a shared **network** resource), different
  fix (dynamic port + PID/port handshake), different blast radius. Folding it in buries the real
  fix. **Filed P3** at ship (`deferred-scope-out`, `domain/engineering`, `priority/p3-low` — all
  four labels verified to exist; no duplicate issue found).
- The split is **forced by the guard**, not a preference: the guard flags `qa:46` regardless, so
  scoping the log out would require an allowlist entry whose reason would be a lie ("port race
  deferred" does not make the log path safe).
- Side effect: unique logs **downgrade** the race from silent to legible — a session losing the
  bind now reads *its own* `EADDRINUSE` instead of a sibling's healthy startup log.

---

## The Guard

### Home: `plugins/soleur/test/scratch-path-collision.test.ts` (bun test)

Verified independently: `test-all.sh:223` runs `run_suite "plugins/soleur" bun test
plugins/soleur/` — **whole-directory**; 46 flat (55 recursive) sibling `.test.ts` files are
auto-discovered with **no registration**. The `tests/scripts/` alternative needs
hand-registration — `test-all.sh:145-150` says so verbatim: *"Registered HERE because nothing
auto-discovers `tests/scripts/` … Without this line the gate … ships with zero coverage."*
**No `scripts/test-all.sh` edit is required, so none will be made.**

### Layering — what this guard does and does not cover

It is the right gate for **guidance shape**. It is **not** the gate for the observed runtime
population (agent-improvised paths), which is instantiated from no skill file. The repo has
already made this argument: `.claude/hooks/background-poll-prefer-monitor.sh:8-12` — *"that gate
is prose, scoped to ship's code path … This hook is the only enforcement independent of which
skills load."* A PreToolUse `Bash` hook is the layer matching the runtime harm.
**Out of scope here** (larger, riskier surface) → **follow-up issue**. Consequently this plan
claims only that the test is stronger **than an AGENTS.md rule**, not stronger than all
alternatives.

### Design

Enumerate via `discoverSkills()` from `plugins/soleur/test/helpers.ts`.

1. **Root at `PLUGIN_ROOT`, not `REPO_ROOT`.** `helpers.ts:6` sets `PLUGIN_ROOT =
   resolve(import.meta.dir, "..")` → `plugins/soleur`, and `discoverSkills()` returns paths
   **relative to it** (`skills/work/SKILL.md`). Resolving those against `REPO_ROOT` → **ENOENT**.
   (`stock-preflight-coverage.test.ts:46` uses `REPO_ROOT` correctly *for its own purpose* —
   copying that line here is a bug.)

2. **Anchor on the HAZARD via write-verb alternations — never let `>` do double duty.**
   v1's `(>>?|&>)\s*/tmp/…` collides with rule 3: `>` is *both* the redirect token *and*
   `<placeholder>`'s closing bracket. That is why `review:982` matched by accident. Match
   **separate alternations**:
   - redirect: `(>>?|&>|2>)\s*<path>`
   - flag: `(-o|--output)\s+"?<path>`
   - verb: `\b(cp|mv|tee|install)\b[^|]*\s"?<path>` and `unzip\b[^|]*-d\s+"?<path>`

3. **`<path>` = `/tmp/` at a path boundary + a class including placeholder metacharacters.**
   - Boundary `(^|[\s"'=])` — else `${GITHUB_WORKSPACE}/tmp/x` false-matches as a **substring**
     (verified: naive → 1 match, boundary-anchored → 0, while still catching real offenders).
   - Class `[A-Za-z0-9_.<>${}*/-]` — **without `<>` the guard cannot see `work:607`, its own root
     cause.**
   - Subtract compliant forms: a path whose first segment is a variable (`"$log"`,
     `"$PREFLIGHT_TMP/x"`, `${GITHUB_WORKSPACE}/tmp/x`) is **not** a hazard.

4. **Extract the detector as a pure function + pin it with committed fixtures.**
   **Highest-severity design item.** Verified: after the fix, the only survivors are
   `work:611` (`> /tmp/log`), `work:982` (`> /tmp/body.md`), `preflight:114` (`> /tmp/A.txt`,
   `> /tmp/B.txt`) — and **all are matched by the *narrow* class too**. So `<>$*{}` would be
   load-bearing for **zero committed assertions**: someone "simplifies" the class back, the floor
   passes, anti-rot passes, offenders is empty → **GREEN, guard blind to Class A**. A one-shot
   mutation ritual cannot prevent that. Export `findHazards(text): string[]` and pin every axis
   with **synthesized inline fixtures** (honors `cq-test-fixtures-synthesized-only`):

   ```ts
   // RED axes — each must be found
   expect(findHazards('bash x > /tmp/<mutant>.log 2>&1')).toHaveLength(1);   // M2 placeholder
   expect(findHazards('bash x > /tmp/mutant.log 2>&1')).toHaveLength(1);     // M1 literal
   expect(findHazards('cp somefile /tmp/fixed.bak')).toHaveLength(1);        // M5 cp-DEST (no redirect!)
   expect(findHazards('curl -o /tmp/fixed.html https://x')).toHaveLength(1); // M7 -o flag
   // GREEN axes — each must stay silent
   expect(findHazards('log=$(mktemp); bash x > "$log" 2>&1')).toEqual([]);
   expect(findHazards('cat "$PREFLIGHT_TMP/x.txt"')).toEqual([]);
   expect(findHazards('png to ${GITHUB_WORKSPACE}/tmp/ux-audit/a.png')).toEqual([]);  // M6
   expect(findHazards('the log lands in /tmp/foo.log — never do this')).toEqual([]);  // prose
   ```

   This converts the plan's two most important claims from rituals into permanent gates, and
   pins the green side so the guard cannot decay into a bare-token grep.

5. **Allowlist: content-addressed, NOT line-numbered.** Key on `(file, exact offending text)` +
   a **mandatory reason string**. Line keys fail twice here: (a) *churn* — Phases 1-2 edit
   `work:210`/`:607`, **shifting** 611 and 982, reddening a correct implementation; (b)
   *inherited waiver* — a waiver keyed to a **position** silently absolves whatever later
   occupies that line, and anti-rot still passes. `stock-preflight-coverage.test.ts:58-93` keys
   by **option name** — borrow the property, not just the shape.

6. **Non-vacuity: `discoverSkills().length > 0` + anti-rot. Drop `MIN_SCANNED_SITES`.**
   Post-fix the detector matches exactly the allowlisted anchors, so "every waiver resolves"
   **strictly implies** any floor over them. Three mechanisms for one property is two too many.

7. **Reporting:** collect `offenders[]` → one `throw` naming file:line, the text, **and the
   constant to extend** (house idiom).

8. **Header comment** per `stock-preflight-coverage.test.ts:1-38`: what it prevents, why (issue
   refs), and a **DOCUMENTED LIMITATIONS** block naming: the `skills/*/SKILL.md` glob (misses
   `incident/scripts/dry-run.sh`), the runtime-improvised population (needs the hook layer), and
   the deliberate no-fence-awareness choice (explicit waiver beats silent skip; allowlist growth
   is the accepted long-run rot vector).

### Mutation matrix — fixture-driven, not file-mutating

**v1's `echo '…' >> <a skill>` → confirm RED → restore ritual is rejected.** It would run in a
worktree carrying ~15 uncommitted SKILL.md edits — the `review:982` clobber class this very plan
calls highest-severity — and its deliverable was prose in a PR body, which enforces nothing on
the next contributor. All axes above are **committed `expect()` calls** (M1/M2/M5/M6/M7 + prose).
Two remain as one-shot checks because they exercise the harness, not the detector:

| # | Check | Proves |
|---|---|---|
| M3 | Delete an allowlist entry whose Class C text still exists → RED | The allowlist is load-bearing. |
| M4 | Point the skill glob at an empty dir → RED | Vacuity is caught. |

Run M3/M4 against **a scratch copy**, never the working tree. **Do not `git stash`** —
`hr-never-git-stash-in-worktrees` is **hook-enforced** (`guardrails.sh
guardrails:block-stash-in-worktrees`); the rule's own body gives the tool: `git show
<commit>:<path>`.

### Why no new AGENTS.md rule

Measured: `B_ALWAYS = 22868 / 23000` → **132 bytes headroom**. A pointer (~55 B) would fit, but
the test goes red in CI while a rule is prose that must be remembered, and `lint_union` couples
pointer↔body 1:1 so the cost is permanent. **No AGENTS rule.**

---

## Implementation Phases

Phase order is load-bearing: fixes precede the guard's allowlist/floor.

**Phase 0 — Preconditions.** Re-run the hazard enumeration (expect **18 occurrences / 16 lines /
9 files** to fix, 5 to waive, `ux-audit` compliant). Confirm `test-all.sh` clean and `:223`
whole-directory. Read `stock-preflight-coverage.test.ts` + `helpers.ts`.

**Phase 1 — Fix the cause (`work`).** `:607` → the live-verified `mktemp` form, **preserving
verbatim** the `pipefail` explanation, explicit `rc=$?`, the never-`| tail` guard, and the
`#4011` **Why**; add `LOG=$log`. `:210` → `d=$(mktemp -t task.XXXXXXXX.diff); git diff > "$d";
echo "DIFF=$d"`. Leave `:611`/`:982` untouched.

**Phase 2 — Highest severity (`review:982`).** → `bak=$(mktemp -t review-bak.XXXXXXXX); cp <file>
"$bak"`; restore from `"$bak"`. State **why** it must be session-unique: it is a **restore
source**, and parallel review agents share one worktree (`review:981`).

**Phase 3 — Sweep the rest, by the criterion.** `preflight:369+373` **as one unit** (both →
`PREFLIGHT_TMP`), plus `:395`, `:688`. Then `qa:46` (**both occurrences**), `qa:82`, `ship:1188`,
`ship:1855`, `plan:229`, `merge-pr:154,155`, `schedule:472`, `rclone:29` → `mktemp`. Classify
`frontend-anti-slop:76` (waive-with-reason or fix).

**Prose constraint (Phases 1-3, load-bearing).** Explanatory prose added by a fix **must not
quote the broken form** — quoting `cp <file> /tmp/<file>.bak` to say "this was wrong" mints a
**new** hazard match at a new line and reddens the guard. Describe the defect; do not reproduce
it. (If a fix genuinely needs to quote it, that quote needs its own allowlist entry with a
reason.)

**Phase 4 — Author the guard (fixtures first).** Write the detector + its fixture suite (§Design
4) **before** wiring the file scan — the fixtures are the RED. Then confirm RED against pre-fix
text via `git show <commit>:<path>` (**not** `git stash`), and GREEN after Phases 1-3.

**Phase 5 — M3/M4** against a scratch copy. Tree untouched.

**Phase 6 — ADR-009 amendment.** Amend its Consequences: worktrees isolate the **working tree**,
not process-level scratch; `/tmp` is a shared namespace across worktrees; point to the criterion.
Run the C4 validation tests if any `.c4` changes (none expected).

**Phase 7 — Exit gate.** Dogfood the new guidance:
```bash
log=$(mktemp -t test-all.XXXXXXXX.log)
bash scripts/test-all.sh > "$log" 2>&1; rc=$?; echo "EXIT=$rc LOG=$log"
```
Inspect `rc` first; then grep `"$log"`. **Coupling note:** all 9 edited SKILL.md files are read
by existing tests (`components.test.ts`, `workflow-fidelity.test.ts`,
`observability-schema-parity.test.ts`, …). None should break — no `description:` frontmatter is
touched (all at line 3; every edit target ≥46), and `plan:229` is far from the canonical
Observability schema block at `plan:487` — but a failure there is adjacent, not mysterious.

**Phase 8 — Ship.** File three issues: (a) qa port-3000 race (P3); (b) PreToolUse Bash hook for
the runtime-improvised population; (c) `TMPDIR` via `settings.json` `env`. Plus
`incident/scripts/dry-run.sh:9`.

---

## Files to Edit

`plugins/soleur/skills/{work,review,qa,ship,preflight,plan,merge-pr,schedule,rclone}/SKILL.md`
(9 files) — sites per the work-list.
`knowledge-base/engineering/architecture/decisions/ADR-009-git-worktree-isolation.md` —
Consequences amendment.

## Files to Create

`plugins/soleur/test/scratch-path-collision.test.ts` — the guard. Auto-discovered by
`test-all.sh:223`; **no registration**.

**NOT edited:** `scripts/test-all.sh` (clean; no registration needed), `ux-audit/SKILL.md`
(already compliant), any product code.

---

## Acceptance Criteria

*(Cut from 12 to 7 — v1's AC1/AC3/AC5/AC10/AC12 were ceremony or unfalsifiable.)*

### Pre-merge (PR)

1. **AC1 — Intent preserved (the best AC; guards a real regression).** The rewritten
   `work:607` bullet still contains **all** of `pipefail`, `rc=$?`, and `4011`. Paired with the
   guard (which proves the path *changed*), this proves the tail-masking guidance *survived*.
2. **AC2 — Guard is red on its own root cause.** With `work:607` at its pre-fix text (via
   `git show <commit>:<path>`), the guard **FAILS** naming `work/SKILL.md:607`.
3. **AC3 — Detector fixtures pin every axis, permanently.** The committed fixture suite asserts
   RED on: placeholder (`/tmp/<mutant>.log`), literal, **`cp` DEST with no redirect**, **`-o`
   flag**; and GREEN on: `mktemp`-var, `$PREFLIGHT_TMP`, `${GITHUB_WORKSPACE}/tmp/…`, bare prose.
   *Narrowing the char class back, or dropping a write-verb alternation, must turn this RED.*
4. **AC4 — Non-vacuity.** `discoverSkills().length > 0` **and** every allowlist entry resolves to
   real matching text. Pointing the glob at an empty dir **FAILS**.
5. **AC5 — Allowlist states the truth.** Every entry is content-addressed (not line-keyed) and
   carries a non-empty reason. `preflight:114`'s reason reads *"narrow race window,
   self-limiting, accepted"* — **not** "not a defect".
6. **AC6 — `preflight:369` and `:373` are fixed in the same commit.** Verify by walking the
   commit's diff for both line regions (a per-commit intersection check — **not** `git log -- A
   B`, which is a **union** filter and would pass on an asymmetric fix).
7. **AC7 — Suite green, guard live.** `test-all.sh` `EXIT=0` (captured via a `mktemp` path per the
   new guidance) **and** its output names `scratch-path-collision`, with no edit to
   `scripts/test-all.sh`.

### Post-merge (operator)

None. All pre-merge in CI. *(The four deferrals are filed as issues by `/ship`, not executed by a
human.)*

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — agent-facing guidance plus
one CI test. The realistic failure is a **guard that cannot go red**, which v1 demonstrably was
along two axes (`cp` DEST, `-o` flag). AC2 + AC3's committed fixtures exist to make that
unshippable.

**If this leaks:** no exposure vector — no regulated data, secrets, network surface, or PII. The
change **reduces** cross-session information bleed, and `review:982` removes a cross-session
**content-corruption** vector.

**Brand-survival threshold:** `none`.
**Reason (required for `none`):** the diff touches only agent-facing markdown, one ADR, and one
CI-only test; it reaches no sensitive path (no schema, migration, auth flow, API route, or
`.sql`), no runtime, and no user data.

---

## Domain Review

**Domains relevant:** none — internal engineering tooling/guidance. `Files to Edit`/`Create`
contain no UI-surface path, so the mechanical override does not fire and the Product/UX Gate is
correctly skipped.

## GDPR / Compliance Gate

**Skipped** — no regulated-data surface; none of the (a)-(d) expansion triggers fire.

## Infrastructure (IaC)

**Skipped — no infrastructure introduced.** Each Phase 2.8 detection class was checked and none
fire: no remote-shell provisioning, no secret-manager write, no service-manager unit, no
scheduled-job registration, no vendor console path, no new vendor account.

> Written *without* reproducing the guard's literal trigger tokens: naming them — even to negate
> them — false-matches `.claude/hooks/iac-plan-write-guard.sh` (it greps bare tokens). The
> `iac-routing-ack` opt-out was **not** used: it emits a `bypass` telemetry event, and recording a
> bypass for a plan with zero infrastructure would be a false positive in the incident log.

## Observability

**Skipped** — `Files to Edit` contains no path under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, or `plugins/*/scripts/`, and no new infra surface. The new file is a CI test, not
a runtime surface. *(The guard's own "ships dead" risk is the real analogue and is covered
structurally by AC7 + AC4, not telemetry.)*

## Architecture Decision (ADR/C4)

**ADR-009 amendment — in scope, this PR.** `ADR-009-git-worktree-isolation:20` states *"Clean
parallel development with **full isolation**."* This plan's thesis is that the isolation **leaks
through `/tmp`** — a shared namespace every worktree writes to. A competent engineer reading
ADR-009 today **would** be misled on exactly this point, which is the gate's own test. Amend its
Consequences to bound the claim (worktrees isolate the *working tree*, not process-level scratch)
and record the mechanism criterion. Per `wg-architecture-decision-is-a-plan-deliverable` this is a
**deliverable of this plan, not a follow-up**. No new ADR: the decision is a correction to an
existing one.

**No C4 impact — enumeration cited.** All three model files read
(`diagrams/{model,views,spec}.c4`). **(a) External human actors:** none added — only the operator,
already modeled. **(b) External systems/vendors:** none — `mktemp` is a local coreutil. **(c)
Containers/data stores:** none — `/tmp` scratch is ephemeral process-local, unmodeled before and
after. **(d) Actor↔surface access relationships:** unchanged; no element description falsified.

## Open Code-Review Overlap

62 open `code-review` issues queried; all 9 target paths matched via standalone `jq --arg`.
**#4133** (*Schema parity test for `## Observability` block*) touches `plan/SKILL.md` —
**Acknowledge**: different concern (the Observability *schema* at `:487` vs. our scratch path at
`:229`), no shared lines, no fold-in value. Remains open. No other overlaps.

---

## Risks & Mitigations

*(v1's table restated the ACs; only the rows carrying a decision found nowhere else are kept.)*

| Risk | Mitigation |
|---|---|
| **Litter:** mktemp files accumulate. | Match the local `trap 'rm -f "$f"' EXIT INT TERM` convention (`ship:564`, `token-efficiency-report.sh:54`) for transient artifacts. Long-lived logs (test-all, dev server) are **deliberately kept** — they are the diagnostic artifact — and `/tmp` is tmpfs-cleared on reboot. |
| **Ergonomic regression:** a `mktemp` path is unrecoverable in a later Bash call (`work:609`: shell state does not persist). | Bounded by the **criterion** — artifacts a later call must find by name use git-dir/workspace scoping, not `mktemp`. Everything else echoes its path. |
| **Guard's scope is narrower than the harm.** | Stated, not hidden: DOCUMENTED LIMITATIONS block + follow-up issues for the hook layer and `incident/scripts/dry-run.sh`. This plan claims the test is stronger **than an AGENTS rule**, not than all layers. |

## Sharp Edges

- **The obvious anchor is wrong — twice.** `[A-Za-z0-9_.-]` misses `work:607`
  (`/tmp/<script>.log`). A **redirect** anchor misses `-o`, `cp`, `tee` — and catches `review:982`
  only because `<file>`'s `>` impersonates a redirect. Anchor on the **hazard**, with `/tmp/` at a
  **path boundary** (else `${GITHUB_WORKSPACE}/tmp/…` false-matches).
- **`review:982` is a restore source, not a log.** Reviewers pattern-match it to the log sites and
  wave it through. It is the opposite: a collision silently restores another session's content.
- **`preflight:369`+`:373` are one unit.** Fixing the reader alone is a **net regression** —
  corruption with a private-looking filename.
- **`qa:46` carries two occurrences on one line.** Fix the Doppler branch, see the line "done",
  and the no-Doppler branch survives.
- **`preflight:114` is a decoy** (same-invocation chain) — but the waiver reason must be honest:
  *narrow race window, accepted*, not *not a defect*.
- **Fix prose must not quote the broken form** — it mints a new hazard match and reddens the guard.
- **Do not `git stash`** to reconstruct pre-fix state (`hr-never-git-stash-in-worktrees`,
  **hook-enforced**). Use `git show <commit>:<path>`.
- **Do not mutate real skill files to test the guard** — this worktree carries the plan's own
  uncommitted edits. Fixtures, not file mutation.
- **Never serialize sessions as a "fix."** Parallel worktrees are the intended workflow (16 live).
- **A "no infrastructure" section can trip `iac-plan-write-guard.sh`** if you name its trigger
  tokens to negate them. Describe classes abstractly; do **not** use the `iac-routing-ack` opt-out
  (it records a false `bypass`).
- The `approvals.jsonl` corroboration is **untracked, main-checkout-only** — never let an AC depend
  on it, and do not read it from the bare repo during `/work`
  (`hr-when-in-a-worktree-never-read-from-bare`).
