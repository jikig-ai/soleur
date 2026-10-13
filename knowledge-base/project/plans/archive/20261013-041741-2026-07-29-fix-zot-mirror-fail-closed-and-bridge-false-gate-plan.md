---
title: "fix(infra): make the zot mirror fail-closed, and stop the pipeline asserting a dead GHCR fallback"
date: 2026-07-29
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-zot-mirror-fail-closed
pr: 7071
plan_version: 2
---

# fix(infra): make the zot mirror fail-closed, and stop the pipeline asserting a dead GHCR fallback

> **v2 — rewritten, not patched.** v1 was reviewed by 7 independent reviewers (repo-research,
> learnings, CTO, CPO, a strong-model advisor, then the escalated 5-agent panel). They returned
> **5 P0s**, three of which invalidated v1's own design or premises. v1's incremental patching had
> itself produced measurable drift (an AC encoding a design the FR forbade, an AC naming a
> discriminator no FR defined, a count stated three different ways) — the fingerprint of appending
> rather than integrating. This is an integrated rewrite; it is ~40% shorter than v1.
>
> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).**

## Overview

On 2026-07-29 the web-platform release for **v0.244.1** built, pushed to GHCR, and published green.
The deploy then died `image_pull_failed` and production sat undeployable ~5h.

The release was green because the CI zot-mirror step is warn-only by design — a correct decision
*when GHCR was a working break-glass fallback*. **That premise is now false**, so the mirror must
fail-closed.

Three deliverables:

- **A** — the mirror becomes release-blocking, via a positive post-copy assertion, **and the deploy
  is actually gated on it** (v1 got this wrong; see P0-A).
- **B** — stop the pipeline and its runbooks asserting a GHCR fallback that no longer exists, and
  close the token-drift detector's coverage gap. **No Terraform, no Cloudflare write, no Doppler
  write.**
- **C** — log the zot-pull stderr that is currently discarded.

## Premise Validation

### Confirmed

| Premise | Evidence |
|---|---|
| Mirror is warn-only, emitted `rc=bridge` | `degraded()` → `mirror_status=degraded`, `exit 0`, `continue-on-error: true`. Run **30468080168** reproduces the quoted annotation verbatim. |
| **GHCR is dead** | `GHCR_READ_TOKEN` is a 40-char `ghp_` classic PAT. `GET api.github.com/user` → **401**. Registry pull-token mint → **403 `{"errors":[{"code":"DENIED"}]}`**. `GHCR_MINTER_DISABLED=true`. |
| Deploy failed `image_pull_failed` | Job 90634334826: `ci-deploy.sh exited 1 (reason=image_pull_failed, tag=v0.244.1)`. |
| `$perr` is discarded on the zot arm | Captured at `perr="$(mktemp` (`ci-deploy.sh:1551`); the zot-failure branch at `:1589` logs only the bare `IMAGE_PULL: zot pull failed for …` line. |
| Host verify is **warn**, not enforce | `ci-deploy.sh:54` `readonly IMAGE_VERIFY_MODE="${IMAGE_VERIFY_MODE:-warn}"`; two tests assert the default stays `warn`. So an unsigned-but-present copy deploys **today**. |

### P0-A — RETRACTED: "a failed `release` job blocks deploy" was FALSE

v1 listed this as *Confirmed*, citing `deploy: needs: [release, migrate, …]`. **That is not the
blocking mechanism.** Measured: `needs.release.result` appears **0 times** in
`web-platform-release.yml`. The `deploy` job's condition leads with `always() &&`, which discards
GitHub's implicit skip-on-failed-`needs`, and then gates on
`needs.release.outputs.docker_pushed == 'true'` — an output written by `Set docker_pushed output`
(`if: steps.docker_build.outcome == 'success'`), **ten steps before** where the new assertion sits.
`migrate` is the same shape (`always() && needs.release.outputs.version != ''`).

The tell is inside the same expression: `await-ci` and `verify-doppler-secrets` are gated on
`.result`; `release` is gated only on an output.

So whether a blocked release stops the deploy rests on an undocumented GitHub semantic v1 never
named — whether a reusable workflow's `workflow_call.outputs` propagate when the called job
concludes `failure`. If they do, the deploy **runs**: migrations apply, the webhook fires,
`ci-deploy.sh` misses in zot, the revoked PAT denies GHCR, and prod is left on **new schema + old
code** with neither a published release nor a deploy — *strictly worse than the v0.244.1 baseline*.

**This is exactly the class of error this plan exists to fix: I read `needs:` and asserted a
mechanism without reading the `if:`.** Fixed deterministically by FR-A5, independent of which
semantic is true.

### Falsified — Deliverable B is re-scoped

**F1. The `HTTP 200` + empty body from `https://registry.soleur.ai/v2/` is CORRECT BEHAVIOUR.** The
ingress for that hostname is `service: tcp://10.0.1.30:5000` — **TCP-mode**, consumable only via
`cloudflared access tcp`. A plain HTTPS GET is not a WebSocket upgrade for that stream, so nothing
is proxied. The repo already documents this (`cf-tunnel-registry-bridge/action.yml` header:
*"`tcp://`, NOT `http://`: `cloudflared access tcp` bridges a raw TCP stream over a WebSocket"*).
Reproduced: with CF Access → `200`, `size=0`, **no `content-type` at all**; without → `403`.

**F2. The private-net route is present and working.** Live tunnel config shows the ingress.
Verified end-to-end: `cloudflared access tcp --hostname registry.soleur.ai --url 127.0.0.1:15000`,
then `GET /v2/` → **HTTP 401 from zot itself** (`Www-Authenticate: Basic realm=…`, zot-shaped JSON).
That is the origin answering. *Limitation: this ran from the operator's laptop, not a runner — it
proves the path is capable, not that a runner will succeed. AC-P1 defers the faithful test.*

**F3. The real cause was a CF Access service-token rotation that did not propagate.** Bridge log,
recovered from the teardown step of run 30468080168:

```
2026-07-29T16:01:14Z ERR failed to connect to origin error="websocket: bad handshake" originURL=https://registry.soleur.ai
```

`websocket: bad handshake` is the *client* failing at the edge — CF Access refused the upgrade. A
missing origin route would instead handshake successfully and fail origin-side.

| Time (UTC) | Event |
|---|---|
| 15:53:26 | Run 30468080168 starts (release for #7065, *"make the CF Access service tokens rotatable via Terraform"*). |
| **15:57:52** | `github-actions-registry-push` service token **created** (live CF API `created_at == updated_at`) — i.e. replaced. |
| 16:01:14 | Bridge runs with the **stale** Doppler value → `websocket: bad handshake` ×4. |
| 16:01:14 | `nc -z 127.0.0.1 5000` **passes anyway** → bridge step `__run_2` reports success. |
| 16:01:15 | `docker login` through the dead stream → `connection reset by peer` → `__run_3` fails. |
| — | `degraded "bridge"` → warn-only. Release **publishes v0.244.1**. |
| — | Deploy: zot lacks v0.244.1; GHCR fallback → revoked PAT → `image_pull_failed`. |

Mechanism: every `doppler_secret` carrying a token declares `lifecycle { ignore_changes = [value] }`,
so Terraform recreated the token but could never propagate the new secret. **The operator reached the
same conclusion hours earlier** — commit `5eba7ec07` (#7067) names `REGISTRY_PUSH_ACCESS_TOKEN_*` as
*"`prd` root stale after a Terraform replace"*. Doppler holds a working token now (my probe minted a
valid `CF_Authorization`), so this staleness is already remediated.

**Net: Deliverable B has no infrastructure defect to fix.** It is a detection-and-truthfulness fix.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Response |
|---|---|---|
| "fix the CF-tunnel bridge that silently mirrored nothing" | Bridge is healthy; one failure from a stale token, since remediated. | Re-scope B to truthfulness + detector coverage. No infra change. |
| "empty 200 ⇒ Cloudflare answering without a working origin" | Expected for a `tcp://` ingress (F1). | Record the probe trap so it is not repeated. |
| "the connector may lack a private-net route" | False (F2). `model.c4:428` already records this #6416 mode as **closed** (web-2 retired 2026-07-17, #6538). | Delete the claim; replace with the measured cause class. |
| "If the fix is Terraform, run fmt/validate/plan only" | No Terraform needed. | IaC gate skipped with reason. |
| ADR-096 permits warn-only | True, justified on GHCR **redundancy**: *"a mirror failure degrades zot redundancy, never the release/build verdict."* GHCR is dead ⇒ zot is not redundant. | Fail-closed requires an **ADR-096 amendment** — an in-PR deliverable. |
| A separate `zot_verify` step (v1 design) | **Breaks on the incident it targets.** On a bridge failure `degraded()` exits *before* `install_crane`, so a sibling step finds no `crane`; `docker login` never ran either, so `crane` would 401. v1's taxonomy would have reported *"CI regression — not a registry problem"*. | **Assertion moves INSIDE `zot_mirror`.** Converged by 3 reviewers. |
| `crane digest` is "established precedent (16 sites)" | **False** — measured **3** repo-wide, and `apply-web-platform-infra.yml` records `crane digest` as a *deliberately rejected* deviation in favour of `docker buildx imagetools inspect`. | Drop the GHCR-side `crane` read entirely (FR-A2). My own unverified count in an evidence-first plan. |
| "Keep the mirror harness green" | It extracts the `run:` block by literal step-*name* match and asserts on `mirror_status` values. | Cost of the honest fix is **two string literals** (`"0 degraded warn 3"`→`"1 …"`, `"0 degraded warn 0"`→`"1 …"`). Freezing them would be a test protecting the bug. |

## Hypotheses

L3 → L7 per `hr-ssh-diagnosis-verify-firewall`; routing verified **before** any auth conclusion.

1. **L3 origin route missing** — **REFUTED** (F2).
2. **L3 DNS/edge** — **HEALTHY** (proxied CNAME to `<tunnel>.cfargotunnel.com`; edge answered every probe).
3. **L3 connector homogeneity** — **REFUTED** for this incident (single web host since #6538; `model.c4:428`; the tunnel's 4 connections are one cloudflared instance's 4 HA edge links).
4. **L7 empty-200 ⇒ broken origin** — **REFUTED** (F1, by design).
5. **L7 CF Access rejected a rotated service token** — **CONFIRMED** (F3), already remediated; the *detection* gap is what this plan closes.
6. **L7 zot down / disk-full** — **REFUTED** (zot served both hosts' v0.244.0 pulls that day and answered my probe).

## User-Brand Impact

- **If this lands broken, the user experiences:** a release reporting success while `app.soleur.ai`
  keeps serving the previous build — the v0.244.1 shape, ~5h silent. In the permissive direction
  there is no error at all, which is why it survived a full release cycle.
- **If this leaks, the user's data is exposed via:** the *blocked* remediation — **not by this PR,
  which moves no personal data.** The exposure is already live and independent of this change: the
  2026-07-27 laptop compromise
  (`knowledge-base/project/learnings/security-issues/2026-07-28-vscode-folderopen-task-rce-and-fleet-wide-key-rotation.md`)
  left the legacy Supabase `service_role` key valid and compromised. That key **bypasses RLS on every
  table**; the sharpest class is BYOK-encrypted customer API-key material (`server/byok.ts`) plus user
  PII. Disabling it requires migrating the browser client off the legacy anon key, which requires
  shipping an image — which, with GHCR dead, requires the mirror to land.
- **Brand-survival threshold:** `single-user incident`

**Threshold reasoning.** First-order, this change is `none`-to-`aggregate pattern`: its own failure
modes are release-pipeline availability. It clears `single-user incident` **transitively**, admissible
because `hr-weigh-every-decision-against-target-user-impact` is outcome-framed. The honest form:
**both** directions extend the same compromised-key window — fail-open silently, fail-closed by
delaying the migration — but blocked-and-loud is recoverable in minutes while the silent case ran ~5h
and spent its diagnostic budget on a misdiagnosis. `aggregate pattern` is wrong because aggregate
harms are trend-shaped; this is one named credential against named rows.

## Functional Requirements

### A — fail-closed, asserted inside the step that does the work

- **FR-A1 — make `zot_mirror` blocking.** Delete `continue-on-error: true` from `zot_mirror`; change
  `degraded()`'s `exit 0` to `exit 1`. Update the harness's two expected-rc literals. **No sibling
  step** — v1's separate `zot_verify` was justified by a tautology ("a step without
  `continue-on-error` cannot be the same step as one that has it"), which treated an editable line as
  immovable. It also *broke on the target incident* (see Reconciliation) and required a
  `degrade_stage` output contract, a duplicated `retry()`, a skip-condition proof, and an 8-way
  taxonomy — all of which dissolve here.
- **FR-A2 — positive post-copy assertion, one `crane` call.** Immediately **before**
  `echo "mirror_status=ok"`, assert that `crane digest "${ZOT}:v${VERSION}"` resolves **and equals
  `${DIGEST}`**; otherwise `degraded "verify" "<detail>"`. Both values are already in scope, and
  `${DIGEST}`'s addressability in zot is already proven by the adjacent
  `cosign sign --yes "${ZOT}@${DIGEST}"`. `${DIGEST}` — not GHCR's copy — is the authoritative
  statement of "the bits this release built".
  **Deliberately NO GHCR-side read:** it would put GHCR back on the release critical path of an ADR
  whose purpose is removing it (a GHCR outage is not a reason production cannot pull), it is the one
  prerequisite v1 never verified (`crane digest` against a private repo-linked package under the
  release token, adjacent to the ADR-088 arm-b denial), and `crane digest` against GHCR is a
  *rejected* in-repo deviation.
- **FR-A3 — `degraded()` emits a truthful reason.** Add `mirror_reason=<bridge|crane_install|copy_v|copy_sha|copy_latest|sign|verify>`
  to `$GITHUB_OUTPUT`, one label per call site. Load-bearing because `degraded()` currently writes
  **only** `mirror_status`, so the state "copy landed but `mirror_status != ok`" has at least two
  causes — and the plan's own analysis says the *copy-arm* case is the common one (`degraded()` is a
  first-failure abort; a failure on the `${COMMIT_SHA}` or `latest` arm kills the loop before
  `cosign sign` runs). v1 labelled that state `signing_failed` and prescribed *"likely a Sigstore
  outage: wait and re-run"* — **actively wrong for its own dominant cause**, and the same
  naming-an-unmeasured-cause defect this plan exists to fix (R6). Harness-safe: it stubs
  `$GITHUB_OUTPUT` and asserts on `mirror_status` values, which are unchanged.
- **FR-A4 — three truthful operator messages, not a taxonomy.** `degraded()` already takes a `$2`
  detail per call site. Give the three real classes a cause + remedy a non-technical operator can
  act on: **bridge** (stale CF Access token → run the drift detector, name
  `scripts/check-cloudflare-token-drift.sh`); **copy/verify** (zot did not receive the image → the
  `crane copy` + `cosign sign` backfill one-liner, then re-run); **sign** (copy landed at the correct
  digest, signature missing → re-sign, or wait if Sigstore is out). Every message must also state
  **nothing was half-shipped** — the release is an unpublished draft with no git tag and re-running is
  non-destructive — and name `apply-deploy-pipeline-fix.yml` as the pipeline-bypass escape hatch, so
  no remedy is a dead end.
- **FR-A5 — gate the deploy on the release's RESULT. (The change that makes A actually fail-closed —
  see P0-A.)** In `web-platform-release.yml`, add `needs.release.result == 'success'` to **both**
  `migrate` and `deploy`. Deterministic regardless of whether `workflow_call.outputs` propagate from
  a failed called job. Without this, FR-A1–A4 may protect nothing and can leave prod on new schema +
  old code.
- **FR-A6 — the failure has to reach a human.** Add `if: failure()` + `./.github/actions/notify-ops-email`
  to the **release** job *and* the **deploy** job. Today both notify steps gate on
  `create_release.released || idempotency.draft_exists` with **no status function**, so an implicit
  `success()` means **neither fires on a blocked release**; the only remaining signal is GitHub's
  failed-workflow email, routed to the triggering actor — possibly a GitHub App identity, i.e. nobody.
  `if: failure()` + `notify-ops-email` is the established repo idiom (7 workflows). Body carries the
  `mirror_reason` and the one-sentence remedy — never a checklist
  (`hr-ship-message-no-operator-checklist`). **Disclose two consumers:** this lands in the shared
  reusable workflow, so plugin releases via `version-bump-and-release.yml` also begin emailing ops.
- **FR-A7 — one comment block, four clauses.** At the assertion site record: (i) the **GHCR coupling**
  — this gate is correct only while GHCR is not a usable fallback, citing ADR-088 arm-b's *structural*
  finding (App installation tokens can `docker login` GHCR but are DENIED `docker pull` of private
  repo-linked packages), so the relaxation condition is testable rather than a matter of taste;
  (ii) the **CF Access coupling** — the bridge is now effectively release-blocking, making that
  service token a release-blocking credential whose propagation is deliberately only *detected*;
  (iii) the gate's **load-bearing sub-value = publish-ordering / version-space integrity** — a blocked
  release consumes no semver, materializes no git tag, publishes no notes; a deploy-side check cannot
  have that property (this, not availability, is why the gate lives here, and without it a future
  reader prunes it as redundant with `pull_image_with_fallback`); (iv) **outcome vs conclusion** —
  read `steps.zot_bridge.outcome`, never `conclusion`, which `continue-on-error` forces to `success`
  (#6416 bit this exact step once).
- **FR-A8 — state what the gate does NOT prove.** It asserts the manifest is in zot **and readable by
  the push credential over the tunnel**; it does **not** prove the host can pull. The host uses a
  different transport (private NIC, no tunnel, no CF Access) and a different credential
  (`ZOT_PULL_*`). Uncovered: private-net 10.0.1.10→10.0.1.30:5000 down; `ZOT_PULL_*` stale (the *same*
  rotation-staleness class, one credential over — and `zot_gate_and_login` fails open to dead GHCR);
  zot `accessControl` granting push-read but not pull-read. No cheap CI-side assertion closes this —
  the gap is on the other side of the network. `web-zot-consumer-probe.sh` is the correct
  non-redundant complement. This sentence must appear in FR-A7's comment **and** the ADR amendment,
  or the amendment records a stronger claim than the mechanism supports and a future reader retires
  the consumer probe.
- **FR-A9 — export the verdict for legibility.** Add `mirror_verified` to the `release` job's
  `outputs:`; the `deploy` job echoes it to `$GITHUB_STEP_SUMMARY` and `::warning::`s when not
  `true`. **Deliberately not** a blocking conjunct — that would defeat the override's only legitimate
  purpose. This lets `postmerge`/the operator digest distinguish a verified release from an
  override-published one.
- **FR-A10 — dispatch-only, reason-required override.** Three reviewers disagreed; the synthesis: an
  override buys **nothing** when the gate is right (an unmirrored image cannot be pulled, so
  overriding publishes a still-undeployable release) but is the difference between a 30-second unblock
  and *editing a workflow on `main` under incident pressure* when the gate **misfires**. So: available
  only via `workflow_dispatch`, inert without a non-empty reason, and when used emits a `::warning::`,
  records to the step summary, fires FR-A6, and files an `action-required` issue.
  **Implementation reality v1 missed:** `reusable-release.yml` is `workflow_call`-only and cannot read
  a caller's dispatch inputs — this requires a new input on **`web-platform-release.yml`** (absent
  from v1's file list) forwarded via `with:`, plus a *defaulted* `workflow_call` input so
  `version-bump-and-release.yml` is unaffected. Gate on `github.event_name == 'workflow_dispatch'`
  (precedent: `force_run`). **Drop v1's `environment:` required-reviewer clause** — `jobs.release` has
  no `environment:`, so it checked a gate that does not exist. Document that the override also
  bypasses `await-ci`, and that self-healing to the same version requires the **same `bump_type`**.
- **FR-A11 — record the orphan-draft leak.** A blocked release leaves an unpublished draft. The
  #4902 self-heal republishes it **only when a later run recomputes the identical tag**; a different
  bump type orphans it permanently, and even the same-bump path never rewrites the notes (so a
  republished draft carries the first PR's changelog). Record + file a tracking issue. No reaper.

### B — stop asserting a dead fallback; close the detector's gap

- **FR-B1 — truthfulness sweep, widened to the artifacts that matter.** v1 swept two grep patterns
  and reached the code and the C4 model but **missed the operator-facing runbook and the ADR's own
  escape hatch**. Correct all of:
  1. `reusable-release.yml` — the **whole** mirror step, not just `:782`: the step header
     (*"a mirror failure must NEVER red a successful release"*), the `::warning::` at `:747`
     (*"release UNAFFECTED (GHCR primary/break-glass)"*), the step summary at `:748`
     (*"release OK (GHCR primary)"*), `:738` (*"the host's atomic GHCR fallback covers it cleanly"*),
     `:743` (*"latency, not availability"*), `:713-716` (claims the Slack line reports a persistent
     miss — it does not fire on a blocked release), and `:782`'s two false claims (the refuted #6416
     route prediction, and *"the host's atomic GHCR fallback covers the pull"*).
  2. `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` — **the highest-consequence
     instance.** It instructs the operator during an outage to delete `ZOT_REGISTRY_URL` so hosts fall
     through to GHCR, reassuring them the *"fallback registry is always warm and current"*. A runbook
     is *instructions*, not a comment. Correct it and add the post-change recovery. Fold in the
     `tcp://` probe trap (a plain HTTPS GET to `registry.soleur.ai` returns an empty 200 **by design**
     and is not a health probe; the correct probe is `cloudflared access tcp` + `GET /v2/`, expect
     200/401) — a section here, not a new file.
  3. **ADR-096 itself** — §Cold-boot-dependency axis 1 (*"a zot outage degrades latency, not
     availability"*) and the **"Instant revert"** bullet (*"unset `ZOT_REGISTRY_URL` → all sites revert
     to GHCR-primary"*). The same dead escape hatch, restated in the normative record that R1b's
     reasoning cites.
  4. `knowledge-base/engineering/architecture/principles-register.md` (AP-016) — asserts the interim
     PAT exception is live and that the GHCR path "MUST recover on a `docker pull` auth-denial". The
     exception has **lapsed**. One dated clause.
  5. `ADR-088` — dated note on its "interim GHCR break-glass" phrasing.

  Sweep patterns must be widened beyond v1's set to include `falls (straight )?through`,
  `latency, not availability`, `Instant revert`, `GHCR-primary`, `release UNAFFECTED`,
  `release OK \(GHCR primary\)`. **Excluded deliberately:** the 2026-07-15 post-mortem — a
  point-in-time record, like `**/archive/**`.
- **FR-B2 — dump the bridge log at the failing step.** Today only the `nc -z` timeout path dumps
  `/tmp/cloudflared-registry.log`; the `docker login` path dumped nothing, and the four
  `websocket: bad handshake` lines survived only incidentally in the `if: always()` teardown, a step
  away from the error.
- **FR-B3 — fix the token-drift detector's coverage gap.** `scripts/check-cloudflare-token-drift.sh`
  has two independent defects: its enumeration is `grep -oE 'CF_API_TOKEN[A-Z0-9_]*'`, which
  **cannot match** `REGISTRY_PUSH_ACCESS_TOKEN_ID`/`_SECRET` — the first case its own header cites —
  and `verify_value()` uses `GET /client/v4/user/tokens/verify` with `Authorization: Bearer`, the
  **API-token** endpoint, wrong for a client-id/secret pair. Add an Access-service-token arm:
  present the pair as `CF-Access-Client-Id`/`-Secret` to the protected hostname, **200 → LIVE,
  403 → DEAD**. Keep enumeration Doppler-derived (gotcha #4): match
  `[A-Z0-9_]*ACCESS_TOKEN_(ID|SECRET)`, never a hardcoded list. The script claims coverage it does
  not have; this is a bug fix, not a feature.
- **FR-B4 — invoke the detector.** `grep -rln check-cloudflare-token-drift` returns **only the script
  itself**. Add it as a **step in `scheduled-terraform-drift.yml`** — not a new workflow: that file
  already runs twice daily, already sets `DOPPLER_CONFIG: prd_terraform` (exactly the detector's
  documented invocation), already carries `notify-ops-email` twice, and is the workflow that *causes*
  the drift. A new GHA `schedule:` would also be off-pattern — that same file's header states Inngest
  is the single scheduling substrate (ADR-033). **Also add the release-preflight arm** (required, not
  "and/or"): a scheduled detector can be hours stale relative to the release that trips over it; a
  preflight turns a blocked release into a correctly-diagnosed one before the build spends its
  minutes.

### C — stop discarding the pull error

- **FR-C1.** In `ci-deploy.sh`, the zot-failure branch (anchor: the
  `IMAGE_PULL: zot pull failed for` line, currently `:1589`) must log a bounded stderr tail using the
  shape `pull_failure_event` already uses — `tail -c 400 "$perr"` — with newlines collapsed so the
  `logger` record stays single-line and Vector-parseable. Anchor on content, not the line number
  (`cq-cite-content-anchor-not-line-number`).

## Implementation Phases

Dependency-directed: contract changes precede their consumers.

- **Phase 0 — preconditions (no writes).** Confirm the harness's two rc literals and that it matches
  on step *name*. Re-run the two premise probes (GHCR 401/403; the `cloudflared access tcp` → `/v2/`
  → 401 bridge check) and paste into the PR. Confirm `${DIGEST}` is addressable in zot post-copy (the
  adjacent `cosign sign "${ZOT}@${DIGEST}"` already proves it).
- **Phase 1 — FR-C1.** RED: extend `ci-deploy.test.sh` to assert the zot-arm line carries the reason.
  GREEN: implement.
- **Phase 2 — FR-A3 + FR-A4 + FR-B1(1) + FR-B2** (all inside the extracted `run:` block / the bridge
  action; contract change before its consumers).
- **Phase 3 — FR-A1 + FR-A2** (make it blocking + the assertion) + FR-A7's comment block.
- **Phase 4 — FR-A5 + FR-A6 + FR-A9 + FR-A10** (`web-platform-release.yml` and the release job).
- **Phase 5 — FR-B3 + FR-B4** (detector + wiring).
- **Phase 6 — FR-B1(2)–(5)** (runbook, ADR-096, AP-016, ADR-088) + the ADR-096 amendment + the three
  C4 description corrections. **Ordering constraint:** FR-B1(2) (the runbook) cannot be deferred to a
  later PR than FR-A — shipping the gate first leaves the runbook instructing a procedure that now
  fails.
- **Phase 7 — full-suite exit gate.** The mirror harness, `ci-deploy.test.sh`, `actionlint` on both
  workflows, `bash -c` on extracted `run:` snippets (never `bash -n` on the YAML).
- **Phase 8 — trackers** (see Deferred).

## Acceptance Criteria

Every AC is **presence-first** and uses `grep -F` with a guard that fails when the anchor is missing.
v1's absence-only ACs were uniformly vacuous — measured: AC1's awk returned empty on a file with no
such step, AC11's pattern returned **0** against code containing the string 6× (mid-pattern `$` is an
ERE anchor under this machine's ugrep 7.5.0), and AC19's target string is **line-wrapped** so its
absence grep passed on the unmodified runbook.

### Pre-merge

- **AC1.** `zot_mirror` no longer carries `continue-on-error`, and `degraded()` exits non-zero.
  `awk '/^      - name: Mirror image GHCR→zot/{f=1;seen=1;next} f&&/^      - name: /{f=0} f&&/^        continue-on-error:/{bad=1} END{if(!seen){print "ABSENT";exit 1} if(bad){print "FOUND";exit 1}}'`
  succeeds; and `grep -cF 'exit 1'` within the `degraded()` body is ≥1.
  **Amended at /work.** The drafted matcher was a bare `/continue-on-error/`, which sees
  COMMENTS. It reported FOUND against a step whose actual key count is **0**, because FR-A7's
  comment block necessarily *discusses* `continue-on-error` — clause (i) records that the step
  used to carry it, and clause (iv) explains that it is what forces `conclusion` to `success`.
  That discussion is the most valuable prose in the step and deleting it to satisfy a grep would
  be the tail wagging the dog. Anchored instead on the YAML key at its exact indent, which a
  comment line cannot produce (it starts with `#`). Third instance of
  `cq-assert-anchor-not-bare-token` in this PR's own ACs, after AC5 and AC10.
- **AC2.** The assertion exists **before** `mirror_status=ok`: `crane digest` appears in the step, and
  its line number is less than the `mirror_status=ok` line. It compares against `${DIGEST}` and makes
  **no** `crane digest ghcr.io/` call (`grep -cF 'crane digest ghcr.io/'` == 0).
- **AC3.** `degraded()` writes `mirror_reason=`, and the full label set is reachable: the seven
  values `bridge`, `crane_install`, `copy_v`, `copy_sha`, `copy_latest`, `sign`, `verify` each
  appear as a reason argument (the three `copy_*` via the `TAG_SPEC` loop's `"<tag>:<label>"`
  pairs). Harness cases T1/T4/T6/T7/T8 pin `bridge`, `copy_v`, `copy_sha` and `verify` behaviourally.
  **Amended at /work.** The drafted form counted the literal `mirror_reason=` and required ≥6,
  "one per call site" — which silently assumed the emit would be inlined at each call site. The
  implementation emits it ONCE inside `degraded()` and passes the label as a parameter, so the
  literal appears twice while all seven labels are reachable. The single-emitter shape is the
  better one (a per-site echo is six chances to forget one, and the label and the message would
  drift apart), so the AC was re-expressed as the property it was standing in for — the label SET
  — rather than the implementation shape it happened to describe.
- **AC4.** The three operator messages each name a cause, a remedy, the "unpublished draft — re-running
  is safe" line, and `apply-deploy-pipeline-fix.yml`. No message contains the token `Sigstore` on the
  copy-arm path.
- **AC5.** `grep -cE "^ +needs\.release\.result == 'success' &&" .github/workflows/web-platform-release.yml`
  == **2** — once in `migrate`, once in `deploy`. (Measured baseline for the bare token:
  **0**.)
  **Amended at /work.** As drafted this was `grep -cF 'needs.release.result' … == 2`, a
  bare-token count. The implementation carries a comment explaining *why* the conjunct is
  not redundant with `needs:` — the single most misreadable thing in this PR, and the
  misreading that caused P0-A — so the literal legitimately appears three times and the
  AC as written failed against a correct file. Anchoring on the conjunct's SYNTAX fixes it
  properly rather than by deleting the documentation: a comment line cannot match `^ +needs\.`
  (it starts with `#`), so the amended form still goes RED if either conjunct is removed,
  while no longer counting prose. This is `cq-assert-anchor-not-bare-token` applied to the
  plan's own AC; the same defect was caught once more in this PR at AC10.
- **AC6.** `if: failure()` + `notify-ops-email` present in both the release job and the `deploy` job.
- **AC7.** FR-A7's comment block contains all four clauses and FR-A8's "does not prove" sentence;
  assert on distinctive anchors (`ADR-088`, `publish-ordering`, `outcome`, `ZOT_PULL_`).
- **AC8.** `mirror_verified` appears in the `release` job `outputs:` (FR-A9).
- **AC9.** The override input exists on `web-platform-release.yml`, is forwarded via `with:`, has a
  defaulted `workflow_call` counterpart, is gated on `github.event_name == 'workflow_dispatch'`, and
  is inert without a non-empty reason. `grep -cF 'environment:' .github/workflows/reusable-release.yml`
  == 0 confirms v1's dropped clause is not reintroduced.
- **AC10 — truthfulness, wrap-immune and scoped.** For `reusable-release.yml`, each of these returns
  **0**: `lack a private-net route`, `release UNAFFECTED`, `release OK (GHCR primary)`,
  `latency, not availability`, `atomic GHCR fallback covers`. Each was verified **present** on
  `origin/main` first, so the AC is non-vacuous. For the runbook and ADR-096, use
  `tr '\n' ' ' < FILE | grep -c '<phrase with [[:space:]]* between words>'` == 0 — the strings wrap.
  Greps are **scoped to the target files**; this plan and the learning legitimately quote the old text.
- **AC11.** The corrected artifacts assert **presence**: the runbook contains the post-change recovery
  and a dated correction; ADR-096's amendment exists; AP-016 carries a dated clause.
- **AC12.** `grep -aFc 'tail -c 400 "$perr"' apps/web-platform/infra/ci-deploy.sh` == **7**
  (measured baseline **6**). `-F` is mandatory: without it the pattern returns **0** on code
  containing it 6×. Additionally the `IMAGE_PULL: zot pull failed for` line must now carry `reason=`.
- **AC13.** `ci-deploy.test.sh` has a passing case asserting the zot-arm reason.
- **AC14.** Detector: enumerates `*ACCESS_TOKEN_(ID|SECRET)` and verifies via
  `CF-Access-Client-Id`/`-Secret` (200→LIVE, 403→DEAD), with a unit test covering both verdicts using
  synthesized fixtures (`cq-test-fixtures-synthesized-only`).
- **AC15.** `grep -rln 'check-cloudflare-token-drift' .github/workflows/` returns ≥1 **inside a `run:`
  step** (baseline: 0 files under `.github`), and the release-preflight arm exists.
- **AC16.** Mirror harness passes, and no PRE-EXISTING case (T1–T5) is weakened: each still
  asserts the same property it asserted before, with only the two expected-rc literals
  changed (`"0 degraded warn 3"`→`"1 …"`, `"0 degraded warn 0"`→`"1 …"`).
  **Amended at /work.** As drafted this was a mechanical "the diff contains no line matching
  `^[+-].*(assert_eq|\[\[ )` other than the two literals". That encoded the right *intent* —
  do not rewrite the harness to fit the change, which would be a test protecting the bug —
  but it also forbade the coverage the plan's own Test Scenarios 2/3/4/6 require, since the
  post-copy assertion did not exist before and no existing case can observe it. Enforcing it
  literally would have shipped a new fail-closed gate with zero tests. New cases T6–T10 were
  therefore added; T1–T5 keep their assertions, and the three literals that did change
  (`warn`→`loud` for the annotation-severity field, plus the two rc values) are the change
  itself. Non-vacuity is established by mutation instead of by diff shape, which is the
  stronger check the diff-shape rule was standing in for: baseline 13/13 green, and five
  mutants — mismatch branch disabled, unresolvable branch disabled, `degraded()` exiting 0,
  the override ignoring its reason, and the assertion removed entirely — each go RED. That
  battery earned its keep: its first run showed T7 surviving the disabled-unresolvable-branch
  mutant, i.e. genuinely vacuous, and T7 was strengthened to pin the message.
- **AC17.** `actionlint` clean on `reusable-release.yml` **and** `web-platform-release.yml`.
- **AC18.** Every `knowledge-base/` path cited in this plan resolves
  (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.(md|c4)'` → all exist).

### Post-merge (operator) — tracked, not remembered

- **AC-P1.** On the first release after merge, the assertion passes and the log records the digest
  match. **Automation not feasible pre-merge** — the faithful test of a CI-side bridge is a real
  release, a production mutation out of scope for an unattended run (F2's limitation). Per
  `wg-block-pr-ready-on-undeferred-operator-steps` this MUST become a tracked follow-through issue
  before PR-ready.

## Observability

```yaml
liveness_signal:
  what: "zot_mirror step outcome per web-platform release: digest match, or mirror_reason naming the failing stage"
  cadence: "every web-platform release (push to main touching apps/web-platform/**)"
  alert_target: "if: failure() -> notify-ops-email to ops@jikigai.com (release AND deploy jobs); ::error:: + step summary on the run"
  configured_in: ".github/workflows/reusable-release.yml (zot_mirror); .github/workflows/web-platform-release.yml (migrate/deploy needs.release.result, deploy notify)"
error_reporting:
  destination: "GitHub Actions annotation + $GITHUB_STEP_SUMMARY + notify-ops-email; host-side pull errors to journald -> Vector -> Better Stack"
  fail_loud: true
failure_modes:
  - mode: "bridge unreachable from the runner (stale CF Access service token after a rotation) — the v0.244.1 shape"
    detection: "mirror_reason=bridge; cloudflared log dumped at the failing step (FR-B2)"
    alert_route: "release job fails -> notify-ops-email naming the drift detector; deploy blocked by needs.release.result"
  - mode: "crane copy mirrored nothing / partially"
    detection: "mirror_reason=copy_v|copy_sha|copy_latest, or the post-copy assertion failing to resolve v<version>"
    alert_route: "release job fails; migrate AND deploy skipped via needs.release.result"
  - mode: "zot copy present at a DIFFERENT digest than this build"
    detection: "post-copy assertion: crane digest != ${DIGEST}, both values emitted"
    alert_route: "release job fails"
  - mode: "copy landed at the correct digest, cosign sign failed (incl. Sigstore outage) — a NEW release-blocking third-party dependency"
    detection: "mirror_reason=sign; message states the digest IS correct and the blocker is the signature"
    alert_route: "release job fails -> notify-ops-email with the re-sign one-liner"
  - mode: "host cannot pull from zot at deploy time (private-net down, or ZOT_PULL_* stale — NOT covered by the CI gate, see FR-A8)"
    detection: "IMAGE_PULL: zot pull failed ... now carrying the stderr tail (FR-C1); pull_failure_event; web-zot-consumer-probe heartbeat absence"
    alert_route: "Better Stack (Vector journald) + Sentry"
  - mode: "a Cloudflare token rotation does not propagate to Doppler"
    detection: "check-cloudflare-token-drift.sh exit 1, now covering Access service tokens and actually invoked (twice daily + release preflight)"
    alert_route: "scheduled-terraform-drift.yml failure -> its existing notify-ops-email"
logs:
  where: "GitHub Actions run logs (release job); Better Stack Logs source soleur-inngest-vector-prd for host-side IMAGE_PULL_* records"
  retention: "GitHub Actions default; Better Stack per existing source retention"
discoverability_test:
  command: "gh run list --workflow=web-platform-release.yml --limit 5 --json databaseId,conclusion && doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --grep IMAGE_PULL --since 24h"
  expected_output: "release runs with conclusion, and IMAGE_PULL_OK/IMAGE_PULL_FAIL records including the stderr tail on any zot miss"
```

No `ssh` in any field.

## Architecture Decision (ADR/C4)

### ADR — amend ADR-096 (status: *Adopting*)

Its `## Decision` states the CI mirror is *"explicitly non-blocking … a mirror failure degrades zot
**redundancy**, never the release/build verdict."* Sound only while GHCR is a working fallback. With
the PAT revoked and the minter off, **zot is the sole pull path**, so a mirror miss is a release that
cannot deploy.

The amendment must: **(a)** record the falsified premise with the 401/403 evidence; **(b)** change
web-platform's mirror from non-blocking to **release-blocking via a positive post-copy assertion**;
**(c)** add to `## Alternatives Considered` the rejected *restore-a-GHCR-credential* option, cited
**structurally** — ADR-088 arm-b's finding that App installation tokens can `docker login` GHCR but
are DENIED `docker pull` of private repo-linked packages, so no zero-touch GHCR pull credential
exists (v1 rejected it as operator preference, a *reversible* reason a future reader could simply
re-add); **(d)** state the testable relaxation condition; **(e)** correct the ADR's **own dead escape
hatches** — §Cold-boot-dependency axis 1 and the "Instant revert" bullet (FR-B1(3)); **(f)** carry
FR-A8's *proves-less-than-it-appears* sentence, so the amendment does not record a stronger claim than
the mechanism supports; **(g)** frame fail-closed as a **mitigation for a single-pull-path
architecture, not a resolution**, recording the restoration path (a working non-personal GHCR pull
credential, or a second mirror) as **open architectural debt** with #6031/#6023 — otherwise a future
reader inherits "one registry, no fallback" as a decision rather than a constraint; **(h)** scope the
language to **web-platform's** mirror, since the inngest image's mirror stays non-blocking and the
inngest host cannot use zot at all (see Deferred).

No new ordinal is claimed.

### C4 views

All three model files read. **No new element or `view include` is required** — enumerated and found
already modelled: **external human actors** none new; **external systems/vendors** none new (`ghcr`,
`zotRegistry`, `cloudflare`, `tunnel`, `github`, `doppler`, `betterstack`, `sentry`, `sigstore` all
present, with edges `github -> tunnel`, `tunnel -> zotRegistry`, `hetzner -> zotRegistry`,
`hetzner -> ghcr`); **containers/data stores** none new; **access relationships** no new actor→surface
grant.

Three descriptions this change **falsifies** must be corrected:

1. `ghcr` (`model.c4:264`) — described as the *"DUAL-PUSH + break-glass FALLBACK"*. The pull
   credential is revoked and the minter disabled: record the fallback as dead in practice, dated.
2. `hetzner -> ghcr` (`model.c4:454`) — *"Atomic fallback pull when zot is unconfigured/unreachable"*.
   Same falsification; it cannot authenticate.
3. `tunnel -> zotRegistry` (`model.c4:428`) — correct that #6416's mode is closed, but should also
   record the **2026-07-29 cause class** (stale CF Access service token after a Terraform replace) so
   the next reader does not re-derive the refuted route hypothesis.

Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing.

## Infrastructure (IaC)

**Skipped, with reason.** No new server, service, cron, vendor account, DNS record, cert, secret, or
firewall rule. The tunnel ingress, DNS record, CF Access application, and service token all already
exist and were verified correct against the live API (F2). **No `.tf` file is edited**, so
`apply-web-platform-infra.yml` does not fire, and **no `terraform apply`, Cloudflare write, or Doppler
write is required** — the unattended constraint is satisfied by construction, not by deferral.
FR-B4's wiring is a workflow step, not a provisioned resource.

## Encryption Posture

**Skipped, with reason.** No persistent store is introduced and no new cross-component connection is
created — the assertion travels the **existing** bridge the step already opened and reads no data.
zot's at-rest posture is unchanged (ADR-140 / `encryption-posture-ledger.json`).

## GDPR / Compliance Gate

**Skipped, with reason.** No regulated-data surface: no schema, migration, `.sql`, auth flow, or API
route. No expansion trigger fires — no LLM/external-API processing of operator data, no new cron
reading `learnings/`/`specs/`, no new artifact-distribution surface. The `single-user incident`
threshold is satisfied procedurally by `user-impact-reviewer` at review time; this change moves no
personal data.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO + architecture-strategist)

**Status:** reviewed
**Assessment:** Mechanism endorsed. **CI is the right layer and the right position** — before
`Finalise release (publish draft)`. The deploy-side alternative was considered and rejected
decisively: it lets the release publish (materializing the tag, consuming the semver, shipping the
notes) and only then refuses, which *is* the v0.244.1 shape — "decoupling them is the bug".
`zot-entry-gate.sh` reuse rejected for three reasons (it loops over both platform images, so the
web-platform verdict would couple to the inngest mirror; its `HEAD == 200` predicate cannot express a
digest mismatch; it presents `ZOT_PULL_*` as curl Basic auth) — transport is *not* the blocker,
contrary to the plan's earlier framing. Verified: `crane` and the zot docker credential persist across
steps, and the teardown's `docker logout 127.0.0.1:5000` makes the ordering mandatory. Folded in:
P0-A, the assertion moving inside the step, FR-A3's reason output, FR-A7's four clauses, FR-A8,
FR-A9, FR-B1's widened sweep, FR-B4's host workflow + required preflight.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

**CPO: SIGN-OFF WITH CONDITIONS.** Threshold `single-user incident` **sustained** with the
justification re-framed (v1 argued only the direction favouring its own design); tier **NONE
confirmed** — the change alters the operator's *failure* UX, but that surface is governed by
observability/runbook quality, not visual design, so it redirects to FR-A4/FR-B1 rather than a `.pen`.
Conditions folded in: the dead escape hatch (FR-B1(2) — the material gap, since v1's sweep reached the
code and the model but not the document the operator opens during an outage); per-discriminator plain
-language remedies + the "nothing was half-shipped" line (FR-A4); the disclosed Sigstore dependency
(Observability); AC-P1 converted to a tracked follow-through.

**Residual action after this merges:** disabling the compromised legacy Supabase `service_role` key
remains **OPEN**. This PR is a *prerequisite*, not the remediation.

### Sequencing — operator's call

The CTO recommends splitting gating from non-gating work into two PRs, because merging this branch
edits `ci-deploy.sh` (matching `on.push.paths: apps/web-platform/**`) and is therefore itself the
first-ever execution of the new gate. **Note this concern is substantially reduced in v2**: the
remaining gating change is a read-side assertion over a path already proven to work, and v1's
unvalidated bridge probe — the change the split was mostly *about* — is now surfaced as a scope
decision rather than included. The plan does not adopt the split unilaterally, since it would move the
task's headline deliverable out of this PR. **Constraint if elected:** FR-B1(2) (the runbook) must NOT
land later than FR-A. Recorded in `decision-challenges.md`.

## Open Code-Review Overlap

**None.** Queried 60 open `code-review` issues; none names any file in this plan's edit list.

## Files to Edit

- `.github/workflows/reusable-release.yml` — FR-A1–A4, A7, A9, A10 (workflow_call input), B1(1), B2.
- `.github/workflows/web-platform-release.yml` — **FR-A5** (`needs.release.result` on `migrate` +
  `deploy`), FR-A6 (deploy notify), FR-A9 (echo), FR-A10 (dispatch input + `with:` forwarding).
- `.github/actions/cf-tunnel-registry-bridge/action.yml` — FR-B2.
- `.github/workflows/scheduled-terraform-drift.yml` — FR-B4.
- `apps/web-platform/infra/ci-deploy.sh` + `ci-deploy.test.sh` — FR-C1.
- `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` — the two expected-rc literals.
- `scripts/check-cloudflare-token-drift.sh` — FR-B3.
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` — FR-B1(2).
- `knowledge-base/engineering/architecture/decisions/ADR-096-…zot.md` — amendment + FR-B1(3).
- `knowledge-base/engineering/architecture/principles-register.md` — FR-B1(4).
- `knowledge-base/engineering/architecture/decisions/ADR-088-…private-ghcr-reads.md` — FR-B1(5).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — three description corrections.

## Files to Create

- A test for the detector's Access-token arm (`*.test.sh`, alongside `scripts/`).
- `knowledge-base/project/learnings/` — the misdiagnosis learning (see Risks R6).

## Risks & Mitigations

- **R1 — a zot outage now blocks releases.** Intended: with GHCR dead, a release that cannot land in
  zot cannot deploy. **No version drift** — verified: `next` derives from
  `git tag --list "${TAG_PREFIX}*"` and a draft materializes no tag until published, so a blocked
  release consumes no version. This is also the gate's load-bearing sub-value (FR-A7 iii).
- **R2 — the orphan-draft / stale-notes leak** (FR-A11). Recorded + tracked, not reaped.
- **R3 — `:latest` and `:<sha>` are pushed before the gate**, so they can point at a build with no
  published release. Conclusion (harmless) survives, but v1's reasoning was imprecise: the fresh-boot
  cloud-init path *does* resolve `:latest` (`variables.tf` default), rewritten to the zot host. It is
  harmless because every **automated** route pins a digest —
  `apply-web-platform-infra.yml` resolves the pin from web-1's live `/health` and *explicitly refuses*
  `:latest` ("a birth on an unvetted image is the ADR-080 stale-image trap"), and the per-PR apply path
  halts on any `hcloud_server` create. The only route to `:latest` is a break-glass operator-local
  apply without `-var image_name`, which that workflow already forbids. (Restated precisely because
  v1's version was the very "verify the claim, don't route on the comment" failure R6 is about.)
- **R4 — a spuriously-failing gate blocks a healthy release.** Mitigated by choosing an assertion with
  no trust configuration and no second credential: one `crane digest` against a value already in
  scope. No cosign verify, no GHCR read.
- **R5 — the gate proves less than it appears** (FR-A8). Stated at the call site and in the ADR.
- **R6 — the misdiagnosis recurs.** The empty-200 trap consumed this incident's diagnostic budget and
  was *caused by a false comment in the repo*. FR-B1 deletes the false claims; the runbook records the
  correct probe. A learning captures the general lesson: **a comment that names a root cause is a
  claim to verify, not a fact to route on** — and, sharply, this plan's own v1 committed the same
  defect twice (labelling an underivable state `signing_failed`, and asserting a `needs:`-based
  deploy gate without reading the `if:`).

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| A separate `zot_verify` step (v1) | **Rejected.** Breaks on the target incident: `degraded()` exits before `install_crane`, so the step finds no crane and no zot login. Also spawned a taxonomy, an output contract, a duplicate retry helper, and a skip-invariant proof — all of which dissolve when the assertion lives in the step that does the copy. |
| Make `degraded()` exit 1 and drop `continue-on-error` | **Adopted** (FR-A1). v1 rejected this as "trusting the step's own exit path", which was circular — the exit path is untrustworthy *because* it is hardcoded `exit 0`. |
| Compare against `steps.docker_build.outputs.digest` only | Kept as the comparand (FR-A2) — it is authoritative for "the bits this release built". |
| Add a GHCR-side `crane digest` (advisor's suggestion) | **Rejected.** Puts GHCR back on the release critical path of an ADR whose purpose is removing it; is the one unverified prerequisite; and `crane digest` against GHCR is a *rejected* in-repo deviation in favour of `docker buildx imagetools inspect`. |
| Assert at the deploy job's start | **Rejected** (architecture review). The release would publish first — materializing the tag and notes — and only then refuse. That decoupling *is* the defect. Also needs cloudflared + Doppler + crane + a second login in a job that has none, and holds the `web-1-swap` lock. |
| Call `zot-entry-gate.sh` from CI | **Rejected.** Loops over both platform images (coupling web-platform's verdict to the inngest mirror); `HEAD == 200` cannot express a digest mismatch; different credential mechanism. Transport is *not* the blocker. |
| Full `cosign verify` in the gate | **Rejected.** Needs trust-root/identity config in CI and risks spuriously failing releases. |
| Restore a GHCR pull credential, keep warn-only | **Rejected structurally** (not as preference): App installation tokens are DENIED `docker pull` on private repo-linked packages (ADR-088 arm-b), so no zero-touch GHCR pull credential exists. |
| Remove `lifecycle { ignore_changes = [value] }` so Terraform propagates rotations | **Rejected**, consistent with the detector's own reasoning: trades silent staleness for a churn bug already hit. Detection is safer — but it must *cover* Access tokens and actually *run* (FR-B3/B4). |
| A new scheduled workflow for the detector | **Rejected.** `scheduled-terraform-drift.yml` already has the credentials, cadence, and notify idiom, and a new GHA `schedule:` is off-pattern (ADR-033). |
| Stage a Terraform fix for operator apply | **Unnecessary** — no infrastructure defect exists (F2). |

## Deferred (tracking issues — Phase 8)

**Filed 2026-07-30.** Net issue flow for this PR: **closing 0, filing 3, net +3.** Each
filing carries its own justification below, per the filing-site net-flow gate. The plan
listed five deferrals; they resolved to three issues plus one inline fix plus one comment
on an already-open issue:

| Plan item | Disposition |
|---|---|
| 1. inngest mirror non-blocking + live #6416 defect | **#7077**, and a status comment on the still-OPEN **#6416** rather than a duplicate. Also absorbs UC-1's deferred `nc -z` probe fix, which the panel explicitly wanted done *together with* the #6416 fix. |
| 2. Two more false `/v2/` gates | Folded into **#7079**. Measured correction to the plan: `cloud-init.yml` has **two** occurrences (`:527` and `:733`), not the one the plan cited. Cannot be inlined — `hcloud_server.web` carries `ignore_changes = [user_data]`, so a cloud-init edit is unverifiable without a host reprovision. |
| 3. `zot-entry-gate.sh` unwired + stale contract | **Half done inline** (a dated header note recording that nothing invokes it, that its contract is stale, and that its probe is a false gate). The remaining wire-or-delete decision is in **#7079**. Its probe was deliberately NOT repaired: fixing a check inside a script nothing calls buys no runtime correctness. |
| 4. AC-P1 first-release verification | **#7078** — required as a tracked follow-through by `wg-block-pr-ready-on-undeferred-operator-steps`; genuinely un-automatable pre-merge (the faithful test is a production release). |
| 5. Orphan-draft / stale-notes leak (FR-A11) | Folded into **#7079**. Deferred rather than reaped because a reaper is a new scheduled object with its own failure modes, against a leak that is confusing rather than dangerous. |

Why net +3 was not reducible further: #7077 and #7078 are different classes (a discovered
defect in another subsystem, and an operator follow-through) and the rule is explicit that
discovered bugs stay separate from consolidated trackers. #7079 is the consolidation — it
absorbs three of the five plan items.

## Test Scenarios

1. Bridge fails → `mirror_reason=bridge`, cloudflared log dumped at the failing step, **release job
   fails**, `migrate` and `deploy` both skipped via `needs.release.result`.
2. Bridge healthy, `crane copy` of `v<version>` mirrors nothing → assertion cannot resolve →
   `mirror_reason=copy_v` → fails.
3. `v<version>` copied, `<sha>` arm fails → loop aborts before `cosign sign` → `mirror_reason=copy_sha`;
   the message must **not** blame Sigstore.
4. zot holds `v<version>` at a different digest → assertion mismatch, both digests emitted.
5. Copy + sign both fine → digest matches → `mirror_status=ok` → release publishes and deploys.
6. `cosign sign` genuinely fails → `mirror_reason=sign`, message states the digest is correct and
   prints the re-sign one-liner.
7. `docker_build` skipped (plugin release, no `docker_image`) → mirror and assertion skipped; release
   unaffected.
8. `workflow_dispatch` override with empty reason → inert, still fails; with a reason → warning +
   notification + `action-required` issue.
9. Detector: dead Access service token (403) → exit 1 naming key + config; live (200) → LIVE.
10. `ci-deploy.sh` zot arm fails → log line carries a bounded single-line stderr tail.
11. Mirror harness passes with only the two expected-rc literals changed.
