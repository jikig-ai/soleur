---
title: "fix: egress gateway bootstrap post-bring-up TCP open races squid start"
type: fix
date: 2026-10-12
slug: egress-gw-tcp-open-bounded-retry
branch: feat-one-shot-10003-egress-gw-tcp-open-retry
issue: 10003
lane: cross-domain
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
---

<!-- closes: deliberately absent. #10003 closes only on post-merge evidence that BOTH hosts applied green
     (see "Post-merge verification"); the PR body uses `Ref #10003` until then (wg-use-closes-n-in-pr-body-not-title-to). -->

# fix: egress gateway bootstrap post-bring-up TCP open races squid start

## Overview

`apps/web-platform/infra/egress-gateway-bootstrap.sh` ends with a single liveness probe,
`timeout 5 bash -c "exec 3<>/dev/tcp/$GW_IP/$GW_PORT"`, issued in the same second as `docker run -d`
(or `docker restart`). `docker` reports the container started before squid has bound its listener, so
the probe is refused and the script dies with `did not answer a TCP open post-bring-up`. Both
`terraform_data.egress_gateway` (web-1) and `terraform_data.egress_gateway_web2` (web-2) fail at that
line on every push apply and are tainted in state.

The fix replaces the one-shot probe with a bounded poll (about 30 s, 1 s interval, fail-closed with
container state and the last log lines on timeout), keeps the check meaningful (squid that never
listens still fails the apply), and adds a behavioural test to `egress-gateway.test.sh`.

The issue (#10003) was filed about a web-2 port-22 `i/o timeout`. That symptom no longer reproduces,
so this plan re-scopes #10003 to the failure that is actually reddening the apply now.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issue | Reality (command that established it) | Plan response |
|---|---|---|
| #10003 title: web-2 `egress_gateway_web2` "times out on port 22" | Does not reproduce. Run 38228632851 (`headSha` 67ebbbeb4e46, created 2026-10-12T09:14:51Z): `terraform_data.egress_gateway_web2 (remote-exec): Connected!` at 09:16:38Z, ~1 s after the dial started, and `egress_gateway` connected at 09:16:38Z too. (`gh run view 38228632851 --log \| sed 's/\x1b\[[0-9;]*m//g' \| grep -E "Connected!"`) | Re-scope to the TCP-open race; comment the re-measure on #10003; do not touch the SSH/firewall layer (see `## Hypotheses`). |
| "both hosts fail at the end of the bootstrap with Connection refused within the same second" | Confirmed. web-2: `started soleur-egress-gw ... 172.31.100.2:8443` at 09:16:49.4818Z then `/dev/tcp/172.31.100.2/8443: Connection refused` at 09:16:49.4827Z and the `ERROR: gw ... did not answer` line at 09:16:49.4829Z. web-1: started 09:16:52.2462Z, refused 09:16:52.2491Z. (same `gh run view` log, grep `started soleur-egress-gw\|Connection refused\|did not answer`) | The race window is milliseconds on a fresh `docker run`; a one-shot probe cannot pass. |
| "an egress_gw_bridge action=rebuilt line in Better Stack" is the green evidence | Wrong for the NEXT apply. The rebuild already happened in run 38228632851 on both hosts (`rebuilt bridge soleur-egress0 (... gw_mode=nat-unprotected ...)` in the log) and bridge options are immutable, so the next run sees `nat-unprotected`, skips the rebuild arm and emits no `action=rebuilt` line (`egress-gateway-bootstrap.sh` lines 103-143: the logger call is inside the `MODE != nat-unprotected` branch). The gw container also already exists, so the next run takes the `docker restart` arm, not `docker run -d` (lines 167-188) — which races the same way. MEASURED: run 38229123048 (`0dc19ef389`, 09:24Z, the staged-env-files push apply) printed `restarted soleur-egress-gw (mounted config refreshed)` then `/dev/tcp/172.31.100.2/8443: Connection refused` then the `did not answer` ERROR on BOTH hosts, and no `rebuilt bridge` line. (`gh run view 38229123048 --log \| sed 's/\x1b\[[0-9;]*m//g' \| grep -E "egress-gw-bootstrap\]\|Connection refused"`) | Post-merge evidence is the apply log line `[egress-gw-bootstrap] OK: gateway up` for BOTH resources plus `egress_gw_probe result=ok`. An `action=rebuilt` line from 09:16Z (if it was shipped) is evidence of the earlier rebuild, not of this fix. |
| "the check races squid starting to listen" (hypothesis) | Supported, but not exclusive: a squid that crashes at start also yields refused. A refusal repeating for 30 s is the discriminator. | The poll's timeout path must report container state + log tail so crash-at-start is distinguishable from slow-start. |
| `server.tf` comment: "web-2's SSH route is slow (~70 s per dial …)" | Stale on 2026-10-12: web-2 connected in ~1 s in run 38228632851. | Out of scope (comment only; the 15m `timeout` is harmless headroom). Noted under Non-Goals, not edited here. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10003 is OPEN with no closing PR
(`gh issue view 10003 --json state,closedByPullRequestsReferences` -> `OPEN`, `[]`); runs
38228632851 (completed, `failure`) and 38229123048 (the staged-env-files PR apply for `0dc19ef389`) exist as cited.
Run 38229123048 was `in_progress` (not `queued`, as the brief says) at the start of planning and has since
**completed `failure` with the identical TCP-open error on both hosts** — so at plan time no apply is in flight,
but main moves: the pre-merge check is re-run at merge time, not trusted from here; the cited file/line
(`egress-gateway-bootstrap.sh:201-202`) exists on this branch's base. The ADR corpus mechanism check:
ADR-278 (open-web egress via a dedicated CONNECT gateway) governs the gateway; it says nothing about
the bring-up probe, so a bounded poll is not a rejected alternative. Stale premise: only the issue
title (port 22) and the "queued" state of run 38229123048. Nothing else.

**Property List (Phase 0.6b).**

- P1. A gateway that becomes ready within the poll window does not fail the apply.
- P2. A gateway that never becomes ready within the window still fails the apply (fail-closed, nonzero exit, existing `die` text preserved).
- P3. A failing check reports enough in the same apply log to tell slow-start from crash-at-start (container state + log tail).
- P4. The bounded wait is bounded: worst-case added latency is the budget, not unbounded.
- P5. The behaviour in P1-P4 is pinned by a test that goes red when the check regresses to a single probe or to a vacuous pass.

**Cut List (Phase 0.6b).**

- Fail-fast on `State.Status=exited` inside the loop -> buys faster failure only; the container runs with `--restart unless-stopped`, so a crash-looping squid flips between `running` and `restarting` and an `exited` test would be unreliable; the timeout diagnostics already buy P3. CUT.
- Pre-existing TCP probe helper shared with `web-git-data-probe.sh` / `git-data-liveness.sh` -> they each carry a one-line `/dev/tcp` use pinned by their own suites (`git-data-liveness.test.sh` S11 asserts it is the only `/dev/tcp` use in that file); a shared lib would couple three suites for one `bash -c` line. CUT.
- A systemd/Docker `HEALTHCHECK` on the gw container -> a different mechanism for the same property (P1/P2) that would also change the container's runtime contract (image is digest-pinned; `docker run` args are asserted by the drift guard). CUT.
- A longer one-shot `timeout` (e.g. `timeout 30`) -> does not help: ECONNREFUSED returns immediately (verified below), so a longer timeout still dies on the first refusal. CUT; this is the cheapest "fix" and the wrong one.
- Retrying the whole bootstrap at the Terraform layer (`remote-exec` retry) -> re-runs the bridge/subnet logic for a ms-scale race. CUT.

**Local falsification run (this session).** A socket that is `bind()`-ed but not yet `listen()`-ing
refuses immediately and a `listen()` afterwards connects:
`python3 -I bnl.py 2 &` (bind, sleep 2 s, listen) then `timeout 2 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ 127.0.0.1 $P`
gave `Connection refused rc=1 t=0s` before the listen and `rc=0` after. This is both the evidence for
the "refused returns immediately" claim and the design of the late-open test fixture (no port-allocation
race, because the port is held by the fixture from the start).

**Relevant files.**

- `apps/web-platform/infra/egress-gateway-bootstrap.sh` (probe at lines 197-202; `die`/`log` at 23-24; the two bring-up arms `docker restart` line 172 and `docker run -d` line 179).
- `apps/web-platform/infra/egress-gateway.test.sh` (69 passing verdicts; anti-vacuity floor `-lt 30` literal at line 190; assertion on the old probe at line 172).
- `apps/web-platform/infra/server.tf` lines 2717-2859 (`terraform_data.egress_gateway`, `..._web2`; both hash the bootstrap into `triggers_replace.config_hash`, so editing the script re-provisions both even without the taint).
- `apps/web-platform/infra/cloud-init.yml:619` (fresh hosts run the same script from `runcmd`; the fix also covers fresh-host births) and `server.tf:203` (the script is part of the baked `host_script_files` set).
- `apps/web-platform/infra/cron-egress-self-heal.test.sh` lines 105-121 (precedent: `extract_fn` awk extraction of functions from the shipped script, "no logic copy").
- `apps/web-platform/infra/git-data-liveness.test.sh` lines 66-100 (precedent: real loopback listeners via `python3 -I`).
- `scripts/guard-vacuity-floor.test.sh` line 857 (the suite is a promoted floor-bearing file; keep the floor structure).

**Institutional learnings applied.**

- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` — a probe that cannot fail is the failure mode to design against; drives the never-opens case and the vacuous-pass mutant.
- `2026-09-28-a-retrying-unit-must-latch-only-full-success-and-undo-what-it-paused.md` — a retry may only report success on full success; the loop returns 0 only from a successful connect, never from loop exhaustion.
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` and the in-file comment at bootstrap lines 43-48 (set -e aborted the bridge rebuild before it started, #9534/#10084) — every conditional in the new loop is an `if`-guard; no bare `[[ ]] &&` / `(( )) &&` (the suite already asserts that, lines 169-170).

## Hypotheses

Network-outage gate (Phase 1.4) fired on `SSH` / `timeout` / `Connection refused` / `terraform_data ... remote-exec`.
Ordered L3 -> L7:

1. **L3 firewall allow-list (CI runner -> host SSH).** Verified not the cause today: both `egress_gateway` and `egress_gateway_web2` printed `Connected!` over the bridge in run 38228632851. The original port-22 symptom (2026-10-10 to 2026-10-11) is therefore not reproduced; `hcloud firewall describe` / egress-IP diff is not needed for this fix and is not run. If port-22 timeouts reappear they get a separate issue.
2. **L3 DNS / routing.** Not applicable: the failing hop is host -> `172.31.100.2` on the host-local docker bridge `soleur-egress0`; no routing leaves the host.
3. **L7 TLS / proxy.** Not applicable: the probe is a bare TCP open, no TLS.
4. **L7 application (squid).** The discriminating hypothesis. ECONNREFUSED (RST) is not a firewall DROP (a drop would time out, not refuse); refused within 1-3 ms of `docker run -d` returning is consistent with "container started, squid not yet bound". Competing sub-hypothesis: squid exits at start (config/helper error). The poll discriminates: slow-start passes inside the window; crash-at-start fails after the window with container state + log tail naming the cause. Prior evidence that squid does run on this image/config: the earlier `egress_gw_probe` stream measured host -> gw healthy on web-1 (`egress-gateway-bootstrap.sh` comment lines 61-71).

## Problem Statement

`docker run -d` and `docker restart` return once the container process is started, not once squid has
loaded its config, started the auth helpers and bound `:8443`. The bootstrap's "apply green == path
works" assertion is a single sample taken at t~0, so it cannot pass on a healthy host. Every push
apply therefore ends red (`notify-apply-failure` fires), both gateway resources stay tainted, and the
rest of the web-2 delivery chain that runs after these resources is never exercised clean.

## Proposed Solution

In `egress-gateway-bootstrap.sh`, replace lines 197-202 with a bounded poll implemented as two small
top-level functions plus one call site (functions so the test can extract them with the repo's
`extract_fn` awk idiom, no logic copy):

```bash
GW_WAIT_S="${EGRESS_GW_WAIT_S:-30}"   # test override; precedent EGRESS_GW_TOKEN_DIR / EGRESS_GW_IMAGE above

# Container state + the last log lines, for the timeout message. Every command is
# `|| true`: a diagnostics failure must not mask the real die. StartedAt/RestartCount
# disambiguate a `docker restart` incarnation from the previous one's log lines.
gw_diag() {
  log "gw container state: $(docker inspect -f '{{.State.Status}} running={{.State.Running}} restarting={{.State.Restarting}} restarts={{.RestartCount}} exit={{.State.ExitCode}} started={{.State.StartedAt}}' "$GW_NAME" 2>&1 || true)"
  log "gw container logs (last 20 lines):"
  timeout 10 docker logs --tail 20 "$GW_NAME" 2>&1 | sed 's/^/[egress-gw-bootstrap]   /' || true
}

# Poll until the gw accepts a TCP open or GW_WAIT_S elapses. Returns only on success;
# on timeout it dies (fail-closed). A refusal is instant, so the per-attempt `timeout 2`
# only bounds a filtered/blackholed attempt; the SECONDS deadline bounds the whole wait.
# The last probe error is kept: "Connection refused" (nothing listening) vs a timeout
# (packets dropped) is the L3-vs-L7 discriminator.
wait_for_gw_tcp() {
  local deadline=$(( SECONDS + GW_WAIT_S )) attempts=0 err=""
  while :; do
    attempts=$(( attempts + 1 ))
    if err="$(timeout 2 bash -c 'exec 3<>"/dev/tcp/$1/$2"' gw-probe "$GW_IP" "$GW_PORT" 2>&1)"; then
      log "gw $GW_IP:$GW_PORT answered a TCP open (attempt $attempts)"
      return 0
    fi
    if (( SECONDS >= deadline )); then break; fi
    sleep 1
  done
  log "last probe error: ${err:-<none>}"
  gw_diag
  die "gw $GW_IP:$GW_PORT did not answer a TCP open post-bring-up"
}

wait_for_gw_tcp
```

Design notes (each is a claim the work phase re-verifies with a command; see the claims ledger):

- Success is a successful connect only (`return 0` is reachable from nothing else) — loop exhaustion falls through to `die`.
- The existing `die` text is preserved verbatim as the final line, so any alert/grep keyed on it keeps matching; the diagnostics precede it. The success line `answered a TCP open (attempt N)` is new: it is the only record of how late squid bound on a green apply (the data to judge whether 30 s is the right budget) and it lets the test prove a retry happened without wall-clock assertions.
- Both bring-up arms (`docker restart` for an existing gw, `docker run -d` for a new one) converge on the single call site, so both are covered.
- `SECONDS` is an integer counter, so a budget of N seconds can end up to 1 s early (measured by the Kieran review: budget 3 ended at 2.06 s in 1 of 18 runs). The loop's contract is "at least N-1 s, about N s"; the tests assert accordingly (see Test Scenarios).
- `local deadline=$(( ... ))` is a literal arithmetic expansion with no command substitution, so `local`'s exit status cannot mask a failure.
- No `set -e` interaction: the probe sits in an `if` condition, `(( ))` sits in an `if`, diagnostics are `|| true`. The function is called bare so `set -e` stays live inside it, and the test calls it bare under `set -euo pipefail` for the same reason.
- `timeout 10` around `docker logs`: a journald read can stall; the failure path must not hang.

### Comment claims ledger (rule: every sentence added to a comment needs its falsifying command run first)

| Sentence to be added (or kept) | Falsifying command | Status |
|---|---|---|
| `docker run -d` / `restart` return before squid binds (a probe at t~0 is refused) | `gh run view 38228632851 --log \| sed 's/\x1b\[[0-9;]*m//g' \| grep -E "started soleur-egress-gw\|/dev/tcp/172.31.100.2/8443: Connection refused"` — started and refused are ~1-3 ms apart on both hosts; run 38229123048 shows the same on the `restarted` arm | RUN (this session) — holds |
| a refused connect returns immediately; `timeout` only bounds filtered attempts | local bind-not-listen fixture (see Research Insights): `rc=1 t=0s` before listen, `rc=0` after | RUN — holds |
| `docker logs` works on a container started with `--log-driver journald` (the gw's driver, bootstrap line 181) | Work phase: `docker run -d --log-driver journald --name t alpine sh -c 'echo x; sleep 60' && docker logs --tail 5 t` on a host with journald; if it fails, the log-tail lines and their comment are dropped (the state line alone still discriminates most modes) rather than adding a `journalctl` arm | NOT YET RUN — gate before writing the sentence |

If a row cannot be run, the sentence is dropped, not softened. The comment deliberately makes no claim about who sets `EGRESS_GW_WAIT_S` (that would need its own grep).

## Files to Edit

- `apps/web-platform/infra/egress-gateway-bootstrap.sh` — replace the single probe (lines 197-202) with `GW_WAIT_S`, `gw_diag`, `wait_for_gw_tcp`; update the comment above it (claims ledger).
- `apps/web-platform/infra/egress-gateway.test.sh` — (a) repoint the line-172 assertion that pins the old probe (`/dev/tcp/\$GW_IP/\$GW_PORT`, which the new `"/dev/tcp/$1/$2"` form no longer matches) to the new shape: `/dev/tcp/\$1/\$2` inside `wait_for_gw_tcp`, `wait_for_gw_tcp` called exactly once at top level, and the old top-level `^timeout 5 bash -c "exec 3<>` absent; (b) a static assertion that `GW_WAIT_S="${EGRESS_GW_WAIT_S:-30}"` appears literally (the extracted-function tests set `GW_WAIT_S` directly, so a wrong production default would otherwise pass); (c) add the behavioural section `-- bootstrap: post-bring-up poll (behavioural) --`; (d) header comment item 5 gains the poll; keep the `-lt 30` floor literal (raise only if the new verdict count justifies it; never lower); (e) extend the suite's `trap` to kill the listener-fixture PIDs.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — bump `BASELINE_DECLARED_PROBES` 62 -> 63 (line 2931) with the PLACEMENT / TRUTH / NO-SUBSTITUTE comment block its failure text asks for: this plan declares `discoverability_test.credentials_required`, and the G1 ratchet counts every declaring plan under `knowledge-base/project/plans/`, so the count moves the moment this plan is committed (the suite is bun, not selected by the infra diff; surfaces only in the full battery).
- `knowledge-base/project/specs/feat-one-shot-10003-egress-gw-tcp-open-retry/tasks.md` — created by the plan skill (derivative of this plan).

## Files to Create

None (tests live in the existing suite; no new script).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open --json number,title,body --limit 200`, then `jq --arg path` for `apps/web-platform/infra/egress-gateway-bootstrap.sh` and `apps/web-platform/infra/egress-gateway.test.sh`: zero matches each.)

## Implementation Phases

### Phase 0 — Preconditions (before any edit)

1. `bash scripts/test-all.sh --capacity` first (the file mode is not executable in this checkout: `scripts/test-all.sh: Permission denied` when run directly, so invoke with `bash`). This session's reading was `CAPACITY_CONTENDED reason=sibling_runs,sibling_suites measured_runs=3 measured_suites=6` — sibling worktrees are running suites. Consequence: run the infra suites in isolation (`bash apps/web-platform/infra/egress-gateway.test.sh` alone, 0.5 s today), and re-run any `rc=124` infra suite alone before treating it as a failure.
2. Record the shellcheck baseline: `shellcheck apps/web-platform/infra/egress-gateway-bootstrap.sh apps/web-platform/infra/egress-gateway.test.sh` currently reports 1 warning (SC2046 at bootstrap line 49, intentional word-splitting of `docker network ls -q`) and 6 info (SC2016 at test lines 141, 149, 162, 163, 171, 172 — grep patterns that deliberately contain a literal `$`). semgrep is broken on this host; shellcheck is the gate, and the bar is **no new finding relative to this baseline** (new code must be clean; the pre-existing ones are acknowledged, not fixed here).
3. Run the claims-ledger `docker logs`/journald row.
4. Confirm the G1 ratchet really moves once this plan is committed: `cd plugins/soleur && bun test test/preflight-discoverability-test.test.ts` fails with 63 declaring plans vs the 62 baseline (the bump is mechanical only if it does).

### Phase 1 — Test first (RED)

Add the behavioural section to `egress-gateway.test.sh` (see Test Scenarios and Guard Contract) and run it against the **unmodified** bootstrap: the extraction non-vacuity checks and the late-open/never-open/diagnostics cases must be RED (function not found). This is the `cq-write-failing-tests-before` step. It proves the harness is wired, not that behaviour is wrong; the behavioural RED proof is Guard Contract mutations 1 and 2.

Test harness shape:

- `extract_fn` (awk, from the `cron-egress-self-heal.test.sh` precedent) pulls `gw_diag` and `wait_for_gw_tcp` from `$BOOTSTRAP`; the one-line `log()`/`die()` are pulled with `grep -E '^(log|die)\(\) \{'` so they are not copied. Non-vacuity floors: `gw_diag` >= 4 lines, `wait_for_gw_tcp` >= 12 lines. A generated lib file is `source`d inside `bash -c` with `set -euo pipefail`, an EXECUTABLE `docker` stub on a fakes `PATH` dir (precedent: `git-data-liveness.test.sh` `FAKES`; prints `STUB-STATE ...` for `inspect`, `STUB-LOG ...` for `logs`) — NOT a shell function, because `timeout 10 docker logs` execs the binary and would bypass a function stub (measured in a scratch run: the function stub was ignored and the real docker answered), and `GW_IP`/`GW_PORT`/`GW_NAME`/`GW_WAIT_S` set per case. The function is called BARE (not as `f || ...`, which would suppress `set -e` inside it and stop mirroring production).
- Listeners: a tiny `python3 -I` fixture (precedent: `git-data-liveness.test.sh`) that `bind()`s a loopback port immediately, prints it, sleeps `DELAY` seconds, then `listen()`s. `DELAY=0` is the already-open control; the never-open variant never calls `listen()`. Because the fixture owns the port from the start there is no free-port race. The suite's existing `trap` is extended to kill the fixture PIDs (a failed run must not leak listeners).
- Every scenario runs under an outer `timeout $((budget+15))` so an infinite-loop mutant surfaces as `rc=124` = FAIL, not a hung suite.
- Budgets are small (late-open: delay 2 s, budget 8 s; never-open: budget 3 s) to keep the suite at a few seconds of real sleeping under contention.

### Phase 2 — Implement (GREEN)

Edit the bootstrap per `## Proposed Solution`. Run shellcheck (no new findings), the suite alone, then the two neighbours that read the same bytes or the same floor structure: `egress-gw-image-staleness.test.sh` (the `ubuntu/squid@sha256:` literal must still appear exactly once, comment-free — do not paste the digest into new comments) and `scripts/guard-vacuity-floor.test.sh` (promoted-suite floor structure intact).

### Phase 3 — Mutation battery

Run each Guard Contract mutation against the finished bootstrap/suite (sed on a scratch copy, never on the tree) and confirm the expected RED. Record a one-line result per row in the PR body.

### Phase 4 — Ship and sequence

1. Rebase on `origin/main` (never merge main). `git fetch origin main && git rebase origin/main`.
2. Before merging: `gh run list --status in_progress` and `gh run list --status queued`, filtered to the apply workflow (`apply-web-platform-infra.yml`, shared concurrency group `#4844`; the R2 backend has no state lock — `use_lockfile = false` — so applies are strictly sequential). At plan time run 38229123048 (staged-env-files PR, `0dc19ef389`) had already concluded `failure` with the same TCP-open error, so nothing was in flight; re-check at merge time and merge only when the workflow has no `in_progress` or `queued` run, so this PR's apply is the only writer.
3. PR body: `Ref #10003` (not `Closes`) until the post-merge evidence below is in; then close with a comment citing the evidence, or leave open with the findings. The PR body's FIRST line answers "does merging this alone mutate production?": yes — the workflow `apply-web-platform-infra.yml` fires on `push` to `main` for `apps/web-platform/infra/**` and its `-target` set names `terraform_data.egress_gateway` and `terraform_data.egress_gateway_web2` (`apply-web-platform-infra.yml` lines 1245-1246), so the merge itself re-provisions both gateways (a gw container restart on each host); no separate dispatch exists.

### Rollback

`git revert` of the squash commit restores the single probe and the old line-172 assertion together (both are in this PR). A revert returns the apply to its current red state; it is not a safety rollback, since the failing check is itself the bug.

## Post-merge verification (evidence the apply is green on both hosts)

**Owner:** the `soleur:ship` post-merge phase of this same session runs these steps (the merge click is the trigger; `Ref #10003` stays on the PR until they pass). If the session ends first, the unfinished verification is carried by a comment on #10003 listing the run id and the three commands, so any later session or the operator can finish it; there is no operator step beyond reading that comment.

The merge triggers `apply-web-platform-infra.yml`. `terraform_data.egress_gateway` and `..._web2` re-provision (their `triggers_replace.config_hash` changes with the bootstrap bytes, and both are tainted). Evidence, all runnable without SSH. A foreground `gh run watch` can outlive the Bash tool's 10-minute cap (the apply serializes on a shared concurrency group and can queue), so the wait is an armed Monitor until-loop (`hr-monitor-not-run-in-background-for-polling`), not a foreground watch:

```bash
MERGE_SHA=$(gh pr view <PR> --json mergeCommit -q .mergeCommit.oid)
[[ -n "$MERGE_SHA" ]] || { echo "PR not merged yet"; exit 1; }   # empty until the merge lands; an empty sha would select nothing
# Run creation lags the merge: bounded wait for the run to exist, then for it to complete.
until RUN=$(gh run list --workflow apply-web-platform-infra.yml --event push --commit "$MERGE_SHA" --json databaseId -q '.[0].databaseId') && [[ -n "$RUN" ]]; do sleep 10; done
until [[ "$(gh run view "$RUN" --json status -q .status)" == completed ]]; do sleep 20; done   # armed via Monitor, with an outer deadline
gh run view "$RUN" --json conclusion -q .conclusion
gh run view "$RUN" --log | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E 'egress_gateway(_web2)? \(remote-exec\).*(OK: gateway up|answered a TCP open)'   # expects OK line + attempt line per resource
```

Better Stack (needs the Doppler `prd_terraform` query credentials): the `egress_gw_probe` stream emits every 5 minutes, so a window that straddles the apply can match pre-apply samples. Anchor it: take the apply run's `updatedAt` as the lower bound and require at least one `egress_gw_probe result=ok` from EACH host after that time (wait up to one 5-minute cadence). The row must carry a host discriminator (`logger -t egress-gw-probe` lines go through journald with `_HOSTNAME`/`host`); confirm the field name from one live row before relying on it, because "both hosts" is unverifiable from a bare grep.

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 30m --grep egress_gw_probe
```

- Expected NOT to appear: a fresh `egress_gw_bridge action=rebuilt` (the bridge is already `nat-unprotected`, see Research Reconciliation; run 38229123048 printed `restarted` and no `rebuilt` line). Its absence is correct, not a failure.
- The remote-exec runs `systemctl restart cron-egress-firewall.service` after the bootstrap. On the tainted resources that line has not been reached in the recent runs (the bootstrap dies first), so a failure *after* the OK line is a new, separate finding: read the log, file it, and keep `Ref #10003`.
- **Close criterion** (the property, not the run's overall color): both resources' `OK: gateway up` lines are present and both `terraform_data` resources completed in that run, and the post-apply `egress_gw_probe result=ok` reading holds for both hosts. Run-level `success` is sufficient but not necessary: an unrelated job turning the run red with both OK lines present is recorded on #10003 and does not by itself block closing; the reverse (run green, an OK line missing) is a failure.
- Close #10003 with this evidence, or comment the findings and leave it open.
- Also comment on #10003 now (work phase, before merge) with the re-measure evidence: port-22 did not reproduce; the failure is the TCP-open race; link this plan and the PR.

## Infrastructure (IaC)

### Terraform changes

No `.tf` change. The bootstrap is a delivered artifact already hashed into both `terraform_data` resources' `triggers_replace.config_hash` (`server.tf` 2720-2727 and 2798-2805), so editing it re-provisions both.

### Apply path

(b)-class re-provision through the existing `terraform_data` `triggers_replace` (no VM replace): expected blast radius is the gw container restart (`docker restart` arm; seconds) on web-1 and web-2 and a re-run of `systemctl restart cron-egress-firewall.service`. The gateway is only used by entitled open-web sessions (ADR-278); a brief gateway restart fails those closed, which is the existing safe default. web-2 stays in service; nothing here retires it.

### Host fan-out

Both fleet hosts already receive the identical bootstrap through their own `terraform_data` resource (`egress_gateway` for web-1, `egress_gateway_web2` for web-2) and fresh hosts through `cloud-init.yml:619` + the baked `host_script_files` entry (`server.tf:203`). No new SSH provisioner is added, so the `web-host-provisioner-parity` classification is unchanged.

### Distinctness / drift safeguards

None needed (no dev/prd value, no `ignore_changes` touched).

### Vendor-tier reality check

None (no new provider resource).

## Observability

```yaml
liveness_signal:
  what: "egress_gw_probe result=ok journald line emitted by cron-egress-resolve.sh run_egress_gw_probe (synthetic CONNECT pair through the app container to the gw), shipped to Better Stack"
  cadence: "5 min per host"
  alert_target: "cron-egress alarm path (cron-egress-alarm@.service) and the Better Stack egress_gw_probe stream; apply failures page via notify-apply-failure"
  configured_in: "apps/web-platform/infra/cron-egress-resolve.sh (run_egress_gw_probe)"
error_reporting:
  destination: "terraform apply log (remote-exec stdout) surfaced by the apply workflow and notify-apply-failure; the bootstrap has no Sentry DSN, same as before this change"
  fail_loud: "[egress-gw-bootstrap] ERROR: gw <ip>:8443 did not answer a TCP open post-bring-up, preceded by the container state line and the last 20 gw log lines (new)"
failure_modes:
  - mode: "squid listens late (within 30 s)"
    detection: "apply stays green; the new bootstrap line `answered a TCP open (attempt N)` records how late squid bound, so a host drifting toward the 30 s budget is visible in the apply log"
    alert_route: "none required (review the attempt count after the first post-merge apply; revisit the budget if it is regularly above 15)"
  - mode: "squid never listens (crash-at-start, bad conf, helper missing)"
    detection: "apply goes red with ERROR line + container state + log tail in the same log"
    alert_route: "notify-apply-failure"
  - mode: "gw container absent or crash-looping after bring-up"
    detection: "egress_gw_probe result=skipped reason=gw_absent / result=fail on the 5-min probe"
    alert_route: "cron-egress alarm + Better Stack stream"
logs:
  where: "apply workflow log (bootstrap stdout); gw container logs in journald (--log-driver journald), forwarded to Better Stack"
  retention: "GitHub Actions log retention for the apply; Better Stack source retention for the journald stream"
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 1h --grep egress_gw_probe
  expected_output: result=ok
  credentials_required: "Better Stack ClickHouse query connection (BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD in Doppler soleur/prd_terraform) — log rows are readable only through that connection; the ingest token is write-only, so no unauthenticated probe verifies the same property"
```

## Guard Contract

### Guard 1 — post-bring-up gateway liveness check (bootstrap) and its behavioural test

**Property.** The bootstrap exits 0 only if a TCP open to the gateway succeeded within the wait budget, and exits nonzero (with the existing `did not answer a TCP open post-bring-up` text, container state and log tail) when no open succeeds within that budget — and a gateway that opens late but inside the budget is not failed.

**Assembly.** The property quantifies over: (1) the single call site `wait_for_gw_tcp` at the end of `egress-gateway-bootstrap.sh`, which both bring-up arms flow through (`docker restart` at the `if docker inspect "$GW_NAME"` arm, `docker run -d` at the `else` arm) — one chokepoint, not two; (2) the functions it composes (`wait_for_gw_tcp`, `gw_diag`, the one-line `die`/`log`); (3) the three delivery channels of the same bytes (`terraform_data.egress_gateway`, `terraform_data.egress_gateway_web2`, cloud-init `runcmd` at `cloud-init.yml:619`), which all execute this one file, so the guard lives at the file and no per-channel copy exists to drift; (4) the test harness's extraction (`extract_fn` over `$BOOTSTRAP`) and its listener fixture. Members drift; the chokepoint is the single call site, and the suite asserts it appears exactly once.

**Mutation matrix:**

| # | Mutation (applied to a scratch copy of the bootstrap / suite) | Expected |
|---|---|---|
| 1 | Limit `wait_for_gw_tcp` to one attempt, and separately to two attempts 1 s apart ("a check that stops at the first member"): the original bug and its near-miss | RED: late-open case (listener opens after 2 s, budget 8 s) fails for both |
| 2 | Make the probe vacuous: replace the connect with `true` | RED: never-open case expects nonzero rc + the `did not answer` text and gets rc 0 |
| 3 | Remove the deadline (`(( SECONDS >= deadline ))` never true / deadline recomputed inside the loop) | RED: never-open case — outer `timeout` fires (rc 124) and the elapsed upper-bound assertion fails |
| 4 | Move `gw_diag` after `die` (diagnostics unreachable) or drop it | RED: never-open case asserts `STUB-STATE` and `STUB-LOG` markers appear before the die line |
| 5 | Own dispatch: rename `wait_for_gw_tcp` in the bootstrap so `extract_fn` yields nothing | RED: the extraction non-vacuity check (`>= 12` lines for `wait_for_gw_tcp`, `>= 4` for `gw_diag`) fails before any behavioural row |

**Harness rows (edits to the SUITE, and inputs that are not the canonical):**

| # | Edit / input | Expected |
|---|---|---|
| H1 | Edit the suite's fixture so the "late" listener never calls `listen()` | RED: the late-open case must fail (proves the case observes the listener and is not satisfied by a stub) |
| H2 | Must-PASS non-canonical: loopback `127.0.0.2` (Linux-only, fine here), a different port, `GW_WAIT_S=7`, listener already open (`DELAY=0`) | PASS (a guard that rejects everything cannot pass this row) |

The static assertions (call site exactly once, old probe absent, `GW_WAIT_S` default literal) are ordinary suite verdicts, not mutation rows: each is a one-line grep whose own failure is directly visible.

**Anchor.** No stored value (hash, count, manifest row) is compared to what it protects, so the stored-value-self-certification class does not apply. The only count is the suite's verdict floor, which is a literal `-lt 30` inside the `if` (promoted-suite structure per `scripts/guard-vacuity-floor.test.sh`) and is only ever raised.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "replace the single probe with a bounded retry (poll up to roughly 30s, 1s interval" | Proposed Solution: `wait_for_gw_tcp`, `GW_WAIT_S=30`, `sleep 1` | mapped |
| 2 | "fail with the existing die message plus the container state and last log lines on timeout" | `gw_diag` + preserved `die` text | mapped |
| 3 | "keep the check meaningful (it must still fail if squid never listens)" | Guard 1 property, mutations 2/4, never-open case | mapped |
| 4 | "extend egress-gateway.test.sh with a test for the retry (passes when the port opens late, fails when it never opens)" | Phase 1 behavioural section; Test Scenarios T2/T3 | mapped |
| 5 | "verify the apply turns green on web-1 and web-2 after merge (egress_gw_bridge action=rebuilt line in Better Stack, egress_gw_probe result=ok)" | Post-merge verification (with the reconciliation that `action=rebuilt` will not re-fire) | mapped |
| 6 | "The PR closes #10003 only if post-merge evidence shows both hosts green, else use Ref" | Phase 4.3, frontmatter comment, Post-merge verification | mapped |
| 7 | "check `gh run list --status in_progress` and `--status queued` before merging" | Phase 4.2 | mapped |
| 8 | "rebase, never merge main" | Phase 4.1 | mapped |
| 9 | "run `scripts/test-all.sh --capacity` first and re-run any rc=124 infra suite in isolation" | Phase 0.1 | mapped |
| 10 | "shellcheck is the gate (semgrep is broken on this host)" | Phase 0.2 baseline + Phase 2; AC | mapped |
| 11 | "every sentence added to a comment or runbook needs its falsifying command run first" | Comment claims ledger | mapped |
| 12 | "web-2 stays in service ... do not retire it" | Apply path; Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `gw_diag` as a separate function | "the container state and last log lines" | asked (the content); the function split is a taste call, kept because both functions extract the same way and a diagnostics change then edits one named unit (recorded in `decision-challenges.md`) |
| `last probe error` log line | "fail with the existing die message plus the container state and last log lines" | inferred — justification: refused vs timeout is the L3-vs-L7 discriminator the Hypotheses section depends on; 2 lines |
| `attempt N` success log line | "keep the check meaningful" | inferred — justification: lets the late-open test prove a retry happened without a wall-clock assertion (`SECONDS` truncation makes those flaky) and records how late squid binds |
| `BASELINE_DECLARED_PROBES` 62 -> 63 | none (consequence of this plan's own `discoverability_test.credentials_required`) | inferred — mechanical coupling to the G1 ratchet; whether to avoid the declaration is a taste call recorded in `decision-challenges.md` |
| `EGRESS_GW_WAIT_S` env override | "poll up to roughly 30s" | inferred — justification: the never-open test cannot wait 30 s; precedent `EGRESS_GW_TOKEN_DIR` / `EGRESS_GW_IMAGE` in the same script |
| Extraction-based behavioural test instead of grep-only | "extend egress-gateway.test.sh with a test for the retry (passes when the port opens late, fails when it never opens)" | asked (a grep cannot observe "passes when late") |
| Neighbour-suite runs (staleness, floor suite) | "shellcheck is the gate" | inferred — justification: they read the same bytes (the `@sha256:` literal parse) and the same floor structure the suite edit touches |
| Comment on #10003 with the re-measure | "re-scoped after re-measure on 2026-10-12" | asked |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform/infra`
- Planned files: 2 source + tasks.md | Estimated changed lines: ~120 (≈25 bootstrap, ≈95 suite)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a red infrastructure apply on every push to main, and an entitled open-web session that fails closed (no external egress) on a host whose gateway never came up; non-entitled sessions are unaffected because the gateway is opt-in (ADR-278).
- **If this leaks, the user's data is exposed via:** no new exposure vector — the change adds a loopback-bridge TCP open and a log tail of the gateway container (squid decision log: workspace attribution `%un`, destination host). The log tail is printed only on the failure path into the apply workflow log, which already carries this script's stdout.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** `aggregate pattern`, not `single-user incident`: the failure mode is a noisy red apply and a fail-closed gateway (no data path opens), so no single user's data is exposed; `none` is rejected because the diff touches a delivery path for a security-adjacent gateway and a vacuous check would let a dead gateway read as "apply green".

*Log-tail disclosure check (RUN at plan time):* `grep -n logformat apps/web-platform/infra/egress-gateway-squid.conf` shows the `soleur_json` format carries `decision`, `decision_reason`, `requested_host`, `resolved_ip`, `workspace` (`%un`, the basic-auth username = workspace id, not the token), `bytes_out`, `duration_ms`, `client` — no password/token field. The work phase re-runs the grep; if a credential-bearing field has appeared, `gw_diag` must filter it or drop the log tail (state only).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash apps/web-platform/infra/egress-gateway.test.sh` exits 0 run alone; reports `RESULT: <N> passed, 0 failed` with N greater than 69; the literal anti-vacuity floor is still present and not lowered.
- [ ] Phase 1 evidence: the new behavioural cases were RED against the unmodified bootstrap (recorded in the PR body).
- [ ] The never-open case: wait budget 3 s against a bound-but-not-listening loopback port exits nonzero, output contains `did not answer a TCP open post-bring-up`, `STUB-STATE` and `STUB-LOG`, and elapsed is within [budget - 1, budget + 10] seconds (`SECONDS` is an integer counter, so the lower bound allows one second of truncation).
- [ ] The late-open case: listener opens after 2 s, budget 8 s, exits 0 and the success line reports `attempt` >= 2 (the retry is proven by the attempt count, not by wall-clock elapsed, which `SECONDS` truncation makes flaky).
- [ ] Mutations 1-5 and harness rows H1-H2 each produce the stated RED/PASS (one-line result per row in the PR body).
- [ ] `shellcheck apps/web-platform/infra/egress-gateway-bootstrap.sh apps/web-platform/infra/egress-gateway.test.sh` shows no finding beyond the Phase 0.2 baseline (1 SC2046 warning at bootstrap `docker network inspect $(docker network ls -q ...)`, the six existing SC2016 infos in the test).
- [ ] `grep -c '^wait_for_gw_tcp$' apps/web-platform/infra/egress-gateway-bootstrap.sh` is `1`, `grep -nE '^timeout 5 bash -c "exec 3<>' apps/web-platform/infra/egress-gateway-bootstrap.sh` is empty, and `grep -c 'GW_WAIT_S="${EGRESS_GW_WAIT_S:-30}"' apps/web-platform/infra/egress-gateway-bootstrap.sh` is `1` (run each once before finalizing; the first two are also suite verdicts).
- [ ] Neighbours green in isolation: `egress-gw-image-staleness.test.sh` and `scripts/guard-vacuity-floor.test.sh`; any `rc=124` re-run alone before judging.
- [ ] Every sentence added to a comment has its claims-ledger command run and its result recorded; the journald `docker logs` row is resolved (sentence and log-tail lines kept with evidence, or dropped).
- [ ] Squid logformat re-checked at work time: no credential field (log-tail disclosure check) or `gw_diag` filters it.
- [ ] `BASELINE_DECLARED_PROBES` bumped 62 -> 63 with its comment block, and `cd plugins/soleur && bun test test/preflight-discoverability-test.test.ts` passes.
- [ ] `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/server.tf apps/web-platform/infra/cloud-init.yml .github` exits 0 (this PR edits neither Terraform, cloud-init nor workflows; merge-base form so a sibling merge cannot redden it).
- [ ] Rebased on `origin/main` with no merge commit; `gh run list --status in_progress` and `--status queued` checked for the apply workflow immediately before merge.
- [ ] PR body says `Ref #10003`, first line answers "does merging this alone mutate production?" (yes: the push apply re-provisions both gateways), includes `## Changelog`, and carries the matrix results.

### Post-merge (operator-free, agent-run)

- [ ] Both resources' `OK: gateway up` lines present in the merge commit's apply run, and both `terraform_data` resources completed (close criterion per Post-merge verification; run-level `success` sufficient, not necessary).
- [ ] `egress_gw_probe result=ok` from EACH host after the apply run's `updatedAt` (Better Stack, host-discriminated).
- [ ] #10003 closed with this evidence, or left open with the findings and `Ref` kept.

## Test Scenarios

- T1 (integration — `bash` + loopback listener): Given a gateway already listening, when `wait_for_gw_tcp` runs, then it returns 0 on attempt 1 (positive control; proves the probe really connects).
- T2 (integration): Given a listener that opens 2 s after bring-up and an 8 s budget, when `wait_for_gw_tcp` runs, then it returns 0 and the success line reports attempt >= 2.
- T3 (integration): Given a port that is bound but never listens and a 3 s budget, when `wait_for_gw_tcp` runs, then rc != 0, output has the existing die text, the container-state line and the log lines, and elapsed is within [budget - 1, budget + 10] seconds.
- T4 (unit — static): the bootstrap contains exactly one top-level `wait_for_gw_tcp` call, no top-level `timeout 5 bash -c "exec 3<>`, and the `GW_WAIT_S` default literal.
- T5 (regression): `restart` arm — the same call site is reached when the gw container pre-exists (assert by structure: the call is after the `if/else/fi` that holds both arms).
- Verification commands for the apply (no browser/API surface): see Post-merge verification.

## Domain Review

**Domains relevant:** engineering (infra) only.

### Engineering (CTO lens, assessed inline)

**Status:** reviewed
**Assessment:** Infra-only change on an existing delivery path; no architectural decision (no new substrate, trust boundary or ADR divergence — ADR-278 untouched), no UI surface, no regulated-data surface (no schema/auth/API route; the log tail stays inside the existing apply log), no new store or connection (the probe is the existing host-to-gw bridge hop). Phases 2.7 (GDPR), 2.10 (ADR/C4), 2.11 (encryption posture) skipped on those grounds; Phase 2.5 Product/UX gate skipped (no UI-surface path in the Files lists).

## Non-Goals

- No change to the SSH/firewall/Cloudflare-tunnel layer: port-22 does not reproduce (`## Hypotheses` 1).
- No edit to the stale "web-2 SSH route is slow (~70s per dial)" comment in `server.tf` (comment-only, would need its own falsification; the 15m connection timeout is harmless headroom).
- Not retiring web-2 (explicit constraint).
- No fix of the pre-existing shellcheck findings (SC2046 line 49; SC2016 in the suite).
- No HEALTHCHECK, shared probe lib, or fail-fast-on-exited (Cut List).

## Risks

- **Downstream failures newly reachable.** With the bootstrap passing, `systemctl restart cron-egress-firewall.service` and anything after it in these resources runs for the first time on the tainted resources; a failure there is a different bug. Mitigation: Post-merge section distinguishes it and keeps `Ref`.
- **Timing flake under contention.** The capacity probe reads `CAPACITY_CONTENDED`; the suite adds ~2-5 s of real sleeping. Mitigation: wide margins (late-open budget 20 s vs 2 s delay; never-open upper bound budget+10 s), outer `timeout` per case.
- **`docker logs` driver behaviour** (journald) unverified until the ledger row runs.
- **Image/baked-set churn.** The script is in the baked `host_script_files` set and the app image COPY set, so the merge also rebuilds the web-platform image; this is expected and unrelated to the apply order.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one carries the section with `aggregate pattern`.
- The suite is a promoted floor-bearing file: add verdicts only through the existing `assert_*`/pass-fail helpers so the `$((PASS + FAIL))` floor keeps counting them, and never convert the literal bound to a variable.
- `scripts/test-all.sh` is not executable here: invoke `bash scripts/test-all.sh`.
- Do not paste the squid image digest into any new comment: `rule-audit.yml` (egress-gw drift step) and `egress-gw-image-staleness.test.sh` parse the first `ubuntu/squid@sha256:` literal in the bootstrap and assume it is the only one.
- The work session never invokes the infrastructure apply; the post-merge apply is the CI workflow's job.

## References

- Run 38228632851 (evidence), run 38229123048 (queued-for-merge apply), merge commit 67ebbbeb4e (set -e fix, #9534 / #10084), #10003, #7258, ADR-278.
- `knowledge-base/project/plans/2026-10-05-feat-open-web-egress-plan.md`, `2026-10-07-fix-web2-cron-egress-delivery-and-mint-backstops-plan.md`.
