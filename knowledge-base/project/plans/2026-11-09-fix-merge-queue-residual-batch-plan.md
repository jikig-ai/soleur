---
title: "fix: merge-queue residual batch — /tmp scratch leak, stale PR-selection base, coalesced-merge blind spots, stall-check false-positives, pin-bump red window"
type: fix
date: 2026-11-09
slug: fix-merge-queue-residual-batch
branch: feat-one-shot-11764-12484-12501-12507-12508-queue-resid
issue: 11764
closes: [11764, 12484, 12501, 12507, 12508]
lane: cross-domain
domain: engineering
priority: p2-medium
brand_survival_threshold: none
---

# fix: merge-queue residual batch — /tmp scratch leak, stale PR-selection base, coalesced-merge blind spots, stall-check false-positives, pin-bump red window

## Enhancement Summary

**Deepened on:** 2026-11-09 (inline pass — the Devin-CLI planning seat has no spawn tool; the per-section/review-agent fan-outs this skill prescribes in parallel were discharged sequentially inline, disclosed per cloud-mode `sequential-fallback`)

**Sections enhanced:** Gates verified — 4.6 User-Brand Impact (present, `none` + non-empty scope-out reason for the `apps/web-platform/server` sensitive path), 4.7 Observability (5 fields, allowlisted `rg` probe, literal expected output, <15s), 4.8 PAT (clean), 4.9 UI wireframe (non-UI, skipped), 4.10 Encryption (no new store, skipped), 4.11 Guard Contract (`lint-guard-contract.py`: 3 entries, green), 4.12 Scope Check (exactly 1 unfenced occurrence), 4.13 Task Design (no new autonomous task, skipped). 4.5 network-outage and 4.55 downtime gates: triggers absent.

### Key Improvements

1. **AC1 scoped to the diff line** — the original "zero matches for `HEAD^1 HEAD`" form would false-fail on explanatory comments kept beside the port (the oracle lane's own comments name `HEAD^1` to say why it is not the base); narrowed to the `git diff --raw` invocation shape.
2. **AC12 count corrected** — four edited workflow files (ci.yml, apply-github-infra, apply-sentry-infra, merge-queue-stall-check), not three.
3. **C4 completeness verified against all three model files** — `model.c4`/`views.c4`/`spec.c4` grep shows no merge-queue/tmpfs-guard/stall-check/pin-bump elements exist to update; the vinngest pin carrier is already modeled. The plan's "no C4 impact" conclusion is evidence-backed, not a bare None.
4. **Verify-the-negative pass** — plan carries no NEVER/MUST NOT/exposure claims requiring contradiction checks; sibling-PR overlap claims (#12498 disjoint, #12495 adjacent) verified live 2026-11-09 and flagged as time-stamped observations to re-check at work time (task 1.1).

### New Considerations Discovered

- `tests/scripts/test-apply-github-infra-mint-shape.sh:245-248` pins the `HEAD_MSG` env block byte-shape — the `EVENT_MSGS_JSON` addition is a pinned-shape edit requiring a same-diff snapshot update (already in Files to Edit; called out so it is not discovered as a red test at GREEN time).
- `test-sentry-alert-adoption-guards.sh:140` counts `HEAD_MSG|ack_destroy|head_commit|git log` occurrences — the combined-var edit may shift the pinned count; re-derive in the same diff (task 3.4).
- `srt-ca-*`/`claude-http-*`/`postmerge-poll*` prefixes trace to the `srt` sandbox runtime and harness-side artifacts — external producers no repo-side trap can fix; the `TMPDIR`→`/tmp/.cs` routing plus the `.cs` age-reap arm is the only mechanism that reaches them, which is why both halves of the #11764 fix are load-bearing (routing alone relocates the pile; reclaim alone leaves producers scattering).

## Overview

One PR fixes five open machinery issues as a single merge-queue residual batch:

- **#11764** — `/tmp` grew to ~6.3k top-level entries (fresh alarm 2026-11-09: 23,358): a count-shaped leak of `tmp.*` files and fixture dirs (`srt-*`, `skill-*`, `pencil-*`, `soleur-*`, `claude-http-*`, `rung2-*-job`, subagent scratch) from test/hook producers and spawned-agent descendants that bypass the ownership-keyed scratch-root pattern (ADR-250).
- **#12484** — `scripts/ci-pr-selection.sh` diffs the frozen merge-ref `HEAD^1` for `pull_request` selection — the same stale-base class fixed for `scripts/ci-oracle-lane.sh` in #12480; the port was deliberately out of #12480's scope and is required before the dark `CI_PR_AFFECTED` lever is activated.
- **#12501** — the coalesced-merge blind spot fixed for the deploy-policy gate (#12404) persists in the two sibling apply workflows: tip-only `github.event.head_commit.message` readers for `[skip-github-apply]`/`[ack-destroy]` (apply-github-infra.yml) and `[skip-sentry-apply]`/`[ack-destroy]` (apply-sentry-infra.yml) silently miss tokens carried below the tip in a coalesced push.
- **#12507** — `merge-queue-stall-check.yml` ages queue heads from `enqueuedAt`; under `max_entries_to_build=1` (PR #12495) a depth-≥2 entry promotes to position 1 already past the 45-min threshold and gets a SUSPECTED-stall filing at the start of its own legitimate build.
- **#12508** — the authored vinngest pin-bump PR arms auto-merge but sits BEHIND and never enters the merge queue (measured 5h20m+ on #12489), leaving `test-infra`/`deploy-script-tests` red while every head containing the tag trips the pin-drift guard.

All five are bounded mechanical fixes riding existing repo machinery: `scripts/lib/scratch-root.sh` (ADR-250), the #12480 three-dot diff shape, the #12404 `EVENT_MSGS_JSON` concat pattern, the stall-check's own `headCommit.oid` correlation machinery, and an explicit `enqueuePullRequest` (merge-queue-jump runbook + ADR-285 App-authored enqueue precedent).

## Research Insights

### Relevant file paths (verified on `origin/main`, 2026-11-09)

- `scripts/ci-pr-selection.sh:307` (`base_sha="$p1"`) and `:320` (`git diff -z --raw … HEAD^1 HEAD`) — the unported stale-base site.
- `scripts/ci-oracle-lane.sh:314-331` — the post-#12480 reference: `PR_BASE_REF` regex gate → unconditional `git fetch --no-tags --quiet origin "refs/heads/$PR_BASE_REF"` → `diff_base="$(git merge-base HEAD^2 FETCH_HEAD)"` → `diff_head="$p2"` (true three-dot); named fail-closed reasons placed after the cheap env gates.
- `.github/workflows/ci.yml:417-431` — the `pr-selection` job's step env (no `PR_BASE_REF` today); `:487` shows the already-wired oracle-selection arm (`PR_BASE_REF: ${{ github.event.pull_request.base.ref }}`).
- `.github/workflows/apply-github-infra.yml:88-91` (kill-switch `HEAD_MSG` env + anchored `[skip-github-apply]` regex), `:290` + `:316` (`HEAD_MSG` env + anchored `[ack-destroy]` regex), `:115` (`if:`-conjunct comment "inert on dispatch").
- `.github/workflows/apply-sentry-infra.yml:161`/`~:167` (`[skip-sentry-apply]`), `:802`+ (`[ack-destroy]` destroy-guard run), operator-guidance text `:1190`, `:1302`, `:1445-1446` ("re-run is the only gesture that carries the original `head_commit.message`").
- `.github/workflows/apply-web-platform-infra.yml:411`,`:869` — the landed reference: `EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}` env + `jq -r 'join("\n")'` concat into `POLICY_MSGS`.
- `.github/workflows/merge-queue-stall-check.yml:163-168` (`STALL_THRESHOLD_MINUTES: '45'`), `:210-230` (`stalled` jq: `position <= $maxpos`, `age > $thr` from `enqueuedAt`), `:291-344` (`fetch_runs` + `queue_candidate_cause` — the oid-correlation machinery the fix reuses).
- `.github/scripts/bump-inngest-bootstrap-pin.sh:~630` — `gh pr merge "$PR_NUM" --auto --squash` arm site; the bump job (`build-inngest-bootstrap-image.yml` `bump-cloud-init-pin`) already mints the soleur-infra App token with `contents:write`+`pull_requests:write` — the verified-good enqueue actor (ADR-285: `github-actions[bot]`-armed enqueues get zero `merge_group` runs; App-armed works).
- `scripts/merge-queue-jump.sh` + `knowledge-base/engineering/operations/runbooks/merge-queue-jump.md` — repo-precedent GraphQL `enqueuePullRequest` mechanism (jump variant; normal enqueue is `jump: false`).
- `scripts/lib/scratch-root.sh` — `soleur_scratch_session_begin` (owned `soleur-run.<pid>.XXXXXXXX` root, `.soleur-owned` marker, `export TMPDIR`, `_soleur_scratch_cleanup` trap splice, ADR-129 contract) and `soleur_scratch_mark_owned`.
- `plugins/soleur/test/test-helpers.sh:34-93` — creates `soleur-inc-XXXXXX` sandbox under ambient TMPDIR, marks `.soleur-owned`, composes an EXIT trap — but does NOT repoint `TMPDIR`, so descendant bare `mktemp` calls still land scattered at the ambient base.
- `apps/web-platform/server/agent-env.ts:46` (`TMPDIR` already in `AGENT_ENV_ALLOWLIST` — passed ambient), `:378` (`env.CLAUDE_CODE_TMPDIR = opts.claudeTmpDir` injected per-tenant); `apps/web-platform/server/agent-session-tmp.ts` (`AGENT_SESSION_TMP_ROOT = "/tmp/.cs"`, per-tenant hash dir); `agent-runner-sandbox-config.ts` binds that root writable and denies it for isolation.
- `scripts/tmpfs-guard.sh:833-879` — reaper 3 reclaims `soleur-run.*` schema dirs and `.soleur-owned` marker dirs at `mindepth 2` under the base; `:45-58` documents the count-shaped class and the pressure tier that drops the size floor. `/tmp/.cs` and bare `tmp.*` files are uncovered.
- `tests/scripts/test-destroy-guard-regex-parity.sh` — pins the anchored `[ack-destroy]` literal across all three apply workflows (subject-agnostic: the regex itself stays).
- `tests/scripts/test-apply-github-infra-mint-shape.sh:245-248` — snapshots the `HEAD_MSG` env block byte-shape; adding `EVENT_MSGS_JSON` beside it is a pinned-shape edit.
- `tests/scripts/test-destroy-guard-counter.sh` / `-sentry.sh` — gate-counter suites whose `HEAD_MSG` fixtures become combined-var fixtures.
- `plugins/soleur/test/merge-queue-stall-check.test.sh` (1873 lines) — gh-stub + sandbox-copy suite; fixture rows for the promoted-head rule go here.
- `scripts/ci-pr-selection.test.sh` — the selector's sentinel suite for the #12484 port.

### Institutional learnings

- `knowledge-base/project/learnings/workflow-issues/2026-10-11-tmpfs-count-shaped-mktemp-leak-across-agent-sessions.md` — same alarm, 2026-10-11; "correct fix is a `trap 'rm -rf "$tmp"' EXIT` (or owned root) at each producer — a census, not a one-liner."
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` T5 drift rule — "a fix to one driver is consciously ported to the other, never assumed to transfer": this PR is the port the rule names.
- `knowledge-base/project/learnings/2026-09-24-a-reaper-whose-trigger-isnt-installed-is-a-no-op.md` — a reclaim mechanism with no live trigger reaps nothing; the `.cs` age-reap arm must land inside the installed `tmpfs-guard` timer path.
- ADR-250 (ownership-keyed reclamation): reapers reclaim only declared owners; heuristic reaping over shared `/tmp` is measured and rejected — but `/tmp/.cs` is a repo-OWNED base, so an age floor inside it does not violate the doctrine.
- ADR-270 (merge queue): records "GitHub enqueues an armed PR whose head is behind `main` on its own under the strict policy" — #12489's 5h20m BLOCKED/not-queued measurement is a counter-instance the fix (explicit enqueue) and an ADR addendum must record.
- ADR-285: enqueues must be App-authored (the bump job's minted soleur-infra token qualifies); `github-actions[bot]`-armed enqueues get zero `merge_group` runs.

### Premise Validation (Phase 0.6)

All five target issues verified OPEN with unchanged scope (gh, 2026-11-09). Cited prior art verified: PR #12480 MERGED (oracle three-dot shape exists on main at `ci-oracle-lane.sh:314-331`); PR #12404 MERGED (EVENT_MSGS_JSON concat live on main); PR #12498 OPEN on a disjoint file set (`apply-web-platform-infra.yml` + `tests/scripts/lib/deploy-policy-gate.sh` — zero overlap with the two sibling workflows); PR #12495 OPEN with a 2-line `MAX_ENTRIES_TO_BUILD` flip + comment on `merge-queue-stall-check.yml` — our run-body change is adjacent and must expect a rebase; PR #12489 still OPEN and measured `isInMergeQueue: false`, `mergeStateStatus: BLOCKED` at plan time — the defect is live, not theoretical. Every cited file exists on `origin/main` (verified via `git cat-file -e`). Collision precheck: the only open PR naming all five issues is #12510 — this pipeline's own draft; not a live duplicate. No ADR rejects a proposed mechanism: ADR-270's self-enqueue claim is extended (not contradicted) by the explicit enqueue; ADR-250's owned-base doctrine is extended (not violated) by `.cs` age reaping.

### Property List (Phase 0.6b)

1. `/tmp` top-level entry count stops growing count-wise from repo-owned and spawned-agent scratch producers.
2. `pull_request` selection diffs the live three-dot base (merge-base of PR head and live base ref), never the frozen merge-ref parent.
3. A `[skip-github-apply]`/`[skip-sentry-apply]`/`[ack-destroy]` token on ANY commit of a coalesced push is honored by both sibling apply workflows.
4. A promoted queue head whose own `merge_group` build just started is NOT filed as suspected-stalled; an old head with NO `merge_group` run still files.
5. A pin-bump PR with armed auto-merge enters the merge queue within one CI cycle — no human-in-the-loop step.

### Cut List (Phase 0.6b)

- **Heuristic/prefix reaper over shared `/tmp`** → property 1 → rejected by ADR-250/ADR-195 (measured ~1,500 authored files marked for deletion in the dry run); ownership-keyed routing + owned-base age reaping covers the property.
- **New scratch mechanism** → property 1 → `scripts/lib/scratch-root.sh` already implements it; this PR routes producers to it, does not rebuild it.
- **New workflow/cron for any fix** → none needed: all fixes land inside existing files/suites.
- **`update-branch` push for #12508** → property 5 → pays a full `pull_request` CI cycle and can re-BEHIND on the next main advance — the defect's own mechanism; explicit enqueue bounds it by construction (merge-queue-jump machinery exists).
- **Drift-check in-flight hush for #12508 (issue candidate 2)** → property 5 → hides a correct red behind a new ack-token surface; heavier than one enqueue step and weakens the guard.
- **Committing a producer-census script** → property 1 → the census is a one-time measurement (greps + `/tmp` prefix histogram) run inside the work phase; no committed artifact is needed.

### External research (Phase 1.6 decision)

Skipped — all five fixes are mechanical ports of patterns already landed and measured in this repo; the codebase and KB are the authority. No external docs needed.

### Community discovery / functional overlap (Phases 1.5/1.5b)

No uncovered stacks (no new stack signatures). Functional overlap: the fix mechanisms are repo-internal ports of repo-internal machinery (`scratch-root.sh`, `EVENT_MSGS_JSON` concat, `enqueuePullRequest`, stall-check correlation) — no community artifact applies; skipped silently.

## Research Reconciliation — Spec vs. Codebase

| Spec/ask claim | Reality on `origin/main` (verified) | Plan response |
|---|---|---|
| #11764 frames producers as "test/hook producers … `mktemp` files and fixture dirs" | `srt-ca-*` (trust-bundle.crt) maps to the `srt` sandbox runtime and `claude-http-*`/`postmerge-poll*` map to harness-side artifacts — some producers are EXTERNAL to the repo; repo-owned producers include test suites without traps, `skill-security-scan`, `pencil-setup` probe, rung2 scripts | Split the fix into (a) repo-owned producer routing (helpers + traps), (b) spawned-agent TMPDIR injection so external descendants land under `/tmp/.cs`, (c) `.cs` age reaping — the only arm that reaches external producers |
| "#12501 is the two sibling workflows only" | Confirmed: #12498's diff touches `apply-web-platform-infra.yml` + `deploy-policy-gate.sh` only; apply-web-platform already carries `EVENT_MSGS_JSON` on main at :411/:869 | Scope to apply-github-infra + apply-sentry-infra exactly; no deploy-policy-gate.sh edits |
| "#12507 … keep your diff minimal and expect a rebase" vs #12495 | #12495's workflow diff is a 2-line `MAX_ENTRIES_TO_BUILD` value flip + comment hunks; test-file edits unknown extent | Diff confined to the run body (jq + pre-filing correlation) + a new comment block; flag rebase in Dependencies & Risks |
| "#12508 fix ~20 lines / 1 file" | The arm site is `bump-inngest-bootstrap-pin.sh:~630`; enqueue needs the PR's GraphQL node id — small but test rows are also required | ~20-40 lines in the script + fixture rows in `test-bump-inngest-bootstrap-pin.sh` |
| `test-helpers.sh` already solves owned scratch for suites | It marks the incident sandbox `.soleur-owned` but never repoints `TMPDIR`; descendant bare `mktemp` still scatters | Add the `export TMPDIR` routing in the no-outer-root arm |

## Problem Statement / Motivation

Each issue is a residual of a fix that already landed elsewhere — the same defect class surviving in a sibling surface — plus one producer-side leak that two prior rounds of tmpfs work deliberately left:

- The queue/CI machinery accumulated five known residuals (#12418's stale base ported only to the oracle lane; #12403's coalesced-blind-spot ported only to web-platform-infra; the `max_entries_to_build=1` flip creates a promoted-head false-positive class; the pin-bump path never closes its own merge loop).
- `/tmp` on the operator host is a RAM-backed tmpfs: thousands of small unreaped entries push count watermarks and alarm even at low byte usage (#11764, third recurrence of the count-shaped class).

Shipping them together avoids five separate queue cycles for five mechanical ports — and one shared review catches cross-issue interactions (e.g., #12507's fix assumes #12495's `max_entries_to_build=1` world).

## Proposed Solution

### #11764 — route producers to owned scratch + reclaim `.cs`

1. **Census (work-phase measurement, uncommitted):** histogram current `/tmp` residue by prefix; `git grep -n mktemp` across `.claude/hooks/`, `plugins/soleur/`, `scripts/`, `tests/`, `apps/` minus knowledge-base; classify each site as (a) already trapped/`rm`'d, (b) runs under an owned root already, (c) needs a trap/`rm`, (d) external producer.
2. **`plugins/soleur/test/test-helpers.sh`:** in the no-outer-root arm, `export TMPDIR` at the `.soleur-owned` sandbox (a test harness is the documented correct caller for TMPDIR export per `scratch-root.sh`'s own contract) — every descendant `mktemp` in every suite sourcing the helpers lands inside the owned dir the trap already removes.
3. **Shared-script producers:** add `trap`/`rm -f` cleanup (or route through `soleur_scratch_session_begin` where the script is a harness) at the census-confirmed repo-owned sites — the measured prefix classes: `plugins/soleur/skills/skill-security-scan/scripts/{lib.sh,run-scan.sh}` (`skill-*`), `plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` (`pencil-*`), `scripts/followthroughs/git-data-rung2-evidence-capture.sh` + `tests/scripts/lib/git-data-birth-readiness-gate.sh` + `tests/scripts/test-git-data-birth-readiness-gate.sh` (`rung2-*-job`), and the non-test `.claude/hooks/` `mktemp` sites that lack cleanup (~9 files, ~27 call sites).
4. **Spawned agents:** `apps/web-platform/server/agent-env.ts` — inject `env.TMPDIR = opts.claudeTmpDir` beside the existing `CLAUDE_CODE_TMPDIR` injection so agent-session descendants (hooks, skill scripts, `srt` fixtures, `claude-http-*`) write under `/tmp/.cs/<tenant>` instead of `/tmp` top level. Tests: `agent-runner-query-options.test.ts` (+ `cc-dispatcher-real-factory.test.ts` env-shape rows) gain the TMPDIR assertion.
5. **`/tmp/.cs` reclaim:** extend `scripts/tmpfs-guard.sh` reaper-3 with an owned-base age arm — `/tmp/.cs` is repo-owned (not shared `/tmp`, so ADR-250's heuristic-reap rejection does not apply), reap entries under it older than a 48h floor plus top-level `.cs/<hash>` dirs whose whole content is older than the floor. Suite: `scripts/tmpfs-guard.test.sh` rows.

### #12484 — port the #12480 three-dot shape to ci-pr-selection.sh

Mirror `ci-oracle-lane.sh:314-331` into the `pull_request` arm of `scripts/ci-pr-selection.sh`: `PR_BASE_REF` regex gate → unconditional `git fetch --no-tags --quiet origin "refs/heads/$PR_BASE_REF"` → `diff_base="$(git merge-base HEAD^2 FETCH_HEAD)"` → `diff_head="$p2"`; named fail-closed reasons (`bad_base_ref`, `base_fetch`, `no_merge_base`) placed after the existing cheap env gates (not-PR, merge shape, fork, re-run — the selector's own ordering: the fetch is placed per the driver's own doctrine, after the cheap guards, before the diff); `base_sha` output emits the resolved merge-base (per the #12418 sibling's recorded ruling). Wire `PR_BASE_REF: ${{ github.event.pull_request.base.ref }}` into the pr-selection step env in `ci.yml`. Add sentinel fixtures/rows to `scripts/ci-pr-selection.test.sh` (stale-frozen-parent fixture where `HEAD^1` ≠ merge-base must produce the three-dot file list; fetch-failure and bad-ref rows assert the named reasons). Update the T5 row in `ci-oracle-lane.md` runbook to record the port landed.

### #12501 — any-commit reach for the four sibling readers

Mirror the #12404/`apply-web-platform-infra.yml` shape in both sibling workflows:

- Add `EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}` beside each `HEAD_MSG` env (kill-switch + destroy-guard steps in both files).
- In each run body, concat: `POLICY_MSGS="$HEAD_MSG"` + `more_msgs="$(jq -r 'join("\n")' <<<"${EVENT_MSGS_JSON:-null}" …)"` → the anchored token regexes read `$POLICY_MSGS` (any-commit reach). The anchored regex literals stay byte-identical (regex-parity suite untouched by shape).
- Rewrite the stale guidance: `apply-sentry-infra.yml:1190`/`:1302`/`:1445-1446` ("re-run is the only gesture that carries the original head_commit.message" — under any-commit reach a fresh push carrying the token on any commit also supplies it; the dispatch-can't-carry-commits caveat stays true) and `apply-github-infra.yml:115` `if:`-conjunct comment.
- Tests: `test-destroy-guard-counter.sh` (github-infra) and `test-destroy-guard-counter-sentry.sh` gain below-tip-token fixtures (token on a non-head commit in `EVENT_MSGS_JSON` → gate sees it); `test-apply-github-infra-mint-shape.sh:245-248`'s env snapshot gains the `EVENT_MSGS_JSON` line; `test-sentry-alert-adoption-guards.sh:140` count is re-derived.
- Documented residual (per #12501): `event.commits` caps at 20 — a token older than the window in a giant coalesced push still misses (fail-open for skip, fail-closed for ack); comment the cap, don't engineer around it.

### #12507 — age promoted heads from build start

Per the architecture-strategist ruling recorded in the issue: when a flagged head entry's `headCommit.oid` is a valid 40-hex, correlate its `merge_group` `ci.yml` run (the existing `fetch_runs`/`refre` machinery) and age from `run.created_at` instead of `enqueuedAt`; only file when the run-derived age still exceeds the threshold. An old head with NO `merge_group` run remains the true suspect and still files. Implementation is a pre-filing correlation arm inside the existing per-entry loop — no new trigger, no new job. Test rows in `merge-queue-stall-check.test.sh`: promoted-head-with-young-build → no file; promoted-head-with-old-build → file; old-head-no-merge_group-run → file (the true stall); oid-null entry → unchanged behavior. Diff kept to the run body + a comment block; expect rebase against PR #12495's comment hunks.

### #12508 — explicit enqueue after arming

In `bump-inngest-bootstrap-pin.sh`, after the `gh pr merge --auto --squash` arm succeeds (and only in the arm branch — mirror_only/withheld paths unchanged): resolve the PR's GraphQL node id and call `enqueuePullRequest` (normal enqueue, `jump` NOT set — the jump variant is operator-urgency tooling per `merge-queue-jump.md`) via `gh api graphql` as the minted App token. On enqueue rejection (permission, already-queued, schema drift): `::warning` and continue — armed auto-merge remains the fallback, strictly better than today and never worse. Test rows in `test-bump-inngest-bootstrap-pin.sh` for: enqueue called after arm (stub-asserted mutation input `enqueuePullRequest` with the PR's node id, `jump` absent), enqueue-failure → warn-and-exit-0, withheld-arm → no enqueue call.

## Technical Considerations

- **Least privilege preserved:** no new permissions, tokens, or workflow triggers anywhere. The enqueue rides the already-minted App token; the fetch rides `contents: read` checkout credentials; the scratch routing reuses the installed reaper.
- **Fail directions preserved:** #12484's port keeps fail-closed named reasons; #12501 keeps the anchored-regex fail directions (skip = fail-unsafe, ack = fail-safe) while widening only the read window; #12507's correlation failure falls back to today's filing behavior; #12508's enqueue failure leaves armed auto-merge intact.
- **Attack surface (#12501 is `type/security`):** the combined message var is read ONLY by anchored own-line token regexes — the `(^|$'\n')token($|$'\n')` anchoring means a token inside a quoted block or trailer still can't fire (unchanged). `toJSON(github.event.commits.*.message)` is workflow-expansion JSON read by `jq`, never eval'd; commit messages are attacker-influenced only by actors who can already push to main.
- **NFR:** no user-facing surface; CI-runner cost is neutral-to-positive (one enqueue API call per publish vs. hours of red-window CI and operator toil; the stall-check gains one `gh api` runs-list per flagged entry — bounded by the position-≤maxpos population, typically ≤1).
- **#11764 blast radius is tmpfs-only:** routing TMPDIR for spawned agents writes under `/tmp/.cs` — the same tmpfs — but converts scattered thousands of entries into per-tenant owned trees the reaper can age out; byte volume unchanged, count collapses.

## Implementation Phases

### Phase 1 — #12484 port (smallest, unblocks CI lever)

1. Port the three-dot diff shape into `scripts/ci-pr-selection.sh`.
2. Wire `PR_BASE_REF` env in `.github/workflows/ci.yml` pr-selection step.
3. Sentinel rows in `scripts/ci-pr-selection.test.sh`; runbook T5 note.

### Phase 2 — #12501 sibling any-commit reach

1. `EVENT_MSGS_JSON` env + `POLICY_MSGS` concat at the four reader sites (two per workflow).
2. Operator-guidance string edits (sentry :1190/:1302/:1445, github-infra :115 comment).
3. Counter-suite fixtures + mint-shape snapshot + adoption-guard count re-derive.

### Phase 3 — #12507 promoted-head aging

1. Pre-filing `merge_group`-run correlation arm in `merge-queue-stall-check.yml` run body.
2. Test rows in `merge-queue-stall-check.test.sh`.

### Phase 4 — #12508 explicit enqueue

1. `enqueuePullRequest` arm in `bump-inngest-bootstrap-pin.sh`.
2. Test rows in `test-bump-inngest-bootstrap-pin.sh`.
3. ADR-270 dated addendum (self-enqueue is not guaranteed; authored bot PRs enqueue explicitly).

### Phase 5 — #11764 producer routing + `.cs` reclaim

1. Census measurement (uncommitted, recorded in the PR body).
2. `test-helpers.sh` TMPDIR routing; shared-script cleanup traps at census-confirmed sites.
3. `agent-env.ts` TMPDIR injection + env-shape test updates.
4. `tmpfs-guard.sh` `.cs` age-reap arm + `tmpfs-guard.test.sh` rows; ADR-250 dated addendum.

### Phase 6 — Verify

Run each touched suite locally: `scripts/ci-pr-selection.test.sh`, `tests/scripts/test-destroy-guard-{counter,counter-sentry,regex-parity,apply-github-infra-mint-shape}.sh`, `tests/scripts/test-sentry-alert-adoption-guards.sh`, `plugins/soleur/test/merge-queue-stall-check.test.sh`, `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`, `scripts/tmpfs-guard.test.sh`, `apps/web-platform` vitest for `agent-runner-query-options`/`cc-dispatcher-real-factory`, plus `actionlint` on the three edited workflows and `bash -n` on edited scripts.

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| #12508: `gh pr update-branch` after arming | Pays a full `pull_request` CI cycle and can re-BEHIND on the next main merge — the defect's own mechanism (issue candidate 1, second form) |
| #12508: drift-check in-flight hush keyed to PR number | Hides a correct red, adds a new ack-token surface (issue candidate 2); the enqueue is smaller and stronger |
| #12508: sequence tag publish behind pin merge | Bump needs the published digest — impossible by construction (issue candidate 3, listed for completeness) |
| #11764: extend the reaper to prefix-match `tmp.*`/`srt-*`/`skill-*` on shared `/tmp` | ADR-250/ADR-195 measured and rejected heuristic reaping of shared `/tmp` |
| #11764: per-site traps only, no TMPDIR routing | Leaves spawned-agent/external producers (the largest prefix classes) unreached — the `.cs` route is what makes the fix stick |
| #12507: reset the aging window for entries promoted from depth>1 | Requires tracking promotion events GitHub doesn't expose per-entry; build-start aging uses data the workflow already reads |
| #12507: raise the 45-min threshold | Capped below `check_response_timeout_minutes` (120) by design; raising weakens the real-stall detector |
| #12501: pure mirror without guidance-text edits | Issue body explicitly calls out the operator-guidance strings whose semantics change under any-commit reach |
| Split into five PRs | Five queue cycles for five mechanical ports; the operator confirmed one PR for this set |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — every surface is repo-internal CI/host machinery. The worst shaped failure is a wedged apply workflow (a kill-switch read that can't fire) or a stall-check that over-files — both internal-noise, both recoverable by revert.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data path is touched; `.github/workflows/*.yml` and `apps/web-platform/server/` edits are infra surfaces whose failure modes are CI-visible, not data-visible.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** no user-facing artifact, no data surface, no production mutation beyond repo CI — the `single-user incident` bar (a tenant-visible breach/loss) cannot be reached by these diffs.
- **Scope-out (sensitive paths touched):** `threshold: none, reason: changes are confined to CI workflow YAML, repo test/tooling scripts, and one server env-injection that routes agent scratch paths — none reachable by tenant data or tenant-visible behavior.`

## Observability

```yaml
liveness_signal:
  what: GitHub Actions run health of the edited surfaces (apply-github-infra, apply-sentry-infra, merge-queue-stall-check, build-inngest-bootstrap-image) plus the host tmpfs-guard alarm remaining quiet
  cadence: apply workflows fire on push to main under path filters; stall-check runs on its cron; tmpfs-guard runs on its installed timer
  alert_target: workflow failures red the run + post to Slack where already wired; stall filings land as `action-required` issues; tmpfs-guard alarms to the operator
  configured_in: the workflows themselves + scripts/tmpfs-guard.{service,timer}
error_reporting:
  destination: Actions run log + existing ::error::/::warning:: channels; pin-bump failures post Slack via the existing step
  fail_loud: yes — every new arm fails with a named reason or an explicit ::warning::, never silently
failure_modes:
  - mode: base-ref fetch or merge-base resolution fails in ci-pr-selection
    detection: named fail-closed `reason=` output (base_fetch / no_merge_base / bad_base_ref)
    alert_route: job continues fail-open per existing continue-on-error design; telemetry in step output
  - mode: combined-message read returns empty/null
    detection: `more_msgs` empty → POLICY_MSGS falls back to HEAD_MSG (today's behavior)
    alert_route: none needed — same as today
  - mode: oid-correlation lookup fails in stall-check
    detection: bounded ::warning::, entry still files as suspected (existing contract)
    alert_route: run log warning
  - mode: enqueuePullRequest rejected in bump script
    detection: ::warning:: line naming the rejection; armed auto-merge remains
    alert_route: run log + the existing pin-bump Slack step on hard failure
logs:
  where: Actions run logs (all workflow/script surfaces); tmpfs-guard guard_log lines on the host
  retention: Actions default retention; host journal/tmpfs-guard log per existing config
discoverability_test:
  command: rg -l enqueuePullRequest .github/scripts/bump-inngest-bootstrap-pin.sh
  expected_output: .github/scripts/bump-inngest-bootstrap-pin.sh
```

## Architecture Decision (ADR/C4)

This plan extends two existing ADRs' recorded claims — addenda are plan deliverables, not follow-ups:

### ADR

- **ADR-270 addendum (dated 2026-11-09):** record the counter-instance — `gh pr merge --auto` armed a PR whose head went BEHIND and it was NOT self-enqueued (PR #12489, `isInMergeQueue: false`, BLOCKED, 5h20m+); authored bot PRs therefore enqueue explicitly via `enqueuePullRequest` as the App actor after arming. Scope the note to the enqueue path; nothing else in ADR-270 changes.
- **ADR-250 addendum (dated 2026-11-09):** record the extension — spawned-agent `TMPDIR` routes to the per-tenant `/tmp/.cs` root (an owned base), and tmpfs-guard gains an owned-base age arm covering it; shared `/tmp` heuristic reaping remains rejected.

### C4 views

Checked all three model files (`model.c4`, `views.c4`, `spec.c4` on `origin/main`) for the actors/systems/relationships this change touches: the merge queue, GitHub Actions workflows, the tmpfs-guard, and agent-session scratch are operational machinery, not modeled C4 elements — no external human actor, no new external system/vendor, no new container or data store, no changed access relationship is introduced. `model.c4` already carries the vinngest pin reference. **No C4 impact** — the enumeration above is the check performed.

### Sequencing

The addenda are authored in this PR describing the landed state; no `adopting` staging needed (no soak-gated decision).

## Guard Contract

### Guard 1 — stall-check promoted-head aging rule

**Property.** A merge-queue head entry whose `merge_group` `ci.yml` build is younger than `STALL_THRESHOLD_MINUTES` must not produce a suspected-stall filing; a head past threshold from build start (or with no `merge_group` run) still files.

**Assembly.** The per-entry filing decision in `merge-queue-stall-check.yml`'s detection step — the single chokepoint between the `stalled` jq filter and `gh issue create`. The aging input is `enqueuedAt` vs `merge_group run.created_at` — the property quantifies over exactly these two aging bases.

**Mutation matrix.**

| # | Mutation (of the guard / its inputs) | Expected |
|---|--------------------------------------|----------|
| 1 | Revert the run-created_at correlation to age only from `enqueuedAt` | RED — a promoted-head fixture whose build is young must not file |
| 2 | Correlate but file when the build is YOUNGER than threshold (invert) | RED — must-file arm proves the young-build exclusion |
| 3 | Correlate by `head_branch` prefix only, dropping the `head_sha == oid` join | RED — a stale run on a superseded temp ref must not satisfy the exclusion |
| 4 | Treat "no `merge_group` run returned" as "no stall" | RED — old-head-no-run is the true suspect and must still file |
| 5 | Harness: stub `gh api` run-list to return malformed JSON | RED — lookup failure must not silently clear a candidate |
| 6 | Must-PASS: QUEUED entry with null `headCommit.oid` and age > threshold | GREEN only if it files — the null-oid path is unchanged |

### Guard 2 — coalesced-push token reach (two sibling workflows)

**Property.** An anchored `[skip-github-apply]` / `[skip-sentry-apply]` / `[ack-destroy]` token on ANY commit in `github.event.commits` is honored identically to a tip-commit token.

**Assembly.** The four reader sites — kill-switch step and destroy-guard step in `apply-github-infra.yml` and `apply-sentry-infra.yml`. The chokepoint is the env-to-regex chain: `HEAD_MSG` ∪ `EVENT_MSGS_JSON` → `POLICY_MSGS` → anchored regex. The regex-parity suite (`test-destroy-guard-regex-parity.sh`) pins the literal across all sites.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert a reader to `HEAD_MSG`-only | RED — below-tip token fixture must fire the gate |
| 2 | Concat `EVENT_MSGS_JSON` without the `null`/empty guard so `POLICY_MSGS` gains a literal `null` line | RED — a no-event-commits fixture must behave exactly as today |
| 3 | Drop the line-anchoring on the token regex while reading the combined var | RED — a quoted/`Co-Authored-By:` token inside a message body must not fire |
| 4 | Dispatch run (`event.commits` empty) behaves differently than today | RED — `workflow_dispatch` fixture must match current skip/ack outcomes |
| 5 | Harness: `jq` absent/fails → `more_msgs` empty | GREEN-equivalent guard row — fallback to HEAD_MSG preserved (must-PASS with degraded input) |
| 6 | Must-PASS: tip-commit token on a normal push | GREEN — identical to today |

### Guard 3 — pr-selection three-dot diff base

**Property.** The `pull_request` file list equals `merge-base(HEAD^2, live base ref)..HEAD^2`; the frozen merge-ref parent `HEAD^1` is never the base.

**Assembly.** `scripts/ci-pr-selection.sh` `run()` pull_request arm: the `PR_BASE_REF` regex gate → `refs/heads/` fetch → `merge-base` → `git diff` — a single chokepoint with named fail-closed reasons, plus the `PR_BASE_REF` env wire in `ci.yml`'s pr-selection step.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert diff to `HEAD^1 HEAD` | RED — stale-frozen-parent fixture must produce only the PR-side file list |
| 2 | Skip the fetch (use payload `base.sha` directly) | RED — stale-base fixture must still resolve the live merge-base |
| 3 | Fetch `"$PR_BASE_REF"` unpinned (no `refs/heads/` prefix) | RED — hex/tag-shaped ref fixture must not FETCH_HEAD outside the named branch |
| 4 | `reason` names unchanged while a new failure path is added unnamed | RED — each named-failure row asserts its own reason token |
| 5 | Harness: fetch stubbed to fail | RED — must emit `base_fetch` reason, not proceed to diff |
| 6 | Must-PASS: up-to-date branch where `HEAD^1` == merge-base | GREEN — file list identical to today |

### Anchor

All three guards compare live workflow/script text to committed fixtures in their own suites; a weakening edit must also falsify the same-file sentinel tests, so no single diff can move both the guard and its oracle undetected (each suite is exercised by the required `test` aggregate + the deploy-script tests leg).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#11764 tmpfs leak: ~6.3k scratch-residue entries in /tmp — test/hook producers leave mktemp files and fixture dirs … route producers through the ownership-keyed scratch-root pattern from prior tmpfs work, or add mktemp cleanup/traps" | Phase 5 (census + test-helpers TMPDIR + script traps + agent-env TMPDIR + `.cs` reaper arm) | mapped |
| 2 | "#12484 ci: scripts/ci-pr-selection.sh pull_request diff base is the frozen merge-ref HEAD^1 — same stale-base class fixed for ci-oracle-lane.sh in merged PR #12480 … needs its own PR_BASE_REF wiring + refs/heads/-pinned fetch" | Phase 1 | mapped |
| 3 | "#12501 sibling workflows share the coalesced-merge blind spot … apply the same fix to .github/workflows/apply-github-infra.yml … and .github/workflows/apply-sentry-infra.yml" | Phase 2 | mapped |
| 4 | "#12507 merge-queue-stall-check.yml false-positives on promotion under max_entries_to_build=1 … reset/exclude the aging window for entries promoted from depth>1, or measure age from build start not enqueue" | Phase 3 (build-start aging — the issue's second option, already architecture-strategist-ruled in the body) | mapped |
| 5 | "#12508 vinngest tag→pin-bump red window: authored pin-bump PR … goes BEHIND … and armed auto-merge never self-updates … Read the full issue body for the fix direction" | Phase 4 (explicit `enqueuePullRequest` — issue candidate 1, enqueue form) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `agent-env.ts` TMPDIR injection | "route producers through the ownership-keyed scratch-root pattern from prior tmpfs work" | asked |
| `tmpfs-guard.sh` `.cs` age arm | "Optionally extend the tmpfs reaper to cover count-shaped residue (currently size-only)" — #11764 issue suggested-fix item 3 | asked |
| Census measurement | "Identify the live producers (grep `mktemp` in `.claude/hooks/`, `scripts/`, `plugins/soleur/scripts/`, test harnesses …)" — #11764 item 1 | asked |
| Runbook T5 note | "the T5 drift rule in knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md — a fix to one driver is consciously ported to the other" | asked |
| Guidance-text edits in sentry workflow | "apply-sentry-infra.yml:1302,1445 teaches operators that a re-run 'is the only one that carries the original head_commit.message' — text whose semantics change under any-commit reach and needs a dedicated editing pass" — #12501 | asked |
| ADR-270/ADR-250 addenda | — | inferred — justification: Phase 2.10 gate — both fixes extend recorded ADR claims; the recorded architecture must not lag the change |
| `test-apply-github-infra-mint-shape.sh` / adoption-guard test updates | — | inferred — justification: pinned-shape/count assertions break without same-diff updates (enforcement contract, not scope growth) |

### Split Assessment

- Subsystems touched: 5 — `.github/`, `scripts/`, `plugins/soleur/` (two-segment: `plugins/soleur`), `tests/`, `apps/web-platform`
- Planned files: ~16 edit + 0 create | Estimated changed lines: ~350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: over the subsystem threshold on paper — but the five issues are the operator-confirmed single-PR set, each fix is a mechanical port of a landed pattern, and splitting buys five queue cycles for diffs that share reviewers and the merge-queue surface. **single PR** (ask-confirmed).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `git grep -n 'diff -z --raw.*HEAD\^1 HEAD' scripts/ci-pr-selection.sh` returns zero matches on the diff invocation (explanatory comments may still name `HEAD^1`); `git grep -n 'merge-base HEAD\^2 FETCH_HEAD' scripts/ci-pr-selection.sh` returns ≥1; `git grep -n 'PR_BASE_REF' .github/workflows/ci.yml` returns ≥1 hit inside the pr-selection step env.
- [ ] AC2: `bash scripts/ci-pr-selection.test.sh` exits 0, including the new stale-frozen-parent fixture row (a `HEAD^1` ≠ merge-base shape yields only the PR-side file list) and the `bad_base_ref`/`base_fetch`/`no_merge_base` named-reason rows.
- [ ] AC3: `git grep -n 'EVENT_MSGS_JSON' .github/workflows/apply-github-infra.yml` returns ≥2 hits (kill-switch + destroy-guard env); same for `apply-sentry-infra.yml`; every anchored token regex at the four sites reads the combined `POLICY_MSGS` var, not `HEAD_MSG` alone.
- [ ] AC4: `bash tests/scripts/test-destroy-guard-regex-parity.sh`, `test-destroy-guard-counter.sh`, `test-destroy-guard-counter-sentry.sh`, `test-apply-github-infra-mint-shape.sh`, and `test-sentry-alert-adoption-guards.sh` all exit 0 — including the new below-tip-token fixtures.
- [ ] AC5: `git grep -n 'head_commit\.message' .github/workflows/apply-sentry-infra.yml` — remaining hits are env wiring or comments that no longer claim a re-run is the only carrier of the original message; the `:1445` "only gesture" text and `:1302` AC17 text are rewritten for any-commit reach.
- [ ] AC6: `merge-queue-stall-check.yml` contains a build-start aging arm: flagged entries with a valid `headCommit.oid` correlate their `merge_group` ci.yml run and re-age from `run.created_at`; `bash plugins/soleur/test/merge-queue-stall-check.test.sh` exits 0 with new rows covering promoted-young-build (no file), promoted-old-build (file), no-merge_group-run (file), and null-oid (unchanged).
- [ ] AC7: `git grep -n 'enqueuePullRequest' .github/scripts/bump-inngest-bootstrap-pin.sh` returns ≥1 hit inside the arm-auto-merge branch only (mirror_only/withheld paths carry no enqueue call); `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` exits 0 with the enqueue-call, enqueue-failure-warn, and withheld-no-enqueue rows.
- [ ] AC8: `git grep -n 'TMPDIR' apps/web-platform/server/agent-env.ts` shows the per-tenant injection beside `CLAUDE_CODE_TMPDIR`; vitest files asserting the env shape (`agent-runner-query-options.test.ts`, `cc-dispatcher-real-factory.test.ts`) pass.
- [ ] AC9: `plugins/soleur/test/test-helpers.sh` exports `TMPDIR` at the owned sandbox in its no-outer-root arm; `git grep -n 'export TMPDIR' plugins/soleur/test/test-helpers.sh` returns ≥1.
- [ ] AC10: `scripts/tmpfs-guard.sh` reaps entries under `/tmp/.cs` older than the 48h floor (owned-base age arm); `bash scripts/tmpfs-guard.test.sh` exits 0 with rows for the `.cs` arm (aged-out entry reaped; fresh entry kept; un-owned `/tmp` entry untouched).
- [ ] AC11: every census-confirmed repo-owned `mktemp` producer in the recorded list carries a cleanup (`trap`/`rm -f`) or writes under an owned root — asserted per-site in the work log; no new bare-`tmp.*`-class producer is added by this diff (`git diff origin/main...HEAD -- '*.sh' | grep -c '+.*mktemp'` new sites each carry cleanup in the same hunk or a named owned root).
- [ ] AC12: `actionlint` exits clean on the four edited workflows (`.github/workflows/{ci,apply-github-infra,apply-sentry-infra,merge-queue-stall-check}.yml`) and `bash -n` clean on every edited `.sh`.
- [ ] AC13: ADR-270 and ADR-250 each carry a dated 2026-11-09 addendum recording the landed behavior (explicit enqueue for authored bot PRs; `.cs` owned-base routing + age reaping).
- [ ] AC14: the PR body carries the producer census histogram (prefix → count → disposition: repo-fixed / agent-routed / external-documented) recorded by the work phase; `closes #11764`, `closes #12484`, `closes #12501`, `closes #12507`, `closes #12508` all present.

### Post-merge (follow-through)

- [ ] AC15: the next `vinngest-v*` tag publish's bump PR shows `added_to_merge_queue` within one publish-run (measured via `gh pr view <N> --json mergeQueueEntry` or the queue timeline) — evidence lands on #12508 or this PR as a comment.
- [ ] AC16: within 7 days, no SUSPECTED-stall issue filed for a head whose own `merge_group` build was younger than 45 min at filing time (sample any filings; self-closing drain unaffected).
- [ ] AC17: `/tmp` top-level entry count trend on the operator host shows the repo-owned prefix classes no longer accumulating (tmpfs-guard watermark does not ratchet through them) — measured at the next guard alarm or 7 days, whichever first.

## Test Scenarios

| # | Scenario | Suite/command | Expected |
|---|----------|---------------|----------|
| 1 | Merge-carrying PR branch (frozen parent ahead of fork point) | `ci-pr-selection.test.sh` stale-base fixture | Selected set excludes main-side re-counted files |
| 2 | `PR_BASE_REF` unset/hex-shaped/tag-shaped | `ci-pr-selection.test.sh` named-reason rows | `bad_base_ref` fail-closed, no diff attempted |
| 3 | Fetch failure mid-run | `ci-pr-selection.test.sh` stubbed-fail row | `base_fetch` reason, fail-open per job design |
| 4 | `[skip-github-apply]` on a non-tip commit of a coalesced push | `test-destroy-guard-counter.sh` + workflow-shape row | Kill switch fires (skip=true) |
| 5 | `[ack-destroy]` below the tip, destroy plan present | counter suites for both workflows | Destroy gate releases the apply |
| 6 | Token inside quoted block / Co-Authored-By trailer in a non-tip commit | counter suites | Anchored regex does NOT fire |
| 7 | `workflow_dispatch` (empty commits array) | counter suites | Identical outcomes to today (no regression) |
| 8 | Depth-2 entry promotes to head with a just-started build | `merge-queue-stall-check.test.sh` gh-stub row | No filing |
| 9 | Head aged >45m with no `merge_group` run | same suite | Files suspected-stall (true stall) |
| 10 | oid-correlation gh-api failure | same suite | Bounded `::warning`, entry still files (existing contract) |
| 11 | Pin-bump arm path | `test-bump-inngest-bootstrap-pin.sh` stub row | `enqueuePullRequest` mutation invoked with PR node id, no `jump` arg |
| 12 | Enqueue API rejection | same suite | `::warning` + exit 0; auto-merge arm intact |
| 13 | mirror_only / provenance-unbound path | same suite | No enqueue call |
| 14 | Suite sourcing test-helpers with ambient TMPDIR=/tmp | test-helpers arm | descendant `mktemp` lands inside the owned sandbox dir |
| 15 | Agent session spawn | `agent-runner-query-options.test.ts` | env carries `TMPDIR` == per-tenant `/tmp/.cs/<hash>` |
| 16 | `.cs` tree with 49h-old and 1h-old entries | `tmpfs-guard.test.sh` | Old reaped, fresh kept, non-`.cs` `/tmp` untouched |

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (94 issues, 2026-11-09) contains no body reference to any planned file path.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. No UI-surface file in Files to Edit/Create (mechanical override checked: no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or ui-surface term in the file lists) — Product tier NONE, no UX gate.

## Infrastructure (IaC)

Skipped — no new infrastructure (no server, service, cron, vendor account, DNS record, secret, or firewall rule is introduced). All edits land inside already-provisioned surfaces.

## Encryption Posture

Skipped — no persistent data store and no new cross-component/network connection is introduced.

## Task Design

Skipped — no NEW autonomous-task surface is created (no new workflow file, cron, Inngest function, registered check, pg_cron, timer, or daemon); all edits modify existing surfaces.

## Dependencies & Risks

- **PR #12495 (open, `feat-one-shot-12269-max-entries-build`)** edits `merge-queue-stall-check.yml` (2-line value flip + comments) and `merge-queue-stall-check.test.sh` — expect a rebase; our diff is confined to the run body + new comment/test rows to minimize collision. Whichever merges second rebases.
- **PR #12498 (open, `feat-one-shot-12403-coalesced-blind-spot`)** edits `apply-web-platform-infra.yml` + `deploy-policy-gate.sh` — disjoint file set; no conflict expected. If it merges first, mirror its final concat shape if it diverges from #12404's.
- **`CI_PR_AFFECTED` is still dark** — the #12484 defect is telemetry-only until activation, so the port carries no live behavior change on merge (verified: `vars.CI_PR_AFFECTED` unset → job skipped).
- **`apply-github-infra` / `apply-sentry-infra` edits are inert until the next matching push** — both trigger on push-to-main path filters; the kill-switch reads only commit messages, so merging this PR does not itself trigger either apply (this PR touches `.github/workflows/` only, outside the `infra/**`/`terraform` paths these workflows filter on — verify at merge time per the PR-body blast-radius line).
- **`/tmp/.cs` reaping is age-based within an owned base** — the 48h floor keeps in-flight artifacts safe; the arm is additive (no change to existing reaper tiers).
- **Rollback:** single revert PR restores all five surfaces; no state, secrets, or external resources are mutated by merging.

## Success Metrics

- #12508: red window for the next pin bump bounded to ≤ one merge_group CI cycle (~60-90 min) vs. measured 5h20m+.
- #12507: zero promoted-head false-positive filings post-merge (AC16).
- #11764: repo-owned prefix classes stop accumulating in `/tmp`; `.cs` reclaim keeps the consolidated tree bounded.
- #12484: selector diff equals GitHub's three-dot semantic on merge-carrying branches (verified by the stale-base fixture).
- #12501: below-tip tokens honored on the next coalesced push touching either sibling's path filter.

## References & Research

- Issues: #11764, #12484, #12501, #12507, #12508 (all OPEN, verified 2026-11-09); related: #12403/#12404 (merged reference), #12418/#12480 (merged reference), #12495/#12498 (in-flight siblings), #12506 (instance tracker), #12269 (lever-E flip), #9927 (host-replace precondition blocked by the red window), #8359/#9262/#8782 (pin-bump machinery lineage), #7004 (ADR-250), #6991/#11764-class (count-shaped leak lineage).
- ADRs: ADR-250 (ownership-keyed scratch), ADR-270 (merge queue), ADR-285 (App-authored bot PRs), ADR-129 (trap composition), ADR-276 (oracle lane / merge_group authority), ADR-232 (auto-bump flow), ADR-195 (report-not-reap for unattributable orphans).
- Runbooks: `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` (T5), `knowledge-base/engineering/operations/runbooks/merge-queue-jump.md` (enqueue mechanism), `knowledge-base/engineering/operations/runbooks/tmpfs-guard-install.md`.
- Learning: `knowledge-base/project/learnings/workflow-issues/2026-10-11-tmpfs-count-shaped-mktemp-leak-across-agent-sessions.md`.

## Files to Edit

- `scripts/ci-pr-selection.sh` — three-dot port (#12484)
- `scripts/ci-pr-selection.test.sh` — sentinel fixtures/rows (#12484)
- `.github/workflows/ci.yml` — `PR_BASE_REF` env wire (#12484)
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` — T5 port-landed note (#12484)
- `.github/workflows/apply-github-infra.yml` — two combined-var readers + comment (#12501)
- `.github/workflows/apply-sentry-infra.yml` — two combined-var readers + guidance text (#12501)
- `tests/scripts/test-destroy-guard-counter.sh` — below-tip fixtures (#12501)
- `tests/scripts/test-destroy-guard-counter-sentry.sh` — below-tip fixtures (#12501)
- `tests/scripts/test-apply-github-infra-mint-shape.sh` — env snapshot update (#12501)
- `tests/scripts/test-sentry-alert-adoption-guards.sh` — count re-derive if affected (#12501)
- `.github/workflows/merge-queue-stall-check.yml` — build-start aging arm (#12507)
- `plugins/soleur/test/merge-queue-stall-check.test.sh` — fixture rows (#12507)
- `.github/scripts/bump-inngest-bootstrap-pin.sh` — explicit enqueue (#12508)
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — stub rows (#12508)
- `plugins/soleur/test/test-helpers.sh` — TMPDIR routing (#11764)
- `apps/web-platform/server/agent-env.ts` — TMPDIR injection (#11764)
- `apps/web-platform/test/agent-runner-query-options.test.ts` — env assertion (#11764)
- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — env-shape rows if it asserts the allowlist product (#11764)
- `scripts/tmpfs-guard.sh` — `.cs` owned-base age arm (#11764)
- `scripts/tmpfs-guard.test.sh` — `.cs` arm rows (#11764)
- `plugins/soleur/skills/skill-security-scan/scripts/lib.sh` + `run-scan.sh` — mktemp cleanup (#11764, census-confirmed)
- `plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` — mktemp cleanup (#11764, census-confirmed)
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`, `tests/scripts/lib/git-data-birth-readiness-gate.sh`, `tests/scripts/test-git-data-birth-readiness-gate.sh` — `rung2-*` cleanup (#11764, census-confirmed)
- `.claude/hooks/` non-test mktemp sites lacking cleanup (~9 files; final list from census) (#11764)
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — dated addendum
- `knowledge-base/engineering/architecture/decisions/ADR-250-ownership-keyed-scratch-reclamation.md` — dated addendum

## Files to Create

None — every fix lands inside existing files/suites (Cut List).
