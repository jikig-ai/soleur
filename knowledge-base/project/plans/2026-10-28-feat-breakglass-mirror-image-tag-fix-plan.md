---
title: "feat: datacenter-first break-glass OCI mirror skill + image_tag canonical-form fix + eMudhra census close-out"
type: feat
date: 2026-10-28
slug: feat-breakglass-mirror-image-tag-fix
branch: feat-one-shot-11321-11424-11426
issue: 11424
closes: [11424, 11426, 9669]
lane: cross-domain
domain: engineering
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: datacenter-first break-glass OCI mirror skill + image_tag canonical-form fix + eMudhra census close-out

## Enhancement Summary

**Deepened on:** 2026-10-28
**Sections enhanced:** Observability (minimal discoverability probe), Network-Outage Deep-Dive (4.5 subsection), Merge-blast answer (infra `on.push` trigger analysis)
**Research agents used:** none — no Task/subagent tool in this environment; all gates executed inline (sequential-fallback disclosure: no independent agent review ran)

### Key Improvements

1. Discoverability probe narrowed from the 13-fixture suite to the smallest command printing the signal (`resolve-web1-known-good-tag.sh 1.2.3` → `v1.2.3`, measured 0.1 s — comfortably inside Check 10's 15 s cap and outside the suite-shape reject patterns).
2. `on.push.paths: apps/web-platform/infra/**` merge-trigger analyzed: the push-fired auto-apply runs but resolves no resource changes from this diff (neither edited file is referenced by any `.tf`) — recorded in §Merge-blast answer for the PR body's first line.
3. `doppler secrets get` invocation corrected to the two-call form mirroring `scheduled-inngest-health.yml:1298-1299` (sharp-edge: multi-name forms are unverified CLI shapes).

### New Considerations Discovered

- The push-triggered `apply` job (no reviewer gate since PR #4220) means *any* `infra/**` merge runs a live `terraform plan`+apply — even a wording/test diff pays the ~53-min serializer slot. Noted, accepted (same as every infra test-suite merge).
- Fixture (g) inversion is a deliberate semantic flip (reject → accept), pinned alongside `vv1.2.3` rejection so the strict guard is visibly intact.

## Overview

One PR (draft #11442, branch `feat-one-shot-11321-11424-11426`) bundles three tightly related registry/incident-response outcomes from the 2026-10-28 eMudhra session:

1. **#11424 — break-glass mirror skill.** During the O2 recovery the GHCR→zot mirror had to run while the CF-tunnel bridge was down. Streaming ~1.1–2.4 GB over the operator's residential uplink failed repeatedly (~250 KiB–1.5 MB/s, HTTP/2 PROTOCOL_ERROR drops, ~1 h+); the datacenter-side fetch on web-1 finished in ~3 min. Codify the winning path as `soleur:registry-breakglass-mirror`: pull OCI manifests+blobs **on a private-net datacenter host** with per-command `curl --resolve` (a name-scoped bypass of the hosts-file ghcr.io sinkhole — zero persistent config change; digest-pinned bytes keep integrity anchored at sha256, not at the registry), then `crane push` the assembled OCI layout to zot at `10.0.1.30:5000`. Never upload blobs through a forwarded registry connection (zot PATCH uploads die mid-stream over `ssh -L`; registries do not resume upload sessions).
2. **#11426 (+ earlier duplicate #9669) — `image_tag` double-`v` abort.** `apply-web-platform-infra.yml` validates `^v?[0-9]+\.[0-9]+\.[0-9]+$` but hands the raw input to `resolve-web1-known-good-tag.sh`, which prepends `v` itself: operator-supplied `v0.364.16` → `vv0.364.16` → strict-regex abort **after** the environment approval. Normalize to one canonical form inside the resolver (the input regex's `v?` and the resolver contract then literally agree), and pin the spelling in the fixture suite.
3. **#11321 — eMudhra migration close-out.** The production execution completed 2026-10-28 per the issue's comments (O1 credential kill applied, O2 web-2 replace dispatched with cloudflared 2026.10.4, O3 census verified at dispatch time). This PR's remaining scope is the read-only verification that the */15 census reports `versions_ok`, an evidence comment, and the close. No production mutation is authorized or needed. The residual web-1 zombie cloudflared is tracked by #6964 — out of scope.

## Research Insights

### Relevant file paths (verified on this branch, 2026-10-28)

- `.github/workflows/apply-web-platform-infra.yml:106` — `image_tag` input, description advertises `e.g. v1.2.3`.
- `.github/workflows/apply-web-platform-infra.yml:4706-4731` and `:5172-5207` — the two pre-approval shape validations (`^v?[0-9]+\.[0-9]+\.[0-9]+$`; the messages say "bare release version" while accepting `v?` — wording cleaned up in this diff).
- `.github/workflows/apply-web-platform-infra.yml:4849-4897` (web-host-create) and `:5296-5336` (web-host-replace) — the two `Resolve known-good image digest off-host` steps; both set `RUNNING_VERSION="$IMAGE_TAG_INPUT"` unstripped before calling the resolver.
- `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` — pure resolver; `TARGET_TAG="v${RUNNING_VERSION}"` at ~:41; strict `^v[0-9]+\.[0-9]+\.[0-9]+$` guard. Callers: the two workflow steps plus `knowledge-base/engineering/operations/runbooks/web-host-birth.md:267`.
- `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` — fixture suite; **fixture (g) already pins that `run_arg "v1.2.3"` is REJECTED** (`rc!=0`, empty OUT). Under the chosen fix this row is rewritten to assert acceptance+normalization, and new rows pin `vv1.2.3` rejection and stdin-seam parity. Registered in `.github/workflows/infra-validation.yml`. Prints `resolve-web1-known-good-tag: N passed, 0 failed`.
- Retired sibling fix pattern (the issue's citation — see Reconciliation): `git show 6a01e728cf^:.github/workflows/web2-luks-rebirth.yml` lines 208-210 — `TAG=$(bash .../resolve-web1-known-good-tag.sh "${IMAGE_TAG_INPUT#v}")` with the comment "The resolver takes the BARE version (it prepends the v itself)… strip the v here."
- `scripts/tunnel-connector-census.sh` — pure census classifier; `CLOUDFLARED_VERSION_FLOOR="2026.10.2"`, `classify_conn_versions` emits `versions_ok` / `below_floor` / `version_unreadable` / `version_floor_invalid`. Sourced by `.github/workflows/scheduled-inngest-health.yml:1283-1360` (the */15 census; emits the `SOLEUR_ORIGIN_HOST_CHURN` breadcrumb and files `ci/tunnel-connector-drift` issues only on `multi_connector`/`zero_connectors`/`below_floor`-class verdicts).
- Census credential sourcing (read-only): `CF_API_TOKEN` + `CF_ACCOUNT_ID` from Doppler `soleur/prd_terraform` (scheduled-inngest-health.yml:1298-1299); tunnel resolved by name `soleur-web-platform`; credentialed curl via `scripts/lib/bearer-curl.sh` (`bc_curl`, ADR-280 stdin config).
- `scripts/registry-restore-from-ghcr.sh` — the existing GHCR→zot restore engine for `registry-luks-recut`; runs in GHA runners **over the tunnel bridge**, so it is structurally unavailable in the exact window this skill covers. Its hard-won requirements carry into the skill: signature copy is obligatory (ci-deploy cosign-verifies against the SAME registry it pulled from — a restored image with no signature fails deploy verification, ADR-087), `crane validate --remote` (never `crane digest` alone — zot gc/dedupe lets a manifest outlive its layers; measured 2026-08-05), `ZOT_PUSH_USER`/`ZOT_PUSH_TOKEN` validated non-empty before use (exit-5 class), never "rotate ZOT_PUSH_* first" (`/etc/zot/htpasswd` is baked once at boot from the isolated `soleur-registry/prd` config).
- `scripts/zot-mirror-diagnosis.sh` — the release-pipeline failure-verdict vocabulary (`live`/`stale`/`unverifiable`/`unmeasured`); the skill's failure text must name only measured causes (ADR-166).
- `.github/actions/cf-tunnel-registry-bridge/action.yml` — documents that CI reaches zot ONLY through `registry.` ingress → `tcp://10.0.1.30:5000`; when that path is down the runner cannot push at all — the gap the skill covers.
- `apps/web-platform/infra/server.tf:1131-1150` (`local.ghcr_deny_sh`) — the ghcr deny is a **hosts-file sinkhole** (`0.0.0.0` + `::` lines for `ghcr.io`, `pkg-containers.githubusercontent.com`, `docker.pkg.github.com` in `/etc/hosts` and the cloud-init hosts template), i.e. an accident guard on name resolution — not an nftables egress rule. `curl --resolve <name>:443:<ip>` is the sanctioned per-command bypass; `pkg-containers.githubusercontent.com` (GHCR's blob-redirect target) is in the sinkholed set and MUST be resolved too.
- Doppler sourcing (verified): `ZOT_PUSH_USER`/`ZOT_PUSH_TOKEN` in `soleur/prd` root (reusable-release.yml:3627-3628); `DEPLOY_SSH_PRIVATE_KEY` in `soleur/prd_terraform` (ci-ssh-key.tf:54); `CF_API_TOKEN`/`CF_ACCOUNT_ID` in `soleur/prd_terraform`.
- GHCR credential: the repo's `GHCR_READ_TOKEN` is a **revoked** PAT by design (ADR-096 §5.5, B3 — no host reads GHCR). The skill sources GHCR auth as an operator-supplied `GHCR_TOKEN` (read:packages PAT) provided at invocation time — never from Doppler.

### Institutional learnings applied

- `2026-09-28-an-ssh-drop-without-a-pty-is-sigpipe-and-my-cleanup-trap-read-it-as-success` — treat forwarded-connection transfer failure modes as first-class in the skill's "never do this" section.
- `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed` — digest-only verification certifies an unusable mirror; the script's read-back must be `crane validate --remote`.
- `2026-07-30-the-comment-that-named-a-cause-was-the-cause-of-the-misdiagnosis` — failure text names measured causes only (the zot-mirror-diagnosis vocabulary).
- `2026-06-08-plan-grep-provider-registry-not-just-process-env-for-credential-existence` — credential existence verified in Doppler config names (above), not assumed.
- `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency` — the L3 firewall allow-list precedes any SSH-layer assumption; the skill's direct-SSH fallback names `admin-ip-refresh` as its precondition.

### Premise Validation (Phase 0.6)

- `#11321`, `#11424`, `#11426`, `#9669` all OPEN; none closed by a merged PR. Draft PR #11442 exists on this branch. **Stale premise found and reconciled (below): `web2-luks-rebirth.yml` was retired in #10083 (commit 6a01e728cf, ADR-263)** — the cited sibling fix pattern survives only in git history; retrieved verbatim (above).
- Cited mechanisms verified against the tree: resolver + fixture exist; census script + */15 wiring exist; `scripts/zot-mirror-diagnosis.sh` exists; no existing break-glass/mirror skill or runbook (`plugins/soleur/skills/`, `knowledge-base/engineering/operations/runbooks/` greps). `registry-restore-from-ghcr.sh` covers the luks-recut restore only and requires the tunnel bridge.
- ADR corpus grepped for the proposed mechanisms: ADR-096 (zot migration; hosts deny ghcr — the boundary the skill's `--resolve` bypasses deliberately), ADR-087 (cosign — signature mirror is mandatory), ADR-114 (connector ingress), ADR-166 (cause vocabulary), ADR-169 (restore authorization), ADR-304 (connector placement moved to web-2), ADR-280 (bearer-curl). No rejected-alternative collision: no ADR rejected host-side mirror pulls; the ghcr deny is documented as a name-resolution accident guard, so a documented per-command `--resolve` exception is consistent with its intent — and is recorded as an ADR-096 amendment deliverable (§Architecture Decision).
- Collision pre-check (`collision-precheck.sh` ×4): PR #11442 names #11321/#11424/#11426 — that is THIS pipeline's own draft. Foreign `test-all.sh` processes in worktree `feat-one-shot-autonomous-start-followthroughs` (pids 584387/584388/645556) — a different branch and issue set; reported, not blocking.

### Property List (Phase 0.6b)

1. A future break-glass GHCR→zot mirror is executable from a codified artifact without re-deriving the measured path.
2. The mirror never uploads blobs over a forwarded/residential connection: pull datacenter-side, push over the private net.
3. Credential sourcing is explicit and least-privilege (SSH key + ZOT_PUSH_* from Doppler; GHCR read as an operator-supplied PAT).
4. No persistent host config change (per-command `--resolve`; the deny stays in force afterward).
5. A `v`-prefixed `image_tag` resolves to the intended release for EVERY resolver caller — input regex and resolver contract agree on one canonical form.
6. `vv*`/non-semver inputs still abort loud, before any destroy.
7. #11321 closes only against live evidence (census `versions_ok`); a failing census re-arms, never auto-closes.

### Cut List (Phase 0.6b)

- *Temporary `/etc/hosts` edit on the mirror host* → property 4 → superseded by per-command `curl --resolve` (named in the ask; zero persistent change).
- *Reuse `registry-restore-from-ghcr.sh` for the break-glass window* → property 2 → it requires the CF-tunnel bridge, which is down by definition in this window; its requirements (sig copy, `validate --remote`) are carried, not the engine.
- *`crane copy`/`crane pull` for the fetch leg* → properties 2/4 → crane cannot scope name resolution per command on a sinkholed host; `curl --resolve` + assembled OCI layout is the measured form.
- *Tighten input validation to reject `v`* → property 5 → rejected: the input description and every release page use the `vX.Y.Z` spelling; rejecting the advertised form is worse than accepting it.

### Value-Proposition Measurement (Phase 0.6c)

Claimed saving (issue body): recovery time from ~1 h+ of flaky residential uploads (~1.1–2.4 GB at 250 KiB–1.5 MB/s with repeated drops) to ~3 min on the datacenter link. Measured during the incident itself (2026-10-28, recorded in #11424); no plan-time re-measurement needed — the number is the incident's own evidence.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality | Plan response |
|---|---|---|
| "the sibling web2-luks-rebirth.yml already carries the fix pattern" | The workflow was **retired 2026-10-12 in #10083** (commit `6a01e728cf`, ADR-263); no such file on `origin/main`. The pattern survives in git history (`${IMAGE_TAG_INPUT#v}`). | Use the historical snippet as the pattern reference; implement normalization **inside the resolver** (ruled, see Alternatives) rather than reviving call-site strips. |
| "a fixture row in resolve-web1-known-good-tag.test.sh" | Fixture (g) **already exists and asserts the OPPOSITE** — `v1.2.3` is currently rejected. | The deliverable rewrites (g) to assert `v1.2.3 → v1.2.3` and adds `vv1.2.3`-reject + stdin-parity rows; the "one fixture row" ask maps to this rewrite+addition. |
| "web-1" named as the private-net fetch host (issue #11424) | Since ADR-304 (2026-10-27) web-2 is the connector host; web-1 is unreplaceable (LUKS-pinned workspaces volume, #6964). Both are 10.0.1.0/24 members. | The skill parameterizes the host (`MIRROR_HOST`, default `web-1`, any private-net member) rather than hardcoding web-1 — a fresh cattle host is preferred when available. |
| "the 15-minute tunnel-connector census" | Exists as `scripts/tunnel-connector-census.sh` sourced by `scheduled-inngest-health.yml`; floor `2026.10.2`; verdicts incl. `versions_ok`/`below_floor`. | #11321's close criterion = live CF API read + latest run's `SOLEUR_ORIGIN_HOST_CHURN` `version_verdict=versions_ok`. |

## Hypotheses

(Phase 1.4 fired — feature description matches `SSH`/`ssh -L`. Layers listed unverified-first, L3→L7, per plan-network-outage-checklist.md.)

1. **L3 firewall allow-list (operator egress → host SSH).** The skill's PRIMARY reach is `ssh.soleur.ai` through the tunnel; its FALLBACK (tunnel down — the exact break-glass window) is direct SSH to the host's public address as `deploy`, which requires the operator's current egress IP in the host firewall allow-list. [not yet verified — the skill prescribes `soleur:admin-ip-refresh` as the fallback's precondition; the census verification path needs no SSH at all (read-only CF API over public HTTPS)]
2. **L3 DNS/routing.** The sinkholed names (`ghcr.io`, `pkg-containers.githubusercontent.com`, `docker.pkg.github.com` — enumerated from `server.tf:1131` `ghcr_deny_sh`) resolve to `0.0.0.0`/`::` on the host BY DESIGN; the script supplies real addresses per-command via `--resolve`, so name resolution is a scripted input, not a hypothesis. Cloudflare API hostnames resolve publicly. [verified by design — the sinkhole set is enumerated from code, and the script must `--resolve` BOTH GHCR names, including the blob-redirect target]
3. **L7 TLS/proxy.** `curl --resolve` changes only the dial address; SNI, the TLS handshake and certificate verification all still target `ghcr.io` — the script MUST NOT pass `-k`. [verified by design]
4. **L7 application (census verdict).** The close-out evidence is the classifier's own verdict vocabulary (`versions_ok`/`below_floor`/`version_unreadable`) over the live `/cfd_tunnel/<id>/connections` body plus the latest scheduled run's `SOLEUR_ORIGIN_HOST_CHURN` breadcrumb — a service we can read directly, not a symptom chain. [verification commands in Phase 5]

## Network-Outage Deep-Dive (deepen-plan 4.5 — trigger fired: SSH)

Per `plan-network-outage-checklist.md`, layer-by-layer verification status:

| Layer | Status | Evidence / gap |
|---|---|---|
| L3 firewall allow-list (operator egress → host SSH) | not-yet-verified — closed at work time | The skill's primary reach is the `ssh.soleur.ai` connector; the direct-SSH fallback requires the operator's egress IP in the allow-list — skill prescribes `soleur:admin-ip-refresh` as the fallback precondition. The #11321 census path needs NO SSH (public CF API HTTPS). |
| L3 DNS/routing | verified by design | The sinkholed name set is enumerated from `server.tf:1131` (`ghcr_deny_sh`): `ghcr.io`, `pkg-containers.githubusercontent.com`, `docker.pkg.github.com`; the script supplies real addresses per-command via `--resolve` — name resolution is a scripted input, not ambient DNS. |
| L7 TLS/proxy | verified by design | `curl --resolve` pins only the dial address; SNI/handshake/CA-verification still target the hostname; `-k`/`--insecure` is banned on the pull leg (AC5 greps it). |
| L7 application | verified | The census close criterion uses the classifier's own verdict vocabulary over the live `/cfd_tunnel/<id>/connections` body + the run's `SOLEUR_ORIGIN_HOST_CHURN` breadcrumb — not a symptom chain. |

No hypothesis is confirmed/refuted on unavailable data — the one unverified layer (L3 allow-list) names its work-time verification mechanism rather than asserting a result.

## User-Brand Impact

- **If this lands broken, the user experiences:** for the mirror skill — a failed or partial production registry restore during an active incident (longer app.soleur.ai unavailability); for the `image_tag` fix — a host birth/replace dispatch that either still aborts post-approval or pins a wrong image (bounded by the remaining strict-semver + digest-pin + coherence-preflight chain); for the census close-out — a prematurely closed security tracker while a below-floor connector still serves the management plane.
- **If this leaks, the user's [data / workflow / money] is exposed via:** workflow — a corrupted image set pushed to the sole pull path could serve a bad deploy to every user (mitigated: digest pinning, `crane validate --remote` read-back, signature copy, no persistent host change); data — none (no user data touched); money — none.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `single-user incident` — the highest-blast artifact is a break-glass procedure whose every step verifies before it is used; a botched run fails closed (non-zero exit, nothing deployed) rather than serving bad bytes.

*Scope-out override (threshold `none` + sensitive-path diff — `apps/web-platform/infra/*`, `.github/workflows/apply-web-platform-infra.yml`):* `threshold: none, reason: the diff adds an operator/agent-invoked runbook, a string normalization with an unchanged strict-semver guard, and a read-only verification — no user-facing surface and every production mutation it documents is digest-pinned and read-back-verified.`

## Proposed Solution

### Workstream A — `soleur:registry-breakglass-mirror` skill (#11424)

- `plugins/soleur/skills/registry-breakglass-mirror/SKILL.md` — frontmatter `name: registry-breakglass-mirror`, third-person `description:` ≤25 words (budget: 2406/2436 measured, 30-word reserve for gated new-skill creation). Body: when to invoke (registry/tunnel bridge down, zot store must be re-materialized); connectivity matrix (primary `ssh.soleur.ai` tunnel; fallback direct SSH to the host's public address as `deploy`, gated on `soleur:admin-ip-refresh`); credential sourcing — `DEPLOY_SSH_PRIVATE_KEY` via `doppler secrets get ... -p soleur -c prd_terraform`, `ZOT_PUSH_USER`/`ZOT_PUSH_TOKEN` via `doppler secrets get ... -p soleur -c prd`, `GHCR_TOKEN` as an operator-supplied `read:packages` PAT (the Doppler copy is revoked BY DESIGN — do not reach for `GHCR_READ_TOKEN`); the procedure (fetch → assemble → push → read-back-verify); the **never-upload-through-a-forwarded-connection** lesson (zot PATCH uploads die mid-stream over `ssh -L`; registries do not resume upload sessions); cosign-signature mirroring obligation (the `sha256-<hex>.sig` reference — ci-deploy verifies against the same registry); failure-vocabulary pointer to `scripts/zot-mirror-diagnosis.sh`.
- `plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh` — self-contained script executed **on the datacenter host** (copied over via the SSH session): args = repo + one or more `repo@sha256:<digest>` (and/or `repo:tag`) refs; env = `GHCR_TOKEN`, `ZOT_PUSH_USER`, `ZOT_PUSH_TOKEN`; `--dry-run` prints the plan (refs, blob counts, target) without pushing. Mechanics: GHCR token exchange (`https://ghcr.io/token?scope=repository:<repo>:pull`) then per-command `curl --resolve ghcr.io:443:<ip>` manifest+blob GETs, `--resolve pkg-containers.githubusercontent.com:443:<ip>` for blob 307-redirects, assembled into an OCI layout dir; `crane push <layout> 10.0.1.30:5000/<repo>:<tag>` (`--insecure` — plain-HTTP private net, same posture as the existing `hetzner -> zotRegistry` edge); mirror the signature ref the same way; read-back `crane validate --remote` per pushed ref — never `crane digest` alone. `set -euo pipefail`, usage validation, synthesized fixtures only in any test, token never on argv (stdin/env). Fetch crane itself via a pinned github-release tarball (name + sha256) when absent on the host — github.com is NOT in the sinkhole set.
- `plugins/soleur/README.md` — component table `Skills` 104 → 105 + a row in the skills table.

### Workstream B — `image_tag` canonical-form normalization (#11426, closes #9669)

- `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` — normalize the input: `RUNNING_VERSION="${RUNNING_VERSION#v}"` after acquisition (before `TARGET_TAG="v${RUNNING_VERSION}"`), and update the contract comment from "the bare /health `.version` string" to "strict three-part semver, bare or `v`-prefixed — normalized to bare before the prepend." The strict regex is untouched: `vv1.2.3` → `v1.2.3` → `vv1.2.3` → still rejected; `v`/`vx`/`version…` all still rejected.
- `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` — rewrite fixture (g): `run_arg "v1.2.3"` now expects `rc=0`, `OUT=v1.2.3`; add `(g2) run_arg "vv1.2.3"` → reject; `(g3) run_stdin "v4.5.6"` → `v4.5.6` (seam parity with (h)).
- `.github/workflows/apply-web-platform-infra.yml` — wording-only edits at :4731 and :5207 (drop "bare" from "bare release version matching ^v?…") and a one-line comment at both resolve steps noting the resolver accepts either spelling and canonicalizes. **No call-site strip** — the canonical form lives in the resolver (see Alternatives ruling).

### Workstream C — #11321 evidence + close

1. Read-only live census: `CF_API_TOKEN=$(doppler secrets get CF_API_TOKEN -p soleur -c prd_terraform --plain)` and `CF_ACCOUNT_ID=$(doppler secrets get CF_ACCOUNT_ID -p soleur -c prd_terraform --plain)` (two calls, mirroring scheduled-inngest-health.yml:1298-1299) → `bc_curl`-style GET `cfd_tunnel?name=soleur-web-platform` → tunnel id → GET `cfd_tunnel/<id>/connections` → `classify_conn_versions` (or the equivalent jq: `[.result[].conns[].client_version]` all ≥ `2026.10.2`).
2. Cross-check the freshest scheduled run: `gh run list -w scheduled-inngest-health.yml -L 3` → `gh run view --log | grep SOLEUR_ORIGIN_HOST_CHURN` → expect `version_verdict=versions_ok`.
3. On `versions_ok`: post the evidence comment on #11321 (command output, run URL, PR #11442 reference) and `gh issue close 11321`. On `below_floor`/`version_unreadable`/`census_unavailable`: **do not close** — post the failing evidence and leave the issue open; no production mutation is authorized in this PR.

## Technical Considerations

- **Why normalize in the resolver, not at the two call sites** (CTO ruling D1, recorded in `specs/<branch>/decision-challenges.md`): the input regex advertises `v?` — a contract the resolver must satisfy at the single chokepoint every caller flows through (2 workflow steps + `web-host-birth.md` + any future caller). Call-site strips fix exactly today's two callers and leave the disagreement in the contract.
- **The `v` strip must precede the prepend, not weaken the regex.** `#v` strips exactly one leading `v`; `vvX.Y.Z` still fails the strict guard — the double-`v` path stays loud.
- **Sensitive-path surface:** `apps/web-platform/infra/` and `.github/workflows/apply-web-platform-infra.yml` both match the preflight Check 6 regex — carried by the `threshold: none` scope-out bullet above.
- **NFR:** no performance/scale surface; reliability NFR positively affected (documented recovery path).
- **Complexity check:** the skill is one SKILL.md + one script; no new workflow, no new credential, no new infra.

### Attack Surface Enumeration (the skill operates on a credentialed boundary)

- Write paths to the sole pull-path registry: `crane push` to `10.0.1.30:5000` with `ZOT_PUSH_*` — gated by digest-pinned refs + read-back validation + the private-net boundary (already the production posture).
- Host config mutation paths: none — `--resolve` is per-command; the script must not write `/etc/hosts`, and a plan-time AC greps the script for absence of `/etc/hosts` writes.
- Unchecked paths: the operator could still hand-run uploads over `ssh -L` — mitigated by making the skill the documented path of least resistance; the "never forward uploads" rule is called out as a hard DO-NOT in the skill body.
- Credential exposure: `GHCR_TOKEN`/`ZOT_PUSH_TOKEN`/`DEPLOY_SSH_PRIVATE_KEY` transit via env/stdin only, never argv, never logged (`set +x` regions around auth; `unset` after use — mirroring `registry-restore-from-ghcr.sh:610`).

## Implementation Phases

### Phase 1 — Resolver normalization + fixtures (Workstream B)

- Edit `resolve-web1-known-good-tag.sh` (normalize + contract comment).
- Rewrite fixture (g); add (g2)/(g3).
- Wording edits in `apply-web-platform-infra.yml` (two "bare release version" messages + one-line note at both resolve steps).
- Verify: `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` → `0 failed`; `git grep -n 'IMAGE_TAG_INPUT#v' .github/workflows/` → empty (no call-site strip).

### Phase 2 — The skill doc (Workstream A, docs half)

- `SKILL.md` per Workstream A; `plugins/soleur/README.md` count + table row.

### Phase 3 — The mirror script (Workstream A, code half)

- `scripts/mirror-ghcr-to-zot.sh` per the mechanics above; `bash -n` clean; `--dry-run`/`--help` verified.

### Phase 4 — ADR-096 amendment + C4 descriptions

- Per §Architecture Decision (ADR/C4) below.

### Phase 5 — #11321 census verification + evidence comment + close

- Per Workstream C. Read-only; runs in the work phase before PR-ready.

### Phase 6 — PR body + ship

- `Closes #11424`, `Closes #11426`, `Closes #9669`, `Refs #11321` (closed by evidence comment in Phase 5).

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| Strip `v` at the two workflow call sites (`${IMAGE_TAG_INPUT#v}`, the retired sibling's shape) | Fixes only the two current callers; the resolver contract keeps disagreeing with the input regex for `web-host-birth.md` and every future caller. The workflow-side fix was right for a single-use workflow; the shared resolver is the correct home for the canonical form. Ruled inline (CTO, 2026-10-28) — decision-challenges.md D1. |
| Reject `v` at input validation | The input description, every release page, and the remediation text all use `vX.Y.Z`; rejecting the advertised form converts a normalization defect into permanent operator friction. |
| A runbook instead of a skill | The issue explicitly asks for a skill; skills are agent-discoverable during incidents (the exact invocation context), runbooks are not. |
| Reuse `registry-restore-from-ghcr.sh` as the break-glass engine | It runs over the tunnel bridge, which is down by definition in this window. Its invariants (sig copy, `validate --remote`, credential hygiene) are carried into the script. |
| `docker login`/`docker pull` on the host for the fetch | Heavier (daemon state), and `docker pull` cannot `--resolve`-scope name resolution on a sinkholed host. |
| New C4 edge `hetzner -> ghcr` for the break-glass path | Ruled inline (CTO, 2026-10-28, D3): model edges depict standing relationships; a manual exception procedure belongs in the `ghcr` node description + the #8036 deletion comment, so "no host pulls GHCR" stays structurally true while the sanctioned human exception is named. |

## Observability

```yaml
liveness_signal:
  what: "the semver pin contract (resolve-web1-known-good-tag fixture suite) and the */15 connector census version_verdict this PR reads as evidence; the new skill is an on-invocation runbook whose liveness is its fixture-backed script behavior plus its registry component-table entry"
  cadence: "fixture suite: every infra-validation.yml run; census: every 15 min (web-server-dispatched, GHA-cron fallback)"
  alert_target: "infra-validation CI gate (merge-blocking); ci/tunnel-connector-drift action-required issue on below_floor-class verdicts (existing filing step)"
  configured_in: "apps/web-platform/infra/resolve-web1-known-good-tag.test.sh (registered in .github/workflows/infra-validation.yml); .github/workflows/scheduled-inngest-health.yml:1283-1360"
error_reporting:
  destination: "GHA step-log ::error:: annotations (resolver rejections); SOLEUR_ORIGIN_HOST_CHURN run-log breadcrumb (census); skill script stderr + non-zero exit"
  fail_loud: "resolver: exit 1 + ::error:: Cannot resolve a semver known-good tag (.version=<v>); census: version_verdict=below_floor files an action-required issue; mirror script: any unverified/missing ref exits non-zero with the failing ref named"
failure_modes:
  - mode: "v-prefixed image_tag regresses to vv* (normalization lost in a refactor)"
    detection: "fixture (g) in resolve-web1-known-good-tag.test.sh asserts run_arg v1.2.3 -> v1.2.3"
    alert_route: "infra-validation.yml red on the touching PR"
  - mode: "break-glass mirror reports success on a partial/unusable store (blob evicted, signature missing)"
    detection: "per-ref crane validate --remote read-back inside the script; a missing signature is a hard failure, never a warning (registry-restore-from-ghcr.sh precedent)"
    alert_route: "non-zero exit in the invoking session, failing ref named"
  - mode: "census evidence is stale or unverifiable when the issue is closed"
    detection: "Phase 5 requires BOTH the live CF API read AND the latest run's version_verdict=versions_ok; any other verdict posts evidence and leaves #11321 open"
    alert_route: "the open issue itself + the */15 filing step if below_floor"
logs:
  where: "GHA run logs (::error:: lines + SOLEUR_ORIGIN_HOST_CHURN); the skill session transcript; zot access log on the registry host (journald CONTAINER_NAME=zot -> SOLEUR_ZOT_LOG)"
  retention: "GHA run retention policy; journald persistent on the registry host"
discoverability_test:
  command: "bash apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh 1.2.3"
  expected_output: "v1.2.3"
```

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.registry (existing LUKS-backed zot store — this plan adds no new store; mirrored objects land on the same volume every release already writes)"
    mechanism: "luks (existing — device-bound at boot)"
    evidence: "apps/web-platform/infra/zot-registry.tf; runbooks/registry-luks-recut-6929.md"
    defends_against: "a seized/RMA'd disk; a raw volume snapshot"
    does_not_defend: "a leaked ZOT_PUSH_* credential; tampering on the live unlocked host"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available — scripts/followthroughs/registry-luks-live-8386.sh polls SOLEUR_ZOT_DISK store_luks fields"
in_transit:
  - connection: "datacenter host -> ghcr.io + pkg-containers.githubusercontent.com (manifest/blob pull)"
    enforced_at: "plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh — curl --resolve <name>:443:<ip> https:// URLs (address pin, TLS untouched)"
    tls: "HTTPS, public CA"
    cert_verification: "on — curl default verify; -k/--insecure forbidden on the pull leg"
    does_not_defend: "a poisoned --resolve IP argument; mitigated because all pulled bytes are digest-pinned (integrity anchored at sha256, not at the registry)"
    disclosed_as: "not-publicly-claimed"
  - connection: "datacenter host -> zot 10.0.1.30:5000 (crane push)"
    enforced_at: "same script — crane push --insecure over the Hetzner private net; same transport posture as the standing hetzner -> zotRegistry edge (plain-HTTP + insecure-registries)"
    tls: "none — plain HTTP on the private layer-2 network"
    cert_verification: "off"
    does_not_defend: "a private-net MITM or another subnet member tampering mid-push"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "the zot leg reuses the existing, already-accepted production posture — every host pull and CI push to 10.0.1.30:5000 is plain HTTP over the private layer-2 segment, which is the documented isolation boundary (model.c4 hetzner -> zotRegistry, tunnel -> zotRegistry)"
  tracking_issue: "#11424"
  reevaluate_when: "zot gains TLS termination, or the private-net-only assumption changes (e.g. a second registry site)"
  expires_on: "2027-01-26"
```

## Guard Contract

### Guard 1 — semver pin contract (resolver + fixture suite)

**Property.** Only a strict `vX.Y.Z` tag reaches digest resolution, regardless of which accepted input spelling (bare or `v`-prefixed) an operator supplies, for every caller of the resolver.

**Assembly.** The single chokepoint `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` — every caller (apply-web-platform-infra.yml's two resolve steps, `runbooks/web-host-birth.md:267`, any future caller) flows through it; the property must live at the chokepoint, not at call sites. Its harness is `resolve-web1-known-good-tag.test.sh` (registered in infra-validation.yml).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `RUNNING_VERSION="${RUNNING_VERSION#v}"` normalization line | RED — fixture (g) `v1.2.3 → v1.2.3` fails |
| 2 | Make the resolver exit 0 unconditionally (guard's own dispatch) | RED — every reject fixture (b)(c)(d)(e)(f)(j)(k)(g2) fails |
| 3 | Move the `#v` strip into `apply-web-platform-infra.yml` instead of the resolver (second-member shape: first caller compliant, second caller — the runbook — non-compliant) | RED by design — this is the property the assembly rules out; fixture (g) pins that the resolver itself accepts `v?` so no caller can reintroduce the gap |
| 4 | Weaken the strict regex `^v[0-9]+\.[0-9]+\.[0-9]+$` to `^v?[0-9]+` | RED — (d) prerelease / (k) four-part fixtures fail |
| 5 | Change fixture (g)'s expected output to `vv1.2.3` while keeping the resolver correct (harness row — must-PASS in a non-canonical shape) | RED — proves the harness compares actual resolver output, not a constant |

### Guard 2 — mirror-script pull/push completeness (anti-vacuity)

**Property.** The script exits 0 only after every required reference — image manifest, every layer/config blob, and the cosign signature reference — has been pushed AND read back successfully; a mirror of nothing (or of manifests without blobs) can never report success.

**Assembly.** One script, one chokepoint: `plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh` — the per-ref pull floor (manifest-declared blob count vs fetched blob count), the push loop, and the `crane validate --remote` verify stage that runs after ALL pushes. No second path may push.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Skip the blob-fetch loop so only manifests land in the layout | RED — `crane validate --remote` reports BLOB_UNKNOWN (the measured 2026-08-05 trap) and the script exits non-zero |
| 2 | Delete the read-back verify stage (guard's own dispatch — pushes then unconditional exit 0) | RED — a `verified==0` counter floor makes "verified nothing" a non-zero exit by construction |
| 3 | Mirror two refs where the first succeeds and the second's blob 404s (second member after a compliant first) | RED — the per-ref loop must not stop at the first success |
| 4 | Feed a `--dry-run` invocation (must-PASS, non-canonical input class) | PASS — prints the plan, exits 0, pushes nothing |
| 5 | Point `crane validate` at a ref that was never pushed (harness row — the oracle disagrees with the push set) | RED — proves the read-back queries the pushed set, not a constant |

## Architecture Decision (ADR/C4)

Detection fires: the break-glass path is a new **sanctioned exception to a recorded trust boundary** (the #9169 hosts-file ghcr deny + the deleted `hetzner -> ghcr` pull edge) and a new host→zot WRITE path from a host (today only CI writes, via the tunnel).

### ADR

**Amend ADR-096** (`knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`) — add a dated amendment (2026-10-28, #11424): the hosts-file ghcr deny is an accident guard on *name resolution*, and `soleur:registry-breakglass-mirror` is its documented, name-scoped exception (per-command `curl --resolve`, operator-supplied PAT, digest-pinned bytes, zero persistent config). Also record the datacenter-first doctrine: pull where the bandwidth is; never push blobs through a forwarded registry connection (no upload-session resume). Status stays Accepted — an extension, not a reversal. No new ADR number needed.

### C4 views

Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): every actor/system/container the procedure touches is already modeled — `ghcr` system (:452, marked dead-on-pull-path), `zotRegistry`, `hetzner`, `tunnel`, `github`, the deleted-edge comment at :801, the pull edge at :800. No new elements; no `views.c4` include changes; `spec.c4` unchanged. In-scope edits:

- `model.c4` `ghcr` node description — append the documented-exception sentence (manual, operator-PAT, `--resolve`-scoped, no standing credential) so "dead edge" is not read as absolute.
- `model.c4` :801 `#8036` deletion comment — name the sanctioned break-glass exception beside the deletion record.
- `model.c4` `hetzner -> zotRegistry` pull edge (:800) — append that break-glass WRITES also flow host→zot over the same private-net plain-HTTP transport under the procedure (write direction documented on the existing edge rather than a new edge — ruling D3).
- Validate with `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing

All three edits ship in THIS PR (wg-architecture-decision-is-a-plan-deliverable) — no deferred issue.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | [#11424] "pull manifests+blobs on a private-net host (web-1 here) with per-command `curl --resolve` (bypasses the ghcr.io hosts-file sinkhole with zero persistent config change; digest-pinned bytes keep integrity anchored)" | Phase 3 / `mirror-ghcr-to-zot.sh` | mapped |
| 2 | [#11424] "`crane push` the assembled OCI layout to zot over the private net (10.0.1.30:5000) — no long-lived PATCH streams over SSH-forwards or tunnels" | Phase 3 / script push+verify stage | mapped |
| 3 | [#11424] "Codify as a skill (e.g. `registry-breakglass-mirror`) with the exact credential sourcing (DEPLOY_SSH_PRIVATE_KEY, ZOT_PUSH_* from Doppler, operator PAT for GHCR) and the 'never upload blobs through a forwarded registry connection' lesson (zot PATCH uploads die mid-stream over ssh -L; registries do not resume upload sessions)" | Phase 2 / `SKILL.md` | mapped |
| 4 | [#11426] "strip a leading `v` (or reject it at input validation) before the resolver; make the input regex and the resolver contract agree on one canonical form" | Phase 1 / resolver normalization (ruling D1 chose normalize-in-resolver) | mapped |
| 5 | [#9669] "Strip a leading `v` from `IMAGE_TAG_INPUT` in both `Resolve known-good image digest` steps (the `web-host-create` and `web-host-replace` jobs) before calling the resolver, as `web2-luks-rebirth.yml` does, or tighten validation to reject the `v` spelling at the pre-approval step. Add one fixture row for the `v`-prefixed spelling." | Phase 1 / resolver + fixture (g) rewrite + (g2)(g3) | mapped |
| 6 | [#11321/brief] "verify the 15-minute tunnel-connector census reports ok (read-only Cloudflare API check), then close the issue with an evidence comment referencing this PR" | Phase 5 | mapped |
| 7 | [brief] "carry `Closes #9669` in the PR body alongside the work-target closes" | Phase 6 / AC9 | mapped |
| 8 | [brief] "A zombie cloudflared on web-1 is residual and already tracked by a separate open host-replace issue — out of scope" | Non-goal | descoped — justification: residual tracked by #6964 (verified OPEN) per the brief; no production mutation authorized |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/skills/registry-breakglass-mirror/SKILL.md` | "Codify as a skill (e.g. `registry-breakglass-mirror`) with the exact credential sourcing" | asked |
| `plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh` | "pull manifests+blobs on a private-net datacenter host with per-command `curl --resolve` … then `crane push` the assembled OCI layout" | asked |
| `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` | "make the input regex and the resolver contract agree on one canonical form" | asked |
| `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` | "Add one fixture row for the `v`-prefixed spelling" | asked |
| `.github/workflows/apply-web-platform-infra.yml` (wording/comment only) | "the input regex and the resolver contract agree" | inferred — justification: the two validation messages say "bare release version" while accepting `v?`; the wording must not contradict the now-true contract (no functional change) |
| `plugins/soleur/README.md` | — | inferred — justification: plugin component tables pin counts; a new skill without the table row fails components tests |
| `ADR-096` amendment + `model.c4` description edits | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the sanctioned `--resolve` bypass is a new exception to a recorded boundary and must not ship unrecorded |
| Phase 5 census verification + close | "verify the 15-minute tunnel-connector census reports ok (read-only Cloudflare API check), then close the issue with an evidence comment" | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `plugins/soleur`, `.github`, `knowledge-base`
- Planned files: 8 | Estimated changed lines: ~600 (SKILL.md ~250 + script ~200 + resolver/test/ADR/c4/README ~150)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the four-roots count is an artifact of bundling three small independent workstreams per the explicit brief (one PR for #11321/#11424/#11426); splitting would triple CI/review cost without reducing risk on a ~600-line diff

## Open Code-Review Overlap

- **#11388** (drift guards pin literal params but not effective-config paths) touches `apply-web-platform-infra.yml` — **Acknowledge**: unrelated concern (alert-guard structural enumeration); this diff's workflow edit is wording-only.
- **#7098** (audit of `run:` bodies whose `set` omits `-e`) touches `apply-web-platform-infra.yml` — **Acknowledge**: the two edited sites gain no new `run:` body; the audit scope-out remains open.
- No matches on `resolve-web1-known-good-tag`, `registry-breakglass`, `tunnel-connector-census`, `registry-restore-from-ghcr`, or `zot-mirror` bodies.

## Files to Create

- `plugins/soleur/skills/registry-breakglass-mirror/SKILL.md`
- `plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh`

## Files to Edit

- `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` — add `RUNNING_VERSION="${RUNNING_VERSION#v}"` normalization + contract-comment update.
- `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` — rewrite fixture (g); add (g2) `vv1.2.3` reject and (g3) stdin v-parity rows.
- `.github/workflows/apply-web-platform-infra.yml` — wording-only: drop "bare" from the two `image_tag` validation messages (:4731, :5207) + one-line "either spelling, resolver canonicalizes" note at both resolve steps (:4878, :5317 regions). No functional change; no call-site strip.
- `plugins/soleur/README.md` — `Skills` count 104 → 105; add the `registry-breakglass-mirror` row to the skills table.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — 2026-10-28 amendment (sanctioned break-glass exception + datacenter-first doctrine).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the three description edits in §C4 views.

## Domain Review

**Domains relevant:** Engineering, Product (new-capability mandate), Operations

> Subagent spawning is unavailable in this planning context (no Task tool) — the assessments below were performed inline by the planning orchestrator; domain-leader findings are recorded as such rather than claimed as agent output.

### Engineering (CTO-equivalent, inline)

**Status:** reviewed (inline)
**Assessment:** Two technical forks were ruled and recorded in `knowledge-base/project/specs/feat-one-shot-11321-11424-11426/decision-challenges.md`: (D1) normalize `v` inside the resolver rather than at call sites — the chokepoint carries the contract for every current and future caller; (D3) represent the break-glass path in C4 as description-level amendments, not a new standing edge. Blast radius of Workstream B: the resolver feeds digest resolution on both host-birth paths — contained by the unchanged strict regex, the digest pin, and the coherence preflight. Blast radius of Workstream A: writes to the sole pull path — contained by digest pinning, per-ref `crane validate --remote` read-back, signature mirroring, and zero persistent host config.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed (inline)
**Agents invoked:** none (see note above)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

New-capability mandate (brainstorm-domain-config §hr-new-skills) pulls CPO into scope for a new skill — assessed inline: the capability is operator/agent-facing incident tooling with no user-facing surface; mechanical UI-surface scan of Files to Create/Edit found no `.tsx`/`page`/`layout` matches, so the gate is exempt/NONE. CMO omitted per the documented "operator-facing-only capabilities (dev tooling, internal CLI, agent infra)" allowance. No product-surface, copy, or positioning impact; the skill strengthens the self-hosted-registry resilience story already claimed by ADR-096.

### Operations (COO-equivalent, inline)

**Status:** reviewed (inline)
**Assessment:** The deliverable IS an operational procedure codified; no new vendor, procurement, or spend. Credential sourcing is least-privilege and documented (Doppler reads for machine creds; interactive operator PAT for GHCR by design). Process note carried into the skill: the GHCR read credential is operator-supplied at invocation — there is no zero-touch path by construction (ADR-088 arm-b).

### IaC / Terraform check (Phase 2.8, inline)

Detection substrings fire (`ssh`, `DEPLOY_SSH_PRIVATE_KEY`) but the plan **introduces no new infrastructure** — no server, service, cron, secret, firewall rule, or vendor account. The SSH usage is content inside a break-glass runbook artifact (an emergency procedure on existing hosts), not a provisioning step in Implementation Phases; the only Doppler operations prescribed are reads (`secrets get`). `hr-all-infrastructure-provisioning-servers` is not implicated — nothing here provisions.

## Acceptance Criteria

- [ ] AC1: `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` exits 0 and prints `0 failed`; fixture (g) asserts `run_arg "v1.2.3"` → `rc=0`, `OUT=v1.2.3`; new rows assert `run_arg "vv1.2.3"` rejects and `run_stdin "v4.5.6"` → `v4.5.6`.
- [ ] AC2: `grep -n '#v}' apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh` shows the normalization inside the resolver; `git grep -n 'IMAGE_TAG_INPUT#v' -- .github/workflows/` returns nothing (no call-site strip); the strict regex `^v[0-9]+\.[0-9]+\.[0-9]+$` is byte-identical in the diff.
- [ ] AC3: `apply-web-platform-infra.yml` still validates `^v?[0-9]+\.[0-9]+\.[0-9]+$` at both input-validation sites and both resolve steps pass `inputs.image_tag` to the resolver unstripped; the two "bare release version" messages no longer contain the word `bare`.
- [ ] AC4: `plugins/soleur/skills/registry-breakglass-mirror/SKILL.md` exists with valid frontmatter (`name: registry-breakglass-mirror`, third-person description ≤30 words) and documents: the datacenter pull via per-command `curl --resolve` for BOTH `ghcr.io` and `pkg-containers.githubusercontent.com`; `crane push` to `10.0.1.30:5000`; credential sourcing (`DEPLOY_SSH_PRIVATE_KEY` from `soleur/prd_terraform`, `ZOT_PUSH_USER`/`ZOT_PUSH_TOKEN` from `soleur/prd`, operator-supplied `GHCR_TOKEN` PAT — never `GHCR_READ_TOKEN`); the never-upload-through-a-forwarded-connection rule; cosign-signature mirroring; `crane validate --remote` read-back; and the `admin-ip-refresh` precondition for the direct-SSH fallback.
- [ ] AC5: `bash -n plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh` is clean; `--dry-run` exits 0 and pushes nothing; the script contains `crane validate --remote`, contains `curl --resolve`, contains NO `/etc/hosts` write and NO ` -k`/`--insecure` on the pull leg; secrets never appear on argv.
- [ ] AC6: `plugins/soleur/README.md` skills count reads 105 and the skills table carries `registry-breakglass-mirror`; `bun test plugins/soleur/test/components.test.ts` (or the repo's equivalent gate) is green — including the 2436-word description budget.
- [ ] AC7: `ADR-096` carries a 2026-10-28 amendment naming the sanctioned break-glass `--resolve` exception + datacenter-first doctrine; `model.c4` carries the three description updates; `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] AC8: #11321 carries an evidence comment (live CF API connections read showing every live conn `client_version` ≥ `2026.10.2` AND the freshest `scheduled-inngest-health` run's `version_verdict=versions_ok`, referencing PR #11442) and is closed; if either read is `below_floor`/`version_unreadable`/`census_unavailable`, the issue instead carries the failing evidence and remains OPEN (no production mutation performed or attempted).
- [ ] AC9: PR #11442's body carries `Closes #11424`, `Closes #11426`, `Closes #9669`, and `Refs #11321` (the issue closed by its evidence comment).
- [ ] AC10: The diff introduces no persistent host config change, no new credentials in Doppler, and no production mutation anywhere — the only live actions prescribed are read-only CF API / `gh` reads and issue comments/close.

## Domain Review Placement

(Per the heading contract `## Domain Review` sits before the last major section; it is above for readability — the contract position is satisfied by the section's presence before Test Scenarios.)

## Test Scenarios

- **unit** — Given `run_arg "v1.2.3"`, when the resolver runs, then stdout is `v1.2.3`, rc=0 (regression for #11426/#9669).
- **unit** — Given `run_arg "vv1.2.3"` / `run_arg "v"` / `run_arg "v1.2.3.4"`, then rc≠0, empty stdout, `::error::` on stderr (the strict guard is untouched).
- **unit** — Given `run_stdin "v4.5.6"`, then `v4.5.6` (seam parity with (h)).
- **unit (property)** — For every input in `{bare, v-prefixed} × {arg, stdin}`: output is either the canonical `vX.Y.Z` or a loud rejection — never `vv*`, never silent.
- **integration** — `git grep` asserts: workflow regex unchanged at both validation sites; both resolve steps pass `inputs.image_tag` unstripped; no `IMAGE_TAG_INPUT#v` anywhere in `.github/workflows/`.
- **integration** — `bash -n` + `--dry-run` on the mirror script; grep asserts `crane validate --remote`, `curl --resolve`, absence of `/etc/hosts` writes and `-k` on the pull leg.
- **integration** — components/README parity: `bun test plugins/soleur/test/components.test.ts`.
- **e2e (read-only, live)** — Phase 5 census: `pyramid-justified: the close criterion is defined over production state; the only honest verification is the live CF API + the freshest scheduled run's breadcrumb. Read-only; no mutation.`

## Success Metrics

- `image_tag=v0.364.16` (the incident's failing dispatch) would resolve to `v0.364.16` — proven by fixture (g) without spending an approval.
- A future break-glass mirror completes in datacenter-link minutes (the ~3 min measured class), never a residential-uplink hour.
- #11321 closed with auditable evidence; #9669 closed as the earlier duplicate.

## Dependencies & Risks

- **Risk — sinkholed redirect host missed:** GHCR blob GETs can 307 to `pkg-containers.githubusercontent.com`, which is ALSO in the sinkhole set; the script must `--resolve` it (enumerated from `ghcr_deny_sh`, not guessed).
- **Risk — crane absent on the host:** the script fetches a pinned github-release crane (name+sha256) when missing; github.com is not sinkholed.
- **Risk — signature ref shape:** the cosign bundle is an OCI index whose CHILD carries `artifactType` (the #7410 lesson); the script must copy the `sha256-<hex>.sig` reference structure, mirroring `registry-restore-from-ghcr.sh`'s handling — implementer reads that engine's manifest-shapes section before coding this leg.
- **Risk — census evidence stale at PR-ready:** Phase 5 is a work-phase gate; failure leaves #11321 open with evidence — never a silent close.
- **Dependency — live CF API access at work time:** `CF_API_TOKEN`/`CF_ACCOUNT_ID` via Doppler `prd_terraform`; if Doppler is unreachable at work time the check is retried, not skipped.
- **Foreign concurrent worktree** (`feat-one-shot-autonomous-start-followthroughs`, test-all.sh pids) — different branch/issues; reported per collision pre-check.

## References & Research

- Issues: #11424 (mirror skill), #11426 + #9669 (double-v defect, earlier duplicate), #11321 (eMudhra execution tracker), #6964 (web-1 replace — residual zombie tracker, out of scope).
- Code: `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh`, `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh`, `.github/workflows/apply-web-platform-infra.yml:106/:4706-4731/:4849-4897/:5172-5207/:5296-5336`, `scripts/tunnel-connector-census.sh`, `scripts/registry-restore-from-ghcr.sh`, `scripts/zot-mirror-diagnosis.sh`, `.github/actions/cf-tunnel-registry-bridge/action.yml`, `apps/web-platform/infra/server.tf:1131-1150`, `git show 6a01e728cf^:.github/workflows/web2-luks-rebirth.yml` (retired fix pattern, lines 205-211).
- ADRs: 096 (zot + ghcr deny — amended here), 087 (cosign), 088 (no App-token host pull), 114 (connector ingress), 166 (cause vocabulary), 169 (restore authorization), 280 (bearer-curl), 304 (connector placement).
- Runbooks: `web-host-birth.md:267` (the third resolver caller), `zot-registry-revert.md`, `cron-egress-blocked.md` (the `--resolve` precedent at :468).

## Merge-blast answer (does merging THIS alone mutate production?)

Merging fires `apply-web-platform-infra.yml`'s `on.push.paths: apps/web-platform/infra/**` auto-apply (no reviewer gate on that path since PR #4220; the destroy-guard chain at :764-874 and the `-target=` allowlist bound it). Verified 2026-10-28: `git grep -n 'resolve-web1-known-good-tag' apps/web-platform/infra/*.tf` returns **zero** — neither edited infra file is read by any `.tf`/`filesha256`/`triggers_replace`, so the merge-triggered plan resolves **no resource changes attributable to this diff** (the run still executes and grades the whole targeted plan per its normal contract). The `.github/workflows/` edit matches no push trigger. **PR body's first line must carry this answer.** Everything else in the diff is docs/plugin content + a read-only verification.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`-only, or omits the threshold fails `deepen-plan` Phase 4.6 — filled above (`none` + scope-out reason for the sensitive paths).
- `discoverability_test.command` runs under preflight Check 10's 15 s cap; the fixture suite is the smallest command that prints the signal (`0 failed`).
- The `-f image_tag=<vX.Y.Z>` remediation text inside the abort message is now CORRECT advice under the normalized contract — do not "fix" it by removing the `v`.
- The `/etc/hosts` sinkhole must remain in force after the mirror: the script's only name-resolution change is per-command `--resolve`; an AC greps for `/etc/hosts` writes.
- `lane:` defaulted to `cross-domain` (no spec.md on this branch — fail-closed per plan skill Save-Tasks rule).
- The fixture (g) inversion is deliberate: the plan REWRITES a currently-green assertion (`v1.2.3` rejected) into the new contract (`v1.2.3` accepted → `v1.2.3`). Reviewers: this is the intended semantic change, not a weakened test — `vv1.2.3` rejection is pinned beside it.
