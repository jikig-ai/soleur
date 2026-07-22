---
title: "fix(hooks): repair the silently-dead PR-body scan and add a follow-through label gate to the merge-boundary auto-close guard"
date: 2026-07-20
type: fix
issue: 6775
branch: feat-one-shot-6775-autoclose-hook-pr-body-scan
lane: cross-domain
brand_survival_threshold: none
---

> No `spec.md` exists for this branch, so `lane:` could not be carried forward — defaulted
> to `cross-domain` (TR2 fail-closed).

# fix: auto-close hook's PR-body scan is dead code; no follow-through label gate

Closes #6775

*v3 — revised after a 6-agent plan review. Four blocking findings applied; see §Review Corrections.*

## Overview

`.claude/hooks/pre-merge-auto-close-scan.sh` is a PreToolUse gate on `gh pr merge`. It
stops a PR from auto-closing an issue it was written to keep open.

Issue #6775 reports that it "scans commit messages but not the PR body." The code
*appears* to contradict this — lines 67–70 fetch and append the PR body. **Measurement
shows the reporter was right, and the mechanism is worse than a missing feature: the
PR-body fetch is dead code that fails silently.**

| # | Defect | Effect |
|---|---|---|
| **D1** | `--repo` slug built by a `sed` that leaves `.git` on SSH remotes | `gh pr view --repo jikig-ai/soleur.git` → GraphQL error → swallowed by `2>/dev/null \|\| true` → **PR body never appended to the corpus** |
| **D2** | No `follow-through` label check on the plain `gh pr merge` path | A standalone `Closes #N` is allowed *by design*; when `#N` is a follow-through tracker the merge silently destroys it |
| **D3** | Test's `gh` stub prints the body ignoring `argv` | The fixture seam sits **above** D1, so the body-path test passes green while the production path has never executed |

D1 shipped 2026-07-03 (`e7f303917`, PR #5969). **The PR-body arm has been dark for 17
days** while the suite reported `8/8 passed`.

This is the shape #6775 cites from
[`2026-07-20-a-fixture-seam-above-the-code-under-test-makes-the-default-path-untestable.md`](../learnings/test-failures/2026-07-20-a-fixture-seam-above-the-code-under-test-makes-the-default-path-untestable.md):
a guard that looks like coverage while being structurally incapable of firing.

#6775's stated fix ("widen the scan to the PR body") would be a no-op — the widening is
already written. The work is: make it execute, add the label gate, and lower the test
seam so D1 could not have hidden.

## Review Corrections

Six agents reviewed v1/v2. Four findings were blocking. Each is recorded rather than
silently folded in, because **three of the four were the plan reproducing the very defect
class it was written to eliminate.**

### C1 (blocking) — v2's label gate would have shipped *unreachable*

Caught independently by the correctness and flow reviewers. The hook ends with:

```bash
EMBEDDED=$(bash "$SCANNER" "$SCAN_FILE" 2>/dev/null | grep -viE "$DIRECTIVE" || true)
[[ -n "$EMBEDDED" ]] || exit 0
```

The label gate's entire target population is a **standalone** `Closes #N`, which by
construction produces **empty** `EMBEDDED` — that is exactly what the D2 probe below
proves. So a gate appended after that early exit never executes on any input. v2's
phrasing ("the label gate is strictly additive") actively invited that placement.

It would have passed every test in the matrix, because the tests exercise the deny path
directly — and been dark in production. **D1, verbatim, inside the fix for D1.**

**Resolution:** Phase 3 now restructures explicitly — hoist the raw scanner output once,
derive *both* arms from it, and make the early exit conditional on **both** being empty.
AC2 pins reachability.

### C2 (blocking) — v1's label-set probe was silently truncated

v1 justified a single `gh issue list --label follow-through --state open` call with the
annotation `# 30 open` and the claim "measured to return the whole set." That was not the
set. It was `gh`'s default page size:

```
$ gh issue list --label follow-through --state open --json number --jq 'length'          -> 30
$ gh issue list --label follow-through --state open --limit 500 --json number --jq 'length' -> 44
$ gh issue list --help | grep limit
  -L, --limit int   Maximum number of issues to fetch (default 30)
```

`gh issue list` sorts newest-first, so the 14 invisible trackers are the **oldest** —
precisely the long-lived ones a follow-through gate exists to protect:

```
2482 3004 3008 3043 3044 3456 3458 3470 3570 3580 3652 3702 3745 3754
$ gh issue view 2482 --json number,labels --jq '{n:.number,ft:(...)}'
{"n":2482,"ft":true}     # open 94 days, follow-through, invisible to the v1 gate
```

A full page is indistinguishable from a truncated one: exit 0, valid JSON, no warning.

**Resolution — eliminate the truncation class, don't raise the limit.** Look up each
referenced issue directly (`gh issue view <N> --json labels`), matching the precedent
already in `ship-soak-followthrough-gate.sh:101-104`. A PR references 1–3 issues, so this
is constant in the thing that actually varies and **cannot paginate** — there is no count
to remember to check. `--limit 500` would fix today's number while leaving an unsignalled
ceiling. AC8 pins the absence of any `gh issue list`.

### C3 (blocking) — delete the slug extraction rather than repair it

v1 proposed replacing the buggy `sed` with the correct form from `pre-merge-rebase.sh:192`,
hoisting it to a testable variable, and pinning it with four remote-form tests.

`gh` already resolves the repository from the working directory's git remote, and
`ship-soak-followthrough-gate.sh:64,68,101` calls `gh pr view` / `gh issue view` with **no
`--repo` at all**. Measured from this worktree:

```
$ (cd "$WORK_DIR" && gh pr view 6748 --json body --jq '.body')       -> Closes #6295 / Ref #6617
$ (cd "$WORK_DIR" && gh pr view "feat-one-shot-6617-…" --json body)  -> same (resolves by branch)
$ (cd "$WORK_DIR" && git rev-parse --is-inside-work-tree)            -> true (works from a worktree)
```

`gh`'s own resolver additionally handles SSH-alias remotes (`git@github-work:owner/repo`),
`insteadOf` rewrites, `GH_REPO`, and `remote.origin.gh-resolved` — cases the sibling `sed`
silently mangles. Adopting that `sed` verbatim per the precedent rule would have inherited
its blind spot. **Both review panels fired on this same scope, which per panel guidance
means prefer delete over fix.** D1 becomes structurally unreachable rather than fixed.

### C4 (blocking) — this PR would have blocked its own merge

v1/v2's AC required "the captured Phase 0.2 failure output recorded in the PR body." That
captured output contains the fixture string `I'll close #5955 after the pipeline confirms
green.` Once Phase 1 repairs the fetch, the hook scans **its own PR body**, finds a
prose-embedded close, and denies its own merge — on the first merge attempt after the fix
lands. (`Closes #6775` at the top is safe: #6775 carries no `follow-through` label.)

**Resolution:** RED evidence lands as its own commit and is re-derived mechanically
(AC1), never pasted into the PR body. A dogfooding gate that has to be disarmed with
`SOLEUR_ACK_AUTOCLOSE=1` to merge would have undercut its own AC.

### Non-blocking findings applied

- **Scoped escape hatch.** `SOLEUR_ACK_AUTOCLOSE` is checked at `:60`, *before* the corpus
  is built — an all-or-nothing kill switch. After Phase 3 the hook has two checks with
  unrelated triggers, so an operator acking a harmless prose false-positive would silently
  disarm tracker protection too. Add `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1`, checked at the
  gate; the label deny names only that one. (v2 argued for keeping one knob; the review
  showed the knob sits above the corpus, which changes the answer.)
- **The realistic false-deny has no AC.** A PR that *genuinely resolves* a follow-through
  tracker legitimately carries `Closes #N` — with 44 open, this deny will fire in normal
  use. AC7 + T13 now cover it, and the deny message explains *why* the issue is protected
  rather than v1's "reword the sentence," which is meaningless advice for a label deny.
- **Meta-test instead of a README note.** The repo already answered this class once:
  `hookeventname-coverage.test.sh` sweeps every hook after nine shipped "silently
  non-enforcing." A `stub-argv-fidelity` meta-test is the same shape and is the only
  artifact that prevents recurrence; a README note is advisory text the next author will
  not read. Detector must parse the **stub body**, not grep the test file broadly — a
  naive sweep false-positives on `$1` in surrounding helpers.
- **Shared deadline, not two independent `timeout 8`s.** Measured: `gh` fails fast on DNS
  failure (0.10s) but **hangs past 20s on blackholed packets**, so the 16s worst case is
  reachable. One deadline across both arms.
- **Cut `emit_incident` to a single stderr line.** At `threshold: none` the operator is
  already at the terminal; a weekly-aggregator sink has no distinct reader, and an offline
  week would write identical rows at merge frequency.
- **Dropped** v1's `timeout`-hang test (tests GNU `timeout`, costs 8s/run), the dated
  obituary in the header (`git blame` holds it), and ~34% of the plan prose (v1 stated
  D1/D2/D3 four times across separate sections).

### Corrected factual claim

v1/v2 asserted that `follow-through-directive-gate.sh` and `ship-soak-followthrough-gate.sh`
"neither fires at `gh pr merge`." **That is wrong.** Measured at
`ship-soak-followthrough-gate.sh:47`:

```bash
grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'
```

It fires on `gh pr merge --auto` and already does `follow-through` membership checks at
`:101-107` — with **inverse** semantics (it denies when a referenced tracker is *missing*
enrollment; this gate denies when the issue *has* the label and would be destroyed). The
accurate claim: **neither fires on plain `gh pr merge`**, which is the gap D2 closes. The
two gates' deny messages must be distinguishable, since both can fire on one `--auto`
merge with three different override mechanisms between them.

## Premise Validation

Every claim measured in-session.

**#6775 is OPEN** — not already closed by a merged PR. Work target valid.

**D1 (decisive probe).**

```
$ git remote get-url origin
git@github.com:jikig-ai/soleur.git
$ ... | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#'
jikig-ai/soleur.git                    # .git NOT stripped
$ gh pr view --repo "jikig-ai/soleur.git" 6748 --json body
GraphQL: Could not resolve to a Repository with the name 'jikig-ai/soleur.git'.
$ gh pr view --repo "jikig-ai/soleur"     6748 --json body
Closes #6295
Ref #6617
```

`[^/]+?` is lazy but must still reach `$`, so `(\.git)?` matches empty and `soleur.git` is
consumed wholesale. The error goes to stderr; the non-zero exit is absorbed by `|| true`.
**Confirmed: the PR body has never been scanned on this repo.** (The correct-slug run also
confirms PR #6748's body reads `Ref #6617` — the manual scrub #6775 describes did land.)

**D2 (probe).**

```
$ echo 'Closes #6617' > /tmp/f; bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh /tmp/f
1:Closes #6617
$ ... | grep -viE "$DIRECTIVE"
(EMPTY -> hook ALLOWS)
$ gh issue view 6617 --json labels --jq '[.labels[].name]'
[...,"follow-through","observability"]
$ gh issue view 6775 --json labels --jq '[.labels[].name]'      # control
["priority/p2-medium","type/bug","domain/engineering"]
```

Allowing standalone directives is correct for ordinary fix-PRs and must be preserved. The
empty result is also what makes C1's reachability trap possible.

**D3 (probe).** `pre-merge-auto-close-scan.test.sh:35-38` writes a `gh` stub whose entire
body is `printf '%s\n' "$pr_body"` — it never inspects `argv`, so any `--repo`, valid or
malformed, yields the body:

```
$ bash .claude/hooks/pre-merge-auto-close-scan.test.sh
PASS: PR-body prose-embedded close → deny (deny)
=== 8/8 passed, 0 failed ===
```

**Green on a path that cannot execute.** The test file is not merely incomplete, it is
misleading — an AC that only says "assert the body path" is satisfied by the existing
line 68.

**Extraction traps (probe).** The scanner emits `<line-number>:<matched-text>`, and the
`DIRECTIVE` filter is line-granular. Three consequences:

```
$ echo 'Refs #6617, closes #6295' | ...scanner...
2:Refs #6617, closes #6295
$ ... | grep -oE '#[0-9]+'                                  # NAIVE
#6617 #6295     <- #6617 is only Ref'd, and IS follow-through -> false deny
$ ... | grep -oiE '(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' | grep -oE '[0-9]+'
6295            <- only the genuinely-closing reference

$ printf 'closes #1 closes #2\nFixes #6775 (see also closes #1)\n' | ...scanner... | grep -viE "$DIRECTIVE"
(EMPTY -> BOTH ALLOW; GitHub closes #1 AND #2 in each case)
```

So: (a) extraction must be **keyword-paired**, not a bare `#N` scrape, or the gate denies
over an issue the PR explicitly declined to close; (b) the `^[0-9]+:` line-number prefix
must be stripped first, or `12:` yields `12` as an issue number; (c) a line-leading
directive **launders every later close on that line** — a live pre-existing hole in the
guard's original purpose, which becomes load-bearing for D2 (extraction must be global
per line, not first-match). `Ref #6617` alone produces no scanner match at all.

**Additional silent-dark paths found in review** (all confirmed, all in the same
early-exit fringe D1 lived in):

- `SCANNER="$WORK_DIR/plugins/…"` is built from the payload **cwd**, not the repo root, so
  any `gh pr merge` issued from a subdirectory misses the scanner and exits 0 in silence.
- `[[ "$BRANCH" != "main" ]]` exits before everything, so `gh pr merge 6775` **from `main`
  bypasses the entire guard** — and that is exactly the post-checkout merge form this
  workflow uses.
- `gh pr view "$BRANCH"` ignores the PR **number** in the intercepted command, so
  `gh pr merge 1234` while on `feat-x` scans feat-x's body and applies the verdict to #1234.
- `git log origin/main..HEAD … || true` fails silently when `origin/main` is absent.

**Enforcement-surface map** (corrected — see §Review Corrections):

| Surface | Layer | Trigger | Semantics |
|---|---|---|---|
| `/ship` Phase 6 | pre-creation | `gh pr create` | blocking, prose arm |
| `pr-auto-close-scanner.yml` | CI | PR events | **observational only** (its header says so) |
| `ship-soak-followthrough-gate.sh` | PreToolUse | `gh pr ready`, `merge --auto` | denies when tracker **lacks** enrollment |
| **this gate** | PreToolUse | plain `gh pr merge` | denies when issue **has** `follow-through` |

`gh api repos/jikig-ai/soleur/branches/main/protection` → **404 Branch not protected**, so
no server-side required check exists today. `.openhands/hooks/` has `pre-merge-rebase.sh`
but **no auto-close-scan counterpart** — a pre-existing coverage hole.

## Research Reconciliation — Issue Claim vs. Codebase

| Issue claim | Reality (measured) | Plan response |
|---|---|---|
| "Scans commit messages but not the PR body" | Symptom correct, mechanism different: the code exists but is dead (D1) | Delete `--repo` so the existing code runs; do not add a second fetch path |
| "Widen the hook's scan to the PR body" | Already widened at `:67-70` | Re-scope to *repair + make loud + gate on label* |
| "Test asserts the BODY path specifically" | A body-path test exists (`:68`) **and passes** | Strengthen: stub validates `argv`; test must **fail against the pre-fix hook** (AC1) |
| "Fail closed when a follow-through issue is referenced" | No check on the plain `gh pr merge` path | Add it (D2), per-issue lookup, before the `EMBEDDED` early exit |

## User-Brand Impact

**If this lands broken, the user experiences:** a `gh pr merge` that either wedges on a
false deny (blocking all shipping) or, unchanged, keeps silently destroying follow-through
trackers — the tracker closes at merge, the daily sweeper skips it (it evaluates only
*open* issues), and the soak verification the tracker existed to enforce never runs. The
operator learns nothing was verified only when the underlying system fails in production.

**If this leaks, the user's data/workflow is exposed via:** no data surface. The hook reads
issue numbers and labels from a repo the operator already owns and writes only to local
stderr. No PII, no credentials, no egress beyond authenticated `gh` calls.

**Brand-survival threshold:** `none` — local developer tooling. *Scope-out:*
`threshold: none, reason: local pre-merge developer hook with no end-user, production, or
data surface; worst case is a wrongly-blocked or wrongly-allowed merge on the operator's
own repo.*

## Observability

The defect *is* an observability failure — a guard that fails open in total silence.

```yaml
liveness_signal:
  what: "PR-body fetch, scanner resolution, and per-issue label lookup outcomes, surfaced on stderr at merge time"
  cadence: "every `gh pr merge` interception"
  alert_target: "the operator's terminal (the channel already in front of them at merge time)"
  configured_in: ".claude/hooks/pre-merge-auto-close-scan.sh"

error_reporting:
  destination: "hook stderr, one terse line naming the skipped arm"
  fail_loud: "yes for DIAGNOSIS; still fail-OPEN for the MERGE DECISION (a hook must never wedge a merge on its own bug)"

failure_modes:
  - mode: "PR-body fetch fails (expired gh auth, offline, GitHub 5xx)"
    detection: "non-zero exit from the deadline-bounded `gh pr view`"
    alert_route: "stderr: 'auto-close scan ran WITHOUT the PR body'"
  - mode: "no PR exists for the branch (a normal pre-PR state, NOT a failure)"
    detection: "gh's no-PR-found exit, distinguished from auth/network failure"
    alert_route: "silent — must not emit a degraded notice, or every pre-PR merge attempt cries wolf"
  - mode: "scanner not found (merge issued from a subdirectory)"
    detection: "path resolved via `git -C \"$WORK_DIR\" rev-parse --show-toplevel` missing the file"
    alert_route: "stderr: 'auto-close scan SKIPPED — scanner not found'"
  - mode: "per-issue label lookup fails, or fan-out exceeds the cap"
    detection: "non-zero exit from `gh issue view`, or >3 referenced issues"
    alert_route: "stderr: 'follow-through label gate SKIPPED'"

logs:
  where: "hook stderr only — no new log file, no telemetry sink at threshold none"
  retention: "n/a"

discoverability_test:
  command: "bash .claude/hooks/pre-merge-auto-close-scan.test.sh && bash .claude/hooks/stub-argv-fidelity.test.sh"
  expected_output: "all cases pass, including the argv-validating body case, the reachability case, and the degraded-notice cases (no ssh, no network)"
```

## Architecture Decision (ADR/C4)

**No ADR.** The reviewer raised that this PR leaves three follow-through-enforcement
surfaces with no reconciling record, and suggested a terse ADR. Rejected in favour of the
cheaper artifact: **Phase 4.1 documents the four-surface division of labour in the hook
header**, cross-referenced from `follow-through-closure-guard.yml`. This change selects no
new enforcement layer — it repairs one that already exists and adds a check to it. Writing
an ADR to record "the hook we already had now also checks a label" would be ceremony; a
future reader's actual question ("which of these is authoritative?") is answered by the
header table at the point of contact.

**C4:** read all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. The
operator actor and GitHub as an external system are already modeled; this change adds no
actor, external system, container, data store, or access relationship, and falsifies no
element description. No `.c4` edit required.

## Domain Review

**Domains relevant:** Engineering

**Assessment:** Risk concentrates in three places — a label gate that is too broad wedges
ordinary fix-PRs (AC6/AC7 pin both negative cases); a gate placed after the early exit
ships dark (AC2); and added network calls on the merge path must stay bounded so an
offline operator is never blocked (shared deadline + fan-out cap + fail-open). No UI
surface, no schema, no infra — the Product/UX gate does not fire (no path in §Files to
Edit matches the UI-surface glob superset).

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` (61 open)
and searched every body for the paths in §Files to Edit. No matches.

## Implementation Phases

### Phase 0 — RED: tests that fail against today's code

Per `cq-write-failing-tests-before`. Land Phase 0 as its **own commit** so AC1's evidence
is re-derivable via `git checkout <red-sha> -- .claude/hooks/` (never `git stash` —
`hr-never-git-stash-in-worktrees`), and never pasted into the PR body (C4).

0.1 **Lower the fixture seam.** Rewrite the `gh` stub so it **inspects `argv`**: dispatch
on subcommand (`pr view` → body; `issue view` → label JSON; else empty), honor a per-case
failure switch that exits non-zero with empty stdout, and carry a comment stating that hook
stubs must validate `argv` — this stub is the precedent the next hook test will copy.

0.2 **Assert the new stub reproduces D1.** With the seam lowered and the hook unmodified,
the body case must **FAIL** while the **commit-body case stays PASS in the same run**. Both
halves are required: a body-only failure is also what a broken stub produces, so the green
commit case is the discriminator proving the seam moved to the fetch and not elsewhere.

0.3 **Reachability case** (pins C1): standalone `Closes #N` on a follow-through issue, PR
body — must `deny`. Fails today, and fails again if the gate lands after the early exit.

0.4 **Label-gate cases** (all failing today): commit-message standalone close on a
follow-through issue → `deny`; `Ref #N` alone → `allow`; standalone close on a
**non**-follow-through issue → `allow`; legitimate follow-through close with
`SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1` → `allow`.

0.5 **Extraction cases:** `Refs #A, closes #B` (`#A` follow-through, `#B` not) → `allow`;
an issue number that is a **prefix of** a follow-through number (e.g. `#661` vs `6617`) →
`allow` (pins exact-token matching); `GH-N` form handled.

0.6 **Degraded-notice cases:** stubbed `gh` fails → `allow` + notice; scanner unresolvable
→ `allow` + notice; **no PR for branch → `allow` and NO notice** (a normal state must not
cry wolf).

0.7 **Meta-test** `stub-argv-fidelity.test.sh`, modelled on `hookeventname-coverage.test.sh`:
sweep every `.claude/hooks/*.test.sh` that puts a `gh` stub on `PATH` and assert the stub
body references `$1`/`$@`. Parse the **stub heredoc body**, not the whole test file — a
naive grep false-positives on `$1` in surrounding helpers. Expect this to surface
pre-existing gaps in sibling suites; triage inline per `wg-defer-only-after-inline-triage`.

### Phase 1 — GREEN: make the PR-body fetch execute (D1)

1.1 Replace the `--repo "$(… sed …)"` construction with a subshell that runs `gh` from
inside the repo, letting `gh` resolve the remote itself:

```bash
(cd "$WORK_DIR" && gh pr view "$BRANCH" --json body --jq '.body') >>"$SCAN_FILE"
```

No slug, no `sed`, no extractor. Bound by the shared deadline from 2.3.

1.2 Resolve `SCANNER` from `git -C "$WORK_DIR" rev-parse --show-toplevel`, not from the
payload cwd, so a merge issued from a subdirectory still finds it.

1.3 Confirm 0.2's body case flips to `PASS` **and** the commit case stays `PASS`. Assert
per-case `PASS:` lines, not suite exit code — Phases 0.3–0.6 are still red by design.

### Phase 2 — GREEN: make the fail-open loud

2.1 Capture exit status for each arm instead of discarding it. On failure keep `allow`
(never wedge a merge on the hook's own bug) and print one terse stderr line naming the
skipped arm. One line, not a banner — a notice the operator learns to ignore is how the
next D1 hides.

2.2 Distinguish gh's **no-PR-found** exit from auth/network failure; the former is silent.

2.3 Give both `gh` arms a **single shared deadline** rather than independent `timeout 8`s.
Measured: `gh` fails fast on DNS failure (0.10s) but hangs past 20s on blackholed packets,
so the additive worst case is reachable.

2.4 Confirm 0.6 goes green.

### Phase 3 — GREEN: follow-through label gate (D2)

3.1 **Restructure the early exit** (pins C1). Hoist the raw scanner output once; derive
`EMBEDDED` (prose arm) and `REFERENCED` (label arm) from it; exit 0 only when **both** are
empty. The gate must be evaluated *before* the existing `[[ -n "$EMBEDDED" ]] || exit 0`,
not appended after it.

3.2 **Extraction contract** — all three traps from §Premise Validation:
  - strip the `^[0-9]+:` line-number prefix **first**;
  - match keyword-paired references globally per line, both forms:
    `(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#|GH-)([0-9]+)`;
  - de-duplicate; compare by **exact token** (`grep -Fxq` against a newline-delimited set),
    never substring — `#661` must not match `6617`.

3.3 Cap fan-out at **3** distinct issues; beyond that skip the gate with the degraded
notice — bounded, not an unbounded loop on the merge path.

3.4 For each, run a deadline-bounded `gh issue view <N> --json labels` from inside
`$WORK_DIR` and test for `follow-through`. Constant per issue and **cannot paginate** —
the property that makes C2's truncation class impossible rather than merely guarded.

3.5 On a hit, **deny**, naming the issue(s), the surface (commit vs PR body), and *why* the
issue is protected (it carries `follow-through`; closing it makes the sweeper skip it, so
the soak never runs). Do not reuse the prose arm's "reword the sentence" advice — there is
nothing to reword. Offer `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1`, and word the message so an
operator who trips both this and `ship-soak-followthrough-gate.sh` on one `--auto` merge
can tell them apart.

3.6 Preserve the existing prose-embedded deny for **all** issues, labelled or not — the
label gate must not widen denial for non-follow-through issues.

3.7 Confirm 0.3, 0.4, 0.5 go green.

### Phase 4 — Documentation + full suite

4.1 Hook header: document the four-surface division of labour (per §Premise Validation's
map), the two escape hatches and what each disarms, and the known bypasses (merge from
`main`, web UI, admin merge, CI-queued auto-merge, OpenHands). State the guard is
best-effort for the agent-driven path, not a complete boundary. No dated history.

4.2 `.claude/hooks/README.md`: add the escape-hatch inventory — `SOLEUR_ACK_AUTOCLOSE`,
`SOLEUR_ACK_FOLLOWTHROUGH_CLOSE`, `SOLEUR_SKIP_OPERATOR_STEP_GATE`, and
`SOLEUR_SKIP_RUNBOOK_SSH_GATE` are currently undocumented.

4.3 Run `bash scripts/test-all.sh`. Orphan suites are exercised only there.

## Files to Edit

- `.claude/hooks/pre-merge-auto-close-scan.sh` — delete `--repo` (D1), scanner-path fix, loud fail-open, early-exit restructure + label gate (D2)
- `.claude/hooks/pre-merge-auto-close-scan.test.sh` — lower the seam (D3), reachability, label-gate, extraction, degraded cases
- `.claude/hooks/README.md` — escape-hatch inventory

## Files to Create

- `.claude/hooks/stub-argv-fidelity.test.sh` — meta-test making the D3 class un-shippable, per the `hookeventname-coverage.test.sh` precedent

## Non-Goals / Out of Scope

- **Blocking standalone `Closes #N` in general.** That is the form every ordinary fix-PR
  uses (including this one). Blocking it wedges all shipping. #6775 scopes fail-closed to
  `follow-through` issues, which is correct.
- **`--auto` deferred merges (TOCTOU).** `gh pr merge --auto` queues; GitHub merges
  minutes-to-hours later. The body can be edited and the label added or removed in that
  window, so for `--auto` this gate is advisory, not a boundary. The durable surface is
  CI-side. Documented, not fixed here.
- **Fixing the line-granular `DIRECTIVE` laundering** (`closes #1 closes #2` allows today).
  A live pre-existing hole in the prose arm. Phase 3.2's global per-line extraction means
  the **label** gate is not fooled by it, but the prose arm still is. Separate defect,
  separate blast radius — **deferred** below.
- **`OWNER/REPO#N` and full-issue-URL forms.** `auto-close-scan.sh` scopes to `#N`/`GH-N`.
  Widening the shared regex changes `/ship` Phase 6 and the CI workflow simultaneously and
  needs its own false-positive audit. **Deferred.**
- **Branch protection / required checks.** `main` has none (measured 404). Establishing it
  changes the merge contract for every auto-merge workflow and is ADR-class.
- **Extracting slug resolution to `.claude/hooks/lib/`.** C3 removes this hook's need for
  it; adding a `source` failure mode to a hook designed for fail-open self-containment is a
  net negative.

## Deferred

To be filed as tracking issues during `/work`:

1. **Line-granular `DIRECTIVE` laundering.** `closes #1 closes #2` and
   `Fixes #N (see also closes #1)` both allow today; GitHub closes both issues.
   *Re-evaluation:* fold in with the next change to the prose arm. *Milestone:* `Post-MVP / Later`.
2. **Generalize `follow-through-closure-guard.yml` as the path-independent reversal layer.**
   It fires `on: issues.closed`, so it covers every bypass in §4.1 (web UI, admin, CI
   auto-merge, OpenHands). Prevention + reversal is strictly stronger than prevention alone,
   and the harm here is fully reversible by reopening. Currently scoped to the callback-URL
   class. *Milestone:* `Post-MVP / Later`.
3. **`.openhands/hooks/` has no auto-close-scan counterpart.** The merge-boundary guard
   exists in one harness only. *Milestone:* `Post-MVP / Later`.
4. **Widen the canonical regex to `OWNER/REPO#N` and full issue URLs.** *Milestone:* `Post-MVP / Later`.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (load-bearing)** — The body-path test **fails** against the pre-fix hook while the
  **commit-body case passes in the same run**, and both pass after Phase 1. A test green
  both before and after has not moved the seam. Evidence is re-derived mechanically via
  `git checkout <red-sha> -- .claude/hooks/ && bash …test.sh`, **not** pasted into the PR
  body (C4).
- **AC2 (reachability)** — A standalone `Closes #N` on a follow-through issue denies. This
  fails if the gate is placed after the `EMBEDDED` early exit, which is how C1 would have
  shipped dark. (T3)
- **AC3** — Body-carried `Closes #N` on a follow-through issue denies. *(#6775 AC 1)*
- **AC4** — Commit-message-carried close on a follow-through issue denies. *(#6775 AC 2)*
- **AC5** — `Ref #N` / `Refs #N` **as the sole reference on a line** allows, even when `#N`
  is follow-through. A line mixing `Refs #A` with `closes #B` correctly denies on `#B`.
  *(#6775 AC 3, restated to match measured behavior)*
- **AC6** — A standalone `Closes #N` for an issue **without** the label allows.
- **AC7** — A PR that *legitimately* closes a follow-through tracker can merge via
  `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1`, and that hatch does **not** disarm the prose arm.
  (T13) This is the deny operators will actually hit — 44 open trackers.
- **AC8** — Label lookup is per-issue: `grep -c 'gh issue list' .claude/hooks/pre-merge-auto-close-scan.sh`
  returns `0`. No paginated call means C2's silent truncation is structurally impossible.
  **Note (measured): this grep returns `0` today, before any change.** It is therefore a
  *guard against introducing* the truncating call — the tempting implementation C2
  rejected — and **not** a before/after discriminator. Do not read a green AC8 as evidence
  the label gate works; AC2 and AC3 carry that. Flagged explicitly because an AC that
  passes before and after is the vacuity class AC1 exists to prevent, and it would
  otherwise read as state-change proof to a reviewer.
- **AC9** — Extraction is keyword-paired, prefix-stripped, and exact-token: `Refs #A, closes #B`
  allows (T11), and an issue number that is a prefix of a follow-through number allows (T12).
- **AC10** — No `--repo` and no remote-URL parsing remain in the hook:
  `grep -cE 'remote get-url origin|--repo' .claude/hooks/pre-merge-auto-close-scan.sh` returns `0`.
  Measured: returns `1` today, so unlike AC8 this *is* a genuine before/after discriminator.
- **AC11** — Degraded arms emit exactly one stderr line and still allow; **no PR for branch
  emits none** (T14/T15/T16).
- **AC12** — `bash .claude/hooks/stub-argv-fidelity.test.sh` passes and fails against a
  reverted (argv-blind) stub.
- **AC13** — `bash scripts/test-all.sh` passes.

### Post-merge (operator)

None. Every step is automatable in-session: a local script, tests run offline against
stubs, no infrastructure, migration, vendor dashboard, or credential mint involved.

## Test Scenarios

Runner: `bash` (`.test.sh`, matching every sibling hook test; `bats` is not installed —
verified `command -v bats` returns nothing).

| # | Surface | Fixture | Expect |
|---|---|---|---|
| T1 | PR body | prose `I'll close #N after…` | `deny` — regression guard, now on a live path |
| T2 | commit msg | prose-embedded close | `deny` — existing behavior preserved |
| T3 | PR body | **standalone** `Closes #N`, `#N` follow-through | `deny` (AC2, AC3 — reachability) |
| T4 | commit msg | standalone `Closes #N`, `#N` follow-through | `deny` (AC4) |
| T5 | PR body | `Ref #N` alone, `#N` follow-through | `allow` (AC5) |
| T6 | PR body | standalone `Closes #N`, `#N` **not** follow-through | `allow` (AC6) |
| T7 | trigger | non-merge command | `allow` — early exit |
| T8 | trigger | `gh pr merge` inside a quoted commit `-m` | `allow` — `strip_command_bodies` |
| T9 | trigger | `SOLEUR_ACK_AUTOCLOSE=1` + T1 fixture | `allow` — broad hatch |
| T10 | trigger | `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1` + T1 fixture | **`deny`** — scoped hatch must NOT disarm the prose arm (AC7) |
| T11 | extraction | one line `Refs #A, closes #B`, `#A` follow-through | `allow` (AC9) |
| T12 | extraction | `#661` referenced, `6617` is follow-through | `allow` — exact-token (AC9) |
| T13 | hatch | legitimate follow-through close + scoped hatch | `allow` (AC7) |
| T14 | infra | stubbed `gh` exits non-zero | `allow` + one notice (AC11) |
| T15 | infra | scanner unresolvable (merge from subdir) | `allow` + one notice (AC11) |
| T16 | infra | no PR exists for branch | `allow`, **no notice** (AC11) |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Gate ships unreachable behind the early exit** | AC2/T3 pin it; Phase 3.1 states the restructure as a numbered step |
| Label gate too broad → wedges ordinary fix-PRs | AC6/T6 pin the unlabelled case; AC7/T13 pin the legitimate-close case |
| Scoped hatch silently disarms the prose arm | T10 asserts the prose arm still denies under the scoped hatch |
| Network calls slow the merge path | Single shared deadline; fan-out capped at 3; fail-open. Baseline is already 4+ *unbounded* `gh` calls in sibling hooks on this path |
| Offline operator cannot merge | Fail-open for the decision; `gh` fails fast on DNS failure (0.10s measured) |
| Degraded notice becomes background noise | One terse line, and the normal no-PR state is explicitly silent (T16) |
| **`--auto` TOCTOU**: gate evaluates at queue time, merge fires later | Documented non-goal; CI is the durable surface |
| Merges bypassing this hook (main, web UI, admin, CI auto-merge, OpenHands) | Enumerated in the header (4.1); `main` has no branch protection (404), so no server-side alternative exists today. Deferred #2 is the reversal layer |
| Two follow-through gates with inverse semantics on `--auto` | Deny messages differentiated (3.5); hatch inventory documented (4.2) |
| Phase 3.2 couples to `auto-close-scan.sh`'s `N:text` output format | Assert the format in the test so a scanner change fails loudly here rather than failing the gate open |
| Meta-test surfaces pre-existing sibling gaps | Expected; triage inline per `wg-defer-only-after-inline-triage` |

## Deepen-Plan Verification Record

Deepened 2026-07-20. All mandatory gates ran; none halted.

| Gate | Result |
|---|---|
| 4.5 Network-outage deep-dive | **Lexical trigger only.** The word `timeout` appears throughout, but as the `timeout(1)` coreutil bounding a subprocess — not a network-outage symptom. No SSH keyword, no `terraform apply`, no `provisioner`/`connection` block anywhere in scope. Disposed as a false positive rather than skipped silently. |
| 4.55 Downtime & cutover | Not triggered — no infra reboot/replace, no DDL, no deploy/router change. Two `.sh` files and a `.md`. |
| 4.6 User-Brand Impact | **PASS** — heading present, 12 non-blank body lines, threshold `none`, and no Files-to-Edit path matches the canonical sensitive-path regex (verified per-path). Scope-out line present anyway. |
| 4.7 Observability | **PASS** — all 5 fields present, none empty-keyed, none placeholder, `discoverability_test.command` contains no `ssh`. |
| 4.8 PAT-shaped variable | **PASS** — zero matches across all four patterns. |
| 4.9 UI-wireframe | Not triggered — 0 UI-surface path hits. |

**Citation verification (all resolved live, none from memory):**

| Citation | Verified |
|---|---|
| #6775 | ISSUE OPEN — work target valid, not already closed |
| #6748 | PR MERGED — the motivating PR |
| #5969 | PR MERGED — introduced D1 |
| #6617 | ISSUE OPEN, carries `follow-through` — the tracker that nearly died |
| #6295 | ISSUE CLOSED, no `follow-through` — the control |
| #2482 | ISSUE OPEN, `follow-through`, 94 days — invisible to C2's truncated probe |
| `e7f303917` | Real hash, **ancestor of `origin/main`**, subject matches PR #5969 — attribution correct |
| `hr-never-git-stash-in-worktrees`, `cq-write-failing-tests-before`, `wg-defer-only-after-inline-triage` | All active `[id: …]` in AGENTS.md — none fabricated or retired |
| `../learnings/test-failures/2026-07-20-a-fixture-seam-…md` | Resolves on disk |
| Milestone `Post-MVP / Later` | Exists |

**AC command verification (run as written):** AC10 returns `1` today → `0` after (genuine
discriminator). **AC8 returns `0` today**, so it is a guard against introducing the
truncating call, not a state-change proof — annotated inline so no reviewer misreads it.
Finding this is itself an instance of the plan's own thesis: an assertion that passes
before and after looks like coverage and is not.

**No further research agents spawned.** Six reviewers had already run against v1/v2 and
converged; the marginal value was in mechanical verification of every citation and command,
which is what this pass did. `bats` absent re-confirmed (`command -v bats` empty) — the
`.test.sh` convention stands.

## Sharp Edges

- **A guard appended after an early exit that its own target population triggers is dead
  code.** The label gate's population produces empty `EMBEDDED`, so appending it after
  `[[ -n "$EMBEDDED" ]] || exit 0` makes it unreachable — while every test still passes,
  because tests exercise the deny path directly. Derive both arms, exit only when both are empty.
- **`gh issue list` silently truncates at 30.** This plan's v1 built its central gate on a
  probe that returned exactly the default page size and read it as the whole set (44 exist;
  the 14 hidden are the oldest). Any `gh … list` in a guard needs `--limit` plus a
  full-page-means-possibly-truncated check — or, better, restructure to a lookup that
  cannot paginate.
- **`gh` resolves the repo from cwd; passing `--repo` invites a slug bug.** Prefer
  `(cd "$WORK_DIR" && gh …)`, as `ship-soak-followthrough-gate.sh` already does. The
  `--repo` form is what made D1 possible, and the "correct" sibling `sed` still mangles
  SSH-alias remotes.
- **A body-path test that passes before the fix proves nothing** — and a body-only RED
  proves little either. Require the commit case green in the same run, or a broken stub
  reads as a reproduced bug.
- **Never scrape bare `#N` from a scanner-matched line.** Strip the `^N:` line-number
  prefix, pair each number with its own preceding keyword, and compare exact tokens —
  otherwise you deny over a `Ref`, invent issue #12 from a line number, or match `#661`
  against `6617`.
- **A dogfooding gate can block its own PR.** Prose fixtures quoted into a PR body are real
  input to the guard once it works. Keep RED evidence in git history, not the PR body.
