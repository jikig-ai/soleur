---
title: "infra: luks-monitor.test.sh flakes on 'printf: write error: Broken pipe' (heartbeat push race) — 2+ CI legs red"
type: fix
date: 2026-09-30
slug: fix-luks-monitor-epipe-flake
branch: feat-one-shot-9245-luks-epipe-flake
issue: 9245
closes: 9245
priority: medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# infra: luks-monitor.test.sh EPIPE flake + artifact-list pagination gaps

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed; no
spec.md exists for this branch — the one-shot path enters at plan).

## Enhancement Summary (deepen-plan, 2026-09-30)

**Reviewed-Coverage: sequential-fallback** — this harness exposes no
subagent spawn (no Task/Skill tool), so the deepen fan-out ran inline in a
single process: every halt gate executed mechanically, the round-1
verify-the-negative sweep ran as greps, and the review lenses ran
lead-authored (disclosed — not independent review).

- Phase 4.4 precedent-diff — PASS, side-by-side recorded in Dependencies &
  Risks (the `--paginate`|`jq -s` shape and the stdin-draining stub are both
  canonical repo forms).
- Phase 4.5 network-outage — triggered only by a *learning filename*
  containing "unreachable"; no SSH/connectivity hypothesis and no
  provisioner-driving Terraform in the diff → pass-through, no deep-dive.
- Phase 4.55 downtime — no trigger (no host/migration/deploy-mechanics
  change; the release-pipeline merge trigger is recorded under Risks).
- Phase 4.6 user-brand — PASS (`threshold: none` + scope-out bullet).
- Phase 4.7 observability — PASS (5 fields; verb `grep` allowlisted; no
  shell metachars; literal `expected_output`; <15 s command).
- Phase 4.8 PAT shapes — PASS (no `var.*_token`/`ghp_`/`github_pat_`).
- Phase 4.9 UI wireframe — SKIP (no UI-surface file).
- Phase 4.10 encryption posture — SKIP (no store/connection trigger).
- Phase 4.11 guard contract — PASS (`lint-guard-contract.py`: 2 guard
  entries green; assemblies name the chokepoint + census procedure, not
  just today's member list).
- Round-1 verify-the-negative — every `never`/`cannot`/`does-not` claim in
  the plan was re-verified by grep during this pass (stub never-reads at
  `workspaces-luks-harness.sh`, `gh_api`/`--paginate` flag tolerance at
  `ci-leg-balance-9232.test.sh:62`, luks-monitor.sh untouched by the edit
  list, active rule-ID citations).
- Quality-check sweep — no SHA/tag citations; no label-creating ACs; no
  AC grep scopes over the plan/tasks dir; bash strict-mode traps checked
  (the wire assert is a string compare, not an arithmetic catch).

### Key Improvements from deepen

1. `discoverability_test.command` rewritten shell-free (sharp-edge Check 10
   reject: `|`/`;`/`&`/`<`/`>`/`$` byte-level) — `bash -c '…&&…'` →
   `grep -rF -e … -e … <dirs>`.
2. Merge-blast-radius answer recorded: the diff's paths sit inside
   `web-platform-release.yml`'s `push: branches:[main]` filter → merge fires
   the standard release pipeline; no diff-authored resource change.
3. Precedent-diff block added (Phase 4.4) for both patterned mechanisms.
4. `sentry-last-applied-sha.sh` no-suite caveat + verification route made
   explicit; sloppy "suite if one exists" replaced with the real suite list
   (`tests/scripts/test-main-duplicate-skip.sh`, `parity.test.sh` paths).

## Overview

`deploy-script-tests` flakes red on `luks-monitor` with
`luks-monitor.sh: line 176: printf: write error: Broken pipe` — two CI legs on
PR #9233 plus intermittent repeats (issue #9245). The write at line 176 is the
escrow passphrase feed (`printf '%s' "$key" | cryptsetup luksOpen
--test-passphrase --key-file -`), not the heartbeat push the issue title
names. The test harness's PATH-shimmed `cryptsetup` exits on `luksOpen`
without reading stdin, so under runner load the `printf` subshell's write
lands after the read end closes: EPIPE under `set -o pipefail` flips the
pipeline verdict, `emit_and_die escrow_passphrase_mismatch` exits 1, and the
run dies before whichever later assert the case was exercising
(missing-baseline, covered-inode, heartbeat). Bundled in the same PR
(operator-directed): the artifact-list pagination gap deferred from #9232 —
`gh api .../artifacts` call sites that stop at the first page, so a run with
more than a page of artifacts silently drops entries (a truncated page reads
identically to a leg that died before its feed write).

## Problem Statement / Motivation

### The EPIPE flake (#9245)

`apps/web-platform/infra/luks-monitor.sh` runs `set -uo pipefail` (line 19).
At line 176 the escrow re-test feeds the LUKS passphrase through a pipe:

```bash
if printf '%s' "$key" | cryptsetup luksOpen --test-passphrase --key-file - "$real_dev" >/dev/null 2>&1; then
  WL_LUKS_OPEN_RESULT=ok
else
  WL_LUKS_OPEN_RESULT=fail; emit_and_die escrow_passphrase_mismatch
fi
```

The verdict is the *pipeline's* status, and `pipefail` folds the `printf`'s
exit into it. `printf` is a builtin; in a pipeline it runs in its own
subshell, concurrent with the `cryptsetup` process. On a real host,
`cryptsetup --key-file -` reads stdin before deciding — the reader outlives
the writer, and the write always lands. In the suite, `cryptsetup` is the
PATH stub at `apps/web-platform/infra/workspaces-luks-harness.sh`
(`mon_prepare`, the `cat > "$d/bin/cryptsetup"` heredoc):

```bash
case "$1" in
  status)  ... ;;
  luksUUID) ... ;;
  luksOpen) exit "${MON_ESCROW_RC:-0}" ;;   # <-- never reads stdin
esac
```

The stub records argv, then `exit`s — under `-P4` suite parallelism
(`run-registered-suites.sh`, `min(nproc,6)` on `ubuntu-24.04`) the stub can
fork, exec, record, and exit before the sibling `printf` subshell is ever
scheduled. The write then lands on a fully-closed pipe: bash reports
`printf: write error: Broken pipe`, the `printf` subshell exits non-zero,
`pipefail` propagates that into the pipeline status, the `if` takes the
failure arm, and `emit_and_die escrow_passphrase_mismatch` exits 1 — before
the fstab/peek/inventory/readyz/heartbeat asserts the case was actually
testing. Every observed failure signature matches:

- `healthy probe did not push the heartbeat (rc=1, pushes=0)` — died at the
  escrow assert, never reached the `curl` push.
- `a missing inventory baseline did not fail closed` — died at escrow; rc=1
  satisfied the `!= 0` half but `monOut 'workspace_count_baseline_missing'`
  never matched.
- `non-immutable covered inode did not fail covered_inode_not_immutable` —
  same shape.

This is the exact class pinned by learning
`2026-09-23-my-verdict-rode-on-a-pipeline-status-and-my-test-deleted-the-option-that-inverts-it.md`
(a verdict riding a pipeline status under pipefail) and
`2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md`
(the pipe buffer narrows the race window but never closes it — a stub that
exits before the writer is scheduled is the extreme form: no read ever).

### The artifact-list truncation (same-PR bundle, deferred from #9232's review)

`GET /repos/{o}/{r}/actions/runs/{run}/artifacts` pages at `per_page`. Five
call sites in this repo stop at page 1. A truncated page is *silent* — it
reads identically to a run that legitimately produced fewer artifacts:

| Site | Page bound | Failure direction on truncation |
|---|---|---|
| `scripts/regenerate-shard-manifest.py` `fetch_timings_from_run` | `per_page=100` | timing artifacts past 100 dropped; the `expected_legs` WARN then misreads truncation as "a leg died before its feed write" — the exact confusion the operator flagged |
| `.github/workflows/web-platform-release.yml` (~620) | `per_page=100` | `release-outputs-web-platform` on page 2 → `a_n=0` → `fail_closed release_outputs_missing` — a *false* deploy block |
| `.github/workflows/web-platform-release.yml` (~605) | `per_page=100` (jobs) | `release / release` job on page 2 → `n=0` → `fail_closed release_job_unresolvable` — false deploy block |
| `scripts/followthroughs/ci-leg-balance-9232.sh:126` | `per_page=100` | a run silently fails `narts -eq EXPECTED` → skipped from the balance sample — quiet under-sampling |
| `.github/workflows/fix-constraints-stage-b.yml:57` | none (30/page default) | `fix-constraints-patch-*` on page 2 → `recovery=0,giveup=0` → "nothing to apply" — a real recovery artifact silently skipped; privileged-consumer path |
| `scripts/sentry-last-applied-sha.sh:63` | `per_page=100` (jobs) | a >100-job run hides an apply success → scans further back → *widens* the assumed-applied window (the script's own comment calls that the permissive direction) |

Sibling sites checked and dispositioned (write-boundary sweep —
`hr-write-boundary-sentinel-sweep-all-write-sites`):

- `scripts/main-push-duplicate-skip.sh:63` (`jobs?per_page=100`) — **already
  guarded**: `total_count > 100` collapses to `missing` → `emit false` → the
  run is NOT skipped. Loud-safe direction. No change.
- `scripts/audit-bot-codeql-coverage.sh:102` (`check-runs?per_page=100`) —
  **acknowledge, no change**: truncation yields `codeql_state=missing`,
  which the audit *reports as a finding* — it fails toward the alarm, never
  toward silence. Different defect direction than this fix's class.
- `.github/workflows/fix-constraints-stage-b.yml`'s **template**
  `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-b.template:57`
  is the source of truth for the dogfood copy (`parity.test.sh` #5 asserts
  repo-root body == `sed __TARGET_DIR__` of the template). Both files get
  the same edit — fixing only the dogfood copy reds parity.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Issue hypothesizes "heartbeat push race" (the push write races teardown) | Line 176 is the *escrow passphrase* feed; the heartbeat push is `curl -gfsS` (~line 386) with no stdin pipe at all. `pushes=0` in the failed run is a *symptom*: the run died at escrow before reaching the push | Fix the escrow feed path, not the push. The acceptance's "test harness waits for the reader" arm is the correct door: the stub IS the reader that never reads |
| "EPIPE tolerance in the monitor's push" is one offered arm | No EPIPE can occur in prod — real `cryptsetup --key-file -` consumes stdin. The defect is stub fidelity, not monitor robustness | Leave `luks-monitor.sh` unchanged; fix the harness stubs. Monitor-side `PIPESTATUS` capture considered and rejected (see Alternatives) |
| Deferred nit: "`regenerate-shard-manifest.py` and `web-platform-release.yml` need pagination" | Sweep found **four more** same-shape sites (stage-B template+dogfood, ci-leg-balance-9232, sentry-last-applied-sha jobs, release.yml jobs) | All silent/permissive-direction sites folded in; already-guarded and alarm-direction siblings dispositioned in the table above |

## Proposed Solution

### Part A — the stubs become faithful readers (the flake fix)

The repo's own convention is already a drain: `inngest-luks-cutover.test.sh`
reads `_k="$(cat)"` and *verifies* the passphrase;
`workspaces-boot-unlock.test.sh` and `git-data-luks-reopen.test.sh` both
`cat > "$FX/key_seen"`. Three stubs predate it and exit without reading:

1. **`workspaces-luks-harness.sh` — `mon_prepare`'s `bin/cryptsetup`**
   (the confirmed flake). In the `luksOpen` arm, consume stdin to a capture
   file before the rc knob decides:

   ```bash
   luksOpen) { [ ! -t 0 ] && cat >"${CALLS}.escrow-stdin"; } 2>/dev/null || true; exit "${MON_ESCROW_RC:-0}" ;;
   ```

   `[ ! -t 0 ]` keeps an unpiped interactive invocation from hanging on a
   terminal stdin; the capture file is what the new wire assert reads.

2. **`workspaces-luks-harness.sh` — `run_case`'s `cryptsetup()` function**
   (~line 362). Serves the `printf '%s' "$KEY" | cryptsetup
   luksFormat/luksOpen --key-file -` lines in `workspaces-cutover.sh` (2397,
   2408), `workspaces-luks-reopen.sh` (157), `git-data-bootstrap.sh` (102)
   for every `run_case` suite that drives them — the same latent flake.
   Drain whenever the argv carries the stdin feed:

   ```bash
   case " $* " in *" --key-file - "*) { [ ! -t 0 ] && cat >/dev/null; } 2>/dev/null || true ;; esac
   ```

   placed immediately after `rec "cryptsetup $*"` (first statement, so
   every arm — including the `return 0` fallthrough — drains first).
   Scoped to `--key-file -` so `status`/`luksUUID`/`close` calls — never
   piped — never touch stdin.

3. **`workspaces-luks-staging.test.sh` ~885** — the inline whole-script
   `bin/cryptsetup` heredoc-printf stub (`*luksFormat*) exit` /
   `*luksOpen*) exit`). Insert the same guarded `cat >/dev/null` drain
   inside both arms (printf-format string — no single quotes / `%` in the
   inserted text).

   The `luks-monitor.sh` side is deliberately untouched: the failure arm is
   correct when the pipe genuinely fails, and on a real host the read end
   is always consumed (see Alternatives for the rejected PIPESTATUS form).

4. **`luks-monitor.test.sh` — pin the wire, not just the argv.** After the
   healthy-heartbeat case (~line 541), assert the passphrase actually
   arrived at `cryptsetup`:

   ```bash
   [ "$(cat "$CALLS.escrow-stdin" 2>/dev/null)" = "k" ]  # MON_KEY default
   ```

   Without the drain there is no capture file → the assert fails
   *deterministically*, not flakily. This is the
   `2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md`
   class closed: argv is recorded, but delivery is what the pipeline
   actually depends on.

### Part B — paginate every artifact/jobs list read

Repo-canonical idiom (`scripts/actions-queue-health.sh:148-153`, learning
`2026-03-24-gh-api-paginate-concatenated-arrays.md`): `gh api --paginate`
with **no** `--jq` (gh applies `--jq` per page → multi-document output),
piped to `jq -s` to slurp the concatenated page objects, then flatten.

- **`scripts/regenerate-shard-manifest.py`** — extract a
  `list_run_artifacts(run_id)` helper that loops `&page=N` until
  `len(chunk) < 100` or `len(arts) >= total_count` (termination on either;
  an empty page also exits). `fetch_timings_from_run` calls it. (A pure
  Python page loop — the script's only external dep today is `gh` itself;
  `jq -s` would add a jq-binary dependency to an operator-run tool, and
  `--paginate`+`--jq` yields multi-document output `json.loads` cannot
  parse.)
- **`.github/workflows/web-platform-release.yml`** (~620) — replace
  `gh_api ".../artifacts?per_page=100" --jq '[.artifacts[] | ...]'` with
  `gh_api --paginate "repos/$REPO/actions/runs/$run_id/artifacts?per_page=100" | jq -s '[.[].artifacts[] | select(.name == "release-outputs-web-platform") | {id, expired}]'`;
  same for the `jobs` call (~605): `--paginate` + `jq -s '[.[].jobs[] |
  select(.name == "release / release") | {name, conclusion}]'`. `gh_api`'s
  3-attempt retry wraps the `--paginate` call unchanged.
- **`plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-b.template`
  and `.github/workflows/fix-constraints-stage-b.yml`** — both get
  `arts=$(gh api --paginate "repos/${REPO}/actions/runs/${RUN_ID}/artifacts" | jq -s '[.[].artifacts[].name]')`
  (identical edit; the line carries no `__TARGET_DIR__` token, so parity
  test #5 stays byte-equal).
- **`scripts/followthroughs/ci-leg-balance-9232.sh:126`** — same
  `--paginate | jq -s` shape. Its test stub already tolerates `--paginate`
  (it shifts the flag and dumps the fixture; `jq -s` then sees a
  one-element stream — works).
- **`scripts/sentry-last-applied-sha.sh:63`** — `jobs?filter=all` goes
  `--paginate | jq -s '[.[].jobs[] | ...]'` (permissive-direction
  truncation — see sweep table).

### Part C — regression coverage (the guards)

- `plugins/soleur/test/regenerate-shard-manifest.test.sh`: add a
  PATH-stubbed `gh` fixture where a run's timing artifact exists **only on
  page 2** (page 1 = 100 filler artifacts, `total_count=101`; page 2 = the
  `suite-timings-scripts-*` artifact). Assert the merged timings include a
  label carried only by the page-2 artifact. Removing pagination turns it
  RED deterministically.
- `scripts/followthroughs/ci-leg-balance-9232.test.sh`: assert the
  artifacts call carried `--paginate` (grep the stub's `calls.log` —
  mirrors `actions-queue-health.test.sh:379-383`'s jobs-pin).
- `luks-monitor.test.sh`: the escrow-stdin wire assert above.

## Technical Considerations

- **Why not fix the monitor instead of the stubs.** Three candidate
  monitor-side forms all lose: (a) `printf | cryptsetup` → here-string
  `<<<"$key"` — bash implements here-strings via a temp file, which writes
  the live LUKS passphrase to disk transiently; the script refuses `-x` for
  exactly this credential-exposure reason (#7797). (b) Process substitution
  `--key-file <(printf ...)` — still a pipe, same EPIPE window, plus
  `/dev/fd` portability caveats. (c) `PIPESTATUS[1]` capture to ignore the
  writer's status — papers over unfaithful stubs but leaves the `write
  error` noise in stderr on every flake and changes prod code for a
  test-only artifact; and an EPIPE in prod would still correctly fail via
  cryptsetup's own rc (it saw EOF → no key → fails). Stub fidelity is the
  defect; the drain is the minimal faithful fix.
- **Why `cat` and not `read`/`head`.** `cat` drains to EOF — precisely what
  real cryptsetup does with `--key-file -`. A `head -c` bound would close
  early on oversized input and reintroduce the race on a different axis.
  `[ ! -t 0 ]` is the only guard needed: in the failing pipelines stdin is
  never a tty; in CI the inherited stdin is non-tty (typically `/dev/null`
  — instant EOF; the drain is correct either way since a pipe is the only
  stdin that carries bytes here), and interactive suite runs keep terminal
  stdin out of the drain.
- **`--paginate` termination.** `gh api --paginate` follows `Link: rel=next`
  until exhausted — bounded by `total_count`. The Python loop terminates on
  `len(chunk) < 100` OR `len(arts) >= total_count`, so an API regression
  that drops `total_count` still terminates on a short page.
- **`jq -s` shape.** `gh api --paginate` emits concatenated JSON documents
  (`{…}{…}`), NOT one document — `jq -s` slurps them into an array of
  page objects, and `[.[].artifacts[]]` flattens. Never combine
  `--paginate` with `--jq`: gh applies `--jq` per page
  (actions-queue-health.sh:148's comment documents the multi-line-scalar
  crash this caused).
- **Rate-limit surface.** `--paginate` adds ≥0 calls today (all listed runs
  fit in one page); worst case is bounded by artifact count ÷ 100.
- **Suite runtime.** `bash apps/web-platform/infra/luks-monitor.test.sh` =
  ~9 s locally (78 asserts). The added drain/assert are O(1).
- **`emit_and_die` rc contract.** rc=1 stays the drift verdict; the fix
  changes *when the stub is faithful*, not the script's exit taxonomy —
  `heartbeat_push_failed` (rc=3) vs drift (rc=1) asserts are untouched.
- **Sensitive paths.** `apps/web-platform/infra/*` and
  `.github/workflows/web-platform-release.yml` match the preflight
  sensitive-path regex → User-Brand Impact carries the `threshold: none`
  scope-out bullet.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/workspaces-luks-harness.sh` | `mon_prepare` `bin/cryptsetup` `luksOpen` arm drains stdin to `"$CALLS.escrow-stdin"`; `run_case` `cryptsetup()` drains stdin when argv carries `--key-file -` |
| `apps/web-platform/infra/luks-monitor.test.sh` | new assert: escrow key arrived at cryptsetup (`$CALLS.escrow-stdin` == `MON_KEY` default `k`) after a healthy `mon_run` |
| `apps/web-platform/infra/workspaces-luks-staging.test.sh` | inline `bin/cryptsetup` stub (~line 885): drain stdin in the `*luksFormat*`/`*luksOpen*` arms |
| `scripts/regenerate-shard-manifest.py` | new `list_run_artifacts(run_id)` page loop (`per_page=100&page=N`, terminate on short page or `total_count`); `fetch_timings_from_run` consumes it |
| `.github/workflows/web-platform-release.yml` | release-monitor step: `artifacts` AND `jobs` calls → `--paginate` + `jq -s` flatten (the `arts=` line also gains `|| fail_closed "..." "github_api_unavailable"` so an `gh_api` failure no longer dies silently under the step's `set -e`) |
| `.github/workflows/fix-constraints-stage-b.yml` | artifacts call → `--paginate` + `jq -s` |
| `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-b.template` | identical artifacts-call edit (parity.test.sh #5 pins dogfood == substituted template) |
| `scripts/followthroughs/ci-leg-balance-9232.sh` | artifacts call → `--paginate` + `jq -s` |
| `scripts/followthroughs/ci-leg-balance-9232.test.sh` | calls.log assert: every `artifacts` call carried `--paginate` |
| `plugins/soleur/test/regenerate-shard-manifest.test.sh` | PATH-stubbed `gh` multi-page fixture: timing artifact only on page 2 → merged output must contain its suites |
| `scripts/sentry-last-applied-sha.sh` | `jobs?filter=all&per_page=100` → `--paginate` + `jq -s` |

## Files to Create

None — all changes land in existing files.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the
  blast radius is CI truthfulness. A wrong drain reddens the suite (fail
  direction, never silent green); a pagination bug in `stage-b`/`release`
  could repeat the exact silent-skip/false-block this PR removes.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no exposure vector — the captured "key" is the stub's synthesized `k`;
  the prod passphrase path is untouched.
- **Brand-survival threshold:** `none`
- `threshold: none, reason:` the sensitive-regex matches
  (`apps/web-platform/infra/*`, `web-platform-release.yml`) are test-harness
  stubs and read-only CI bookkeeping calls — no credential path, no
  provisioned resource, and no user-data surface changes; the probe binary
  `luks-monitor.sh` is deliberately unmodified.

## Observability

The deliverable is offline/CI machinery; its observable surface is the
deploy-script-tests leg itself and the post-merge leg-balance probe.
(Included because the Files-to-Edit set touches `apps/*/infra/` — Phase 2.9
trigger.)

```yaml
liveness_signal:
  what: "deploy-script-tests leg verdicts on luks-monitor (78 asserts) + the ci-leg-balance-9232 soak probe"
  cadence: "per CI run (suites), daily sweep once the #9232 follow-through enrollment fires"
  alert_target: "required/advisory job red + follow-through comment on #9232"
  configured_in: ".github/workflows/infra-validation.yml deploy-script-tests; scripts/followthroughs/ci-leg-balance-9232.sh"
error_reporting:
  destination: "GitHub Actions job log; suite [FAIL] rows name the case"
  fail_loud: "a resurrected flake reads as the case's own FAIL (escrow_passphrase_mismatch attribution is now impossible to confuse — the wire assert + drain make it deterministic)"
failure_modes:
  - mode: "stub drain regressed (removed or redirected)"
    detection: "escrow-stdin wire assert fails deterministically — the capture file is absent when the drain is absent"
    alert_route: "deploy-script-tests leg red"
  - mode: "pagination regressed (call shape or page loop removed)"
    detection: "page-2 fixture assert (regen) + --paginate call-shape assert (ci-leg-balance)"
    alert_route: "plugins/soleur test battery + followthrough suite red"
  - mode: "a NEW non-draining stub added to the harness later"
    detection: "same wire assert pattern; sibling suites already drain (git-data-luks-reopen, boot-unlock, inngest) so the convention is load-bearing"
    alert_route: "deploy-script-tests leg red"
logs:
  where: "deploy-script-tests job log (per-suite PASS/RED via run-registered-suites.sh); suite stdout/stderr captured per case in MON_OUT"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: grep -rF -e escrow-stdin -e paginate apps/web-platform/infra scripts .github/workflows plugins/soleur/skills/constraint-scaffold/references
  expected_output: escrow-stdin
```

## Guard Contract

### Guard 1 — escrow wire-delivery assert (`luks-monitor.test.sh` + harness drain)

**Property.** On every `mon_run`, the passphrase the probe pipes must
actually arrive at `cryptsetup` — the `luksOpen` stub drains stdin into
`$CALLS.escrow-stdin`, and the suite asserts the file carries `MON_KEY`.

**Assembly.** The chokepoint is `luks-monitor.sh:176` — the single
stdin-pipe into a stubbed binary on the probe path (verified by grep:
`printf` lines 23/126/176; only 176 feeds a pipe). All three non-draining
`cryptsetup` stubs on `printf|cryptsetup --key-file -` paths are enumerated
by the census below and all three get the drain: `mon_prepare`'s
`bin/cryptsetup` (luks-monitor), `run_case`'s `cryptsetup()` (cutover,
reopen, git-data SUTs), staging test's inline stub. Faithful-draining
siblings (`inngest-luks-cutover` `_k="$(cat)"`, `git-data-luks-reopen` /
`workspaces-boot-unlock` `cat > key_seen`, `registry-luks-escrow`
`cat > "$KEYSEEN"`) define the convention and are unchanged.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `cat >"${CALLS}.escrow-stdin"` drain from the `luksOpen` arm | RED — capture file absent, wire assert fails deterministically |
| 2 | Redirect the drain to `/dev/null` only (no capture file) | RED — file absent → same fail; pins the capture, not just "a drain exists" |
| 3 | SUT mutation: point `printf` at the wrong fd (`printf '%s' "$key" >&2 | cryptsetup …` shape) | RED — file empty ≠ `k`; the wire, not the argv, is pinned |
| 4 (dispatch) | Assert reads the wrong path (`$CALLS` not `$CALLS.escrow-stdin`) | RED — `cat $CALLS` content is the argv log, `k` substring check must target the capture file |
| 5 (must-pass) | `MON_KEY` overridden to a different value via `mon_run MON_KEY=…` | PASS — the assert compares against the knob, not a literal |

### Guard 2 — pagination regression coverage (`regenerate-shard-manifest.test.sh` + `ci-leg-balance-9232.test.sh`)

**Property.** Every `gh api …/artifacts` (and the two `…/jobs`) list call
sites read ALL pages — a run with >page-size artifacts cannot be silently
truncated.

**Assembly.** The call-site census is the assembly: artifacts =
`regenerate-shard-manifest.py`, `web-platform-release.yml`,
`fix-constraints-stage-b.template` + dogfood `.yml`, `ci-leg-balance-9232.sh`;
jobs = `web-platform-release.yml`, `sentry-last-applied-sha.sh`. Already-
guarded siblings (`main-push-duplicate-skip.sh`'s `total_count` guard;
`audit-bot-codeql-coverage.sh`'s alarm-direction `missing`) are documented
dispositions, not blind spots. There is no single chokepoint — the sites
are enumerated per-file; the asserts live in the two fixture suites whose
`gh` stubs observe call shape (`calls.log`) and page semantics.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `list_run_artifacts` to a single `?per_page=100` fetch | RED — the page-2-only timing artifact is never merged; the label assert fails |
| 2 | Keep the loop but never increment `page` | RED — page 1 refetched; the page-2 artifact never arrives (loop exits on `len(arts) >= total_count` with duplicates or on timeout-free short-page logic — either way the page-2 label is absent) |
| 3 | Drop `--paginate` from `ci-leg-balance-9232.sh`'s artifacts call | RED — calls.log grep: an `artifacts` call without `--paginate` fails the shape assert (dispatch row) |
| 4 (harness) | gh stub that ignores `page=` and always returns the full set | must-PASS only when real pagination ran — covered by the fixture splitting the artifacts across pages (row 1 would falsely pass); the fixture's page-1 payload must EXCLUDE the target artifact |
| 5 (must-pass) | `total_count=101` with page 2 holding exactly 1 artifact | PASS — boundary page size is not off-by-one'd |

## Acceptance Criteria

- [ ] AC1 — `apps/web-platform/infra/luks-monitor.test.sh` cannot flake on
  the escrow feed: the `mon_prepare` `bin/cryptsetup` stub drains stdin on
  `luksOpen` into `$CALLS.escrow-stdin`, so `printf`'s write can never land
  on a closed pipe.
- [ ] AC2 — Wire assert: the suite asserts
  `[ "$(cat "$CALLS.escrow-stdin")" = "$expected_key" ]` after a healthy
  `mon_run` — deterministic RED if the drain is removed or the feed shape
  changes.
- [ ] AC3 — The same defect class is closed in the two sibling stubs:
  `run_case`'s `cryptsetup()` drains on `--key-file -` argv, and
  `workspaces-luks-staging.test.sh`'s inline stub drains in its
  `luksFormat`/`luksOpen` arms.
- [ ] AC4 — `luks-monitor.test.sh` green across 3 consecutive
  infra-validation `deploy-script-tests` runs on the PR (re-trigger the leg
  via re-run/empty-push; the issue's acceptance bar).
- [ ] AC5 — `scripts/regenerate-shard-manifest.py` reads every artifacts
  page (loop terminates on short page or `total_count`); the new gh-stub
  fixture proves a page-2-only timing artifact is merged.
- [ ] AC6 — `web-platform-release.yml` artifacts AND jobs calls, the
  `fix-constraints-stage-b` template + dogfood copy,
  `ci-leg-balance-9232.sh`, and `sentry-last-applied-sha.sh` all paginate
  via `--paginate` + `jq -s` flatten.
- [ ] AC7 — `parity.test.sh` #5 stays green (stage-b template and dogfood
  copy edited identically); `ci-leg-balance-9232.test.sh` carries the
  `--paginate` call-shape assert.
- [ ] AC8 — `bash apps/web-platform/infra/luks-monitor.test.sh` and the
  staging/freeze suites that drive `run_case` stay green locally;
  `bash plugins/soleur/test/regenerate-shard-manifest.test.sh` and
  `bash scripts/followthroughs/ci-leg-balance-9232.test.sh` green.

## Test Scenarios

- Given the `luksOpen` stub drains stdin to `$CALLS.escrow-stdin`, when a
  healthy `mon_run` executes, then the file exists containing `k` and the
  wire assert passes.
- Given the drain is removed, when the suite runs, then the wire assert
  fails deterministically on every run (not 2% of the time).
- Given a `run_case` suite drives `printf key | cryptsetup luksFormat
  --key-file -`, when the function stub answers, then stdin was consumed —
  no `write error` can appear in `CASE_OUT`.
- Given a gh fixture whose run carries 101 artifacts with the timing
  artifact on page 2, when `fetch_timings_from_run` executes, then the
  merged dict contains page-2 suites; mutation to single-page turns it RED.
- Given `ci-leg-balance-9232.sh` runs against the stub, when the calls log
  is inspected, then every `/artifacts` call carried `--paginate`.
- Given the stage-b template and dogfood copy, when `parity.test.sh` runs,
  then the bodies stay byte-equal after substitution.
- **Local verification:** `bash apps/web-platform/infra/luks-monitor.test.sh`
  → `78 passed, 0 failed` (count moves to 79 with the wire assert); a
  stress loop `for i in $(seq 60); do bash apps/web-platform/infra/luks-monitor.test.sh >/dev/null 2>&1 || echo "FLAKE $i"; done`
  prints nothing.
- **CI verification:** re-run the `deploy-script-tests` legs on the PR 3×
  (`gh run rerun --failed` on the two previously-red leg shape, or empty
  pushes); all legs green.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** (inline — this harness exposes no subagent spawn; CTO-lens
self-assessment) Blast radius is confined to test fixtures and CI
bookkeeping reads. The escrow drain changes no prod code path — the probe
binary is untouched and its exit taxonomy (`emit_and_die` rc=1 vs
`emit_readiness_and_die` rc=3) is preserved. The pagination edits follow a
documented repo idiom and every consumer's fail direction was enumerated in
the sweep table — the two corrected ones flipped from silent-skip/false-
block to actually reading the data.

No other domain's Assessment Question matches: no user-facing surface
(Product — the Files lists hit no UI-surface term or `components/**/*.tsx`
glob), no regulated-data surface (Legal), no vendor/procurement
(Operations/Finance), no pipeline or support surface (Sales/Support), no
public messaging (Marketing).

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (87 open) for every
Files-to-Edit path. One hit:

- #3220 (`ci: postmerge verification of trigger-bearing migrations in prd`)
  — **acknowledge**: it names `web-platform-release.yml` but scopes to the
  `migrate` job's post-apply verification; this plan edits the
  release-monitor step's API reads (~605/620). Disjoint sections of the
  same file; no rework or double-counting risk.

No other open scope-out touches `workspaces-luks-harness.sh`,
`luks-monitor{,.test}.sh`, `regenerate-shard-manifest.py`,
`fix-constraints-stage-b.*`, `ci-leg-balance-9232.*`, or
`sentry-last-applied-sha.sh`.

## Success Metrics

- `deploy-script-tests` legs stop flaking on `luks-monitor` (issue's bar:
  3 consecutive green infra-validation runs; class-level fix verified by
  the deterministic wire assert, not by run-count luck alone).
- Zero artifact/jobs list call sites in the repo that can silently truncate
  (the sweep table enumerates the full set; the two surviving non-paginated
  sites are deliberately-guarded or alarm-direction).
- No new credential exposure surface (no here-string temp files; the only
  new file write is the test-scratch capture under `$RUN_SCRATCH`).

## Dependencies & Risks

- **Merge-side blast radius (per sharp edge — "does merging THIS alone
  mutate production?"):** the diff touches `apps/web-platform/infra/*` and
  `plugins/soleur/**`, both inside `web-platform-release.yml`'s `push:
  branches:[main] paths:` set — so the merge fires the standard release
  pipeline (rebuild + redeploy of identical runtime bits; `luks-monitor.sh`
  itself is unchanged, so the baked unit is byte-identical). No resource is
  created or mutated by the diff itself. `fix-constraints-stage-b.yml` runs
  only on `workflow_run` after a Stage-A success; its edit changes a read
  path inside the privileged consumer, exercised on the next real trigger.
- **Precedent-diff (deepen Phase 4.4).** Both patterned mechanisms are
  canonical repo forms — deltas side-by-side:

  ```text
  precedent: actions-queue-health.sh:152           this plan (release.yml ~620):
    gh api --paginate ".../jobs" \                   gh_api --paginate ".../artifacts?per_page=100" \
      | jq -s '[.[].jobs[]|select(...)] | length'      | jq -s '[.[].artifacts[]|select(...)|{id,expired}]' \
    || { echo UNKNOWN; exit 2; }                       || fail_closed "..." "github_api_unavailable"

  precedent: inngest-luks-cutover.test.sh:190       this plan (harness bin/cryptsetup):
    luksOpen) _k="$(cat)"; [verify; exit rc]          luksOpen) { [ ! -t 0 ] && cat >"$CALLS.escrow-stdin"; } \
                                                            2>/dev/null || true; exit "${MON_ESCROW_RC:-0}"
  ```

  Deltas: `gh_api` wraps the call in 3-attempt retry/`timeout 20` (precedent
  exits 2 on transport failure — the plan's `fail_closed` arm is the same
  fail-loud direction). The drain adds `[ ! -t 0 ]` (siblings don't guard
  because they only ever run piped; the harness stub can also be invoked by
  non-piped callers) and captures to a file for the wire assert instead of
  verifying inline — same drain semantics, different assertion site.
- **Risk: a drained stub masks a real "cryptsetup never reads" defect.**
  Mitigation: the wire assert pins *delivery*, and the rc knob
  (`MON_ESCROW_RC`) still drives the failure arm — a stub can drain AND
  return failure; both directions stay testable.
- **Risk: `[ ! -t 0 ]` guard skipped a drain in a context where stdin is a
  tty and the SUT pipes.** Impossible by construction — a pipeline never
  connects a tty to the consumer's stdin.
- **Risk: `jq -s` on an empty `gh_api` output yields `[]` → `a_n=0` →
  `fail_closed`.** Same verdict shape as today's empty page — fail-closed
  direction preserved; the new `|| fail_closed` on the `arts=` line also
  covers transport failure (previously a bare `set -e` death with no
  `skip_reason` → degraded Slack reporting — flagged by the `gh_api`
  block's own comment).
- **Risk: `timeout 20` inside `gh_api` bounds all pages.** Bounded —
  artifact counts per run are O(tens); a pathological multi-hundred-page
  run would hit the timeout and `fail_closed` loudly, never truncate
  silently.
- **Dependency:** `jq` and `gh` on runners (already required);
  `python3`+`gh` for the regen tool (unchanged).
- **Risk: `--paginate` on `jobs?filter=all`** changes result order? No —
  pagination preserves the endpoint's ordering; `filter=all` still widens
  to every attempt's jobs.

## Implementation Phases

### Phase 1: EPIPE drains + wire assert (the #9245 fix)

1. `workspaces-luks-harness.sh` `mon_prepare` `bin/cryptsetup`: `luksOpen`
   arm drains stdin to `"$CALLS.escrow-stdin"` guarded by `[ ! -t 0 ]`.
2. `workspaces-luks-harness.sh` `run_case` `cryptsetup()`: guarded drain
   when argv contains `--key-file -`.
3. `workspaces-luks-staging.test.sh` ~885: drain in both inline-stub arms.
4. `luks-monitor.test.sh`: wire assert after the healthy-heartbeat case.
5. `bash apps/web-platform/infra/luks-monitor.test.sh` green; stress loop
   60×; run the two other suites that exercise the edited stubs
   (`workspaces-luks-staging.test.sh`, `workspaces-luks-freeze.test.sh`).

### Phase 2: pagination + regression fixtures

1. `regenerate-shard-manifest.py` `list_run_artifacts` + consumer swap;
   multi-page fixture in `plugins/soleur/test/regenerate-shard-manifest.test.sh`.
2. `web-platform-release.yml`: artifacts + jobs calls → `--paginate` +
   `jq -s`; add `|| fail_closed` to the `arts=` line.
3. `fix-constraints-stage-b.template` + dogfood `.yml`: same artifacts fix,
   byte-identical between them.
4. `ci-leg-balance-9232.sh` + its test's calls.log `--paginate` assert.
5. `sentry-last-applied-sha.sh` jobs call → `--paginate` + `jq -s`.
   (Caveat: this script has NO dedicated suite — the change is a one-line
   idiom swap to the documented `--paginate`|`jq -s` shape; verify with
   `bash -n` + a review read, and note `apply-sentry-infra.yml` exercises it
   on its next run.)
6. Run `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh`,
   `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`,
   `bash scripts/followthroughs/ci-leg-balance-9232.test.sh`, and
   `bash tests/scripts/test-main-duplicate-skip.sh` (unchanged neighbor —
   confirms the `total_count` guard sibling still green).

### Phase 3: CI verification

1. Push; watch `deploy-script-tests` legs on the PR.
2. Re-trigger the legs twice more (`gh run rerun --failed` or empty push)
   for the 3-green AC.
3. `act`-free workflow sanity: `actionlint` / the repo's workflow lint
   suites for the two edited workflows.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| `printf … | cryptsetup` → `cryptsetup … <<<"$key"` (here-string) | Bash here-strings are implemented via a temp file — the live LUKS passphrase transiently hits disk. The script refuses `-x` for this exact credential-exposure reason (#7797). Same reason `> tmpfile` is out. |
| `--key-file <(printf '%s' "$key")` (process substitution) | Still a pipe (`/dev/fd/N`) — the same EPIPE window if the reader exits first; adds `/dev/fd` portability caveats for zero gain. |
| `luks-monitor.sh`: capture `${PIPESTATUS[1]}` so only cryptsetup's rc decides | Papers over unfaithful stubs but keeps `write error` stderr noise on every flake, and changes prod code for a test-only artifact. In prod the read end is always consumed, so the tolerance buys nothing real. Rejected — but recorded: if a future run shows EPIPE on a REAL host, this is the first lever to revisit. |
| Retry/skip the heartbeat push on EPIPE (issue's arm 1, literal) | The failing write is the escrow feed, not the heartbeat push — tolerating EPIPE at the push would fix nothing (the run dies earlier). |
| `trap '' PIPE` / ignore SIGPIPE in the monitor | Changes signal semantics for the whole script to tolerate a stub defect; the `emit_and_die` verdict is correct *when the write genuinely fails*. |
| Global `git grep` sentinel banning `printf \|` in infra scripts | Over-broad: pipe-into-stub is fine when the stub drains; the defect is stub fidelity, not the pipe shape. |
| Fix only `mon_prepare`'s stub (the observed site) | Leaves the identical latent flake in `run_case` suites and staging's whole-script runs — same edit, next month's flake. The census was cheap; the sweep is the write-boundary rule applied. |

## Architecture Decision (ADR/C4)

None required — a defect-fidelity fix to test stubs plus pagination on
existing API reads; no boundary move, no new substrate, no ADR reversal.
C4 check: no new external actor, external system, container, or changed
access relationship is introduced (the probe/heartbeat/Sentry topology is
unchanged; the only new "system" interactions are additional `gh api` page
reads of an already-called endpoint). A competent engineer reading the
existing ADRs + C4 would not be misled after this ships.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #9245: `gh issue view 9245 --json state` → `OPEN`, no
  `closedByPullRequestsReferences`. Premise holds.
- `luks-monitor.sh:176` verified on-branch: the `printf '%s' "$key" |
  cryptsetup luksOpen --test-passphrase --key-file -` escrow feed — the
  line number and construct in the issue match the code.
- `scripts/regenerate-shard-manifest.py:148`,
  `.github/workflows/web-platform-release.yml:~620` verified; the deferred
  nit is recorded in
  `knowledge-base/project/specs/feat-one-shot-9232-duration-aware-shard-packing/session-state.md`
  ("Skipped: --paginate on artifacts-list").
- ADR corpus (`knowledge-base/engineering/architecture/decisions/`): no ADR
  decides stub stdin fidelity or `gh api` pagination policy; the proposed
  mechanisms sit in no ADR's rejected-alternatives table.
- The issue's *hypothesis* ("heartbeat push race") is stale vs. the code —
  the heartbeat push is `curl` with no stdin pipe. Corrected in the
  Reconciliation table; acceptance arm 2 ("test harness waits for the
  reader") is the implemented arm.

### Property List (Phase 0.6b)

- P1: `luks-monitor.test.sh`'s verdict is decided by probe behavior, never
  by scheduler timing (no `write error` in `MON_OUT`; no early die).
- P2: `WL_LUKS_OPEN_RESULT` still reflects `cryptsetup`'s rc (both
  directions testable via `MON_ESCROW_RC`).
- P3: every `gh api …/artifacts`/`…/jobs` list site reads all pages;
  truncation can never masquerade as a dead leg or a missing release
  artifact.
- P4: no new credential exposure surface (no temp-file here-strings) and
  no hang on unpiped stdin.

### Cut List (Phase 0.6b)

- "EPIPE tolerance in the monitor's push" (issue arm 1, literally) → P1 —
  but the failing write is the escrow feed, not the push; a heartbeat-side
  tolerance buys no property in the list. Cut; the faithful-reader drain
  (already the repo's convention — four sibling stubs drain) covers P1.
- Monitor-side `PIPESTATUS` verdict capture → P2 — property already held:
  `pipefail`'s fold is correct when the reader is faithful. Cut; recorded
  under Alternatives.

### Repo research (inline — no subagent spawn available)

- `workspaces-luks-harness.sh`: `mon_prepare` (`:657`) writes per-case PATH
  stubs; `bin/cryptsetup` (`:686`) exits on `luksOpen` without reading —
  the confirmed flake. `run_case` (`:215`) defines `cryptsetup()` (`:362`)
  with the same non-draining fallthrough for `luksFormat`/`luksOpen`.
- `luks-monitor.sh`: `set -uo pipefail` (`:19`); escrow feed `:176`; the
  only stdin pipe into a stubbed binary. `cryptsetup status | sed | head
  -1` (`:164`) is safe — `head` is last and the producer emits ≤1 matching
  line.
- Stub census (drain status): faithful — `inngest-luks-cutover.test.sh:185`
  (`_k="$(cat)"` + passphrase verify), `git-data-luks-reopen.test.sh:466` and
  `workspaces-boot-unlock.test.sh:1100` (`cat > "$FX/key_seen"`),
  `registry-luks-escrow.test.sh:~104` (`cat > "$KEYSEEN"` + argv pin).
  Non-draining — the three sites in Files to Edit.
- `deploy-script-tests` (`infra-validation.yml:522`): `K=4` matrix, runs
  `run-registered-suites.sh` at `-P4` — the contention context. Advisory
  leg (not merge-blocking) but red legs cost cycles and mask regressions.
- `gh_api` (`web-platform-release.yml:375`): 3-attempt retry wrapper over
  `timeout 20 gh api`; `--paginate` passes through positionally.
- Pagination idiom: `actions-queue-health.sh:148-153` — `--paginate` with
  NO `--jq`, piped to `jq -s` (per-page `--jq` yields multi-doc output).
  Same shape pinned by `actions-queue-health.test.sh:379-383` (calls.log
  `--paginate` assert — the model for the ci-leg-balance assert).
- Stage-b dogfood parity: `constraint-scaffold.sh:568` emits
  `fix-constraints-stage-b.yml` via `sed __TARGET_DIR__`; `parity.test.sh`
  #5 asserts the repo-root body == substituted template → both files get
  the same edit.
- Suite runtime: `bash luks-monitor.test.sh` ≈ 9 s, 78 asserts (measured
  2026-09-30).

### Applicable learnings

- `2026-09-23-my-verdict-rode-on-a-pipeline-status…` — verdict must not
  ride a pipeline's exit status under pipefail; same class.
- `2026-07-28-a-ten-run-sample-said-unreachable…` — the pipe buffer narrows
  the EPIPE window but never closes it; 10 greens ≠ fixed. Hence the
  deterministic wire assert (P2) instead of relying on run-count luck.
- `2026-03-24-gh-api-paginate-concatenated-arrays` — `--paginate` +
  `jq -s` idiom; single-page verification does not validate pagination
  (hence the page-2 fixture).
- `2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire` —
  pin delivery, not just argv: the `$CALLS.escrow-stdin` capture assert.
- `2026-09-28-an-ssh-drop-without-a-pty-is-sigpipe…` — `$?`/pipeline
  semantics around SIGPIPE/EPIPE.

### External research

Skipped — strong local context: the defect class is fully determined by
in-repo code, the fix idiom is already the repo convention (draining
stubs + `--paginate`|`jq -s`), and no external dependency behavior is in
doubt.

## Sharp Edges

Verification pass over `plan/references/plan-sharp-edges.md` (read at
finalization per Phase 6.5):

- **Verdict on a pipeline status** — addressed head-on: the plan fixes the
  reader rather than the verdict, and documents why `PIPESTATUS` capture
  was rejected.
- **Assert anchors not bare tokens** — the wire assert reads a capture
  FILE's content (`$CALLS.escrow-stdin` == `k`), not a grep of call argv;
  the `--paginate` assert greps `calls.log` lines filtered to `/artifacts`
  endpoints (mirrors `actions-queue-health.test.sh`'s shape).
- **Fixtures synthesized only** — all fixtures (page-split artifacts,
  `MON_KEY=k`) are synthesized; no recorded prod data.
- **Single-page verification trap** — the regression fixture forces
  multi-page (101 artifacts, target only on page 2).
- **Anti-vacuity** — both new guards carry mutation-matrix rows including
  a dispatch row and a must-PASS non-canonical input.
- **Generated-artifact parity** — stage-b is a generated file: the template
  is edited and the dogfood copy kept byte-equal (parity.test.sh #5 is the
  mechanical check).
- **Fail direction inventory** — every truncation site's failure direction
  was enumerated before folding (silent-skip and permissive sites fixed;
  guarded and alarm-direction sites dispositioned).

## References & Research

- Issue: #9245 (this fix closes it); deferred nit from #9232's review —
  `knowledge-base/project/specs/feat-one-shot-9232-duration-aware-shard-packing/session-state.md`
  ("performance-oracle … Skipped: --paginate on artifacts-list").
- Failed runs: 36641696218 job 109655567788; 36643215007 job 109660549623.
- Sibling green run: 36641076266 (same leg, minutes later — the
  intermittency signature).
- Overlap-checked: #3220 (acknowledged — disjoint section of the same
  workflow file).
- Idiom sources: `scripts/actions-queue-health.sh:148-153`;
  `actions-queue-health.test.sh:379-383`;
  `scripts/main-push-duplicate-skip.sh:61-70` (`total_count` guard);
  faithful-drain stubs at `inngest-luks-cutover.test.sh:185`,
  `git-data-luks-reopen.test.sh:466`, `workspaces-boot-unlock.test.sh:1100`,
  `registry-luks-escrow.test.sh:~104`.
