---
title: "fix(infra): convert the 6 deferred pipe-fed grep -q readers in web-private-nic-guard.sh and cron-egress-enforce-probe.sh (merge-queue series, pass 2)"
type: fix
date: 2026-10-07
slug: grep-q-pass2-nic-guard-egress-probe
branch: feat-one-shot-grep-q-pass2-nic-guard-egress-probe
issue: 9217
closes: none
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix(infra): grep -q pass 2 for the NIC guard and the egress-enforce probe

Spec lacks a valid `lane:` (no spec.md exists for this branch), so it defaults to `cross-domain` (fail-closed).
The PR body uses `Ref #9217`, `Ref #7005`, `Ref #6601`, `Ref #7376`, `Ref #7797`, `Ref #9482`, `Ref #9638` and
`Ref #9639`; never `Closes` (each is a standing tracker that stays open after this pass). The planning pipeline
skipped the Phase 0.7 skeleton checkpoint: the research here was a handful of local reads, not the agent fan-out the
checkpoint protects, and the whole plan was written in one pass.

## Overview

Pass 1 (PR #9632, merge `a0359450dd`, verified an ancestor of `origin/main`) credential-hardened both scripts and
took them out of the three lint baselines, which is the precondition for editing them. This pass is the conversion
the series always intended: the last two production rows of `SWEEP_DEFERRALS` in
`.claude/hooks/grep-q-pipe-guard.test.sh` (`:463` `cron-egress-enforce-probe.sh | = | 2` and `:464`
`web-private-nic-guard.sh | = | 4`) are converted to the `grep -c ... >/dev/null` form and the two rows are deleted.
That takes `apps/web-platform/infra/` to zero deferred early-exit pipes except the four file-exact host-replace rows
and the two security-pinned rows that stay (see Not Fixed).

The six sites (measured: `PATTERN_V2` from the guard run over the two files returns 6 on `origin/main`, 0 on the
prototype below):

| # | File:line | Today | After |
|---|---|---|---|
| 1 | `web-private-nic-guard.sh:55` | `... addr show 2>/dev/null \| grep -qwF -- "$EXPECTED_IP"; then` | `... \| grep -cwF -- "$EXPECTED_IP" >/dev/null; then` |
| 2 | `web-private-nic-guard.sh:61` | same, inside the 30x bounded wait | same change |
| 3 | `web-private-nic-guard.sh:78` | `printf '%s\n' "$IMDS_BODY" \| grep -qE "...ip:...$EXPECTED_IP..." && IMDS_HAS_EXPECTED=true` | `\| grep -cE "..." >/dev/null && IMDS_HAS_EXPECTED=true` |
| 4 | `web-private-nic-guard.sh:80` | `printf '%s' "$IMDS_NETS" \| grep -qE '^[0-9]+$' \|\| IMDS_NETS=0` | `\| grep -cE '^[0-9]+$' >/dev/null \|\| IMDS_NETS=0` |
| 5 | `cron-egress-enforce-probe.sh:86` | `until docker ps --format '{{.Names}}' \| grep -qx "$CONTAINER"; do` | `\| grep -cx "$CONTAINER" >/dev/null; do` |
| 6 | `cron-egress-enforce-probe.sh:100` | `if ! nft list chain ip filter DOCKER-USER 2>/dev/null \| grep -q 'jump SOLEUR-EGRESS'; then` | `\| grep -c 'jump SOLEUR-EGRESS' >/dev/null; then` |

Why `-c ... >/dev/null` and not the `< <(producer)` or here-string forms the guard header also allows: it is the form
Wave A2 (PR #9587, `d58f804f78`) chose for the whole web-host boot family, including the sibling
`cron-egress-postapply-assert.sh`, which already carries the identical producer
(`docker ps --format '{{.Names}}' | grep -cx soleur-web-platform >/dev/null`, `:111` and `:122`). `soleur-host-bootstrap.sh`,
`cron-egress-postapply-assert.sh` and `cloud-init.yml` contain zero process substitutions (`grep -c '< <('` returns 0 for each),
so `-c` adds no new shell feature or `/dev/fd` dependency on a fresh-host boot path, keeps the producer first (smallest
diff), reads the whole stream so the producer can never take EPIPE, and preserves exit status exactly. Verified
equivalence, measured on bash and dash (GNU grep 3.12) over 8 inputs (empty, no trailing newline, match on line 2,
near-miss name, numeric and mixed) and both patterns used here: zero status differences between `grep -q` and
`grep -c ... >/dev/null`.

**Honest scope of the benefit.** Neither script sets `pipefail` (`grep -n pipefail` over both returns nothing; the
probe is `set -e`, the guard `set -u`). Without `pipefail` a pipeline's status is the last stage's, so none of the six
sites misreads a present line as absent today. The deferral rows track a TEXT shape, and the conversion pays that
debt to zero and makes the files immune if a later edit adds `set -o pipefail`. It does not fix a live flake and the
PR body and tracker comment say so.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (command or file) | Plan response |
|---|---|---|
| "Class W deploy files auto-apply on merge" | For these two files the apply is `apply-web-platform-infra.yml` (`on.push.paths: apps/web-platform/infra/**`, `:19-20`), through `terraform_data.private_nic_guard_install` (`-target` at `:1192`, `triggers_replace` hashes the guard, `server.tf:896-908`). The probe has no running-host delivery path. Neither file is in `apply-deploy-pipeline-fix.yml` (`grep -n 'cron-egress\|nic-guard'` over it returns nothing) | Apply path restated below; `[skip-deploy-fix-apply]` is irrelevant and never used |
| The 6 hits are pipe-fed misreads | No `pipefail` in either file (see Overview) | State plainly; this is table-to-zero, not a flake fix |
| "`lint-shell-trace-credential-refusal.py --changed` is advisory, in lint-bot-statuses" | Confirmed: job `lint-bot-statuses:` at `.github/workflows/ci.yml:160`, step at `:231` | Ran it on the prototype and on the two files as they stand: `OK: 2 scanned file(s), 0 baselined (A/B/C), 0 baselined (D), 0 baselined (Rule E: 0 site(s))` |
| Converting the file means its suite and every source-text pin over it stay green; "grep the OLD line text across every `*.test.*`" | Done with fixed-string greps of all six old texts over the whole tree (excluding `knowledge-base/`). The only other file carrying the old texts is `apps/web-platform/infra/cloud-init-registry.yml:2138,2145,2230,2232` (the REGISTRY twin of the NIC guard). Its suite `private-nic-guard.test.sh:499` pins `grep -cE 'grep -qwF -- "\$EXPECTED_IP"' "$RENDERED"` equal to 2, but `$RENDERED` is rendered from `cloud-init-registry.yml` (`:37`, `:67`), not from the web guard. No `*.test.*` pins any of the six web-guard or probe lines by text | The registry twin is left alone (its 13-hit row stays, host-replace class); no pin to move. The web guard header's "one family" sentence is left alone (plan review judged a qualifier ceremony); one comment per script explains the idiom |
| Open draft PR #9529 also edits `cron-egress-enforce-probe.sh` | `gh pr diff 9529`: its hunks add an xtrace refusal block after `set -e` (header, ~line 26) and a new section 4 after the negative probe (~line 129-200). It is `mergeStateStatus: DIRTY` today and its xtrace hunk re-adds a refusal that pass 1 already landed with different text, so it conflicts with `main` independently of this PR. Its new gateway check already uses `grep -qx "$GW_CONTAINER" < <(docker ps ...)` | This PR changes exactly two single lines in that file (`:86`, `:100`), more than 40 lines from either #9529 hunk, so no textual overlap. #9529's rebase will need to pick a form for its own new line; mention on the tracker |
| #9639 and #9638 triage | #9639 (F5 root sources a deploy-owned file, F6 unit expands the secret before the refusal, F7 no boot-trail event, F8 no standing alert) and #9638 (harden the Sentry DSN curl in lockstep across three files, teach Rule D) | None fits this pass: F5 edits `emit_fail` (the Sentry path the parity pin freezes) in the file #9529 also edits; F6 edits a unit file and its own suite; F7 edits `cloud-init.yml`; F8 adds a Terraform alert; #9638 edits three files including `workspaces-luks-emit.sh` under security review. All stay tracked and are named in the NOT-fixed list |

## Research Insights

**Premise Validation.** Cited trackers #9217, #7005, #6601, #7376, #7797, #9482, #9638 and #9639 are all OPEN
(`gh issue view`). Pass 1 merge `a0359450dd` is an ancestor of `origin/main` (`git merge-base --is-ancestor`). PR #9529
is OPEN, draft, DIRTY. The two `SWEEP_DEFERRALS` rows exist at `:463-464` with ceilings 2 and 4; the guard run prints
`DEFERRED: ... (2 hits, ceiling 2, mode =, slack 0, #9217)` and `(4 hits, ceiling 4 ...)`. Nothing in the brief is
already resolved. One premise was imprecise (Class W scope, above).

**ADR corpus check.** No ADR lists this mechanism among rejected alternatives. `grep -l 'grep -q\|SIGPIPE'` over the
ADR directory hits ADR-115, 119, 202, 068, 179 and 184; the only grep-q-adjacent line (`ADR-115:418`) is about fstab
handling in the registry boot path, unrelated. ADR-193 (anti-vacuity floors) governs the two `MIN_CASES` literals this
plan raises. ADR-100 and ADR-169 (host-replace classes) are why the other four production rows stay.

**Property List.**

1. P1 — none of the six sites can read a present line as absent, whatever shell options a later edit adds.
2. P2 — each converted predicate returns the same verdict as before for match, near-miss, empty and
   non-canonical-order input (exit-status equivalence, plus behavioral rows on the two real scripts).
3. P3 — the two files cannot regrow a pipe-fed early-exit grep unnoticed, because they are no longer inside any
   deferral row and the derived sweep covers them.
4. P4 — the deferral ledger shrinks by exactly these two rows and nothing else moves.

**Cut List** (mechanism proposed or implied, what covers it):

- Re-hardening the Sentry DSN curl — CUT (#9638; the `TRANSPORT` parity block in `cron-egress-enforce-probe.test.sh`
  pins those lines byte-identical to `soleur-host-bootstrap.sh`; this PR does not touch them).
- A new suite file or a new anti-vacuity floor — CUT. Both suites exist and are already in the LIVE
  `PROMOTED_FILES` (the fourth assignment, `scripts/guard-vacuity-floor.test.sh:801`, ends with
  `web-private-nic-guard.test.sh|cron-egress-enforce-probe.test.sh`); only the existing `MIN_CASES` literals move.
- In-suite mutation runner — CUT. The mutation matrix is executed once by hand on scratch copies and recorded in the
  PR body (pass 1 precedent).
- Converting the registry twin in `cloud-init-registry.yml` — CUT (host-replace class, existing row).
- A source-text pin on the new `-c` spelling — CUT. The behavioral near-miss rows below observe the discrimination;
  a text pin would only prove spelling.

**Carrier census** (what reads or pins these files; fixed-string greps of every old and new line text over the whole
tree excluding `knowledge-base/`):

| Consumer | Pin or dependency | Effect |
|---|---|---|
| `server.tf:173-310` `host_script_files` -> `host_scripts_content_hash` (`:311`) -> `user_data` | 64-byte hash only; `hcloud_server.web` has `ignore_changes = [user_data, ...]` (`server.tf:597`) | user_data text changes, no replace, no size change |
| `server.tf:891-951` `private_nic_guard_install` (guard only) | `triggers_replace` includes `file(web-private-nic-guard.sh)` | resource replaces; provisioner re-runs on web-1 only |
| `Dockerfile` / `.dockerignore` (both scripts) | COPY into the image | new image via `web-platform-release.yml`; fresh hosts get the new bytes only through it |
| `soleur-host-bootstrap.sh` | install + 0755 assert loops; Sentry transport parity | transport lines untouched |
| `cloud-init.yml:644,807` | timer enable; probe invocation, `poweroff -f` on non-zero exit | unchanged text; a wrong probe verdict would power a fresh host off (see Blast Radius) |
| `cron-egress-enforce-probe.test.sh` | `'^set -e'`, curl-form regexes, Sentry TRANSPORT parity, sibling-host parity, delivery lockstep, xtrace and drawdown rows | none reads lines 86 or 100; healthy run (P-X1c) exercises both converted sites |
| `web-private-nic-guard.test.sh` | runs the real file against PATH stubs | exercises sites 1-4 on the happy path only today (gap closed by Phase 0) |
| `private-nic-guard.test.sh:499-513` | pins the REGISTRY twin text | unaffected (different file); must stay green |
| `betterstack-send-failed-alert-mutation.test.sh` M18 (`:364-365`) | mutates the guard's `--data-raw` payload | payload text untouched |
| `fresh-boot-parity.test.sh:109-113`, `doppler-injection-bound.test.sh:232`, `arm-heartbeats*.test.sh`, `plugins/soleur/lib/heartbeat-manifest.ts` | name-level references | unaffected; run |
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | user_data byte budget | script bytes are image-baked, not in user_data; run as a check |
| `scripts/lib/test-affected-paths.sh:1444-1455` | `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` | the hook suite is edited by this PR, so it is selected regardless |

**Touched-file lints that fire on these paths** (checked before editing, per the lesson):

| Lint | Verdict |
|---|---|
| `lint-shell-trace-credential-refusal.py --changed --base origin/main` (advisory, `ci.yml:231`) and the repo-wide required run | clean on prototype; no credential, curl or xtrace line is edited; Rule E untouched (bearer already on `--config -`, `web-private-nic-guard.sh:130`) |
| `lint-shell-capture-exit.py` | `0 new findings` on the prototype |
| `lint-trap-tempfile-ownership.py` | no `mktemp` added to any script; the suites already own their traps |
| `grep-q-pipe-guard.test.sh` (inside the required test shard) | the `apps/web-platform/*.test.sh` row sits at `180 hits, ceiling 180, slack 0`, so every NEW test line must avoid a pipe-fed early-exit grep (here-strings or `grep -c ... >/dev/null` only) |
| `lint-infra-no-human-steps.py --changed` | applies to this plan, tasks and learnings only; run on each before commit |
| `lint-guard-contract.py` | run on this plan |
| `guard-vacuity-floor.test.sh` | run before the first commit (floors raised in two suites already in `PROMOTED_FILES`) |

**Learnings applied** (paths under `knowledge-base/project/learnings/`): the Wave A2 form decision
(`test-failures/2026-10-06-a-source-text-pin-over-a-file-is-a-pipe-into-grep-q-so-the-suite-that-pins-its-own-subject-is-in-the-class.md`),
the vacuity meta-guard contract
(`test-failures/2026-10-06-a-new-anti-vacuity-floor-joins-the-meta-guard-and-a-fix-pass-must-be-audited-in-every-run.md`),
the carrier-census method
(`test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`)
and the per-workflow `paths:` fact
(`test-failures/2026-10-06-a-lints-required-ness-belongs-to-its-job-and-auto-apply-on-merge-is-a-per-workflow-paths-fact.md`).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 rows) was searched with `jq --arg path` for each of
`web-private-nic-guard.sh`, `cron-egress-enforce-probe.sh`, both `.test.sh` files and
`.claude/hooks/grep-q-pipe-guard.test.sh`; no body names any of them.

## Not Fixed (stated in the PR body and the tracker comment)

- The Sentry-DSN curl family is untouched: #9638.
- #9639 items F5-F8 (root sources a deploy-owned file; unit wrapper expands the secret before the refusal; no boot-trail
  event; no standing alert; heartbeat URL on argv) are untouched.
- The remaining production rows of `SWEEP_DEFERRALS` are untouched (host-replace class per ADR-100 and ADR-169, one
  sha256-pinned forensic print, one digest-pinned image). The REGISTRY NIC guard inside `cloud-init-registry.yml` keeps the
  same four shapes. The test-shaped `<=` rows are untouched.
- Later items of the series (Wave B, live-verify rail, `lint-bot-statuses`, guard blind spots, `--ratchets`, `JOBS=1`,
  Wave A3 carriers) are not started; they are separate PRs.
- The running web-2 never receives the NIC guard through `private_nic_guard_install` (targets `web["web-1"]` only,
  `server.tf:910`); this is pre-existing.
- Local `scripts/test-all.sh --affected` is expected to be skipped on this contended host (load average 18-21 at
  planning time); the PR body states it verbatim and CI is the gate.
- Site 4 (`web-private-nic-guard.sh:80`) is converted but no stub can drive it RED (see Phase 0); the PR body labels it an
  equivalent mutant covered only by the exit-status table.

Tracker comment must also state the series' terminal state (CTO review): the rows that cannot convert without a
host-replace window stay until a host-replace is already scheduled for them, and the sweep deliberately keeps counting a
text shape; teaching it to ignore files with no `pipefail` was considered and left out because it loses the
immunity-to-a-later-`pipefail` property. And note the sequencing with draft #9529: both PRs touch the probe suite's
exact `MIN_CASES` literal, so whichever lands second rebases that one line.

## Implementation Phases

### Phase 0 — characterization rows (behavior-preserving refactor: green before AND after)

A conversion that preserves behavior cannot be driven RED by its own tests; `cq-write-failing-tests-before` is
satisfied differently here. The new rows are written first against the UNCONVERTED scripts, must be GREEN there (they
assert current behavior, not the conversion), and are then shown to bite by hand-applied mutants (Guard 2). They are
needed because the suites exercise the six sites only on the happy path (healthy probe run P-X1c; NIC-guard T1/T2 with a
canonical address and IMDS body), so an always-true, inverted or flag-mistyped conversion keeps every existing row green.
The plan-review panel cut the first draft's 18 rows to the ones below; each keeps a distinct mutant alive. No new row
may contain a pipe-fed early-exit grep (the `apps/web-platform/*.test.sh` row has zero slack).

`apps/web-platform/infra/cron-egress-enforce-probe.test.sh` (the `docker` and `nft` stubs are at `:220-227`):

- Stub knobs, added to the existing bodies: `docker` `ps` arm emits `printf '%s\n' "$STUB_PS_NAMES"` when that variable
  is SET (even empty, via the `${STUB_PS_NAMES+x}` test) and `soleur-web-platform` otherwise; `nft` emits
  `printf '%s\n' "$STUB_NFT_OUT"` when set, else `jump SOLEUR-EGRESS`. The `printf` newline is load-bearing: with zero
  output lines an empty pattern (`grep -c ''`) would count 0 and survive the always-match mutant. Values travel only
  through `run_probe`'s `envw` words, never exported.
- **P2-2 near-miss names** (`soleur-web-platform-old` and `soleur-web-platform2`, one per line): rc 1 and stdout names
  `ASSERT-FAILED: container-absent` (the `-x` exact-line property of site 5).
- **P2-3 non-canonical must-pass** (`other` first, `soleur-web-platform` second): rc 0 and `egress-enforce-ok`.
- **P2-4 jump absent** (`STUB_NFT_OUT=` empty): rc 1; stdout names `ASSERT-FAILED: docker-user-jump`; no logged `docker`
  call has `exec` as its first argument (the structure arm precedes the behavioral probes).
- **P2-6 stdout carries no bare count** (healthy run, exact-line match): no stdout line is purely numeric. This is the
  row that kills a conversion that forgot `>/dev/null` (every other stdout assertion is a substring match).
- About 6 new cases; raise `MIN_CASES=56` (`:288`, directly above its `if` at `:289`) to the measured new total, exact
  (ADR-193 convention; the PR body records that the floors are exact by convention).

`apps/web-platform/infra/web-private-nic-guard.test.sh` (new section `--- pass 2 (#9217): converted predicates keep
their discrimination ---`; `EXTRA_ENV` overrides the per-run stub variables because `env` words come after the defaults):

- **W-1 `-w` near-miss**: `EXPECTED_IP=10.0.1.1` while the `ip` stub shows `10.0.1.10` -> `nic_ok=false` and
  `converged_by=detect-only`. Starts absent, so it reaches site 1 and then site 2 (the wait loop): weakening either alone
  turns it red.
- **W-2 `-F` literal**: `ip` stub shows `inet 10a0b1c10/32` while `EXPECTED_IP=10.0.1.10` (dots as wildcards would match
  it) -> `nic_ok=false`, `detect-only`.
- **W-4 IMDS near-miss**: body `- ip: 10.0.1.100` with `network_id:` lines present -> `imds_has_expected=false` (the closing
  `$` anchor of site 3).
- **W-5 wait-loop success arm, non-canonical must-pass**: an `ip` stub that omits the address on its first call and shows it
  from the second (call counter in a file named by an env knob; the stub is also called for `NIC_ADDRS`, so count only the
  predicate calls or key the flip on call number >= 2) -> `nic_ok=true`, `converged_by=already`. Without it a site 2 that is
  always false, or that lost its `break`, stays green (Kieran P1).
- **W-6 stdout carries no bare count**: no stdout line of a healthy run is purely numeric (kills a forgotten `>/dev/null`).
- About 8 new cases; raise `MIN_CASES=154` (`:553`) to the measured new total, exact.
- Site 4 (`IMDS_NETS` fallback) has no driveable RED row: `IMDS_NETS` is the output of `grep -c` at `:74`, always numeric (or
  empty only if grep itself errors), so the `|| IMDS_NETS=0` arm is unreachable from any stub. Stated plainly as an
  equivalent mutant; the exit-status equivalence table is its only evidence.

Run both suites against the UNCONVERTED scripts: every pre-existing row and every new row GREEN, totals recorded.
Run `bash scripts/guard-vacuity-floor.test.sh` and `bash .claude/hooks/grep-q-pipe-guard.test.sh` before the first
commit (new test lines must not add a pipe-fed `grep -q`).

### Phase 1 — the six conversions

Apply the six single-line edits in the table above. In each script add ONE short comment above the first converted site
(CTO review: the idiom reads as a worse `grep -q` and will be reverted without a reason): it says the predicate reads the
whole stream so the producer never takes EPIPE and points at the header of `.claude/hooks/grep-q-pipe-guard.test.sh`. The
wording must not contain a literal pipe-into-`grep -q` shape (the AC4 probe scans comments too). The first-draft header
clause about the registry twin is dropped (three reviewers called it ceremony); the "one family" sentence at
`web-private-nic-guard.sh:19-20` is left as is.

Run the exit-status equivalence table once more over the final lines (bash and dash, 8 inputs x 2 patterns) and record it
in the PR body. Do not edit any `curl`, `emit_fail`, xtrace, `INGEST_URL_PINNED` or Sentry transport line.

### Phase 2 — ledger

`.claude/hooks/grep-q-pipe-guard.test.sh`: delete the two rows (`:463-464`) and the "A seventh and eighth ..." comment
block above them (`:458-462`); `GATED_PROD_ROWS=8` -> `6` (`:898`); re-read the Wave A2 comment (`:440`) and the header
prose for sentences that name these two files or count rows and narrow each.

### Phase 3 — verification (record every result in the PR body)

The two extended suites; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `bash scripts/guard-vacuity-floor.test.sh`;
`private-nic-guard.test.sh` (registry twin, must stay green) and
`apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (it mutates the guard); the lints in the
Research Insights table, each by its own invocation; the Guard 1 and Guard 2 mutants on scratch copies; then
`bash scripts/test-all.sh --affected` if the host allows (it covers the remaining carrier suites listed in the census),
otherwise the PR body says verbatim that local `--affected` was skipped on a contended host and CI is the gate.
`plugins/soleur/skills/work/SKILL.md` is at 361940 bytes against its 362000-byte ceiling: nothing is added there.

### Phase 4 — ship tail

Tracker comment on #9217 (evidence, NOT-fixed list, terminal state, #9529 sequencing note); the one learning; labels
`semver:patch`, `app:web-platform` (both verified present), `type/chore`, `domain/engineering`; then in order: `Filed:`
line, Merge Danger section (`Undo:`, `Blast Radius:`), Pipeline Tally, Changelog, Model Dissents (informational), then
`soleur:postmerge`.

## Files to Edit

- `apps/web-platform/infra/web-private-nic-guard.sh` (4 sites, one comment)
- `apps/web-platform/infra/cron-egress-enforce-probe.sh` (2 sites, one comment)
- `apps/web-platform/infra/web-private-nic-guard.test.sh` (W-1, W-2, W-4, W-5, W-6, `MIN_CASES`)
- `apps/web-platform/infra/cron-egress-enforce-probe.test.sh` (stub knobs, P2-2, P2-3, P2-4, P2-6, `MIN_CASES`)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (delete two rows and their comment, `GATED_PROD_ROWS`)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-pass2-nic-guard-egress-probe/tasks.md`
- One learning under `knowledge-base/project/learnings/test-failures/` (topic only; the author picks the date): a
  behavior-preserving shell-form conversion needs rows that observe the DISCRIMINATION (near-miss, exact-line, second
  member, stdout cleanliness), because the happy path is satisfiable by an always-true grep; it also records that the six
  sites had no `pipefail`, so the sweep row counted a text shape, not a live misread.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "convert the 6 deferred pipe-fed `grep -q` hits" | Phase 1 table (6 sites) | mapped |
| 2 | "delete those rows" | Phase 2 | mapped |
| 3 | "Converting a file means its owning suite and every source-text pin over it stay green: grep the OLD line text across every *.test.*, not just the basename." | Research Reconciliation row 4; Carrier census; Phase 3 | mapped |
| 4 | "post an evidence comment on the existing tracker (#9217), write one learning per non-obvious finding, and state plainly in the PR body and tracker comment which items were NOT fixed" | Phase 4; Not Fixed; Files to Create | mapped |
| 5 | "Do not use Closes (use Ref); never use [skip-deploy-fix-apply]" | frontmatter note; AC7 | mapped |
| 6 | "the Sentry DSN curl is deliberately untouched (#9638)" | Cut List; Phase 1 last paragraph | mapped |
| 7 | "Triage #9639 / #9638: fix inline only where they naturally fit this pass, else leave tracked and say so." | Reconciliation row 6; Not Fixed | mapped |
| 8 | "check which touched-file lints in ci.yml fire on an infra script BEFORE editing it" | Research Insights lint table | mapped |
| 9 | "Any new anti-vacuity floor must meet guard-vacuity-floor.test.sh's shape and be in the LIVE PROMOTED_FILES ... run that suite before the first commit." | Cut List (no new floor); Phase 0 last paragraph; AC4 | mapped |
| 10 | "add nothing there" (work/SKILL.md) | Phase 3 last sentence | mapped |
| 11 | "keep edits to that file minimal and mention the overlap in the plan" | Reconciliation row 5 | mapped |
| 12 | "local --affected may be skipped relying on CI (say so verbatim in PR body)" | Not Fixed; AC7 | mapped |
| 13 | "Do NOT plan the later items" | Not Fixed | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Six conversions | asks 1-2 | asked |
| `grep -c >/dev/null` form (not here-string) | — | inferred — justification: Wave A2 family convention and zero process substitutions in the sibling boot scripts; the guard header allows both |
| Phase 0 characterization rows (P2-*, W-*) | ask 3 "its owning suite ... stay green" | inferred — justification: the suites cover only the happy arm, so a wrong conversion keeps them green; trimmed by plan review to the rows that each kill a distinct mutant |
| One short comment per script | — | inferred — justification: the idiom reads as a worse `grep -q` and would be reverted without a stated reason (CTO review) |
| `MIN_CASES` literal raises | ask 9 "anti-vacuity floor" | inferred — justification: an unraised floor leaves slack that hides dropped rows; same exact-count convention as pass 1 |
| `GATED_PROD_ROWS` 8 -> 6 | ask 2 | inferred — justification: the probe at `:898` fails the suite if the count is not edited with the rows |
| One learning | ask 4 | asked |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `.claude`
- Planned files: 5 edited + tasks + one learning | Estimated changed lines: about 100 (6 script lines + 2 comments, ~40 test lines, ~12 ledger lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Guard Contract

### Guard 1 — deferral ledger holds the two files at zero

**Property.** No pipe-fed early-exit `grep` exists in `web-private-nic-guard.sh` or `cron-egress-enforce-probe.sh`, and a
new one cannot be added to either without the derived sweep reddening the required test shard.

**Assembly.** The chokepoint is `scan_sweep` (`.claude/hooks/grep-q-pipe-guard.test.sh`), which derives its own population
by `git grep --no-index --exclude-standard` over `SWEEP_PATHSPEC` (every `.sh .bash .bats .yml .yaml .tf .template .js`
outside `knowledge-base/` and the suite itself), matches `PATTERN_V2`, filters comments and `# sigpipe-demo: intentional`
markers, and hands the lines to `sweep_verdict`, which assigns each to the first matching `SWEEP_DEFERRALS` row or reports
it "outside the deferral table". The ledger is the single `SWEEP_DEFERRALS` array; the production-row count is pinned
separately by `GATED_PROD_ROWS`. Both scripts are `.sh`, so they are in the population without any edit, and with their
rows deleted any hit is undeferred and fatal.

**Mutation matrix.**

| # | Mutation (on a scratch copy of the tree) | Must go RED because |
|---|---|---|
| G1-1 | append a pipe-fed early-exit grep line to `web-private-nic-guard.sh` after the converted sites (a second member after a compliant first) | "pipe-into-early-exit-grep outside the deferral table (1 site)" |
| G1-2 | delete the two rows but leave `GATED_PROD_ROWS=8` | `real-table-production-rows: 6 non-test-shaped rows (want exactly 8)` |
| G1-3 | revert only site 5 (`grep -cx` back to `grep -qx`) in the probe | undeferred hit on that one file |
| H1-1 (must-pass, non-canonical) | scratch file using the allowed here-string form (`grep -q P <<<"$V"`) | the sweep stays green: the guard does not reject every form |

The stale-row check (re-adding a deleted row) and the empty-population control (`rc_none`, `:950`) already exist in the
suite and are not re-tested here.

**Anchor.** The ledger is a stored value (row ceilings, `GATED_PROD_ROWS`) that the same diff can edit together with the
code it protects, so this guard proves consistency, not integrity. What outside the commit must move for a weakening to
pass: a reviewer accepting a visible one-line row addition (the table diff is the review surface, stated in the file
header); `GATED_PROD_ROWS` pins the production-row count so a production row cannot be added silently.

### Guard 2 — converted predicates keep discriminating

**Property.** Each of the six converted predicates returns the same verdict it returned before the conversion for a match,
a near-miss, an empty input and a non-canonical ordering, observed on the real scripts, and emits nothing on stdout.

**Assembly.** All six sites: NIC guard trigger predicate (`:55`) and its twin inside the bounded wait (`:61`), the IMDS
expected-address corroboration (`:78`), the IMDS-count numeric check (`:80`); probe readiness loop (`:86`) and the
`DOCKER-USER` jump check (`:100`). The two trigger sites are separate members; the near-miss rows start from an absent
address so they pass through both, and W-5 drives the second member's success arm. Site 4 is the one member no stub can
reach; its evidence is the equivalence table and it is reported as an equivalent mutant.

**Mutation matrix** (hand-applied on a scratch copy, one at a time; the control line, all suites green on the unmutated
scratch tree, is read first).

| # | Mutation | Must go RED because |
|---|---|---|
| G2-1 | drop `w` from site 1 only | W-1: `10.0.1.1` matches inside `10.0.1.10`, `nic_ok` flips true |
| G2-2 | drop `w` from site 2 only (second member) | W-1 again: the wait loop finds the prefix |
| G2-3 | drop `F` from site 1 only; then from site 2 only | W-2: wildcard dots match `10a0b1c10` |
| G2-4 | drop the closing `$` from the site 3 regex | W-4: `10.0.1.100` corroborates `10.0.1.10` |
| G2-5 | drop `x` from site 5 | P2-2: `soleur-web-platform-old` satisfies the readiness loop |
| G2-6 | remove the `!` at site 6, and separately make site 6's pattern empty | P2-4 (the knob emits at least one line, so an empty pattern counts it) |
| G2-7 | make site 2 always false, or delete its `break` | W-5 |
| G2-8 | drop `>/dev/null` at one site per script | P2-6 / W-6 |
| H2-1 (must-pass, non-canonical) | P2-3 (other container first), W-5 (address appears on the second call) | stay green on the correct conversion; a guard that rejects everything reds them |

**Anchor.** Not a stored-value guard (behavioral rows over live script execution against PATH stubs); the floors are exact
counts, the pass 1 convention, and the case counter moves in the assert wrappers, never in `_pass`/`_fail` (ADR-193).

## Observability

```yaml
liveness_signal:
  what: SOLEUR_PRIVATE_NIC emit to Better Stack each guard run (web-private-nic-guard.sh:105,130) plus the web_nic_guard heartbeat ping on healthy runs (web-private-nic-guard.sh:146-148); Sentry event with tag probe_result from emit_fail on any probe failure (cron-egress-enforce-probe.sh:63-80)
  cadence: every 5 minutes (web-private-nic-guard.timer OnUnitActiveSec=5min); the probe runs once per fresh-host boot
  alert_target: Better Stack heartbeat absence alarm for web-nic-guard; Sentry issue for the probe (a failed probe also powers the host off, so absence is the second signal)
  configured_in: apps/web-platform/infra/server.tf:944 (env file), apps/web-platform/infra/web-private-nic-guard.timer, plugins/soleur/lib/heartbeat-manifest.ts:200-214
error_reporting:
  destination: Better Stack Logs source via the pinned ingest URL (guard); Sentry via the DSN read from Doppler at runtime (probe emit_fail)
  fail_loud: guard prints "[nic] ..." lines on stderr (journal tag web-nic-guard) and withholds the heartbeat when nic_ok is false; probe prints ASSERT-FAILED sentinels, emits the Sentry event and exits 1 so cloud-init powers the host off
failure_modes:
  - mode: a converted predicate reads a present address as absent (false negative)
    detection: SOLEUR_PRIVATE_NIC rows carry nic_ok=false and converged_by=detect-only; the heartbeat lapses
    alert_route: Better Stack heartbeat absence for web-nic-guard
  - mode: a converted predicate reads an absent or near-miss address as present (false positive, the silent direction)
    detection: no runtime signal can see it by design; Phase 0 rows W-1 and W-2 and the post-merge read of nic_ok in the first post-apply row are the detection
    alert_route: pre-merge CI red on the suite; post-merge verification fails the merge check
  - mode: the readiness loop or the jump check mis-verdicts on a fresh host
    detection: probe_result=container_absent or structure_fail in the Sentry event, plus the host's absence
    alert_route: Sentry issue; the host powering off is the fail-closed outcome
logs:
  where: journalctl -t web-nic-guard shipped to Better Stack by Vector (vector.toml, SyslogIdentifier at web-private-nic-guard.service:22); probe output in the cloud-init log and the Sentry event
  retention: unchanged by this change (Better Stack source plan and Sentry project retention)
discoverability_test:
  command: python3 -c "print(sum(len(__import__('re').findall(r'\x7c *grep( +-[A-Za-z]+)* +-[A-Za-z]*q', open(f).read())) for f in ('apps/web-platform/infra/web-private-nic-guard.sh','apps/web-platform/infra/cron-egress-enforce-probe.sh')))"
  expected_output: 0
```

Note on the block above: the runtime signals are unchanged by this PR and reading them needs vendor credentials, so the
local command proves the one property this PR creates (no pipe-fed early-exit grep remains in the two scripts) and
nothing about Better Stack. It prints 6 on `origin/main` and 0 on the converted tree (both runs done during planning),
finishes in well under 15 seconds, and carries none of the shell-active bytes Check 10 rejects (`|`, `;`, `&`, `<`,
`>`, `$`, backtick: the bar is written as the regex escape for byte 0x7c). `credentials_required` is omitted on purpose:
declaring it would make Check 10 skip the command and verify nothing.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is edited, so `apply-deploy-pipeline-fix.yml` does not fire through its `server.tf` path trigger.

### Apply path

(b) existing automation, no new mechanism. On merge to `main`:

1. `apply-web-platform-infra.yml` fires (`apps/web-platform/infra/**`, `:19-20`). Its SSH-provisioned leg targets
   `terraform_data.private_nic_guard_install` (`:1192`); that resource replaces because the guard's bytes are in
   `triggers_replace` (`server.tf:896-908`). The provisioner copies guard, unit and timer to web-1, rewrites
   `/etc/default/web-private-nic-guard`, reloads systemd and (re)enables the timer: idempotent, no container or host
   restart. A tick landing during the non-atomic env-file rewrite can exit 1 once with `EXPECTED_IP` unset; the next
   tick recovers (a property of every re-provision of this resource).
2. `hcloud_server.web` carries `ignore_changes = [user_data, ...]` (`server.tf:597`), so the changed
   `host_scripts_content_hash` plans no change for it: no replace, no downtime.
3. `web-platform-release.yml` builds and deploys a new image the normal way; both scripts reach a FRESH host only
   through that image. A fresh-host dispatch is protected by the off-host `host-image-coherence-preflight.sh` run before
   any destructive step, so a web-2 replace should wait for the new release.
4. `cron-egress-enforce-probe.sh` has no running-host delivery path; its first execution of the new bytes is the next
   fresh web-host boot.
5. The SSH leg runs only when its token is readable; when it is not, the run stays green and a notification step
   (`Notify ops — SSH stage skipped, nothing delivered (#7539)`, `:1211`) fires. A green merge is therefore not proof
   of delivery; the post-merge checks read that step's outcome and the heartbeat.
6. No commit message in this PR may contain a line that is exactly `[skip-web-platform-apply]` or `[ack-destroy]`
   (`:335-341`), and `[skip-deploy-fix-apply]` is never used.

**Blast radius.** The NIC guard on web-1 only (a wrong verdict is detect-and-alarm, never a reboot, by ADR-123's design),
and fresh web hosts only for the probe, where a wrong verdict powers the new host off (`cloud-init.yml:807-809`) and a
wrong-green verdict still leaves the behavioral negative probe (`curl` exit 28) as the independent enforcement proof.
No running production origin executes the probe.

### Network-Outage Deep-Dive, distinctness, vendor tier

The post-merge apply drives a resource with `connection { type = "ssh" }`: CI reaches web-1 over the Cloudflare tunnel SSH
bridge (not `var.admin_ips`), and this plan changes no firewall, DNS, tunnel, secret, destination or vendor resource, so
L3 and L7 are unchanged; the verification artifact is the notification step's outcome (skipped means the SSH stage ran).
Not verified and not claimed: current egress-IP reachability of web-1.

## Architecture Decision (ADR/C4)

Skipped: no architectural decision. A mechanical shell-form conversion plus ledger shrink; no ownership or trust boundary
moves, no new substrate, no ADR reversed. Nothing in the C4 model names these predicates (the NIC guard and probe appear
only as host-resident scripts already modeled), so a reader of the existing ADRs and C4 is not misled after this ships.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. (Engineering is the only domain; the CTO lens is
covered by the carrier census, Guard Contract and apply-path analysis above.)

## User-Brand Impact

- **If this lands broken, the user experiences:** a fresh web host that powers itself off at boot (probe false negative) or a web-1 NIC guard that reports the private network healthy when it is not (guard false positive), delaying detection of a lost private link behind the app.
- **If this leaks, the user's data is exposed via:** no new vector; no credential, curl, URL or log-content line is edited, and Rule E and the xtrace refusal from pass 1 are untouched.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change is a behavior-preserving shell-form rewrite with exit-status equivalence measured and behavioral near-miss rows added, and the blast radius is detect-only on web-1 plus fresh hosts, so no single user's data or session is at risk.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` exits 0, its `DEFERRED:` lines name neither converted file, `grep -c -e 'cron-egress-enforce-probe' -e 'web-private-nic-guard' .claude/hooks/grep-q-pipe-guard.test.sh` prints `0`, and `grep -n '^GATED_PROD_ROWS=' .claude/hooks/grep-q-pipe-guard.test.sh` prints `GATED_PROD_ROWS=6`.
- [ ] AC2 `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` ends `RESULT: <N> passed, 0 failed` and `bash apps/web-platform/infra/web-private-nic-guard.test.sh` ends `=== <M> passed, 0 failed ===`, where `N` and `M` equal the raised `MIN_CASES` literals exactly (about 62 and 162; take the measured values), and `bash scripts/guard-vacuity-floor.test.sh` exits 0 (run before the first commit).
- [ ] AC3 each gate by its own invocation: `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` prints `OK`; `python3 scripts/lint-shell-capture-exit.py apps/web-platform/infra/web-private-nic-guard.sh apps/web-platform/infra/cron-egress-enforce-probe.sh` reports `0 new findings`; the repo-wide credential-refusal run (`scripts/test-all.sh`) stays green; `private-nic-guard.test.sh` and the `betterstack-send-failed-alert-mutation` suite pass.
- [ ] AC4 the discoverability command in `## Observability` prints `0` on the final tree (text shape only: a line-continued pipe would not be seen, which the sweep covers).
- [ ] AC5 `git diff --name-only origin/main...HEAD` is a subset of the five edited files, this plan, `specs/feat-one-shot-grep-q-pass2-nic-guard-egress-probe/` (`tasks.md`, `session-state.md`), the one learning, and generated `knowledge-base/INDEX.md` if the pipeline rewrites it; `plugins/soleur/skills/work/SKILL.md` is absent from it.
- [ ] AC6 the Guard 1 and Guard 2 mutants ran once by hand on scratch copies after reading the control line; every `G*` row went RED, `H*` rows stayed green, site 4 is reported as an equivalent mutant; results are in the PR body.
- [ ] AC7 PR body: first line states whether merging alone mutates production (it re-delivers the NIC guard to web-1 and ships a new image; the probe runs only at fresh-host boot); `Ref` lines only (no `Closes`/`Fixes`/`Resolves`); the NOT-fixed list; the verbatim sentence "Local `--affected` was skipped on this contended host; CI is the gate." when that is true; the exit-status equivalence table; the Wave A2 form rationale; the "no `pipefail`, so no live misread" statement; the note that the floors are exact by convention; labels `semver:patch` and `app:web-platform`; no commit message carries `[skip-deploy-fix-apply]`, `[skip-web-platform-apply]` or `[ack-destroy]`.
- [ ] AC8 evidence comment posted on #9217 (commands with their numbers, the corrected Class W premise, the terminal-state statement and the #9529 sequencing note).

### Post-merge (verified by `soleur:postmerge`, automatable)

- [ ] AC9 the `apply-web-platform-infra.yml` run for the merge SHA concludes success and its step `Notify ops — SSH stage skipped, nothing delivered (#7539)` is skipped (read with `gh run view <id> --json jobs`), meaning the SSH leg ran; `terraform_data.private_nic_guard_install` appears as replaced and no `hcloud_server.web` line does.
- [ ] AC10 the Better Stack heartbeat `soleur-web-nic-guard-web-1` reads `up` after the apply (reader pattern: `scripts/followthroughs/l3-probe-armed-6438.sh:62-68`); the heartbeat-absence alarm is the standing backstop, so this is a confirmation, not the only guard.

## Test Scenarios

1. Healthy probe run against stubs: rc 0, `egress-enforce-ok`, no bare count on stdout (existing P-X1c plus P2-6).
2. Probe with only near-miss names, and with the container listed after another: P2-2, P2-3.
3. Probe with the jump absent: P2-4.
4. NIC guard with the address present, absent, a prefix near-miss, a wildcard lookalike, and appearing on the second call: T1, T2, W-1, W-2, W-5.
5. IMDS corroboration with a canonical body and a prefix near-miss: T2, W-4; stdout cleanliness: W-6.
6. Guard ledger: append a pipe-fed grep, delete rows with a stale count pin, revert one site: G1-1..G1-3.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above.
- `apps/web-platform/*.test.sh` is `<= 180` with slack 0: a single pipe-fed early-exit grep in a new test row reds the required shard. Use here-strings or `grep -c ... >/dev/null`.
- Both `MIN_CASES` literals must stay on the line directly above their `if` and be edited in place; moving them breaks `guard-vacuity-floor.test.sh`'s shape check. `PROMOTED_FILES` is assigned four times in that file and only the last is read; this plan adds no file to it.
- The hand-applied mutants run on scratch copies of the tree, never the worktree; read the control line (all suites green on the unmutated scratch tree) before any row, because the probe suite needs `apps/web-platform/Dockerfile` and fails in a bare sandbox.
- The one comment added per script must not contain a literal pipe-into-`grep -q` shape, or the AC4 probe (which scans comments too) reads nonzero.
- `plugins/soleur/skills/work/SKILL.md` has 60 bytes of headroom; do not add prose there.
- The main checkout carries an uncommitted `M .mcp.json` that is not part of this work; never stage it.
