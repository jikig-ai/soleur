---
title: "fix(infra): make the rehearsal's dockerd deny probe measure the steady state and record why it fails"
date: 2026-10-09
slug: rehearse-dockerd-hosts-cache-race
branch: feat-one-shot-9799-rehearse-dockerd-hosts-cache-race
issue: 9799
lane: single-domain
type: fix
---

# fix(infra): make the rehearsal's dockerd deny probe measure the steady state and record why it fails

Ref #9799 (tracker item 5). No close keyword: the tracker stays open for items 1 and 4.

## Enhancement Summary

**Deepened on:** 2026-10-09 (focused pass: the plan is a ~60-line CI-probe fix, so the halt gates and live
verifications ran inline rather than as a 40-agent fan-out; the plan-review panel had already run four
reviewers).
**Sections enhanced:** Scope Check (added; was missing, 4.12), Observability discoverability command
(re-shaped, 4.7), Research Insights (live verifications below).

### Key Improvements
1. Scope Check added: 11 asks mapped; the new test suite surfaced as the one unrequested item and queued as a
   User-Challenge in `decision-challenges.md` (ask 4 is conditional on a suite that does not exist).
2. Observability probe changed from the suite (suite-shaped, trips the Check 10 detection) to one anchored grep
   with a literal expected output.
3. Cited facts re-verified live (below).

### Gate results
- 4.6 User-Brand Impact: present, threshold `none`, scope-out bullet present for the `apps/*/infra/` path. Pass.
- 4.7 Observability: five fields present; command verb `grep` is allowlisted, no SSH, under the 15 s cap,
  `expected_output` is a literal. Pass.
- 4.8 PAT-shaped variables: none. 4.9 UI wireframe: no UI surface, skipped. 4.10 Encryption posture: no new
  persistent store or cross-component connection ("image store" here means the runner's docker image store
  setting under test), skipped.
- 4.11 Guard Contract: `lint-guard-contract.py` green (1 guard entry); assembly names the chokepoint
  (`assert_dockerd_denied`), matrix has 5 rows including an own-dispatch row (M1) and a reorder row (M3).
- 4.12 Scope Check: present, one unfenced occurrence, no `unmapped`, every `inferred` row justified.
- 4.5 Network-outage: the plan's words `unreachable`/`timeout` appear only as probe results on a throwaway
  runner; no SSH or firewall hypothesis is proposed, so no deep-dive. 4.55 Downtime: no serving surface.

### Live verifications (this pass)
- PR #9805: MERGED, "zot claim out of ci-deploy.sh and fan-out HMAC key off argv" (matches tracker items 2-3).
- Issue #8881: OPEN, the K=6 -> K=7 rebalance review (the overlap acknowledged above).
- ADR-252 exists: `ADR-252-infra-suite-registration-is-presence-and-deploy-script-tests-is-a-matrix.md`.
- Go `net/hosts.go` at go1.24.0 (fetched from raw.githubusercontent.com): `cacheMaxAge = 5 * time.Second`;
  `readHosts` returns early on `now.Before(hosts.expire)`, otherwise stats and compares `mtime` and `size`.
- `docker info --format '{{.HTTPProxy}} {{.HTTPSProxy}} {{.NoProxy}} {{json .RegistryConfig.Mirrors}}'` runs on a
  current local docker; the plan still requires one best-effort check on each CI leg (Phase 3 step 5).
- Failing run timeline (run 37863203385 attempt 1): `docker 28.0.4 driver=overlay2` printed 00:08:40.87Z, the
  deny step started in the same second, `::error::rehearse[classic]: dockerd could still pull ...` at
  00:08:42.98Z. Attempt 2 conclusion: success.
- `zot-image-rehearse.sh` is referenced by no `triggers_replace`; the only `.github/workflows` mention is the
  `paths:` filter and the job step in `zot-image-mirror.yml`, which this plan does not edit.

## Overview

`zot-image-rehearse.sh <store>` (CI job `rehearse` in `.github/workflows/zot-image-mirror.yml`)
applies the rendered ghcr.io hosts-file deny and then proves three things: `getent` resolves ghcr.io only to
`0.0.0.0`/`::`, `curl` cannot reach it, and `docker pull` of the upstream ref fails. Run 37863203385
attempt 1 (`rehearse (classic)`) failed the third probe with "dockerd could still pull from ghcr.io after
the deny" and passed on attempt 2. The probe sends the pull's output to `/dev/null`, so the run recorded
nothing about why the pull succeeded.

This plan changes only the rehearsal probe (one script plus one new offline suite):

1. **Make a recurrence diagnosable.** The dockerd probe captures the pull output and, when the pull succeeds
   (the deny failed), prints it with the docker version, the hosts file mtime/size/age, whether the image was
   already in the store, the daemon's proxy/mirror fields and its unit environment. A refused pull prints one
   line with the rc and the last output line, so a pass is also evidence.
2. **Remove the suspected race.** Sleep 7 s (5 s Go cache + 2 s margin) immediately before the dockerd pull,
   inside one function that is the script's only pull site.
3. **Pin it offline.** A new `zot-image-rehearse-probe.test.sh` under `apps/web-platform/infra/` drives that
   function against PATH shims: five rows and four mutations.

## Hypothesis, stated as one (not a measured cause)

Go's `net` package caches the hosts file for 5 s: `src/net/hosts.go` has `cacheMaxAge = 5 * time.Second`, and
`readHosts` returns early when `now.Before(hosts.expire)` without a stat (verified against go1.24.0 source
on 2026-10-09). If dockerd resolved any name through the Go resolver within 5 s before the deny was appended,
its next ghcr.io lookup inside that window would use the old table and reach the real address.

What supports it: the failing run's timeline (log of run 37863203385 attempt 1) shows `docker info` ready at
00:08:40.87Z, the deny applied in the same second, and the failure at 00:08:42.98Z, so the whole deny step,
including the pull, took about 2 s after a daemon (re)start. `getent` and `curl` (libc, a different process)
saw the deny; only dockerd did not. Attempt 2 passed.

What is NOT established: nothing on the runner recorded a dockerd read of the hosts file, and nothing
recorded where the pull connected. The hypothesis also needs a dockerd lookup shortly before the deny, and no
step in this script performs one (the anchor uses curl; `docker info` does not resolve names); a lookup at
daemon start (for example `localhost` or the hostname) would do, but that is unmeasured. Other explanations that fit the same single observation and that the new
diagnostics are designed to separate:

| Alternative | Discriminating field in the new failure output |
|---|---|
| Hosts cache (the working hypothesis) | hosts `age_s` < 5 at probe time; with the wait in place a recurrence **refutes** it |
| dockerd is behind an HTTP(S) proxy or registry mirror, so name resolution happens elsewhere | the daemon unit's environment and the `docker info` proxy/mirror fields |
| The digest was already in the local store and the "pull" was satisfied locally | `image_present_before=yes` |
| The pull raced a daemon restart, or an unrelated pull succeeded for another reason | pull output tail and the docker version |

If the fix does not hold (a recurrence with age >= 7 s), the diagnostics above are the next step; do not
extend the wait.

## Research Insights

**Premise validation.** Issue #9799 is open and item 5 is the addendum this plan targets (items 2 and 3 are
delivered by PR #9805; items 1 and 4 are untouched here). The cited path exists on `origin/main`:
`apps/web-platform/infra/zot-image-rehearse.sh`, with the deny step at lines 97-108 and the discarding probe at
line 105. The cited run exists and its attempt-1 log shows the quoted timeline. The ADR corpus was not
searched for the mechanism because the change is a test-probe wait, not an architectural mechanism.

**Property List.**
1. The rehearsal's dockerd probe measures the deny in steady state, not within the resolver's cache window.
2. When the probe fails, the log carries enough to separate a stale resolver cache from a persistent leak.
3. The wait and the capture are pinned by an offline suite, so neither can be dropped silently.

**Cut List.** (mechanism -> property -> what already covers it)
- Retry-until-denied loop on the pull -> would make a persistent leak look like a pass after N tries -> cut;
  a single probe after a fixed wait keeps "denied" meaning "denied now".
- mtime-derived wait, journal tail, resolver view, 11-row suite and 6-mutation battery -> cut by the plan-review
  panel (see Review Revisions).
- Re-probe after a second wait on failure -> property 2 is already served by the age/proxy/store
  fields -> cut; it needs an image-removal step whose behaviour on a digest ref is unverified.
- Asserting the pull's error text (for example "connection refused") -> would add a new flake source across
  three docker builds (28.x classic/containerd, Ubuntu docker.io) -> cut; the reason line is printed, not
  asserted.
- A separate sourced library file -> property 3 only needs the functions to be sourceable -> cut; a source
  guard inside the script avoids adding a file to `zot-image-mirror.yml`'s `paths:` filter.
- Waiting on dockerd's own read time -> not observable from outside the process -> cut; waiting from the
  hosts file mtime bounds it from above.

**Capability checks (grepped, authority named).**
- `zot-image-rehearse.sh` is not read by any `triggers_replace` (grep of `apps/web-platform/infra/*.tf`: only a
  prose comment in `zot-registry.tf` names `zot-image-oci-archive.sh`). Editing it fires no registry replace
  and no web-host apply.
- No test suite for `zot-image-rehearse.sh` exists. The only suite that opens it is `web-ghcr-deny.test.sh`
  (its census), which skips comment lines and `.test.` files and flags a code line matching its deny-loop
  or hosts-write regexes; the new code must not write the hosts file and must not contain a
  `for h in <ghcr names>; do` loop.
- Suite registration is by filesystem presence (ADR-252): `run-registered-suites.sh` derives the set from
  `git ls-files` under `apps/web-platform/infra/`, and `.github/scripts/test/test-infra-suite-registration.sh`
  validates `suite-shard-legs.tsv` rows. A tsv row is optional (untabled suites hash-fall-back into a leg).

**Does the real registry host share the ordering? No (read of `cloud-init-registry.yml`, no edit).**
`docker.io` arrives in `packages:` (the daemon starts at install, before `runcmd`); `runcmd` writes the deny
first, and later reaches the docker enable-now entry (the daemon is already active, so there is no restart);
the boot path is `zot-image-fetch.sh` (curl download plus `docker load`) followed by `docker run` of the
loaded ID. There is no `docker pull`, no dockerd restart after the deny, and no dockerd resolution of
ghcr.io on that host; the heartbeat's `ghcr_blocked` uses `getent` (libc), which has no 5 s cache. The
registry runbook (`registry-host-replace-dispatch.md`) names no pull-after-deny sequence. So the race is a
property of the rehearsal's probe only, and the comment in the script will say so. The web-host copies of the
deny (`cloud-init.yml`, `server.tf`) run against long-lived daemons and were not examined; out of scope.

**Learnings applied.** `2026-09-30-my-deny-guards-proved-one-template-arm-and-missed-one-line-blocks.md`
(item 10: match the construct, never a token that a string can name; relevant to the census interaction above);
`2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` (a probe must be shown to fail on
the thing it detects; drives the harness rows below).

## Research Reconciliation: tracker text vs. code

| Tracker / brief claim | Reality | Plan response |
|---|---|---|
| "wait out the cache before the probe" | Correct as a remedy, but the cache window is anchored on dockerd's last read, which is unobservable | Anchor on the hosts mtime: any read before the write expires before mtime+5 s |
| "capture the pull output" | The probe is `timeout 120 sudo docker pull ... >/dev/null 2>&1` inside an `if` | Capture with `2>&1` into a variable; keep the `timeout 120` |
| Deny "landed ~2 s after the restart" | Confirmed by the run log (deny step 00:08:40.87Z, error 00:08:42.98Z) | Kept as the evidence line; flagged as consistent with, not proof of, the cache |
| "check whether the real host has the same ordering" | It does not (see above) | Recorded here and in the PR body; no change to `cloud-init-registry.yml` |

## Files to Edit

- `apps/web-platform/infra/zot-image-rehearse.sh` — lines ~25-40 (helpers + source guard, defined before any
  side effect) and lines ~97-108 (the deny step). Header comment gets a line stating the probe waits out the
  resolver cache and that this is the rehearsal's probe, not a claim about the registry host.

## Files to Create

- `apps/web-platform/infra/zot-image-rehearse-probe.test.sh` (mode 755) — offline suite.
- `knowledge-base/project/specs/feat-one-shot-9799-rehearse-dockerd-hosts-cache-race/tasks.md` (this plan's tasks).

Registration is by presence; `suite-shard-legs.tsv` / `suite-durations.tsv` rows only if the registration gate
asks for them, generated by the incremental regenerator.

**Forbidden / untouched (a registry replace or web-host apply would fire):** `terraform_data.deploy_pipeline_fix`
trigger files, `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`. The fix needs none of
them (the rehearsal script is not a trigger input), so no stop condition applies.

## Open Code-Review Overlap

Queried open `code-review` issues against the three paths above.
- `zot-image-rehearse.sh`: none.
- `.github/workflows/zot-image-mirror.yml`: none (and this plan does not edit it).
- `suite-shard-legs.tsv`: #8881 (test-scripts K=6 -> K=7 rebalance review). **Acknowledge:** a different
  concern (shard balance for another group); this plan adds no row unless the registration gate asks. The
  scope-out stays open.

## Implementation Phases

### Phase 1 — tests first (cq-write-failing-tests-before)

Create `zot-image-rehearse-probe.test.sh`; run it and see it fail (the function does not exist yet).

Harness (sibling-suite conventions): `set -uo pipefail`, `TMPDIR` default, `mktemp -d` scratch under an
`assert_fixture_dir` check, an instrument self-test of `pass()`/`fail()` before anything is measured, a final
ledger line `zot-image-rehearse-probe: N passed, M failed`, and a floor (fewer than the expected row count
fails, so a suite that sourced nothing cannot exit 0). Every fixture is synthesized
(cq-test-fixtures-synthesized-only).

Shims in a scratch `bin/` first on `PATH`, all appending to one call log: `sudo` (drops itself, `exec "$@"`),
`docker` (pull rc/output and `version`/`info`/`image inspect` answers from env), `sleep` (logs its argument,
does not sleep), `systemctl` (prints a fixed line). The hosts file is a scratch file; `stat`, `date` and
`touch` are real. The script under test is loaded with `source` inside a subshell, followed by `set +e`
(sourcing leaks the script's `set -euo pipefail`), so a row sees the function's real return code.

Rows (offline, well under 2 s):

| # | Input | Expect |
|---|---|---|
| 1 | pull exits 1 with `dial tcp 0.0.0.0:443: connect: connection refused` | returns 0; call log shows `sleep 7` before the one `docker pull` |
| 2 | pull exits 0 and prints a unique marker line | returns 1; output carries the marker, the docker version string, the hosts mtime and age, `image_present_before=`, and the proxy/mirror fields |
| 3 | pull exits 0 with empty output (must still be a failure) | returns 1 |
| 4 | pull exits 1 with a different message, `no such host` (must-PASS, not the canonical) | returns 0 |
| 5 | static, over `zot-image-rehearse.sh`: exactly one `docker pull` line, no `/dev/null` on it, and the deny application (`sudo sh "$W/deny.sh"`) comes before the `assert_dockerd_denied` call | pass |

Mutation battery (a `sed` copy of the script is sourced instead of the real one; each must turn the named
rows RED): M1 delete the `sleep` (row 1); M2 restore `>/dev/null 2>&1` on the pull (row 2); M3 move the
`sleep` after the pull (row 1: the order read); M4 return 0 on a successful pull (rows 2, 3). Harness row: a
`docker` shim that logs nothing turns row 1 red rather than green.

### Phase 2 — the fix in `zot-image-rehearse.sh`

Helpers go directly after `set -euo pipefail` and before `STORE=` parsing, then the source guard:

```bash
# Go's net package caches the hosts file for 5 s without a stat (src/net/hosts.go cacheMaxAge); +2 s margin.
# This is the REHEARSAL's probe, not a claim about the registry host: that host starts dockerd before the
# deny, never restarts it after, and never pulls from ghcr.io.
HOSTS_CACHE_WAIT_S=7

assert_dockerd_denied() {  # <hosts-file> <ref>: 0 = dockerd cannot pull <ref>; 1 = it could (diagnostics printed)
  local hosts="$1" ref="$2" out rc present
  sleep "$HOSTS_CACHE_WAIT_S"
  present=no; sudo docker image inspect "$ref" >/dev/null 2>&1 && present=yes
  out="$(timeout 120 sudo docker pull "$ref" 2>&1)" && rc=0 || rc=$?
  if (( rc != 0 )); then echo "dockerd pull refused (rc=$rc): $(printf '%s\n' "$out" | tail -n 1)"; return 0; fi
  # pulled: print the evidence (every diagnostic best-effort, `|| true`)
  ...  pull output `tail -n 20`, docker version, `stat` mtime/size and age_s of "$hosts", image_present_before=$present,
  ...  `docker info -f` proxy/mirror fields, `systemctl show docker -p Environment -p DropInPaths`
  return 1
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0   # sourced by the offline suite: helpers only
```

Call site (replaces lines 105-107): `assert_dockerd_denied /etc/hosts "ghcr.io/project-zot/zot-linux-amd64@sha256:$D" || die "dockerd could still pull from ghcr.io after the deny (diagnostics above)"`.

Why unconditional rather than mtime-derived (panel decision): the deny is always freshly applied on a new
runner, so an age computation only saves seconds, and it was the source of two fail-open paths (see Review
Revisions). The sleep sits inside the function, immediately before the pull, so the pull cannot be reordered
ahead of it without moving a line in the one chokepoint.

Constraints: the function is called under `||`, so `set -e` is OFF inside it; every step that must stop the
function uses an explicit `return`, and `rc` is captured with `&& rc=0 || rc=$?`. No diagnostic may reference
`$STORE`, `$W` or `dk` (unset under `set -u` when sourced). Nothing writes the hosts file and no code line
carries a deny-loop header or `>` / `tee` / `install` toward `/etc/hosts` (census in `web-ghcr-deny.test.sh`;
`2>&1` is safe). Bound the output (`tail -n 20`).

### Phase 3 — register and verify (targeted local only; CI carries the broad battery)

1. `bash apps/web-platform/infra/zot-image-rehearse-probe.test.sh` green; re-run each mutation to see it red.
2. `shellcheck` on the two files.
3. `bash apps/web-platform/infra/web-ghcr-deny.test.sh` (census over the edited script; SKIPs locally without
   terraform, fails closed in CI): read a SKIP honestly.
4. Registration is by presence (ADR-252), so no tsv row is required (untabled suites hash-fall-back into a
   leg). Run `bash .github/scripts/test/test-infra-suite-registration.sh`; add rows only if that gate asks for
   them, via `python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write` (diff must be the
   new row only).
5. Do not run the full `rehearse` locally. CI `rehearse (classic|containerd|host)` on the PR is the live
   verification. Before relying on the new `docker info -f` format string, run it once on the PR's three legs
   (best-effort, `|| true`, so a bad template prints nothing rather than failing the step).

### Phase 4 — PR

PR body: `Ref #9799` (item 5), no close keyword next to an issue number. State plainly: the cache is a working
hypothesis, not a measured cause (and what is unexplained: the dockerd read that would have to precede the
deny); what the new output shows if it recurs; the real-host ordering finding (not shared;
`cloud-init-registry.yml` unchanged); the one path not examined (web-host deny copies). No new issues filed.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "make the dockerd probe capture its output and print it (plus the docker version and the hosts file mtime) on failure" [brief] | Phase 2 (`assert_dockerd_denied` capture and diagnostics); Files to Edit: `zot-image-rehearse.sh` | mapped |
| 2 | "remove the race by waiting out the 5 s cache (or otherwise making the probe measure the steady state) and say plainly in a comment that this is the rehearsal's probe, not a claim about the registry host" [brief] | Phase 2 (`HOSTS_CACHE_WAIT_S=7`, `sleep` before the pull, the comment) | mapped |
| 3 | "check cloud-init-registry.yml and the registry runbook for whether the real host has the same ordering (daemon restart then deny then a ghcr pull) and, if it does, note it in the PR rather than widening scope" [brief] | Research Insights (real-host ordering finding, no edit); Phase 4 (PR body) | mapped |
| 4 | "add offline test row(s) in the existing zot-image-rehearse test suite if one exists (find it under apps/web-platform/infra/ and check how it is registered)" [brief] | Phase 1 and Files to Create: `zot-image-rehearse-probe.test.sh`; Phase 3 step 4 (registration) | mapped (condition not met: no such suite exists; see provenance row 3) |
| 5 | "Do not edit trigger files of terraform_data.deploy_pipeline_fix, cloud-init-registry.yml, zot-registry.tf, variables.tf or server.tf" [brief] | Files to Edit (none of them); acceptance criterion on `git diff --stat` | mapped |
| 6 | "This is a working hypothesis, not a measured cause: the plan must say so and must make a recurrence diagnosable." [brief] | `## Hypothesis` section and its alternatives table; Phase 2 diagnostics | mapped |
| 7 | "Use `Ref #9799` in the PR body, no close keyword next to an issue number" [brief] | Phase 4; acceptance criteria | mapped |
| 8 | "Net-issue-flow: file no new issues." [brief] | Phase 4 (no issues filed); Cut List records the one deferred idea inline instead | mapped |
| 9 | "No web-1/web-2/git-data host contact; no apply workflow dispatch." [brief] | Infrastructure (IaC) section; Post-merge: none | mapped |
| 10 | "Rely on CI for the broad battery (the machine is contended); keep targeted local checks only." [brief] | Phase 3 (targeted local only) | mapped |
| 11 | "The user-brand-impact threshold for this CI-only rehearsal probe is expected to be `none` (state the reason)." [brief] | `## User-Brand Impact` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `zot-image-rehearse.sh`: capture and diagnostics | "capture its output and print it (plus the docker version and the hosts file mtime) on failure" (ask 1) | asked |
| Edit `zot-image-rehearse.sh`: 7 s sleep and comment | "waiting out the 5 s cache" (ask 2) | asked |
| Diagnostics beyond version and mtime: `image_present_before`, proxy/mirror fields, daemon unit environment | "must make a recurrence diagnosable" (ask 6) | asked |
| Create `zot-image-rehearse-probe.test.sh` | — | inferred — justification: ask 4 is conditional on a suite existing and none does, so the literal ask is to add nothing; without a test the sleep and the output capture can be dropped silently, which the plan's property 3 forbids. Persisted as a User-Challenge in `decision-challenges.md` for the operator to confirm or cut. |
| Source guard before `STORE=` parsing | — | inferred — justification: the only way to run `assert_dockerd_denied` offline without a new library file or a workflow path-filter edit; it exists solely to serve the suite above and goes if the suite goes. |
| Registration rows in `suite-shard-legs.tsv` / `suite-durations.tsv` | "check how it is registered" (ask 4) | asked (conditional: only if the registration gate requires them) |
| Real-host ordering check (read-only) | "check cloud-init-registry.yml and the registry runbook" (ask 3) | asked |
| `## Guard Contract`, `## Observability`, `## Review Revisions` sections | — | inferred — justification: required plan-skill gates (Phase 2.9, 2.12) for a plan whose Files to Edit sit under `apps/*/infra/` and whose deliverable includes an assertion-based CI probe. |

### Split Assessment

- Subsystems touched: 1 — apps/web-platform (infra), plus knowledge-base plan/tasks
- Planned files: 2 product files (+ at most 2 generated tsv rows) | Estimated changed lines: ~220 (about 60 in the script, about 150 in the suite)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `zot-image-rehearse.sh` no longer sends the dockerd pull's output to `/dev/null`; on a successful pull
  it prints the pull output tail, `docker version`, hosts mtime/size/age, `image_present_before`, the
  proxy/mirror fields and the daemon unit environment, then fails through `die`.
- [ ] The probe sleeps 7 s immediately before the pull, inside the single `assert_dockerd_denied` chokepoint,
  and a comment says this is the rehearsal's probe and that the registry host does not share the ordering.
- [ ] `zot-image-rehearse-probe.test.sh` exists (mode 755), passes, and each of M1-M4 turns the named rows red.
- [ ] `web-ghcr-deny.test.sh` and `test-infra-suite-registration.sh` green.
- [ ] `git diff origin/main --stat` lists only the rehearse script, the new suite, any generated tsv row, and
  this plan/tasks. None of `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`, or any
  `deploy_pipeline_fix` trigger file appears.
- [ ] CI `rehearse (classic)`, `rehearse (containerd)` and `rehearse (host)` green on the PR.
- [ ] PR body carries `Ref #9799`, the hypothesis wording and the real-host finding; no close keyword.

### Post-merge

None. No apply, no workflow dispatch, no host contact. #9799 stays open for items 1 and 4; item 5 is reported
in a tracker comment after merge (a comment, not a close).

## Test Scenarios

The five rows and four mutations in Phase 1. Live scenario: the next `rehearse` runs on real runners; a green
run now prints one `dockerd pull refused (rc=..)` line per leg, the first recorded evidence of what a denied
dockerd pull looks like on each docker build.

## Review Revisions (plan-review panel, 2026-10-09)

Applied as Mechanical (eng-panel correctness and simplification; none drops operator-requested scope: the
brief's items (1)-(3) all remain):

- R1 (Kieran P1, confirmed by execution): `age=$(( $(date +%s) - $(stat -c %Y f) )) || return 1` does not
  fail closed: a failed `stat` is an arithmetic syntax error that aborts the enclosing `||` list, so the probe
  would be skipped and the script would print "denied". Resolved by removing the age arithmetic.
- R2 (Kieran P1): a function called under `||` runs with errexit off, so a bare helper call can fail and the
  pull still runs. Resolved with explicit `return`s and `&& rc=0 || rc=$?` capture (Phase 2 constraints).
- R3 (DHH, code-simplicity, CTO): mtime-derived wait, `date`/`stat` shims, 11 rows and 6 mutations are out of
  proportion for a CI-only probe. Replaced by an unconditional 7 s sleep, 5 rows and 4 mutations.
- R4 (DHH, code-simplicity): diagnostics beyond the brief trimmed: journal tail (CTO: low signal without
  daemon debug logging), resolver view and ghcr hosts lines dropped (the earlier `getent` already proves the
  hosts file). Kept: pull output, docker version, hosts mtime and age (the brief), plus `image_present_before`,
  the proxy/mirror fields and the daemon unit environment (the three discriminators of the alternatives table).
- R5 (code-simplicity): the success-path baseline is folded into a single line. Kept.
- R6 (Kieran P2): sourcing leaks `set -euo pipefail`; rows `set +e` after the source; diagnostics must not use
  `$STORE`, `$W`, `dk`.
- R7 (Kieran P2): the hypothesis needs a dockerd hosts read shortly before the deny, and no step in this
  script performs one (the anchor uses curl). The hypothesis section now says so. `localhost` or a
  hostname lookup at daemon start would qualify, but that is unmeasured.
- Declined: dropping the new suite for a static assertion in `web-ghcr-deny.test.sh` (code-simplicity): a
  static grep is the satisfiable-by-a-stub shape the 2026-08-04 learning warns about; the behavioral rows
  (output visible on success, sleep before pull, return code) are the point. Row 5 keeps the static check as
  a supplement only. Skipping the tsv row: adopted (presence is registration).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing. The change is inside a CI-only rehearsal script on a
throwaway GitHub runner; a broken probe turns a PR check red or leaves the registry boot unrehearsed, and no
user-facing route, data path or deployed host runs this file.
**If this leaks, the user's data is exposed via:** no vector. The diagnostics print the pull output, docker
version, hosts-file metadata and proxy settings of an ephemeral runner; no credential, user datum or
production value is read (the daemon unit's environment is printed, not the process environment, and a hosted
runner's docker unit carries no secrets).
**Brand-survival threshold:** none

threshold: none, reason: CI-only rehearsal probe on an ephemeral runner; the diff touches `apps/web-platform/infra/` but changes no deployed artifact, no host and no user-facing surface.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI test-probe change in infrastructure tooling. Product/UX gate
skipped: no UI-surface file in Files to Edit/Create. Not a regulated-data surface (no schema, auth, API route,
or `.sql`); no new store or connection, so no encryption-posture section; no architectural decision, so no
ADR/C4 change.

## Infrastructure (IaC)

No new infrastructure. The edited script is not a Terraform trigger input.
- Terraform changes: none.
- Apply path: none (no apply, no replace, no host contact).
- Distinctness / drift safeguards: not touched; the five forbidden files are unchanged and the acceptance
  criteria assert it from the diff.
- Vendor-tier reality check: no vendor resource involved.

## Observability

The surface is a CI job, which the operator can inspect without SSH. The local probe is deliberately the
smallest command that shows the fix is in place (one anchored grep, well inside Check 10's 15 s cap); the offline
suite is the test of the behaviour, not the discovery command.

```yaml
liveness_signal:
  what: the `rehearse (classic|containerd|host)` matrix legs of zot-image-mirror.yml report a result, and each prints the "dockerd pull refused" line
  cadence: every pull request touching the registry boot path and every push to main touching the mirror inputs
  alert_target: the GitHub check status on the PR; the existing workflow-failure path for main
  configured_in: .github/workflows/zot-image-mirror.yml (job rehearse) and apps/web-platform/infra/zot-image-rehearse.sh
error_reporting:
  destination: the job log (::error:: annotation from die) with the diagnostics block immediately above it
  fail_loud: the step exits 1 through die; the matrix is fail-fast false so the other stores still report
failure_modes:
  - mode: dockerd resolves ghcr.io through a stale hosts cache
    detection: diagnostics show hosts age_s < 5 at pull time (cannot recur once the sleep is in place)
    alert_route: failed rehearse leg
  - mode: dockerd reaches ghcr.io by a path the hosts file does not govern (proxy, mirror, local image)
    detection: diagnostics show proxy/mirror fields or image_present_before=yes with age_s >= 7
    alert_route: failed rehearse leg
  - mode: the diagnostics themselves fail
    detection: every diagnostic is best-effort (`|| true`); the die message prints regardless
    alert_route: failed rehearse leg with a shorter block
logs:
  where: GitHub Actions job log for the run
  retention: GitHub's workflow-log retention
discoverability_test:
  command: grep -c '^HOSTS_CACHE_WAIT_S=7$' apps/web-platform/infra/zot-image-rehearse.sh
  expected_output: 1
```

## Guard Contract

### Guard 1 — dockerd deny probe measures the steady state and records its failure

**Property.** The rehearsal reports "dockerd cannot pull from ghcr.io" only from a pull issued at least 7 s
after the deny was applied, and reports "dockerd could pull" only together with the evidence to tell a stale
cache from a persistent leak.

**Assembly.** One chokepoint: `assert_dockerd_denied` is the only `docker pull` site in
`zot-image-rehearse.sh` and holds the only `sleep`; the call site is the single use of the
`die "dockerd could still pull ..."` message. Row 5 enumerates the script's `docker pull` lines and requires
exactly one, with no `/dev/null` on it, and the deny application before the call. The other docker calls in
the script (`dk run`, `dk image rm`, the load done by the rendered fetch) do not probe the deny and are outside
the property. A second pull site added later reddens row 5.

**Mutation matrix.**

| # | Mutation | Must go RED |
|---|---|---|
| M1 | delete the `sleep` (own dispatch: the probe still runs, with no wait) | row 1 |
| M2 | restore `>/dev/null 2>&1` on the pull | row 2 |
| M3 | move the `sleep` after the pull (reorder, not delete) | row 1 (reads call order) |
| M4 | return 0 on a successful pull | rows 2, 3 |
| M5 | add a second `docker pull` outside the function | row 5 |

Rows 1 and 4 are the second compliant member (a different denial message after the canonical one). Row 3 is
the must-fail input with no output.

**Harness rows.** A `docker` shim that logs nothing must turn row 1 red (an edit to the SUITE, not the guard);
rows 3 and 4 are must-PASS/must-FAIL inputs that are not the canonical. The suite's floor reddens a run that
sourced nothing.

**Anchor.** No stored value is compared to the thing it protects. The constant 7 is derived in the comment
beside it (5 s cache + 2 s margin) and row 1 asserts `sleep 7`, so lowering it to 5 or 6 reddens row 1.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan; this one
  states `none` with a reason because the diff touches an `infra/` path.
- Do not make the wait conditional on `STORE`: the host leg installs docker.io fresh and the classic and
  containerd legs restart the daemon.
- The census in `web-ghcr-deny.test.sh` reads the rehearse script: a code line (not a comment) containing a
  deny-loop header or a hosts write fails it. Keep the diagnostics read-only (`stat`, `ls`).
- The source guard must sit before `STORE=` parsing; placed after, `source` would hit the usage `exit 2`.
- PR body wording: no close keyword next to an issue number, and keep to the operator's excluded-wording note
  from the brief.
- If a recurrence shows the pull succeeding after the 7 s sleep, treat the cache hypothesis as refuted and read
  the diagnostics; do not raise the constant.
