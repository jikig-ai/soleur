---
title: "fix(infra): close #7103's R1–R5 — delivery is not activation, and absence is not evidence"
date: 2026-08-01
issue: 7103
pr: 7146
branch: feat-one-shot-7103-recovery-residuals
type: bug-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: deepened
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> **Phase 2.8 note.** Every `systemctl` verb in this plan is executed **by an IaC-delivered
> artifact**, never by an operator and never over SSH: the reconciliation is folded into
> `infra-config-apply.sh` (delivered by `terraform_data.infra_config_handler_bootstrap`), the sudo
> grant that permits it lives in `deploy-inngest-bootstrap.sudoers` + its `cloud-init.yml` mirror
> (both Terraform-delivered), and the chain is applied by `apply-deploy-pipeline-fix.yml` on merge.
> See `## Infrastructure (IaC)` — including the new `replace_target` dispatch input that replaces
> the one <!-- lint-infra-ignore start: negated mention — this clause records that the operator step is REPLACED by the replace_target dispatch input, it does not prescribe one -->operator-local `terraform apply` the existing recovery text still prescribes.<!-- lint-infra-ignore end -->

# Close #7103's R1–R5

## Enhancement Summary

**Deepened on:** 2026-08-01
**Panel:** architecture-strategist, code-simplicity-reviewer, spec-flow-analyzer, security-sentinel,
observability-coverage-reviewer, user-impact-reviewer, plus a mechanical verify-the-negative /
attribution / count sweep. Escalated to the full panel by the `single-user incident` threshold.

### What the deepen pass changed

The v1 plan would have shipped a privilege-escalation path, a public credential-leak amplifier, and
three independent ways to brick the host's only remediation channel. All are corrected below.

1. **Phase order re-ranked by recurrence risk** (coordinator directive): R1 is Phase 1. R2 → R3
   remain a hard dependent pair. R1's two halves are tracked separately, with half (a) explicitly
   re-filed rather than implied.
2. **SECURITY, P0 — the restart grant would have completed a `deploy` → root persistence chain.**
   `infra-config-install.sh`'s content gate is scoped to `/etc/default/*`; the three
   `*.service.d/*.conf` dests get **none**. `vector.service` runs `User=deploy`, and a drop-in may
   set `User=root` + `ExecStart=`. Today such a payload is inert because nothing root-restarts the
   unit. Phase 3 was about to supply exactly that. A drop-in **shape gate** now ships *before* the
   grant, and the C4 "no actor gains access" row — which was false — is corrected.
3. **SECURITY, P0 — this repo is PUBLIC and `$b64` is unmasked.** `gh repo view` confirms
   `"visibility":"PUBLIC"`. The digest step deliberately calls `nonsensitive()` on a base64 of the
   live prd `DOPPLER_TOKEN`; GitHub's masker redacts only the registered literal, never a
   re-encoding, and this workflow has **zero** `::add-mask::` calls while a sibling infra workflow
   has twenty. Committing a harness that re-executes that body raises the cost of any future
   `set -x` to *permanent public disclosure*.
4. **The writes stay UNCONDITIONAL.** v1 made them content-conditional; that silently drops the
   per-apply re-assertion of `640 root:deploy` on the credential, so a DAC drift would be skipped,
   reported `ok`, and never repaired. `changed` is now derived from a sha compare used *only* by the
   restart predicate, with the drop-in's mtime preserved on an identical write.
5. **Three ways to brick the channel, all closed**: fallible new reads under `set -euo pipefail`
   aborting the write loop mid-way (the #4804 freeze re-entered); a `restarts`-key hard failure that
   reds `adjudicate_infra_config` and thereby skips the `if: success()`-gated activation step; and a
   stale state frame passing the gate because the state file is never invalidated at run start.
6. **`try-restart`'s exit code is not evidence.** It returns 0 on a `Type=simple` fork, and is a
   **no-op returning 0** on a *failed* unit. Grading is now on `is-active` +
   `ExecMainStartTimestamp` advancement, with `noop_not_active` a distinct, gate-failing outcome.
7. **The positive control was itself credential-gated and host-blind.** `_canary()` runs *inside*
   `doppler run`, so a dead token silences the very control used to certify that token's errors
   absent; and `betterstack-query.sh` has no `--host` flag while `--grep` terms are OR-combined, so
   another host's canary could certify this host's vector. Both corrected.
8. **The soak directive would have auto-closed #7103.** The sweeper closes on PASS. It now goes on a
   dedicated soak issue, with literal secret names and a concrete `earliest`.
9. **Seven ACs cut as ceremony; the predicate collapsed from three clauses to one**; twelve ACs added
   that pin the corrections above.

---

## Overview

Production was restored to `v0.247.5` at 2026-08-01 18:45Z. #7095 is closed. Five residuals remain on
#7103, filed 2026-08-01T18:51Z (R1–R4) plus the workflow-gap item (R5) that
`wg-when-a-workflow-gap-causes-a-mistake-fix` requires. This is the tracker's tail, not incident
response.

One sentence names what all five share: **the system repeatedly reported a state it had not
established.** A credential landed on disk and was called active. A telemetry query returned zero and
was called clean. A digest of the empty string was called ACTIVE. A test suite that skipped a red
runner was called green. And an invocation whose environment differed from its sibling's reported two
symptoms of one cause as if they were two facts.

| Phase | Item | What ships |
|---|---|---|
| 1 | **R1** | A per-invocation self-report (`SOLEUR_DEPLOY_INVOCATION`) naming the hook, the script's own sha, and the credential source — the instrument that discriminates the two live hypotheses — plus a loud failure on the credential-absent path. **First: highest recurrence risk, no blockers.** |
| 2 | **R5(a)** | `scripts/test-all.sh` invokes the two runners it does not cover today, plus a registration tombstone and a named incident bypass. |
| 3 | **R2** | A drop-in **shape gate** (security precondition), then `infra-config-apply.sh` reconciles the running units whose drop-ins it delivers, grading on activation rather than exit code, and reports per-unit into the status JSON. |
| 4 | **R3** | A four-outcome absence helper that cannot return `clean` without a host-scoped positive control read **at the sink**, a credential-independent canary, and the AC12 re-verification enrolled on a dedicated soak issue. **Hard-gated on Phase 3.** |
| 5 | **R4** | The #7140 digest-oracle regression harness, committed, hermetic, with an `::add-mask::` and an `id: rendered_digest` on the step. |
| 6 | **R5(b)** | A committed mutation battery proving the `cf-tunnel-ssh-bridge` liveness gate is non-deletable. (The re-anchoring itself already shipped in #7133.) |
| 7 | — | ADR-158, the one C4 description correction, and the Session Error the 2026-08-01 learning is missing. |

### Sequencing invariants (load-bearing, not preferences)

- **R3 may never be verified before R2 lands *and applies*.** R3's measurement path runs physically
  through `vector.service`, the component R2 repairs. Any phase shape that verifies AC12 first is
  invalid, not merely suboptimal — it would re-record the exact "zero errors is indistinguishable
  from the channel not shipping" reading that made AC12 unverifiable. Hence AC-PM-4 is a post-apply
  follow-through probe, not a pre-merge AC.
- **R1 ships first because it is the item with real recurrence risk.** It was harmless on the observed
  run only by coincidence — prod already held the tag and the fall-through target was the
  documented-revoked GHCR path. The durable defect is that two invocation paths on one host had
  different environments, and it resurfaces the next time the coincidence does not hold.
- **Within Phase 3, the shape gate ships before the grant.** 3.1 is a security precondition for 3.2:
  granting a root restart of a unit whose configuration can be written without validation converts a
  delivery capability into an execution capability.
- **R5(a) is Phase 2, with one consequence.** R1's tests live in `ci-deploy.test.sh` — inside the
  runner Phase 2 folds in. Phase 1's green is therefore subject to the gap Phase 2 closes, so Phase 1
  is **re-verified at the exit gate** (AC-X-1 runs on the final tree). Recorded rather than used to
  override the risk ranking.

One PR, seven phases. Nothing is deferred except R1's half (a), explicitly re-filed on #7103 with its
reproduction detail intact (Phase 1.7), and the `vector.toml` token-redaction follow-up (Alternatives).

---

## Research Reconciliation — Spec vs. Codebase

Every claim below was verified against `origin/main` by a mechanical sweep; the one contradiction it
found is corrected in Phase 0.2.

| Claim (from the #7103 residuals / task framing) | Reality on `origin/main` | Plan response |
|---|---|---|
| R1: "give the second invoker `ZOT_REGISTRY_URL`" | **Not implementable as written.** `hooks.json.tmpl` has exactly two hooks executing `ci-deploy-wrapper.sh` — `deploy` and `deploy-peer` — and *neither* passes `ZOT_REGISTRY_URL` or `DOPPLER_TOKEN`. The only difference is `SOLEUR_DEPLOY_PEERS`, omitted from `deploy-peer` by design. `ZOT_REGISTRY_URL` is resolved *inside* `ci-deploy.sh` › `zot_gate_and_login()` from Doppler. There is no invoker-side site. | Half (b) — loud failure — plus the instrument that identifies the invoker. Half (a) stays **open and re-filed**. §Phase 1. |
| R1: the two log lines show "two invocation paths with different environments" | **The string is the tell, and it points elsewhere.** The short-form `ZOT_GATE: ZOT_REGISTRY_URL unset — GHCR path (dark, pre-provisioning)` does **not** exist at HEAD; `3faa95fa8` (#7097) replaced it with the long form. The 2026-08-01 plan uses that exact short form as its marker for "#7097's `ci-deploy.sh` never landed on the host". | Two disjoint hypotheses (H-R1-A script-version vs H-R1-B environment), both live, both discriminated by one instrument. §Hypotheses. |
| R2: "(a) a `restart-unit` hook, (b) fold `try-restart` into `infra-config-apply.sh`, (c) accept" | **The v1 deliverability premise was false and it hid two things.** (i) A fourth option exists — `infra-config-install.sh` already runs as root under the **bare-command** grant `INFRA_CONFIG_INSTALL`. (ii) More importantly, that installer validates content **only** for `/etc/default/*`; the three `*.service.d/*.conf` dests get none. So *any* option adding a root restart of those units completes a `deploy` → root chain. | Decided on the merits in §Phase 3, and the **shape gate is a precondition of all four options**. |
| R5(b): "make the liveness gate non-deletable" | **Already shipped.** #7133 re-anchored `check-cloudflare-token-drift.test.sh`'s W1–W10 on constructs a comment cannot produce, with an anti-vacuity floor of ≥50 (verified). | Do **not** re-anchor. Ship the missing half: a battery that *proves* deletion goes red. §Phase 6. |
| R5: "the local suite reported 240/240" | 240 was the 2026-08-01 measurement; HEAD is **242** (101 explicit `run_suite` calls + 141 from the single glob). One suite is deliberately double-counted. | ACs assert a **delta** measured at Phase 0, never an absolute literal. |
| R5: "a guard the diff had disarmed sat red in a runner that was never invoked" | Confirmed, but **not from the learning file** — it never names a runner; its Session Errors 1–14 omit this. The fact lives only in commit `bf4816455`'s body (verified verbatim). The runner is `run-registered-suites.sh`; the guard is `web-1-swap-concurrency-parity.test.sh`. | The learning gets one appended Session Error. §Phase 7. |
| R3: "add a positive control" | **The emitter exists but is unusable as-is, twice over.** `web-zot-consumer-probe.sh` › `_canary()` is the sole `SOLEUR_PROBE_CANARY` emitter repo-wide — but it runs *inside* `doppler run …`, so a dead prd token silences the control used to certify that token's errors absent; and `betterstack-query.sh` has **no `--host` flag** while repeated `--grep` terms are OR-combined, so a foreign host's canary would satisfy it. | Hoist the canary out of the credential wrapper; read the control with an explicit `host_name` SQL predicate. §Phase 4. |
| Phase 0.2's `--list \| wc -l` expects 87 | **CONTRADICTS.** The command returns **88** — the runner prints a `Derived 87 registered infra suite(s)…` header to stdout ahead of the list. The underlying count (87) is right; the instruction is wrong. | Phase 0.2 now pipes through `grep -c '\.test\.sh$'`. |
| AC12/AC13 and Phase 4b "live in the 2026-07-30 plan" | They live in the **2026-08-01** plan. The 2026-07-30 plan's AC12/AC13 were **deleted** during its own review (its Revision R20 records the cut). | All citations resolve to the 2026-08-01 file. |
| B5's ADR ordinal | Next free on a **freshly-fetched** `origin/main` is **ADR-158**. | Provisional; `/ship` re-verifies. |

---

## Open Code-Review Overlap

62 open `code-review` issues, each body searched against every Files-to-Edit path — **zero matches**
(independently re-verified by the sweep). **None.** No fold-in, acknowledgement, or deferral needed.

---

## Hypotheses

The feature description matches the network-outage trigger set (`SSH`), and Phase 3 drives a
`terraform apply` on resources carrying `remote-exec` provisioners — both triggers fire.
`emit_incident hr-ssh-diagnosis-verify-firewall applied` was emitted at plan time and at the deepen
pass.

### Network-Outage Deep-Dive (L3 → L7)

No connectivity symptom is under diagnosis. Every symptom in R1–R5 is a *reporting* defect on a
working transport. The layers are answered as preconditions of Phase 3, the one phase with a network
dependency.

| Layer | Status | Verification artifact |
|---|---|---|
| **L3 — firewall allow-list** | **Not applicable to the symptom; mechanized for the dependency.** Phase 3's delivery leg reaches the host through the Cloudflare Tunnel, not `hcloud_firewall` — verified: `firewall.tf` has no rule opening :9000 publicly and gates :22 to `var.admin_ips`. No operator-egress-IP dependency on this path, so admin-IP drift (#2681) cannot be the failure mode. | `firewall-9000-deny.test.sh`, already in the registered infra suite set. |
| **L3 — DNS / routing** | **Not verified by hand, deliberately.** Per `hr-no-dashboard-eyeball-pull-data-yourself`, the route is asserted at run time by `cf-tunnel-ssh-bridge`, whose **final** step is ADR-154 proposition 3's transport probe. Position is the contract. | `.github/actions/cf-tunnel-ssh-bridge/action.yml` › the `MUST REMAIN THE FINAL STEP` banner. Phase 0.5 asserts it is still final. |
| **L7 — TLS / proxy** | **Covered by the same gate.** ADR-154 records why bare reachability is insufficient: a local `cloudflared` listener opens on a dead credential, so `nc -z 127.0.0.1 2222` succeeds. Post-#7134 the gate grades on Cloudflare Access's own denial stamp, not the status code. | Same file. |
| **L7 — application** | **Verified, and it is R1's subject.** The journal *does* carry entries for the window. The defect is that they do not say which invocation produced them. | §H-R1. |

**Gap to close before implementation:** none at L3/L7.

### H-R1 — why did a second `ci-deploy` invocation run without a Doppler credential?

Established from source (every fact independently re-verified by the sweep):

- **F1.** Exactly two hooks execute `ci-deploy-wrapper.sh`. Neither passes `ZOT_REGISTRY_URL` or
  `DOPPLER_TOKEN`.
- **F2.** `ci-deploy-wrapper.sh` is a single `exec timeout …` line, asserted inert by its own suite.
- **F3.** `zot_gate_and_login()` runs **after** `flock -n 200`. The second invocation *won* the lock.
- **F4.** The "dark, pre-provisioning" branch and `recovery_stage=refetch_unavailable` have the
  **identical** precondition: `! command -v doppler || [[ -z "${DOPPLER_TOKEN:-}" ]]`. The residual
  reports them as two observations; they are **one cause, reported twice**.
- **F5.** The credential is sourced under an `if [ -r … ]` with **no else branch** — absence selects
  the no-credential path in total silence, the exact rule the same file states later:
  *"ABSENCE OF A VALUE MUST NEVER SILENTLY SELECT A CODE PATH."*
- **F6.** Closed set of `POST /hooks/deploy` producers: `web-platform-release.yml`,
  `apply-deploy-pipeline-fix.yml` (*Redeploy to load applied profile*), `deploy-inngest-image.yml`,
  `restart-inngest-server.yml`, `scripts/cutover-inngest.sh`. Only two send
  `deploy web-platform <tag>`; the second derives `TARGET_TAG` from the **running container's**
  version and fires only on a seccomp hash mismatch — the state of a host stuck on a pre-2026-07-30
  container. `deploy-peer` is dormant at single-host.
- **F7.** `zot_gate_and_login`'s dark branch is the **only** arm that does not call
  `zot_gate_degraded_event` — the branch with the least evidence has the least telemetry.

**Named second invocation path:** `.github/workflows/apply-deploy-pipeline-fix.yml` › the *Redeploy
to load applied profile* step.

**What remains genuinely UNKNOWN:**

| # | Hypothesis | Status | Discriminator |
|---|---|---|---|
| **H-R1-A** | The second invocation executed a **pre-#7097 `ci-deploy.sh`**. | **UNKNOWN — not refuted.** | `script_sha` in the new marker vs. the merge commit's `ci-deploy.sh`. |
| **H-R1-B** | Same script; `DOPPLER_TOKEN` was empty for that invocation, and the residual abbreviated the message. | **UNKNOWN — not refuted.** | `cred_file=` and `doppler_token=` in the new marker. |

Both are **UNKNOWN**, deliberately. The deciding datum is discarded at the source today. **No
hypothesis here may be graded CONFIRMED or REFUTED until the marker has shipped and been read.** It
would be easy to "refute" H-R1-A by noting both paths hit the same `execute-command`, and to "confirm"
H-R1-B by arithmetic on F4 — but both arguments run entirely inside the region the instrument is
missing from. That is the 2026-07-16 defect class, declined.

---

## User-Brand Impact

Enumerated **by role**, not only by surface — surface-based enumeration is what hid the findings the
deepen pass caught.

**Role: operator / founder.** The role the `single-user incident` threshold is about here, and the
only role that loses anything.

- **If this lands broken, the operator experiences:** the loss of the host's *only* no-SSH remediation
  channel. Concretely, `deploy.soleur.ai/hooks/infra-config-status` returns `exit_code != 0` while
  `app.soleur.ai/health` serves a stale `version` — the 26-hour #7095 shape, on a host ADR-154 records
  as **unreplaceable** (`cx33` `available=false` in 6 of 6 datacenters). The deepen pass found
  **three** distinct routes to that state in v1, all now closed: fallible new reads aborting the write
  loop under `set -euo pipefail` (the #4804 freeze re-entered mid-loop, deterministic and
  self-repeating); a hard `restarts`-key failure that reds `adjudicate_infra_config` and thereby skips
  the `if: success()`-gated *Redeploy to load applied profile* step, so files land and activation never
  happens; and a stale state frame passing the gate because the state file is never invalidated at run
  start.
- **Second loss, compounding the first:** Phase 3 restarts `vector.service`, the agent shipping every
  log the operator reads — and `vector.toml` **excludes `vector.service` from its own sources**, so a
  vector that starts and dies reports nothing anywhere. The realistic trigger is already documented in
  this repo: `server.tf` records that an out-of-band Doppler rotation leaves `prd_terraform` holding a
  stale token which the apply re-pushes. Today that push is inert; a credential-keyed restart makes it
  **activating**. Hence grading on `is-active`, not on `try-restart`'s exit code, and hence the gate
  failing on `active != active`.
- **If this leaks, the operator's credential material is exposed via** the digest oracle. This repo is
  **PUBLIC** (`gh repo view` → `"visibility":"PUBLIC"`), Actions logs are world-readable, and the step
  deliberately calls `nonsensitive()` on a base64 of the live prd `DOPPLER_TOKEN` — which GitHub's
  masker does **not** redact, because it only knows the registered literal. Committing a harness that
  re-executes that body raises the cost of any future `set -x` from "a bad run" to *permanent public
  disclosure*. Mitigated by an `::add-mask::` in the step itself (5.1), a hermetic `env -i` harness
  that cannot reach real `doppler` (5.3), and a `pull_request_target` refusal — the harness executes a
  `run:` body taken from the PR head, i.e. attacker-controlled code by construction.
- **Third exposure, from the fix rather than the bug:** the new sudo grant would have completed a
  `deploy` → root persistence chain, because `infra-config-install.sh` validates content only for
  `/etc/default/*` while `vector.service` runs `User=deploy` and a drop-in may set `User=root` +
  `ExecStart=`. Closed by the shape gate shipping first.

**Role: authenticated `app.soleur.ai` user.** Scoped out, with the reason rather than by omission:
`web-platform-release.yml` is an independent `on: push` workflow, so a red `apply-deploy-pipeline-fix`
job does **not** block container deploys. App users stay insulated in every failure mode above.

**Roles not touched:** no data-persistence, payment, or cross-tenant surface is in this diff. Stated
so the absence reads as a checked result rather than an omission.

- **Brand-survival threshold:** `single-user incident` — CPO sign-off required at plan time before
  `/work`; `user-impact-reviewer` runs again at review time (it did, on 2026-08-03, and returned
  9 findings against this section — see session-state §"Review Phase — session 4").

The canonical bullet form above is load-bearing, not cosmetic: `/ship` preflight Check 6 parses
`- **Brand-survival threshold:** <label>` as an anchored bullet so a free-text sentence mentioning
the words cannot satisfy it. This was a bare paragraph until 2026-08-03, so the gate reported the
bullet missing on a plan that had genuinely declared the threshold — the declaration was there and
the machine-readable form was not.

---

## Downtime & Cutover

The gate does **not** fire on the serving surface — no host replace, no `server_type`/placement change,
no container swap, no lock-taking DDL, no router restructure. `app.soleur.ai` serves throughout. One
availability window exists and is named rather than hidden: **the observability plane.**

| Surface | Offline op | Duration | Zero-downtime path taken |
|---|---|---|---|
| `vector.service` | one `try-restart` on the first apply after merge | sub-second re-exec | **Drain-then-act ordering**: reconciled **last**, after `inngest-heartbeat`, so the stream used to verify the outcome is the last interrupted. journald buffers during the gap and vector replays from `/var/lib/vector` on restart — events delayed, not lost. Followed by an `is-active` assertion, so a restart that does not come back is a gate failure rather than a silent blackout. |
| `webhook.service` | delayed self-restart (**pre-existing**, unchanged) | ~3 s | Already deferred via `systemd-run --on-active=3s` so the HTTP 202 completes first. |
| `app.soleur.ai` | none | — | n/a |

Residual accepted: a sub-second telemetry gap, once, on one apply. The alternative is option (c),
which the residual rates weakest and which leaves R3 with no live channel. Bounded by AC-R2-4 — a
second consecutive apply must report `skipped`.

---

## Implementation Phases

### Phase 0 — Preconditions (read-only; no writes)

Each is a command whose output goes in the work log. A failed precondition re-scopes the phase it
guards.

0.1 `bash scripts/test-all.sh` on a clean tree; record `N/N suites passed`. The **before** number for
    AC-R5-1 — asserted as a delta, never against a literal.
0.2 `bash apps/web-platform/infra/run-registered-suites.sh --list | grep -c '\.test\.sh$'`
    (expect 87). **Not** `| wc -l` — the runner prints a `Derived N registered infra suite(s)…`
    header to stdout, so `wc -l` returns 88 and a worker following it verbatim gets a spurious
    mismatch. Then run it in full and record `PASS`/`RED`. A pre-existing red is triaged under
    `wg-when-tests-fail-and-are-confirmed-pre` **before** Phase 2 folds it in.
0.3 `bash .github/scripts/test/run-all.sh`; record `RAN` (expect 10; `MIN_SUITES=10`, zero slack).
0.4 `python3 -c "import yaml; print(yaml.__version__)"` in the job that will run the R4 harness.
    **Decides Phase 5's home.** Two sibling suites already parse workflow YAML this way inside the
    required `test` check.
0.5 Confirm the liveness gate is still the final step of `cf-tunnel-ssh-bridge/action.yml`.
0.6 Count `FILE_MAP` entries in `infra-config-apply.sh` (expect 19). `infra-config-install.sh`'s
    header says "18 allowlisted destinations" **in two places** — both stale, corrected in 3.9.
0.7 Confirm `"source": "string"` is an accepted hook source (it is — `INVENTORY_LIVENESS_ONLY` on
    `inngest-liveness`).
0.8 Re-derive the required-check list from `gh api repos/jikig-ai/soleur/rulesets/14145388` rather
    than trusting this plan's copy.
0.9 Enumerate every consumer of `cat-infra-config-state.sh`'s output; Phase 3 adds a key to that
    payload.
0.10 **Read `infra-config-apply.sh`'s tail exactly**: the state-write block, the `${STATE_FILE}.final`
    sentinel that disarms the EXIT trap, and the post-write `sync`/`daemon-reload`/self-restart
    region. Phase 3 **moves** code across that boundary.
0.11 Read `deploy-inngest-bootstrap.sudoers` in full and record, for every `Cmnd_Alias`, its paired
    `deploy ALL=(root) NOPASSWD:` User_Spec line **and** the corresponding post-write `grep`
    assertion in `server.tf`'s bootstrap `remote-exec`. Phase 3 adds all three; v1 added only the
    alias, which grants nothing.
0.12 Read `infra-config-install.sh`'s content gate and confirm its scope
    (`if [[ "$dest_canonical" == /etc/default/* ]]`). Phase 3.1 widens it. **This is the security
    precondition of the whole phase** — do not proceed to 3.2 without it.
0.13 `gh repo view jikig-ai/soleur --json visibility` — confirm PUBLIC, so the 5.1 `::add-mask::` is
    understood as necessary rather than defensive decoration.

### Phase 1 — R1: make the invocation say who it is

**First by recurrence risk.** R1 has two halves and this phase ships one and a half:

| Half | Status in this PR |
|---|---|
| **(b) the dark path fails loudly rather than falling through to a registry known to be dead** | **Shipped** — 1.4. |
| **(a) the second invoker is identified by name and receives the same environment** | **Named, not remedied.** F6 names the path. The *environment divergence* is not remediable from source: both hooks pass identical environments (F1), so there is no invoker-side site where the difference could have been introduced, and none to fix. The mechanism that will name it is 1.2's marker. **(a) remains OPEN and is re-filed (1.7).** |

1.1 **Hook identity** — add to the `deploy` and `deploy-peer` hooks respectively
    `{ "source": "string", "name": "deploy", "envname": "SOLEUR_DEPLOY_HOOK_ID" }` and the
    `deploy-peer` equivalent. Proven-supported form (0.7).
1.2 **Self-report** — emitted **after** the credential-read block and **before** `flock`, so it
    reports the credential state at the point of use:

    ```
    SOLEUR_DEPLOY_INVOCATION: hook=<id|unset> script_sha=<first 12 of sha256 of BASH_SOURCE>
      cred_file=<present|absent|unreadable> doppler_token=<present|absent>
    ```

    **Four fields, not six.** `peers` is derivable from `hook=` and constant at single-host;
    `ppid_unit` is constant (`webhook.service` for both hooks). Neither discriminates the hypotheses.
    Closed vocabulary only — never a token, never a byte of the credential file. `cred_file` and
    `doppler_token` are genuinely independent: *readable but empty* is a real third state.
1.3 **Break the silent absence** — the credential `if [ -r … ]` gets an `else` that sets the
    `cred_file` value the marker reports. **No separate `SOLEUR_DEPLOY_CRED_SOURCE` line** — a second
    marker for one fact is what ADR-158 proposition 3 forbids. Distinguish absent (`[ -e ]` false)
    from unreadable (`[ -e ]` true, `[ -r ]` false) — a permissions or namespace fault is a different
    diagnosis. Fail-open control flow unchanged.
1.4 **Fail loudly on the dark branch** — add `zot_gate_degraded_event no_credential_source` to the one
    arm that lacks it (F7). It routes over the baked-DSN Sentry path, credential-independent by
    construction and therefore the one transport that survives this exact failure. **This is half (b).**
1.5 Keep the fail-open control flow. **Out of scope:** converting it to a terminal
    `doppler_read_failed` abort — that is #7103 **B1**, and a new abort path would break the #6090
    baked-cred cold-boot route. **No new deploy-state `reason` enum either**: the Sentry event already
    names the cause on a surviving transport; a third emission of one fact adds cross-file coupling
    for nothing.
1.6 Tests in `ci-deploy.test.sh` (registered): marker on every exercised path; each `cred_file=` value
    independently reachable; `doppler_token=absent` implies the degraded event; the marker never
    contains the fixture token. Plus a `hooks.json.tmpl` assertion that both hooks carry a **distinct**
    `SOLEUR_DEPLOY_HOOK_ID`. This suite is re-run at the exit gate (AC-X-1).
1.7 **Re-file half (a) on #7103**, reproduction detail verbatim: both timestamps, both `ZOT_GATE`
    lines, the `IMAGE_PULL_FAIL` line, F1–F7, and the statement that 1.2's marker is the mechanism
    that will name the divergence on next occurrence.
1.8 `vector.toml` needs **no** change — verified both directions: `ci-deploy` is in the Source-4
    allowlist **and** `ci-deploy.sh` sets `readonly LOG_TAG="ci-deploy"`. Assert rather than assume;
    `vector.toml` warns that an allowlist entry whose unit does not set the matching literal is "a
    permanently-dead no-op that reads like coverage."

### Phase 2 — R5(a): make the local suite invoke the runners it does not cover

2.1 Add two `run_suite` registrations to `scripts/test-all.sh` —
    `apps/web-platform/infra/run-registered-suites.sh` and `.github/scripts/test/run-all.sh`. Each
    counts as one suite at the aggregate level; the nested runner reports its own counts.
2.2 Gate the infra runner on relevance so a docs-only run does not pay for it, but **fail loudly**
    rather than skip silently: invoke it when the diff touches `apps/web-platform/infra/**` or
    `.github/workflows/infra-validation.yml`, or when `TEST_GROUP` asks. When skipped for
    irrelevance, print the skip **and the exact re-run command**.
2.3 **Named incident bypass.** The relevance gate fires on exactly the paths an infra hotfix must
    touch, so it lands minutes on the incident path. Add `SOLEUR_INCIDENT_SKIP=1`, which prints the
    skipped runner plus the re-run command (the same loud-skip contract as 2.2) — a documented lever
    rather than leaving `TEST_GROUP` as an undocumented escape hatch. Paste the 0.2 measured
    wall-clock into the PR body so the added cost is a recorded number, not discovered mid-incident.
2.4 Rewrite the `echo`-only mentions of `run-registered-suites.sh` that today stand in for running it.
    A comment reading "this runner does NOT cover `apps/web-platform/infra/`" must not survive the
    change that makes it false.
2.5 **Registration tombstone.** Extend `scripts/lint-orphan-test-suites.sh` with a `REQUIRED_RUNNERS`
    list asserting a `run_suite` **call-shape** line exists for each runner:
    `grep -qE "^[[:space:]]*run_suite .*[\"' ]apps/web-platform/infra/run-registered-suites\.sh([\"' ]|$)"`.
    Anchored on the call shape, never the bare path — the bare path already appears in `test-all.sh`
    comments and `echo` strings (verified at five sites), so a bare-token grep would false-pass.
    `cq-assert-anchor-not-bare-token`, one level up from where #7133 applied it.
2.6 Mutation-test 2.5 in a sandbox: delete each `run_suite` line, assert the linter reds and names the
    missing runner.

**Deliberately NOT done:** folding the 87 infra suites in individually. The aggregate registration
keeps `run-registered-suites.sh` as the single authority that *derives* its list from
`infra-validation.yml` — the property that stops it and CI drifting apart.

### Phase 3 — R2: reconcile the units whose drop-ins were delivered

#### Option choice

| Option | Verdict |
|---|---|
| **(a)** a `restart-unit` webhook hook | **Rejected.** Adds a remote-triggerable primitive to the one host that cannot be replaced, decouples the restart from the event requiring it, and falsifies the `tunnel -> hetzner` C4 description. |
| **(b)** fold reconciliation into `infra-config-apply.sh` | **Chosen.** Causally coupled — the event requiring the restart *is* the delivery — and it runs where the delivery outcome is already known and reported. |
| **(c)** accept; vector refreshes only on host recreate | **Rejected.** The telemetry plane ages out silently and R3 has no live channel. Half-implements the invariant `10-inngest-heartbeat-doppler-token.conf` states in its own header. |
| **(d)** reconcile inside `infra-config-install.sh` (already root) | **Rejected, on the real reason.** Zero new sudoers alias, zero `cloud-init.yml` edit, one fewer file on the SSH leg — genuinely attractive. But it is reachable through the **bare-command** grant `INFRA_CONFIG_INSTALL`, whose own header records that "sudo permits the bare command with ANY arguments — so the SECURITY BOUNDARY is here, not in sudoers." Putting a unit-restart capability behind a grant `deploy` may invoke directly with arbitrary arguments widens that boundary from *write these dests* to *write these dests and restart units*, on the host with no replacement path. The installer is also per-file and stateless while the decision is per-unit and needs the whole delivery outcome. |

**Note the shape:** every option, (d) included, needed 3.1 first. The security precondition is not a
property of the option chosen.

#### Tasks

3.1 **SECURITY PRECONDITION — validate drop-in content before anything can activate it.**
    `infra-config-install.sh`'s content gate is scoped to `/etc/default/*`; the three
    `*.service.d/*.conf` dests get **none**. `vector.service` runs `User=deploy`; systemd merges
    drop-ins after the unit body, so a drop-in may set `User=root`, reset and replace `ExecStart=`, or
    add `AmbientCapabilities=`. Today such a payload is inert because nothing root-restarts the unit;
    3.2 supplies exactly that. Extend the gate to drop-in dests with a **whitelist of permitted
    directives** — blank, comment, `[Service]`, `Environment=`, `EnvironmentFile=` — rejecting
    anything else with a named reason (`dropin_shape:bad_lines=N`). One rejection test per forbidden
    directive (`ExecStart=`, `User=`, `AmbientCapabilities=`, `NoNewPrivileges=`). `webhook.service`
    omits `NoNewPrivileges`, so this gate is the only boundary on that path.
3.2 **Sudoers, all three halves.** Add to `deploy-inngest-bootstrap.sudoers` **and** its
    `cloud-init.yml` mirror:

    ```
    Cmnd_Alias DROPIN_TRY_RESTART = /usr/bin/systemctl try-restart inngest-heartbeat.service, \
                                    /usr/bin/systemctl try-restart vector.service
    deploy ALL=(root) NOPASSWD: DROPIN_TRY_RESTART
    ```

    …**and** a post-write `grep -q DROPIN_TRY_RESTART /etc/sudoers.d/deploy-inngest-bootstrap`
    assertion in `server.tf`'s `infra_config_handler_bootstrap` `remote-exec` inline list, mirroring
    the two existing grant assertions there. **The `User_Spec` line is load-bearing and was missing
    from v1**: every existing alias in that file is paired with one, and without it every restart is
    denied while a shape-only AC stays green. Sudoers argument matching is exact, so
    `try-restart vector.service --no-block` is *denied* rather than widened — the risk is denial, not
    escalation, and denial is what the lockstep test in 3.10 pins.
3.3 **Restructure the script tail (P0 — a change to the existing state-machine contract).** Today the
    script writes the state JSON, touches `${STATE_FILE}.final` (disarming the EXIT trap), and only
    *then* runs `sync`/`daemon-reload`/self-restart. Reconciliation must run **after** `daemon-reload`
    but appear **in** the state JSON. So:
    - move `sync` + `daemon-reload` + the reconciliation loop **above** the state-write block;
    - leave only the delayed `systemd-run … restart webhook` after it;
    - add `"restarts":[]` and `"schema_version":2` to the EXIT-trap payload, so an unhandled abort
      reports *unhandled* rather than tripping 3.8's contract check;
    - **`rm -f "$STATE_FILE"`** alongside the existing `.final` removal at handler start, so an
      unfinished apply reads `{"exit_code":-2,"reason":"no_prior_apply"}` instead of serving the
      *previous* apply's frame as if it were current.

    That last item is not cosmetic: the gate's poll window is ~18 s while two synchronous
    `try-restart` calls can take longer, and on a future handler-only apply (the handler is **not** in
    `FILE_MAP`) no payload byte changes — so a stale frame would pass the count and content
    invariants and certify a `restarts` array produced by the *previous* apply. That is the #6594
    latched-false-green reproduced inside the mechanism built to end it.
3.4 **Writes stay UNCONDITIONAL; `changed` is derived, not enforcing.** v1 made the write
    content-conditional. That silently drops the per-apply re-assertion of `640 root:deploy` on the
    credential: a dest whose DAC drifted (world-readable, or `root:root` breaking `vector`'s read)
    matches on content, is skipped, reports `changed:false` — and the state JSON still says `ok`. The
    one channel that could repair it stops repairing it. So:
    - every `FILE_MAP` entry is installed on every apply, exactly as today. `status:"ok"`, non-empty
      `sha256`, `WRITTEN_COUNT` incremented — the delivery invariant `adjudicate_infra_config` and
      `infra_config_content_assert` depend on is untouched;
    - `changed` is computed from a `sha256sum` compare of the staged temp against the existing dest
      and used **only** by 3.5's predicate;
    - to stop clause-equivalent over-firing, preserve the drop-in's mtime on a content-identical write
      (`touch -r "$dest" "$tmp"` before install);
    - **compare with `sha256sum` only.** Never `diff`/`cmp -l`/`od` on a `FILE_MAP` dest — a `diff` of
      `/etc/default/soleur-doppler-token` prints the prd token into journald → vector → Better Stack;
    - `lstat`-guard the pre-write read: `[[ -L "$dest" ]]` ⇒ treat as changed, never follow.
3.5 **One restart predicate.** For each unit in a fixed in-script `RESTART_MAP`, restart when the unit
    is running config older than anything it depends on:

    ```
    stale(unit) :=  ExecMainStartTimestamp(unit)  <  max( mtime(drop-in),
                                                          mtime(/etc/default/soleur-doppler-token) )
    ```

    This subsumes v1's three OR'd clauses and is strictly more correct — it also heals a credential
    rotation predating this PR. One `reason` enum (`stale_config`) naming *which file is ahead of the
    process*. Guard rails, in order:
    - **`ActiveState` first.** Inactive ⇒ `action=skipped reason=unit_inactive`, **no attempt**.
      `ExecMainStartTimestamp` is empty for an inactive unit, so treating empty as
      "unparseable ⇒ stale" builds a loop that never self-disarms while reporting success.
    - **`try-restart` is a no-op on a *failed* unit and still exits 0**, and on a `Type=simple` unit
      its 0 means *forked*, not *running*. Grade on effect: after a short settle, re-read
      `systemctl show <unit> -p ActiveState -p ExecMainStartTimestamp -p NRestarts`.
      `action=restarted` only when `ActiveState=active` **and** the timestamp advanced; otherwise
      `noop_not_active` or `restart_did_not_advance`.
    - `reason=timestamp_unparseable` is reserved for a **non-empty** value `date -d` cannot parse.
    - A denied `sudo` emits `sudo_denied` — a provisioning defect, never sharing an enum with
      `unit_inactive` or `noop_not_active`.
    - `DropInPaths` is **not** a valid input: `daemon-reload` refreshes systemd's in-memory view, so
      it lists the new drop-in even though the process never re-execed.
    - **Ordering: `vector` last** — restarting it blinks the stream every post-apply assertion reads
      through.
3.6 **Guard every new fallible read.** `stat -c %Y` on a dest that does not exist exits 1;
    `sha256sum` on a missing dest exits 1; `systemctl show` can fail. Under this script's
    `set -euo pipefail` any of those kills the handler **mid-loop**, the EXIT trap overwrites the
    state with `files_total:0, reason:"unhandled"`, and the post-write `daemon-reload` + webhook
    self-restart never run — a freshly-delivered `hooks.json` written but never activated. That is the
    #4804 chicken-and-egg freeze re-entered, and it is deterministic. Every new read follows the
    file's existing guarded idiom (`|| rc=$?`, `if ! cmd`, `2>/dev/null`) with a per-file/per-unit
    reason enum (`dest_absent`, `dest_unreadable`, `timestamp_unparseable`).
3.7 **Report, with the data that make it checkable.** Emit
    `SOLEUR_INFRA_CONFIG_RESTART: unit=<u> action=<enum> reason=<enum> rc=<n> active=<state>` per
    unit, and add to the state JSON:

    ```json
    "schema_version": 2,
    "restarts": [ { "unit": "...", "action": "...", "reason": "...", "rc": 0,
                    "active": "active", "nrestarts": 0,
                    "exec_main_start_ts_before": 0, "exec_main_start_ts_after": 0 } ]
    ```

    Epoch seconds, closed vocabulary, no host paths. `exec_main_start_ts_*` is what AC-PM-2 reads —
    v1 asserted a field the plan never emitted — and is the same datum 3.5's grading needs.
3.8 **Gate assertion, staged so it cannot brick the channel it protects.** In `infra-config-gate.sh`,
    and **only in `adjudicate_infra_config` (terminal), never in `infra_config_count_invariant`** —
    the latter is the poll break-condition, so a timing race there would burn all three attempts and
    become an unretried terminal red:
    - `schema_version < 2` or key absent ⇒ `::warning::infra_config_handler_predates_restarts` naming
      the handler-bootstrap leg, and **pass**. The absence can only be repaired over that leg, so
      failing here would red `adjudicate_infra_config`, which skips the `if: success()`-gated
      *Redeploy to load applied profile* step — files land, activation never happens, and the only
      route to the missing key is the leg ADR-154 says can be dead on a host that cannot be replaced;
    - `schema_version >= 2` ⇒ the array must cover every `RESTART_MAP` unit, and **fail** on any
      `rc != 0`, `active != active`, or
      `action ∈ {noop_not_active, restart_did_not_advance, sudo_denied}`. A delivered-but-unactivated
      unit is precisely ADR-158 proposition 1's defect.

    The hard-on-absent flip happens in a follow-up once one apply has demonstrably delivered the
    contract; that flip is recorded on #7103, not smuggled in here.
3.9 Ordering is a **task**, not a verification: assert the `depends_on` edge from `deploy_pipeline_fix`
    to `infra_config_handler_bootstrap` (it exists today — verified) and that both
    `infra-config-apply.sh` and `deploy-inngest-bootstrap.sudoers` are inside the bootstrap resource's
    `triggers_replace` hash (they are — verified). Correct the two stale "18 allowlisted destinations"
    comments in `infra-config-install.sh` to 19.
3.10 **Test seam and lockstep.** Introduce
    `SYSTEMCTL="${INFRA_CONFIG_SYSTEMCTL:-sudo /usr/bin/systemctl}"` so the suite injects a stub and
    the predicate/reporting/ordering logic runs **unguarded** in sandbox mode, with only the `sudo`
    self-restart behind `INFRA_CONFIG_TEST_MODE` — without the seam, AC-R2-4/AC-R2-7 assert behaviour
    gated out of the test run. Add a **sudoers↔caller argv lockstep** assertion extracting the
    `DROPIN_TRY_RESTART` argv from both sudoers files and the `sudo systemctl` argv from
    `infra-config-apply.sh`, requiring byte equality per unit (anchored) — the
    `GIT_LOCK_CHARDEVICE_SWEEP` block records the precedent and the #5934 outcome when it drifts:
    "sudo denies the sweep… and the durable remediation is a SILENT no-op."
3.11 Tests in `infra-config-apply.test.sh` (registered): the staleness predicate fires and
    self-disarms; `unit_inactive` short-circuits without an attempt; a stub unit that exits
    immediately after fork yields `noop_not_active` and **reds the gate**; `vector` is ordered last
    (asserted on marker order, not declaration order); the array is emitted in every outcome; a
    missing dest, an unreadable dest, and an unparseable `systemctl show` each leave
    `files_written == files_total` and still reach the post-write block; the stub was invoked; the
    drop-in shape gate rejects each forbidden directive; a gate fixture with all 19 files at
    `changed:false` still passes `adjudicate_infra_config`.

### Phase 4 — R3: an absence assertion that cannot pass while the channel is dark

**Hard-gated on Phase 3.** No task here may be verified against a live channel before Phase 3 has
landed *and applied*.

4.1 Create `scripts/betterstack-assert-absence.sh` with **four** outcomes, evaluated in order:

    | outcome | condition | exit |
    |---|---|---|
    | `unknown` | the query did not answer — any non-zero `betterstack-query.sh` exit, or output that does not parse as JSONEachRow | 3 |
    | `unshipping` | control == 0 | 2 |
    | `present` | absence > 0 | 1 |
    | `clean` | absence == 0 **and** control ≥ 1 | 0 |

    The `unknown` arm is the correction v1 missed: `betterstack-query.sh` exits 3 on absent
    credentials and errors the whole query if its archive arm fails — in both cases stdout is empty,
    which a row-count parse reads as *absence satisfied*. That is the same ADR-154 proposition-2 shape
    the helper exists to enforce, applied to the absence arm but not to its own transport.
    `unshipping` and `unknown` are **never** reported as `clean`.

    It stays a **separate script**, not a flag on `betterstack-query.sh`: that file is a pure transport
    whose exit vocabulary is already spoken for (`3` = credentials not injected, `64` = bad flag /
    underivable archive table, otherwise `curl --fail-with-body`'s codes) and whose header promises
    verbatim SQL passthrough with one output contract.
4.2 **The control is host-scoped and read at the sink.** Two independent corrections:
    - **Host scoping.** `betterstack-query.sh` has **no `--host` flag**, and repeated `--grep` terms
      are **OR**-combined (`raw LIKE '%a%' OR raw LIKE '%b%'`). Meanwhile `vector.toml` states all
      hosts multiplex into the one Logs source with `host_name` as the sole discriminator, and
      `web-zot-consumer-probe` is provisioned `for_each var.web_hosts`. A `--grep`-based control would
      therefore let **another** host's canary certify this host's vector — a false `clean` on exactly
      the host under test. Implement the control read in raw-SQL mode with an explicit `host_name`
      predicate applied to **both** the hot and archive arms.
    - **Read at the sink, not the host.** A `logger` call proves the script ran, not that anything
      shipped. Reading the canary back *through Better Stack* proves journald → vector → sink end to
      end.
4.3 **Make the control credential-independent.** `_canary()` runs *inside*
    `doppler run --project soleur --config prd -- …`, so a dead prd token exits before the inner
    `bash` ever execs and the canary is never emitted — the control is gated behind the exact
    credential whose failure it is used to certify absent. Hoist the rate-limited emit out of the
    wrapper (an `ExecStartPre=` carrying the same `/run` marker rate-limit, or a small
    `web-zot-consumer-probe-canary.sh` invoked before `doppler run`). Record in 4.1 that even then
    `unshipping` cannot discriminate vector-death from probe-unit-death — an honest limit, not a
    defect.
4.4 Window discipline: the canary is rate-limited to 1800 s, so the minimum valid window is **1 h**. A
    shorter `--since` is rejected with a named error rather than evaluated — a false `unshipping`
    teaches the operator to ignore the signal, the review-fatigue class #6454 names.
4.5 **Tie the control to its wiring — in the suite that already owns that assertion.** Add four
    anchored assertions to `apps/web-platform/infra/journald-config.test.sh` (registered): (i)
    `web-zot-consumer-probe` is in `vector.toml`'s Source-4 allowlist; (ii)
    `web-zot-consumer-probe.service` sets that literal `SyslogIdentifier=`; (iii) the probe still
    emits `SOLEUR_PROBE_CANARY`; (iv) **the emit site is outside the `doppler run` wrapper** (4.3's
    invariant, otherwise one refactor from silently regressing). No new file, no mutation ceremony
    around one-line greps — the runtime backstop is `unshipping` at the sink.
4.6 Repoint the AC12/AC13 discoverability command in the 2026-08-01 plan at the new helper. Scoped to
    that one live recipe; historical incident prose keeps its point-in-time query.
4.7 **Follow-through enrollment — on a dedicated issue, not on #7103.** `sweep-followthroughs.sh`
    **closes the issue on PASS**; enrolling a seven-item tracker would auto-close #7103 with B1–B7 and
    R1's half (a) still open — the exact outcome AC-X-5 exists to prevent. So: file *"AC12 telemetry
    positive control — #7103 R3 soak"*, cross-link it from #7103, and put the directive there:

    ```
    <!-- soleur:followthrough script=scripts/followthroughs/ac12-telemetry-positive-control-7103.sh
         earliest=<concrete YYYY-MM-DD stamped at /ship>
         secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
    ```

    **Literal secret names, not `BETTERSTACK_*`** — the sweeper matches by exact variable name, not
    glob, and all three already exist in `scheduled-followthrough-sweeper.yml` (so "wire any new
    `secrets=`" is a no-op; the wildcard was the whole defect). **A concrete `earliest`**, because
    `iso_to_epoch` returns `0` on anything `date -u -d` rejects, so a literal `<apply+1d>` placeholder
    makes the soak gate silently disappear and the probe run on merge day.

    The probe must additionally:
    - **self-guard**: read `start_ts` from `/hooks/infra-config-status` and **exit 1** if less than
      1 h has elapsed since the apply, so a bad `earliest` cannot produce a day-0 PASS;
    - **require the subject to have run**: at least **3** `SOLEUR_DEPLOY_INVOCATION` rows in the
      window for AC-PM-5 (≥1 for AC-PM-3's `script_sha` read). Without this, zero `ci-deploy`
      invocations make the absence half trivially true while the canary — emitted by an independent
      60 s timer — satisfies the control, yielding `clean` → PASS → close, with both hypotheses still
      ungraded;
    - **map `unshipping` and `unknown` to exit 1 (FAIL).** The sweeper comments `TRANSIENT` on any
      exit other than 0/1 and never escalates, so exits 2/3 would accrete daily comments forever. A
      dark or unanswerable channel must read as a failure.

    Model it on `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`, `start=` pinned strictly
    after the deploy.

### Phase 5 — R4: commit the digest-oracle regression harness

5.1 **Mask first, then identify.** In the *Export rendered credential digest* step, immediately after
    capture and before any branch:

    ```bash
    [[ -n "$b64" ]] && printf '::add-mask::%s\n' "$b64"
    ```

    This repo is **PUBLIC**; Actions logs are world-readable; `nonsensitive()` is applied deliberately;
    and GitHub's masker redacts only the registered literal `secrets.DOPPLER_TOKEN`, never a base64
    re-encoding. There are currently **zero** `::add-mask::` calls in this workflow while a sibling
    infra workflow has twenty. Then add `id: rendered_digest` — keying a guard on a free-text `name:`
    makes it "one cosmetic rename away from a spurious red" (`git-data-rung2-rehearsal.test.sh`'s own
    words).
5.2 **Correct the step's stated safety contract.** Its comment says *"So: no `set -e`"* — but GitHub
    invokes a bare `run:` as `bash -e {0}`, so errexit is **inherited**. The body survives only because
    every failure-capable command is inside `|| …` or an `if` condition. Either add an explicit
    `set +e` (if the never-blocks contract is real) or correct the comment to say errexit is in force
    and every command is deliberately guarded. A comment that overstates the control it substitutes is
    the defect class this whole PR is about.
5.3 Create `scripts/digest-oracle-guard.test.sh`. It parses the workflow, locates the step by
    `id: rendered_digest`, extracts `step["run"]`, and executes it **hermetically**:
    - `env -i PATH="$stub/bin" HOME=… GITHUB_ENV="$tmpenv" bash -e "$body"` — `env -i`, **not** a
      `PATH` prefix. A prefix leaves the real `doppler`/`terraform` reachable and the ambient
      environment (any `DOPPLER_TOKEN`) visible;
    - assert `command -v doppler` and `command -v terraform` both resolve inside `$stub/bin`, and that
      the real binaries were not invoked (the stub keeps a call log);
    - `GITHUB_ENV` is a per-arm `mktemp`; assert its final content is either empty or exactly one
      `INFRA_CONFIG_RENDERED_SHA__…=<64hex>` line;
    - **refuse to run under `pull_request_target`** (`exit 2`) — the suite executes a `run:` body taken
      from the PR head, i.e. attacker-controlled code by construction.
5.4 Three cases from the #7140 PR body, plus three regression arms:

    | stub behaviour | required outcome |
    |---|---|
    | console prints `(sensitive value)` | `::warning::`, **nothing** appended to `$GITHUB_ENV` |
    | console exits non-zero, no output | `::warning::`, **nothing** appended |
    | valid base64 of a payload whose first line is `DOPPLER_TOKEN=` | the **exact** digest, byte-for-byte |
    | base64 of a payload **without** the marker | export nothing (content gate, not shape gate) |
    | any arm | the exported digest is **never** `e3b0c442…b855` (sha256 of the empty string) — the literal that made the pre-#7140 step announce ACTIVE while hashing nothing |
    | errexit posture | inject a bare failing command into a sandbox copy of the body; assert the arm reddens — proving the guard, not the comment, is what holds |

5.5 Anti-vacuity floor (`MIN_ASSERTS`). No failure message may interpolate the fixture payload, `$b64`,
    or decoded bytes — asserted by grepping the harness's own output for the fixture literal and
    requiring zero hits (mirror of AC-R1-5). Fixtures synthesized only
    (`cq-test-fixtures-synthesized-only`).
5.6 Fixture-precondition self-check: workflow present and the `id:` locatable, else `exit 2` naming the
    drift. Register with a `run_suite` line in `scripts/test-all.sh`.
5.7 **The gating decision, recorded.** This suite lands in the **required** `test` check:
    - #6454's constraint is about **external tooling** on the merge-queue critical path
      (`run-all.sh`'s `CONTRACT (#6454)`: "BASH-ONLY: no terraform, no cloud-init, no apt"). This
      harness stubs `doppler` so `terraform` is never reached, and needs only `bash` +
      `python3`+`yaml`, which two sibling suites in the *same required check* already use.
    - The alternative home (`apps/web-platform/infra/`, run by the **advisory** `deploy-script-tests`
      job) would put a regression guard in a runner nobody is blocked by — reproducing, in the same
      PR, the defect R5 exists to fix.
    - Escape hatch if 0.4 fails: a path-filtered standalone workflow, downgrade recorded in the PR
      body.

### Phase 6 — R5(b): prove the liveness gate is non-deletable

6.1 Create `scripts/cf-tunnel-liveness-gate-mutations.test.sh`, modelled on
    `.github/scripts/test/test-infra-suite-registration-mutations.sh` — a `mktemp -d` sandbox that
    **never** mutates tracked files, a green control first, `assert_landed` per mutant, and per-mutant
    *message* assertions rather than bare exit codes.
6.2 Seven arms (v1's M2 cut: W3's anchor is a whole-file grep, so deleting the step and deleting only
    the echo line remove the same line — M1 already covers it):

    | # | Mutation | Must red |
    |---|---|---|
    | M1 | Delete the entire gate step, **leaving the header comment intact** | W1, W3, W4, W5 |
    | M3 | Move the gate step so it is no longer final | W6 |
    | M4 | Repoint one caller at a different action and add a spare `uses:` elsewhere; total unchanged | W7 (membership, not cardinality) |
    | M5 | Delete the `-replace=cloudflare_zero_trust_access_service_token.ci_ssh` line, leaving the dispatch-input prose | W9 |
    | M6 | Retarget the escalation step's `if:` to `verdict == 'unverifiable'` | W10 |
    | M7 | **Control:** unmutated sandbox is green | — |
    | M8 | **Anti-vacuity:** delete every assertion call; the suite must NOT exit 0 (the ≥50 floor) | floor |

6.3 A mutant that stays green is a **hard failure of this battery**. Register with a `run_suite` line.

**Why this and not more anchoring:** the anchoring shipped in #7133 and is correct. What did not ship
is anything that keeps it correct. The 2026-08-01 learning
`…my-mutation-battery-inferred-the-verdict-from-the-input-under-test.md` is the direct warning: a
battery whose stub derives the expected verdict from the input under test reports all-caught while
pinning nothing. M4 and M8 exist precisely because they are the arms such a battery passes vacuously.

### Phase 7 — Records

7.1 **ADR-158** (provisional ordinal, re-derived from a freshly-fetched `origin/main`).
7.2 One `model.c4` element-description sentence naming the drop-in shape gate as the
    delivery↔activation boundary (see §Architecture Decision — this is the only C4 edit in scope).
7.3 Append one Session Error to
    `knowledge-base/project/learnings/2026-08-01-i-shipped-a-gate-my-own-tests-could-not-see.md`: the
    "240/240 was read as the exit gate for a diff whose guards live in a runner `test-all.sh` does not
    cover" fact lives only in commit `bf4816455`'s body, and the learning's Session Errors 1–14 omit
    it. A learning that omits the lesson its own commit message states is the perishable-evidence
    class this plan exists to end.
7.4 CHANGELOG is **not** touched (`wg-never-bump-version-files-in-feature`).

---

## Infrastructure (IaC)

**No operator step exists anywhere in this plan**, and no step is executed over SSH by a human.

### Terraform changes

No new Terraform **resource**. Two existing resources carry the payload:

| Resource | Role | File |
|---|---|---|
| `terraform_data.infra_config_handler_bootstrap` | Delivers the edited `infra-config-apply.sh`, `infra-config-install.sh`, and `deploy-inngest-bootstrap.sudoers`. Sudoers must ride this leg: it is deliberately absent from `FILE_MAP` so the handler cannot widen its own privileges. Gains one post-write `grep` assertion for the new alias. | `server.tf` |
| `terraform_data.deploy_pipeline_fix` | `local-exec` → `push-infra-config.sh` → HMAC POST to `/hooks/infra-config`, delivering `ci-deploy.sh`, `hooks.json`, and the drop-ins. SSH-free by construction. `depends_on` the bootstrap resource (verified present). | `server.tf` |

Required variable changes: **none**. No new `TF_VAR_*`, therefore no operator mint. Both edited files
are already inside the bootstrap resource's `triggers_replace` hash (verified). `cloud-init.yml` gains
the mirrored `Cmnd_Alias` **and its `User_Spec` line** so a fresh host boots with the grant.

### Apply path

**(b) cloud-init + idempotent handler, on the existing auto-apply.** Merging this PR *is* the apply:

1. `terraform apply`; the handler-bootstrap leg lands the new handler, installer, and sudoers over the
   CF-Tunnel SSH bridge (final step: ADR-154's transport probe);
2. `deploy_pipeline_fix`'s `local-exec` pushes the `FILE_MAP` payload over HTTPS + HMAC + CF Access;
3. the handler clears the stale state file, writes the files, `daemon-reload`s, reconciles
   `RESTART_MAP`, **then** writes the state JSON, then self-restarts `webhook`;
4. `infra-config-gate.sh` asserts per-file delivery and (staged per 3.8) the `restarts` array;
5. `/hooks/infra-config-status` returns the state JSON — how the result is verified, over HTTPS.

**New: a CI lever for the bricked-channel recovery.** The workflow's own `000|502|503` branch says a
plain re-run does not fix a wedged bootstrap and prescribes
`terraform apply -replace=terraform_data.infra_config_handler_bootstrap` — but the apply step is a
fixed `-target` invocation with no `-replace`, and `workflow_dispatch.inputs` exposes only `reason`
and `allow_missing_status_endpoint`. The prescribed route is therefore operator-local Terraform, which
this plan's own banner says does not exist and which `hr-no-ssh-fallback-in-runbooks` forbids as a
runbook exit. Add a `workflow_dispatch` input `replace_target` with an allowlisted enum
(`none` | `infra_config_handler_bootstrap` | `deploy_pipeline_fix`), routed through an env var and
appended as `-replace=terraform_data.<value>` to both the plan and apply commands — the existing
`host_creates` destroy-guard already bounds the blast radius. Update the 000/502/503 text and 3.8's
warning to name that dispatch arm.

**Blast radius / downtime:** see `## Downtime & Cutover`. No container swap, no host replace, no
deploy.

### Distinctness / drift safeguards

- **`dev != prd`:** this path exists only in `prd`; Doppler config is `prd_terraform` throughout.
- **`lifecycle.ignore_changes`:** `hcloud_server.web` carries `ignore_changes = [user_data]`
  (verified), so `cloud-init.yml` edits do **not** reach the running host — the mirror is for future
  hosts only. The live grant arrives via the bootstrap leg. Stated explicitly because assuming
  otherwise makes Phase 3 a silent no-op on web-1.
- **`-replace` on the host is unavailable** per ADR-154 (`cx33` zero stock, 6/6 datacenters). The new
  `replace_target` input is scoped to the two `terraform_data` resources and cannot reach
  `hcloud_server.web`.
- **State storage:** no secret value enters `terraform.tfstate`.

### Vendor-tier reality check

No vendor resource is created. Better Stack usage is **read-only** against the existing Logs source
and adds no monitor or heartbeat, so no `betteruptime_policy` and no free-tier gate. Hetzner: no new
server, volume, or firewall rule. Cloudflare: no new token, ruleset, or DNS record.

---

## Architecture Decision (ADR/C4)

### ADR

**ADR-158 — Delivery is not activation, and absence is not evidence.** (Provisional ordinal 155,
re-derived from a freshly-fetched `origin/main`.)

1. **A config push that writes a unit drop-in must reconcile the running unit, must validate what it
   wrote before anything can activate it, and must report per unit what it did — including when it did
   nothing.** `daemon-reload` makes systemd *aware* of a drop-in; it does not make a running process
   *use* it. And a delivery channel that writes unit configuration without a content gate is not a
   delivery channel once something root-restarts those units — it is an execution channel. A restart
   *reported* without evidence the process re-execed (a timestamp that advanced, an `ActiveState` that
   is `active`) is the same defect one level in.
2. **A telemetry absence is not evidence unless the same query window carries a positive control read
   at the sink, scoped to the same host, and emitted independently of the credential under test.**
   `clean`, `unshipping`, and `unknown` must not share a code path or an exit code. ADR-154's
   proposition 2 pushed one layer down, to the channel itself.
3. **An execution path whose environment can differ from its sibling's must self-report its identity,
   its own bytes, and its credential source — once.** Two markers with one precondition are one fact.

Extends, does not reverse, ADR-154. Alternatives (a), (c), (d) and their rejection reasons are in
Phase 3's option table.

### C4 views

**One element description must be corrected** — v1's "no actor gains access" row was **false**, and
the correction is itself the finding. No new element, edge, or view.

| Category | Enumerated | Verdict |
|---|---|---|
| **External human actors** | `founder` | Already modelled (`sentry -> founder`, `betterstack -> founder`) |
| **External systems** | Better Stack, Sentry, Doppler, Cloudflare, GitHub Actions | Already modelled with the relevant edges |
| **Containers / data stores** | None new | n/a |
| **Access relationships that change** | **Changed, and it must be recorded.** The `deploy` user gains the ability to *activate* unit configuration it can already write. The real delta is **delivery-only → delivery + activation**, mitigated by the 3.1 drop-in shape gate. Root-equivalence already existed transiently via `INNGEST_BOOTSTRAP` inside `webhook.service`'s namespace; this would have added a persistent, namespace-independent one. | The `hetzner` element description gains one sentence naming the shape gate as the boundary. **The one C4 edit in scope (7.2).** |
| **Edges this would falsify** | `tunnel -> hetzner` enumerates hook routes by name. **Option (a) would have falsified it**; option (b) adds no hook | Stays true |
| **Edges strengthened** | `hetzner -> betterstack` — the Vector agent now re-execs on credential rotation instead of aging out | Yes |

After the edit, run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` (AC-X-6) —
a `view … include` referencing an undefined element fails there, not at `tsc`.

---

## Observability

```yaml
liveness_signal:
  what: SOLEUR_DEPLOY_INVOCATION (per ci-deploy invocation) and SOLEUR_INFRA_CONFIG_RESTART
        (per unit per infra-config apply)
  cadence: event-driven (per deploy / per apply), not periodic
  alert_target: Better Stack Logs source 2457081, host soleur-web-platform, via journald -> vector
                Source 4 (the SYSLOG_IDENTIFIER allowlist)
  configured_in: apps/web-platform/infra/ci-deploy.sh (readonly LOG_TAG="ci-deploy"),
                 apps/web-platform/infra/infra-config-apply.sh (readonly LOG_TAG="infra-config-apply").
                 Both identifiers verified present in vector.toml Source 4 AND set by live
                 `logger -t "$LOG_TAG"` call sites — neither is a dead allowlist entry.

error_reporting:
  destination: Sentry (baked-DSN host path, credential-independent) for
               zot_gate_degraded_event no_credential_source; GitHub Actions job failure for the CI
               suites and for infra-config-gate.sh; the infra-config state JSON, readable over
               /hooks/infra-config-status, for per-unit restart outcomes
  fail_loud: true — every new branch emits. `skipped` carries the same weight as `restarted`;
             `noop_not_active`, `restart_did_not_advance`, and `sudo_denied` are distinct enums that
             fail the gate; the credential-file else branch feeds the marker's cred_file value.

failure_modes:
  - mode: infra-config delivers the drop-in but the unit is never re-execed (today's R2 state)
    detection: the restarts array names the unit with action=skipped while its dependency-set mtime
               exceeds ExecMainStartTimestamp
    alert_route: layer 6 — infra-config-gate.sh adjudicate_infra_config -> apply-deploy-pipeline-fix
                 job failure
  - mode: the restart is attempted and the process does not come back
    detection: active != "active", or exec_main_start_ts_after did not advance
    alert_route: layer 6 — the gate fails on any action in {noop_not_active,
                 restart_did_not_advance, sudo_denied} or active != active
  - mode: vector.service dies on the reconciliation restart, and vector cannot report its own death
            (vector.toml excludes vector.service from its own sources; its console sink is
            journald-only and unshipped)
    detection: the `active` field for vector.service in the state JSON, read over HTTPS from
               /hooks/infra-config-status — the one transport that survives a dead vector
    alert_route: layer 6 — gate failure. Out-of-band corroboration: absence of SOLEUR_PROBE_CANARY at
                 the sink, which the Phase 4.1 helper grades as `unshipping`.
  - mode: the sudo grant is missing (alias without User_Spec) so every restart is denied
    detection: action=sudo_denied; plus the 3.10 lockstep + sudoers-shape tests pre-merge, and the
               server.tf remote-exec grep at delivery time
    alert_route: required `test` check pre-merge; gate failure post-merge
  - mode: vector restart-loops on every apply, blinking telemetry each merge
    detection: action=restarted on consecutive applies with no dependency-set mtime change
    alert_route: layer 6 — infra-config-gate.sh fails when a unit reports action=restarted while
                 `changed` is false for both its drop-in and the credential and the reason is not the
                 one-shot heal. (NOT a pre-merge AC, which cannot fire in production.)
  - mode: the telemetry query itself fails and empty output reads as absence satisfied
    detection: scripts/betterstack-assert-absence.sh returns `unknown` (exit 3), never 0
    alert_route: the AC12 follow-through probe, which maps it to FAIL
  - mode: the channel is dark and an absence query reads as clean
    detection: the helper returns `unshipping`, mapped to exit 1 so the sweeper reports FAIL rather
               than accreting daily TRANSIENT comments
    alert_route: scheduled-followthrough-sweeper.yml on the dedicated soak issue
  - mode: the positive control is silently unwired, or re-buried inside `doppler run`
    detection: the Phase 4.5 four-way assertion in journald-config.test.sh
    alert_route: required `test` check
  - mode: a ci-deploy invocation runs with no credential source (the R1 state)
    detection: SOLEUR_DEPLOY_INVOCATION with doppler_token=absent, plus
               zot_gate_degraded_event no_credential_source in Sentry
    alert_route: Sentry issue alert -> email (the baked-DSN path survives a dead Doppler token)
  - mode: the local suite silently excludes a runner again
    detection: scripts/lint-orphan-test-suites.sh REQUIRED_RUNNERS check
    alert_route: required `test` check

logs:
  where: Better Stack Telemetry (ClickHouse) source 2457081 via scripts/betterstack-query.sh;
         GitHub Actions logs
  retention: ~3 days hot+archive for Better Stack; 90 days for Actions logs

discoverability_test:
  command: curl -sS -o /dev/null -w '%{http_code}' --max-time 10 https://app.soleur.ai/health
  expected_output: "200"

# WHY THIS IS ONE UNAUTHENTICATED CURL AND NOT THE FULL RECIPE (corrected 2026-08-03).
# It was `bash scripts/test-all.sh && doppler run … && doppler run … && curl …`, which
# /ship preflight Check 10 refuses to execute: the check runs the command with `env -i` but
# `$HOME` PRESERVED, so a `doppler` invocation reaches the operator's on-disk token — and the
# gate's credentialed-CLI reject fires rather than running it. So the field that exists to be
# EXECUTED could never be executed, which is the same "declared-verifiable but unverified" gap
# the field was added to close (#4148).
#
# `discoverability_test.command` means: ONE command, no ssh, no credentials, that an operator
# can run locally to answer "is this observable at all?". The full verification recipe is a
# different thing and lives below as prose, where nothing tries to run it.
#
# full_verification (operator recipe — credentialed, NOT the discoverability probe):
#   1. bash scripts/test-all.sh                    -> suite count = baseline + 6
#   2. doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-assert-absence.sh \
#        --since 2h --host soleur-web-platform --absence 'Doppler Error: Invalid Auth token'
#      -> `clean` exit 0, or `unshipping`/`unknown` exit 2/3 — the latter two being the point
#   3. doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
#        --since 2h --grep SOLEUR_DEPLOY_INVOCATION --limit 20
#      -> at least one row whose script_sha matches the deployed ci-deploy.sh
  # Contains no remote-shell invocation.
```

---

## Encryption Posture

```yaml
at_rest:
  - store: /etc/default/soleur-doppler-token (host disk, ext4 root volume)
    mechanism: plaintext-exception (pre-existing; delivered by #7095/#7133, not introduced here)
    evidence: infra-config-apply.sh FILE_MAP entry `640|root:deploy`; cloud-init.yml
              `install -m 640 -o root -g deploy`
    defends_against: read by any non-root, non-`deploy` local account; accidental world-read
    does_not_defend: root compromise; offline disk imaging; a `deploy`-user compromise (the account
                     webhook.service runs as, by design — ci-deploy.sh must read the file)
    disclosed_as: host-local credential material; Art. 30 unaffected (no personal data)
    live_verification: every apply re-installs the dest, re-asserting 640 root:deploy (Phase 3.4 keeps
                       the write UNCONDITIONAL precisely so this remains true); the state JSON reports
                       the delivered sha256 and infra-config-gate.sh tier-2 byte-compares it
exception:
  justification: The credential must be readable by an unprivileged systemd unit at process start. An
                 encrypted-at-rest form needs a key readable by the same unit, relocating rather than
                 removing the exposure. Pre-existing decision of #7095.
  tracking_issue: 7103 (B5 — the copy-invariant ADR)
  reevaluate_when: B5's ADR is written, or a host-level secrets agent is introduced
  expires_on: 2026-11-01
in_transit:
  - connection: GitHub Actions -> deploy.soleur.ai/hooks/{deploy,infra-config,infra-config-status}
    tls: TLS 1.2+ via the Cloudflare edge, plus HMAC-SHA256 payload signature and CF Access
         service-token headers
    cert_verification: on (curl default; no -k on this path)
    does_not_defend: a compromised WEBHOOK_DEPLOY_SECRET or CF Access service token — the #7095
                     failure, and why ADR-154's transport probe is the final bridge step
    disclosed_as: internal control plane; no personal data crosses it
  - connection: host vector -> Better Stack Logs (s2457081.eu-fsn-3.betterstackdata.com)
    tls: HTTPS, bearer token from BETTERSTACK_LOGS_TOKEN
    cert_verification: on (Vector http sink default)
    does_not_defend: >-
      Credential material in log content. CORRECTED from v1, which claimed vector.toml's "three-stage
      PII scrub" as the mitigation: that scrub redacts user PII (userid, OAuth params, email,
      Authorization headers, URL userinfo) and control characters, and has NO pattern for a Doppler
      service token (dp.st./dp.sa./dp.pt.), a GitHub token (ghp_/ghs_/github_pat_), or a generic
      high-entropy bearer outside an Authorization header. The real control for THIS plan's markers is
      that their vocabulary is closed by construction (enums, a truncated sha, epoch integers),
      asserted by AC-R1-5 — not the scrub. Token-shaped redaction is filed as a follow-up on #7103
      rather than smuggled in here; it needs its own pins in vector-pii-scrub.test.sh and
      cq-regex-unicode-separators-escape-only applies to any pattern added there.
    disclosed_as: telemetry, EU (eu-fsn-3) residency
  - connection: GitHub Actions workflow log -> public internet
    tls: n/a (a disclosure surface, not a transport)
    cert_verification: n/a
    does_not_defend: >-
      Anything printed unmasked. The repo is PUBLIC (verified), and the digest step renders a base64
      of the live prd DOPPLER_TOKEN under nonsensitive(). GitHub's masker does not redact a
      re-encoding of a registered secret. Mitigated by the 5.1 ::add-mask::, the hermetic env -i
      harness (5.3), and the no-interpolation assertion (5.5 / AC-R4-6).
    disclosed_as: public build log
```

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — required by the threshold).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The deepen pass moved seven findings from "would have shipped" to "corrected in the
plan", two of them security-class. The grant that motivated the whole phase turned out to complete a
`deploy` → root chain because the installer validates only `/etc/default/*`; the shape gate now
precedes the grant, and the C4 access row — which claimed no actor gained anything — is corrected. The
public-repo credential exposure on the digest step is independent of this PR but is made materially
riskier by committing a harness that re-executes that body, so the `::add-mask::` ships with the
`id:`. On reliability, three distinct routes to bricking the sole remediation channel are closed
(unguarded reads aborting the write loop, a fail-closed gate that skips the `if: success()` activation
step, and a stale state frame). The restart is now graded on `is-active` + timestamp advancement
rather than on `try-restart`'s exit code, which is fork-success on a `Type=simple` unit and a silent
no-op on a failed one. Remaining risk is the delivery-leg dependency, Risk 1, now with a CI lever
<!-- lint-infra-ignore start: negated mention — "a CI lever INSTEAD OF" an operator step; no human step is prescribed -->instead of an operator-local `terraform apply`.<!-- lint-infra-ignore end -->

### Product/UX Gate

**Tier:** none — the mechanical UI-surface override did not fire. No path in Files to Create/Edit
matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface term.
**Decision:** n/a. **Agents invoked:** none. **Skipped specialists:** none.
**Pencil available:** N/A (no UI surface). CPO sign-off remains required by the threshold.

---

## GDPR / Compliance

Not invoked. No regulated-data surface: no schema, no migration, no `.sql`, no auth flow, no API
route. None of the four expansion triggers fire. The new markers carry a closed vocabulary and no
personal data.

---

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/digest-oracle-guard.test.sh` | R4 — hermetic harness for the `rendered_digest` step |
| `scripts/cf-tunnel-liveness-gate-mutations.test.sh` | R5(b) — 7-arm non-deletability battery |
| `scripts/betterstack-assert-absence.sh` | R3 — four-outcome absence assertion, host-scoped control |
| `scripts/betterstack-assert-absence.test.sh` | R3 — its suite (clean/present/unshipping/unknown; foreign-host control; short-window rejection) |
| `scripts/followthroughs/ac12-telemetry-positive-control-7103.sh` | R3 — soak-gated AC12 probe with elapsed-time and invocation-count self-guards |
| `apps/web-platform/infra/web-zot-consumer-probe-canary.sh` (or an `ExecStartPre=` equivalent) | R3 — the credential-independent canary emit hoisted out of `doppler run` |
| `knowledge-base/engineering/architecture/decisions/ADR-158-delivery-is-not-activation-and-absence-is-not-evidence.md` | Phase 7 |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/hooks.json.tmpl` | R1 — per-hook `SOLEUR_DEPLOY_HOOK_ID` |
| `apps/web-platform/infra/ci-deploy.sh` | R1 — 4-field `SOLEUR_DEPLOY_INVOCATION`; `else` on the credential guard; `zot_gate_degraded_event no_credential_source` |
| `apps/web-platform/infra/ci-deploy.test.sh` | R1 — marker, credential-source, degraded-event, hook-identity assertions |
| `scripts/test-all.sh` | R5(a) — two runner registrations + the two new suites; relevance gate; loud skip; `SOLEUR_INCIDENT_SKIP`; correct the now-false coverage comment |
| `scripts/lint-orphan-test-suites.sh` | R5(a) — `REQUIRED_RUNNERS` call-shape tombstone |
| `apps/web-platform/infra/infra-config-install.sh` | R2 — **drop-in shape gate** (security precondition); correct both stale "18 destinations" comments to 19 |
| `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` | R2 — `DROPIN_TRY_RESTART` alias **and** its `deploy ALL=(root) NOPASSWD:` User_Spec |
| `apps/web-platform/infra/cloud-init.yml` | R2 — mirror both sudoers lines |
| `apps/web-platform/infra/infra-config-apply.sh` | R2 — move `sync`/`daemon-reload`/reconcile above the state write; `rm -f "$STATE_FILE"` at start; `schema_version`; `RESTART_MAP`; derived `changed` with unconditional writes + mtime preservation; `ActiveState`-first single predicate; activation grading; `restarts` array; guarded reads; `SYSTEMCTL` seam; `"restarts":[]` in the trap |
| `apps/web-platform/infra/infra-config-apply.test.sh` | R2 — predicate, inactive short-circuit, activation grading, ordering, guarded-read arms, stub-invoked, sudoers lockstep, shape-gate rejections, `changed:false` gate fixture |
| `apps/web-platform/infra/infra-config-gate.sh` | R2 — staged `restarts` assertion in `adjudicate_infra_config` only |
| `apps/web-platform/infra/server.tf` | R2 — `remote-exec` grep assertion for the new alias |
| `apps/web-platform/infra/web-zot-consumer-probe.service` | R3 — invoke the canary outside the `doppler run` wrapper |
| `apps/web-platform/infra/journald-config.test.sh` | R3 — the four positive-control wiring assertions |
| `.github/workflows/apply-deploy-pipeline-fix.yml` | R4/IaC — `::add-mask::`; `id: rendered_digest`; correct the errexit comment; add the `replace_target` dispatch input and route it into plan+apply; update the 000/502/503 recovery text |
| `.github/workflows/scheduled-followthrough-sweeper.yml` | R3 — confirm the three literal `BETTERSTACK_QUERY_*` names are exported (they are; no new wiring expected) |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | ADR — one sentence on the `hetzner` element naming the drop-in shape gate as the delivery↔activation boundary |
| `knowledge-base/project/plans/2026-08-01-fix-web1-credential-delivery-channel-dark-plan.md` | R3 — repoint the AC12/AC13 discoverability command |
| `knowledge-base/project/learnings/2026-08-01-i-shipped-a-gate-my-own-tests-could-not-see.md` | Phase 7 — append the missing Session Error |

**Not edited:** `apps/web-platform/infra/vector.toml` (all four identifiers verified already in the
Source-4 allowlist, both directions; token-shaped redaction is a filed follow-up);
`webhook.service`; `CHANGELOG.md`; the three `10-*-doppler-token.conf` drop-ins.

---

## Acceptance Criteria

### Pre-merge (PR)

**R1 — both halves tracked**

- **AC-R1-1** `hooks.json.tmpl` gives `deploy` and `deploy-peer` **distinct** `SOLEUR_DEPLOY_HOOK_ID`
  values, asserted by `jq` over the rendered template.
- **AC-R1-2** `SOLEUR_DEPLOY_INVOCATION` is emitted on every path the suite exercises, after the
  credential read and before `flock`; each of `cred_file=present|absent|unreadable` and
  `doppler_token=present|absent` is independently reachable.
- **AC-R1-3** **Half (b):** with no credential source, the suite observes a
  `zot_gate_degraded_event no_credential_source` call.
- **AC-R1-4** **Half (a) re-filed:** #7103 carries a comment with both timestamps, both `ZOT_GATE`
  lines, the `IMAGE_PULL_FAIL` line, F1–F7, and the marker's name as the naming mechanism. Verified by
  `gh issue view 7103 --comments`.
- **AC-R1-5** No emitted marker contains the fixture credential value on any path, including failure
  messages. Zero hits required.
- **AC-R1-6** `script_sha` equals the first 12 characters of the sha256 of the in-repo `ci-deploy.sh`
  — the property that makes H-R1-A decidable.
- **AC-R1-7** Exactly **one** marker reports the credential state: a grep for any second
  credential-source marker name returns 0.

**R5(a)**

- **AC-R5-1** `bash scripts/test-all.sh` reports the 0.1 baseline **+ 5**. A delta, never an absolute
  literal. The 5 are enumerated so the number is derived, not remembered: 2.1 registers TWO runners
  (`run-registered-suites.sh`, `.github/scripts/test/run-all.sh`), and 4.8, 5.6 and 6.3 each register
  one new suite. An earlier revision of this plan said **+ 4** while its own task list prescribed 5
  registrations — left uncorrected, the exit gate fails on a CORRECT tree, and the cheapest way to
  make a count-mismatch go green is to drop a registration, which is exactly the R5 defect this PR
  exists to close.
- **AC-R5-2** Deleting either runner's `run_suite` line reds `lint-orphan-test-suites.sh` and the
  message names the missing runner. Sandbox output in the PR body.
- **AC-R5-3** No surviving claim that this runner does not cover the infra directory:

  ```bash
  grep -cE '(does NOT cover|NOT covered|is NOT covered)[^|]*apps/web-platform/infra|apps/web-platform/infra[^|]*(does NOT cover|NOT covered)' scripts/test-all.sh
  ```

  = 0. **The originally-drafted form of this AC was vacuous and was corrected here rather than
  reported as passing.** It read `grep -c 'This runner does NOT cover apps/web-platform/infra/'`,
  and that literal never appeared on any single line: the comment it targeted wraps after "does
  NOT", so the command returned 0 against the UNMODIFIED file and would have certified Phase 2.4
  as done before a byte was changed. Measured before the edit: the literal form returned **0**,
  the shape above returned **5**. The AC must also stay scoped to the infra path — an unscoped
  `does NOT cover` matches a still-TRUE and unrelated claim about `scripts/*.test.sh` globs
  (`test-all.sh` line ~330), so the loose form fails on a correct tree. `cq-assert-anchor-not-bare-token`,
  and the plan-quoted-command rule: verify by running the LITERAL command, then fix the command
  when the literal is the thing that is broken.
- **AC-R5-4** An irrelevance skip prints the exact re-run command; `SOLEUR_INCIDENT_SKIP=1` prints the
  same, and the measured wall-clock is in the PR body.

**R2**

- **AC-R2-1** **Shape gate:** `infra-config-install.sh` rejects a drop-in payload containing
  `ExecStart=`, `User=`, `AmbientCapabilities=`, or `NoNewPrivileges=`, each with a named reason, and
  accepts one containing only blanks, comments, `[Service]`, `Environment=`, `EnvironmentFile=`. One
  arm per forbidden directive.
- **AC-R2-2** Both sudoers files contain the alias **and** `deploy ALL=(root) NOPASSWD:
  DROPIN_TRY_RESTART`; no `systemctl` grant in either file carries a wildcard; the verb is
  `try-restart` and the path is absolute. `server.tf`'s bootstrap `remote-exec` greps for the alias.
- **AC-R2-3** The sudoers argv and `infra-config-apply.sh`'s `sudo systemctl` argv are byte-equal per
  unit (anchored), across both sudoers files.
- **AC-R2-4** The staleness predicate fires when the dependency-set mtime exceeds
  `ExecMainStartTimestamp` and **self-disarms** on the next run; a second consecutive apply with
  nothing changed reports `action=skipped` for both units.
- **AC-R2-5** An inactive unit short-circuits to `unit_inactive` with **no** attempt. A stub unit that
  exits immediately after fork yields `noop_not_active` and **reds the gate** — proving the grading is
  on activation, not on `try-restart`'s exit code.
- **AC-R2-6** `vector.service` is ordered **last**, asserted on emitted marker order.
- **AC-R2-7** The state JSON carries `schema_version: 2` and a `restarts` array covering every
  `RESTART_MAP` unit in every outcome, each with `active`, `nrestarts`, and
  `exec_main_start_ts_before/after`. The `SYSTEMCTL` stub was invoked.
- **AC-R2-8** A `sudo` denial records `action=sudo_denied` with its `rc`, does **not** abort the apply,
  and **does** fail the gate.
- **AC-R2-9** `adjudicate_infra_config` passes against a fixture where all 19 files carry
  `changed:false`, `status:"ok"`, non-empty `sha256`, `files_written == files_total`. The steady-state
  regression pin.
- **AC-R2-10** The gate **warns and passes** on `schema_version < 2` / absent key, and **fails** on a
  malformed array or any of `rc != 0`, `active != active`,
  `action ∈ {noop_not_active, restart_did_not_advance, sudo_denied}`. Both arms against fixtures.
  Asserted to live in `adjudicate_infra_config`, **not** in `infra_config_count_invariant`.
- **AC-R2-11** A missing dest, an unreadable dest, and an unparseable `systemctl show` each leave
  `files_written == files_total` and still reach the post-write command block — the #4804
  mid-loop-abort pin.
- **AC-R2-12** The reconciliation runs **after** `daemon-reload` and **before** the state write
  (source-order check anchored on the three constructs), and `rm -f "$STATE_FILE"` runs at handler
  start.
- **AC-R2-13** The credential dest is installed on **every** apply — no code path skips a `FILE_MAP`
  write. Asserted by a fixture whose dest content is identical and whose mode has drifted to `644`,
  requiring re-install to `640 root:deploy`.

**R3**

- **AC-R3-1** The helper returns four distinct exit codes; `unshipping` and `unknown` **never** return
  0. Asserted across (absence 0/>0) × (control 0/≥1) plus a stub exiting 3 with empty stdout.
- **AC-R3-2** A stubbed response containing only a **foreign-host** canary returns `unshipping`, not
  `clean` — the host-scoping pin.
- **AC-R3-3** A `--since` shorter than 1 h is rejected with a named error.
- **AC-R3-4** `journald-config.test.sh` carries the four wiring assertions and reds when any one link
  breaks, **including** re-burying the canary emit inside the `doppler run` wrapper.
- **AC-R3-5** The follow-through directive is on the **dedicated soak issue**, not #7103, carries
  three **literal** secret names and a **concrete** `earliest` date, and the probe exits 1 (not 2 or
  3) on `unshipping`/`unknown`, exits 1 when <1 h has elapsed since the apply's `start_ts`, and exits
  1 when fewer than 3 `SOLEUR_DEPLOY_INVOCATION` rows are in the window.

**R4**

- **AC-R4-1** The step contains `^\s*id: rendered_digest$` **and** an `::add-mask::` of `$b64` emitted
  before any branch.
- **AC-R4-2** `bash scripts/digest-oracle-guard.test.sh` exits 0, meets `MIN_ASSERTS`, and names all
  three residual cases plus the three regression arms.
- **AC-R4-3** Reverting `nonsensitive(` reds the `(sensitive value)` case; deleting the
  `grep -q '^DOPPLER_TOKEN='` gate reds the empty-digest arm; injecting a bare failing command reds
  the errexit arm. All three demonstrated in the PR body — a harness that cannot fail is not a
  harness.
- **AC-R4-4** The harness runs under `env -i`; `command -v doppler` and `command -v terraform` both
  resolve inside the stub dir; the real binaries were not invoked; `GITHUB_ENV` is a per-arm tempfile
  whose final content is empty or exactly one `INFRA_CONFIG_RENDERED_SHA__…=<64hex>` line.
- **AC-R4-5** The suite exits 2 under `GITHUB_EVENT_NAME=pull_request_target`.
- **AC-R4-6** No harness output on any arm contains the fixture payload, `$b64`, or decoded bytes.

**R5(b)**

- **AC-R5b-1** All 7 arms reported by name, control green, exit 0.
- **AC-R5b-2** M1 (delete the step, keep the header comment) reds the drift suite and the battery
  asserts the message names W1/W3/W4/W5.
- **AC-R5b-3** M4 (repoint one caller, spare `uses:`, total unchanged) reds via W7.
- **AC-R5b-4** `git status --porcelain` is empty after a full run.

**Cross-cutting**

- **AC-X-1** `bash scripts/test-all.sh` green at baseline + 5 — the gate's own invocation, on the
  **final** tree. Expected output includes the nested runners' counts (`run-registered-suites.sh`
  0 RED; `run-all.sh` RAN ≥ 10). Also the re-verification of Phase 1 under the folded-in suite.
- **AC-X-2** `actionlint` on the two edited workflows; `shellcheck` on every created/edited `.sh`.
  Zero new findings. (`actionlint` is **not** run against `.github/actions/*/action.yml`.)
- **AC-X-3** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` — byte count
  **unchanged**; no new AGENTS rule ships here.
- **AC-X-4** Every `knowledge-base/` path cited resolves (excluding files this PR creates).
- **AC-X-5** The PR body uses `Ref #7103`, **not** `Closes #7103` — the AC12 soak is post-apply, and
  #7103 still carries B1–B7 plus R1's half (a).
- **AC-X-6** `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass after the
  `model.c4` description edit.

### Post-merge (automated — no operator-run step)

- **AC-PM-1** `apply-deploy-pipeline-fix.yml` fires on merge and concludes success. The `infra-config`
  leg reports `schema_version: 2` and a `restarts` array in which `vector.service` shows
  `action=restarted reason=stale_config active=active` — the one-time backlog heal. Machine-graded by
  `adjudicate_infra_config`, not by a human reading the payload.
- **AC-PM-2** In that array, `vector.service`'s `exec_main_start_ts_after` is greater than
  `exec_main_start_ts_before` **and** greater than the apply's `start_ts`, and `active` is `active` —
  read via `/hooks/infra-config-status`, never SSH.
- **AC-PM-3** The next `ci-deploy` invocation emits `SOLEUR_DEPLOY_INVOCATION` with a `script_sha`
  matching the merge commit and `doppler_token=present`. **This is the reading that grades H-R1-A and
  H-R1-B** — folded into the follow-through probe and recorded on #7103 under the half-(a) entry.
- **AC-PM-4** **AC12 re-verified through a live channel.** The helper returns `clean` for
  `Doppler Error: Invalid Auth token` on host `soleur-web-platform` over a ≥1 h window starting
  strictly after the apply, with ≥3 `SOLEUR_DEPLOY_INVOCATION` rows in the same window. Enrolled on
  the dedicated soak issue.
- **AC-PM-5** **AC13's negative half.** Across the next 3 `ci-deploy` invocations the host emits
  neither `ZOT_GATE: … dark, pre-provisioning` (either form) nor
  `PRELUDE: GHCR_READ_{USER,TOKEN} not both present`, asserted through the same helper so silence
  cannot satisfy it. Same probe.

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **The shape gate, the handler, and the sudoers all ride the handler-bootstrap leg** over the CF-Tunnel SSH bridge. If `ci_ssh` is dead at merge time, Phase 3 lands in the repo and never reaches the host. | ADR-154's transport probe is the **final** bridge step, so a dead credential fails early with a named reason (0.5 asserts it is still final). 3.8's warn-on-absent arm means a stale handler does **not** red the apply and does not skip the `if: success()` activation step. <!-- lint-infra-ignore start: negated mention — the remedy is the in-CI dispatch; the operator step is what it replaces. Markers are inline so the table row is not split. -->The remedy is now an in-CI `replace_target` dispatch input, not an operator-local `terraform apply`.<!-- lint-infra-ignore end --> |
| 2 | **The grant activates unvalidated unit configuration** — a `deploy` → root persistence chain. | 3.1 ships the drop-in shape gate **before** 3.2, with a per-directive rejection test (AC-R2-1). The C4 access row records the real delta rather than claiming none. |
| 3 | **Public disclosure of the prd Doppler token via the Actions log.** | Three layers: `::add-mask::` in the step (5.1); `env -i` hermetic harness that cannot reach real `doppler` (5.3); a no-interpolation assertion over the harness's own output (5.5 / AC-R4-6). Plus a `pull_request_target` refusal, since the harness executes PR-head code. |
| 4 | **New fallible reads abort the write loop under `set -euo pipefail`**, freezing delivery (#4804 class). | 3.6 requires the file's existing guarded idiom for every new read, with per-file reason enums; AC-R2-11 pins all three failure shapes. |
| 5 | **A stale state frame passes the gate**, certifying a previous apply's `restarts`. | 3.3 adds `rm -f "$STATE_FILE"` at handler start so an unfinished apply reads `no_prior_apply`. |
| 6 | **`try-restart` reports success without activation** (fork-success on `Type=simple`; no-op-with-0 on a failed unit). | 3.5 grades on `is-active` + timestamp advancement; `noop_not_active` and `restart_did_not_advance` are distinct gate-failing enums; AC-R2-5 pins it with a stub that dies after fork. |
| 7 | **A credential-keyed restart makes a stale-token push activating** — `server.tf` records that an out-of-band rotation leaves `prd_terraform` holding a stale token the apply re-pushes. Today inert; after Phase 3, vector re-execs onto an invalid credential. | The gate fails on `active != active`, read over HTTPS — the one transport that survives a dead vector. `try-restart` + `vector` last bounds the window. |
| 8 | **Writes going conditional would drop the per-apply DAC re-assertion** on the credential. | 3.4 keeps writes unconditional; `changed` is derived and used only by the predicate; mtime preserved on identical content; AC-R2-13 pins re-install on mode drift. |
| 9 | **The positive control is credential-gated and host-blind**, so `clean` can be false. | 4.3 hoists the canary out of `doppler run`; 4.2 reads it with an explicit `host_name` SQL predicate; AC-R3-2 pins the foreign-host case; 4.5's fourth assertion stops the hoist regressing. |
| 10 | **The soak directive auto-closes its host issue on PASS.** | 4.7 puts it on a dedicated soak issue with literal secret names, a concrete `earliest`, an elapsed-time self-guard, an invocation-count requirement, and `unshipping`/`unknown` → exit 1. |
| 11 | **Phase 2 lands minutes on the infra hotfix path.** | 2.3's named `SOLEUR_INCIDENT_SKIP` bypass with the loud-skip contract, and the 0.2 wall-clock recorded in the PR body. |
| 12 | **Phase 2 surfaces pre-existing red** that `test-all.sh` was hiding. | 0.2 measures before the fold-in; a pre-existing red is triaged under `wg-when-tests-fail-and-are-confirmed-pre`. |
| 13 | **`python3`+`yaml` unavailable on the required runner.** | 0.4 measures first; two sibling suites in the same check already depend on it; documented fallback is a path-filtered workflow. |
| 14 | **The `restarts` array changes the status response shape.** | Additive, behind `schema_version`. 0.9 enumerates every consumer before the change. |
| 15 | **`cloud-init.yml` edits do not reach web-1** (`ignore_changes = [user_data]`). | Stated in §Infrastructure. The live grant arrives via the bootstrap leg; AC-PM-1/2 verify the live path, not the mirror. |
| 16 | **ADR-158's ordinal is claimed by a sibling PR.** | Provisional; `/ship`'s collision gate re-verifies after every sync; on renumber sweep plan + `tasks.md` + every AC naming it. |
| 17 | **Scope.** Seven phases across infra, CI, security, and knowledge-base. | The items are coupled: 3.1 is a precondition of 3.2, R2 gates R3, R5's lesson decides R4's placement, R5(a) makes Phase 3's green trustworthy. Splitting would ship R3's verification before R2's mechanism — the ordering the coordinator ruled invalid — or the grant before the gate. |

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **R2 (a): a `restart-unit` webhook hook** | Remote-triggerable primitive on the unreplaceable host; decoupled from the event requiring it; falsifies the `tunnel -> hetzner` C4 description. Retained as fallback. |
| **R2 (c): accept; vector refreshes only on host recreate** | Telemetry ages out silently; R3 gets no live channel; half-implements the drop-in's own stated invariant. |
| **R2 (d): reconcile inside `infra-config-install.sh`** | Zero new alias, zero `cloud-init.yml` edit, one fewer file on the SSH leg — genuinely attractive. Rejected because the installer sits behind a **bare-command** grant `deploy` may invoke with arbitrary arguments, so a restart capability there widens the boundary from *write these dests* to *write these dests and restart units*. Per-file and stateless, while the decision is per-unit. |
| **R2: a `systemd.path` unit watching the drop-in directory** | A new always-on unit on the host whose failure modes are the subject here, firing on *write* not *change*. |
| **R2: content-conditional `FILE_MAP` writes** | Drops the per-apply re-assertion of `640 root:deploy`; a DAC-drifted dest would match on content, be skipped, and report `ok`. |
| **R4: `apps/web-platform/infra/` + the advisory `deploy-script-tests`** | The strongest precedent but the wrong fit — that precedent exists because the suite needed terraform + apt on the critical path. A regression guard in an advisory runner reproduces the defect R5 exists to fix. |
| **R4: a new standalone path-filtered workflow** | Viable, retained as the 0.4 fallback; rejected as default because it creates a fourth shell-test registration surface. |
| **R4: a `PATH`-prefix harness (the sibling precedent)** | Leaves the real `doppler`/`terraform` reachable and the ambient environment visible. `env -i` instead. |
| **R5(a): fold the 87 infra suites in individually** | A third hand-maintained list; destroys the derive-from-workflow property that makes the runner trustworthy. |
| **R5(a): a warn-only boundary assertion instead of invocation** | The residual asks for invocation; a warning is what the current comment already is. |
| **R3: a second telemetry canary unit** | The emitter exists, is allowlisted, and is rate-limited. Its two defects (credential-gated, host-blind) are fixed in place; the missing half was always the consumer. |
| **R3: fold the verdict into `betterstack-query.sh`** | Its exit vocabulary (`3`, `64`, curl's codes) collides with `0/1/2/3`, and its header promises verbatim SQL passthrough with one output contract. |
| **R3: `--grep` for the host discriminator** | Repeated `--grep` terms are OR-combined, so a foreign host's canary would satisfy the control. Raw-SQL `host_name` predicate instead. |
| **R1: convert the fail-open zot gate to a terminal abort** | That is #7103 **B1**, and a new abort path would break the #6090 baked-cred cold-boot route. |
| **R1: a separate `SOLEUR_DEPLOY_CRED_SOURCE` marker** | A second emission of one fact, in the PR whose ADR forbids exactly that. |
| **Token-shaped redaction in `vector.toml`'s PII scrub** | Correct and needed — the scrub genuinely has no Doppler/GitHub token pattern — but it is a change to the shared telemetry pipeline needing its own pins in `vector-pii-scrub.test.sh`. **Filed as a follow-up on #7103** rather than smuggled into a seven-phase PR; the Encryption Posture now states the real control for *this* plan's markers instead of over-claiming the scrub. |

---

## Sharp Edges

- **`infra-config-install.sh` validates content only for `/etc/default/*`.** The three
  `*.service.d/*.conf` dests get none, `vector.service` runs `User=deploy`, and `webhook.service`
  omits `NoNewPrivileges`. Any change that adds a root restart of those units completes a
  `deploy` → root chain. The shape gate is the boundary; it ships first.
- **This repo is PUBLIC and the digest step's `$b64` is unmasked.** GitHub's masker knows only the
  registered literal, never a base64 re-encoding. Never add `set -x` or an unguarded `echo` there.
- **GitHub runs a bare `run:` as `bash -e {0}`.** Omitting `set -e` does not disable errexit. The
  digest step's comment claiming otherwise is wrong and is corrected in 5.2.
- **`infra-config-apply.sh` seals its state JSON — and disarms its EXIT trap — before `daemon-reload`.**
  Anything appended after the write block is invisible to the status hook, and any failure there exits
  non-zero while the payload still reads `exit_code:0`.
- **The state file is never invalidated at run start**, so an overrunning apply serves the *previous*
  frame — and on a handler-only apply no payload byte changes, so that stale frame passes both
  invariants.
- **A `Cmnd_Alias` without a `User_Spec` line grants nothing**, and sudoers argument matching is exact
  — so argv drift between the grant and the caller is a *silent permanent no-op*, the #5934 shape.
- **`try-restart` exits 0 on a failed unit (no-op) and on a `Type=simple` fork.** Its exit code is not
  evidence of activation. Grade on `is-active` + `ExecMainStartTimestamp` advancement.
- **`systemctl show -p ExecMainStartTimestamp` is EMPTY for an inactive unit.** Treating empty as
  "unparseable ⇒ stale" builds a loop that never self-disarms while reporting success.
- `DropInPaths` is refreshed by `daemon-reload` and proves **nothing** about whether the running
  process loaded the drop-in.
- **`vector.toml` excludes `vector.service` from its own sources.** A vector that dies reports nothing
  anywhere; the only signals are the state JSON's `active` field and the absence of
  `SOLEUR_PROBE_CANARY` at the sink.
- **`_canary()` runs inside `doppler run`** — the control is gated behind the credential whose failure
  it certifies. And **`betterstack-query.sh` has no `--host` flag** while `--grep` terms are
  OR-combined, so a foreign host's canary can satisfy a host-scoped claim.
- **`sweep-followthroughs.sh` closes the issue on PASS**, comments TRANSIENT on any exit other than
  0/1, and `iso_to_epoch` returns `0` on an unparseable `earliest` — so a placeholder date silently
  removes the soak gate.
- **`run-registered-suites.sh --list` prints a header line**, so `| wc -l` returns 88, not 87.
- `actionlint` validates **workflows** only; against a composite `action.yml` it emits spurious
  "section missing" errors.
- The residual's R1 remedy option (a) — "give it `ZOT_REGISTRY_URL`" — has **no invoker-side site**.
- R5(b)'s re-anchoring is **already done** (#7133). The missing artifact is the battery that keeps it
  done.
- `.github/scripts/test/run-all.sh` sits at exactly its `MIN_SUITES=10` floor.
- `infra-config-install.sh` says "18 allowlisted destinations" in **two** places while its table holds
  19.
- AC12/AC13 and Phase 4b live in the **2026-08-01** plan; the 2026-07-30 plan's were deleted during
  its own review.
