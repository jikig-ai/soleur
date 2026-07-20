---
title: "fix(infra): gzip git-data cloud-init user_data under Hetzner 32KB cap"
issue: 5927
type: bug
lane: cross-domain   # no spec.md exists for this branch → defaulted to cross-domain (TR2 fail-closed). Substantively single-domain (engineering/infra, CTO).
brand_survival_threshold: none
milestone: "Phase 4: Validate + Scale"
created: 2026-07-03
---

# fix(infra): gzip the git-data cloud-init `user_data` under Hetzner's 32,768-byte cap (#5927) 🐛

## Enhancement Summary

**Deepened on:** 2026-07-03 · **Agents:** framework-docs-researcher, architecture-strategist, code-simplicity-reviewer, security-sentinel.

**Key corrections applied from deepen review:**
1. **Decode path is CODE-CONFIRMED, not just "team idiom" (upgrade R1 grounding).** cloud-init's `DataSourceHetzner.py` calls `util.maybe_b64decode(ud)` with the comment *"Hetzner cloud does not support binary user-data. So here, do a base64 decode of the data if we can"* (added cloud-init 20.3, 2020-08-25, PR #448; Ubuntu 24.04 ships far newer). Chain: Hetzner stores the base64gzip string → `maybe_b64decode` → raw gzip bytes (magic `1f 8b`) → cloud-init auto-decompresses → byte-identical `#cloud-config`. Because Hetzner does **not** accept binary user-data, base64 is **mandatory** — so `base64gzip()` is the *only* viable gzip path, not merely one option. R1 downgraded from "primary unproven risk" to "confirmed by source; empirically re-confirmed at #5887 first provisioning (fail-closed)."
2. **[CRITICAL] The size-test must gzip REAL script content, not the `"x".repeat(N)` placeholder render.** A naive gzip of the x-substituted render collapses ~1000:1 (~1-2 KB) and would be non-discriminating — a re-inlining regression would gzip to near-nothing and never trip the budget. Fix: the gzip model reads the 5 script files from disk and base64s them for real (as `measure.mjs` did → 16,447 B gzip / ~21,929 B base64gzip), placeholder-substituting only the small secrets/ids (~600 B). See Phase 3 / AC4 / R2.
3. **AC3 `terraform console` is uncomputable pre-provisioning.** The template map injects `hcloud_volume.git_data.id`, `hcloud_volume.git_data_luks.id`, and `doppler_service_token.git_data.key` — all "known after apply" for a not-yet-created host, so `length(base64gzip(templatefile(...)))` returns `(known after apply)`. The corrected node test (real content) is the pre-merge byte gate; byte-exact is confirmed at #5887 provisioning. See Phase 2 / AC3.
4. **Dropped the throwaway-host boot smoke-test** (source-confirmed decode makes it unnecessary; it would also punch a temporary public-SSH hole through the host's deny-all ingress). #5887's fail-closed readiness check is the empirical gate. Dropped the Phase-0 "confirm base64gzip is a builtin" lookup step.
5. **Security: "no new exposure vector" CONFIRMED** (base64gzip is lossless encoding, not encryption; token equally recoverable from state/API as today; gitleaks scans git source where the token is only a TF reference). Forward-note added to the ADR amendment: a future control scanning tfstate/plan-output for secrets must base64gzip-decode first.

## Overview

A fresh Hetzner **git-data** host (`hcloud_server.git_data`, `apps/web-platform/infra/git-data.tf:105`) cannot be provisioned: its rendered cloud-init `user_data` is **~41,662 B — ~9 KB over Hetzner's 32,768-byte hard cap**. `git-data.tf:123` renders `cloud-init-git-data.yml` via `templatefile(...)`, injecting 5 `base64encode(file(...))` scripts (bootstrap, transport-wrapper, remove, provision, pre-receive-placeholder) whose base64 blobs alone total ~32,176 B. #5918 (LUKS/transport/remove/provision, merged) added the last three, tipping git-data over the cap; before #5918 it rendered ~28 KB (under cap), which is why #5921's plan scoped git-data out as "under cap, guard-only."

**Fix (measured, not assumed): wrap the whole render in Terraform's `base64gzip()`.** cloud-init natively decompresses gzip-compressed `user_data`. This is the CTO's recorded "gzip-first" direction (ADR-080 amendment 2026-07-02, scope-boundary note naming #5927). #5921 rejected gzip for the **web** host on **size** grounds only (web base64gzip measured 140,856 B — still 4.3× over), not mechanism — so `base64gzip()` is already the team's established Hetzner idiom. git-data's payload is highly compressible shell, so it compresses far better than web's.

**Measurement (this plan, reproduced with the size-test's exact modeling + real script bytes):**

| Form | Bytes | vs 32,768 cap |
|---|---|---|
| Raw rendered `user_data` (today) | 41,662 | ✗ +8,894 over |
| `gzip -9` of the render | 16,447 | ✓ under (16,321 headroom) |
| `base64gzip()` output (gzip → base64, what Hetzner stores) | ~21,929 | ✓ under (~10,839 headroom) |

`base64gzip()` output (~21.9 KB) is what the Hetzner API stores and what the 32,768 cap measures — under cap with ~10 KB headroom. **The R2/GHCR HTTPS-fetch fallback in the issue is NOT needed** (zero new infra, zero new egress dependency). It is retained only as a documented contingency if gzip ever proved insufficient (it does not — size fits) or if #5887's first provisioning were to reveal a decode failure (source analysis says it will not — see Risks R1).

**Zero content edits.** gzip-first wraps the *entire* rendered document — `cloud-init-git-data.yml` and all 5 injected scripts stay **byte-identical**. Only the `user_data =` expression in `git-data.tf` changes, plus the size-guard test's git-data assertion and an ADR-080 status update.

## Premise Validation (Phase 0.6)

All cited premises verified against `origin/main` + live `gh`; all held:

- **Files exist:** `git-data.tf`, `cloud-init-git-data.yml`, all 5 injected scripts (bootstrap 9,183 B; transport-wrapper 5,043 B; remove 4,738 B; provision 4,167 B; pre-receive-placeholder 997 B), and the size-guard test `plugins/soleur/test/cloud-init-user-data-size.test.ts` — all present.
- **#5918** MERGED (added transport-wrapper/remove/provision → the over-cap cause). **#5921** CLOSED via **PR #5922** (merged; web-host bake-and-extract fix + the size-guard test). **#5887** OPEN (git-data provisioning blocker — the `-target` allow-list / `moved` issue). **ADR-068** and **ADR-080** both exist.
- **`git-data.tf` carries NO `lifecycle.ignore_changes=[user_data]`** (confirmed, git-data.tf:153-156) and the host is not yet provisioned → the fix may freely edit the render; there is nothing running to force-replace.
- **Mechanism (`base64gzip()`) is confirmed by cloud-init source, not team deployment precedent.** *(Corrected at deepen review — do not overclaim.)* No `base64gzip` exists anywhere in `apps/web-platform/infra/*.tf` today; the **web** host passes `user_data` as **raw plaintext** (`server.tf:108`) and ADR-080's web base64gzip figure (140,856 B) was a *size-rejection measurement, never booted*. The real grounding is cloud-init's `DataSourceHetzner.maybe_b64decode` (see Enhancement Summary #1): Hetzner cannot accept binary user-data, so it base64-decodes the stored string before cloud-init, which then auto-gunzips. ADR-080 lines 229-234 record git-data as the "distinct-mechanism fix (gzip-first)" tracked in #5927; this plan implements that recorded direction with the source-confirmed decode path.
- **Own capability claim probed (`hr-verify-repo-capability-claim-before-assert`):** `hcloud_server.git_data` is **NOT** in the `apply-web-platform-infra.yml` `-target` allow-list (grep of the workflow: only `betteruptime_heartbeat.{github_*,inngest_prd}` appear; zero `git_data` targets). So merging this fix triggers the workflow (path filter `apps/web-platform/infra/**`) but the `-target`-scoped apply creates nothing for git-data — provisioning stays gated behind #5887.

## Research Reconciliation — Issue Claims vs. Codebase

No `spec.md` exists for this branch. Issue claims reconciled directly against code:

| Issue claim | Reality | Plan response |
|---|---|---|
| 5 base64 scripts injected at `git-data.tf:123` | Confirmed: 5 `base64encode(file())` args (bootstrap, pre-receive-placeholder, provision, transport-wrapper, remove) | Wrap the whole `templatefile()` in `base64gzip()`; args unchanged. |
| Rendered ≈ 41,662 B | Reproduced 41,662 B exactly via the size-test's modeling | Confirmed; used as the "before" baseline. |
| gzip likely sufficient; "measure first" | Measured: gzip -9 = 16,447 B; base64gzip = ~21,929 B — both under cap | Adopt gzip-first; drop the R2/GHCR fallback to contingency-only. |
| `git-data.tf` has no `ignore_changes=[user_data]`; host not provisioned | Confirmed (tf:153-156) | Edit render freely; no taint/replace needed. |
| Same failure class as #5921 but web's docker-bake mechanism does not transfer (git-data is no-docker) | Confirmed: zero docker/image refs in `cloud-init-git-data.yml` | Use gzip (no-infra), not bake-and-extract. |
| Size-guard test pins git-data at a no-further-growth ceiling referencing #5927 | Confirmed: `GIT_DATA_CEILING = 42_000`, test asserts `renderedSize < 42_000` (models RAW, not gzipped) | Replace the raw-ceiling assertion with a gzipped sub-cap budget. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the git-data host is **not yet provisioned** (gated behind #5887) and serves no user traffic. A broken gzip would surface as a failed **future** provisioning (the #5887 operator would hit an opaque Hetzner create error or a cloud-init-didn't-run host), never as a live-user incident.

**If this leaks, the user's data is exposed via:** no new exposure vector. gzip is a **lossless, reversible transport wrapper** over the *same* cloud-config; it changes no secret handling, no key material, no data-at-rest posture. The LUKS passphrase, transport/provision/remove keys, and Doppler token are delivered identically (still never in cleartext user_data — the token is a scoped 0600 env file, the LUKS key is fetched via `doppler run` at boot).

**Brand-survival threshold:** `none`.
**Reason (required — infra diff touches a sensitive path):** the git-data host is not yet provisioned; a gzip decode failure is **fail-closed** — cloud-init won't run, the web-host-driven post-provisioning readiness check (git-data.tf:9-14) fails loudly before any ADR-068 cutover, and no user workspace git data ever reaches a misconfigured host. gzip is binary: the decompressed cloud-config is byte-identical or the boot aborts entirely — there is no partial-config-corruption path.

## Files to Edit

- `apps/web-platform/infra/git-data.tf` — wrap the `user_data = templatefile(...)` expression (line 123-151) in `base64gzip(...)`. Update the adjacent comment block to record the gzip-first rationale + the base64gzip decode contract (Hetzner base64-decodes → cloud-init gunzips). **No change to the `templatefile()` var map.**
- `plugins/soleur/test/cloud-init-user-data-size.test.ts` — replace the git-data test's raw-ceiling assertion (`renderedSize(...) < GIT_DATA_CEILING`) with: model the **base64gzip'd** size (gzip the modeled render via `node:zlib`, base64-encode, measure) and assert `< HETZNER_CAP` with a sub-cap budget + non-vacuity floor. Update the file header comment (lines 18-22) to record that #5927 landed via gzip-first (git-data is now UNDER cap). Remove/retire `GIT_DATA_CEILING`.
- `knowledge-base/engineering/architecture/decisions/ADR-080-runtime-plugin-deploys-via-image-rebuild.md` — amend the "Scope boundary" note (lines 229-234): flip #5927 from "tracked" to **resolved via `base64gzip()`**; record the mechanism (whole-render gzip-first, ~21.9 KB base64gzip vs 32,768 cap), the source-confirmed decode contract (`DataSourceHetzner.maybe_b64decode`, cloud-init ≥20.3), the #5887 empirical gate, and the security forward-note (gzip is encoding not encryption — future tfstate/plan-output secret scanners must decode first).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-5927-git-data-user-data-32kb-cap/tasks.md` — derived task breakdown (created in the Save Tasks step).
- *(Contingency only — do NOT create unless #5887 provisioning reveals a decode failure, which source analysis says it will not)* an R2/GHCR fetch path. Not part of the primary deliverable.

## Implementation Phases

### Phase 1 — Wrap `user_data` in `base64gzip()` (the fix)
Precondition: confirm current `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` is green (git-data ceiling test passing at ~41,662 < 42,000) and `terraform -chdir=apps/web-platform/infra fmt -check` is clean.
1. In `git-data.tf`, change `user_data = templatefile("${path.module}/cloud-init-git-data.yml", { … })` to `user_data = base64gzip(templatefile("${path.module}/cloud-init-git-data.yml", { … }))`. Keep the var map identical. (`base64gzip` is a Terraform **core** builtin — no provider add.)
2. Update the comment block above `user_data` to document: (a) why gzip-first (git-data is no-docker; #5921's bake-and-extract does not transfer); (b) the decode contract, citing the mechanism: **Hetzner does not accept binary user-data, so it base64-decodes the stored string (cloud-init `DataSourceHetzner.maybe_b64decode`) → raw gzip bytes → cloud-init auto-gunzips → byte-identical `#cloud-config`**; (c) the measured base64gzip size (~21.9 KB) vs the 32,768 cap.

### Phase 2 — Pre-merge byte estimate (source of truth: the node test; byte-exact deferred to provisioning)
3. `terraform -chdir=apps/web-platform/infra fmt -check` and `terraform validate` pass (via `infra-validation.yml`). **Note (deepen F3):** a `terraform console` `length(base64gzip(templatefile(...)))` returns `(known after apply)` for git-data because the map injects `hcloud_volume.git_data.id`, `hcloud_volume.git_data_luks.id`, and `doppler_service_token.git_data.key` — all unknown until the resources exist. So the pre-merge byte estimate comes from the corrected node test (Phase 3, real script content + placeholder secrets ≈ the ~21,929 B base64gzip figure), NOT from `terraform console`. If a concrete console number is wanted pre-merge, dummy-substitute the three unknown refs (same shape as the test). The **byte-exact** value is confirmed at #5887's first `terraform plan` (all refs resolved).

### Phase 3 — Update the size-guard test  [deepen F2 — CRITICAL: gzip REAL content, not placeholders]
4. In `cloud-init-user-data-size.test.ts`, add a `renderedGzipB64Len(cloudInitFile, gitDataTf)` helper that models the render with **real** `base64encode(file())` content for the 5 script args — i.e. read each script from disk and base64 it for real (the string, not just its length) — while placeholder-substituting only the small variable secrets/ids (pubkeys ~120 B, volume ids 24 B, token 48 B). Then `gzipSync(Buffer.from(render), { level: 9 })` (from `node:zlib`), base64-encode, return the length. **Do NOT gzip the `"x".repeat(N)` render** — x-runs compress ~1000:1 and make the assertion non-discriminating (a re-inlining regression would gzip to near-nothing and never trip the budget).
5. Rewrite the git-data test to assert `b64gzipLen < HETZNER_CAP` AND `< GIT_DATA_BUDGET` (sub-cap, e.g. `28_000` — ≥6 KB headroom over the ~21,929 B measured; loose enough for Go-vs-node zlib header/level differences + runner jitter, tight enough to catch a re-inlined script) AND `> GIT_DATA_FLOOR` (non-vacuity, e.g. `10_000`). Mirror the web triple-assert convention (test lines 142-144). Add an inline comment on each constant (as `WEB_BUDGET`/`WEB_FLOOR` have). Delete `GIT_DATA_CEILING`.
6. Update the file-header comment (lines 18-22) to state git-data is now UNDER cap via gzip-first (#5927) and that the model gzips real script content.
7. `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → green (web unchanged + git-data new assertion). Sanity-check the assertion is discriminating: temporarily add a dummy 6th `base64encode(file())`-shape arg to the modeled map and confirm the test's modeled b64gzip size *rises materially* (proves the model tracks real content, not x-runs) before removing it.

### Phase 4 — ADR-080 amendment + C4 confirmation
8. Amend ADR-080 scope-boundary note (see Files to Edit): flip #5927 to resolved-via-`base64gzip()`; record the decode contract (`DataSourceHetzner.maybe_b64decode`, cloud-init ≥20.3) + the measured byte estimate; add the **security forward-note** (deepen: a future control scanning tfstate/plan-output for secrets must base64gzip-decode first — gzip is encoding, not encryption). Confirm no C4 element/edge change (see Architecture Decision section) — cite the enumeration.

### Phase 5 — Decode-path verification (source-confirmed; empirical gate at #5887)
9. The decode path is **confirmed by cloud-init source** (`DataSourceHetzner.maybe_b64decode`, cloud-init ≥20.3; Ubuntu 24.04 ships current). No throwaway boot test is provisioned (it would open a temporary public-SSH hole in the deny-all host for a source-confirmed mechanism). The **empirical** re-confirmation is #5887's first git-data provisioning: its web-host-driven readiness check (git-data.tf:9-14) fails **loudly and fail-closed** if cloud-init did not run, before any cutover or user data. Annotate #5887 that its first provisioning is the decode-path confirmation gate so the operator expects it.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `git-data.tf` `user_data` expression is `base64gzip(templatefile("${path.module}/cloud-init-git-data.yml", { … }))`; the `templatefile()` var map is byte-unchanged (5 `base64encode(file())` args intact). `grep -c "base64encode(file(" apps/web-platform/infra/git-data.tf` returns the same count as `origin/main`.
- **AC2** `cloud-init-git-data.yml` and all 5 injected `.sh` scripts are byte-identical to `origin/main` (`git diff --stat origin/main -- apps/web-platform/infra/cloud-init-git-data.yml apps/web-platform/infra/git-data-*.sh` shows no changes to those files).
- **AC3** Pre-merge byte estimate `< 32768` from the corrected node test's modeled base64gzip length (real script content), pinned in the PR body and ADR; the ADR notes that byte-exact confirmation is deferred to #5887's first `terraform plan` (git-data refs are `known after apply` pre-provisioning, so `terraform console` cannot yield a concrete number without dummy substitution — deepen F3).
- **AC4** `cloud-init-user-data-size.test.ts` git-data test asserts the **base64gzip'd** size (modeled with **real** `base64encode(file())` script content, secrets as placeholders) `< HETZNER_CAP` and `< GIT_DATA_BUDGET` and `> GIT_DATA_FLOOR`; `GIT_DATA_CEILING` removed. The discrimination sanity-check (Phase 3 step 7) passes — modeled size rises when a dummy script arg is added. `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` is green.
- **AC5** The web host test still passes unchanged (no cross-contamination of the shared helpers).
- **AC6** `terraform -chdir=apps/web-platform/infra fmt -check` and `infra-validation.yml`'s `terraform validate` pass.
- **AC7** ADR-080 scope-boundary note flips #5927 to resolved-via-base64gzip with the measured byte count + decode contract; the size-test header comment reflects git-data now under cap.
- **AC8** PR body uses `Ref #5927` (NOT `Closes`) — the fix makes the render valid but the empirical decode confirmation lands at #5887's first provisioning; the code-side fix itself is complete at merge.

### Post-merge (verification)
- **AC9** #5887 annotated that its first git-data provisioning is the decode-path confirmation gate (readiness check = pass ⇒ cloud-init decoded correctly). On that success, `gh issue close 5927` with the readiness-check evidence — or close #5927 at merge if the team accepts the source-confirmed decode as sufficient and treats #5887 as the standing gate (operator choice; note in PR body).

## Infrastructure (IaC)

### Terraform changes
- **File:** `apps/web-platform/infra/git-data.tf` (single expression change: `user_data` wrapped in `base64gzip()`).
- **Providers:** none added. `base64gzip()` is a Terraform **core** builtin (no provider). hcloud stays `~> 1.49`. *(Fallback Option B only: `hashicorp/cloudinit` provider would need adding to `main.tf` — not in scope.)*
- **Sensitive variables:** unchanged. Same `doppler_token` (scoped `prd_git_data` service token), `git_*_pubkey` locals, volume ids — all delivered identically inside the (now gzipped) render.

### Apply path
- **(a) cloud-init-only — the resource is not yet provisioned.** `hcloud_server.git_data` is absent from the `apply-web-platform-infra.yml` `-target` allow-list, so the merge-triggered auto-apply plans (HCL `file()`/`base64gzip()` evaluate at plan-time regardless of `-target`, per the workflow's own note at line 177) but **creates nothing** for git-data. The fix is therefore **inert on live infra** at merge time and simply makes the render valid for whenever #5887 first provisions the host. No `ignore_changes`, no taint, no replace — the host does not exist.
- **Downtime / blast-radius:** none. No running host is touched.

### Distinctness / drift safeguards
- git-data is **prd-only** Hetzner infra (no dev equivalent). No `dev != prd` collision.
- `git-data.tf` deliberately carries **no** `lifecycle.ignore_changes=[user_data]` (tf:153-156) — preserved. Once the host is provisioned, a future `user_data` edit correctly forces replace (the intended fence-iteration path); gzip does not change that contract.
- Secret values still land in `terraform.tfstate` exactly as before (unchanged) — gzip does not alter what is stored, only the encoding of the delivery document.

### Vendor-tier reality check
- Hetzner `cax11` ARM host — no free-tier gate on server create. The only vendor limit at play is the 32,768-byte `user_data` cap, which this fix resolves (~21.9 KB base64gzip).

## Observability

```yaml
liveness_signal:
  what: git-data host reachability (git ls-remote over the private net) → Better Stack PUSH heartbeat
  cadence: 60s period / 30s grace (betteruptime_heartbeat.git_data_prd, git-data.tf:214; paused=true until the web-host probe cron ships)
  alert_target: email (Better Stack), policy_id gated on betterstack_paid_tier
  configured_in: apps/web-platform/infra/git-data.tf (heartbeat + GIT_DATA_HEARTBEAT_URL Doppler secret)
error_reporting:
  destination: this change adds NO new runtime error path (lossless encoding wrapper). A gzip-decode failure at first provisioning surfaces via the web-host-driven post-provisioning readiness check (git-data.tf:9-14) failing loudly (absent git / bare-repo root / hook) → the paused heartbeat never starts pinging → absence-of-ping alert once unpaused.
  fail_loud: true (readiness check aborts cutover; cloud-init fail-closed by design)
failure_modes:
  - mode: base64gzip decode fails on Hetzner (source-confirmed it does NOT — DataSourceHetzner.maybe_b64decode) → cloud-init never runs
    detection: #5887 first-provisioning readiness check (git ls-remote / bare-repo root / hook over private net) finds no git/bare-repo/hook; cloud-init status on the host = error
    alert_route: readiness-check failure blocks cutover fail-closed (no heartbeat unpause); no user data reaches the host
  - mode: user_data regresses back over cap (new script re-inlined)
    detection: CI size-guard test (cloud-init-user-data-size.test.ts) fails on the gzipped-size budget
    alert_route: CI red on PR (blocking)
logs:
  where: cloud-init logs on the host (/var/log/cloud-init.log, /var/lib/cloud) — inspected at #5887 first provisioning if the readiness check fails
  retention: host-local (ephemeral until #5274 PR C ships the probe cron); not a new dark surface — this change introduces no new persistent runtime process
discoverability_test:
  command: bun test plugins/soleur/test/cloud-init-user-data-size.test.ts   # size regression, NO ssh
  expected_output: git-data base64gzip'd user_data < 32768 (and < GIT_DATA_BUDGET) → test green
```

Note (affected-surface, 2.9.2): the git-data host is a blind-ish surface (deny-all public ingress, no docker/Sentry in its minimal cloud-init), but **this change adds no new failure mode to it** — it is a lossless re-encoding of the identical cloud-config, and the decode path is confirmed by cloud-init source (`DataSourceHetzner.maybe_b64decode`). The one residual risk (a boot that silently didn't decode) is discriminated fail-closed by #5887's web-host-driven readiness check over the private net — the existing observability surface for this host, not a new dark surface introduced by this change.

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-080** (not a new ADR): the "gzip-first for git-data" decision was already recorded in ADR-080's 2026-07-02 amendment scope-boundary note (lines 229-234). This plan **implements** it. The amendment task: flip #5927 from "tracked" → **resolved via `base64gzip()`**; add the concrete mechanism (whole-render gzip-first, modeled base64gzip ~21.9 KB vs 32,768 cap), the Hetzner decode contract (`DataSourceHetzner.maybe_b64decode`, cloud-init ≥20.3), and the decode-path verification status (source-confirmed; empirical gate = #5887 first provisioning). No new decision is introduced — this records execution of an existing one.
- **Security forward-note (add to the amendment, from deepen security review):** `base64gzip()` is a lossless *encoding*, NOT encryption — the scoped Doppler token remains recoverable from `terraform.tfstate` and the Hetzner API exactly as today. Any *future* control that scans tfstate or `terraform plan` output for secret literals must `base64 -d | gunzip` first, or it will be blind to the gzipped envelope. (No live regression: today's CI secret-scan is `gitleaks git`, which scans committed source where the token is only a TF reference.)
- **Accretion advisory (deepen, non-blocking):** ADR-080 is titled "runtime plugin deploys via image rebuild"; this is its *second* stretch onto Hetzner `user_data` cap handling (a no-docker concern unrelated to image rebuild). Amending is defensible (ADR-080 already named #5927 as the tracked follow-up), but a future consolidation of "Hetzner 32 KB user_data cap handling" into a small dedicated ADR that both the web and git-data hosts reference could reduce accretion. Out of scope here.

### C4 views
- **No C4 model change.** Enumeration checked against all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`):
  - **External human actors:** none new (git-data is an internal private-net host; no new correspondent/vendor/role).
  - **External systems:** none new — gzip needs **no** R2/GHCR (the fallback that *would* have added an external `Pulls scripts` edge is not used).
  - **Data stores:** `gitDataStore` ("Shared git-data") already modeled (`model.c4:194`); the `claude -> gitDataStore` edge already exists (`model.c4:309`). Unchanged.
  - **Access relationships:** unchanged — same transport/provision/remove key posture; gzip alters only the delivery encoding of the cloud-config, not who accesses what.
  - Therefore no element/`#external` tag/edge/`view … include` line is added, and no existing element description is falsified. (Confirm during /work by re-reading the three `.c4` files; run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` only if any `.c4` is touched — expected: not touched.)

### Sequencing
- The ADR amendment is authored in THIS PR (Phase 4), describing the resolved state. It is not deferred.

## Domain Review

**Domains relevant:** Engineering (CTO) — carry-forward.

### Engineering (CTO)
**Status:** reviewed (carry-forward from ADR-080 amendment).
**Assessment:** The CTO already ruled "gzip-first" for git-data and recorded it in ADR-080's scope-boundary note naming #5927. This plan implements that ruling with a measurement (base64gzip ~21.9 KB < 32,768) that confirms sufficiency. The decode path is confirmed by cloud-init source (`DataSourceHetzner.maybe_b64decode`; Hetzner cannot accept binary user-data so base64 is mandatory and `base64gzip()` is the intended path), with #5887's first-provisioning readiness check as the fail-closed empirical gate — no throwaway boot test needed. No new architecture; no data-model or trust-boundary change.

### Product/UX Gate
Not run — no Product relevance. No file in `## Files to Edit`/`## Files to Create` matches a UI-surface term/glob (infra `.tf`, a `bun:test` `.ts`, an ADR `.md`). Tier: NONE.

### GDPR / Compliance (Phase 2.7)
Skipped — no regulated-data surface change. git-data eventually stores user git repos, but this change is a **lossless encoding wrapper** over the identical cloud-config: no schema, auth flow, API route, `.sql`, data-flow, or key-handling change. None of the (a)-(d) expansion triggers fire (no LLM on session data; threshold is `none` not single-user; no cron reading learnings/specs; no new distribution surface).

## Open Code-Review Overlap

**None.** Queried 61 open `code-review` issues (`gh issue list --label code-review --state open`); zero reference `git-data.tf`, `cloud-init-user-data-size.test.ts`, or `cloud-init-git-data.yml`.

## Risks & Mitigations

- **R1 — [RESOLVED BY SOURCE — was primary risk] Does Hetzner base64-decode `user_data` so cloud-init sees gzip bytes?** **Yes, confirmed by cloud-init source.** `DataSourceHetzner.py` calls `util.maybe_b64decode(ud)` with the comment *"Hetzner cloud does not support binary user-data. So here, do a base64 decode of the data if we can"* (cloud-init 20.3+, PR #448; Ubuntu 24.04 ships far newer). Because Hetzner rejects binary user-data, base64 is **mandatory** and `base64gzip()` is the intended path — not a datasource gamble. The documented base64+gzip failure reports are for datasources that do NOT base64-decode (AWS EC2 raw, LXC); Hetzner explicitly does. **Residual empirical confirmation:** #5887's first provisioning readiness check (fail-closed). **On the Option-B fallback (corrected at deepen review):** `hashicorp/cloudinit` with `base64_encode = true` *also* relies on the platform base64-decoding — it is NOT a decode-path escape hatch, and `base64_encode = false` (raw gzip) would fail on Hetzner (binary unsupported). So Option B is not a meaningful fallback for a *decode* failure. If gzip were ever insufficient (it is not — size fits with ~10 KB headroom), the real contingency is the issue's **R2/GHCR HTTPS-fetch** (git-data has apt/GitHub egress) — kept as documented contingency only.
- **R2 — [CRITICAL if mis-implemented] The size-test model must gzip REAL script content.** Gzipping the `"x".repeat(N)` placeholder render collapses ~1000:1 (~1-2 KB) and makes the assertion **non-discriminating** — a re-inlined script gzips to near-nothing and never trips the budget, so the test goes green while guarding nothing. **Mitigation:** Phase 3 step 4 models the 5 script args with real `base64encode(file())` content (only the ~600 B of secrets stay as placeholders); Phase 3 step 7 sanity-checks discrimination by confirming a dummy added script raises the modeled size. This is the load-bearing correction from deepen review.
- **R3 — Go (`base64gzip`) vs node (`node:zlib`) gzip output differs; plus CI zlib jitter.** The node model will never byte-match `terraform`'s Go gzip (different headers/level), so the test is a budget guard, not a byte-exact oracle. **Mitigation:** budget-based assertion (`< GIT_DATA_BUDGET` with ≥6 KB slack over ~21.9 KB), never exact equality. Byte-exact truth is #5887's `terraform plan` (AC3).
- **R4 — Future `user_data` edit forces host replace once provisioned.** Unchanged by this fix (no `ignore_changes` by design). Documented, not a regression.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold fails `deepen-plan` Phase 4.6. This plan's threshold is `none` with the required sensitive-path reason bullet — do not strip it.
- **Do NOT edit `cloud-init-git-data.yml` or the 5 scripts.** The whole point of gzip-first is a zero-content-change wrapper; any content edit both defeats the "byte-identical" AC2 and risks re-tripping the LUKS-block test (`git-data-luks.test.sh` greps the raw template — a content edit could break it).
- **The 32,768 cap measures the `base64gzip()` OUTPUT string** (what Hetzner stores, ~21.9 KB), not the decompressed cloud-config (41.7 KB) and not the raw gzip (16.4 KB). Assert the base64gzip length in the test.
- `terraform plan`/`console` in `apps/web-platform/infra` needs the canonical `prd_terraform` invocation (raw AWS R2 creds exported + `--name-transformer tf-var`) if full var resolution is required — see `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`.

## Test Scenarios

1. **Size regression (unit, no infra):** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` — git-data base64gzip'd size (real script content) < 32,768 and < `GIT_DATA_BUDGET`; web unchanged.
2. **Discrimination sanity-check (Phase 3 step 7):** adding a dummy `base64encode(file())`-shape arg to the modeled map raises the modeled b64gzip size materially (proves the model tracks real content, not x-runs); remove after.
3. **Template/script immutability:** `git diff --stat origin/main -- apps/web-platform/infra/cloud-init-git-data.yml apps/web-platform/infra/git-data-*.sh` → empty.
4. **Terraform validate/fmt:** `infra-validation.yml` green (`terraform fmt -check` + `validate`).
5. **Decode-path (empirical, deferred to #5887):** first git-data provisioning → web-host readiness check (git ls-remote / bare-repo root / hook over private net) passes ⇒ cloud-init decoded the base64gzip user_data correctly. Fail-closed if not.
