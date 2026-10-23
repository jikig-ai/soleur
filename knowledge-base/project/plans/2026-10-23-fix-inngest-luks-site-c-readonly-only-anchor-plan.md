---
title: "fix: Inngest generation anchor reads the read-only Hetzner token only (Site C)"
date: 2026-10-23
slug: inngest-luks-site-c-readonly-only-anchor
branch: feat-one-shot-inngest-luks-site-c-readonly
issue: 10664
type: fix
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix: Inngest generation anchor reads the read-only Hetzner token only (Site C)

`Ref #10664` (never a closing keyword: the tracker has other open items). Epic #10390. Draft PR #10891.
Spec lacks a valid `lane:` (no `spec.md` exists for this branch), so `lane: cross-domain` is the
fail-closed default.

## Enhancement Summary

**Deepened on:** 2026-10-23
**Sections enhanced:** Research Reconciliation, Files to Edit, Phases 0-5, Guard Contract, Observability,
Acceptance Criteria, Risks
**Agents used:** security-sentinel, test-design-reviewer, architecture-strategist (review), plus the CTO
agent for rulings R8 and R9 (`decision-challenges.md`); the mechanical gates 4.6-4.12 were run
directly.

### Key improvements

1. The first draft said no edited file fires an apply workflow. It is false for
   `apps/web-platform/infra/cutover-inngest-workflow.test.sh`; the plan now carries the kill-switch merge
   step, a post-merge check and an operator item (the brief's constraint conflicts with ask 1).
2. The scanner now evaluates every operand after `get`, widens the one-hop definition sites, scans the
   inverted population, refuses inherited seam variables under `GITHUB_ACTIONS`, and splits into a
   probe-able scanner plus a mutation suite (R8, R9c).
3. The allowlist expiry follows the trio model (RED only on a pull request touching the guarded files)
   so it cannot stop unrelated PRs or tenant deploys (R9b).
4. ADR-225 is amended append-only; registration follows the right precedent (`no-tofu-ssh`) and the
   registration checks are explicit; the discoverability probe no longer runs a suite.

### New considerations discovered

- Merging also cuts a web-platform release of unchanged code (the test file is not excluded from its
  path filter); the plan says so in the PR body.
- Wrapper-function indirection stays a named blind spot with a real runtime backstop.
- The first live scanner run over the inverted population must be listed in the PR body.

## Overview

`_inngest_server_created_epoch` in `scripts/cutover-inngest.sh` reads `HCLOUD_TOKEN_READONLY` from
`soleur/prd_terraform` and, when that read returns nothing, falls back to the read/write
`HCLOUD_TOKEN`. The fallback was the live path until operator steps O5 (mint the read-only token) and
O10 (evict the read/write name) landed; a names-only listing of `soleur/prd_terraform` on 2026-10-20
shows `HCLOUD_TOKEN_READONLY` listed and `HCLOUD_TOKEN` absent. The fallback has therefore had no live
member for three days, and it is the last read-only-then-read/write fallback in the repository that
the Tier-B census cannot see (the census reads workflow `run:` bodies only).

This PR (PR-A of the Inngest LUKS arc):

1. removes the fallback (read-only token alone; an absent token is the existing `unreadable` refusal),
   and fixes the stale comment that justified it;
2. corrects every sentence that still says the fallback exists (runbook, ADR-225, ADR-241, the
   credential-tiers runbook, the C4 edge description);
3. adds a scanner (`scripts/lint-hcloud-token-readonly-no-fallback.sh`) over `scripts/` and sibling script trees, driven by a
   standalone mutation-matrix suite (CTO R1/R8), so the next
   read-only-then-read/write fallback, or a new bare read of the read/write name, is red in CI.

Out of scope, each already tracked in #10664 or #9755: `inngest-server-flip-guard.sh` (feeds
`user_data` at `server.tf` ~2281, so even a comment edit changes baked host bytes and rides the
host-replace window package); the `op=backup` read of the bare `HCLOUD_TOKEN` at ~line 1900 of the
same script (a Hetzner write that needs a reviewer-gated Tier-B environment; CTO 2026-10-22: docs
only); the orphan-sweep steps, the user notice and the Doppler plan-tier read (other #10664 items).

## Research Reconciliation — Spec vs. Codebase

| Claim in the ask / tracker | Reality (verified 2026-10-23 on this branch, `origin/main` = `c9133926a8`) | Plan response |
|---|---|---|
| "Fix the stale `Measured 2026-09-24` comment (~line 551)" | Two sentences in the file begin `Measured 2026-09-24`. Line 477 ("GENERATION. Measured 2026-09-24: the old server shipped its last flip row at 14:25:05...") records a host-replace measurement and is TRUE. Only the line 551-552 sentence ("prd_terraform holds only HCLOUD_TOKEN, so the fallback is the live path") is stale. | Edit only the l.547-561 comment and the l.563-590 body. An AC asserts line 477's sentence is still present. |
| "the matching notice (about line 550 and 586)" | Line 586 is the `::notice::` "using the read/write HCLOUD_TOKEN (... ADR-241 D4 fallback until it is minted)" inside a `[[ "$tokvar" == HCLOUD_TOKEN ]]` branch; line 588 is the positive "using HCLOUD_TOKEN_READONLY" notice. | CTO R4: both notices and the `$tokvar` variable go (one static credential). |
| "remove the fallback" is one edit | Four suites assert the fallback: `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (doppler stub l.1183-1189, asserts l.1437-1455, l.1499-1513) and `tests/scripts/test-argv-bearer-sweep.sh` (l.2525 `empty-warning` check; mutant `warning-dropped` whose from-text contains `$tokvar`, l.2554). Removing the code alone reds both. | Tests are rewritten in the same commit as the code (Phase 2). |
| Docs to fix: runbook ~l.142, ADR-225 ~l.114, ADR-241 ~l.1105 | Also stale: `infra-credential-tiers-8209.md` (generation-anchor row ~l.160 says "still true on 2026-10-20 ... the one remaining fallback"; step 4 ~l.255 names "the site C fallback" as a place that still reads the old name), the runbook's "the warning names which variable was sent" (~l.133), and the `github -> hetzner` edge description in `knowledge-base/engineering/architecture/diagrams/model.c4` l.739 ("both read HCLOUD_TOKEN_READONLY first and fall back to HCLOUD_TOKEN (ADR-241 D4) until it is minted"; stale for the workspaces-luks-cutover reader since 8b too). | CTO R3 / R7: all are in scope as directly-dependent false statements. `model.likec4.json` is regenerated, never hand-edited. |
| "Add a census row" | The Tier-B census (`tests/scripts/test-infra-privileged-tier-census.sh`, 4392 lines) is keyed on workflow `run:` bodies with a synthetic-fixture battery; it cannot see `scripts/`. | CTO R1: a standalone suite (trio-baseline precedent), not a census row. |
| Two bare `HCLOUD_TOKEN` reads exist in `scripts/cutover-inngest.sh` | Confirmed: l.568 (the fallback) and l.1900 (`op=backup`). `git grep` over non-test, non-knowledge-base files finds no other `doppler secrets get HCLOUD_TOKEN`. | The scan allowlists exactly the l.1900 read (with #9755/#10664 and an expiry). |
| `scripts/cutover-inngest.sh` edits might trigger a prod dispatcher | `cutover-inngest.yml` `push` is path-scoped to its own file; `infra-validation.yml` lists the script under `pull_request.paths` only (runs `deploy-script-tests`). `registry-host-replace-dispatch.yml` keys only on `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf` and itself. | `scripts/cutover-inngest.sh` itself is safe. |
| "No file this PR edits fires an apply workflow" (the brief's constraint, and this plan's first draft) | FALSE for one file, found by the deepen-plan architecture review and verified: `apps/web-platform/infra/cutover-inngest-workflow.test.sh` must be edited (it asserts the removed fallback), and a push to main touching `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml` (`push.paths`, environment `infra-privileged`), `web-platform-release.yml` (`apps/web-platform/**`; `path_filter` excludes only `plugins/soleur/docs/` and `plugins/soleur/test/`) and `infra-validation.yml`. ADR-280:99 records the trap; #10652 edited the sibling suite the same way. | CTO R9a: no way around the edit; the kill switch `[skip-web-platform-apply]` in the squash body (AC8) is adequate only if verified (AC9). The conflict with the brief is an operator item (Risks; `decision-challenges.md`). |

## Research Insights

**Premise Validation (Phase 0.6).** Cited by reference and re-checked: #10664 OPEN (the tracker's own
text says O10 "was measured done on 2026-10-20, so this is now actionable"); #10390 OPEN; PR #10891
draft/open (this branch); PR #10692 draft/open (untouchable, not read or touched). Cited paths all
exist on this branch: `scripts/cutover-inngest.sh` (the 547-600 block holds the fallback),
`runbooks/inngest-server.md` l.142, ADR-225 l.114 (item 4 of the 2026-09-24 Amendment), ADR-241 l.1105
(the "Left open" bullet of the 2026-10-20 entry). ADR corpus check: ADR-241 D4 (accepted) and its
2026-10-20 entry already ruled "no fall-back from the read-only token to the write token"; this plan
completes that ruling for the one site it left open. No ADR rejects removal. The tracker's
claim "the Better Stack retention comment in `inngest-server-flip-guard.sh`" is the excluded item.

**Property List (Phase 0.6b).**

- P1. The generation anchor is read with the read-only Hetzner token and never with the read/write one.
- P2. An absent, empty or unusable read-only token refuses fail-closed with a warning that names the
  variable and where to restore it (no silent downgrade, no substitution).
- P3. No document in the repository states that the fallback exists or is "the live path".
- P4. A bare read of the read/write name through `doppler secrets get` anywhere in `scripts/`,
  `plugins/**/scripts/` or `apps/*/infra/**/*.sh` fails CI unless it is a tracked, expiring exception.

**Cut List.** (mechanism -> property -> what already covers it)

- A census row in the 4392-line workflow census -> P4 -> a standalone suite covers it with a
  fixture battery of its own (CTO R1); the census cannot read non-workflow files.
- A "pairing rule" (a file holding both the read-only and the bare read) -> P4 -> redundant with the
  per-site rule, and true in `scripts/cutover-inngest.sh` today via the allowlisted line (CTO R2).
- A file-level non-literal arm (any non-literal read in a file naming a Hetzner variable) -> P4 ->
  would flag the unrelated `"$CK"` read in the same script (CTO R5); replaced by two narrower arms.
- A new notice/log line for the removed path -> P2 -> the existing warning already covers it.
- A new Doppler/Hetzner probe to "re-confirm" O5/O10 -> P1 -> the 2026-10-20 names-only listing is the
  recorded measurement; a live credentialed probe is excluded by the brief.

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):
`2026-10-15-removing-a-printed-recipe-owes-a-bounded-replacement-and-a-spelling-guard-is-a-tripwire.md`
(match structure, expect several review rounds, vary the axes of the forbidden pattern);
`2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis.md` (a mutation
battery that varies one axis proves little);
`2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md` (a false
comment is restated by plan, ADR and tests unless each is checked against the code);
`2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md` (enumerated CI discovery
makes every new suite an orphan until registered);
`2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` (derive the work list by
`git grep`, not from the named filter);
`2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md` (dated
amendment, not a rewrite of the ADR body).

## User-Brand Impact

- **If this lands broken, the user experiences:** a refused (never a mis-run) Inngest cutover op: the
  generation anchor returns `__UNREADABLE__` and `op=resume` / `op=arm` / `op=luks-cutover` stop at G3
  with a `::warning::` naming `HCLOUD_TOKEN_READONLY`. Worst case is a delayed cutover dispatch by the
  owner. The ops are dispatch-only, so no end-user session or data is touched while the Inngest host is
  healthy; but `op=resume` / `op=arm` are the recovery verbs for a parked or flushed Inngest host, so if the
  owner dispatches one during an incident and the read-only secret is missing, recovery is blocked until
  the owner restores it, and the queued Inngest jobs and crons keep stalling for that time (review
  2026-10-23, user-impact P2-2). Merging also rolls out a release of unchanged code to the web hosts.
- **If this leaks, the user's workflow is exposed via:** nothing new. The change removes a code path
  that could read the destroy-capable token; no new credential, log field or egress is added. The
  token still travels on curl's stdin, is masked first, and no response byte is printed.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident`, because a wrong outcome here is a
  closed gate (refusal) rather than an open one, and no user data is read or written; not `none`,
  because the diff touches a credential-read path and the guard's false negative would let a future
  destroy-capable fallback ship unseen.

## Open Code-Review Overlap

Two open `code-review` issues name files this plan edits; neither concerns this change.

- #8800 (census sandbox shares inodes with the live repo): names `scripts/lib/test-affected-paths.sh`.
  **Acknowledge**: different concern. The new suite builds its fixtures under a fresh `mktemp -d`
  with copied files (no symlinks into the live tree), so it does not add a write-through hazard.
- #8659 (33 suites replace the composed EXIT trap): names `scripts/test-all.sh`. **Acknowledge**:
  different concern. The new suite installs exactly one EXIT trap, before anything is written.

## Files to Edit

- `scripts/cutover-inngest.sh` — comment block l.547-561 and the body l.563-590 of
  `_inngest_server_created_epoch` (the function header at l.562 is not touched). Drop `tokvar`, the
  fallback read and both notices; use the literal variable name in the shape and 401/403 warnings; the
  empty-token warning names only `HCLOUD_TOKEN_READONLY` and points at step O5 of
  `infra-credential-tiers-8209.md`. Do NOT touch l.477 (a true, unrelated measurement) or l.1900
  (`op=backup`).
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — the `doppler` stub in `lv_mocks`
  (~l.1183-1189) and the assertions titled "no token resolved" (verdict `__UNREADABLE__`), "the read/write
  fallback is announced by NAME", "a rejected token names the variable that was sent" and "falls back to
  HCLOUD_TOKEN only after an empty read-only read" (~l.1437-1456, ~l.1499-1513). This file fires the
  production push apply on merge; see Risks.
- `tests/scripts/test-argv-bearer-sweep.sh` — l.2525 (`empty-warning` text) and l.2554 (mutant
  `warning-dropped`: both its from-text and its to-text carry the old `$tokvar` wording).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — l.133 ("names which variable was
  sent") and l.139-146 (the "today that is the read/write HCLOUD_TOKEN" paragraph).
- `knowledge-base/engineering/architecture/decisions/ADR-225-per-operation-latched-flags-are-the-control-channel-for-a-host-with-no-inbound-path.md`
  — item 4 of the 2026-09-24 Amendment (l.113-119) stays as written; add the bracketed pointer
  "[Superseded 2026-10-23, see Amendment below]" to it and append a dated `#### Amendment — 2026-10-23`
  block in the file's existing idiom (CTO R9d).
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
  — a bracketed `*(Superseded 2026-10-23, #10664 Site C: ...)*` pointer on the "Left open" bullet
  (l.1105; its original wording stays, matching the file's own Superseded markers at l.365, l.629 and
  l.780) plus a NEW dated 2026-10-23 entry before `## References`.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` — the
  generation-anchor row (~l.160) and step 4 (~l.255), plus one sentence naming the scan. Leave the O4b
  row alone.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — one clause in the `github -> hetzner`
  description (l.739); `model.likec4.json` regenerates through the `c4-model-regenerate` hook.
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` —
  only if the Phase 3 sweep classifies its l.198 clause ("the silent fallback of the read-only loader;
  a no-fallback loader is carried by #9927") as a current-state false statement (stale since 8b).
- `scripts/test-all.sh` — one `run_suite` line next to `trio-baseline-census` (~l.6225).
- `scripts/lib/test-affected-paths.sh` — add the suite label to `ALWAYS_ON_SUITES` (list at ~l.106).

Contingent, decided in Phase 4.3 by a command and not by guess: the additive rows of
`scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv` (+ their `.n` files) if the shard
manifest check reports the new label as untabled and untabled is not accepted.

## Files to Create

- `scripts/lint-hcloud-token-readonly-no-fallback.sh` — the scanner: live scan only, honours `HCLOUD_SCAN_ROOT` and `HCLOUD_SCAN_TODAY`, prints
  `live: findings=0 allowlisted=1`, exits non-zero on a finding (CTO R8). It is also the
  `discoverability_test` probe. It is a new shell script whose source names `doppler secrets get`,
  so it carries the repo's xtrace-refusal preamble or builds the phrase from parts (Phase 4.4).
- `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` — the mutation-matrix suite: drives the scanner against synthetic fixtures and runs it once
  against the REAL tree requiring `findings=0` (without that row nothing guards the live tree).
- `knowledge-base/project/specs/feat-one-shot-inngest-luks-site-c-readonly/tasks.md` (plan phase).

Explicitly NOT touched: `apps/web-platform/infra/inngest-server-flip-guard.sh`, any `*.tf`,
`cloud-init*.yml`, any `.github/workflows/*` file, `.github/actions/**`, migration 163, PR #10692's
worktree. Pipeline-written files the diff-scope AC must allow: `knowledge-base/INDEX.md` (if the
pipeline regenerates it) and, under `knowledge-base/project/specs/feat-one-shot-inngest-luks-site-c-readonly/`,
`tasks.md`, `decision-challenges.md` and `session-state.md`.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: the scan suite and the rewritten assertions go RED
against the current code first, then the code and docs make them green.

### Phase 0 — RED: the scan suite and the rewritten assertions (no production code yet)

0.1 Write the scanner `scripts/lint-hcloud-token-readonly-no-fallback.sh` and the suite `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` per the Guard Contract below
  (the suite holds the real-tree row and the synthetic-fixture mutation matrix; write the suite first). Budget: the suite stays small (one
  scanner function, one allowlist table, one table-driven matrix loop). Run it against the unmodified
  tree: it MUST be RED with exactly one finding, the fallback read at ~l.568 of
  `scripts/cutover-inngest.sh` (F-literal, un-allowlisted); the `op=backup` read at ~l.1900 is
  allowlisted and clean. Record the RED output in the PR body. Re-run the two non-literal arms against
  `git ls-files` here (CTO R5): if either arm hits an unrelated site, fall back to the same-line arm
  only and record the extra blind spot; list the first live run's findings (the inverted population
  now includes `.claude/hooks`, `*.service`, `cloud-init*.yml` and `*.tf`) in the PR body.
0.2 In `apps/web-platform/infra/cutover-inngest-workflow.test.sh` replace the fallback assertions with
  the new contract (Phase 2) and run it: RED against the current script.
0.3 In `tests/scripts/test-argv-bearer-sweep.sh` update the `empty-warning` check and the
  `warning-dropped` mutant to the new warning text; run its `lead (a1)` rows: RED.

### Phase 1 — GREEN: remove the fallback in `scripts/cutover-inngest.sh`

1.1 Comment block (l.547-561), rewritten to state facts as of the change: "Tier A only (ADR-241 D4,
  #10664): HCLOUD_TOKEN_READONLY, read alone. There is NO fallback to the read/write HCLOUD_TOKEN: O5
  and O10 are done (names-only listing of soleur/prd_terraform, 2026-10-20: the read-only name listed,
  the read/write name absent), and a reader that can reach the destroy-capable token stops being
  read-only the day the read-only secret goes missing. An absent, empty or unusable read-only token is
  `__UNREADABLE__` with one warning naming it; restore it per infra-credential-tiers-8209.md step O5.
  Guarded by scripts/lint-hcloud-token-readonly-no-fallback.sh." Keep the remaining
  public-log hygiene bullets. Leave the `Measured 2026-09-24` sentence at l.477 alone.
1.2 Code: delete `tokvar`; one `doppler secrets get HCLOUD_TOKEN_READONLY -p soleur -c prd_terraform
  --plain` read; an empty read gets the warning "doppler returned nothing for HCLOUD_TOKEN_READONLY in
  prd_terraform (unset, a Doppler auth failure or a network failure - not distinguished), so the
  current $INNGEST_HOST server could not be identified. Nothing was written; restore the token (step
  O5 of infra-credential-tiers-8209.md) and re-dispatch."; `_bearer_ok` failure -> the marker plus the
  shape warning with the literal name; `::add-mask::` unchanged and still second; delete the
  `tokvar`-comparison notice block entirely; the 401/403 warning says "the one sent was
  HCLOUD_TOKEN_READONLY". Declarations become `local tok resp rc=0 code body epoch now`.
1.3 Run `bash -n scripts/cutover-inngest.sh` and the repo's shell lint for it.

### Phase 2 — rewrite the assertions of the removed behaviour

`apps/web-platform/infra/cutover-inngest-workflow.test.sh`:

- Stub (`lv_mocks`): keep the bare-name branch as BAIT, keyed on the NAME and not the argv: any
  `secrets get HCLOUD_TOKEN` followed by any flags records `HCLOUD_TOKEN` into `FLV_HC_READS` and returns
  `RW-TOKEN-SENTINEL` for modes `both` and `rw`, so a reordered-flag respelling of the bare read cannot
  slip into the stub's generic miss arm. One recording channel (the `FLV_HC_READS` equality below is
  what fails on a bare read).
- l.1437-1439: the new warning text for mode `none`.
- l.1448-1456: replaced by one block. Mode `rw` (read-only empty, read/write present) gives
  `__UNREADABLE__`, zero curl calls, `FLV_HC_READS` exactly `HCLOUD_TOKEN_READONLY`, and
  `RW-TOKEN-SENTINEL` in none of stdout, stderr, `FLV_CURL_ARGV`, `FLV_CURL_STDIN` and
  `FLV_CURL_CALLS`; `FLV_STUB_MISS` is asserted empty inside this block too. The "read/write token is masked too" assertion
  (l.1451-1452) is deleted, since that sentinel must now never appear. The 401 row at l.1453 becomes
  `call_flip_liveness_count current http401 both` (not `rw`, which would stop before any request) and
  expects "the one sent was HCLOUD_TOKEN_READONLY;".
- l.1499-1513: keep "only HCLOUD_TOKEN_READONLY is read when it resolves"; delete the "falls back to
  HCLOUD_TOKEN only after an empty read-only read" assertion (the `rw` block above is its replacement,
  not a second copy).
- l.1599-1602 (stub controls) stay.

`tests/scripts/test-argv-bearer-sweep.sh`: l.2525 expects "doppler returned nothing for
HCLOUD_TOKEN_READONLY in prd_terraform"; the l.2554 mutant `warning-dropped` takes a from-text of
`echo "::warning::G3 generation anchor: the HCLOUD_TOKEN_READONLY read` (the leading indentation is
kept) and a to-text of `: "::warning::G3 generation anchor: the HCLOUD_TOKEN_READONLY read` (same
indentation; one clause, one line, which is what `text_mut` requires). No other change to that file: the scan suite covers the bare-read property.

### Phase 3 — documentation (facts as of 2026-10-23; no premature future tense)

- Runbook `inngest-server.md`: l.133 "the warning names which variable was sent" becomes "the warning
  names HCLOUD_TOKEN_READONLY"; l.139-146 is rewritten to "The anchor reads HCLOUD_TOKEN_READONLY alone:
  since #10664 (2026-10-23) there is no fallback to the read/write HCLOUD_TOKEN, which no longer exists
  in prd_terraform (names-only listing 2026-10-20). A missing or unusable read-only token is
  unreadable; re-dispatching does nothing until it is restored (infra-credential-tiers-8209.md step
  O5)." The existing "so all four ops now also refuse ..." sentence is kept as written.
- ADR-225: item 4 of the 2026-09-24 Amendment stays as written (a true record of what was measured
  then); append the bracket "[Superseded 2026-10-23, see Amendment below]" to it and add, after the
  existing amendment, a `#### Amendment — 2026-10-23: the generation-anchor read has no fallback`
  block: the read uses HCLOUD_TOKEN_READONLY alone (ADR-241 D4); the fallback was the live path from
  2026-09-24 until O5 and O10 landed and was removed once both were measured done (names-only listing
  2026-10-20) under #10664 Site C; the mask, stdin and no-response-byte rules are unchanged (CTO R9d).
- ADR-241: a new `### 2026-10-23 (#10664 Site C): the generation anchor no longer falls back, and
  scripts/ is scanned` entry ("Appended"; "No status change; D4 stays accepted"; it avoids the
  `Allow:`, `Re-date:` and `Reclass:` line tokens the trio census parses). It carries four facts and a pointer: the Site C removal; the scanner's path (its header
  holds the population, finding rule and blind spots, so they cannot drift here); the one allowlisted
  `op=backup` read with expiry 2026-12-15 and trackers #9755 and #10664; that `op=backup` stays open;
  and the residual that a read/write token stored under the read-only name is undetectable (the control
  is the O5 write-probe, last recorded 2026-09-29, not re-run). The old "Left open" bullet keeps its
  wording and gets a trailing `*(Superseded 2026-10-23, #10664 Site C: closed, see the entry below; the
  op=backup half stays open.)*`.
- `infra-credential-tiers-8209.md`: the generation-anchor row becomes "HCLOUD_TOKEN_READONLY alone (no
  read/write fallback since #10664, 2026-10-23)"; step 4's sentence names only the `op=backup` path as
  the remaining reader of the old name; one added sentence points at the scan suite. The O4b row is
  untouched.
- `model.c4` l.739: replace "both read HCLOUD_TOKEN_READONLY first and fall back to HCLOUD_TOKEN
  (ADR-241 D4) until it is minted" with "both read HCLOUD_TOKEN_READONLY alone, with no fall-back to the
  write token (ADR-241 D4, #9927 item 8b, #10664); op=backup reads the absent read/write name and
  refuses, #9755)". Commit through the hook so `model.likec4.json` is
  regenerated and staged (never hand-edit it; if the hook cannot run, stop and report); then run
  `bash plugins/soleur/test/c4-model-freshness.test.sh` and
  `bash plugins/soleur/test/c4-count-parity.test.sh`.
- Sweep (derive the list by grep, not from this plan): run

  ```bash
  git grep -nE 'falls? back to (the )?(read/write )?`?HCLOUD_TOKEN|read/write .?HCLOUD_TOKEN|until (it|the read-only token) is minted|not yet minted|site C fallback|read-only-then-read/write|which variable was sent|which token it used|prints which token|silent fallback' -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'
  ```

  The plan, specs and learnings quote the phrases on purpose and are excluded, or the sweep is
  unsatisfiable by construction. Classify every hit as historical (kept) or current-state (fixed). The
  planner's run on 2026-10-23 (before `silent fallback` was added to the pattern) returned 24 hits
  across 13 files; the current-state ones are the script
  (l.552, l.586), the workflow suite (l.1450, l.1512), ADR-225 (l.114-116), ADR-241 (l.1105),
  `model.c4` l.739 and its generated JSON, `infra-credential-tiers-8209.md` (l.160, l.255) and
  `inngest-server.md` (l.133, l.141-142). The rest already say there is NO fallback or describe the
  removed past tense and are kept (`infra-validation.yml` l.1493, ADR-282 l.318,
  `infra-credential-tiers-8209.md` l.138 and l.215, `inngest-luks-cutover-6894.md`,
  `web-host-reboot.md`, `token-drift-workflow-causes.test.sh`). Record the fixed hits in the PR body.

### Phase 4 — register the suite and prove it

4.1 `scripts/test-all.sh`: `run_suite "tests/scripts/hcloud-token-readonly-no-fallback-scan" bash
  tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` with a comment citing #10664 and the
  reason (nothing auto-discovers `tests/scripts/`).
4.2 `scripts/lib/test-affected-paths.sh`: add the label to `ALWAYS_ON_SUITES` with a justifying
  comment in the style of the `tests/scripts/no-tofu-ssh` entry (a repo-wide `git ls-files` walker: the
  verdict is a property of the tree, not of a diff). CTO R8 asks that an edit to the scanner select the
  suite; ALWAYS_ON guarantees it, so add no `AFFECTED_*_PATHS` block unless the census reports the label
  UNCLASSIFIED. Run `bash scripts/lint-orphan-test-suites.sh` and `bash scripts/test-all-affected.test.sh`,
  and prove selection with `bash scripts/test-all.sh --print-selection --paths=<the scanner path>`.
  `.github/workflows/infra-validation.yml` is NOT edited (CTO R8 asked to check its
  `pull_request.paths` list; measured 2026-10-23, it has no `scripts/lint-*.sh` entry, and editing a
  workflow is outside this PR's diff-scope; coverage comes from `ci.yml` running `scripts/test-all.sh`
  on every pull request, where the suite is ALWAYS_ON).
4.3 Shard manifest: a new label is untabled and hash-falls-back by design (`ci.yml` and
  `.github/scripts/test/test-infra-suite-registration.sh`; `trio-baseline-census` has no TSV row
  either). Predict no TSV change and do NOT run `regenerate-shard-manifest.py --write` (it rewrites four
  generated files and conflicts with other PRs); run `plugins/soleur/test/scripts-shard-totality.test.sh`
  and `.github/scripts/test/test-infra-suite-registration.sh` to confirm, and record the verdict.
4.4 Measure the scanner's wall time; the discoverability probe runs it under a 15 s cap, so the target
  is under 5 s (the suite's own time is not on the probe path). Run
  `python3 scripts/lint-shell-trace-credential-refusal.py` on the new scanner: its source contains the
  phrase `doppler secrets get`, a credential signal, so it either carries the repo's xtrace-refusal
  preamble or builds the phrase from parts; do not add an exemption.

### Phase 5 — verification and ship hand-off

Run, in order: the scanner; the new suite; `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`; the
`lead (a1)` and `bk` rows of `tests/scripts/test-argv-bearer-sweep.sh`; the C4 tests;
the AC5 registration checks. CI runs the
full runner; read its result as `N/N suites passed`, not by exit code (learning
`2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`). PR body: `Ref #10664`, the
RED output of 0.1, the fixed sweep hits, a first line stating that merging fires the web-platform apply, release and
infra-validation workflows and that the apply is suppressed by the kill switch, and it ends with the
`🤖 Generated with [Claude Code]` line. The merge uses an explicit squash body carrying the exact own-line
`[skip-web-platform-apply]` (AC8); post-merge confirm `skip=true` on the apply run (AC9).
Commits end with the `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` line. Stage by
explicit path, never `git add -A`.

## Guard Contract

### Guard 1 — hcloud-token-readonly-no-fallback-scan

**Property.** No file in the scanned population reads the read/write Hetzner credential through
`doppler secrets get` (by literal bare name, by a same-line expression naming a Hetzner variable, or by
one hop of variable indirection) except the single tracked, expiring `op=backup` read.

**Assembly.** The guard is the scanner `scripts/lint-hcloud-token-readonly-no-fallback.sh` (CTO R8); the
suite `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` is its battery. The property
quantifies over every `doppler secrets get ...` text in every tracked-or-untracked-unignored text file:
`git -C "$ROOT" ls-files -z --cached --others --exclude-standard`, MINUS a pinned exclusion list (CTO
R9c4): tests (a directory segment in {test, tests, `__tests__`, fixtures}, a `*.test.sh` suffix, a
`test-*` basename), `knowledge-base/`, docs, `*.md`, lockfiles, generated JSON, symlinks,
`.github/workflows/**` (the Tier-B census owns it), and the scanner and suite themselves. Inverting the
selection (everything except the exclusions) is what brings `.claude/hooks`, `*.service`,
`cloud-init*.yml` and `*.tf` `local-exec` reads into scope; Phase 0.1 lists the first live run's
findings. Chokepoints, each asserted by the suite: (1) the population filter, one function; (2) the
read parser (backslash continuations joined; whole-line comments dropped; `doppler` global options
allowed before `secrets`; flags tolerated between `secrets` and `get`; EVERY non-option operand after
`get` is a name, skipping the values of `-p`, `-c`, `--project`, `--config`, `--token`, `--timeout`,
`--config-dir`, `--api-host` and `--scope`; quotes stripped); (3) the allowlist, keyed on (file,
whitespace-normalized line text, exact count) with an expiry. The parser deliberately does NOT
distinguish command position: a bare read inside an `echo` or `printf` string is a printed recipe the
next agent pastes (the class #9927 item 8b removed from the sweep steps), so it is a finding; rephrase
the text or allowlist it. Findings, per operand: F-literal (the name equals the bare `HCLOUD_TOKEN`,
word-bounded, because `HCLOUD_TOKEN` is a prefix of `HCLOUD_TOKEN_READONLY`); F-sameline (a non-literal
name on a logical line that also names a word-bounded `HCLOUD_TOKEN` or `HCLOUD_TOKEN_READONLY`);
F-onehop (the name is `"$v"` or `${v}` and a definition of `v` in the same file contains a
word-bounded bare `HCLOUD_TOKEN`; definition sites are the closed list `v=`, `${v:-`, `local v=`,
`for v in`, `read ... v` (including a here-string), `printf -v v`, `declare -n v` and an array literal
`v=(...)`). Two liveness floors, each printed as exact counters: at least 20 reads inspected, and the
allowlisted line found exactly once; every fixture control asserts its own `inspected`, `skipped_comment`
and `skipped_test` counters, not only a green exit. NOT in the assembly, stated in the scanner header
as named blind spots: a name that arrives from env or argv at runtime; a chain of two or more
assignments; wrapper-function indirection (`_get_secret HCLOUD_TOKEN`; parsing a wrapper body needs
call-graph work that false-positives on `_bearer_curl HCLOUD_TOKEN`, and the runtime backstop is real:
the bare name is absent from `prd_terraform`, so such a read returns empty and fails closed); a name
split across adjacent quoted segments; `doppler run -- printenv`, `--only-secrets`, `secrets download`;
and reads that are not `doppler secrets get` (the loader-delivered `rw) _var=HCLOUD_TOKEN` in
`apps/web-platform/infra/git-data-wipe.sh`).

Seams on the scanner: `HCLOUD_SCAN_ROOT` (the tree; default the repo root), `HCLOUD_SCAN_TODAY`
(strict `YYYY-MM-DD`, a valid calendar date, else FAIL SETUP; default `date -u +%F`; a visible line
whenever it is set), and the event and diff-touch inputs the trio census already defines (mirror its
`--event-name` plus changed-files decision, `test-trio-baseline-census.sh` ~l.213 and ~l.750-775, and
its base-ref resolution ~l.1196; reuse by extraction only if the trio census stays green). The scanner
exits FAIL SETUP (rc 2) when `GITHUB_ACTIONS` is set and either `HCLOUD_SCAN_*` variable is inherited
from the environment (CTO R9c5); the suite runs its fixture rows under `env -u GITHUB_ACTIONS` and runs
the live row with no override. Expiry model (CTO R9b, the trio model): past 2026-12-15 the scanner is RED
only on a `pull_request` event whose diff touches `scripts/cutover-inngest.sh`, the scanner, the suite
or ADR-241; on `push`, `merge_group`, `schedule` and local runs it prints a `::warning::` and exits 0, so
the expiry can never stop an unrelated PR or a tenant deploy through `ci_not_green`; within 21 days
before the expiry it prints the warning everywhere and exits 0. The live line is
`live: findings=0 allowlisted=1`, which the discoverability probe matches.

**Mutation matrix.** Rows derive from this design and run on a SYNTHETIC fixture tree: the smallest
compliant tree (one read-only reader, the allowlisted `op=backup`-shaped line, an unrelated `"$CK"`
read in a file that names only `HCLOUD_TOKEN_READONLY`, an excluded test file holding a bare read, and
enough padding reads for the floor). Instrument controls run first and abort the suite on failure: the
pristine fixture must be GREEN with the exact counters, and a fixture with exactly one bare read must be
RED with one F-literal. Content rows pin `HCLOUD_SCAN_TODAY` to a fixed date well before the expiry so
findings never depend on the wall clock; each mutation asserts the edit landed (md5 change plus an exact
diff-line count). The matrix is table-driven in one loop.

| # | Mutation (edit to the fixture or to the clock) | Must go | Why this row |
|---|---|---|---|
| M1 | A second, identical copy of the allowlisted line appended to the allowlisted file (count 2) | RED, count | a re-added fallback hiding in a file that has a legitimate read |
| M2 | A read-only read FIRST, then a bare `HCLOUD_TOKEN` read in the same function (the exact removed shape) in a NEW file | RED, F-literal | the second member after a compliant first |
| M3 | Multi-operand reads: `get HCLOUD_TOKEN_READONLY HCLOUD_TOKEN --plain`, and the bare name first with a flag between the two names | RED each, F-literal | the one-line fallback; a first-operand-only parser is the class |
| M4 | One-hop definitions, one per site in the closed list: `n=HCLOUD_TOKEN`, `for n in HCLOUD_TOKEN_READONLY HCLOUD_TOKEN`, `read -r n <<< HCLOUD_TOKEN`, `printf -v n HCLOUD_TOKEN`, `names=(HCLOUD_TOKEN)`, each followed by `doppler secrets get "$n"` | RED each, F-onehop | indirection, every spelling the arm claims |
| M5 | `${RO:-$(doppler secrets get ${NAME:-HCLOUD_TOKEN})}` | RED, F-sameline | non-literal name on a line naming the variable |
| M6 | Literal spellings: a `\` continuation before the name, the name after flags, `doppler secrets -p soleur -c prd_terraform get HCLOUD_TOKEN`, and a quoted name (`"HCLOUD_TOKEN"`, `'HCLOUD_TOKEN'`) | RED each, F-literal | parser variants; the quote is the natural one-keystroke repair of a refusal |
| M7 | A bare read inside an `echo "..."` string | RED, F-literal | printed recipes are findings by design |
| M8 | The allowlisted line's text edited (a flag added); and the allowlisted line deleted (stale entry) | RED each | allowlist keyed on text, and a stale entry cannot linger |
| M9 | The scanned directories renamed in the fixture (empty population) | RED, floor | the guard's own dispatch: zero inspected must not exit 0 |
| M10 | `HCLOUD_SCAN_ROOT` is not a git work tree, and a population path is replaced by a directory or a dangling symlink | FAIL SETUP (rc 2), never "no findings" | a scanner that cannot enumerate or read must not exit 0; root-independent (no `chmod`) |
| M11 | `GITHUB_ACTIONS=true` with an inherited `HCLOUD_SCAN_TODAY=2000-01-01`, and with an inherited `HCLOUD_SCAN_ROOT` | FAIL SETUP (rc 2) | the clock and root seams cannot be set from a workflow's environment |
| L1 | The scanner against the REAL tree, run by the suite with no override | GREEN: exactly one allowlisted read, zero findings | the contract on the real population; without this row nothing guards the live tree (CTO R8) |
| L2 | A copy of the live population (all selected files, via `HCLOUD_SCAN_ROOT` on a `git init` copy) with the pre-change fallback line re-inserted into `scripts/cutover-inngest.sh` | RED, F-literal named explicitly | the real shape and the real floors, not a fixture shape |
| C1 | `"$CK"` in a file naming only `HCLOUD_TOKEN_READONLY`; the pristine fixture's read-only reader; `HCLOUD_TOKEN_RW`, `HCLOUD_TOKENS` and `X_HCLOUD_TOKEN` as operands | GREEN (must-PASS, counters asserted: the read is `inspected`) | F-sameline and F-onehop must not over-fire; the word boundary |
| C2 | A bare read inside a whole-line comment; a bare read in an excluded test file | GREEN (must-PASS, `skipped_comment` and `skipped_test` asserted, not unseen) | comments and tests are permitted differences |
| C3 | Clock and event rows: today = expiry-22 silent; expiry-21 `::warning::` rc 0; expiry day green; expiry+1 on `pull_request` touching `scripts/cutover-inngest.sh` RED; expiry+1 on `pull_request` touching none of the guarded files, on `push`, on `merge_group` and locally = `::warning::` rc 0; malformed override FAIL SETUP | per row | the 21-day window, the inclusive expiry, the event dimension and the seam; the expiry is its own named row, never reported as "fallback found" |

Harness rows: the instrument controls and rows C1 to C3 and L1 are must-PASS or must-RED inputs that
are not the canonical fixture; there is no edit-the-suite-itself row, because a circular "neuter the
parser, expect the control to notice" row proves the control, not the parser. Reorder row: not
applicable (the property has no order or lifetime component).

**Anchor.** The allowlist (inside the scanner) and the read it permits can be edited in one diff, so
the guard proves consistency, not integrity. What moves OUTSIDE the commit is the clock: after
2026-12-15 the entry cannot be carried silently (RED on a pull request that touches the guarded files,
a warning everywhere else, and a 21-day warning window before), so the exception is re-decided on a
date rather than forgotten. The reviewer-visible anchor is the ADR-241 2026-10-23 entry, which names
the entry, its expiry and its trackers (#9755, #10664); renewal is a dated edit with a stated reason,
deletion is the intended end. The scanner header names the owner and trackers in one line and points
at that entry. The guard does not claim a read/write token stored under the read-only name is
detectable; that control stays the O5 write-probe (last recorded 2026-09-29, not re-run, and excluded
here by the no-live-probe rule).

## Observability

```yaml
liveness_signal:
  what: the scanner's line "live: findings=0 allowlisted=1", run by the suite's real-tree row L1 in every per-PR test-all run
  cadence: per pull request and per push to main (always-on suite; also infra-validation deploy-script-tests when scripts/cutover-inngest.sh changes)
  alert_target: a red required check on the PR; a warning annotation on push after the allowlist expiry
  configured_in: scripts/test-all.sh (run_suite line) and scripts/lib/test-affected-paths.sh (ALWAYS_ON_SUITES)
error_reporting:
  destination: GitHub Actions run annotations on the cutover-inngest.yml dispatch (the public run log), not Sentry; the script runs on a runner, not in the web app
  fail_loud: "::warning::G3 generation anchor: doppler returned nothing for HCLOUD_TOKEN_READONLY ..." followed by the op's ::error:: refusal, and the SOLEUR_CREDENTIAL_REFUSED marker for an unusable shape
failure_modes:
  - mode: HCLOUD_TOKEN_READONLY absent or empty in prd_terraform
    detection: the anchor returns __UNREADABLE__; the warning names the variable; the op refuses at G3 (run goes red)
    alert_route: the dispatching owner sees the red run; no pager (dispatch-only op, nothing runs unattended)
  - mode: read-only token rejected by Hetzner (HTTP 401/403)
    detection: "the Hetzner API REJECTED the token (HTTP 401) - the one sent was HCLOUD_TOKEN_READONLY"
    alert_route: same red run
  - mode: a new bare read/write read or a re-added fallback in a scanned file
    detection: the scanner fails the PR check with file, line and finding class
    alert_route: required check on the PR
logs:
  where: GitHub Actions run logs for the cutover-inngest.yml dispatch and for the test-all job
  retention: the repository's Actions log-retention setting
discoverability_test:
  command: bash scripts/lint-hcloud-token-readonly-no-fallback.sh
  expected_output: findings=0
```

## Architecture Decision (ADR/C4)

No new architectural decision: the change enforces ADR-241 D4's recorded end state at the last site that
had not reached it, and adds a regression guard for it. Per Phase 2.10 the record still must not lag.

### ADR

Amend ADR-241 (a new dated 2026-10-23 entry, D4 body untouched, no status change) and ADR-225 (item 4
kept, a Superseded pointer and a dated `#### Amendment — 2026-10-23` block appended, CTO R9d). No new ADR, so no ordinal to claim. Both edits are Phase 3
tasks of this PR.

### C4 views

Read all three model files: `model.c4`, `views.c4`, `spec.c4`. Checked against the change: external
human actors (none added: dispatch is by the existing owner actor); external systems (the Hetzner Cloud
API and Doppler, both already modeled by the `github -> hetzner` and `github -> doppler` edges at
l.733-739); containers and data stores (none touched); actor-to-surface access relationships
(unchanged). The only falsified content is the `github -> hetzner` edge description clause "both read
HCLOUD_TOKEN_READONLY first and fall back to HCLOUD_TOKEN (ADR-241 D4) until it is minted"; it is edited
(Phase 3) and `model.likec4.json` is regenerated by the hook. No element, tag or `view ... include` line
is added. The derived cardinalities embedded in edge prose are unchanged; `c4-count-parity.test.sh` is
run to prove it.

### Sequencing

The ADR text describes the present state (the fallback removed and the scan merged in the same PR);
nothing is `adopting`.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Consulted on 2026-10-23 (rulings R1-R9 in `decision-challenges.md`): a scanner plus a standalone suite,
not a census row; per-site detection with a keyed, expiring allowlist; two narrow non-literal arms; ADR
append-only convention (ADR-225 included); the credential-tiers runbook and the C4 edge text in scope;
the trio expiry model (RED only on a pull request touching the guarded files, a warning elsewhere) with
a 21-day warning; the kill-switch handling of the apply trigger. Risk carried: the scan arms' "zero
extra findings" claim is re-verified on the real tree before commit (Phase 0.1); the expiry is bounded
by the event model and named owner and trackers; the apply trigger is an operator item.

No Product/UX, Legal, Finance, Marketing, Sales, Operations or Support implication: no UI surface, no
user data, no regulated-data surface (the GDPR gate is not triggered: no schema, migration, auth flow
or API route, and no new LLM or external-API processing), no new infrastructure (no `.tf`, workflow or
cloud-init), no persistent store or new network connection (the Encryption Posture gate skips).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`scripts/cutover-inngest.sh` (~lines 547-562): remove the read-only-then-read/write token fallback; read via the read-only token only" [brief] | Phase 1; Files to Edit entry 1 | mapped |
| 2 | "Fix the stale \"Measured 2026-09-24\" comment (~line 551)." [brief] | Phase 1.1 (l.547-561 comment; l.477 deliberately kept, it is a true measurement) | mapped |
| 3 | "Stale-comment fixes in `knowledge-base/engineering/operations/runbooks/inngest-server.md` (~line 142), ADR-225 (~line 114) and ADR-241 (~line 1105, \"Left open\")." [brief] | Phase 3; Files to Edit entries 4-6 | mapped |
| 4 | "Add a census row or a `scripts/` scan test so the next read-only-then-read/write fallback is caught." [brief] | Phase 0 and Phase 4; Guard 1; Files to Create entry 1 | mapped |
| 5 | "EXCLUDE `inngest-server-flip-guard.sh`" [brief] | Files to Edit "Explicitly NOT touched"; AC6 | mapped |
| 6 | "Do not touch infra files that trigger the registry-host-replace dispatcher or any apply workflow." [brief] | AC6 diff-scope; Research Reconciliation row on dispatchers | mapped |
| 7 | "No production-mutating acts; no Hetzner/Doppler/Supabase writes; no live credentialed probes." [brief] | Observability (no probe runs a credential); Phase 0.1 and Phase 4 (hermetic fixtures); Risks | mapped |
| 8 | "Ref #10664, do NOT use Closes since the tracker has other open items" [brief] | AC7; Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit 1: `scripts/cutover-inngest.sh` (comment, body) | asks 1-2 | asked |
| Files to Edit 4-6: runbook, ADR-225, ADR-241 | ask 3 | asked |
| Files to Create 1-2 and Files to Edit 9-10: the scanner, the suite and its registration | ask 4 | asked |
| Rewrite of the assertions in `cutover-inngest-workflow.test.sh` and `test-argv-bearer-sweep.sh` | — | inferred — justification: removing the code reds these four assertions of the removed behaviour; leaving them red ships a broken suite |
| `infra-credential-tiers-8209.md` (two "still true" passages and one sentence) | — | inferred — justification: CTO R3 ruled it in scope; both passages state the removed fallback as current, a known-false statement in the same PR |
| `model.c4` clause and the regenerated `model.likec4.json` | — | inferred — justification: CTO R7 ruled it in scope; a present-tense design statement that becomes false |
| Shard-manifest rows (contingent) | — | inferred — justification: a registered suite must satisfy the shard-totality check or CI goes red |
| The 21-day warning window, `HCLOUD_SCAN_TODAY` seam and the expiring allowlist | ask 4 | asked — the exception for `op=backup` (ruled R2/R6) cannot be carried silently without an expiry |

### Split Assessment

- Subsystems touched: 4 — `scripts`, `apps/web-platform`, `tests`, `knowledge-base`
- Planned files: 13 | Estimated changed lines: 600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root count reaches the threshold but the roots are one property (the script, the tests that pin it, the docs that describe it, and the guard that keeps it); a split would leave the removal unguarded or the docs false for a PR cycle. Nothing is deferred without a tracker (#10664 items, #9755).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `bash scripts/lint-hcloud-token-readonly-no-fallback.sh` exits 0 and prints
  `live: findings=0 allowlisted=1`; `bash tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh`
  exits 0 (its matrix rows, including L2, RED with F-literal on the pre-change shape); and
  `git grep -nE 'doppler secrets get HCLOUD_TOKEN([[:space:]]|"|'"'"'|$)' -- scripts/cutover-inngest.sh`
  prints exactly one line, the `op=backup` read.
- [ ] AC2. Stale text gone from the script, with checks that can fail:
  `grep -c 'prd_terraform holds only' scripts/cutover-inngest.sh` prints `0`;
  `grep -cE '(^|[^_])tokvar' scripts/cutover-inngest.sh` prints `0` (the unrelated `_tokvar` helper at
  l.75-78 is not matched); the function body
  `awk '/^_inngest_server_created_epoch\(\) \{$/,/^\}$/' scripts/cutover-inngest.sh | grep -cE 'HCLOUD_TOKEN([^_A-Z]|$)'`
  prints `0` (it prints 5 before the change); and
  `grep -c 'GENERATION. Measured 2026-09-24' scripts/cutover-inngest.sh` prints `1` (the true l.477
  sentence survives).
- [ ] AC3. `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` and the `lead (a1)` and `bk`
  rows of `tests/scripts/test-argv-bearer-sweep.sh` are green; no assertion text still names "using the
  read/write HCLOUD_TOKEN" or "the one sent was HCLOUD_TOKEN;"; and the `rw` block goes RED when the SUT's
  bare read is respelled with reordered flags (bait keyed on the name, not the argv).
- [ ] AC4. The Phase 3 sweep command, re-run on the final tree, returns only hits classified historical
  in the PR body; `git grep -n 'until it is minted' -- knowledge-base/engineering/architecture/diagrams/`
  returns nothing (this covers the generated `model.likec4.json` too; CTO R7); and
  `bash plugins/soleur/test/c4-model-freshness.test.sh` and
  `bash plugins/soleur/test/c4-count-parity.test.sh` are green.
- [ ] AC5. Registration: `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/test-all-affected.test.sh`,
  `bash plugins/soleur/test/scripts-shard-totality.test.sh`,
  `bash .github/scripts/test/test-infra-suite-registration.sh` and
  `python3 scripts/lint-trap-tempfile-ownership.py` are green; `bash scripts/test-all.sh --print-selection`
  lists the new label, and still lists it when the diff holds only the scanner path; no shard TSV rows
  are added for an untabled label.
- [ ] AC6. Diff-scope: `git diff --name-only origin/main...HEAD` is a subset of the Files to Edit and
  Files to Create lists plus the pipeline-written files named above; it contains NO `*.tf`,
  `cloud-init*`, `.github/workflows/*`, `.github/actions/*`,
  `apps/web-platform/infra/inngest-server-flip-guard.sh` or migration path, and its only path under
  `apps/web-platform/infra/` is `cutover-inngest-workflow.test.sh` (the conflict with the brief is
  recorded as an operator item, see Risks).
- [ ] AC7. The PR body says `Ref #10664` (no `Closes`), says in its first line that merging fires the
  web-platform apply, release and infra-validation workflows and that the apply is suppressed by the
  kill switch, lists the flip-guard retention comment and `op=backup` as still open, and ends with
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- [ ] AC8. The squash merge is issued with an explicit body that carries the line
  `[skip-web-platform-apply]` alone on its own line (the apply workflow's preflight regex requires an
  exact own-line match); done by the shipping agent in the merge command.

### Post-merge

- [ ] AC9. The shipping agent reads the `apply-web-platform-infra.yml` run for the merge commit and
  confirms its preflight output is `skip=true` (a names-only run read, no secrets). Do not rely on "a
  test-file edit plans to a no-op" (known state drift, ADR-241 M9). It also reads the
  `web-platform-release.yml` run for the merge commit and records that it was an unchanged-code
  rebuild with no Tier-B or version-bump side effect beyond the normal release. It also confirms, by a
  names-only listing (`doppler secrets --only-names -p soleur -c prd_terraform`), that
  `HCLOUD_TOKEN_READONLY` is present, since the anchor now has no fallback (review 2026-10-23).
- [ ] AC10. Tracker #10664: the Site C checkbox text is split so the flip-guard retention-comment
  sub-item stays unticked; done by the shipping agent with `gh issue edit` (no owner step).

## Test Scenarios

1. Read-only token present: one read, request sent, epoch printed (unchanged behaviour; existing rows).
2. Read-only token absent, read/write present (bait): `__UNREADABLE__`, zero requests, the read/write
   token never read and never printed (absent from stdout, stderr, curl argv, curl stdin and call
   log).
3. Read-only token of every hostile shape: marker plus shape warning, zero requests (existing rows,
   updated warning text).
4. Hetzner 401: the warning names `HCLOUD_TOKEN_READONLY`.
5. Scan: the Guard 1 matrix, including the instrument controls, the live-tree and population-copy
   rows, and the clock and event rows.
6. Scan liveness: an emptied population is RED, not vacuously green.

## Risks and Sharp Edges

- **Constraint conflict with the brief (operator item).** The brief says not to touch infra files that
  trigger an apply workflow, and also asks to remove the fallback. The fallback is asserted by
  `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, so leaving it unedited turns
  `infra-validation` red, and a `git mv` out of the directory still touches the path. A push to main
  that touches `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml` (environment
  `infra-privileged`, no reviewers), `web-platform-release.yml` (`apps/web-platform/**`, the test file is
  not excluded; it cuts a release and rolls out an unchanged-code image) and `infra-validation.yml`;
  ADR-280:99 records the same trap. `registry-host-replace-dispatch.yml` is NOT triggered (its paths are
  `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf` and itself) and neither is
  `cutover-inngest.yml` (its push trigger lists only its own file). Mitigation (CTO R9a): the kill switch
  in AC8 and the read in AC9; sibling precedent is #10652, which edited this same suite. If the owner
  rejects the conflict, the fallback removal cannot ship, because the suite pins the old behaviour.
- **Time bomb by design, bounded.** From 2026-11-24 the scanner prints a `::warning::`, and after 2026-12-15
  an `expired` warning, until the `op=backup` allowlist entry is deleted or renewed with a new dated ADR-241
  entry; the date never turns the scan red (warning-only, CTO R10, which replaced the R9b trio model). Owner: the #9755 work; trackers: #9755 and
  #10664, named in the scanner header and the ADR-241 entry. The 21-day warning starts 2026-11-24.
- **Line-keyed text.** The allowlist keys on normalized line text, so reformatting l.1900 reddens the
  scanner on purpose; the failure message prints the expected and the found text.
- **Line numbers drift.** The edit instructions cite line numbers as of 2026-10-23 and content anchors
  (assert strings, quoted clauses); the anchors are authoritative. Other draft PRs also edit
  `cutover-inngest-workflow.test.sh` (ADR-280:179-180 names one); the PR body names which side
  rebases.
- **Prefix trap.** `HCLOUD_TOKEN` is a prefix of `HCLOUD_TOKEN_READONLY`; every pattern is
  word-bounded and rows C1 pin it.
- **First-definition harness.** The workflow suite evals the FIRST multi-line definition of
  `_inngest_server_created_epoch`; its existing "defined exactly once" assertion stays.
- **Do not widen to workflows.** Workflow reads belong to the Tier-B census (G1g and G1j).
- **Registration precedent.** `trio-baseline-census` and `infra-privileged-tier-census` use declared
  edge arrays (`AFFECTED_*_PATHS`), not ALWAYS_ON. The right precedent for a repo-wide
  `git ls-files` walker is `tests/scripts/no-tofu-ssh` (ALWAYS_ON with a justifying comment); copy that
  comment style. The new label is selected by `scripts/test-all.sh` at the line
  `if _affected_in_list "$_label" ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"}; then`, and the entry
  goes in the same diff as the `run_suite` line (a registration-only runner diff is admitted only
  together with its own ALWAYS_ON entry, ADR-242 decision 20). The trio census edited
  `scripts/test-affected-kb-consumers.baseline.txt` only because it names knowledge-base paths; this
  suite does not.
- **ADR-241 diff tokens.** The trio census parses added ADR-241 lines of the form `Allow:`, `Re-date:`
  and `Reclass:` followed by "Ruled by" as rulings (`test-trio-baseline-census.sh` ~l.792-796). The new
  ADR-241 entry names an expiry and a CTO ruling, so it avoids those exact tokens.
- **Fixture environment and trap order.** The fixtures run `git init` under one `mktemp -d` and must
  pass a constructed environment (unset every `GIT_*` location variable; pin identity and config) per
  the plugin's Test Fixture Conventions, or a linked-worktree `GIT_DIR` redirects the fixture into the
  live repository. If the suite sources `test-helpers.sh`, its single EXIT trap is installed BEFORE the
  source (lint-trap-tempfile-ownership rule (c)).
- **Natural repairs of the refusal.** The one-line repair a stuck agent will type when the anchor
  refuses is to store the read/write token under the read-only name; that residual is undetectable here
  (stated in the ADR entry). The natural repair of a RED scan is to allowlist the line; that needs a
  tracker, an expiry and a reviewer-visible ADR line (Anchor above).
- **A plan whose `## User-Brand Impact` section is empty, holds placeholder text or omits the
  threshold fails `deepen-plan` Phase 4.6** (filled above).
- **Preview is not proof.** The planner's read-only preview (784 files, no finding from either
  non-literal arm) used the narrower pre-deepen population; Phase 0.1 re-runs the real scanner on the
  inverted population and lists its first findings.
