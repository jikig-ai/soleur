---
title: "Container-registry write-path topology — should CI push zot-first and demote GHCR?"
date: 2026-08-04
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: ["#7247", "#7248"]
adrs: ["ADR-167 (new)", "ADR-096 (amended)", "ADR-088 (reasoning clarified)"]
status: draft
---

# Container-registry write-path topology (zot-primary write path)

## Overview

The brief asked: *given GHCR is not readable, not a fallback, and not a refill source,
should CI push directly to zot and demote GHCR to a best-effort archive whose failure is a
warning rather than a release blocker?*

**Answer: no — not as the response to this incident.** Three of the four premises in that
question are false or overstated against what this session measured, and the change would
have prevented **zero** of the four release failures on 2026-08-04. The measured, persistent
release blocker is the **zot leg**, not GHCR.

This plan records the evidence, answers the question with a decision (ADR-167), corrects the
architecture record where it is wrong, and prescribes the **one** change the evidence
actually supports: a bounded retry on the GHCR push for its measured failure class.

> **Verification posture.** Everything below was re-measured in this session. Where a claim
> came from the originating brief and did not survive re-measurement, it is recorded in
> `## Research Reconciliation` with the measurement that falsified it. No conclusion is
> inherited.

---

## Premise Validation (Phase 0.6)

| Cited premise | Probe | Result |
|---|---|---|
| PR #7244 in flight on a sibling branch | `worktree-manager.sh cleanup-merged` | **Stale** — merged; worktree auto-removed. ADR-166 is on `main`. Read from `main`, not as in-flight. |
| #7247 OPEN | `gh issue view 7247` | **Holds.** Title: *"zot is crash-looping on the registry host (~4 restarts/min since 17:08 UTC 2026-08-03) — the active cause of the release blockage"* |
| #7248 OPEN | `gh issue view 7248` | **Holds.** |
| ADR-096 / ADR-088 / ADR-062 / ADR-166 exist | `ls .../decisions/` | **All four present.** |
| Run 30913993850 failed at "Build and push Docker image" | `gh run view --json jobs` | **Falsified for the run's final state** — see reconciliation R1. |
| 403 root cause UNKNOWN | attempt-1 log body | **Falsified — it is measured.** See R2. |

Next free ADR ordinal against freshly-fetched `origin/main`: **167** (highest present: 166).
Provisional per `/ship`'s collision gate.

---

## Research Reconciliation — brief vs. measured reality

| Brief's claim | Measured reality | Plan response |
|---|---|---|
| **R1.** Run 30913993850 "failed at *Build and push Docker image*"; "the zot mirror step never ran." | The run is `run_attempt: 2`. The re-run the brief was waiting on **completed at 13:54:56Z**. On attempt 2 the GHCR build+push **succeeded** (cosign pushed the signature to `ghcr.io/jikig-ai/soleur-***@sha256:4cc17eba…` at 13:52:04Z) and the job died at **"Mirror image GHCR→zot (crane) + cosign-sign the zot digest"**. The mirror step ran, three times, and failed three times. | The premise inverts. Plan is built on the zot leg being the blocker. |
| **R2.** "The 403's root cause is UNKNOWN… Record it as unknown unless you measure it." | **Measured.** The brief's quote was truncated one character before the body that names the cause. Attempt 1, `21_Build and push Docker image.txt:802`: `denied: permission_denied: Error from intermediary with HTTP status code 403 "Forbidden" - with-body: { "documentation_url": ".../rest/overview/rate-limits-for-the-rest-api#about-secondary-rate-limits", "message": "You have exceeded a secondary rate limit. Please wait a few minutes before you try again." }` | Root cause = **GitHub secondary rate limit**. Transient by construction; the response body prescribes its own remedy ("wait a few minutes"), and the re-run confirmed it. This is the only change the 403 evidence supports (Phase 2). |
| **R3.** "`Docker login` SUCCEEDED; the push was denied — authenticate-but-not-authorize." | The framing is not supported. GHCR returns `denied: permission_denied` as its **generic wrapper for a rate-limited push**, not an authorization decision. The `Error from intermediary` prefix marks it as an edge/proxy response, not a permission evaluation. | Do not plan against an authorization defect. There is none. Explicitly noted in ADR-167 as the ADR-166 failure mode the brief itself reproduced. |
| **R4.** "GHCR… can block 100% of releases while serving **zero reads**." | **False.** GHCR serves at least two real reads: (a) the release job's own `crane copy ghcr.io/… → 127.0.0.1:5000` — visible in the run log as `Copying from ghcr.io/jikig-ai/soleur-***:v0.249.5 to 127.0.0.1:5000/…` with `existing blob:` lines, i.e. a **successful authenticated GHCR read**; (b) `inngest -> ghcr` (ADR-136) — the config-refresh bundle is pulled **GHCR-direct** by the Inngest host. | Corrected in ADR-167 §Context and in `model.c4`. |
| **R5.** "the zot 60 GB store re-fills ONLY from a fresh CI dual-push — **NOT from GHCR**." | The C4 sentence is quoted accurately, but it is about the **host** pull-fallback path, and it is contradicted by the release workflow's own recovery instruction. `reusable-release.yml` `degraded()` detail: *"zot did not receive this image; backfill via `crane copy GHCR→zot && cosign sign --yes <zot>@<digest>`, then re-run."* That **is** a GHCR→zot refill. | The distinction that reconciles both: **hosts** cannot read GHCR; **CI** can. Stated precisely in ADR-167; `model.c4` line 272 amended. |
| **R6.** ADR-088 arm-b ⇒ "no zero-touch GHCR pull credential CAN exist, only a personal one." | **Holds, but is scoped to hosts.** In-workflow, `GITHUB_TOKEN` under the job's `packages: write` (verified at `reusable-release.yml:119`) reads the repo's own packages fine — which is why the crane copy works at all. | ADR-088's reasoning is not reopened; its **scope** is stated explicitly. No personal credential is proposed. |
| **R7.** "The last green release (30903635026, 11:09Z) pushed to GHCR fine; only two commits landed between it and the failure." | Both halves true, but the surrounding pattern is not "green until 13:28". Of the 12 most recent release runs, **8 failed**. The two runs immediately *before* the green one (30900564194 @10:25Z, 30902554446 @10:54Z) both failed at the **zot mirror step** with the same signature. | The "two commits changed something" framing is dropped. Nothing in the diff is implicated. |
| **R8.** `docker_image: "ghcr.io/jikig-ai/soleur-web-platform"`; steps at ~L740 / ~L818 / ~L844; `packages: write` declared. | **All verified exactly.** `web-platform-release.yml:87`; `reusable-release.yml:740, 818, 844`; `permissions.packages: write` at `:119`. | Carried forward unchanged. |
| **R9.** Registry host is "cx33, 4 vCPU / 8 GB" with an "ADR-062 `--memory=7168m` cap" (`model.c4:272`). | **Stale.** `zot-registry.tf:54` — *"soleur-registry is GRANDFATHERED on its cx23"*; the cap is now **derived** (`registry_memory_cap_mb = server_type.memory * 1024 - reserve`, `:83`), not a constant. Live telemetry agrees with the Terraform, not the C4: `mem_total_mb=3819`, `zot_memory_cap_mb=3072`. | C4 correctness fix folded into this plan's `### C4 views` task. Not a config defect — a documentation drift. |
| **R10.** (Found while verifying my own citations, not claimed by the brief.) The config-refresh channel is "ADR-136" per `model.c4:507,513,514,515`. | **Wrong ordinal.** ADR-136 is `ADR-136-preapply-entrypoint-enumeration-gate.md`. The config-refresh channel is **ADR-135** — the only ADR in the corpus containing `6780`, the issue those same C4 lines cite. | Corrected in `### C4 views` item 4. Caught by resolving every `ADR-*.md` link in the new ADR against disk before shipping it — the same check first caught this plan's *own* draft inventing an ADR-136 filename with an `inngest-config-refresh-channel` slug that does not exist. (Slug deliberately not written as a resolvable filename token here: AC13 scans this file, and a literal example would false-fail its own gate — the self-reference trap in `cq-assert-anchor-not-bare-token`.) |

---

## Hypotheses (L3→L7 — `hr-ssh-diagnosis-verify-firewall`, gate fired on `403` / `handshake` / `connection reset`)

The checklist mandates L3→L7 ordering **before** any service-layer hypothesis. Verified this session:

| Layer | Verification | Result |
|---|---|---|
| **L3 — firewall allow-list** | N/A by design, and stated rather than skipped: the registry host is deny-all-public (`model.c4:272`) and is reached **only** through the CF Tunnel (`tunnel -> zotRegistry`, `model.c4:457`). There is no operator-egress allow-list on this path, so admin-IP drift (#2681 class) cannot be the cause. | **Not applicable — excluded on architecture, not on assumption.** |
| **L3 — DNS / routing** | `dig +short registry.soleur.ai` → `188.114.96.2`, `188.114.97.2` (Cloudflare anycast). | **Healthy.** |
| **L7 — TLS / proxy / Access** | `curl -sI https://registry.soleur.ai/v2/` → `HTTP/2 403`, `server: cloudflare`, `cf-ray: a25e1d650e9fd540-CDG`, `cf-access-aud: 3162f272…`, `cf-access-domain: registry.soleur.ai`. | **Healthy.** Edge terminates TLS and Cloudflare Access enforces as designed (403 without a service token is the *correct* response to an unauthenticated probe). Access is **admitting** CI's tokened requests — the bridge's `docker login 127.0.0.1:5000` **succeeded** at 13:52:16Z. |
| **L7 — origin dial** | cloudflared teardown log, run 30913993850: `ERR failed to connect to origin error="websocket: bad handshake" originURL=https://registry.soleur.ai` ×4 (13:52:17Z–13:52:24Z). Same signature in run 30902554446 (11:03:48Z). | **FAILING — this is the layer.** |
| **L7 — service (zot container)** | Self-pulled `SOLEUR_ZOT_DISK` via `betterstack-query.sh` (Doppler `prd_terraform`), 13:35–14:00Z: `zot_restarts` **4827 → 4845 → 4871 → 4888 → 4910 → 4938** = **111 restarts in 25.0 min ≈ 4.44/min**, constant `boot_id=c60e54b7…` (the *container* is restarting, the host is not). | **CONFIRMED as the failing component. Matches #7247's stated rate.** |

**Cause of the restarts: UNMEASURED — and deliberately not named here.** The telemetry
positively **excludes** the two obvious candidates: `zot_oom_kills=0`, `oom_killed=false`,
`oom_kills_5m=0`, `exit_code=0` (clean exits, not OOM kills), and `pcent=54` / `resize_ok=true`
(disk is not full). Per ADR-166, this plan names no further cause. Attribution is **#7247's**
deliverable, not this plan's; see `## Non-goals`.

**#7248 demonstrated live:** the same payload carries `ping_rc=0` and `state_status=running`
while every push failed. A registry restarting 4.4×/min graded **GREEN** on the read-path
verdict throughout.

---

## The question, answered

### What a GHCR demotion would have prevented

| Run | Time | GHCR push | zot mirror | Would GHCR-demotion have saved it? |
|---|---|---|---|---|
| 30900564194 | 10:25Z | ✅ | ❌ | **No** |
| 30902554446 | 10:54Z | ✅ | ❌ | **No** |
| 30913993850 att.1 | 13:28Z | ❌ (rate limit) | skipped | **No** — zot was crash-looping (4827 restarts, climbing) at that moment |
| 30913993850 att.2 | 13:43Z | ✅ | ❌ | **No** |

**Zero of four.** In every measured case zot failed. GHCR failed once, transiently, from a
self-documenting rate limit that resolved on retry. A topology change that demotes GHCR
addresses the leg that worked and leaves untouched the leg that did not.

### Why the "GHCR is a pure liability" framing does not hold

GHCR is not on the critical path *for nothing*. It is the **staging copy that makes recovery
possible**. Today, when the zot leg fails, the image still exists in GHCR, and the workflow's
own `degraded()` message prescribes exactly that recovery:

> `backfill via 'crane copy GHCR→zot && cosign sign --yes <zot>@<digest>', then re-run.`

That path requires GHCR to hold the image **and** requires a working GHCR *read* — which CI
has. Remove the GHCR leg and that recovery path is deleted along with it.

### Options

| # | Option | Verdict |
|---|---|---|
| 1 | **Push zot-first, GHCR best-effort** (`continue-on-error`) | **Reject.** Not the "smallest change" it appears to be: GHCR is not a separable *leg* — it is the buildx `push: true` **output target** (`reusable-release.yml:740-746`). Making it best-effort requires re-targeting the build (OCI-layout export or a zot-direct push) first, so this collapses into option 2's cost. It also inverts the ordering so the *full image upload* traverses the crash-looping origin instead of a digest-preserving crane copy from a staged source. |
| 2 | **Build and push directly to zot; drop the crane hop** | **Reject — actively harmful today.** (a) Deletes the documented `crane copy GHCR→zot` backfill by deleting its source. (b) Pushes the entire image through the CF tunnel into the origin that is currently failing, with no staged copy anywhere if it fails. (c) Trades one registry's *transient, retryable, self-documenting* failure for total dependence on one that has failed 3+ consecutive times today. |
| 3 | **Keep dual-push, make the GHCR leg non-blocking** | **Reject as framed** (same L740 structural objection as option 1), **but its intent is partially adopted**: the *measured* GHCR failure class is made non-blocking the correct way — by retrying it — rather than by ignoring it. Ignoring a GHCR push failure would silently ship a release whose only image copy is in a crash-looping registry, removing the backfill source precisely when it is needed. |
| 4 | **Treat the 403 as a credential defect to repair** | **Reject — there is no credential defect.** The 403 is a secondary rate limit (R2). Repairing a credential that is working would be the exact ADR-166 failure: acting on a cause nobody measured. |
| **5** | **Keep dual-push; retry the GHCR push on its measured failure class; fix the actual blocker (#7247) and the health-verdict gap (#7248) as their own work** | **ADOPT.** |

### Does this plan depend on #7248?

**No — and that is a consequence of the decision, not an accident.** #7248 (read-path-only
health verdict) becomes materially *more* dangerous under a zot-primary write path, because
the write path would then have no independent verdict at all. By **not** adopting zot-primary,
this plan does not take on that dependency.

#7248 remains independently worth fixing — this session watched it mislead in real time
(`ping_rc=0` throughout a 4.4/min crash loop) — but it is not a blocker for anything here, and
this plan does not claim it as a deliverable.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a release that reports success while the image
never reached the registry hosts pull from — production silently stays on the previous version,
or a deploy fails `image_pull_failed` and `app.soleur.ai` serves nothing. This is the
v0.244.1 shape (~5h undeployable, #7071).

**If this leaks, the user's data is exposed via:** no new exposure surface. This plan adds no
data path, no credential, and no external egress. The retry added in Phase 2 wraps an
already-authenticated push to an already-configured registry.

**Brand-survival threshold:** `single-user incident` — the release pipeline is the only path by
which any fix reaches the single production user. A wrong decision here does not degrade a
feature; it removes the ability to ship at all.

**CPO sign-off required at plan time before `/work` begins.** `user-impact-reviewer` will be
invoked at review time.

---

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-167 — "The container-registry write path stays dual-push; GHCR is CI's backfill
source, not a demotable archive."** Provisional ordinal (next free vs. freshly-fetched
`origin/main`; re-verified by `/ship`'s collision gate).

It records: the measured 403 cause; the measured blocker; the rejection of options 1–4 with
reasons; the corrected GHCR read-scope; and an explicit **revisit trigger** so this is a
decision with an expiry condition rather than a closed door.

**Amend ADR-096 in place** (no new ordinal). The 2026-07-30 amendment's supporting sentence
*"GHCR still receives every image but nothing can read it back"* is true of **hosts** and false
of **CI** — and CI's read is what the amendment's own backfill remedy depends on. Amend to say
so; the amendment's *conclusion* (the mirror is release-blocking) is unchanged and correct.

**ADR-088:** reasoning **clarified, not reopened.** Arm-b's finding stands exactly as written.
Add one scoping sentence: it is a statement about *host-side zero-touch* credentials, and does
not bear on CI's in-job `GITHUB_TOKEN` read. **No personal credential is proposed anywhere in
this plan** — that class stays retired.

**ADR-062:** no change. Referenced only because `model.c4:272` attributes a stale `7168m`
constant to it; the drift is in the C4 text, not in ADR-062.

### C4 views

Checked **all three** model files (`model.c4`, `views.c4`, `spec.c4`) per the completeness
mandate — not a keyword grep.

*Enumeration performed:* external human actors (none added — this is a CI-internal path);
external systems (`ghcr`, `sigstore`, `betterstack`, `tunnel` — **all already modeled**);
containers/data stores (`zotRegistry` — **modeled**); access relationships (`github -> ghcr`,
`github -> tunnel`, `tunnel -> zotRegistry`, `hetzner -> zotRegistry`, `hetzner -> ghcr`,
`inngest -> ghcr` — **all already modeled**). **No new element and no new edge is required**, so
no `views.c4` `include` line changes and no `spec.c4` change.

Three **description corrections** are in scope, because this change falsifies them:

1. `model.c4:268` (`ghcr`) — *"It receives every image and can serve none"* is false. It serves
   CI's backfill read and the ADR-136 config-bundle host read. Correct to scope the dead read
   to **hosts**.
2. `model.c4:272` (`zotRegistry`) — *"re-fills ONLY from a fresh CI dual-push — NOT from GHCR"*
   → scope to the host pull path, and name the CI `crane copy` backfill the release workflow
   already prescribes.
3. `model.c4:272` (`zotRegistry`) — **stale host spec** (R9): "cx33, 4 vCPU / 8 GB" and the
   `--memory=7168m` constant → cx23, derived cap, per `zot-registry.tf:54,83` and live
   telemetry (`mem_total_mb=3819`, `zot_memory_cap_mb=3072`).
4. `model.c4:507, 513, 514, 515` — **wrong ADR ordinal** (R10). These cite the config-refresh
   channel as "ADR-136"; ADR-136 is `ADR-136-preapply-entrypoint-enumeration-gate.md`. The
   config-refresh channel is **ADR-135**
   (`ADR-135-pull-based-signed-config-refresh-for-dedicated-inngest-host.md`, which is also the
   only ADR containing `6780`, the issue those same lines cite). Correct these four to ADR-135.

**Deliberately NOT fixed (scope discipline):** `model.c4` also cites "ADR-136" at lines 260,
264, 362, 474, 475 for a **third** subject — Web Push / statutory-triage notification fallback.
That cluster is outside this plan's evidence chain, and a quick grep of the decisions directory
surfaced **no** ADR that clearly owns the Web Push fallback, so the correct ordinal is *not
established*. Recording it as an observation to verify separately rather than guessing —
asserting a replacement ordinal I have not confirmed would be the same defect as R10 itself.
Line 470's "ADR-136" (Cloudflare rulesets read-only GETs) **is correct** and must not be
touched — it genuinely is the pre-apply entrypoint gate.

Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing.

---

## Observability

```yaml
liveness_signal:
  what: "release job outcome + steps.zot_mirror.outcome (already load-bearing since #7242 —
         degraded() exits non-zero and the step no longer carries continue-on-error)"
  cadence: "per merge to main touching apps/web-platform/**"
  alert_target: "release-outcome job → ops@jikigai.com (Resend) + GitHub Checks annotation"
  configured_in: ".github/workflows/reusable-release.yml (release-outcome job)"

error_reporting:
  destination: "GitHub Actions ::error:: annotation + $GITHUB_STEP_SUMMARY + release-outcome email"
  fail_loud: true   # degraded() exits non-zero; no continue-on-error on the mirror step

failure_modes:
  - mode: "GHCR push hits a GitHub secondary rate limit (the measured 2026-08-04 class)"
    detection: "NEW in Phase 2 — the retry wrapper emits ::notice::ghcr push attempt N/M failed
                (rc=…); retrying in Ns, so a rate-limited push is VISIBLE even when it then
                succeeds. Today this class is invisible unless it exhausts the job."
    alert_route: "Checks annotation; escalates to the existing release-outcome email only if
                  all attempts are exhausted"
  - mode: "GHCR push fails for a NON-retryable reason (real authz change, repo/package deleted)"
    detection: "retry exhausts, buildx exits non-zero, docker_build.outcome != success →
                mirror step skips its gate and the release job fails"
    alert_route: "release-outcome email + Checks annotation"
  - mode: "zot mirror fails (the measured active blocker)"
    detection: "degraded() → mirror_status/mirror_reason outputs + ::error:: + step summary;
                registry-host state via SOLEUR_ZOT_DISK (zot_restarts, exit_code, oom_kills)"
    alert_route: "release-outcome email; standing recurrence alarm
                  scheduled-zot-restart-loop.yml (*/30) files a [ci/zot-restart-loop] issue"

logs:
  where: "GitHub Actions run logs (90d); SOLEUR_ZOT_DISK → Better Stack Logs source 2457081
          (hot window ~40min via remote(), older rows in the s3 archive)"
  retention: "Actions 90d; Better Stack per source retention + s3 archive"

discoverability_test:
  command: |
    gh run list --workflow=web-platform-release.yml --limit 5 \
      --json databaseId,conclusion,displayTitle
    gh run view <id> --json jobs \
      --jq '.jobs[] | select(.conclusion=="failure") | .steps[] | select(.conclusion=="failure") | .name'
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      --since 3h --grep SOLEUR_ZOT_DISK --limit 6
  expected_output: "The failing STEP NAME (distinguishing the GHCR leg from the zot leg) and the
                    registry host's zot_restarts series — with no remote-shell access."
```

No remote-shell verb appears in any command above. **Every diagnostic in this plan was obtained
this way** — the run logs, the attempt-1 error body, and the restart series were all self-pulled
(`hr-no-dashboard-eyeball-pull-data-yourself`).

### Soak follow-through enrollment

**Not required.** No acceptance criterion in this plan is time-gated: there is no
`adopting → accepted` flip and no "stays at ~0 for N days" close condition. ADR-167 is
`accepted` on merge, because it records a decision **not** to change the topology — there is
nothing to soak. The revisit trigger is event-driven (a non-retryable GHCR block), not
elapsed-time-driven, so it is stated in the ADR rather than enrolled as a probe.

---

## Implementation phases

Ordered so contract changes precede consumers.

### Phase 1 — Record the decision (no code)

1.1 Write `ADR-167-container-registry-write-path-stays-dual-push.md` (status `accepted`).
1.2 Amend ADR-096's 2026-07-30 amendment in place — scope "nothing can read it back" to hosts;
    note CI's read is what the amendment's own backfill remedy depends on. Conclusion unchanged.
1.3 Add the one scoping sentence to ADR-088 arm-b.
1.4 Correct the three `model.c4` descriptions (§C4 views). Run the two c4 tests.

### Phase 2 — The one change the evidence supports

2.1 Wrap the GHCR push in a bounded retry for the measured secondary-rate-limit class.
    `docker/build-push-action` has no native retry, so the shape is a `retry()` wrapper —
    **reuse the one already in this file** at the mirror step (`n=1 max=3`, `sleeps=(0 5 15)`)
    rather than inventing a second idiom.
    - **Backoff must suit the failure.** GitHub's own body says *"wait a few minutes."* The
      mirror step's 5s/15s is tuned for a TCP reset, not a rate limit. Use longer waits
      (e.g. `0 60 180`) and state the number in the code comment with the body quoted.
    - **Retry only the retryable.** Gate on the response signature (`secondary rate limit` /
      HTTP 403 carrying the rate-limit `documentation_url`). A blanket retry would paper over a
      genuine authz change — the exact "name a cause you measured" discipline of ADR-166,
      applied to a remedy instead of a message.
2.2 Emit `::notice::` per retry attempt so a rate-limited-but-recovered push is visible
    (today it is invisible unless it exhausts the job).
2.3 Extend `scripts/` test coverage for the classifier if 2.1 lands as a sourced helper
    (mirroring `scripts/zot-mirror-diagnosis.sh` + its suite, registered in `test-all.sh`).

### Phase 3 — Verification

3.1 `actionlint` on the changed workflow; `bash -c` on the extracted `run:` snippet
    (**not** `bash -n` on the YAML).
3.2 c4 syntax + render tests.
3.3 `bash test-all.sh` (or the scripts group) if 2.3 added a suite.

---

## Acceptance criteria

### Pre-merge (PR)

- **AC1** `ADR-167-*.md` exists with status `accepted`, and its `## Decision` names the
  measured 403 cause (secondary rate limit) and the measured blocker (zot leg).
- **AC2** ADR-096 contains an amendment scoping "nothing can read it back" to hosts.
  `grep -c 'hosts'` on the amended paragraph ≥ 1.
- **AC3** ADR-088 contains the host-scope sentence, and no ADR touched by this PR **proposes**
  reintroducing a personal credential. Assert on the proposal, not on the token string —
  historical citations of the *revoked* credential are expected and must not fail this AC.
- **AC4** `model.c4` no longer contains the literal `can serve none`; and
  `grep -c 'cx33' model.c4` == 0.
- **AC5** `model.c4` `zotRegistry` description contains `cx23` and does **not** contain `7168m`.
- **AC6** `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
- **AC7** The GHCR push retry exists and is **conditional**: the changed region contains both
  a retry construct and a rate-limit signature match. A blanket unconditional retry fails this AC.
- **AC8** `actionlint .github/workflows/reusable-release.yml` clean; the extracted `run:`
  snippet passes `bash -c`.
- **AC9** Full-suite exit gate green (`test-all.sh`).
- **AC10** No `continue-on-error` is added to, and none is removed from, the
  `zot_mirror` step. (This plan explicitly does **not** relax the #7242/ADR-096 blocking gate.)
- **AC11** PR body uses `Ref #7247` / `Ref #7248` — **not** `Closes` — since neither is
  resolved by this plan.
- **AC12** The four config-refresh C4 lines cite ADR-135, and line 470 still cites ADR-136:
  ```bash
  awk 'NR==507||NR==513||NR==514||NR==515' knowledge-base/engineering/architecture/diagrams/model.c4 \
    | grep -c 'ADR-136'   # expect 0
  awk 'NR==470' knowledge-base/engineering/architecture/diagrams/model.c4 \
    | grep -c 'ADR-136'   # expect 1  (correct citation — must NOT be rewritten)
  ```
  Line numbers are brittle across edits — re-anchor to content (`config-refresh bundle`,
  `rulesets API`) if the file shifts, per `cq-cite-content-anchor-not-line-number`.
- **AC13** **Every** `ADR-*.md` link in every file this PR touches resolves on disk:
  ```bash
  git diff --name-only origin/main...HEAD -- '*.md' \
    | xargs -r grep -ohE 'ADR-[0-9]+[A-Za-z0-9._-]*\.md' | sort -u \
    | xargs -rI{} bash -c '[[ -f knowledge-base/engineering/architecture/decisions/{} ]] || echo "BROKEN: {}"'
  ```
  Expect no output. This is the gate that caught R10; it must run on every future ADR edit.

### Post-merge (operator)

None. Every step is automatable in-session or in CI.
*(Automation feasibility checked per the plan gate: ADR/C4/workflow edits are file edits;
verification is `actionlint` + `bun`/`vitest` + `gh`; telemetry is `betterstack-query.sh`.
Nothing here needs a browser, a vendor console, or host access.)*

---

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| **The retry masks a future real authz failure.** | The retry is gated on the rate-limit signature (AC7). A non-matching 403 fails immediately, as today. |
| **Deciding "no change" reads as "nothing to do," and #7247 stalls.** | This plan closes nothing. #7247 and #7248 stay OPEN with `Ref`, and #7247 already carries the standing `scheduled-zot-restart-loop.yml` recurrence alarm. `## Non-goals` names the boundary explicitly. |
| **The C4 "cx23" correction is itself stale** (host could be resized later). | Anchor the description to the **derivation** (`server_type` × memory − reserve, `zot-registry.tf:83`) rather than restating a constant — the same class of drift that produced R9. |
| **A future reader re-litigates the topology from the same false premises.** | ADR-167 records the four premises and the measurement that falsified each, so the next reader starts from evidence rather than from the framing. |
| **Rate-limit pressure worsens** (more parallel workflows → more GHCR pushes). | The `::notice::` per attempt (2.2) makes the frequency measurable. The ADR's revisit trigger fires on *repeated* GHCR blockage — with data, not impression. |

---

## Non-goals (explicitly out of scope)

- **Diagnosing why zot restarts.** #7247 owns this. This plan measured the *rate* (4.44/min)
  and *excluded* OOM and disk-full; it names no cause beyond that (ADR-166).
- **Fixing the read-path-only health verdict.** #7248 owns this. This plan does not depend on it.
- **The registry host's LUKS at-rest posture** (code-declared / live-pending, #6929) — untouched.
- **The ADR-136 config-refresh channel.** Noted as evidence that GHCR serves reads (R4);
  its own topology is not changed here. *(One observation logged for #7248's owner or a
  follow-up: `model.c4:268` says no zero-touch GHCR **pull** credential can exist, while
  `inngest -> ghcr` describes a GHCR-direct host pull. Both may hold if that edge is still
  `ADOPTING` and not yet live — but it is an unresolved tension in the record, not something
  this plan measured or fixes.)*

## Deferrals

No capability is deferred by this plan — it declines a proposed change rather than postponing
one, so there is nothing to track. The conditions under which the declined change should be
reconsidered are recorded as ADR-167's revisit trigger.

---

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering

**Status:** reviewed (inline — see the process note below)
**Assessment:** Release-pipeline topology with a `single-user incident` threshold. The
architectural call is to **preserve** a staging+mirror topology whose staging leg has a real,
currently-load-bearing purpose (backfill source), rather than collapse to a single registry
that is measurably the failing component. The evidence base is first-party measurement of four
runs, live host telemetry, and the workflow source. No new surface, credential, or egress.

### Product/UX Gate

**Not applicable.** No file in `## Files to Edit` matches the UI-surface term list or glob
superset — the changes are two ADRs, one `.c4` model file, one workflow, and optionally one
shell script. The mechanical UI-surface override does not fire; Product is NONE.

**Skipped specialists:** none required (no UI surface → `ux-design-lead` not applicable;
`wg-ui-feature-requires-pen-wireframe` does not fire).

### Gates skipped, with reasons

- **2.7 GDPR/compliance** — skipped. No regulated-data surface; no schema, migration, auth
  flow, or API route. None of triggers (a)–(d) fire: no LLM/external-API processing of
  operator data, no new cron reading `learnings/`, no new artifact distribution surface.
  (Threshold (b) `single-user incident` is declared — but it is declared about *release
  availability*, not about personal data, and this plan adds no data path.)
- **2.8 Infrastructure-as-Code routing** — skipped. No new server, service unit, cron, vendor
  account, DNS record, TLS cert, secret, or firewall rule is introduced. A detection scan over
  the plan text found no remote-shell invocation, no service-unit state change, no
  secret-write verb, and no vendor-console wording. All Doppler usage here is **read-only**
  (`doppler run` fronting the telemetry query), which the gate explicitly excludes.
- **2.11 Encryption posture** — skipped. Introduces no persistent store and no new
  cross-component connection. Files-to-Edit match none of `\.tf$`,
  `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`. The
  registry volume's posture is pre-existing and untouched (see Non-goals).

---

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` and matched each planned
path against the issue bodies.

**None.** No open `code-review` issue names `reusable-release.yml`, `web-platform-release.yml`,
`model.c4`, or any of the three ADR files.

---

## Files to edit

| Path | Change |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` | amend in place (host-scope the read claim) |
| `knowledge-base/engineering/architecture/decisions/ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md` | add host-scope sentence to arm-b |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | 3 description corrections (L268, L272) |
| `.github/workflows/reusable-release.yml` | conditional bounded retry + `::notice::` on the GHCR push |
| `scripts/` + `test-all.sh` | **optional** — only if 2.1 lands as a sourced classifier helper |

## Files to create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-167-container-registry-write-path-stays-dual-push.md` | the ADR |
| `knowledge-base/project/specs/feat-zot-primary-write-path/tasks.md` | task breakdown |

---

## Process note — deviations from the plan skill, and why

Two prescribed steps were **not** run, recorded here rather than passed off as done:

1. **No research subagents** (`repo-research-analyst`, `learnings-researcher`,
   `best-practices-researcher`, `framework-docs-researcher`) and **no multi-agent
   `plan-review` panel** (DHH / Kieran / code-simplicity / architecture-strategist /
   spec-flow-analyzer) were spawned. This session's operating instructions prohibit spawning
   agents unless the user requests them, and that instruction takes precedence over the
   skill's default. All research was performed directly.
   - *Consequence, stated plainly:* the `single-user incident` threshold normally escalates to
     a 5-agent panel, and this plan has **not** had that adversarial pass. Its central claims
     are first-party measurements with the commands inlined, so they are re-checkable — but a
     panel would independently probe the reasoning, and it has not. **Recommend running
     `/soleur:plan-review` (or `/soleur:deepen-plan`) before `/work`** if the operator wants
     that coverage; it is a one-word request.
2. **No Scoped Advisor Consult (Step 4.5)** — same reason.

Everything else in the skill (premise validation, network-outage gate + telemetry emission,
overlap check, User-Brand Impact, ADR/C4 gate, Observability, and the skip-with-reason gates)
was run.
