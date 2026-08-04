# fix: the `zot mirror FAILED` error must consume the in-job token verification, not contradict it

---
issue: 7242
type: bug
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
branch: feat-one-shot-7242-zot-mirror-error-misdiagnosis
adr: ADR-166 (provisional ordinal — re-derive against origin/main before merge)
---

## Enhancement Summary

**Deepened on:** 2026-08-03
**Review panel:** dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer, cto (devex lens) — 6 agents, all findings consolidated.
**Deepen agents:** learnings-researcher, Explore (precondition verification).
**Gates passed:** 4.5 network-outage (telemetry emitted), 4.6 user-brand impact, 4.7 observability
(5/5 fields, no SSH), 4.8 PAT-shaped (clean), 4.9 UI-wireframe (N/A), 4.10 encryption posture (N/A).

### Key improvements

1. **A2 deleted entirely.** The proposed Access probe *duplicated a probe the job already runs*
   (`access_hostname_for()` maps `REGISTRY_PUSH_ACCESS_TOKEN` → `registry.soleur.ai`) and graded on
   the **status code** — the exact instrument #7127 removed as wrong. The plan's own thesis,
   violated in its primary deliverable. Both simplification reviewers converged; the cut dissolved
   an entire class of downstream findings (the `EDGE_CODE` unset-value hole, three unreachable arms,
   five ACs, two risk rows, two test scenarios).
2. **The verdict became four-valued.** The first draft mapped `rc=1 → stale`, collapsing
   *DEAD* and *UNVERIFIABLE* — so a transient network fault would print "the token is STALE, rotate
   it" about a token nothing measured. The cited precedent condemns exactly this collapse inline
   (`scheduled-terraform-drift.yml:235-238`). Now parsed from JSON: `live` / `stale` /
   `unverifiable` / `unmeasured`.
3. **Deliverable B was aimed at the wrong artifact.** The `serving is FINE` heading belongs to the
   private-NIC boot-race advisory, not a zot-push advisory — the proposed replacement would have
   written a *new* false claim. B1/B2/B3 cut; B4 (the cumulative `reboot_count` misread that
   produced hypotheses H3 and H4) kept and promoted.
4. **The alarm cannot fire at all** — measured, and the mechanism corrected mid-review. All seven
   issue-filing steps use plain `if:` with no status-check function, so they inherit an implicit
   `success()` and skip whenever the checker step fails, *including on the FIRE verdict they exist
   to report*. Pulled in scope; the sibling detector already uses the fix.
5. **Structural fix adopted (CTO):** the diagnosis text moves to a sourced
   `scripts/zot-mirror-diagnosis.sh`, making "both messages tell the same story" true by
   construction instead of by assertion — and per-arm tests direct function calls instead of
   driving a 270-line extracted YAML block four times.
6. **Deliverable E added:** `scripts/lint-diagnosis-claims.sh`. Two prior iterations were each
   "fixed" by rewriting the message; neither generalized. Prose is not an enforcement mechanism.

### New considerations discovered

- **Three consumers, not one.** `cf-tunnel-registry-bridge` is called by `reusable-release.yml`,
  `build-inngest-config-bundle.yml` and `build-inngest-bootstrap-image.yml`; the latter two have no
  preflight and would pin the `unmeasured` arm. **The identical blast-radius miss for this identical
  action is already on record** (`specs/feat-one-shot-zot-mirror-fail-closed/decision-challenges.md:32`).
- **Deliverable E would land in an ADVISORY CI job.** `lint-bot-statuses` is absent from both
  `required-checks.txt` and the Terraform ruleset, so a PR merges with it red. The lint must be
  promoted (ruleset + required-checks move as a pair) or the plan must stop claiming enforcement.
- **`model.c4:457` must be amended, not deleted** — it is a deliberate #7071 cause-class record that
  prevents #6416 being re-derived. One reviewer recommended deletion; a second read the context and
  showed deletion re-opens the failure mode. Two further sibling sites carry the same falsified claim.
- **A sibling alarm shares the defect.** `scheduled-inngest-health.yml` gates eight issue-filing
  steps on plain `if:` conditions too. Not fixed here — filed with the Phase 1 issues.
- **`|| rc=$?` flips a step's `outcome` to `success`**, which would disarm the
  `BRIDGE_OUTCOME == 'failure'` gate the mirror step depends on. Safe for `token_preflight`; a trap
  for any future refactor of `zot_bridge`.
- **AC17/AC19 were unsatisfiable** (three reviewers converged): both required the crash-loop to stop,
  which this plan explicitly does not fix. Moved to the crash-loop issue as follow-throughs.

### The live incident, still open

zot has been crash-looping since ~17:08 UTC — **1032 restarts by 21:25**, ~4/min, `oom_kills=0`, a
recurrence of the closed #6288. It is the active cause of the deploy blockage, it is **not** fixed by
this plan, and the plan deliberately records its proximate cause as UNKNOWN rather than guessing.

---

## Overview

Every `Web Platform Release` since 17:11 UTC on 2026-08-03 fails at the zot-mirror bridge with
`mirror_reason=bridge`. Production serves `0ed105b4c349` (the 16:35 release) while `main` is at
`e861e341da6b` — three releases behind, each stranded as an unpublished draft.

The standing error text tells the operator the cause is a stale `REGISTRY_PUSH_ACCESS_TOKEN_*`
and to run the drift check. **A step in the same job, six minutes earlier, already disproved
that.** This plan makes the failure messages *consume* the verification result that is already
computed in-job — so the error names a cause that was **measured**, never one that was merely
plausible — and closes the one hypothesis the preflight genuinely cannot settle (the origin) by
measuring it in-job too.

It also restores the alarm that should have caught this: `scheduled-zot-restart-loop.yml` cannot
open its recurrence issue on **any** non-zero checker exit, including the FIRE verdict it exists to
report (Deliverable B2 — one word, seven steps).

This is the third iteration of the same defect class on this exact code path. The workflow's
own comments record the previous two:

> *"It predicted a missing tunnel-connector route as the likely cause. REFUTED … Reading that
> prediction as a finding is what sent the 2026-07-29 investigation to the wrong network layer
> and consumed its entire diagnostic budget."* — `reusable-release.yml:1050-1053`

The fix is therefore structural, not a re-wording: **no failure message on this path may name a
cause the job did not measure.**

---

## Diagnosis (measured, not inferred)

All probes below were run live during planning on 2026-08-03 between 21:02 and 21:06 UTC.
Commands and raw outputs are reproduced so a reader can re-run them.

### The measured root cause

`zot` is in a continuous crash-restart loop. From Better Stack `SOLEUR_ZOT_DISK`
(`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 12h --grep SOLEUR_ZOT_DISK`):

| time (UTC) | `zot_restarts` | delta | `oom_kills` |
|---|---|---|---|
| 17:00 | 0 | +0 | 0 |
| 17:05 | 0 | +0 | 0 |
| **17:10** | **2** | **+2** | 0 |
| 17:15 | 22 | +20 | 0 |
| 17:20 | 45 | +23 | 0 |
| 19:05 | 477 | +19 | 0 |
| 20:22 | 765 | +16 | 0 |
| 21:05 | **950** | +20 | 0 |

The loop begins between 17:05 and 17:10 and runs at a steady **~4 restarts/minute**, unbroken,
for four hours. **The first release failure is 17:11:50** — one to six minutes after onset. That
is the cause: a `docker login` + three-tag `crane copy` takes tens of seconds and is therefore
near-certain to straddle a restart. When it does, the tunnel connector's origin dial fails and
`cloudflared` reports `websocket: bad handshake`; the docker client sees
`read: connection reset by peer`.

`oom_kills=0` and `oom_killed=false` throughout, so this is **not** the OOM signature — it is a
recurrence of the *non-OOM* crash-loop class of the (closed) #6288.

### Every named hypothesis, refuted with an artifact

| # | Hypothesis | Verdict | Deciding artifact |
|---|---|---|---|
| H1 | Stale `REGISTRY_PUSH_ACCESS_TOKEN_*` (what the error text claims) | **REFUTED** | In-job preflight at 20:23:05 → `live entries: 1  dead entries: 0  unverifiable: 0`. Independently: the `prd`-root token authenticates live today (H2 row). |
| H2 | The Access policy no longer admits the registry-push token (issue's step 1) | **REFUTED** | App `f9424b19-…` / `registry.soleur.ai` has policy *"Allow GitHub Actions registry push"*, `decision=non_identity`, `include=[{service_token:{token_id:"1b281614-9ba0-430b-aa2d-9de3c1c8852c"}}]`. That token is `github-actions-registry-push`, `client_id=8414f99a…access`, **expires 2027-07-29**. Doppler `prd` root holds **the same** `client_id`. Live probe with those creds → **HTTP 200 + `CF_Authorization` cookie issued**. |
| H3 | The registry host's `cloudflared` connector never re-registered after the 17:13 reboot (issue's step 2) | **REFUTED, and the premise is a wrong model** | Tunnel `soleur-web-platform` is `status=healthy` with 4 connections, all opened **2026-07-31 / 2026-08-01**, `origin_ip=135.181.45.178` — none re-opened after 17:13. Separately, **there is no `cloudflared` on the registry host**: `tunnel.tf` routes `registry.*` → a **web**-host connector → `tcp://10.0.1.30:5000`. A registry-host reboot cannot deregister a web-host connector. |
| H4 | The registry host rebooted at 17:13 (the #7232 advisory's premise) | **REFUTED** | `SOLEUR_PRIVATE_NIC` for `enp7s0:10.0.1.30` reports `boot_id=c60e54b7-…` unchanged all day with `uptime_s=1570434` at 21:02 — **18.2 days**. The host has not rebooted. The advisory's `reboot_count=1` is a *persisted cumulative counter*, not evidence of a reboot in-window. |
| H5 | zot origin flapping / crash-looping | **CONFIRMED** | The table above: `zot_restarts` 0 → 950, onset 17:05–17:10, first failure 17:11. |

### Network-outage checklist (`hr-ssh-diagnosis-verify-firewall`, L3 → L7)

Required because the symptom set matches `connection reset`, `handshake`, `timeout`.
Telemetry emitted (`emit_incident hr-ssh-diagnosis-verify-firewall applied`).

| Layer | Verified | Artifact |
|---|---|---|
| **L3 — allow-list / authorization** | ✅ verified | Path has no public firewall ingress; the equivalent gate is CF Access. Policy + token identity + expiry read from the CF API (H2 row). Control probe: no creds → **403**; treatment probe: with creds → **200**. |
| **L3 — DNS / routing** | ✅ verified | `registry.soleur.ai` resolves and is answered by the CF edge (`cf-ray: a25843d6cb0ec91d-CDG`). Tunnel `status=healthy`, 4 connections, `origin_ip=135.181.45.178`. |
| **L7 — TLS / proxy** | ✅ verified | `curl -D -` → `HTTP/2 200`, `server: cloudflare`, `strict-transport-security` present, `set-cookie: CF_Authorization=…` (Access granted). |
| **L7 — application** | ✅ verified — **this is the fault** | Full CI path reproduced locally with `cloudflared access tcp --hostname registry.soleur.ai --url 127.0.0.1:15000`; `GET /v2/` through the bridge returned **zot's own** `HTTP/1.1 401 Unauthorized`, `Www-Authenticate: Basic realm="Authorization Required"`, body `{"code":"UNAUTHORIZED",…}`. No bad handshake **at that instant**. Combined with `zot_restarts` climbing 4/min, the origin is *intermittently* up — which is exactly the signature that defeats a single-sample health probe. |

### What is deliberately recorded as UNKNOWN

- **Why zot restarts.** `oom_kills=0` rules out the OOM class. The proximate crash reason is in
  the container's own exit status / logs on the host, which this planning session did not read.
  The plan does **not** assert a cause for the restart loop and does not fix it.
- **Whether the 20:29 bridge failure was origin-flap or something else.** My probe is a
  *different actor at a different time* — capability, not actuality. The `zot_restarts` +
  timeline correlation is very strong, but the deciding per-attempt datum (what the connector saw
  at 20:29:11) is not retained anywhere. **This is precisely the gap Deliverable A closes**: after
  this change, the next occurrence records its own discriminator instead of leaving the next
  reader to re-derive it.

---

## Research Reconciliation — Issue claims vs. codebase/live reality

| Issue claim | Reality | Plan response |
|---|---|---|
| "Check the Access application/policy — is the token still in an allow policy?" | It **is**. Policy intact, token identity matches Doppler byte-for-byte, expires 2027. | Scope item closed as **investigated and refuted**. No policy change. The *measured* refutation becomes the new error text's H2 arm. |
| "Confirm the **registry host's** `cloudflared` connector re-registered after the 17:13 reboot" | There is no `cloudflared` on the registry host; the connector is web-host-side and never re-registered because it never dropped. Also the registry host never rebooted (18d uptime). | Scope item closed as **refuted**. The wrong mental model is itself worth fixing — see Deliverable D (docs/C4 already state this correctly at `model.c4:457`; the *advisory* does not). |
| "In-job log: `live entries: 3`" | The in-job preflight prints **`live entries: 1`** (it runs `--only REGISTRY_PUSH_ACCESS_TOKEN`, and `DOPPLER_TOKEN_PRD` reads exactly one config). `3` is the *local* fleet-wide scan. | Cosmetic; noted so no AC greps for `3`. Confirms the preflight checks **the same config the bridge reads** — so its verdict is genuinely load-bearing. |
| "#7232's registry host reboot is the leading hypothesis" | Refuted (H3/H4). | Not imported as work. #7232 remains a closed contextual citation. |
| `mirror_reason=bridge` message is the only misdiagnosis site | There are **two** sites: `reusable-release.yml:1059` (the `degraded bridge` detail) **and** `.github/actions/cf-tunnel-registry-bridge/action.yml:188` (the `::error::` on docker-login failure, the only `stale-service-token` literal in the repo). | Both are in `## Files to Edit`. Fixing only one leaves the other shouting the refuted diagnosis. |
| — (not in issue) | `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` repeats the same "single most likely explanation: a rotation that did not propagate" framing, **and** carries a clause (`branch configs inherit it`) that the detector itself now contradicts. | Folded in — Deliverable D. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is release infrastructure.
The *indirect* impact is what matters and is already live: production is pinned three releases
behind, so every bug fix and feature merged after 16:35 UTC is invisible to users until the
mirror recovers. A misdiagnosing error message extends that window by however long the operator
spends on the refuted hypothesis (measured precedent: the 2026-07-29 incident spent its entire
diagnostic budget on a refuted cause).

**If this leaks, the user's data/workflow/money is exposed via:** no user data is on this path.
One handling note: `cloudflared` prints the CF Access service-token **secret in cleartext** at
`--loglevel debug` (observed during planning). The CI action correctly uses `--loglevel warn`;
any change to this path must keep it there, or the secret lands in a retained CI log.

**Brand-survival threshold:** `aggregate pattern` — a slow-deploy window is a compounding
credibility cost, not a single-user incident. No CPO sign-off gate.

---

## Deliverable A (PRIMARY) — failure messages consume the in-job verification

### A1. Thread the preflight verdict out of `token_preflight`

`reusable-release.yml` step `id: token_preflight` currently computes `rc`, prints a sentence, and
**discards it**. Nothing downstream can read it.

Add `--json-file` + a `$GITHUB_OUTPUT` write. Both patterns already exist in-repo and should be
copied rather than invented:

- `.github/workflows/scheduled-terraform-drift.yml:231` — `--json-file "$RUNNER_TEMP/token-drift.json"` then a `python3 -c` parse into `$GITHUB_OUTPUT`.
- `.github/actions/cf-tunnel-ssh-bridge/action.yml:324` — `--only CI_SSH_ACCESS_TOKEN --json-file …`.

```bash
rc=0
bash scripts/check-cloudflare-token-drift.sh --only REGISTRY_PUSH_ACCESS_TOKEN \
  --json-file "$RUNNER_TEMP/registry-push-token.json" || rc=$?

# Parse the JSON. rc ALONE IS NOT ENOUGH — see the correction note below.
read -r dead unver < <(python3 -c '
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(int(d.get("dead",-1)), int(d.get("unverifiable",-1)))
except Exception:
    print(-1,-1)
' "$RUNNER_TEMP/registry-push-token.json")

if   [[ "$rc" != 0 && "$rc" != 1 ]];        then verdict=unmeasured   # rc=2: nothing was checked
elif [[ "$dead" == -1 || "$unver" == -1 ]]; then verdict=unmeasured   # verdict file unreadable
elif [[ "$dead" -gt 0 ]];                   then verdict=stale        # MEASURED dead
elif [[ "$unver" -gt 0 ]];                  then verdict=unverifiable # measured "could not tell"
else                                             verdict=live
fi
printf 'verdict=%s\n'    "$verdict" >> "$GITHUB_OUTPUT"
printf 'checked_at=%s\n' "$(date -u +%H:%M:%SZ)" >> "$GITHUB_OUTPUT"
```

**Correction applied at plan review (this was the plan's own thesis, violated in its primary
deliverable).** The first draft mapped `rc=1 → stale`. But the script exits 1 when
`DEAD_N > 0 **OR** UNVERIFIABLE_N > 0` (`check-cloudflare-token-drift.sh:1143`), and
*unverifiable is not stale — it is unmeasured*. A transient network fault during the preflight
would have printed **"the token is STALE, rotate it"** about a token nothing measured: exactly the
defect this plan exists to drain.

The precedent the plan cites as the thing to copy says so inline. `scheduled-terraform-drift.yml:235-238`:

> *"Exit 1 covers BOTH 'a token is dead' and 'a token could not be verified', and exit 2 means
> nothing was checked at all — three states calling for three different operator actions, which is
> why collapsing them let the old single email assert a cause the detector never claimed."*

That workflow derives **four** values from the JSON. The first draft added `--json-file` and then
never read it, leaving the verdict on `rc` alone — strictly weaker than the pattern it claimed to
copy, with the JSON as dead weight. Hence **four** verdicts, and `checked_at` (which AC6's cited
message literal requires and which nothing previously produced).

**Load-bearing:** keep `|| rc=$?`. Actions runs `run:` under `bash -eo pipefail`; a bare
invocation aborts the step at that line and the `case` never executes. The step's comment records
this having already happened once.

`--json-file` also has its own exit-2 path (unwritable path), which lands on the same `*` arm —
correct, because "the verdict file could not be written" is genuinely *unmeasured*.

**Default when the step did not run.** `token_preflight` is gated on
`steps.version.outputs.next != '' && inputs.docker_image != ''` and is `continue-on-error: true`.
Consumers MUST read `steps.token_preflight.outputs.verdict` with a `|| 'unmeasured'` fallback —
an unset output must degrade to *no conclusion*, never to *live*.

### A2. ~~Add an Access-vs-origin discriminator probe~~ — **CUT at plan review**

**A2 was wrong and is deleted in full.** It is recorded here rather than silently removed,
because the mistake is the most instructive thing in this plan.

A2 proposed a curl to `https://registry.soleur.ai/v2/` with the service-token headers, grading
`403` vs `200` to separate "Access refused" from "origin unreachable". Three verified facts kill it:

1. **The job already does this.** `scripts/check-cloudflare-token-drift.sh:651`
   `access_hostname_for()` maps `REGISTRY_PUSH_ACCESS_TOKEN` → `registry.${APP_DOMAIN_BASE}`.
   The preflight's probe is already aimed at exactly that hostname with exactly those headers.
2. **The 200/403 pair I "measured" was already measured and recorded**, on 2026-08-01, in that
   same file (`:668-672`) — including the zero-byte body I observed:
   `admitted -> 200, 0 bytes, no Access stamp` / `rejected -> 403, ~39 kB, cf-access-aud + -domain`.
3. **Grading on the status code is a deleted anti-pattern.** `:661` records that revision #7127
   graded on status and that the theory was false; `:676-680` concludes *"Grading on the status
   code is the wrong instrument regardless of which codes it maps… the discriminator is the
   Access **stamp**, not the status."* A2 would have reintroduced precisely what #7127 removed.

**Therefore `verdict=live` already means "the token authenticates AND Cloudflare Access admitted
it on `registry.soleur.ai`."** The `live`/`403` cell is unreachable by construction: an
Access-rejected credential grades DEAD or UNVERIFIABLE and exits 1, which is `verdict=stale`.
The 2×2 has one live column, so there is no matrix — only the verdicts the preflight
already computes.

The irony is the point, and it is why this section stays visible: **a plan whose thesis is "never
name a cause the job did not measure" proposed measuring something the job measured six minutes
earlier, and asserted the preflight could not answer the question the preflight exists to answer.**
Deliverable A1 is the entire mechanism. Everything else was scaffolding.

**Consequently deleted:** the probe, `EDGE_CODE` and its `$GITHUB_ENV` export, the `tcp://`
semantics comment, the `live`/`403` and `*`/`000` arms, AC4, two risk rows, two `failure_modes`
entries, two test scenarios, and one Sharp Edge.

**Semantics — state these verbatim in the code comment, they are subtle and easy to misread.**
The `registry.*` ingress is `tcp://`, not `http://`. A plain HTTPS GET therefore **cannot** reach
zot as HTTP; the `200` is the edge's answer for a non-WebSocket request to a tcp ingress. So this
probe proves **only** that Access authorized the request. It is *not* a zot health check, and the
message must never present it as one. That distinction is exactly what makes it a clean
discriminator: it isolates the authorization layer from everything behind it.

Verified both arms live during planning (control + treatment), per the ADR-130 discipline: a bare
403 could be a bad token, a wrong hostname, or a typo'd URL — 403-without-creds **and**
200-with-creds together isolate it to the authorization decision.

### A2b. The `live` arm must TERMINATE — measure the origin hypothesis in-job

Deleting A2 leaves a real gap: the preflight settles the **authorization** hypothesis, and nothing
settles the **origin** one. The first draft closed that with prose — *"First check: is
`zot_restarts` climbing?"* — which is a dashboard-eyeball instruction to a non-technical operator
and a direct `hr-no-dashboard-eyeball-pull-data-yourself` violation. It is also, by the plan's own
ADR, a ranked hypothesis rather than a measurement.

**Measure it instead.** Verified available: `web-platform-release.yml:95` declares
`secrets: inherit`, `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` are Actions secrets already used
by four workflows, and `scripts/betterstack-query.sh` is in the checked-out tree. So on the
bridge-failure path the job can read the registry host's own restart series and **print it**:

```
zot_restarts over the last 3h: 0 → 950 (+~20 per 5-min sample, oom_kills=0)
→ the registry was restarting ~4x/min while this push ran.
```

That is the deciding datum, captured at the moment it is produced, on an ephemeral runner where it
is otherwise destroyed. It replaces the one instruction the operator could not execute with the
answer they would have gone looking for. Fail-soft: if the query errors, say so — never convert a
query failure into a claim about zot.

### A3. Branch on the verdict — four arms, no matrix

`EDGE_CODE` is gone with A2, so the message keys on `verdict` alone. Four values, four arms
(the fourth, `unverifiable`, was added at review — collapsing it into `stale` was the plan's own
thesis violated in its primary deliverable):

| `verdict` | What the message says |
|---|---|
| `live` | *"The Preflight step in this job at `<checked_at>` presented these exact credentials to `registry.soleur.ai` and Cloudflare Access **admitted** them. Rotating the token will not help — this job proved it."* Then the measured `zot_restarts` series from A2b, and the plateau-gated re-run instruction. ← **today's incident** |
| `stale` | A **measured** DEAD value: rotation genuinely is the remedy. State the corrected remedy (below), not the falsified one. |
| `unverifiable` | The credential **could not be graded**, and the script says why — surface its own `cause` verbatim (`gate-indeterminate`, `stamped-non-refusal`, `unexpected-status`, `refused-unstamped`), each of which already carries a *"Do NOT rotate"* instruction. |
| `unmeasured` | Nothing was checked (rc=2 / unreadable verdict file). List candidates **unranked** and give a base case: if the settling probe is itself unavailable, escalate to the crash-loop issue rather than looping on a probe that just failed. |

**The `live` arm's claim rests on one mapping — cite it.** `verdict=live` means "Access admitted
it" only because `access_hostname_for()` maps `REGISTRY_PUSH_ACCESS_TOKEN` → `registry.*`. Add an
inline comment naming that function, so a future edit that drops the mapping cannot silently
hollow out the "rotating will not help" claim. (It fails safe today — an unmapped token grades
UNVERIFIABLE, not live.)

**The `live` arm must not over-claim.** It settles the *Access credential* only. It says nothing
about `ZOT_PUSH_USER` / `ZOT_PUSH_TOKEN`, a distinct docker-login failure mode that must not be
absorbed into "origin-side".

**Corrected remedy on the `stale` arm.** Both message sites currently say *"set the live value on
the **prd ROOT** config"* — the same clause Deliverable D fixes in the runbook because
`check-cloudflare-token-drift.sh:1049` calls it **`FALSIFIED`**. Fixing the runbook while the
messages keep repeating it would be incoherent. State which configs must actually be written, and
assert its **presence** (AC), not merely the old clause's absence.

### A3d. Extract the diagnosis text to a sourced script — the structural fix

*(Adopted from review: the option the first draft never considered.)*

The mirror `run:` block is **21,523 bytes / 270 lines — 5.2× the next-largest step** in
`reusable-release.yml`, and the existing suite awk-extracts and executes that whole block under
PATH stubs. Adding per-arm assertions means driving 270 lines four times to compare four strings,
in a file where `scripts/lint-workflows.sh:4-9` already documents actionlint deadlocking past the
65 kB pipe buffer.

This repo already solved this shape: `scripts/inngest-liveness-classify.sh` is a pure classifier
`source`d by `scheduled-inngest-health.yml:90` and unit-tested directly by its own
`*.test.sh`. Siblings: `inngest-restart-poll-classify.sh`, `prod-version-drift-check.sh`,
`zot-restart-loop-alarm.sh`.

Do the same: **`scripts/zot-mirror-diagnosis.sh`** exposing `zot_mirror_diagnosis <verdict> <checked_at> <restart_summary>`, `source`d by **both** the workflow step and the composite action. This is cheaper on every axis:

- The arm text leaves YAML; each `run:` grows ~2 lines instead of ~40 of prose.
- Per-arm tests become direct function calls in `scripts/zot-mirror-diagnosis.test.sh` — no awk
  extraction, no stubs, no anti-vacuity arithmetic, and `scripts/lint-orphan-test-suites.sh`
  registers `scripts/*.test.sh` automatically.
- **A4's "both messages tell the same story" becomes true by construction** rather than an
  assertion someone must remember. The first draft created *two* copies of the arm set in two
  files with nothing binding them — the exact liability it named ("fixing only one leaves the
  other shouting the refuted diagnosis") and then reproduced.
- T9 shrinks to one assertion that the block calls the helper; the ≥20 floor never moves, honoring
  its own comment (*"A FLOOR, not equality, so adding a case never requires editing this line"*).

Verify at /work: a composite action under `.github/actions/` can `source "$GITHUB_WORKSPACE/scripts/…"` (it runs in the caller's workspace; `scheduled-inngest-health.yml` uses that path form).

### A3b. The ops email makes a promise this design deliberately breaks

`reusable-release.yml:1239` — the operator's **first** touchpoint — ends: *"the failing step names
**the cause** and **the one command** that fixes it."* False today, and false by design on the
`unverifiable` / `unmeasured` arms. Reword to promise what the run delivers: what was **measured**,
and what it rules in or out. Carry `verdict` into the email body so the operator can triage without
opening the run.

### A3c. The right telemetry was already named — but framed too narrowly to be reached

`degraded()` (`reusable-release.yml:958`) already ends every failure with *"If disk-full: see
SOLEUR_ZOT_DISK / Better Stack registry_disk_prd."* `SOLEUR_ZOT_DISK` is **the marker carrying
`zot_restarts`** — the field that settles this incident. The pointer was always there; the
`If disk-full:` prefix made it unreachable. Widen it to registry-host health generally.

### A4. **Three** sites, not two

`.github/actions/cf-tunnel-registry-bridge/action.yml:150` is a third unmeasured-cause site, on
the listener-timeout path: *"(CF Access registry_push token may be expired/missing, or the zot
host is down)"*. More honest than `:188` — it offers both — but still names causes nothing
measured, and *"the zot host is down"* is the arm today's incident lands on. Fold it in.

`:188` is the repo's only `stale-service-token` literal and the acute one.

### A4b. Passing the verdict into the composite action

Composite actions cannot read caller step outputs, so add an input defaulting to `unmeasured`:

```yaml
token-verdict:
  description: 'live|stale|unverifiable|unmeasured. Branches the failure message only.'
  required: false
  default: unmeasured
```

`reusable-release.yml` passes `${{ steps.token_preflight.outputs.verdict || 'unmeasured' }}`.
The `||` guard is load-bearing at **both** consumers: a composite `default:` does **not** apply
when an input is passed as an explicit empty string, so the default alone is not protection.

### A4c. **Three consumers**, and two of them have no preflight

`cf-tunnel-registry-bridge` is a **shared action with three callers** — verified:

| Caller | Line | Has a token preflight? |
|---|---|---|
| `reusable-release.yml` | 786 | yes (`token_preflight`) |
| `build-inngest-config-bundle.yml` | 125 | **no** |
| `build-inngest-bootstrap-image.yml` | 230 | **no** |

The input is backward-compatible, but the *semantics* are not: both inngest workflows would
permanently pin the `unmeasured` arm, whose contract is "list the candidates unranked." Today they
get a concrete (if often wrong) remedy; after this change they would get an unranked list — an
**actionability regression in two workflows** the first draft never mentioned. This is producer-side
union widening across a shared boundary (`hr-type-widening-cross-consumer-grep`,
`cq-union-widening-grep-three-patterns`), and the first draft did no cross-consumer sweep.

**This exact miss is already on record for this exact action.**
`knowledge-base/project/specs/feat-one-shot-zot-mirror-fail-closed/decision-challenges.md:32`:
*"Blast radius the plan initially missed: `cf-tunnel-registry-bridge` is a shared action with three
consumers."* Second time. That is itself the argument for Deliverable E.

**Fix (cheap):** both inngest workflows already pass `secrets.DOPPLER_TOKEN_PRD`, so the preflight
is a copy-paste. Add it to both. Failing that, the `unmeasured` arm must be actionable standalone
and the action's input description must say `unmeasured` is those callers' steady state.

### A5. Constraints the existing tests impose

`plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` extracts the real `run:` block.
**T9** (`:340-351`) greps for `UNPUBLISHED DRAFT`, `Re-run failed jobs`,
`check-cloudflare-token-drift.sh`, and asserts `apply-deploy-pipeline-fix.yml` is **absent**.

The first two live in the shared `SAFE_TO_RERUN` suffix (`:952`) appended to **every**
`degraded()` call, so asserting them "per arm" is **vacuous** — it passes for any arm, including a
blank one. Keep one global assertion for those; put the discriminating assertions in
`scripts/zot-mirror-diagnosis.test.sh` (A3d), where they are direct calls.

`check-cloudflare-token-drift.sh` must survive on the `stale` / `unverifiable` / `unmeasured` arms
and must **not** headline the `live` arm. **T4** (`"1 degraded loud 0 bridge"`) and **T5**
(a `skipped` bridge is not a failure) must not change.

`token_preflight` has **zero** coverage today — A1's `$GITHUB_OUTPUT` contract breaks nothing and
is protected by nothing. New coverage is mandatory.

---

## Research Insights (deepen-plan)

All verified live against the repo during the deepen pass. These are implementation constraints,
not suggestions — each one would have cost a mid-`/work` pivot.

### R1 — The composite action CAN reach `scripts/`, and the path form matters

**Precedent exists for *invoking*:** `.github/actions/bot-pr-with-synthetic-checks/action.yml:215,240`
runs `node apps/web-platform/scripts/…` and `python3 scripts/lint-credential-path-literals.py` with
**bare relative paths and no `working-directory` key anywhere in the file**. That confirms
empirically that a composite action's `run:` executes with the *caller's* workspace as cwd. It is on
the required-check path (ADR-139), so it is exercised on every bot PR — live evidence, not aspiration.

**But `source` has no composite-action precedent** — it is exclusively a workflow-level pattern today
(`scheduled-inngest-health.yml:88-90`, `restart-inngest-server.yml:90`, ~20 sites in
`apply-web-platform-infra.yml`). The dominant form is absolute:

```bash
# shellcheck source=/dev/null
source "$GITHUB_WORKSPACE/scripts/zot-mirror-diagnosis.sh"
```

**Use the absolute `$GITHUB_WORKSPACE` form**, not a bare relative path: it is robust if a caller ever
sets `working-directory` on the job defaults, and it matches the 20+ existing `source` sites.

**Mirror the one-line discipline.** `cf-tunnel-ssh-bridge/action.yml:319-324` keeps its
`check-cloudflare-token-drift.sh` invocation on **one physical line** because a test greps for it to
prove the gate is defined exactly once. If AC6 greps for the helper call, keep it on one line.

### R2 — The classifier library must NOT set `-euo pipefail`

Copying `scripts/inngest-liveness-classify.sh` exactly:

- `#!/usr/bin/env bash`, **no `set -euo pipefail`**, and **no top-level executable code** — it is a
  pure library. This is load-bearing: it is sourced into a step already running under
  `bash -eo pipefail {0}`, so a `set -e` here would **leak into the caller** and change the failure
  semantics of the very step it is diagnosing.
- Header comment enumerating every token the function can echo (a **Modes:** table). Our four
  verdicts go there.
- Functions echo exactly one token to stdout and `return 0`; predicates return via exit status.
- The argument contract is documented immediately above the function.

Caller shape: `MODE=$(classify_liveness_mode "$CODE" "$BODY")` then `case "$MODE" in`.

Test shape (`scripts/inngest-liveness-classify.test.sh`): `set -euo pipefail`, resolve via
`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, **source** (never execute), then
`assert_eq "desc" "expected" "$(fn args)"` per case, with a comment naming the defect each case
regresses. Footer: `echo "=== Results: $PASS passed, $FAIL failed ==="` then `[[ "$FAIL" -eq 0 ]]`.

**Registration is mandatory, not optional.** `scripts/lint-orphan-test-suites.sh` walks every
`scripts/*.test.sh` and fails if it is not referenced by `test-all.sh`; its `EXCLUSIONS=()` is empty
and documented as *"EMPTY IS THE GOAL STATE"*. It runs at `.github/workflows/ci.yml:178`. So
`scripts/zot-mirror-diagnosis.test.sh` **must** get a `run_suite` line (pattern:
`test-all.sh:445`) or CI reddens.

### R3 — Deliverable E's lint would land in an ADVISORY job — this changes the deliverable

**Only one lint in the repo uses a `.highwater` baseline**: `scripts/lint-trap-tempfile-ownership.py`.
Its mechanism is the right template:

- `HIGHWATER_FILE = Path(__file__).resolve().parent / "<name>.highwater"` — cwd-independent.
- Comment-tolerant parse: `int(HIGHWATER_FILE.read_text().split("#")[0].strip())`.
- Three modes: `--census` (count, exit 0), `--check-highwater` (compare), default (scan).
- **A missing baseline is a hard error (`return 2`), never a pass.**
- Regression (`live > allowed`) → exit 1 with a remedy-bearing message. Improvement
  (`live < allowed`) → exit 0 with a `note:` to ratchet down. Blocking upward, advisory downward.
- **Anti-vacuity positive control** (`lint-trap-tempfile-ownership.test.sh:152-160`): assert
  `--census` returns a **non-zero** integer, because *"a high-water check whose census always
  returned 0 would pass forever."* Copy this — our lint is exactly the shape that could count zero
  and certify silence.

**The caveat that changes the deliverable:** both highwater steps run in the `lint-bot-statuses` job
(`ci.yml:122`), and `ci.yml:165-172` states that job is **ADVISORY — absent from both
`scripts/required-checks.txt` and the Terraform ruleset**, so a PR can merge with it red. A lint that
cannot block is a lint that will be ignored, and Deliverable E exists precisely because prose did not
hold for two iterations.

So Deliverable E must either (a) add the lint to `required-checks.txt` **and** the Terraform ruleset
together (they must move as a pair), or (b) explicitly accept advisory-only status and say so, rather
than claiming an enforcement it does not have. **Do not silently inherit the advisory job** — that
would be this plan shipping its own thesis violation a fourth time.

### R4 — Institutional learnings that bear directly on this plan

**R4.1 — `|| rc=$?` makes the step SUCCEED, which can disarm a downstream `outcome == 'failure'` gate.**
([`2026-07-30-the-step-that-could-not-report-and-the-guard-that-worked-in-one-scan-mode.md`](../learnings/2026-07-30-the-step-that-could-not-report-and-the-guard-that-worked-in-one-scan-mode.md))
This is a live trap for A1. The mirror step branches on
`BRIDGE_OUTCOME: ${{ steps.zot_bridge.outcome }} == 'failure'`. Any refactor that swallows a
non-zero exit into `rc` flips that step's `outcome` to `success` and the `degraded bridge` arm
**never fires** — re-entering the #6416 silent-mirror defect. `token_preflight` is safe (nothing
gates on its outcome), but **do not** apply the same `|| rc=$?` idiom to `zot_bridge` without
re-checking every `outcome`-reading consumer. Add this to Phase 0.

**R4.2 — A guard that RESTATES the value it guards is a second unsynchronized pin.**
([`2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens.md`](../learnings/2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens.md))
`lint-diagnosis-claims.sh` (Deliverable E) is exactly this shape — its causal-phrase list restates
prose that lives in the messages. A stale phrase list fails **green**, not red. Mitigate with a
non-vacuity control arm: a fixture message that *must* trip the lint, plus one that *must not*.
This is the same requirement as AC23 and the `--census`-returns-non-zero guard in R3.

**R4.3 — A check that cannot report is indistinguishable from one that passed.**
([`2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`](../learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md))
Eight recorded instances; instance 1 is a gate that is never *called*. Its prescriptions are AC6
and AC23 verbatim: assert the **invocation**, not the definition, and prove the check *can* fail via
mutation. This is also the precise shape of Deliverable B2 — seven steps that could never report.

**R4.4 — Closing an issue that a code comment names by number obliges a `git grep` of that number.**
([`2026-07-30-the-comment-that-named-a-cause-was-the-cause-of-the-misdiagnosis.md`](../learnings/2026-07-30-the-comment-that-named-a-cause-was-the-cause-of-the-misdiagnosis.md))
This is the same repo, the same code path, and the direct ancestor of this issue: a comment
speculating "the tunnel connector may lack a private-net route" outlived the issue's closure
(2026-07-17) and became the default hypothesis months later. Deliverable D's sibling sweep is that
obligation being discharged — extend it to `git grep -n '#6416\|#7071'` across workflows, actions,
runbooks and `.c4`, and update or delete what each explains.

**R4.5 — Measure the alarm's real jitter; never copy a margin from a sibling.**
([`2026-08-02-my-alarm-could-go-silent-four-ways-and-a-fixture-pinned-one-of-them.md`](../learnings/2026-08-02-my-alarm-could-go-silent-four-ways-and-a-fixture-pinned-one-of-them.md))
If Deliverable B2 touches the Sentry cron monitor's `checkin_margin_minutes`, derive it from
`gh run list --workflow=scheduled-zot-restart-loop.yml --event=schedule --limit 60` (median, max,
gaps) — a margin copied from a sibling that is *also* permanently missed is a silent alarm.

**R4.6 — `::add-mask::` before any secret reaches `$GITHUB_ENV`.**
([`2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md`](../learnings/2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md))
Relevant to A2b only insofar as it must never echo credentials; the plan adds no new secret
handling, and the Sharp Edge on `--loglevel debug` covers the one real exposure on this path.

---

## Deliverable B — the alarm that cannot fire, and the one false claim in the advisory

### B1. **CUT** — the `serving is FINE` rewrite was aimed at the wrong advisory

*(Two reviewers converged on this independently; recorded rather than silently dropped.)*

`scheduled-zot-restart-loop.yml:263` sits inside the step **`Open or comment private-NIC self-heal
advisory (NIC ADVISORY)`** (`:240`), titled `[ci/registry-private-nic] Registry private-NIC boot
race self-healed` (`:251`). Its body is built from `NIC_ALARM_CAUSE`/`NIC_ALARM_DETAIL`
(`zot-restart-loop-alarm.sh:291-298`), which read `SOLEUR_PRIVATE_NIC`.

"Serving is FINE" there means *"the NIC boot race self-healed"*. Its basis is `nic_ok=true` +
`reboot_count>0` — **not** the read-path probes the first draft attributed to it. So the proposed
replacement (*"this advisory probed the read path, one sample per 60 s"*) would have written a
**new false claim** into the body: that advisory probes no registry endpoint at all. Writing an
unmeasured claim is the same defect in the other direction. **B1/B2/B3 cut.**

The read-path-only argument is true and valuable — but it belongs to the `[ci/zot-restart-loop]`
leg and the `zot-liveness-heartbeat` / consumer-probe surfaces, which is where the "systematically
biased toward fine" reasoning actually holds. Moved to the deferred alarm issue.

### B2. The alarm is structurally incapable of filing an issue — **one word × 7 steps**

**Measured, not inferred** (the first draft asserted this loosely and was corrected at review):

- Run `30851584863` (20:44): step `Run zot restart-loop checker` → **failure**; **all seven**
  issue-filing steps → **skipped**; `Sentry check-in (final)` → success with `STATUS: ok`.
- The seven steps carry plain conditions — `if: steps.alarm.outputs.exit_code == '1'` (`:133`),
  `== '3'` (`:169`), `nic_verdict == 'FIRE'` (`:204`), `'ADVISORY'` (`:241`), `'SILENT'` (`:287`),
  `'GREEN'` (`:322`), `exit_code == '0'` (`:346`) — **none contains a status-check function**, so
  each inherits an implicit `success()` and skips whenever *any earlier step failed*.
- Only `:373` has `if: always()`, which is why the Sentry step ran at all. And `STATUS: ok`
  proves `exit_code` **was** written (`:383` evaluates `ok` only for `0|1|3`) — so the outputs
  exist; the steps skip purely on the failed-predecessor rule.

So whenever the checker step exits non-zero — **including a FIRE, which is exit 1 by design** —
every issue-filing step is skipped. **The recurrence alarm built for this exact failure (#6291)
cannot open its issue on the one verdict it exists to report.** That is why a textbook 4/min climb
produced no `[ci/zot-restart-loop]` issue.

Fix: `if: always() && steps.alarm.outputs.… == '…'` on all seven. Pull **in scope** — it is
smaller than anything else in this plan and it restores the operator's only recurrence detector.

**Precedent — the sibling detector already does exactly this.**
`scheduled-terraform-drift.yml:444` reads
`if: always() && steps.token_drift.outputs.verdict == 'dead'`, and the `always() &&` form appears
in **8** workflows (`infra-validation.yml:1213`, `apply-web-platform-infra.yml:973`,
`web-platform-release.yml:918,1152`, `fix-constraints-stage-b.yml:281`,
`scheduled-supabase-advisor-scan.yml:311`, `scheduled-terraform-drift.yml:444,458`). The zot alarm
is the outlier, not the innovation.

**The same latent defect exists in a sibling alarm — widen the lint to catch it.**
`scheduled-inngest-health.yml` gates its issue-filing steps on plain conditions with no status
function (`:354`, `:377`, `:388`, `:574`, `:624`, `:670`, `:815`, `:874`); only `:686` has
`always()`. So any failure in its checker step silently skips its issue filing too. **Do not fix it
in this PR** (different alarm, different blast radius) — but `scripts/lint-diagnosis-claims.sh`
(Deliverable E) should grow a companion check, or a sibling lint should assert that *any step whose
`if:` references `steps.<id>.outputs.*` for issue-filing carries a status-check function*. File it
with the Phase 1 issues.

**Defense-in-depth on the same file (one expression).** The Sentry status at `:383` keys on
`exit_code` alone, so a checker that aborts *without* emitting a verdict is indistinguishable from
a real FIRE and checks in **green** — ADR-166's defect class in the monitor itself. The
discriminator already exists in the same step's outputs: require
`exit_code == '1' && verdict == 'FIRE'`. Cheap, and it closes the "green while broken" window
regardless of why the checker exited.

*(The first draft's claim that the Sentry check-in "falsely reported ok" is **withdrawn**: `ok` is
correct-by-design for a FIRE — `:379-382` says so explicitly. The defect is the skip rule, not the
check-in.)*

### B4. The false causal claim — the one that produced H3 and H4

`NIC_DETAIL` asserts *"the NIC was ABSENT at boot and the guard converged it by REBOOTING"*
whenever window-max `reboot_count > 0`. `reboot_count` is **cumulative and persisted**: measured
`reboot_count=1` alongside **18.2 days** uptime and an unchanged `boot_id`.

**This false claim is what produced the issue's own steps 1 and 2** (hypotheses H3/H4 — "the host
rebooted at 17:13", "confirm the connector re-registered"). It is the highest-value non-message fix
in the plan.

Gate the reboot claim on in-window evidence: a `boot_id` change, or `uptime_s < RECENT_BOOT_S`
(**define the constant explicitly** — an undefined "recent" lets implementation and test each pick
a different number and both pass). With `<2` in-window samples, fail toward **no claim**.

---

## Deliverable C — recovering the three blocked drafts

**Re-run failed jobs**, never a fresh dispatch (which recomputes the version and can strand the
draft). Automatable, therefore not an operator step.

**Do not hand-roll the plateau gate — it already exists.**
`scripts/followthroughs/zot-restart-plateau-6288.sh` is a plateau prober with exactly the right
contract (`0 = PASS (plateau holds)`, `1 = FAIL (still climbing)`, `2 = TRANSIENT`), newest-`boot_id`
scoped via `scripts/lib/zot-telemetry-parse.sh`, fail-safe on query faults, and **already wired into
`scheduled-followthrough-sweeper.yml`** with the `BETTERSTACK_QUERY_*` secrets. The first draft
re-derived "two consecutive zero-delta samples" in prose — a second, divergently-maintained
definition of plateau.

Wire the re-run to that prober **on the sweeper's schedule, not to `/work`** — `/work` is
session-scoped, so a `/work`-owned gate is an operator checklist item in disguise
(`wg-block-pr-ready-on-undeferred-operator-steps`, `hr-ship-message-no-operator-checklist`).

**Never-plateaus branch (previously a dead end):** escalate to the crash-loop issue. State that
`allow_unmirrored_reason` publishes the draft but does **not** make the image pullable, so the
deploy still will not land — the operator must not read it as a fix.

**`SAFE_TO_RERUN` self-contradiction (pre-existing, now inherited by every arm):** it says *"do NOT
start a fresh 'Run workflow' dispatch"* and one sentence later *"re-dispatch
web-platform-release.yml with `allow_unmirrored_reason=<why>`"* — a fresh dispatch. Resolve in the
same edit, and carry the plateau condition inline on the `live` arm so the message does not tell
the operator to do the one thing this plan says must not be done unqualified.

---

## Deliverable D — the docs that repeat the refuted diagnosis

*(Promoted: highest value-per-line in the plan — two sentences, no test, no plumbing.)*

- `zot-registry-revert.md:128` — *"a 'websocket: bad handshake' from cloudflared = the EDGE
  rejected you, which is the stale-Access-token shape, **not an origin problem**."* **False**, and
  the single sentence that most directly produced this misdirection. Today's measurement is the
  counter-example: a crash-looping **origin** produced a bad handshake with Access admitting the
  request.
- `zot-registry-revert.md:76` — *"branch configs inherit it."* `check-cloudflare-token-drift.sh:12`
  states the opposite and **`:1049` names this clause verbatim and calls it `FALSIFIED`**. The repo
  already knows; the correction was never propagated back.
- `zot-registry-revert.md:66` — *"the single most likely explanation"* → cite the preflight verdict
  instead. Replacing the false sentence with the verdict pointer *is* the re-rank.
- `model.c4:457` — **AMEND, do not delete.** One reviewer argued for deletion (a C4 relationship
  is the wrong home for a diagnosis heuristic); a second read the surrounding context and showed
  deletion is unsafe: the sentence is explicitly framed as a **"2026-07-29 CAUSE CLASS (#7071)"**
  record whose stated purpose is to stop #6416 (a missing origin route) being re-derived as the
  explanation. Deleting it re-opens the failure mode the note exists to close. Its dichotomy is
  edge-refusal vs *missing route*; today's cause is a **third** case — route present, origin
  present-but-restarting. Amend to add that third case; keep the #7071 record intact.
- **Two sibling sites carry the same falsified claim and were missed by the first draft:**
  `cf-tunnel-registry-bridge/action.yml:7-9` (header), and `reusable-release.yml:1054-1056` — a
  comment asserting *"The MEASURED cause class is a CF Access service-token rotation that never
  propagated"*, which is an **unmeasured claim for today's incident, in a file this plan is already
  editing**. Sweep both.

---

## Deliverable E — the enforcement that actually breaks the cycle

Iterations one (2026-07-15) and two (2026-07-29) were each fixed by rewriting the message.
Iteration three rewriting it *better* generalizes nothing: every other `::error::` / `::warning::`
/ `degraded` message in `.github/workflows/` and `.github/actions/` stays free to name an
unmeasured cause, and the prose Deliverable D hand-corrects is prose the 2026-07-29 fix already
wrote once and which re-drifted.

Add **`scripts/lint-diagnosis-claims.sh`** — scan operator-facing message literals across
`.github/workflows/` **and** `.github/actions/` for causal-claim phrases (`most likely cause`,
`likely cause`, `serving is fine`, `not an outage`, `= the EDGE`, `which means`) and require
either a measured-verdict variable reference in the same block or an explicit `# MEASURED-BY:`
marker. Ship with a `.highwater` ratchet (precedent: `lint-trap-tempfile-ownership.highwater`) so
it lands green and drives down instead of blocking on a repo-wide sweep.

Note `.github/actions/**` is currently unlinted — `lint-workflows.sh:40-43` and
`lint-workflow-step-env-refs.py` both scan `.github/workflows/*.yml` only, which is precisely why
`action.yml:150` and `:188` went unexamined.

**Without this, the honest forecast is iteration four on a different message site.**

---

## Out of scope — surfaced, not silently dropped

`/work` files each as its own `action-required` issue **before merge**, not after (the first is the
production blocker; deferring the filing makes the deferral invisible until the PR is already in):

1. **zot is crash-looping — still, and unabated.** 1032 restarts by **21:25** (0 at 17:05,
   950 at 21:05), a steady ~4/min for 4h20m with `oom_kills=0`; a
   recurrence of the closed #6288. The active cause of the deploy blockage. This plan does **not**
   guess why it restarts. One cheap probe first: check whether the container's exit status/stderr
   reaches Better Stack — if it does, the deciding datum is a query away and needs no SSH.
2. **The read-path-only scoping of the zot health verdict** (moved here from B1) — the
   `zot-liveness-heartbeat` single 60 s sample cannot see a 4/min loop, and nothing anywhere probes
   the push path. B2 restores the alarm's ability to *file*; this issue fixes what it *claims*.

---

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/reusable-release.yml` | A1 JSON-parsed 4-valued `verdict` + `checked_at` (`token_preflight`, ~L514-551); A2b in-job `zot_restarts` read on the failure path; A3/A3d call the shared diagnosis helper from the `degraded bridge` arm (~L1059); A3b reword the ops-email promise + carry `verdict` (~L1239); A3c widen the telemetry pointer (~L958); A4b pass `token-verdict`; C resolve the `SAFE_TO_RERUN` dispatch contradiction (~L952). |
| `.github/actions/cf-tunnel-registry-bridge/action.yml` | A4 rewrite the docker-login `::error::` (~L188) **and** the listener-timeout `::error::` (~L150) via the shared helper; A4b new `token-verdict` input. Keep `--loglevel warn`. |
| `.github/workflows/scheduled-zot-restart-loop.yml` | B2 add `always() &&` to all seven issue-filing `if:` conditions (L133, 169, 204, 241, 287, 322, 346). |
| `scripts/zot-restart-loop-alarm.sh` | B4 gate the "converged by REBOOTING" claim on in-window boot evidence with a named `RECENT_BOOT_S` constant. |
| `scripts/zot-restart-loop-alarm.test.sh` | B4 case: no reboot claim when `uptime_s` contradicts a recent boot; `<2` samples → no claim. (N5/N15 need **no** edit — their needles are `"H2 confirmed"` / `"without a reboot"`, neither of which changes.) |
| `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` | Thin T9 to "the block calls the helper" + keep the one global `SAFE_TO_RERUN` assertion. T4/T5 unchanged; the ≥20 floor does not move. |
| `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` | D — the three sentences at `:66`, `:76`, `:128`. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | D — **amend** (not delete) the `:457` cause-class record to admit the third case. |
| `.github/workflows/build-inngest-config-bundle.yml` | A4c — add the token preflight (or record `unmeasured` as its steady state). |
| `.github/workflows/build-inngest-bootstrap-image.yml` | A4c — same. |
| `knowledge-base/engineering/architecture/principles-register.md` | AP-021 diagnostic-honesty row (AC24). |
| `scripts/test-all.sh` | Register the two new `scripts/*.test.sh` suites if the glob does not pick them up. |

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/zot-mirror-diagnosis.sh` | A3d — the sourced diagnosis classifier; single source of truth for both message sites. |
| `scripts/zot-mirror-diagnosis.test.sh` | Per-arm assertions as direct function calls (auto-covered by `lint-orphan-test-suites.sh`). |
| `scripts/lint-diagnosis-claims.sh` + `.highwater` | E — the enforcement that generalizes ADR-166 beyond this one path. |
| `knowledge-base/engineering/architecture/decisions/ADR-166-*.md` | See below. |

---

## Architecture Decision (ADR/C4)

### ADR

**ADR-166 — a CI-emitted operator-facing message may only name a cause the job measured.** Scope
widened at review from "this path" to **any diagnostic claim in any CI-emitted operator-facing
message, enforced by `scripts/lint-diagnosis-claims.sh`**. An ADR whose enforcement mechanism is
named *in the decision* is the only version that survives to iteration four; the first draft
listed "ADR-166 states the invariant" as the sole mitigation for its top risk, which is exactly the
unenforceable-prose failure the ADR is about.

Records: (a) messages branch on a measured verdict or explicitly declare *unmeasured*; (b) a
verdict must not collapse "could not check" into "bad" — the DEAD/UNVERIFIABLE/unmeasured
distinction is load-bearing; (c) where a cheap probe discriminates competing hypotheses, the
failing step runs it and reports the value; (d) enforcement is the lint, not the prose.

Ordinal **166** is provisional (ADR-165 is highest on disk). Re-derive against freshly-fetched
`origin/main` immediately before merge; if it moves, sweep `plans/`, `specs/`, and every AC naming
it in the same edit.

### C4 views

Read all three of `model.c4`, `views.c4`, `spec.c4`. External human actors: unchanged. External
systems: unchanged (Cloudflare Access/Tunnel, GitHub Actions, Better Stack, zot all modeled).
Containers/data stores: unchanged. Access relationships: unchanged — the verdict is a job-internal
value. **Correctness:** `model.c4:457`'s `tunnel -> zotRegistry` description asserts
bad-handshake ⇒ edge-refusal; today's measurement falsifies it as an if-and-only-if. Deleted per
Deliverable D. Re-run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing

Ships with this PR; no soak gate.

---

## Observability

```yaml
liveness_signal:
  what: SOLEUR_ZOT_DISK zot_restarts (existing, per-5min) — the climb/plateau signal that
        discriminates this failure class; plus the release job's mirror_status output.
  cadence: 5 min (host heartbeat); per-release (mirror_status)
  alert_target: scheduled-zot-restart-loop.yml -> [ci/zot-restart-loop] issue + Sentry cron
                monitor scheduled-zot-restart-loop
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (emitter);
                 .github/workflows/scheduled-zot-restart-loop.yml (consumer)
  ROUTE_STATUS: RESTORED BY THIS PR — but B2's `always()` sweep alone did NOT restore it, and
                claiming so was itself an unmeasured claim. The producer step aborted under
                `-e` before writing $GITHUB_OUTPUT, so every arm compared against unset. The
                route is restored by the `|| rc=$?` capture PLUS the sweep PLUS pairing the
                numeric arms with their verdict (GHA `==` coerces null to 0). Found at review.

error_reporting:
  destination: GitHub Actions annotations on the release run + notify-ops-email to
               ops@jikigai.com (now carrying `verdict`) + the [ci/zot-restart-loop] issue
  fail_loud: true — the mirror step has no continue-on-error; a bridge failure blocks the
             release and it stays an unpublished draft (nothing half-ships)

failure_modes:
  - mode: token measured DEAD (rotation did not propagate)
    detection: verdict=stale, from json.dead>0 (never from rc alone)
    alert_route: the stale arm + scheduled-terraform-drift
  - mode: token could not be graded (gate-indeterminate / stamped-non-refusal / unexpected-status
          / refused-unstamped)
    detection: verdict=unverifiable, from json.unverifiable>0; the script's own `cause` is surfaced
    alert_route: the unverifiable arm, which repeats the script's "Do NOT rotate" instruction
  - mode: origin flapping / zot crash-loop        # today's incident
    detection: verdict=live AND the in-job zot_restarts series shows a climb (A2b)
    alert_route: the live arm prints the series; independently [ci/zot-restart-loop] (via B2)
  - mode: nothing was measured (Doppler/CLI precondition missing, unreadable verdict file)
    detection: verdict=unmeasured
    alert_route: the unmeasured arm — ranks nothing, and has a base case when the settling
                 probe is itself unavailable
  - mode: the alarm's own issue-filing is skipped
    detection: checker step conclusion=failure with all seven filing steps skipped
    alert_route: closed by B2 (always() &&); Sentry cron monitor already errors on TRANSIENT(2)

logs:
  where: GitHub Actions run logs (90d); Better Stack Logs (hot + S3 archive) for
         SOLEUR_ZOT_DISK / SOLEUR_PRIVATE_NIC; the cloudflared bridge log is dumped by the
         action's own failure path and the caller's if:always() teardown
  retention: Actions 90d; Better Stack per source retention

discoverability_test:
  command: |
    gh run view <run-id> --log-failed | grep -E 'verdict=|zot_restarts'
    bash scripts/zot-mirror-diagnosis.sh live 20:23:05Z "0 -> 950"   # arm text, no CI needed
  expected_output: the release log names the measured verdict and the restart series; the helper
                   prints the live arm without a token-rotation headline
  # NO ssh anywhere on this path (hr-no-ssh-fallback-in-runbooks)
```

**Affected-surface note (§2.9.2).** The failing surface — a tunnel-mediated push from an ephemeral
runner — cannot be inspected after the fact. `verdict` + `checked_at` + the `zot_restarts` series
is the in-surface structured probe, and it discriminates all four hypotheses in a single event.
Today the deciding datum was destroyed at the moment it was produced.

---

## Encryption Posture

Not applicable — no new persistent store and no new cross-component connection. A2's proposed
extra TLS call was **cut**; A2b reuses the existing Better Stack query path already used by four
workflows with the same secrets. Gate skipped per §2.11.

---

## Acceptance Criteria

### Pre-merge (PR)

1. `token_preflight` writes `verdict` ∈ {`live`,`stale`,`unverifiable`,`unmeasured`} plus
   `checked_at`, derived from the **JSON** (`dead` / `unverifiable`), not from `rc` alone.
   Asserted behaviourally against a faked drift script.
2. `dead=0, unverifiable>0` yields `unverifiable` — **never** `stale`. This is the thesis
   assertion; without it the plan reproduces the defect it exists to fix.
3. An unreadable/absent verdict file, and rc=2, both yield `unmeasured`.
4. An unset `token_preflight` output resolves to `unmeasured` at **both** consumers via an explicit
   `|| 'unmeasured'` (a composite `default:` does not apply to an explicitly-empty input). Assert
   the negative: it must never resolve to `live`. *(YAML-expression assertion — stated as such, so
   it is not smuggled into a behavioural claim.)*
5. `scripts/zot-mirror-diagnosis.sh` returns four distinct texts; the `live` text does **not**
   headline token rotation, and cites `checked_at` and `access_hostname_for()`.
6. Both message sites (`reusable-release.yml` degraded-bridge, `action.yml:188` **and** `:150`)
   obtain their text from the shared helper — asserted by grepping for the `source`/call, so the
   two cannot drift.
7. The `stale` arm states the **corrected** remedy; assert its **presence** (not the old clause's
   absence, which false-fails on a file documenting its own prohibition).
8. The `unverifiable` arm surfaces the script's own `cause` value and repeats "Do NOT rotate".
9. The `unmeasured` arm ranks nothing and contains a base case for "the settling probe is itself
   unavailable".
10. On the failure path the job emits a `zot_restarts` series or an explicit "could not query"
    statement — never silence, and never a claim about zot derived from a failed query.
11. All seven issue-filing steps in `scheduled-zot-restart-loop.yml` carry a status-check function
    in their `if:`; verified by asserting each condition string contains `always()`.
12. `zot-restart-loop-alarm.sh` makes no "converged by REBOOTING" claim when `uptime_s` exceeds the
    named `RECENT_BOOT_S` constant or when fewer than 2 in-window samples exist.
13. `zot-registry-revert.md` no longer PRESCRIBES the `branch configs inherit` clause or the
    "bad handshake = the EDGE rejected you, not an origin problem" sentence, and `model.c4`'s
    cause-class record is AMENDED to admit the measured third case.
    **Corrected at implementation.** This AC originally said "no longer contains" (an
    absence-grep, which false-fails on a file that quotes its own retraction to warn against
    it — the exact trap AC7 names one screen above) and "is deleted" for `model.c4`, which
    contradicted Deliverable D, the Files-to-Edit table and the Sharp Edges. Deleting the
    record re-opens the #6416 re-derivation it exists to close, so AMEND won.
14. `scripts/lint-diagnosis-claims.sh` exists, scans **both** `.github/workflows/` and
    `.github/actions/`, and passes at its committed `.highwater`.
15. `ADR-166-*.md` exists (ordinal re-derived against `origin/main`) and names the lint as its
    enforcement mechanism.
16. `bash scripts/test-all.sh` passes — the gate's own invocation, not a hand-enumerated subset.
17. Both new `scripts/*.test.sh` suites are registered (or glob-covered) — `lint-orphan-test-suites.sh` clean.
18. `actionlint` clean on the edited **workflows**. *(Observation, not a new constraint:
    `.github/actions/**` is not linted today — `lint-workflows.sh:40-43` scans workflows only.)*
19. `--loglevel warn` unchanged in the bridge action — asserted by a real grep, not left as a wish.
20. **Cross-consumer:** all three callers of `cf-tunnel-registry-bridge` are accounted for — either
    both inngest workflows gain a preflight, or the `unmeasured` arm is asserted actionable
    standalone and the input description records it as their steady state.
21. `TOKEN_VERDICT` (and any value the extracted-`run:` harness must drive) reaches the mirror block
    via an `env:` mapping — **not** a `${{ }}` interpolation inside the run body, which bakes in as
    a literal and makes per-arm testing structurally impossible. Default-expand under `set -u`.
22. The composite action gets a syntax gate: `python3 -c 'import yaml; yaml.safe_load(open(…))'`
    plus `bash -n` on its extracted `run:` bodies. It is the one edited file `actionlint` does not
    cover, so today it has **no** parse check at all.
23. **Mutation check:** deleting each arm's distinguishing literal must red the suite. An
    assertion-count floor proves the assertions *ran*, not that they *bite*
    (`cq-assert-anchor-not-bare-token`).
24. ADR-166 cites its lineage (ADR-147 cl.4, ADR-154 §2, ADR-164 §2, ADR-126 §3, ADR-082/115) and
    claims only the **generalization** to failure text on any job — plus an `AP-021` row in
    `knowledge-base/engineering/architecture/principles-register.md`, which today has no
    diagnostic-honesty principle across AP-001…AP-020.
25. The Sentry check-in requires `exit_code == '1' && verdict == 'FIRE'`, so an abort with no
    verdict cannot check in green.

### Post-merge (automated)

26. Two `action-required` issues filed **before merge** (crash-loop; read-path-only health verdict).
27. The re-run of the three blocked runs is wired to `scripts/followthroughs/zot-restart-plateau-6288.sh`
    via `scheduled-followthrough-sweeper.yml` — not to `/work` — with an explicit never-plateaus
    escalation branch.

**Deliberately NOT acceptance criteria of this PR** *(three reviewers converged)*: "the three
drafts are re-run" and "production `build_sha` advances". Both require the crash-loop to stop,
which this plan explicitly does not fix. Gating merge on the remission of an undiagnosed production
fault either blocks the PR forever or gets silently waived — and a silently waived AC is how the
next reader concludes the mirror recovered. They belong to the crash-loop issue as follow-throughs.

---

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| 1 | `dead=0, unver=0`, rc=0 | `live` |
| 2 | `dead>0`, rc=1 | `stale` |
| 3 | `dead=0, unver>0`, rc=1 | `unverifiable` — **not** `stale` |
| 4 | rc=2 | `unmeasured` |
| 5 | verdict file unreadable/absent | `unmeasured` |
| 6 | `token_preflight` skipped entirely | both consumers see `unmeasured`; never `live` |
| 7 | helper called with `live` | origin-side text, restart series, no rotation headline |
| 8 | helper called with `stale` | corrected remedy present |
| 9 | helper called with `unverifiable` | script `cause` + "Do NOT rotate" |
| 10 | helper called with `unmeasured` | unranked + base case |
| 11 | Better Stack query fails on the failure path | explicit "could not query"; no zot claim |
| 12 | alarm checker exits 1 (FIRE) | the FIRE issue step is **not** skipped |
| 13 | `reboot_count=1`, `uptime_s`=18d, `boot_id` unchanged | no "converged by REBOOTING" claim |
| 14 | `<2` in-window NIC samples | no reboot claim (fail toward no claim) |

---

## Domain Review

**Domains relevant:** none

Infrastructure/CI-observability change. No path in `## Files to Edit` / `## Files to Create`
matches the UI-surface term list or glob superset, so the mechanical override does not fire and the
Product/UX Gate is skipped. No regulated-data surface and none of the four expanded GDPR triggers
fire — §2.7 skipped. §2.8 skipped: no new server, service, secret, vendor, or persistent runtime
process; every edit targets an already-provisioned surface.

---

## Open Code-Review Overlap

**None.** All 64 open `code-review` issues were queried and each path in `## Files to Edit` matched
against every issue body with a standalone `jq --arg … | contains($path)`. Zero matches
(2026-08-03). All cited repo paths were existence-verified; the only non-existent paths are the
four this plan creates.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A future message site names an unmeasured cause and nobody notices — iteration four. | Deliverable E's lint, scanning workflows **and** actions, with a highwater ratchet. Prose alone demonstrably did not hold for two iterations. |
| The two message sites drift apart. | A3d makes them one sourced function — identical by construction rather than by assertion. |
| `verdict` collapses "could not check" into "stale" (the plan's own thesis defect). | AC2 asserts `unverifiable` explicitly; the verdict is derived from JSON fields, not `rc`. |
| The in-job Better Stack read (A2b) adds a failure mode to releases. | Runs only on the already-failing path, fail-soft: a query error prints "could not query", never a claim. |
| B2's `always() &&` causes issue steps to run on unrelated earlier failures. | Their output conditions still gate them; `always()` only removes the implicit `success()`. An unset output matches no arm. |
| ADR-166 ordinal collides with a sibling PR. | Provisional; re-derived before merge with a full artifact sweep if it moves. |
| ~~Deleting `model.c4`'s heuristic loses information.~~ **Row retired:** it was written for a delete that did not happen. The record was AMENDED — its dichotomy was incomplete, not false, and it is a deliberate #7071 cause-class note. |

---

## Sharp Edges

- **The plan's own first draft violated its thesis twice**, and both are worth remembering:
  it proposed an Access probe the job already ran (`access_hostname_for()`), and it mapped
  `rc=1 → stale`, collapsing UNVERIFIABLE into a measured accusation. *Check whether the job
  already measures the thing before adding a probe, and never let a verdict collapse
  "could not check" into "bad".*
- Grading a Cloudflare Access probe on the **status code** is a deleted anti-pattern (#7127). The
  discriminator is the **Access stamp**. `check-cloudflare-token-drift.sh:661-680` is the tombstone.
- `cloudflared --loglevel debug` prints the Access service-token **secret in cleartext** (observed
  during planning). CI uses `warn`; never raise it, and never paste a debug-level log into an issue.
- `reboot_count` in `SOLEUR_PRIVATE_NIC` is **cumulative and persisted** — measured `reboot_count=1`
  alongside 18.2 days of uptime. Any verdict reading it as "rebooted recently" is wrong.
- A GitHub Actions step whose `if:` lacks `always()`/`failure()`/`success()` inherits an implicit
  `success()` and **skips when any earlier step failed** — regardless of its own condition. That,
  not the check-in, is why the alarm never filed.
- `SAFE_TO_RERUN` is appended to **every** `degraded()` call, so asserting its literals "per arm"
  is vacuous. Per-arm assertions must target arm-specific text.
- The in-job preflight prints `live entries: 1`, not `3` — it runs `--only` and `DOPPLER_TOKEN_PRD`
  reads exactly one config. Do not write an AC greping for `3`.
- `|| rc=$?` is load-bearing under `bash -eo pipefail`; a bare invocation aborts the step before the
  branch runs. This has already bitten `token_preflight` once.
- Absence-greps false-fail on files that legitimately document their own prohibition. Assert the
  **presence** of the corrected text instead.
- An **unwritable `--json-file` converts a genuinely DEAD token (exit 1) into exit 2 → `unmeasured`**
  (`publish_verdict || exit 2`, `check-cloudflare-token-drift.sh:1117`). Safe direction today, but
  pin it in the new suite — a future refactor could invert it.
- `cf-tunnel-registry-bridge` has **three** callers, and a prior plan already missed exactly that
  (`specs/feat-one-shot-zot-mirror-fail-closed/decision-challenges.md:32`). Any change to its
  inputs or message contract needs a cross-consumer sweep, not a single-caller read.
- A C4 relationship description that *records a refuted cause class on purpose* must be **amended,
  not deleted** — deleting it re-opens the failure mode the record exists to close.
