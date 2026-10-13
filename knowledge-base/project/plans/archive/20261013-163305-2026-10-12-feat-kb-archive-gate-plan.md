---
title: "feat: gate PR merge on unarchived KB artifacts (kb-archive-gate)"
type: feat
date: 2026-10-12
slug: kb-archive-gate
branch: kb-archive-gate
issue: none
lane: cross-domain
---

# feat: gate PR merge on unarchived KB artifacts (kb-archive-gate)

## Enhancement Summary

**Deepened on:** 2026-10-12
**Sections enhanced:** Proposed Solution (a)/(d), Guard Contract, Acceptance Criteria, Dependencies & Risks, Research Insights
**Research agents used:** sequential-fallback (no Task tool in this session — deepen research ran as inline greps/reads; `Reviewed-Coverage: sequential-fallback`)
**Gates cleared (§4.x):** 4.6 User-Brand Impact present+valid; 4.7 Observability present+valid; 4.8 PAT scan clean; 4.9 UI-wireframe skipped (no UI surface); 4.10 Encryption Posture skipped (no store/connection); 4.55 Downtime skipped; 4.5 Network-Outage trigger 0 hits in Overview/Problem; 4.11 `lint-guard-contract.py` green (1 guard); 4.12 Scope Check 1 unfenced section, mechanically compliant; 4.4 precedent-diff satisfied (pre-merge-rebase.sh cited); 4.45 realism passes run inline

### Key Improvements

1. **Resolver adopted verbatim** — `pre-merge-rebase.sh`'s #8778/#9401
   PR-head resolver (same-repo pointer proof, scan/cmd agreement, `cd`
   scan, `refs/pull/N/head` fetch, `--help` pass-through) imported
   byte-for-byte and parity-pinned instead of the v1 hand-rolled
   HEAD-only check — kills the drain-prs false-deny/false-pass pair.
2. **Trigger boundary widened** — `\s--\s`, `\(`, bare `|`, and an
   invocation-prefix clause (env assignments + `if`/`time`/`sudo`/…)
   added; the sibling's chain-only boundary misses ship's own
   `with_lock merge-main 600 -- gh pr merge` arming form.
3. **Fail-open scope refined** — `main`/detached/`bare` exempt only the
   HEAD path; numbered/`--match-head-commit` merges gate on every
   checkout state (coverage for `soleur:schedule`/drain sessions).
4. **#7383 resolved by measurement** — `archive-kb.sh --dry-run` on a
   live `feat-one-shot-*` worktree lists the topic-named plan; remaining
   gap is discovery of *untracked* artifacts, fixed in Phase 4.

### New Considerations Discovered

- Sibling hooks `ship-unpushed-commits-gate.sh`/`cla-signed-author-gate.sh`
  share the pre-`--` boundary gap — deferral runs the
  `wg-defer-only-after-inline-triage` triple test at ship: pass → file the
  `type/chore` tracking issue; fail → durable in-place documentation
  (comments at each sibling's trigger line), never conversation-only.
- `archive-kb.sh` already `git add`s before `git mv` (:244-246), so the
  untracked fix is discovery-only.
- Multi-PR commands (`gh pr merge 42 && gh pr merge 43`) stay in the
  conservative L-deny posture per the sibling's "one PR per command".

## Overview

KB session artifacts — `knowledge-base/project/specs/<dir>/`, `plans/*.md`,
`brainstorms/*.md` — must be `git mv`'d into their `archive/` subdirectories
inside the feature PR. On PR #10064 the in-PR archival step (`soleur:ship`
Phase 6 step 5.5, running `archive-kb.sh`) was silently skipped: the PR merged
with `specs/feat-one-shot-plugin-version-visibility/` and its plan live on
`main`. Measured on `origin/main` 2026-10-12: ~1747 live spec dirs (the brief's
1540-of-1751 figure has drifted only by sibling merges), `specs/archive/`
holds 652. A sibling session sweeps the existing backlog
(`kb-archive-sweep` worktree); **this plan only stops NEW leaks** — it does
not touch the backlog or `archive/`.

Three changes, one enforcement unit:

1. **A PreToolUse deny hook** (`.claude/hooks/ship-kb-archive-gate.sh`),
   modeled on `ship-unpushed-commits-gate.sh`, that denies `gh pr merge` when
   the PR head's diff vs `origin/main` adds or modifies non-`archive/` files
   under the three KB artifact roots.
2. **`soleur:ship` restructure**: promote step 5.5's archival block into its
   own named phase — `## Phase 6.45: KB Artifact Archival` — placed in the
   shared tail both PR arms converge through, before any `gh pr ready` /
   `gh pr merge`.
3. **`soleur:postmerge` report-only read-back** (`## Phase 5.8`): flag KB
   artifacts a merged PR landed at live paths and name the one-line archive
   command — the detective backstop for leaks that slip every preventive
   gate (manual UI merges, `gh api`, other harnesses).

Plus: verify `archive-kb.sh` discovery on a one-shot branch (verified — see
Research Insights) and close its residual untracked-file gap.

## Problem Statement / Motivation

Root causes, per the brief and verified in-tree:

1. Step 5.5 is buried as a numbered item inside Phase 6's **"If an open PR
   exists"** conditional list (`ship/SKILL.md:1967`). An agent that writes
   the PR body itself — or walks the "no open PR exists" arm — never
   encounters it. The step is also invisible to the Phase 5 Final Checklist.
2. Nothing mechanical checks the result: no hook, no CI job, no post-merge
   verification. The failure is indistinguishable from success.
3. `cleanup-merged` does not durably archive for the general merge-time
   case (its archive step is scoped to legacy pre-#2815 bare-root specs and
   reaped branches; ADR-258's `reap_archive_persist` covers the reap path,
   not a ship-time skip).
4. `archive-kb.sh` discovery must cover `feat-one-shot-*` spec dirs and
   topic-named plans — **verified OK** (branch-diff discovery, #9803):
   dry-run on `feat-one-shot-9969-edge-roots` listed the topic-named plan
   `2026-10-12-fix-affected-edges-under-cover-siblings-plan.md` and the spec
   dir. Residual: **untracked** artifact files are invisible to
   `git diff` (branch-diff only sees committed state; a topic-named plan
   left uncommitted or a non-`feat-*` spec dir uncommitted is still missed),
   and an unresolvable merge-base silently degrades to slug-only.

## Proposed Solution

### (a) `.claude/hooks/ship-kb-archive-gate.sh` — deny `gh pr merge` on live-path KB artifacts

Modeled on `.claude/hooks/ship-unpushed-commits-gate.sh` — same input contract
(`hook_parse_input` on stdin, fail-hard source of `lib/incidents.sh` +
`lib/hook-input.sh`, `declare -f` guard), same deny-JSON shape
(`permissionDecision: "deny"`, `hookEventName: "PreToolUse"`), same incident
telemetry via `emit_incident`. Two corrections over the sibling, both
precedented in-tree:

- **Trigger boundary** — `(^|&&|\|\||\||;|\(|\s--\s)` plus an optional
  invocation prefix `(<assignment>|if|while|until|then|do|elif|else|!|time|env|command|builtin|exec|nohup|sudo)\s+`
  (repeated; `prod-write-defer-gate.sh:179`'s assignment clause extended
  with the keyword set — `time gh pr merge`, `if gh pr merge`, `! gh pr
  merge` are the same bypass class). The bare
  `(^|&&|\|\||;)` shape (the sibling's, and `cla-signed-author-gate`'s)
  misses ship's own sanctioned arming form
  `bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge` (the `\s--\s`
  member, `pre-merge-rebase.sh:121`), a `FOO=x gh pr merge` env prefix,
  and the `$(…)`/pipe substitution forms. A gate that cannot see the
  wrapped arm never fires on the main path (#3689 class). Documented
  residuals, shared with every sibling and named so the postmerge
  backstop owns them: quoted `bash -c '…'` / `sh -c` payloads (stripped
  by `strip_command_bodies`), `eval "…"` indirection, variable/alias
  invocation (`$GH pr merge`), `gh api …/merge`, and UI merges — none
  fire the regex; Phase 5.8 reports the landed result regardless.
  **Binding nuances (CTO ruling):** the trigger must NOT absorb the
  sibling's `ready` alternation — `gh pr merge` alone (ruling: ready
  marks review-readiness, not publication); the `\s--\s` member appears
  in BOTH the fire-check regex and `_merge_args`' extraction regex, as
  it does in the sibling's two sites.
- **PR-head resolution** — import `pre-merge-rebase.sh`'s #8778/#9401
  resolver VERBATIM (byte-copied helpers with a provenance comment, parity-
  pinned by a suite row that diffs each function body against
  `pre-merge-rebase.sh` — the `assert_fixture_dir` copy convention):
  `_merge_args`, the `--help`/`-h`
  pass-through, `_repo_url_parts`, `_repo_flag_operands`,
  `_repo_env_operands`, `_repo_pointers_same_repo`, `_strip_repo_flags`,
  the scan/cmd-agreement `MERGE_TARGET_WHY` ladder, the in-command `cd`
  foreign-checkout scan, the `timeout`→`gtimeout`→bare portability wrapper,
  and the `^[0-9a-f]{40}$` oid validation. `drain-prs`/`merge-pr` arm other
  branches' PRs from whatever CWD the session sits in (`gh pr merge -R
  <repo> <N>` is their emitted form) — a HEAD-only check false-denies a
  clean-PR merge issued from a dirty branch and false-passes a leaky
  merge issued from a clean one.

Logic:

1. Exit 0 unless `gh pr merge` matches the trigger in `$SCAN`
   (`gh pr ready` NOT gated — decision-challenges: ready marks
   review-readiness, not publication; the merge is the leak event, and a
   ready-deny would hit legitimate draft-for-review flows).
2. `--help`/`-h`-only invocations → exit 0 (sibling pass-through).
3. Validate `.cwd` (absolute, existing dir) → `git rev-parse --git-dir`.
4. **Target resolution** (verbatim-imported ladder): scan/cmd-agreement;
   repo-pointer sighting `-R`/`--repo`/`GH_REPO=`/`GH_HOST=` → all must
   prove same-repo else `MERGE_TARGET_WHY` (proven-foreign pointers →
   exit 0, the merge isn't ours; unprovable → deny). Head precedence:
   `--match-head-commit <40-hex>` (the admin-hatch's exact merged sha) >
   one bare PR number N > HEAD (flag-first or arg-less invocations).
   For N: `git fetch --no-tags origin "refs/pull/${N}/head"` → FETCH_HEAD
   (verified fetchable on real origin: `refs/pull/10064/head` →
   `88a8375`; creatable in fixture bare repos via `git push origin
   HEAD:refs/pull/N/head` — no `gh` dependency). L-state (mixed numbers,
   non-bare target, foreign cd, >1 PR in one command) → **deny** carrying
   `MERGE_TARGET_WHY` — for this gate a HEAD fallback on a wrong target
   is both a false-pass and a false-deny; the multi-PR posture mirrors
   the sibling's "merge one PR per command" and stays conservative —
   looping per-invocation is a defensible v2, not v1. **Boundary
   (CTO ruling):** the L-deny applies only to invocations that CARRY a
   target token the ladder cannot prove; a purely flag-only invocation
   (`gh pr merge --squash --auto`, no positional) has no named target
   and correctly takes the HEAD path — do not conflate `--squash` (a
   flag) with `somebranch` (a non-bare positional). Flag-first-with-
   number stays in the conservative deny; the deny text says to reorder.
5. **Fail-open scope (refined ruling — decision-challenges).** The brief's
   `main`/`detached`/`bare` fail-opens apply to the HEAD-based path,
   where the branch is the measured object and HEAD is meaningless in
   those states. A numbered or `--match-head-commit` merge is always
   verifiable (it resolves a pushed object), so it gates **regardless**
   of local branch state — `soleur:schedule` merges from a main checkout
   (#8791) and drain sessions still get coverage; a release-class PR
   carries no KB artifacts and passes cleanly. `SOLEUR_SKIP_KB_ARCHIVE_GATE=1`
   env escape mirrors the sibling's env contract.
6. `git fetch --no-tags origin main` — **fail-closed deny** on failure
   (sibling T9 posture; unverifiable head is the silent-miss class).
   `base=$(git merge-base origin/main "$HEAD_SHA")`; empty base (shallow
   clone) → exit 0 **with a `headless_or_stderr` warn naming the cause**
   (CTO ruling: no fail-open path is silent — a silent pass on an
   unmeasurable merge is the reports-clean-because-it-could-not-look
   shape).
7. `git diff --name-status -z --diff-filter=AM "$base"..."$HEAD_SHA" --
   knowledge-base/project/specs knowledge-base/project/plans
   knowledge-base/project/brainstorms` (the `-z` + `read -d ''` form —
   `--name-status` alone quotes paths containing special characters).
   Drop rows whose path matches `*/archive/*`; for `specs/` require
   depth ≥ 2 (`specs/<dir>/<file>`, `<dir>` != `archive`; a root-level
   `specs/.gitkeep` never fires). Any remaining row → DENY.
   - `A` rows = artifact created on-branch and still live = the #10064
     leak shape.
   - `M` rows = artifact live at base AND head, unarchived by this PR —
     included per the brief's "adds or modifies" (decision-challenges row).
   - `R`/`D` rows excluded by the `AM` filter; a `git mv` to `archive/`
     nets only `archive/` additions — compliant diffs pass cleanly.
   - **Learnings are never archived** (`learnings/` is not a gated root);
     neither are `engineering/`, `product/`, `operations/`, `legal/` —
     permanent-KB docs, not session artifacts.
8. Deny: `emit_incident "wg-kb-artifacts-archived-in-pr" deny …` + jq JSON.
   Reason lists ≤10 sanitized rows (sibling's C0/DEL/U+2028-9 strip +
   80-char truncation) and prints the exact remediation + ordering caveat:

   > Fix: `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`
   > then `git add -A knowledge-base && git commit -m "chore(kb): archive
   > <branch> artifacts at ship" && git push` — the check reads the pushed
   > PR head, so a local-only archive does not clear it.
   > For an `M`-row on `specs/<dir>/` (archive-kb refuses to collapse a
   > modified live spec dir by design): `git mv
   > knowledge-base/project/specs/<dir>
   > knowledge-base/project/specs/archive/<ts>-<dir>` + commit + push.
   > Ordering: archive only AFTER ship's last live-path reads — Phase 6
   > step 2.5 (decision-challenges render) and step 5 (Operator Holds).
   > It belongs inside ship `## Phase 6.45: KB Artifact Archival`.
   > Hatch: `SOLEUR_SKIP_KB_ARCHIVE_GATE=1` bypasses (named in the deny —
   > an undocumented hatch is discoverable only by reading the hook).

   Registration: `.claude/settings.json` PreToolUse/`Bash` immediately after
   `ship-unpushed-commits-gate.sh` (after `pre-merge-rebase.sh` so auto-sync
   pushes land first); `.devin/config.json` `^exec$` block mirroring the same
   relative order; one `bind devin-tool=exec` row in
   `.claude/hooks/devin-dispositions.tsv`. `plugins/soleur/hooks/hooks.json`
   is NOT touched — the ship-* family is repo-dev, not plugin-shipped.

   Adjacent finding (deferral): `ship-unpushed-commits-gate.sh` and
   `cla-signed-author-gate.sh` still use the `(^|&&|\|\||;)`-only boundary,
   so the `with_lock -- gh pr merge` form bypasses them on the sanctioned
   arming path — the same #3689 class `pre-merge-rebase.sh` fixed. Out of
   this plan's edit set; the recording mechanism is conditional per the
   CTO ruling — run the `wg-defer-only-after-inline-triage` triple test
   at ship time: pass → file the `type/chore` tracking issue (per
   `wg-when-deferring-a-capability-create-a`); fail → durable in-place
   documentation (this Non-Goals note + a comment at each sibling's
   trigger line naming the gap), never conversation-only.

### (b) `soleur:ship` — promote archival to `## Phase 6.45: KB Artifact Archival`

- New `## Phase 6.45: KB Artifact Archival` placed between the "If no open
  PR exists" `gh pr create` block and `### Semver Label and Changelog`.
  Both arms converge there: the exists-arm falls out of step 5 (Operator
  Holds) → skips the create block → Phase 6.45; the create-arm runs
  `gh pr create` → Phase 6.45. The moved content is step 5.5's body
  verbatim (archive-kb.sh invocation, commit-and-push rider, stale-
  reference sweep, partial-discovery WARNING handling, ordering caveat,
  re-entry-from-archive note) plus the `[skill-enforced: ship Phase 6.45 +
  hook ship-kb-archive-gate.sh]` marker and the `SOLEUR_RULE_APPLIED` echo
  for `wg-kb-artifacts-archived-in-pr`.
- Exists-arm: delete step 5.5; steps 6–7 (`gh pr ready`, `wait-ready-run`,
  `gh pr merge --squash --auto`, UNTRUSTED-CI announce, present-URL)
  **move into Phase 6.5's `### CI Status Check` subsection** as the single
  arming site —
  `if isDraft: ready + wait-ready-run` before the merge-main-lock
  `gh pr merge --squash --auto`. This is what makes "named phase before
  merge" structurally true for BOTH arms: there is no `gh pr merge` site
  left before Phase 6.45. (Rejected alternative: an in-place `###` heading
  inside the exists-arm — smaller diff but keeps the conditional-wrap and
  two arming sites, which is the root cause being fixed.) **CTO nuance:**
  Phase 7's CI-failure recovery retains its `gh pr merge <number>
  --squash --auto` re-queue — a second merge site by construction, but
  post-archive and still covered by the hook; the invariant is "no merge
  site before Phase 6.45", not "one site total". Do not remove it.
- Phase 5 Final Checklist gains `- [ ] KB artifacts archived (Phase 6.45
  gate)` between the Phase 5.5 gate rows and "Push to remote".
- Cross-reference updates (all "Phase 6 step 5.5"/"step 6" pins):
  `ship/SKILL.md:2982-2989` ("the in-PR archival point" passage → name
  Phase 6.45 + the hook), `archive-kb/SKILL.md:30`, `compound/SKILL.md:517`,
  `ship/references/ready-run-wait.md:5` and
  `ship/references/settle-then-admin-merge.md:117` (mark-ready site moves
  to Phase 6.5). Steps 2.5/4/4.5/5 numbers unchanged.

### (c) `soleur:postmerge` — `## Phase 5.8: KB archival read-back (REPORT-ONLY)`

After Phase 5.7, before Phase 6. For the merged squash commit:
`git diff --name-status --diff-filter=AM "${MERGE_SHA}^" "${MERGE_SHA}" --
<three roots>` (single-parent diff works for the squash shape and for a
first-parent merge commit). Non-`archive/` A/M rows = artifacts the merge
landed live. Report them verbatim as a red post-merge status in the Phase
6 issue comment and the Phase 7 summary, naming the one-line fix:
`bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (on a new
branch + PR — archive cannot ride a merged PR). Report-only like Phases
5.5/5.6/5.7: never blocks "done"; it is the catch-net for every merge
path the hook cannot see (UI merges, `gh api`, queue merges from other
harnesses).

### (d) `archive-kb.sh` discovery — verified + residual fix

Verified: the #9803 `discover_branch_diff` covers `feat-one-shot-*` spec
dirs (A-row collapse) and topic-named plans (commit provenance) — measured
dry-run above. Remaining gap fixed in this PR: extend discovery to
**untracked** artifact paths (`git status --porcelain --
knowledge-base/project/{specs,plans,brainstorms}`, same `*/archive/*`
exclusion and spec-dir collapse), closing the last silent-miss for
uncommitted topic-named plans / non-`feat-*` spec dirs — the residual of
#7383 and adjacent to #9172's staged-but-unpersisted class (noted, not
fixed here). Discovery is the only gap: the move path already runs
`git add "$artifact"` before `git mv` (`archive-kb.sh:244-246`), so an
untracked file moves cleanly once listed. **Scope (CTO ruling):** `??`
rows only — staged/modified rows are already covered by branch-diff for
tracked files; keep the spec-dir collapse symmetric (an untracked dir
under `specs/` collapses to the dir; a lone untracked root-level file
such as `specs/.gitkeep` does not fire).

## Technical Considerations

- **Hook input is untrusted (ADR-156/157):** no shell eval of stdin;
  `hook_parse_input` + `hook_input_emit_ask` on parse failure, exit 0.
- **`gh pr ready` NOT gated** (assumed ruling — decision-challenges):
  ready marks review-readiness, not publication; the merge is the leak
  event. A `gh pr ready` deny would hit a legitimate draft-for-review
  flow on non-ship paths.
- **Fail-open scope** (ruling — decision-challenges): `main`/`detached`/
  `bare` exempt only the HEAD-based path; numbered and
  `--match-head-commit` merges resolve pushed objects and gate on every
  checkout state.
- **Verbatim import vs lib extraction** (ruling): the resolver helpers are
  copied byte-for-byte from `pre-merge-rebase.sh` and parity-pinned by a
  suite row, per the repo's copied-helper convention (`assert_fixture_dir`
  is pinned byte-equal by `fixture-dir-operand-assert.test.sh`). A
  shared `lib/` extraction would force an edit to the live review-evidence
  gate for ~zero net code — rejected.
- **Ordering in the hook chain:** registered after `pre-merge-rebase.sh`
  (auto-sync pushes reflected) and after `ship-unpushed-commits-gate.sh`.
  The hook itself mutates nothing — only fetches — so ordering beyond that
  is inert.
- **Self-application:** this PR adds `specs/kb-archive-gate/` + this plan
  at live paths — ship's Phase 6.45 must archive them or the new gate
  denies this PR's own merge. That is the designed bootstrap proof.
- **No `gh` dependency in the hook** — `refs/pull/<N>/head` is a git ref
  (verified `git ls-remote origin 'refs/pull/10064/head'` → `88a8375`);
  fixtures push it to a local bare origin
  (`git push origin HEAD:refs/pull/N/head`).
- **AGENTS budget (measured at plan time):**
  `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` →
  `B_ALWAYS=43435` vs the 46000-byte cap → ~2565 B headroom; a ~60 B index
  pointer + a ≤600 B rule body for `wg-kb-artifacts-archived-in-pr` fits.
  Rule id verified unique repo-wide.
- **Test suite** `.claude/hooks/ship-kb-archive-gate.test.sh`: fixture
  bare-origin + work pattern per the sibling suite; both-direction cases
  (deny AND must-pass non-canonical); `MIN_ASSERTIONS` exact case floor +
  `pass+fail == cases` accounting + `UNRESOLVED` (exit 3) on missing
  jq/git + a fixture-nonempty vacuity control (assert the live-path file
  exists in the fixture before asserting the deny); registered in
  `scripts/suite-shard-legs.tsv` via
  `python3 scripts/regenerate-shard-manifest.py --incremental --write`.
- **`AGENTS.rules.md`:** proposed new workflow-gate entry
  `wg-kb-artifacts-archived-in-pr` (one line, `cq-agents-md-tier-gate`
  Workflow-Gates tier — the violation can only occur in the ship pipeline)
  plus the `AGENTS.md` index line. If the tier gate rejects a corpus entry,
  fall back to the synthetic `<prefix>-*` rule-id namespace the incidents
  lib allows.
- Semver: `semver:minor` (new `.claude/hooks` component + skill phases;
  no plugin components added — hooks are repo-dev).
- Portability (sharp edge): the hook uses `git`, `jq`, `grep`, `sed`,
  `awk`, `tr`, `head` only — no GNU-only flags, no `timeout`; bash 3.2
  compatible (no `declare -A`), `set -eo pipefail` without `-u` per
  sibling convention.
- NFR: none — read `nfr-register.md` not applicable to a local hook; the
  only perf surface is one `git fetch` + one diff per `gh pr merge` call.

## User-Brand Impact

- **If this lands broken, the user experiences:** a legitimate
  `gh pr merge` denied mid-pipeline with a remediation message that does
  not fit their case — or, on the false-pass side, another merged PR
  silently leaving spec/session-state files live on `main` forever.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  unfinished session artifacts (decision rationale, session-state,
  task lists referencing internal issue numbers) staying publicly visible
  at live paths on `main` instead of being filed under `archive/`.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal workflow tooling that
  gates developer-facing git commands; the sensitive-path regex
  (`SENSITIVE_PATH_RE`: `apps/*/infra`, `server`, `supabase`, `app/api`,
  auth/doppler/credential workflows) is untouched — no user-data or
  production surface is modified.

## Observability

```yaml
liveness_signal:
  what: "ship-kb-archive-gate.test.sh green in the hooks shard of scripts/test-all.sh"
  cadence: "per-PR CI (required `test` check)"
  alert_target: "required-check failure on the PR"
  configured_in: ".claude/hooks/ship-kb-archive-gate.test.sh + scripts/suite-shard-legs.tsv"
error_reporting:
  destination: ".claude/.rule-incidents.jsonl via emit_incident (rule wg-kb-artifacts-archived-in-pr)"
  fail_loud: "PreToolUse deny JSON rendered in the agent transcript; incident row per deny"
failure_modes:
  - mode: "hook present but not dispatched (settings/devin registry drift)"
    detection: "registration assertions in ship-kb-archive-gate.test.sh + devin-matcher-parity.test.sh"
    alert_route: "CI red"
  - mode: "deny message names remediation that no longer exists (archive-kb.sh moved)"
    detection: "deny-reason content assertions in the suite"
    alert_route: "CI red"
logs:
  where: ".claude/.rule-incidents.jsonl + hook stderr"
  retention: "repo-local jsonl (incident rotation per lib/incidents.sh)"
discoverability_test:
  command: "grep -o ship-kb-archive-gate.sh .claude/settings.json"
  expected_output: "ship-kb-archive-gate.sh"
```

(Section included defensively: Phase 2.9's path detection —
`apps/*/server|src|infra`, `plugins/*/scripts`, new infra surface — does
not fire; the hook lives in `.claude/hooks/` and emits its own incident
telemetry.)

## Guard Contract

### Guard 1 — `ship-kb-archive-gate.sh` deny hook (+ its test suite)

**Property.** Before an agent-issued `gh pr merge` executes, zero A/M rows
exist at non-`archive/` paths under
`knowledge-base/project/{specs,plans,brainstorms}` in the PR head's diff
vs `origin/main`.

**Assembly.** Chokepoint: the PreToolUse `Bash`/`exec` matcher — every
shell command the agent issues flows through it; the trigger regex covers
`gh pr merge` at every command boundary (`^`, `&&`, `||`, `;`) after
`strip_command_bodies` removes commit bodies/heredocs. The artifact
population is a mechanical census: `git diff --name-status --diff-filter=AM`
over the three roots, not a hand-maintained list. Registrations:
`.claude/settings.json` + `.devin/config.json` + the dispositions ledger —
three sites, all pinned by the suite.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture branch adds `specs/<dir>/tasks.md` live, `gh pr merge` issued | hook denies — else RED |
| 2 | Narrow the trigger regex to `^gh pr merge` (drop chain clause): `x && gh pr merge` slips | suite's chained-form case turns RED |
| 3 | Drop the `\s--\s` boundary: `with_lock merge-main 600 -- gh pr merge` slips | wrapped-form case turns RED — the #3689 class |
| 4 | Second member after compliant first: `specs/a/` archived in-diff, `specs/b/` still live | still denies — first-member short-circuit is the defect class |
| 5 | Topic-named plan at `plans/*.md` live (slug ≠ branch) | denies — covers the #7383 shape |
| 6 | `M` row on a spec file live at base | denies per the AM contract — an A-only filter vacates it |
| 7 | `gh pr merge <N>` resolving `refs/pull/N/head` on the fixture bare origin, issued from a different (clean) branch | denies on the REMOTE head's artifacts — the drain-prs shape |
| 8 | Harness: weaken assert_deny to accept any exit-0 | vacuity accounting (`pass+fail==cases`, MIN_ASSERTIONS floor) + fixture-nonempty control turn RED |
| 9 | Must-PASS: diff adds only `learnings/*.md`, or only `*/archive/*` paths (sweep-shaped PR) | silent pass — a deny-everything guard cannot detect itself without must-PASS rows |
| 10 | Must-PASS: `gh pr merge` inside a quoted string / commit `-m` body, `gh pr merge --help` | no fire — substring/help false-positive |

**Anchor.** The guard reads state derived at call time (merge-base +
head SHA), not a stored value; fixtures are synthesized per-run into tmp
dirs outside the commit — no single diff can weaken both the SUT and the
population it is measured against.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "A PreToolUse hook modeled on .claude/hooks/ship-unpushed-commits-gate.sh that denies `gh pr merge` (and `gh pr ready` if sensible) … Fail open on main, detached HEAD and bare repo." | FR-1 / Phase 1 / Files-to-Create `.claude/hooks/ship-kb-archive-gate.sh` | mapped |
| 2 | "Add a bash test suite with both-direction fixtures, an exact case floor and a vacuity guard; register it in scripts/suite-shard-legs.tsv." | FR-2 / Phase 1 / Files-to-Create `.claude/hooks/ship-kb-archive-gate.test.sh` + `suite-shard-legs.tsv` edit | mapped |
| 3 | "In plugins/soleur/skills/ship/SKILL.md, promote archival into its own named phase before push/merge, add it to the Phase 5 Final Checklist, and update every cross-reference and test that pins the old step number." | FR-3 / Phase 2 / ship SKILL.md + archive-kb SKILL.md + compound SKILL.md + ready-run-wait.md + settle-then-admin-merge.md edits | mapped |
| 4 | "A report-only post-merge phase in plugins/soleur/skills/postmerge/SKILL.md that flags added KB artifacts still at live paths on origin/main and names the one-line archive command." | FR-4 / Phase 3 / postmerge SKILL.md edit | mapped |
| 5 | "Verify an archive-kb.sh dry run on a one-shot branch lists the spec dir and the plan (learnings are never archived). … discovery for topic-named plans is in scope to check/fix" | FR-5 / Phase 4 / archive-kb.sh untracked-discovery extension + verification record | mapped |
| 6 | "do NOT touch the existing backlog or knowledge-base/project/specs/archive" | AC-19 scope guard — no `archive/` writes, no backlog moves | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `.claude/hooks/ship-kb-archive-gate.sh` | "A PreToolUse hook modeled on .claude/hooks/ship-unpushed-commits-gate.sh that denies `gh pr merge`" | asked |
| `.claude/hooks/ship-kb-archive-gate.test.sh` | "Add a bash test suite with both-direction fixtures, an exact case floor and a vacuity guard" | asked |
| `settings.json` / `.devin/config.json` / `devin-dispositions.tsv` registrations | "A PreToolUse hook" — inferred registration sites | inferred — justification: a hook no registry dispatches is dead code; `devin-matcher-parity.test.sh` fails any registration without a disposition row |
| `scripts/suite-shard-legs.tsv` | "register it in scripts/suite-shard-legs.tsv" | asked |
| ship SKILL.md Phase 6.45 + Phase 6.5 arming consolidation | "promote archival into its own named phase before push/merge" | asked |
| postmerge Phase 5.8 | "A report-only post-merge phase in plugins/soleur/skills/postmerge/SKILL.md" | asked |
| archive-kb.sh untracked discovery | "discovery for topic-named plans is in scope to check/fix" | asked |
| `AGENTS.rules.md` + `AGENTS.md` rule entry | — | inferred — justification: every ship-* deny hook emits a corpus-backed rule id via `emit_incident`; without the entry the incident telemetry cites a rule that does not exist. Contingent on `cq-agents-md-tier-gate` placement. |
| decision-challenges.md / tasks.md / this plan | pipeline convention | inferred — justification: one-shot pipeline artifacts (ADR-084 render + Save Tasks contract) |

### Split Assessment

- Subsystems touched: 5 — `.claude`, `.devin`, `scripts`, `plugins`, `knowledge-base`
- Planned files: 15 | Estimated changed lines: ~900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over the subsystem and lines thresholds on
  paper, but it is ONE enforcement unit: the hook's deny message references
  the new phase, and landing the gate without the skill restructure (or
  vice versa) leaves the doc/mechanism split mid-flight. No natural seam.

## Acceptance Criteria

- [ ] AC1: `bash .claude/hooks/ship-kb-archive-gate.test.sh` exits 0 with
  `FAIL=0`; the suite carries a `MIN_ASSERTIONS` exact floor, a
  `pass+fail == cases` accounting block, an `UNRESOLVED` (exit 3) arm on
  missing jq/git, and a fixture-nonempty vacuity control; it is listed in
  `scripts/suite-shard-legs.tsv` and `bash
  scripts/lint-orphan-test-suites.sh` reports no orphan.
- [ ] AC2: fixture — branch adds `specs/<dir>/<file>` live; `gh pr merge`
  denied; reason contains `archive-kb.sh`, the ordering tokens for
  step 2.5 / Operator Holds, the manual `git mv … specs/archive/` path
  (for `M`-on-`specs/` denies archive-kb refuses), and the
  `SOLEUR_SKIP_KB_ARCHIVE_GATE` hatch name.
- [ ] AC3: fixture — topic-named plan added live (plan slug ≠ branch
  slug); `gh pr merge` denied (#7383 shape).
- [ ] AC4: fixture — `M` row on a spec file live at base; denied.
- [ ] AC5: fixture — brainstorm `A` row at live path; denied.
- [ ] AC6: fixture — same artifacts committed under `archive/` paths only
  (the post-archive shape); `gh pr merge` passes silently.
- [ ] AC7: fixture — additions confined to `learnings/` and non-KB code;
  passes (learnings are never archived).
- [ ] AC8: HEAD-path fail-open verified on `main`/`master`, detached HEAD,
  non-git-dir, and unresolvable merge-base — the merge-base case exits 0
  but emits a `headless_or_stderr` warn naming the cause (never silent) —
  while `gh pr merge <N>` on the same states still resolves `pull/N/head`
  and gates.
- [ ] AC9: no fire on non-matching commands, quoted-string/commit-body
  `gh pr merge`, `gh pr merge --help`, `bash -c` quoted payloads (the
  documented strip residual), and `gh pr ready`.
- [ ] AC10: trigger coverage fixtures — `with_lock merge-main 600 --
  gh pr merge`, `FOO=1 gh pr merge`, `x | gh pr merge`, `$(gh pr merge)`,
  `time gh pr merge`, `if gh pr merge; then …` all fire; each with a deny
  on a leaky fixture branch.
- [ ] AC11: head-resolution fixtures — `gh pr merge --squash --auto`
  (flag-first → HEAD); `gh pr merge <N>` → `refs/pull/<N>/head` fetched
  from the fixture bare origin and gated on the REMOTE head;
  `gh pr merge --admin --match-head-commit <40-hex>` → the pinned sha
  gated; `-R <same-repo>` proven → resolved; foreign or unprovable repo
  pointer → deny carrying `MERGE_TARGET_WHY`; in-command `cd` into a
  foreign checkout → deny; multi-invocation disagreement (raw vs
  quote-stripped `877"9"`) → deny.
- [ ] AC12: fail-closed deny when `git fetch origin` fails, with the
  reason naming the fetch; `SOLEUR_SKIP_KB_ARCHIVE_GATE=1` passes.
- [ ] AC13: deny output is exactly one JSON object on stdout,
  `permissionDecision == "deny"`, `hookEventName == "PreToolUse"`, and one
  incident row with `rule_id` `wg-kb-artifacts-archived-in-pr`.
- [ ] AC14: `.claude/settings.json` registers the hook under
  PreToolUse/`Bash` after `ship-unpushed-commits-gate.sh`;
  `.devin/config.json` registers the `^exec$` twin in mirrored order;
  `.claude/hooks/devin-dispositions.tsv` carries a `bind` row —
  `devin-matcher-parity.test.sh` green. A parity row diffs the copied
  resolver helpers byte-for-byte against `pre-merge-rebase.sh`.
- [ ] AC15: `ship/SKILL.md` contains `## Phase 6.45: KB Artifact
  Archival`; the old `5.5.` numbered item is gone; in document order no
  `gh pr ready`/`gh pr merge` instruction precedes Phase 6.45 inside
  Phase 6; the Phase 5 Final Checklist lists the archive line; the
  `gh pr merge --squash --auto` arming site sits inside Phase 6.5.
- [ ] AC16: no remaining stale step pins: `grep -rn 'Phase 6 step'
  plugins/soleur/skills/{archive-kb,compound,ship}` returns only hits
  naming steps 2.5/4/4.5/5 in their unchanged meanings;
  `archive-kb/SKILL.md`, `compound/SKILL.md`, `ready-run-wait.md`,
  `settle-then-admin-merge.md`, `ship/SKILL.md`'s Phase-7 archival
  discussion name Phase 6.45 / Phase 6.5. (`work/SKILL.md`'s "one-shot's
  step 5.5" is a different step numbering — not a hit.)
- [ ] AC17: `postmerge/SKILL.md` contains `## Phase 5.8` report-only
  read-back naming `archive-kb.sh`; no blocking language on the
  "done" verdict.
- [ ] AC18: `archive-kb.sh --dry-run` on `feat-one-shot-9969-edge-roots`
  (or equivalent fixture) lists the spec dir and the topic-named plan —
  plus, after the extension, untracked KB files.
- [ ] AC19: `git diff --name-only origin/main...HEAD` on this PR touches
  ZERO paths under `*/archive/` and ZERO pre-existing `specs/<dir>` dirs
  other than `specs/kb-archive-gate/` (scope guard — no backlog edits).
- [ ] AC20: `wg-kb-artifacts-archived-in-pr` appears exactly once in
  `AGENTS.rules.md` (Workflow Gates tier, ≤600-byte body) and once in the
  `AGENTS.md` index, or the incidents-lib synthetic namespace is used
  deliberately (decision recorded).
- [ ] AC21: self-application — at ship time, Phase 6.45 archives
  `specs/kb-archive-gate/` and this plan; the merge passes the new gate.

## Test Scenarios

All `unit`-labelled (fixture-driven shell tests — lowest layer that
exercises the behavior; no browser/API surfaces):

- Given a fixture branch with a live `specs/` dir addition, when
  `gh pr merge` is issued, then a deny JSON with remediation text
  (AC2). `unit`
- Given a topic-named plan added live, when `gh pr merge` is issued,
  then deny (AC3). `unit`
- Given artifacts committed under `archive/` only, when `gh pr merge` is
  issued, then silent exit 0 (AC6 — must-PASS, non-canonical). `unit`
- Given `learnings/`-only additions, when `gh pr merge` is issued, then
  silent pass (AC7). `unit`
- Given `gh pr merge 42` with `refs/pull/42/head` on the fixture origin
  carrying live artifacts, when issued from a clean different branch,
  then deny (AC11). `unit`
- Given origin unreachable, when `gh pr merge` is issued, then deny
  naming the fetch (AC12). `unit`
- Given main / detached HEAD / bare repo, when `gh pr merge` is issued,
  then pass — silent on branch-state, warn-only on unresolvable
  merge-base (AC8). `unit`
- Given `echo 'gh pr merge'` or a `-m` body containing the phrase, when
  issued, then no fire (AC9). `unit`

## Open Code-Review Overlap

Query run 2026-10-12 (`gh issue list --label code-review --state open`,
body-contains per planned path). One hit: **#8881** mentions
`suite-shard-legs.tsv` — a completed evidence record for the #8854 K=6→7
rebalance; all findings fixed inline, no open scope-out. **Disposition:
acknowledge** — no fold-in; the TSV row we add is regenerated by
`regenerate-shard-manifest.py`, which is the mechanism #8854 built.
All other planned paths: no matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.
The Phase 2.5 mechanical UI-surface override does not fire: `Files to
Create`/`Files to Edit` contain no `components/**`, `app/**/page.tsx`,
`*.njk`, or any term in `ui-surface-terms.md` (docs/orchestration/hooks
only — the reference's own exclusion row).

## Architecture Decision

**ADR:** none proposed. The mechanism class — a PreToolUse deny hook
gating `gh pr merge` on repo-state predicates — is established precedent
(`ship-operator-step-gate`, `ship-unpushed-commits-gate`, `pre-merge-rebase`'s
review-evidence gate, `ship-net-issue-flow-gate`; contract ADRs
156/157/193). This PR adds one instance plus a doc restructure; no new
component boundary, state model, or lifecycle is introduced. The
`AGENTS.rules.md` rule body for `wg-kb-artifacts-archived-in-pr` records
the "why" per `cq-agents-md-why-single-line`. Re-evaluate at ship if the
rulings in `decision-challenges.md` are overturned.

**C4 views:** none — hooks are not in the C4 component inventory
(`knowledge-base/engineering/architecture/diagrams/model.c4` covers app
components).

## Implementation Phases

### Phase 1 — the hook + suite (deliverable a)

1. Write `.claude/hooks/ship-kb-archive-gate.sh` per §(a): input contract,
   trigger regex, fail-open/fail-closed ladder, `pull/N/head` resolution,
   AM-filter + archive exclusion, deny JSON + `emit_incident`.
2. Write `.claude/hooks/ship-kb-archive-gate.test.sh` per the sibling
   fixture pattern (bare origin + clone work-tree, `make_payload`,
   `assert_deny`/`assert_pass`, `test-incident-sandbox` isolation,
   `assert_fixture_dir` copy — byte-equal to `test-helpers.sh` canonical,
   pinned by `fixture-dir-operand-assert.test.sh`), the case list in
   §Acceptance Criteria, `MIN_ASSERTIONS` floor, vacuity accounting,
   UNRESOLVED arm.
3. Register: `.claude/settings.json` (PreToolUse/`Bash`, after
   `ship-unpushed-commits-gate.sh`), `.devin/config.json` (`^exec$`,
   mirrored order), `devin-dispositions.tsv` (`bind devin-tool=exec`,
   reason string per existing rows).
4. `python3 scripts/regenerate-shard-manifest.py --incremental --write`
   to add the suite row to `scripts/suite-shard-legs.tsv` (verify diff is
   one row before committing — a rebalance is out of scope).
5. `AGENTS.rules.md` + `AGENTS.md` — `wg-kb-artifacts-archived-in-pr`
   entry (subject to tier-gate; else synthetic rule id).

### Phase 2 — ship SKILL.md restructure (deliverable b)

1. Delete the `5.5.` numbered item; insert `## Phase 6.45: KB Artifact
   Archival` between the `gh pr create` block and `### Semver Label and
   Changelog`, carrying the moved body + skill-enforced marker +
   `SOLEUR_RULE_APPLIED` echo.
2. Move the exists-arm's ready+arm block (former steps 6–7,
   `wait-ready-run`, UNTRUSTED-CI announce, present-URL) into Phase 6.5
   "CI Status Check" ahead of the merge-main-lock arm; add the
   `isDraft` → `gh pr ready` preamble.
3. Phase 5 Final Checklist: add the archive row.
4. Update cross-references (§b list); re-grep for `step 5\.5` and
   `Phase 6 step` to confirm the sweep (AC15).

### Phase 3 — postmerge read-back (deliverable c)

Insert `## Phase 5.8: KB archival read-back (REPORT-ONLY)` per §(c):
merge-SHA diff, live-path filter, verbatim report into Phase 6 comment +
Phase 7 summary, one-line archive command, never-blocking.

### Phase 4 — archive-kb discovery (deliverable d)

1. Extend `discover_branch_diff` (or add `discover_untracked`) to union
   `git status --porcelain` KB paths (same `*/archive/*` exclusion;
   spec-file → dir collapse on `??` rows inside `specs/<dir>/`).
2. Record the verification (already measured in Research Insights) in
   `archive-kb/SKILL.md`'s discovery notes; evaluate #7383 for
   close-or-comment at ship time (do not close from this plan).

## Files to Create

- `.claude/hooks/ship-kb-archive-gate.sh`
- `.claude/hooks/ship-kb-archive-gate.test.sh`
- `knowledge-base/project/specs/kb-archive-gate/decision-challenges.md`
  (written)
- `knowledge-base/project/specs/kb-archive-gate/tasks.md`

## Files to Edit

- `.claude/settings.json` — hook registration
- `.devin/config.json` — `^exec$` twin registration
- `.claude/hooks/devin-dispositions.tsv` — `bind` row
- `scripts/suite-shard-legs.tsv` — suite row (via regenerator)
- `plugins/soleur/skills/ship/SKILL.md` — Phase 6.45, Phase 6.5 arming,
  Phase 5 checklist, :2982-2989 refs
- `plugins/soleur/skills/postmerge/SKILL.md` — Phase 5.8
- `plugins/soleur/skills/archive-kb/SKILL.md` — :30 ref + discovery note
- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` — untracked
  discovery
- `plugins/soleur/skills/compound/SKILL.md` — :517 ref
- `plugins/soleur/skills/ship/references/ready-run-wait.md` — :5 ref
- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` —
  :117 ref
- `AGENTS.rules.md` + `AGENTS.md` — `wg-kb-artifacts-archived-in-pr`
  (contingent)

## Success Metrics

- The #10064 merge-shape replayed in a fixture is denied 100% of the time
  (suite's deny cases).
- Zero `gh pr merge`-path live-path landings after merge (observable via
  the new postmerge Phase 5.8 report going forward).
- `specs/` live-dir count on `origin/main` stops growing from new merges
  (the backlog itself is the sibling sweep's scope).

## Dependencies & Risks

- **False-deny surface:** `gh pr merge <N>` on a foreign-repo PR from a
  Soleur worktree → `pull/N/head` fetch fails → fail-closed deny. Rare in
  this repo; deny message names the fetch failure. Mitigation if it
  bites: skip when the arg's repo differs (add `gh pr view` resolution
  later — deliberately not in v1 to keep the hook `gh`-free).
- **`pull/N/head` availability:** GitHub exposes it for every PR
  (same-repo and fork). Fixture pushes it to a bare origin to prove the
  codepath.
- **Shallow clones** (CI `depth: 1`): merge-base fails → fail-open; same
  exposure `archive-kb.sh` already carries. Accepted, recorded.
- **Staged-but-uncommitted artifacts** are invisible to a head-diff gate
  by construction — they never reach the merge (#9172 is the persistence
  side, not the leak side). The untracked-discovery extension in Phase 4
  is the complementary fix on the producer side.
- **Renumber churn:** steps 6–7 move to Phase 6.5 — the two reference
  files that pin "ship Phase 6 step 6" are in the edit list.
- **Test-suite cost:** each fixture spins a tiny git repo; ~15 cases ≈
  seconds — within a normal hooks shard leg.

## References & Research

- `.claude/hooks/ship-unpushed-commits-gate.sh` (model hook) and its
  `.test.sh` (fixture conventions, T1–T15)
- `plugins/soleur/skills/ship/SKILL.md:1967-1983` (step 5.5), `:523-543`
  (Phase 5 checklist), `:2103-2208` (Phase 6.5), `:2982-2989` (archival
  discussion)
- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh:122-157`
  (branch-diff discovery, #9803)
- `.claude/hooks/devin-matcher-parity.test.sh`,
  `.claude/hooks/devin-dispositions.tsv` (registration contract)
- ADR-156/157 (hook input contract), ADR-258 (reap-archive persistence),
  ADR-176 (checkpoint discipline), ADR-084 (decision-challenges render)
- PR #10064 (the leak instance); issues #7383, #9172; the #7240/#9768
  class documented in ship Phase 7
- Learnings: `2026-03-13-archive-kb-stale-path-resolution.md` (silent
  "No artifacts found" class),
  `2026-03-03-pre-merge-rebase-hook-implementation.md` (hook patterns)

## Research Insights

**Premise Validation (Phase 0.6).** Cited artifacts verified against
`origin/main` 2026-10-12: PR #10064 is `MERGED` (2026-10-12T18:05:57Z);
its squash commit `c64bdcd2` adds 5 live-path KB files — the plan and 4
spec-dir files — all still live on `main` (verified via `git ls-tree` /
`git show`). Issues #7383 and #9172 are `OPEN`. All cited files exist:
`ship-unpushed-commits-gate.sh` (read in full), `archive-kb.sh` (read —
branch-diff discovery present at :122-157), `ship/SKILL.md` (step 5.5 at
:1967 inside the "If an open PR exists" list), `postmerge/SKILL.md`,
`suite-shard-legs.tsv`, `technical-ruling-delegation.md`. Two premise
corrections: (1) "cleanup-merged does not durably archive" is stale in
the categorical — ADR-258's `reap_archive_persist` persists reap archives
on committable checkouts; the merge-time gap it cannot cover stands.
(2) #7383's stated gap is already closed by the #9803 branch-diff code —
verified by `--dry-run` on `feat-one-shot-9969-edge-roots` (topic-named
plan + spec dir both listed); the residual is untracked files and
shallow-clone merge-base. Measured spec-dir census: 1747 live dirs +
`archive` + `.gitkeep` on main (brief: ~1751; drift is sibling merges),
652 archive entries — directionally confirmed. ADR corpus grep
(hook/deny/archive keywords): no ADR rejects this mechanism class; ~7
ship-* deny hooks are precedent.

**Property List (Phase 0.6b).**

- P1: an agent-issued `gh pr merge` cannot land a head carrying live-path
  KB artifacts — no existing mechanism buys this (ship Phase 2's
  unarchived-artifact glob routes to `soleur:compound`, which can
  legitimately defer; it is not a merge gate).
- P2: ship's documented order makes archival a named unconditional phase
  after the last live read and before every arm — the mechanism exists
  (step 5.5's body); its placement inside a conditional numbered list is
  the defect, so this is a restructure, not a new mechanism.
- P3: a leak that slips every preventive gate is surfaced post-merge —
  no existing mechanism buys this (`cleanup-merged` cannot; verified
  above).
- P4: `archive-kb.sh` discovers the feature's own artifacts regardless of
  naming — mostly exists (verified); residual is the untracked-file set.

**Cut List.** None — each of the four deliverables maps to a property no
existing mechanism covers. Checked `grep -rn 'archive\|specs/'
.claude/hooks/*.sh`: no existing hook gates on KB paths; the ask's claim
"nothing mechanical checks the result" verified against the hook
inventory.

**Repo research (inline — no Task tool in this session).** Relevant
paths: `.claude/hooks/lib/{incidents,hook-input,hook-tool-kind}.sh` (hook
contract), `.claude/settings.json:54-117` (ship-family registration
block), `.devin/config.json` `^exec$` block, `devin-dispositions.tsv`
(`bind` row schema), `scripts/suite-shard-legs.tsv` (n=8 legs,
regenerator script), `ship/SKILL.md` Phases 5/5.4/5.5/6.4/6/6.5/7,
`postmerge/SKILL.md` phase ladder, `merge-pr`/`drain-prs` (`gh pr merge`
on foreign branches — drove the `pull/N/head` design). Learnings cited in
References. CLAUDE.md conventions applied: `#!/usr/bin/env bash`,
`set -eo pipefail` (no `-u` in hooks), `[[ ]]`, `local` declarations,
stderr for diagnostics, deny JSON on stdout.
