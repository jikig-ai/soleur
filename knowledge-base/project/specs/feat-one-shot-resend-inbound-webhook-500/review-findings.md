# Review findings — DO NOT MERGE AS-IS

> **Status 2026-08-02 — three findings applied, the merge block STANDS.**
>
> Applied, each RED-proven before GREEN and mutation-verified on sandbox copies:
> **finding 8** (`head -1` → `tail -1` + duplicate-key fixtures), **finding 1** (the
> third write site at `cloud-init.yml`, + a value-based parity guard covering it, +
> the two falsified ADR-155 claims), and **P1-a** (`init_probe_targets()` inside the
> `BASH_SOURCE` guard + an end-to-end case that sources the real file — which also
> discharges the P2 source-time-invariant finding).
>
> `inngest-inventory.test.sh` 120 → 139 assertions. Registered infra suites 87/87;
> `scripts/test-all.sh` 242/242.
>
> **Still open and still blocking:** findings **2, 3, 4, 5, 6, 7** (all P1), the P2
> and P3 lists, and **P2-b / M7** — deleting a test function call still exits 0,
> because this suite has no assertion-count floor. M7 is the one that can silently
> undo the P1-a work above.

7 of 9 agents reported (test-design-reviewer, code-quality-analyst still running when this
was written). Independent convergence on the top finding from 3 agents. Every measurement
below was run by the reporting agent, not inferred.

**Live state at review time: the outage is STILL RUNNING.** A fresh Better Stack pull
during review returned `connect ECONNREFUSED 10.0.1.40:8288` from
`CONTAINER_NAME=soleur-web-platform`, 30 rows in a 2-minute window
(2026-08-02 12:25:56 → 12:27:57), including a NON-email dispatch
(`"actionClass": "engineering.pr_review_pending"`). The failure is fleet-wide, not the
inbound-email route only.

---

## P1 — blocks merge

### 1. A third `INNGEST_BASE_URL` write site was never swept — **APPLIED**
`apps/web-platform/infra/cloud-init.yml:819` still carries
`-e INNGEST_BASE_URL=http://10.0.1.40:8288`. `git log -L 819,819` proves the original
cutover commit `b02870e1d` (#6348, ADR-100 step 2.4) changed **two** write sites in
lockstep — `ci-deploy.sh` AND `cloud-init.yml`. This PR reverted only `ci-deploy.sh`.
The line sits **outside** the `%{ if web_colocate_inngest ~}` gate (708–773), so it fires
on every fresh boot regardless of the toggle.

Converged: architecture-strategist (P1), pattern-recognition-specialist (P1),
security-sentinel (P1).

**Every parity guard in this PR is scoped to `ci-deploy.sh` and structurally cannot see
it** — `cron-inngest-cron-watchdog.test.ts:291`, `inngest-inventory.test.sh:1012`. The
only guard touching cloud-init's value (`cloud-init-inngest-bootstrap.test.sh:447`) is
presence-only and value-blind: it passes with `10.0.1.40` just as happily.

This also falsifies two claims in ADR-155 that I wrote: ":141-142 every other 10.0.1.40
reference legitimately describes it" (false) and ":139-140 both write sites moved
together" (three sites, two moved).

**Root of my error:** the CTO ruling explicitly listed `cloud-init.yml` in the
"must NOT be touched" set and I did not re-derive it. `hr-verify-repo-capability-claim-before-assert`
applies to a CTO ruling exactly as it applies to an issue body.

### 2. The paused operating point is not reproducible from IaC
`variables.tf:582-586` sets `web_colocate_inngest` **default false**. A web host recreated
from `terraform apply` therefore (a) never bootstraps a co-located inngest, and (b) with
finding 1 unfixed, boots dispatching at `10.0.1.40`. Both halves broken.
`web-probe-read-token.tf:5-6` states it outright: *"web-1 has no
`/etc/default/inngest-server` — `web_colocate_inngest` defaults false"*.

Today's web-1 survives only because it **predates** the 2026-07-11 default flip
(`5fbf00f0e`, #6344). ADR-155 justifies the rollback as using "the component that is
demonstrably serving" — true of the running instance, false of anything Terraform builds.
Violates `hr-fresh-host-provisioning-reachable-from-terraform-apply`.

### 3. The repoint may convert ECONNREFUSED into 401, not into success
Cutover step 2.4 reconciled `soleur/prd`'s `INNGEST_EVENT_KEY`/`INNGEST_SIGNING_KEY` to
the DEDICATED host's values (`inngest-server.md` §2.4 "Channel-key reconcile"). That
reconcile provably happened — the predecessor host served 2026-07-24 → 07-30, which the
cutover's G3.5 `PARITY_FAIL` hard gate would otherwise have blocked.

The co-located `inngest-server.service` loads its keys **once at process start** via
`doppler run --config prd` (inngest-bootstrap.sh ExecStart). Nothing has restarted it
since 2026-07-23, and a web-platform deploy does NOT restart it —
`systemctl restart inngest-server.service` in `ci-deploy.sh` runs only under
`COMPONENT=inngest`. So the app is about to dispatch a post-reconcile key at a server
holding the pre-reconcile key.

The reverse repoint has **no counterpart to G3.5** — that gate exists only in the cutover
workflow's `op=arm` arm.

**Fix:** dispatch `restart inngest` / `deploy inngest` so the co-located unit reloads
`soleur/prd` (reconciling by construction), or add a reverse sha256 parity assertion —
and make it a hard pre-deploy gate, not a spec bullet. This is the CTO's P1 pre-flight,
which was deferred.

### 4. No post-deploy proof that a send SUCCEEDS
`ci-deploy.sh`'s `verify_inngest_health` curls `http://127.0.0.1:8288/health` — an
**unauthenticated** liveness probe. It returns 200 under finding 3 and the deploy is
declared green while Resend's auto-disable clock keeps running. The only verification is
`tasks.md` 1.3, which is unchecked, manual, and post-merge. AC11 gates Phase 2's cutover,
not this merge.

### 5. Diagnosability REGRESSION on the failure path this PR most plausibly creates
`isTransientFetchError` (`send-with-retry.ts:19`) matches only TypeError "fetch failed",
TimeoutError, and errno codes. An Inngest **401 carries none of them** → no retry, no warn
rows. Net: the plan's own §B1 `econnrefused` column drops to **0** — which a responder
reads as FIXED — while `send_failed` continues.

Worse, the structural failure reaches no queryable signal at all today:
`send-with-retry.ts:44` gates its only `logger.warn` on
`attempt < MAX_RETRIES && isTransientFetchError(err)`, so the final attempt emits nothing
and just rethrows at `:52`. And the route's tagged capture is swallowed —
`route.ts:303`'s `logger.error` mirrors first, setting `__sentry_captured__`, so
`:307`'s `captureException(err, {tags:{op:"inngest-send"}})` early-returns via
`checkOrSetAlreadyCaught`. That is the mechanism behind the measured **0 issues for
`op:inngest-send`**; `github/route.ts:319-326` has the identical dead tag.

**Fix belongs in `sendInngestWithRetry`'s rethrow (covers all 5 call sites), not in
route.ts (covers 1):** capture a wrapper `new Error(msg, { cause: err })` with
`tags:{feature, op:"inngest-send"}`. `linkedErrorsIntegration` walks `cause` so the
undici chain survives. Do NOT switch to `String(err)` — pino's cause-flattening is the
only reason `connect ECONNREFUSED 10.0.1.40:8288` appears in the shipped line.

### 6. The new fail-open derivation is silent, and the path is LIVE
`inngest-inventory.sh:162` falls back to `http://127.0.0.1:8288` — **byte-identical to a
successful derivation** for the co-located case. There is no third state, and the probe
target appears in neither emitted JSON (`:554`, `:618-621`) nor journald summary
(`:551`, `:609`). A green verdict has an unknown subject — the #7144 defect restated.

It fires on ordinary deploys: `ci-deploy.sh:2873` `docker rm` → `:2895` `docker run`
leaves a window where `docker inspect` returns nothing, and the watchdog runs `*/15`.
`2>/dev/null` at `:146` destroys the reason, so "no such container" vs "permission denied
on docker.sock" is indistinguishable without SSH — a new SSH-only error path
(`hr-no-ssh-fallback-in-runbooks`).

**Fix:** emit `probe_base` + `probe_target_source` (`env|derived|fallback`) on the JSON and
journald summaries; WARN on the fallback branch; add a `::warning::` branch in
`scheduled-inngest-health.yml` (that workflow already has this shape at :151-155).
Layer 3 (Vector journald — `inngest-inventory` already allowlisted at `vector.toml:158`)
+ Layer 6 (webhook response body).

### 7. CTO limb (c) — the ECONNREFUSED alarm — is absent AND untracked
No `.tf`/`.yml` in the diff. `apps/web-platform/infra/sentry/issue-alerts.tf` already
carries ~30 per-symptom rules for strictly less severe classes (incl.
`outbound_email_send_failure`, and one filtering `op=inngest-send-push`). This is one
resource in an established pattern. Not deferred-with-a-ledger either: `tasks.md:36`
(task 0.1, file the `type/incident` issue) is still unchecked. **Depends on finding 5** —
a `tagged_event` filter on `op:inngest-send` matches nothing today.

---

### 8. `head -1` reads the WRONG duplicate — the derivation picks the value the app does NOT use — **APPLIED**
`apps/web-platform/infra/inngest-inventory.sh:148`. `Config.Env` legitimately contains
`INNGEST_BASE_URL` **twice**: once from `--env-file` (Doppler) and once from the `-e`
override. Verified empirically on Docker 29.4.3:

```
Config.Env:  INNGEST_BASE_URL=http://FROM_ENV_FILE:8288   <- --env-file, listed FIRST
             INNGEST_BASE_URL=http://FROM_DASH_E:8288     <- -e,          listed SECOND
head -1   -> http://FROM_ENV_FILE:8288    (what derive_dispatch_base picks)
printenv  -> http://FROM_DASH_E:8288      (what the app process actually sees)
```

The duplicate-key condition holds in prod **today** — phase-0 §Split-brain records that
ci-deploy.sh's `-e` overrides "the Doppler value that still reads
`host.docker.internal:8288`". It is masked only because both values currently agree. The
moment the repoint returns via `-e …10.0.1.40` with Doppler still on
`host.docker.internal`, the function returns the stale Doppler value → maps to loopback →
the watchdog certifies the surviving co-located server. **That is #7144 reconstructed, by
the code written to prevent it.**

Fix: `tail -1`. All three test fixtures (`inngest-inventory.test.sh:967,974,979`) are
single-entry, so the regression guard is structurally blind to the production env shape —
a duplicate-key fixture is required, and it is the FIXTURE-SHAPE coverage axis the
review skill documents.

## P2

- **The docker stub's argv fidelity is insufficient — PROVEN BY MUTATION.** security-sentinel
  mutated the SUT to query `soleur-web-platform-canary` AND `--format "{{json .Config.Labels}}"`,
  ran the suite: **120 passed, 0 failed**, identical to baseline. My stub's
  `[[ "$*" == *"soleur-web-platform"* ]]` substring match also matches the canary name, and
  it ignores `--format` entirely. Fix: exact positional `[[ "$2" == "soleur-web-platform" ]]`
  + assert the format string contains `.Config.Env`. **This is a vacuity in a test I added
  in this PR.**
- **Portless alias derives a malformed URL (measured).** `${host_part##*:}` on a colon-free
  string returns the whole string: `http://host.docker.internal` →
  `http://127.0.0.1:host.docker.internal`. Probe fails → `inngest_down` → auto-restart of a
  HEALTHY server. The parity assert only checks `http://*:8288`, so it cannot catch this.
- **The repoint is a security REGRESSION, not neutral.** The dedicated host scopes
  `:8288/:8289` via host-local nftables to `${web_host_private_ips}` then drops
  (`cloud-init-inngest.yml:75-76`, re-asserted every boot). The web host has **no
  INPUT-chain nftables at all** — `cron-egress-nftables.sh` manages only DOCKER-USER egress
  and concedes so at :19-21; `firewall.tf` allows 22/80/443/ICMP and does not filter the
  private interface. The co-located server binds `0.0.0.0:8288`
  (`inngest-bootstrap.sh:799`). Net: the unauthenticated control API moves from an
  allowlist-guarded host to one reachable from every peer on `10.0.1.0/24` (git-data .20,
  registry .30, .40, grok-dogfood) — exactly the sources SEC-H2 drops. Pre-existing posture,
  but this PR makes it load-bearing and ADR-155 does not mention it. Recommend a web-host
  `inngest-nftables` unit mirroring `cloud-init-inngest.yml:70-90`.
- **`ci-deploy.sh` retains the identical blind spot in 4 places** (`:2099`, `:2164`, `:2211`,
  `:2935` all hardcode `127.0.0.1:8288`). They agree with the app only by the coincidence
  that `host.docker.internal` maps to loopback — the same coincidence that evaporated at the
  repoint. Sharpened by this PR's own edit to `inngest.test.sh:581-584`, which still pins
  ci-deploy to the loopback literal under a "probe is not a lone snowflake" rationale while
  `inngest-inventory.sh` has left that pairing.
- **Double-fire window is scheduled by ADR-155's own criteria.** ADR-100: "two inngest
  servers on the *same* prd Inngest Postgres both fire every cron's schedule regardless of
  local `--sdk-url`". Criteria 1–3 require booting + health-probing the dedicated host
  BEFORE criterion 4 repoints — i.e. both schedulers live on the shared backend. Add a fifth
  criterion: the dedicated host's `INNGEST_POSTGRES_URI` returns to the AC-DARK non-prod
  backend before boot.
- **TS parity guard is first-match-only.** `cron-inngest-cron-watchdog.test.ts:291` uses a
  non-global `.match()`; a canary/prod divergence inside `ci-deploy.sh` passes it. The new
  bash case 6 covers this; the TS guard whose comment claims the invariant does not.
- **Both new parity cases vacate silently** — wrapped in `if [[ -r "$ci_deploy" ]]` with no
  `else`. A rename/relocation makes both disappear with a green suite.
- **web-2 false-RED (P3-ish but real).** `derive_dispatch_base` maps `host.docker.internal`
  → loopback unconditionally; web-2 runs the app container with the same env but has never
  run inngest-server, so a probe landing there derives loopback, finds nothing, and
  auto-dispatches a restart.
- **Task 3.5 (operator-reaching channel) deferral is untracked.** Task 0.4 is `[x]` and the
  recorded answer is that the monitor WAS red, so 3.5 is no longer conditional — it is due.
  It is a label change plus an issue emitter on an existing cron, unlike Phase 2.
- **My runbook note contradicts the command beneath it.** `inbound-email-ingress-dead.md:132`
  says "use SENTRY_AUTH_TOKEN for anything that lists or searches"; the block at :140-143
  then uses `SENTRY_API_TOKEN` against a **listing** endpoint (`/monitors/.../checkins/`)
  with no exemption note.

## P3

- `server/inngest/client.ts:11-13` — stale comment still says the base URL is "the dedicated
  soleur-inngest host … post-cutover". This PR fixed the equivalent comments in
  `cron-inngest-cron-watchdog.ts` and `send-with-retry.ts` and missed the file that actually
  constructs the client.
- **Argument injection into curl is reachable (measured).** No `--` before the URL at
  `:330`, `:441`, `:524`; `INNGEST_BASE_URL=-oJUNK` → `GQL_URL=-oJUNK/v0/gql`, parsed as an
  option. `--config`/`-K` is the interesting variant. Not command injection (confirmed
  `$(...)` stays literal). Add `--` plus a `^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?$` shape
  guard, which also fixes the portless bug.
- **Newline spoofing in the env parse (measured).** `{{println .}}` + `sed | head -1`: an
  earlier variable whose value embeds `\nINNGEST_BASE_URL=http://attacker.tld` wins over the
  genuine entry. `--env-file` rejects multi-line values, so the vector is image-level `ENV`
  or an API-set `-e`.
- ADR-155:93-96 "silently recreate this outage" — with the derived probe from this same PR
  that case now goes RED, so it would not be silent. Reword or name the residual precisely.
- ADR-155 should cite **AP-016** (`principles-register.md:26`), which already records the
  ADR-088 refutation verbatim; ADR-155 presents it as new. AP-016's LAPSED clause (#7071,
  PAT revoked 2026-07-30) is the same-day upstream of this incident.
- Completion criterion 2 is circular: it requires the health probe to watch the DEDICATED
  host before the repoint, but this PR makes the probe target derive FROM the app's
  `INNGEST_BASE_URL`. Name `INNGEST_PROBE_BASE` (the explicit override) as the pre-repoint
  mechanism, or the criteria are unsatisfiable in their stated order.

---

## Verified clean

- **git-history-analyzer: zero contradictions.** All six historical claims substantiated —
  `b02870e1d` is the cutover commit (and touched BOTH write sites, which is how finding 1
  was found); the 203/EXEC fix landed `4a2087f31` 20 days before host creation;
  `INNGEST_HOST_FALLBACK` was set in the same commit; the `web_colocate_inngest` default
  flipped `5fbf00f0e` 2026-07-11, predating web-2; no prior rollback attempt exists.
- **No credential values in the diff.** Only shape-descriptors (`ghp_` PAT, dead) and HTTP
  status codes. The runbook reads the token via `doppler secrets get --plain` and never
  echoes it.
- architecture-strategist verified ADR-155's entire factual table line by line (ADR-088
  refutation, `ignore_changes`, all four Alternative-C zot-mirror claims) — all substantiated.
- ADR numbering 155 is correct and unclaimed; `paused` is the right disposition vs supersede.
- The probe-target derivation itself is a genuine improvement and is well-tested for the
  cases it covers.

## P2 (continued — from code-quality-analyst)

- **Three code comments reassert the claim this branch's own last commit corrected.**
  `cffcdceab` rewrote ADR-155 + phase-0 after measuring that a PREDECESSOR host served
  until 29s before the replacement. But `cron-inngest-cron-watchdog.ts:75-78` still says
  the cutover repointed "before that host was proven to boot" and "it never bound :8288
  (its FIRST boot failed…)" — all three clauses false; `inngest-inventory.sh:128` implies a
  9-day outage by juxtaposing "on 2026-07-24" with "~3 days"; and
  `cron-inngest-cron-watchdog.test.ts:271-273` repeats it. The ADR-100 banner gets it right
  ("was REPLACED on 2026-07-30 … its predecessor had been serving"). **As shipped the branch
  contradicts itself, and the comment version is what an engineer reads first.**
- **"The vendor detected the outage before we did" is FALSE and I wrote it.**
  `inngest-inventory.sh:131` (and the commit message). Phase-0 §0.4 measured
  `cron-email-ingress-probe` first firing **2026-07-31T06:15:24Z**; Resend reported
  **18:23 UTC** — our own detection fired ~12h EARLIER, on the first run after onset.
  Phase-0 states the conclusion explicitly: a **response** failure, not a detection gap.
  The inversion matters because it points remediation at more signal instead of at an
  operator-reaching channel (task 3.5).
- **The top-level invocation violates this file's own documented source-time invariant.**
  `inngest-inventory.sh:162` vs the rule stated at `:624-629`: *"sourcing must NOT hit the
  network. HOST_ID resolves HERE, inside the guard, for exactly that reason: a top-level
  assignment would fire resolve_host_id's `curl --max-time 3` on every source."* Line 162
  is exactly that. Verified: `source inngest-inventory.sh` invokes docker. Worse than the
  pattern it violates — `resolve_host_id` bounds itself at 3s; `docker inspect` has no
  timeout (see the P2 timeout finding) and fires even when both consumers are overridden.


---

## test-design-reviewer (9th agent) — Test Quality Score 7.25/10, Grade C

Every mutation below was run on a SANDBOX COPY (`cp -r` + a detached worktree); the live
worktree was verified clean before and after. These are measured, not predicted.

**The suite's dominant idiom is assert-on-source-TEXT** (`sed`-extract-and-`eval`,
`grep -qF` an exact source string, `grep -oE` a value out of a sibling script). Text pins
verify a string EXISTS, never that it is REACHABLE FROM THE ENTRY POINT. Five green
mutations all left the pinned text intact while severing or reverting the behavior.

### The structural cause
The extractor at `inngest-inventory.test.sh:934` is
`sed -n '/^INNGEST_APP_CONTAINER=/,/^}$/p'` — it **stops at the function's closing brace
on line 158**. But the diff's behavior lands in three TOP-LEVEL assignments at `:162`
(`INNGEST_PROBE_BASE`), `:164` (`GQL_URL`), `:168` (`INNGEST_HEALTH_URL`). Those lines are
never sourced, never executed, and asserted by nothing except one indirect grep on `:168`.

### Measured mutations that stayed GREEN

| # | Mutation | Result |
| --- | --- | --- |
| **M1** | `:162` → hardcoded loopback (function kept, **caller disconnected**) | **120/0 + 181/181 GREEN** |
| **M2** | `:164` `GQL_URL` → hardcoded loopback | **120/0 + 181/181 GREEN** |
| **M6** | revert **BOTH** `ci-deploy.sh` sites to the outage value `10.0.1.40` | **120/0 + 181/181 GREEN** |
| **M5** | add third/fourth sites as `https://…` and `"$LEGACY_INNGEST"` | **120/0 GREEN** |
| **M11** | `:155` → port hardcoded 8288 (passthrough deleted) | **120/0 + 181/181 GREEN** |
| **M7** | delete the bare CALL at `:1019` (function body kept) | **114 passed, 0 failed, EXIT=0** |
| **T4** | diverge ONLY `ci-deploy.sh:2907` (prod), leave canary correct | **28/28 GREEN** |
| **M8** | rename `ci-deploy.sh` away | cases 5+6 emit **ZERO** assertions, fail open |
| M10 (control) | `:168` → hardcoded | **RED** ✓ |
| M3 (control) | over-aggressive host mapping | **RED** ✓ (118/2) |
| M4 (control) | literal third `-e …10.0.1.40` site | **RED** ✓ (119/1) |
| T1/T2/T3 (controls) | each parity side alone, and lockstep | **RED** ✓ |

**M2 is the sharpest:** `GQL_URL` is the PRIMARY probe (the functions query that decides
the verdict); `/health` is only corroborating. The suite pins the secondary and leaves the
primary unpinned.

**M6 is the most alarming:** reverting the entire change under review leaves the shell
suite green AND case 5 prints the reassuring line
`PASS: ci-deploy.sh target (http://10.0.1.40:8288) resolves to a probe target (…)` —
because `:999` asserts a port-shape glob `== http://*:8288`, not a value. The only thing
pinning the correct value is a hardcoded string in a TypeScript file in a DIFFERENT
workflow (`ci.yml` vs `infra-validation.yml`), a cross-language cross-workflow dependency
no comment records.

### My RED-first was run against the wrong mutant class
I verified RED by DELETING the function. The three lines that actually carry the behavior
never had a RED, and two of them survive reversion. Grade "First (TDD): 5/10" is correct.
This is the documented trap — *a battery only covers what you mutate* — and my
"mutation-proven" claim in commit `e95626825` is therefore overstated and must be
corrected when the tests are fixed.

### Required fixes
- **P1-a** — **APPLIED.** Add an end-to-end case that SOURCES the real file under the stub
  and asserts `GQL_URL` + `INNGEST_HEALTH_URL`. Kills M1, M2 and M11 at once. (Interacts
  with the P2 finding that the top-level invocation violates the file's own source-time
  invariant — fix both together: move the derivation inside the `BASH_SOURCE` guard AND
  assert it.)
  Done as `init_probe_targets()` + `test_probe_targets_end_to_end`. Measured RED for each
  target mutation: M1 129/10, M2 135/4, M11 136/3, derivation-back-to-top-level 138/1.
  The M11 kill required a NON-8288 fixture port — every prior fixture used 8288, where a
  hardcoded port and a correct passthrough are indistinguishable (the P3-a insight).
  Source-time purity carries a positive control, so a zero call-count cannot pass by
  virtue of a broken PATH. Probes run in a fresh `bash -c`, not a subshell: this suite
  marks `NOW_MS` readonly and the real file assigns `NOW_MS` at load, so a subshell
  inherits the readonly attribute and the file's own `set -e` aborts the source silently.
- **P1-c** Replace the `== http://*:8288` glob at `:999` with a VALUE assertion.
- **P2-a** Widen both greps to `INNGEST_BASE_URL=[^[:space:]\\]+` (drop the `http://`
  anchor) so `https://`/`${VAR}`/quoted forms enter the population, and assert the match
  COUNT is exactly the expected number, not just unique-count 1.
- **P2-b** Add an assertion-count floor (`[[ "$PASS" -ge N ]]`) — this file has a stable
  enumerable count of 120. Same for `inngest.test.sh`, which already computes `TOTAL` and
  discards it.
- **P2-c** `cron-inngest-cron-watchdog.test.ts:291` — use `matchAll` with `/g`, assert every
  capture is identical, then compare to `resolveInngestHost(undefined)`.
- **P3-a** Fixture `http://host.docker.internal:9288` (kills M11) and the portless case.
- **P3-b** Add `else … FAIL` to the `[[ -r "$ci_deploy" ]]` wrappers at `:992` and `:1010`.

### Kept as good
The incident-anchored comments, the `docker` stub's `exit 64` on unexpected argv (right
instinct, though security-sentinel proved the argv match itself is too loose), and
`inngest.test.sh:588-591` documenting a MEASURED prior mutation escape.
