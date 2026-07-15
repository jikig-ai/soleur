<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: this plan introduces NO new infrastructure. It edits the
  host-resident ci-deploy.sh, delivered to running hosts via the EXISTING
  apply-deploy-pipeline-fix.yml auto-apply (HTTPS /hooks/infra-config, no SSH).
  See the ## Infrastructure (IaC) section. No manual provisioning step exists.
-->
---
title: "fix(infra): deploy GHCR image_pull_failed — recover on pull-denial, not only login-failure (§1A gap)"
date: 2026-07-14
type: fix
issue: 6400
severity: P1
lane: cross-domain
brand_survival_threshold: aggregate pattern
refs: ["#6395", "#6396", "#6090", "#6031", "#6122", "ADR-088", "ADR-096", "ADR-087"]
---

# fix(infra): deploy GHCR `image_pull_failed` — recover on pull-denial, not only login-failure (§1A gap)

## Enhancement Summary

**Deepened on:** 2026-07-14
**Review panel:** architecture-strategist, security-sentinel,
observability-coverage-reviewer, code-simplicity-reviewer (all grounded in
`ci-deploy.sh`). Gates run: 4.5 network-outage (fired — see deep-dive), 4.6
user-brand (pass), 4.7 observability (pass), 4.8 PAT-shaped (fired — documented
exception, below), 4.9 UI-wireframe (n/a).

### Key changes from review

1. **Helper return contract (P1-B):** `refetch_ghcr_and_relogin` must make the
   `docker login` result its exit status — §1A's inline body falls through to
   `dt=""` (returns 0 always). The extraction is NOT byte-identical; it adds the
   return contract. Helper now echoes a staged result (`recovered` /
   `refetch_unavailable` / `relogin_failed`).
2. **Classifier input type (P2-E / security P1):** `_pull_result_is_auth_denied`
   must receive stderr **content** (`tail -c 400 "$perr"`), not the tempfile
   path, or recovery silently no-ops.
3. **Single event, `recovery_stage`-tagged (P1-A / simplicity / observability):**
   no `not_recovered` second event; `pull_failure_event` gains a `recovery_stage`
   tag so ONE event per failure discriminates the branch; the new breadcrumb
   fires only on recovered-success.
4. **cosign continuity (P2-F):** the relogin writes the SAME `$GHCR_DOCKER_CONFIG`
   the verifier mounts `:ro`, so a recovered pull doesn't 401 the `.sig` fetch
   (new AC13).
5. **DRY (P2-G) + temp cleanup (P2-H):** one `_ghcr_pull_or_recover` at both GHCR
   sites; `rm -f "$perr"` on every return.
6. **Scope cut (simplicity Rec1):** Phase 4 (cloud-init boot-path parity) deferred
   to a follow-up — recreate-only, contributes nothing to the running-host P1.
7. **ADR re-homing (P2-C/D):** normative MUST → ADR-096 (owns the interim GHCR
   path); ADR-088 keeps only the factual note; AP-016 register updated.

## Overview

The `web-platform-release` deploy job fails at the `deploy` step with
`ci-deploy.sh exited 1 (reason=image_pull_failed)`; Sentry `WEB-PLATFORM-59`
records `image pull failed (auth_denied)`. Prod (web-1) is frozen on the last
green build; every new merge fails the same way. PR #6395's §1A (re-fetch the
GHCR credential from Doppler + retry `docker login` on a login **FAILURE**, not
only on EMPTY) was applied to the host but the redeploy still `auth_denied` —
**necessary-but-insufficient**.

**Root cause (structural, confirmed by code + telemetry-of-record):** §1A's
recovery is gated on the outcome of `docker login`
(`ghcr_prelude_and_login`, `ci-deploy.sh:655-683`). But the production failure
surfaces one step later, at `docker pull` inside `pull_image_with_fallback`
(`ci-deploy.sh:750-782`, called at `:1439`), which has **no credential
re-fetch/relogin/retry** — it emits `pull_failure_event` and aborts. A
credential that **logs in successfully but cannot pull** therefore bypasses §1A
entirely: login succeeds → §1A is skipped → the pull denies →
`image_pull_failed`. Two independently-sufficient conditions produce exactly
this shape, and **the same fix covers both**:

1. **A GitHub App installation token is baked/used.** GHCR accepts App
   installation tokens for `docker login` but returns `denied` on `docker pull`
   of private repo-linked packages — a confirmed GitHub platform limitation
   (`knowledge-base/project/learnings/2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`;
   ADR-088 is **superseded** on exactly this fact). If the host's baked
   `/etc/default/soleur-ghcr-read` snapshot is an App token, login-ok + pull-deny
   is guaranteed and §1A never fires.
2. **A rotated/revoked PAT where the baked login nonetheless returns success**
   (edge case) — again login-ok, pull-deny, §1A skipped.

**The durable fix:** move the credential recovery to the site where pull
capability is actually proven — the pull itself. On a GHCR `docker pull`
classified `auth_denied`, re-fetch the CURRENT `prd` credential (the valid
pull-capable PAT — Doppler `prd` holds it and the host's `prd`-scoped
`DOPPLER_TOKEN` can read it), `docker login` again, and retry the pull **once**
before aborting. `login`-success is not proof of `pull` capability; only a pull
attempt is. This is delivered as an edit to the host-resident `ci-deploy.sh`,
which auto-applies to the running host on merge via
`apply-deploy-pipeline-fix.yml` (HTTPS `/hooks/infra-config` file delivery — **no
SSH, no image pull required to land the fix**); the next release deploy then
self-recovers. Zero human steps.

This hardens the **interim GHCR PAT pull path** that ADR-096 (#6122) keeps live
as break-glass until the self-hosted `zot` registry soak completes. It does not
change the registry substrate, the token TTL, the minter (which stays disabled),
or the App permission set.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6400 / KB record) | Reality (verified this session) | Plan response |
|---|---|---|
| "`DOPPLER_TOKEN` may be **absent** in the webhook/deploy exec context → §1A skipped." | `DOPPLER_TOKEN` **is present**: `cloud-init.yml:408` writes it into `/etc/default/webhook-deploy` (deploy:deploy 0600); `webhook.service:7` sources it; sibling units use it to run `doppler … --config prd`. | Discard the "token absent" hypothesis. Fix does not depend on injecting a token; it depends on recovering at the pull site. Confirm at /work Phase 0 from Vector logs (PRELUDE lines), not by assumption. |
| "§1A re-fetches from `prd` (the deruelle **PAT**, long-lived); baked comes from `prd_terraform` (**App-minted**, expiring) — different cred **classes**." | `prd.GHCR_READ_TOKEN` = valid pull-capable **PAT** (HTTP-200 live-pull proof + App-tokens-can't-pull fact + **minter disabled** `GHCR_MINTER_DISABLED=true`, `cron-ghcr-token-minter.ts:74-89`). `var.ghcr_read_token` (baked source, from `prd_terraform`) is documented as the **same machine-account PAT** (`variables.tf:335-345`, `ghcr-read-credential.tf`). | The re-fetch **class** is correct (both PAT). The real gap is not class-mismatch on re-fetch but that recovery never runs on a login-ok/pull-deny cred. The baked value is a **boot snapshot** never re-baked on a running host (`server.tf` `lifecycle.ignore_changes=[user_data]`), so it can drift stale/App even when the source is a PAT. |
| Learning `2026-07-13-…-stale-baked-cred.md:71` asserts `var.ghcr_read_token` is "the ADR-088 App-installation-minted read cred." | Contradicts `variables.tf:335-345` (PAT) AND the HTTP-200 pull proof in the same learning file (:30-32). It is a stale/incorrect "reconciled false positive." | In-PR doc fix: correct that line to "machine-account read:packages PAT (interim, ADR-087 D1); App-minted minter is disabled (can't pull GHCR)." Prevents future misdiagnosis. |
| Remediation option 4: "Land #6396 observability FIRST." | #6396 is **merged** (commit `c749e4e6a`): Vector ships host journald→Better Stack + `pull_failure_event` carries `host_id`. | The blind spot is closed. /work Phase 0 pulls this telemetry to confirm which branch executed before/while shipping the fix (diagnosis-first). |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct new breakage — the fix
is **fail-open** (a recovery attempt that, on failure, leaves the identical
`image_pull_failed` terminal state as today). Worst case is "still frozen," never
"more broken." The user-visible harm is the *pre-existing* one this fixes: prod
stays frozen on an old build, so no feature/fix/security patch can reach the one
prod host serving all users.

**If this leaks, the user's data is exposed via:** no new exposure vector. The
change handles a GHCR read credential that is piped to `docker login` via
`--password-stdin` only, never argv/logs, and unset after use (unchanged
discipline). No user data, schema, or PII surface is touched.

**Brand-survival threshold:** `aggregate pattern` — a fleet-wide deploy-pipeline
availability regression, not a per-single-user data incident. The fix's fail-open
design bounds the blast radius of a bad change to "no change from current frozen
state." (Sensitive-path note: touches `apps/web-platform/infra/*.sh` — a
credential-handling surface — so the section is mandatory and present;
`reason: fleet-wide deploy reliability, fail-open, no data surface`.)

## Hypotheses (L3→L7 — network-outage checklist honored)

The issue text contains "SSH"/"timeout" tokens, triggering the network-outage
checklist. The symptom is **L7 auth (HTTP 401/`denied`)**, not L3/L4
connectivity — but the checklist's L3-first discipline is honored by explicitly
ruling out the lower layers with artifacts:

1. **L3 firewall / egress — RULED OUT (artifact).** The credential pulls the
   exact denied tags off-host to **HTTP 200** (issue evidence) and the registry
   returns HTTP status codes (`401`/`200`), not `ECONNREFUSED`/`EHOSTUNREACH`/
   timeout. A registry that answers HTTP is reachable; egress-IP/firewall drift
   would produce a connect failure, not an auth denial. No firewall change is
   proposed.
2. **L3 DNS / routing — RULED OUT.** `ghcr.io` resolves and completes a TLS
   handshake (the 401/200 responses prove the request reached GHCR's origin).
3. **L7 TLS/proxy — N/A.** Pull is direct host→ghcr.io over the host's
   unrestricted egress (ADR-087 B′); no CF edge on this path.
4. **L7 application/auth — THE FAULT.** `pull_result=auth_denied` is a
   credential capability failure (login-capable, pull-incapable cred, or a
   revoked baked snapshot). Fix at this layer. Verification artifact at /work
   Phase 0: Better Stack Vector query for the `ci-deploy` PRELUDE lines + Sentry
   `op:image-pull pull_result:auth_denied` grouped by `host_id`.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5 — gate fired on "SSH"/"timeout")

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall / egress | **verified — not the fault** | Off-host `docker pull` of the denied tags → HTTP **200** (issue evidence); GHCR returns HTTP status, not `ECONNREFUSED`/`EHOSTUNREACH`/timeout. A reachable-but-401 registry rules out egress-IP/firewall drift. No `hcloud firewall` change proposed. |
| L3 DNS / routing | **verified — not the fault** | `ghcr.io` resolves + TLS-handshakes (the 401/200 responses prove the request reached GHCR origin). |
| L7 TLS / proxy | **N/A** | Host→ghcr.io is direct over the host's unrestricted egress (ADR-087 B′); no CF edge on the pull path. |
| L7 application / auth | **THE FAULT** | `pull_result=auth_denied` = credential capability failure. /work Phase 0 pulls the `ci-deploy` PRELUDE lines (Vector→Better Stack, #6396) + Sentry `op:image-pull` by `host_id` to confirm the login-ok/pull-deny branch. |

Ordering discipline honored: L3/L4 confirmed healthy *before* the L7 auth
hypothesis — the fault is genuinely application-layer credential capability, not a
lower-layer connectivity drop. No sshd/fail2ban/firewall fix is in scope.

### Deepen-plan Phase 4.8 disposition (PAT-shaped-variable gate)

The 4.8 gate fired on `var.ghcr_read_token`. **Sanctioned exception, not a
regression:** this is the GHCR `read:packages` *pull* credential, which GitHub
*requires* be a user PAT — App installation tokens cannot pull private GHCR (the
exact fact this issue turns on; ADR-088 superseded, ADR-087 D1). It is a READ
credential, not GitHub-write auth, and the plan introduces **no new** PAT
variable — it references the existing, architecturally-mandated one. AP-016
already records this as the interim exception to `hr-github-app-auth-not-pat`;
Phase 5 updates AP-016's stale "multi-tenant target" clause. Telemetry emitted.

## Root-cause verification gate (/work Phase 0 — diagnosis-first, no SSH)

Per the recurring-prod-symptom discipline (a fix that survived a prior fix must
be pinned to the executing path from production observability, not code-reading
alone), Phase 0 MUST establish **which branch executed** before relying on the
fix targeting it — now possible because #6396 shipped the telemetry:

- **Sentry (API, no dashboard eyeballing):** query `op:image-pull` events since
  the incident window, grouped by `host_id` and `pull_result`. Confirms
  `auth_denied` and per-host attribution.
- **Better Stack Vector logs** (`betterstack-query.sh`, source 2457081): pull the
  `ci-deploy` `PRELUDE:` lines for the failing host+window. The decisive
  discriminator:
  - `docker login … ok (private-package pull authenticated)` **followed by**
    `IMAGE_PULL_FAIL … auth_denied` ⇒ **login-ok / pull-deny** (Scenario 1/2) —
    the exact gap this fix closes.
  - `docker login … FAILED …` + `re-fetch … STILL FAILED` ⇒ §1A ran and the
    re-fetch itself failed ⇒ additionally investigate the `prd` value/scope
    before relying on the pull-site recovery (same helper still applies).
- **Current prod state:** `curl -s https://app.soleur.ai/health | jq .version`.
  If prod has already been hand-recovered (re-bake/recreate) since filing, the
  deliverable is the **durable structural hardening** so the class cannot recur;
  the fix ships regardless.

If Phase 0 shows **zero** `op:image-pull auth_denied` events on any live host
(fully self-recovered and no recurrence), record it and still ship the
structural fix — the login-ok/pull-deny gap is real in the code regardless of
whether it is currently firing.

## Implementation Phases

### Phase 1 — Extract a shared GHCR re-fetch/relogin helper (`ci-deploy.sh`)

Factor the credential recovery out of §1A's inline retry into a reusable helper
so the pull site can call the identical logic (no duplication):

```bash
# refetch_ghcr_and_relogin: re-fetch the CURRENT prd GHCR read cred, re-run
# docker login into the SAME docker config the cosign verifier mounts, and
# return a STAGE code so the caller can discriminate the failure.
# Echoes on stdout one of: recovered | refetch_unavailable | relogin_failed
# Returns 0 iff stage==recovered.
# Token via --password-stdin only; never argv/logs; kept `local` + unset after so
# no child process env carries it. On success re-exports GHCR_READ_USER (username,
# not a secret) so the :ro cosign docker config authenticates with the retried
# cred. Guarded on doppler + DOPPLER_TOKEN (prd-root scoped).
refetch_ghcr_and_relogin() {
  command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]] || { printf refetch_unavailable; return 1; }
  local du="" dt="" n=0
  n=0; until du="$(timeout 45 doppler secrets get GHCR_READ_USER  --plain --project soleur --config prd 2>/dev/null)"; [[ -n "$du" ]]; do n=$((n+1)); [[ "$n" -ge 3 ]] && break; sleep 5; done
  n=0; until dt="$(timeout 45 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null)"; [[ -n "$dt" ]]; do n=$((n+1)); [[ "$n" -ge 3 ]] && break; sleep 5; done
  [[ -n "$du" && -n "$dt" ]] || { dt=""; printf refetch_unavailable; return 1; }
  # docker login writes $GHCR_DOCKER_CONFIG (the SAME file verify_image_signature
  # mounts :ro) — the auth ENTRY is what cosign needs, not just the username.
  if printf '%s' "$dt" | docker login ghcr.io -u "$du" --password-stdin >/dev/null 2>&1; then
    export GHCR_READ_USER="$du"; dt=""; printf recovered; return 0    # login status IS the exit status
  fi
  dt=""; printf relogin_failed; return 1
}
```

**Load-bearing (P1-B, architecture review):** the extraction is NOT
byte-identical to §1A. §1A's inline body ends at `dt=""` (`ci-deploy.sh:679`),
whose exit status (0) would make the function `return 0` on every path — the
`docker login` result is never surfaced. The helper MUST make the login status
its return status (as above), or the pull-site gate `… && refetch_ghcr_and_relogin`
would retry the pull against a still-bad cred and muddy the `recovered` signal.

Then replace the inline body at `ci-deploy.sh:669-679` (§1A) with a call to this
helper — §1A's observable behavior (recover on login FAILURE) is preserved; the
helper just adds the return contract §1A never needed inline.

### Phase 2 — Recover at the pull site (`pull_image_with_fallback`, `ci-deploy.sh:750-782`)

Wrap the GHCR pull + recovery in ONE helper called at BOTH GHCR pull sites (the
zot→GHCR atomic fallback at `:765` and the zot-dark GHCR path at `:775`) — do NOT
inline the block twice (P2-G: same drift risk the classifier extraction avoids).
The zot leg (`:755`) is NOT wrapped — zot-down already has the atomic GHCR
fallback and the zot cred is a different class/registry (recovery is
GHCR-credential-scoped).

```bash
# _ghcr_pull_or_recover <perr>: pull ${IMAGE}:${TAG} from GHCR; on an AUTH-denied
# failure, re-fetch the prd cred, relogin, retry the pull ONCE. Returns 0 on
# success. On failure, sets the global RECOVERY_STAGE for the caller's
# pull_failure_event tag (empty when no recovery was attempted). Retry-once, no loop.
_ghcr_pull_or_recover() {
  local perr="$1"
  RECOVERY_STAGE=""
  docker pull "${IMAGE}:${TAG}" 200>&- 2>"$perr" && return 0
  # classify the STDERR CONTENT (not the file path — P2-E/security): the predicate
  # reuses pull_failure_event's regex (ci-deploy.sh:525), extracted to one source.
  if _pull_result_is_auth_denied "$(tail -c 400 "$perr" 2>/dev/null)"; then
    local stage; stage="$(refetch_ghcr_and_relogin)"   # recovered|refetch_unavailable|relogin_failed
    if [[ "$stage" == "recovered" ]]; then
      if docker pull "${IMAGE}:${TAG}" 200>&- 2>"$perr"; then
        pull_auth_recovery_event "${IMAGE}:${TAG}" recovered   # info breadcrumb, distinct op
        return 0
      fi
      RECOVERY_STAGE="pull_still_denied"                       # relogin ok but retry pull still denied
    else
      RECOVERY_STAGE="$stage"                                  # refetch_unavailable|relogin_failed
    fi
  fi
  return 1
}
```

Call site (both `:765` and `:775`), fail-open, temp-file cleanup preserved (P2-H):

```bash
if _ghcr_pull_or_recover "$perr"; then rm -f "$perr"; return 0; fi
# pull_failure_event carries RECOVERY_STAGE as a tag so ONE event per failure
# discriminates the root cause (no second event — simplicity + P1-A).
pull_failure_event "${IMAGE}:${TAG}" "$(tail -c 400 "$perr" 2>/dev/null)" "${RECOVERY_STAGE:-}"
rm -f "$perr"; return 1
```

- `_pull_result_is_auth_denied` reuses the classifier regex in `pull_failure_event`
  (`ci-deploy.sh:525`) — extract it to a tiny predicate that greps its **content**
  argument so the two agree by construction (do NOT duplicate the regex).
- **No `not_recovered` second event** (P1-A + simplicity): a non-auth pull failure
  (network/manifest_unknown) never enters the recovery branch, so `RECOVERY_STAGE`
  stays empty and `pull_failure_event` fires exactly as today. Only an auth-denied
  miss carries a non-empty `RECOVERY_STAGE`.
- **cosign continuity (P2-F):** `refetch_ghcr_and_relogin`'s `docker login` writes
  the retried auth ENTRY into the same `$GHCR_DOCKER_CONFIG` that
  `verify_image_signature` mounts `:ro` — so a recovered pull does not then 401 the
  `.sig` fetch. Re-exporting `GHCR_READ_USER` (username) alone is insufficient; the
  auth entry is what cosign needs.
- Retry the pull exactly **once** (no loop). Fail-open: on recovery miss, the
  terminal state is the unchanged `image_pull_failed` — never worse than today.

### Phase 3 — Discriminating recovery telemetry (`recovery_stage`)

The recovery must be diagnosable in ONE event per outcome (observability P1: a
boolean `recovered|not_recovered` cannot distinguish the competing root causes).
Two additions:

1. **`pull_auth_recovery_event "${IMAGE}:${TAG}" recovered`** — a fail-open,
   env-guarded Sentry breadcrumb (mirror `pull_failure_event`'s transport +
   `host_id` tag; build the payload with `jq -n --arg`, never string-interpolate;
   NEVER include raw docker stderr) fired ONLY on a **recovered-success**. Tags:
   `feature:supply-chain op:image-pull-recovery host_id:<id>`, `level:info`. The
   distinct `op` keeps recovered-successes OUT of the WEB-PLATFORM-59 failure
   grouping.
2. **`pull_failure_event` gains an optional `recovery_stage` arg** (3rd param)
   surfaced as a Sentry tag. On an auth-denied miss the caller passes
   `refetch_unavailable | relogin_failed | pull_still_denied` (from the helper's
   staged return); on a non-auth failure it is empty (byte-identical to today).
   So ONE failure event pins the branch — no second event on the miss path.

This is the affected-surface (host, operator-blind) discriminating probe mandated
by plan Phase 2.9.2 — one event decides the root cause the moment it ships:
`recovered` (baked cred was login-ok/pull-deny, now healed), `pull_still_denied`
(relogin succeeded but the `prd` cred itself cannot pull — escalate to PAT
rotation), `relogin_failed` / `refetch_unavailable` (Doppler/token path).

### Phase 4 — DEFERRED: boot-path parity (`cloud-init.yml` seed `ghcr_login`) → follow-up

**Cut from this PR (simplicity review Rec1).** The boot seed-pull is the same
login-ok/pull-deny class, but `cloud-init.yml` is baked `user_data` with
`ignore_changes=[user_data]` — the change lands ONLY on host recreate, contributes
**nothing** to the running-host P1, is NOT delivered by
`apply-deploy-pipeline-fix.yml`, and adds a higher-blast-radius fresh-host
provisioning edit + a new test file to a hotfix. File a tracked follow-up issue
("boot-path GHCR seed-pull denial parity, mirroring ci-deploy.sh #6400"; may be
mooted by zot/ADR-096). The acute fix is Phases 1-3.

### Phase 5 — Config-source reconciliation + register/doc hygiene (verification)

The baked snapshot is only a boot cache; the durable recovery is the re-fetch.
Reconcile the source + correct the stale records:

- /work verify (read-only, API): confirm `prd_terraform.GHCR_READ_TOKEN` (the
  `TF_VAR_ghcr_read_token` baked source) is the **same pull-capable, `read:packages`-only
  PAT** as `prd.GHCR_READ_TOKEN`. If it diverges (e.g. an App token left from #6031
  minter experiments), file a follow-up to re-align `prd_terraform` (no code
  change; the recovery already covers the running fleet).
- In-PR doc fix: correct the stale App-minted claim in
  `2026-07-13-…-stale-baked-cred.md:71` (see Research Reconciliation).
- In-PR register fix (P2-D): update `principles-register.md` AP-016 — it still
  names the App-installation-token minter as "the multi-tenant target," which the
  confirmed root cause (App tokens cannot pull private GHCR) makes infeasible for
  the pull leg; record that the forward direction is ADR-096/zot. Leaving it stale
  makes the register contradict the ADR this PR amends.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — extract `refetch_ghcr_and_relogin`
  (Phase 1, with explicit staged return); `_ghcr_pull_or_recover` + pull-site
  recovery at both GHCR sites (Phase 2); `pull_auth_recovery_event` +
  `_pull_result_is_auth_denied` predicate + `pull_failure_event` `recovery_stage`
  arg (Phase 3).
- `apps/web-platform/infra/ci-deploy.test.sh` — RED-first tests (see Test Scenarios).
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — record the normative login≠pull-capability recovery contract for the interim GHCR break-glass path it owns (see ADR/C4).
- `knowledge-base/engineering/architecture/decisions/ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md` — factual note in the staleness section (why App tokens can't pull); NOT the normative MUST (P2-C).
- `knowledge-base/engineering/architecture/principles-register.md` — update AP-016 (minter can't pull GHCR; forward is ADR-096/zot) (P2-D).
- `knowledge-base/project/learnings/2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md` — correct line 71 (stale App-minted claim).

## Files to Create

- `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` — soak probe (see
  Follow-Through Enrollment). No other new file — helper + breadcrumb live inside
  `ci-deploy.sh`; no new Terraform resource, secret, vendor, or workflow.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (RED→GREEN):** `ci-deploy.test.sh` adds a mock-`docker` case where
  `docker login` **succeeds** but the first GHCR `docker pull` returns
  `denied`, and a second `docker pull` (after a re-fetch/relogin) **succeeds**.
  Assert `pull_image_with_fallback web` returns 0 and the trace shows exactly one
  re-login + one pull retry. (Fails on `main` where §1A never fires on a
  login-ok/pull-deny cred.)
- **AC2:** a mock case where BOTH pulls deny (recovery miss) → `pull_image_with_fallback`
  returns 1, `final_write_state 1 "image_pull_failed"` path is reached (terminal
  state unchanged from today — fail-open proven).
- **AC3:** the auth-denied classifier `_pull_result_is_auth_denied` is the SAME
  regex `pull_failure_event` uses (grep proves one regex, not two) AND it
  classifies stderr **content** — a mock passing the stderr *content* string
  matches, and the pull-site caller passes `tail -c 400 "$perr"` (not the path),
  so recovery is not a silent no-op (security/P2-E).
- **AC4:** zot-active mock: a zot pull failure still falls back to GHCR (existing
  behavior) and the new recovery does NOT fire on the zot leg (recovery is
  GHCR-cred-scoped).
- **AC5:** on a **recovered-success** `pull_auth_recovery_event` fires once
  (`op:image-pull-recovery`, `host_id` tag, level info); on an auth-denied **miss**
  NO second event fires — `pull_failure_event` carries the `recovery_stage` tag
  (`refetch_unavailable|relogin_failed|pull_still_denied`); a non-auth failure
  carries an empty `recovery_stage`. Asserted via the Sentry-store mock-trace
  harness (deterministic, no live network).
- **AC6:** `refetch_ghcr_and_relogin` never places the token on argv or in logs
  (grep the function body: token is `local`, reaches `docker login` only via
  `--password-stdin`, and is unset after); `pull_auth_recovery_event` payload is
  built with `jq -n --arg` and contains NO raw docker stderr — reuses §1A +
  `pull_failure_event` discipline.
- **AC7:** `bash -n` on `ci-deploy.sh`; `ci-deploy.test.sh` passes locally (invoke
  via `bash ci-deploy.test.sh` — the repo convention; verify at /work).
- **AC13 (cosign continuity, P2-F):** a mock asserts the recovered pull's
  `docker login` writes into the SAME `$GHCR_DOCKER_CONFIG` that
  `verify_image_signature` mounts `:ro`, so a recovered pull does not then 401 the
  cosign `.sig` fetch.
- **AC14 (helper return contract, P1-B):** `refetch_ghcr_and_relogin` returns
  non-zero (and echoes `relogin_failed`/`refetch_unavailable`) when relogin does
  NOT succeed — a mock with a failing `docker login` proves the retry pull is NOT
  attempted (guards against the §1A `dt=""`-fallthrough return-0 bug).
- **AC8:** ADR-096 recovery-contract note + ADR-088 factual note + AP-016 update +
  the corrected learning line committed in the same PR.
- **AC9:** `ship-deploy-pipeline-fix-gate.test.ts` parity: `ci-deploy.sh` is in
  both `apply-deploy-pipeline-fix.yml`'s `paths:` filter and `server.tf`'s
  `deploy_pipeline_fix` `triggers_replace` set (both already true — assert
  unchanged so the fix auto-applies on merge).

### Post-merge (automated — no human step)

- **AC10 (auto):** merging fires `apply-deploy-pipeline-fix.yml` → `ci-deploy.sh`
  lands on the host (`files_written == files_total`, `files_failed == 0`) via the
  HTTPS `/hooks/infra-config` path. No SSH; verified by the workflow itself.
- **AC11 (auto):** the subsequent `web-platform-release` deploy completes
  (`reason=ok`), prod `https://app.soleur.ai/health` `.version` advances past the
  frozen build; no `pull_result=auth_denied` on the winning deploy.
- **AC12 (soak, follow-through):** zero `op:image-pull pull_result:auth_denied`
  events fleet-wide for 3 days post-deploy (enrolled follow-through, below).
  `Ref #6400` in the PR body; the follow-through sweeper closes #6400 when the
  soak holds.

## Observability

```yaml
liveness_signal:
  what: "web-platform-release deploy job reaches reason=ok AND prod /health .version advances; a recovered gap emits op:image-pull-recovery (recovered)"
  cadence: "every deploy (per merge to main touching apps/web-platform/**)"
  alert_target: "Sentry WEB-PLATFORM-59 (image pull failed auth_denied) — existing; recovery_stage tag narrows next occurrence"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (pull_failure_event + recovery_stage tag, pull_auth_recovery_event); .github/workflows/web-platform-release.yml (deploy gate)"
error_reporting:
  destination: "Sentry (op:image-pull with recovery_stage tag, op:image-pull-recovery) + Better Stack via #6396 Vector host-journald shipping"
  fail_loud: "pull_failure_event (error) on total failure, now tagged recovery_stage; recovered-success emits op:image-pull-recovery (info) — one event per outcome, no double-emit"
failure_modes:
  - mode: "baked/first cred logs in but cannot pull (App token or revoked snapshot) — the target bug"
    detection: "pull_auth_recovery_event op:image-pull-recovery (recovered, host_id-tagged, level info); PRELUDE 'docker login … ok' then IMAGE_PULL_FAIL (Vector)"
    alert_route: "no page — recovered is info; the recovery firing at all is the signal the baked cred is stale"
  - mode: "prd cred itself cannot pull (login-ok but pull-deny even after re-fetch — e.g. an App token clobbered prd)"
    detection: "pull_failure_event recovery_stage=pull_still_denied, host_id-tagged (relogin succeeded, retry pull still denied)"
    alert_route: "Sentry WEB-PLATFORM-59 (error) — escalate to prd GHCR_READ_TOKEN rotation / verify prd holds a read:packages PAT"
  - mode: "prd cred unfetchable / relogin fails (Doppler transient, revoked token)"
    detection: "pull_failure_event recovery_stage=relogin_failed | refetch_unavailable, host_id-tagged"
    alert_route: "Sentry WEB-PLATFORM-59 (error) — check Doppler prd GHCR_READ_{USER,TOKEN}"
  - mode: "DOPPLER_TOKEN unreadable in deploy exec context (regression)"
    detection: "recovery_stage=refetch_unavailable + PRELUDE 'doppler/DOPPLER_TOKEN unavailable' line in Vector logs"
    alert_route: "Sentry WEB-PLATFORM-59 (error) + Better Stack log query; surfaced in deploy-status reason"
logs:
  where: "host journald (ci-deploy tag) -> Vector -> Better Stack Logs source 2457081 (#6396); Sentry store API"
  retention: "Better Stack Logs default; Sentry event retention"
discoverability_test:
  command: "scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh  (Sentry API: count op:image-pull pull_result:auth_denied since deploy) ; curl -s https://app.soleur.ai/health | jq .version"
  expected_output: "auth_denied count == 0 over the soak; .version advanced past the frozen build — NO ssh"
```

### Follow-Through Enrollment (soak-gated close — plan Phase 2.9.1)

- **Script:** `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` — exit 0
  when Sentry reports zero `op:image-pull pull_result:auth_denied` events since a
  `start=` pinned strictly after deploy (mirror
  `reconcile-ff-only-sentry-4977.sh`).
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh earliest=<deploy+3d> secrets=SENTRY_* -->`
  on #6400 + the `follow-through` label.
- **Sweeper wiring:** add any new `secrets=` to
  `.github/workflows/scheduled-followthrough-sweeper.yml` (reuse existing
  `SENTRY_*` if already wired).

## Infrastructure (IaC)

No new Terraform resource, secret, vendor, cron, DNS, or host. Delivery uses the
**existing** auto-apply path:

- **Terraform changes:** none. `ci-deploy.sh` is a host-resident script hashed in
  `server.tf`'s `terraform_data.deploy_pipeline_fix` `triggers_replace`.
- **Apply path:** `apply-deploy-pipeline-fix.yml` fires on merge (paths filter
  already includes `ci-deploy.sh`) and delivers the new script over HTTPS
  `/hooks/infra-config` (no SSH, no image pull needed to land it). The workflow's
  "Redeploy to load applied profile" step no-ops for a script-only change
  (seccomp unchanged); the concurrent/next `web-platform-release` deploy exercises
  the new recovery path. (The boot-path `cloud-init.yml` parity was cut to a
  follow-up — Phase 4; it would land only on host recreate anyway.)
- **Drift / distinctness safeguards:** the running fleet is recovered by the
  re-fetch at deploy time (baked snapshot is a cache); no state file touched.
- **Vendor-tier reality check:** none — no provider resource created.

## Architecture Decision (ADR/C4)

This records a **credential-recovery contract** for the interim GHCR pull path.
Per the architecture review (P2-C), the live normative MUST is homed in **ADR-096**
(which owns the interim GHCR break-glass path), NOT buried in the `superseded`
ADR-088.

### ADR

- **ADR-096 (normative, primary):** add to the interim-GHCR-path section: *"On the
  interim GHCR pull path, login-success is not proof of pull capability. A
  credential that `docker login`s but cannot `docker pull` (a GitHub App
  installation token, or any login/pull capability split) makes login-outcome-gated
  recovery a false gate. The host MUST re-fetch the `prd` cred + relogin + retry the
  pull once on a `docker pull` **auth-denial**, not only on a login **failure** —
  until zot retires this path."*
- **ADR-088 (factual note only):** in its existing staleness section, cross-link
  the above with the factual "why" (App installation tokens can't pull GHCR).
  Status stays `superseded`; it does not carry a current-governing MUST.
- **AP-016 register update:** see Phase 5 (P2-D).

### C4 views

**No C4 impact.** Enumeration checked against all three `.c4` files: external
human actors (operator, untrusted PR author — unchanged); external systems
(`ghcr` `model.c4:254` already modeled with the authenticated `hetzner -> ghcr`
`read:packages` pull edge `:380`; `zotRegistry` `:258`; `doppler` already
modeled) — no new vendor/system; data stores (Doppler `prd` already modeled) —
none new; access relationships — the host→GHCR authenticated pull edge already
exists; this change alters only *how the host recovers the credential within that
existing edge*, not the topology. No element, tag, or `view include` line changes.

### Sequencing

The ADR amendment + code land together in this PR.

## Domain Review

**Domains relevant:** engineering (infrastructure) only.

Infrastructure/tooling reliability change to a host-resident deploy script. No
user-facing surface, no UI file in Files-to-Edit (mechanical UI-surface override
does not fire), no schema/migration/auth-flow, no pricing/legal/marketing/support
implication.

### Product/UX Gate

**Tier:** none — no UI surface (no `components/**`, `app/**/page.tsx`, or
UI-surface path in Files-to-Edit).

Cross-cutting engineering review is provided by deepen-plan's research triad
(data-integrity / security / architecture) and the standard `/review` panel at PR
time (credential-handling diff → security-sentinel + observability-coverage-reviewer
will run).

## Open Code-Review Overlap

None — no open `code-review`-labeled issue names `ci-deploy.sh`,
`cloud-init.yml`, or the ADR/learning files in scope (verify at /work with the
two-stage `gh issue list --json` + standalone `jq --arg` pattern before freezing).

## Test Scenarios

1. **login-ok / pull-deny → recovered:** mock `docker login` success + first
   GHCR pull `denied` + second pull success ⇒ deploy proceeds (AC1). *This is the
   scenario `main` fails.*
2. **login-ok / relogin-ok / retry-pull still denies:** recovery attempted,
   `prd` cred also cannot pull ⇒ `image_pull_failed`, fail-open, single
   `pull_failure_event` tagged `recovery_stage=pull_still_denied` (AC2/AC5).
3. **relogin fails:** `refetch_ghcr_and_relogin` returns non-zero, retry pull NOT
   attempted, `pull_failure_event` tagged `relogin_failed` (AC14).
4. **§1A path unchanged:** baked `docker login` FAILS → §1A (now via
   `refetch_ghcr_and_relogin`) recovers → login ok → pull ok. Regression parity
   with existing §1A tests.
5. **zot active, zot pull fails:** atomic GHCR fallback still works; recovery
   does not fire on the zot leg (AC4).
6. **token hygiene + no-stderr-leak:** grep-assert `--password-stdin`-only +
   local + unset; recovery event payload built with `jq -n --arg`, no raw
   stderr (AC6).
7. **cosign continuity:** recovered pull's login writes `$GHCR_DOCKER_CONFIG`;
   the `:ro`-mounted verify leg authenticates (AC13).

## Alternatives Considered

| Alternative | Why not (now) |
|---|---|
| Re-bake fresh creds via full `apply-web-platform-infra` / host recreate | Requires a human-run apply; transient (bakes another snapshot that re-stales), and does not fix the structural login-ok/pull-deny gap. `ignore_changes=[user_data]` means only recreate re-bakes. Rejected as the durable fix; recovery-at-pull is substrate-independent. |
| Inject/verify `DOPPLER_TOKEN` in the deploy exec context | Premise false — the token is present and `prd`-scoped (Research Reconciliation). No-op. |
| Probe-pull inside `ghcr_prelude_and_login` to test pull capability after login | Wasteful extra pull on every deploy; recovering at the real pull site is simpler and covers zot/ghcr uniformly. |
| Wait for zot (#6122/ADR-096) to retire GHCR | Correct long-term substrate fix, but it is soak-gated and does not unfreeze prod now; GHCR stays break-glass through soak, so the interim path must be hardened regardless. |
| Enable the ADR-088 minter | Superseded/infeasible — App tokens can't pull GHCR. Minter stays disabled. |

## Sharp Edges

- The fix is **fail-open by contract**: a recovery miss MUST leave the exact
  `final_write_state 1 "image_pull_failed"` terminal state as today — never a new
  failure mode. Assert in AC2.
- **Do not** auth-recover the zot pull leg — recovery is GHCR-credential-scoped;
  zot-down is already handled by the atomic GHCR fallback.
- Retry the pull **exactly once** — no loop (a loop against a genuinely-invalid
  `prd` cred would burn the deploy window).
- Reuse `pull_failure_event`'s classifier regex via one extracted predicate — a
  second copy will drift (`cq`/paren-safety class).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  deepen-plan Phase 4.6 — this one is filled.
- The `cloud-init.yml` parity fix (Phase 4) lands only on host recreate — do not
  claim it recovers running hosts.
