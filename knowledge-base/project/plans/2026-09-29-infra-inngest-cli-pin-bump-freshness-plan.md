---
title: "chore(infra): bump pinned inngest CLI off v1.19.4 in its own window, with pin-freshness monitoring"
date: 2026-09-29
type: chore
issue: 7463
branch: feat-one-shot-7463-inngest-cli-pin-bump
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(infra): bump pinned inngest CLI off v1.19.4 in its own window, with pin-freshness monitoring

Spec lacks valid `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-29 via `soleur:deepen-plan` (executed inline — this harness
has no subagent-spawn tool; every prescribed fan-out — skills, learnings, per-section
research, review agents — was run as an orchestrator pass with
`Reviewed-Coverage: sequential-fallback`, never claimed as independent review).
**Sections enhanced:** Premise Validation (propagation chain), Proposed Solution
(poll exit semantics + labels), Technical Considerations (notifier + GH-Actions
justification), Guard Contract (failure-text directionality + parity pin), IaC/Apply
path (auto-mint), Downtime & Cutover (NEW), Observability (discoverability fix),
AC (ops-remediation `Ref` correction + tracker preconditions), Rollback (NEW),
Sharp Edges (5 additions).

**Gate results:** 4.6 User-Brand pass · 4.7 Observability pass AFTER one real reject
(suite-shaped `discoverability_test.command` → replaced with
`inngest-cli-pin-probe.sh`) · 4.8 PAT clean · 4.9 no UI · 4.10 Encryption Posture
pass · 4.11 Guard Contract lint green (1 entry) · 4.55 Downtime halt FIRED → section
added · 4.5 evaluated — keyword hits are incidental nouns, no connectivity
hypothesis, no provisioner-driving apply in scope.

### Key Improvements

1. **Corrected "merge is inert" → "host-inert but pipeline-active":**
   `mint-inngest-bootstrap-tag.yml` watches `apps/web-platform/infra/inngest*` and the
   pin is a watched input — merging PR-A auto-mints a `vinngest-v*` tag, builds the
   image, and opens the cloud-init pin PR (ADR-232). The operator window is the
   downstream pin-PR + deploy dispatch, not the bump merge.
2. **`Closes #7463` → `Ref #7463` on BOTH PRs** (ops-remediation convention): the
   issue's core deliverable lands at the apply window that post-dates both merges.
3. **Goose-migration evidence hardened the window:** upstream auto-migrates on
   `start`; the delta contains destructive cleanup migrations (v1.22.0's
   `apps_unique_active_name`) → Postgres backup is now a named pre-flip precondition
   and the re-spike enumerates the migration census.
4. **Poll mirror fully specified:** `action-required` label + zot exit semantics
   (drift→issue+rc0, detector-fail→nonzero) + parity-pinned clone guard.

### New Considerations Discovered

- `inngest_cli_sha256_arm64` is NOT in the mint's watched `PINS` set (arm64-only
  drift mints nothing — recorded).
- Upstream's built-in update notifier is suppressed under non-TTY/`CI` — the
  committed monitor is the only operative signal.
- The self-monitoring circularity argument (the freshness probe must not run on the
  substrate it monitors) independently settles GH-Actions-vs-Inngest-cron.

## Overview

Move the pinned self-hosted Inngest CLI (`inngest_cli_version`, currently `v1.19.4` in
`apps/web-platform/infra/inngest.tf`'s first `locals` block) to the current upstream
release, in its own change window — the issue is explicit that this must not share a
window with the #6178 cutover, because one-way goose migrations run against a Postgres
the co-located v1.19.4 host shares. In the same change, add the pin-freshness monitoring
#7308 asked for, absorbed into #7463: the remediation the monitor recommends (the bump)
exists here and only here.

The change ships as **two PRs** (operator-imposed UNTRUSTED-CI rule — see §PR split):

- **PR-A** — the pin bump, both arch checksums from one release `checksums.txt`, the
  provenance sidecar, the offline staleness/coherence gate + mutation battery, the
  ADR-100 re-spike evidence, and every `v1.19.4`-pinned follower comment re-verified or
  corrected. **No workflow edits** — admin-merge is authorized when CI is green.
- **PR-B** — the detection half's trigger: a `Detect inngest CLI pin drift` step on the
  existing `.github/workflows/rule-audit.yml` (1st + 15th cron, already
  `issues: write`), plus its workflow-guard suite. Workflow edit → **normal,
  review-gated merge, NOT admin-merge**.

This PR lands code/config only. The host-side binary bump reaches production later, in
an operator-gated apply/dispatch window — out of scope for both PRs, tracked by a
follow-through issue this plan prescribes (§Non-goals).

## Premise Validation

Everything the feature description cites was checked on 2026-09-29; the load-bearing
items were probed against the actual binaries, not inferred:

- **#7463 OPEN, #7308 OPEN** (`gh issue view 7463|7308 --json state`). #7463's body
  absorbs #7308's pin-freshness requirement; #7308's remaining items (running-version
  surface on `/hooks/deploy-status`; the SDK major is separately tracked in #8628)
  stay out of scope → the PRs say `Ref #7308`, never Closes/Fixes/Resolves.
- **Pin anchor verified**: `apps/web-platform/infra/inngest.tf` first `locals` block
  carries `inngest_cli_version = "v1.19.4"`, `inngest_cli_sha256` (amd64,
  `d023b266…d757`), `inngest_cli_sha256_arm64` (`30a3f014…8199`).
  `local.inngest_arch = startswith(var.inngest_server_type, "cax") ? "arm64" : "amd64"`
  (`inngest-host.tf`) — amd64 today (cpx22); arm64 is the unused ternary arm, as the
  issue states.
- **`vendor-pin-verify.yml` has zero inngest mentions** — re-measured
  (`grep -c -i inngest` → 0), and it is the wrong home anyway: it is a PR-time
  NOTICE-blob gate with no `schedule:` trigger.
- **Merge is host-inert but pipeline-active** — two facts measured, not assumed:
  (a) `hcloud_server.inngest`, its volumes, its network and firewall, and the
  dedicated `random_id`/`doppler_secret` set are all in `OPERATOR_APPLIED_EXCLUSIONS`
  (`plugins/soleur/test/terraform-target-parity.test.ts`); the per-merge apply
  allow-list in `apply-web-platform-infra.yml` does not target them; the dispatch jobs
  (`apply_target=inngest-host` / `inngest-host-replace`) are operator-gated. No merge
  can mutate the running host.
  (b) BUT the merge is not quiet: `mint-inngest-bootstrap-tag.yml` fires on
  push-to-main over `paths: apps/web-platform/infra/inngest*` and its script re-decides
  from HEAD vs the newest merged `vinngest-v*` tag. The watched image-input set is
  `PINS=(inngest_cli_version inngest_cli_sha256 vector_version vector_sha256)`
  (`mint-inngest-bootstrap-tag.sh:380`) — **a version/amd64-sha bump IS a watched
  input**, so PR-A's merge automatically mints the next `vinngest-v*` tag on main's
  tip, dispatches `build-inngest-bootstrap-image.yml` (builds, SHA-verifies, pushes to
  GHCR + zot mirror), and its `bump-cloud-init-pin` job (ADR-232) opens the cloud-init
  pin-bump PR as the `soleur-ai` App. Those are repo/registry writes by design — the
  host flip still waits on that auto-PR's merge plus the operator's deploy/replace
  dispatch. **`inngest_cli_sha256_arm64` is NOT in the watched set** — an arm64-only
  drift would mint nothing (arm64 rides the cloud-init template var only; Sharp Edges).
- **Upstream measured, not assumed**: `gh api repos/inngest/inngest/releases/latest`
  → **v1.45.1** (published 2026-09-17T20:51:40Z). A published-desc release walk puts
  `v1.19.4` at position 33 of 271 releases (i.e., ~32 releases behind as of
  2026-09-29 — the plan records this measurement, not the issue's conflicting
  "22"/"27"; the true delta is recomputed by tag-ordered walk at bump time, per the
  issue).
- **Release assets verified**: `v1.45.1` (and `v1.19.4`) ship exactly
  `checksums.txt` + per-OS tarballs; **no detached `.sig` exists on either release** —
  the issue's "signed checksums.txt" is loose language for *the single
  release-shipped* checksums.txt. The plan does not prescribe a signature-verification
  step that cannot pass.
- **Binary probes performed at plan time** (both tarballs sha256-verified against
  their own release `checksums.txt` — the v1.19.4 amd64 hash matches the committed pin
  `d023b266…` end-to-end):
  - All flags the repo passes exist on **both** versions: `--host --port
    --sqlite-dir --postgres-uri --redis-uri --postgres-max-open-conns
    --postgres-max-idle-conns --postgres-conn-max-idle-time --poll-interval
    --sdk-url --signing-key`. None removed.
  - **`--postgres-conn-max-idle-time` is still an IntFlag in MINUTES** on v1.45.1
    ("in minutes", default 5) — the #6258 unit trap verified against the new binary's
    own help; the work-phase re-spike re-verifies units against the pinned tag's
    `cmd/start` **source**, per the issue.
  - **`--signing-key` on v1.45.1: "Must be hex string with even number of chars"** →
    the `signkey-prod-` strip (inngest-bootstrap.sh
    `${INNGEST_SIGNING_KEY#signkey-prod-}`) is still required and still sufficient.
    `INNGEST_SIGNING_KEY` remains an env input (36 string references in the binary).
  - **`inngest pause` exists on NEITHER v1.19.4 NOR v1.45.1** — the drain call in
    `inngest-bootstrap.sh` (`"$INSTALL_PATH" pause || log warn …`) is dead code *on
    the live version already*; today's upgrade drain is the `DRAIN_SLEEP_SEC` sleep
    alone. Pre-existing defect, not a bump regression → triaged to a follow-up issue
    (§Non-goals), recorded in the sidecar.
  - v1.45.1 adds `--connect-{executor,gateway}-grpc-{ip,port}` flags, all defaulting
    to loopback IPs — new listener surface to sanity-check in the re-spike, not a
    removal.
- **Suite registration verified**: `run-registered-suites.sh` derives the registered
  set **from the filesystem** (`apps/web-platform/infra/**/*.test.sh` presence; the
  shard TSV is duration tuning with hash-fallback for untabled labels). PR-A needs no
  workflow edit.
- **The `ci-deploy.test.sh` start-writer inventory** pins `systemctl`
  start/restart/enable verb lines against `inngest-server` (19 lines across 10 files).
  Required only if the diff adds a writer line — the bump adds none; the check is
  conditional (see AC).
- **C4 checked (all three files read, not grepped)**: `model.c4` has the `inngest`
  container (no version claim in its description) and `projectZot` (the `#external`
  upstream-system pattern). **No element and no edge models the upstream
  `inngest/inngest` release downloads** — yet `inngest-bootstrap.sh` `curl`s
  `github.com/inngest/inngest/releases/download/…` at host runtime, and
  `build-inngest-bootstrap-image.yml` downloads + sha-verifies at image build. Two
  live edges, unmodeled — a genuine C4 gap this plan fixes (§ADR/C4).
- **No matching brainstorm** (this feature entered via one-shot, skipping brainstorm);
  no `spec.md`/`specs/` dir exists for this branch yet.

## Mechanism Minimality — Property List & Cut List

**Property list** (the ask restated as observable outcomes):

- **P1** — `inngest_cli_version` names a current upstream release, and both arch
  checksums are traceable to the ONE `checksums.txt` shipped in that release.
- **P2** — a named, automated signal fires when the pin drifts behind upstream or the
  analysis of record ages, filed as ONE idempotent, actionable issue whose remediation
  is the bump procedure.
- **P3** — confidence the new version preserves the repo's load-bearing invariants:
  ADR-100's three Phase-0 findings, the `--postgres-max-open-conns` durable sentinel,
  the `signkey-prod-` strip, and every flag unit — verified against the new version's
  binary/source, never assumed.
- **P4** — every artifact that encodes or asserts v1.19.4-scoped claims moves in
  lockstep with the pin or is explicitly re-verified unaffected.

**Mechanism coverage check** (grepped, per `hr-verify-repo-capability-claim-before-assert`):

| Property | Existing mechanism that covers it? |
|---|---|
| P1 | None — the bump IS the change. |
| P2 | None. Verified: no inngest mention in `vendor-pin-verify.yml`; `rule-audit.yml` carries the zot poll but no inngest step. The zot/cosign precedent supplies the shape — reused, not reinvented. |
| P3 | None for the new version. The v1.19.4-pinned comments are claims, not coverage; the re-spike re-establishes them. |
| P4 | Partially — the binary consumers (`build-inngest-bootstrap-image.yml`, `inngest-bootstrap.sh`) read the locals at build/run time; the ~17 follower files carrying `v1.19.4`-pinned behavioral claims are enumerated in §Files to Edit. |

**Cut list**:

| Mechanism considered | Property | Verdict |
|---|---|---|
| A NEW `scheduled-*.yml` workflow for the poll | P2 | CUT — a step on existing `rule-audit.yml` covers it (same shape as the zot step; also dodges the `new-scheduled-cron-prefer-inngest` hook). |
| An Inngest-cron poller (`safeCommitAndPr`) | P2 | CUT — same rejection as the zot plan's Option B: four new moving parts to produce a draft artifact a human-opened PR already delivers better. |
| Hand-editing `suite-shard-legs.tsv` to register the new suites | P2-enforcement | CUT — registration is filesystem-glob; untabled labels hash-fallback. The next `regenerate-shard-manifest.py --group infra` run tables them. |
| Any host-side bump step (tag push, dispatch, apply) | P1-live | CUT — operator-gated window, out of scope per the constraint; tracked by a follow-through issue instead of an in-PR step. |
| Running-version field on `/hooks/deploy-status` | (would serve P2) | CUT — belongs to #7308's remaining scope, stays there. |

## Research Insights

**Repo anchors (all verified this session):**

- Pin: `apps/web-platform/infra/inngest.tf` first `locals` block
  (`inngest_cli_version`, `inngest_cli_sha256`, `inngest_cli_sha256_arm64`).
- Consumers of the pin — the full propagation chain, all verified:
  `build-inngest-bootstrap-image.yml` greps `inngest_cli_version` + `inngest_cli_sha256`
  from `inngest.tf` at image build, downloads the amd64 tarball, sha-verifies, and
  bakes `INNGEST_CLI_VERSION`/`INNGEST_CLI_SHA256` into the image env → the dedicated
  host reads the VERSION from that image env (`cloud-init-inngest.yml:1164`,
  `docker inspect`) while its cloud-init **overrides** the image's amd64-only sha with
  the arch-matched template var (`inngest-host.tf:357-358` →
  `cloud-init-inngest.yml:1165-1168`) → `inngest-bootstrap.sh` builds `DOWNLOAD_URL`
  from version+arch and sha256-verifies on the host → on `deploy inngest` /
  re-provision it detects the version mismatch and drains/restarts (~5s downtime on
  loopback, per the runbook's "CLI version bump" section). The web hosts' co-located
  inngest rides the same bootstrap-image env path. `mint-inngest-bootstrap-tag.yml`
  (`paths: apps/web-platform/infra/inngest*`) auto-mints the `vinngest-v*` tag +
  dispatches the build on any image-input change; `bump-cloud-init-pin` (ADR-232)
  authors the cloud-init image-pin PR.
- Follower files carrying the amd64 sha256 literal: `inngest-userdata-budget.sh` (a
  size-fixture stub inside a synthesized `terraform console` vars map — 64-hex shape is
  what matters; still updated in the bump so `git grep <old-sha>` returns zero).
- `v1.19.4`-pinned behavioral claims live in: `inngest-inventory.sh`,
  `inngest-enumerate-reminders.sh`, `inngest-doublefire-probe.sh`,
  `inngest-wiped-volume-verify.sh`, `ci-deploy.sh`, `betterstack-logs-alerts.tf`
  (error-text needles), `scripts/cutover-inngest.sh`, `inngest-host.tf` header,
  `inngest-bootstrap.sh` (the #6258 unit comment), plus matching `.test.sh` fixtures
  and `tests/scripts/test-inngest-host-dark-gate.sh` (a `cli_version=v1.19.4` fixture).
- Flag surface the repo passes (ExecStart, inngest-bootstrap.sh
  `@@BACKEND_FLAGS@@`/shared prefix): `--host 0.0.0.0 --port 8288 --sqlite-dir
  /var/lib/inngest` + durable-branch-only `--postgres-max-open-conns 5
  --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 1` + `--poll-interval 60
  --sdk-url <url>`; secrets via env (`INNGEST_POSTGRES_URI`, `INNGEST_REDIS_URI`,
  `INNGEST_SIGNING_KEY` stripped of `signkey-prod-`). The sentinel ordering
  (`--postgres-max-open-conns` FIRST in BACKEND_FLAGS) is load-bearing for
  `inngest-inventory.sh`, `inngest-server-flip-guard.sh`,
  `inngest-wiped-volume-verify.sh`, `cloud-init-inngest.yml`, `ci-deploy.sh`, and
  `inngest.test.sh`.
- Precedent of record: `knowledge-base/project/plans/2026-08-04-chore-zot-image-pin-bump-and-freshness-cadence-plan.md`
  (the same change shape — pin bump + freshness owner — already adjudicated through
  review) and its artifacts: `zot-image.provenance.md`,
  `zot-image-staleness.test.sh`, `zot-image-staleness-mutation.test.sh`,
  `cosign-trusted-root-staleness.test.sh` + `cosign-trusted-root.provenance.md`, and
  the `Detect zot pin staleness` step in `rule-audit.yml`.
- Spike methodology of record:
  `knowledge-base/project/specs/feat-inngest-dedicated-host/phase0-empirical-spike.md`
  (local docker harness — server, redis, two Postgres containers, two SDK apps — zero
  production touch).
- ADR-100's three Phase-0 findings (established vs v1.19.4, to re-spike): (1) fan-out
  routing is ROUTE-ONCE — same-app-id `--sdk-url`s collapse to one app,
  last-writer-wins serve URL with flap; (2) cron runs enumerable via top-level
  `runs(filter: RunsFilterV2!)`, `scheduled_tick` nonexistent,
  `cronSchedule`/`eventName` null, `startedAt` reliable; (3) Redis `FLUSHALL` before a
  Postgres flip is MANDATORY (retained queue keys + idempotency keys mis-execute).

**Institutional learnings applied:**

- `2026-03-20-checksum-verification-binary-downloads.md` — embedded checksums >
  downloaded checksums; the bump procedure downloads tarballs + `sha256sum -c`s them
  against the *embedded* values (not merely trusting the checksums file that ships
  from the same host).
- `2026-05-16-sha-pin-prefix-match-false-positive-in-plan-verification.md` — verify
  the bump with full-length 64-hex greps anchored on the assignment, never prefixes.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — the gate ships with anti-vacuity floor + positive control + a mutation battery,
  not as an afterthought.
- `2026-07-29-my-guard-tested-the-one-case-that-cannot-happen-in-production.md` — the
  gate's mutations are design-derived (swap in ONE file; coherent-swap is honestly
  declared the poll's job, not claimed offline).
- `2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md` — the age-gate
  is a backstop for the poll's own failure, not a duplicate trigger.
- `2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms.md` —
  applies to the spike harness lifecycle (containers must be reaped even when a
  finding aborts mid-run — the phase0-empirical-spike cleanup convention).
- `2026-05-29-provider-migration-issue-verify-pinned-beta-schema-before-planning.md`
  — version-scoped claims (the ~17 `v1.19.4` comment pins) are verified against the
  target version, not re-asserted.
- `2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing.md`
  — applied twice: (a) the gate's failure text names the reconciliation direction
  (sidecar is authoritative, never "just make them agree"), and (b) a forced
  `-replace` from a stale pin ships nothing — the reason the bump and the monitor are
  one change, not a monitor watching a pin nobody can move.
- `2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md` — the
  PR-B workflow step is a copy-adapted clone of the zot step; the workflow-guard suite
  parity-pins the shared skeleton (rc semantics, label idempotence, upsert shape)
  rather than loosely re-deriving it — the failure mode that shipped a permanently-red
  gate the first time this class was written.
- `2026-09-28-a-stale-but-signed-image-is-caught-by-the-version-it-was-built-as.md` —
  a stale-but-validly-signed image is caught by its build tag, not its signature; the
  cloud-init pin PR's `tag@sha256:` compound reference is the freshness carrier for
  the image leg, our monitor is the carrier for the upstream-CLI leg — the two are
  complementary, non-overlapping.
- `2026-04-06-doppler-cli-checksum-cloud-init.md` — the cloud-init-templated
  checksum pattern this plan's arch-ternary sha already follows; nothing new needed.
- `2026-06-18-inngest-secrets-env-not-argv-and-detection-sentinel-swap.md` — secrets
  flow via `INNGEST_*` env, never argv (systemd unit leaks argv into `ps`); the
  re-spike's signkey check verifies the env path stays the input, not just the flag.

**External research:** a targeted upstream-docs sweep ran at deepen time (the
plan-time fan-out was deliberately skipped — the committed zot precedent is a stronger
authority for this exact shape). It produced two load-bearing corrections: (a)
upstream **auto-runs goose migrations on `start`** and the helm upgrade note
prescribes backups before upgrading — now a follow-through precondition and a
Downtime-&-Cutover bound; (b) upstream ships its own update notifier, inert under
our non-TTY unit — recorded so nobody later claims it as the freshness mechanism.
Current flag docs corroborate the MINUTES units on both `conn-max-*` flags.

**Domain-leader / specialist note:** this planning run executes inside a harness
without a subagent-spawn tool, so research and review agents the skill prescribes as
Tasks were executed inline by the orchestrator; the inline substitutions are recorded
wherever a section would otherwise cite an agent.

## Research Reconciliation — Issue vs. Codebase

| Issue/spec claim | Reality (verified) | Plan response |
|---|---|---|
| "Both arch checksums from ONE signed checksums.txt" | `checksums.txt` exists per release (sha256sum format); **no detached signature** on either release | Source both rows from the one file; verify each tarball by re-hash, not by trusting the file; call it "release-shipped" not "signed" |
| "22 vs 27 releases behind" | Published-desc walk: v1.19.4 at position 33/271 as of 2026-09-29 (incl. `-test`/`-beta` prereleases) | Restate neither; the bump procedure recomputes a tag-ordered stable-release delta with the command recorded |
| "`--postgres-max-open-conns` still exists" | Exists on v1.45.1 (default 100) | Plan-time verified; re-verify at pinned tag in Phase 0 |
| "`signkey-prod-` strip still holds" | v1.45.1 `--signing-key` requires bare even-length hex; `INNGEST_SIGNING_KEY` env read | Verified at plan time; re-verify at pinned tag |
| "`--postgres-conn-max-idle-time` is IntFlag in MINUTES" | v1.45.1 help: "in minutes", default 5 | Verified on the new binary; work phase re-verifies against `cmd/start` source at the pinned tag |
| "v1.19.4 drain pauses the server" (`inngest-bootstrap.sh` prose) | `inngest pause` absent on BOTH versions — dead call, drain is sleep-only | Sidecar records it; micro follow-up issue (§Non-goals); no behavior change from the bump |

## PR split (operator-imposed UNTRUSTED-CI boundary)

| | PR-A (this branch's PR) | PR-B |
|---|---|---|
| Contents | Pin bump + both checksums + provenance sidecar + offline staleness/coherence gate + mutation battery + re-spike evidence + follower-comment updates + ADR-100 amendment + C4 edits | `Detect inngest CLI pin drift` step on `.github/workflows/rule-audit.yml` + `rule-audit-inngest-pin-workflow-guard.test.sh` |
| Workflow edits | **NONE** | `.github/workflows/rule-audit.yml` only |
| Merge class | Admin-merge authorized when CI green | **Normal review-gated merge — NOT admin-merge** |
| PR body refs | `Ref #7463`, `Ref #7308` (no Closes — monitor's detection half not yet live) | `Ref #7463`, `Ref #7308` — also `Ref`, not `Closes`: the issue's core ask (the live CLI bump) only lands at the operator apply window that post-dates both merges, so `Closes` would auto-close into a false-resolved state (ops-remediation `Ref`-not-`Closes` convention). #7463 closes when the follow-through tracker's apply step is verified landed |

## Proposed Solution

### The bump

Target = the latest upstream release **at implementation time** (measured `v1.45.1`,
2026-09-17, at plan time). Procedure (the sidecar's `## Bump procedure` records it for
the next bump):

1. `gh api repos/inngest/inngest/releases/latest` → target tag.
2. Tag-ordered walk: `gh api 'repos/inngest/inngest/releases?per_page=100' --paginate`
   → position of the OLD pin among stable (non-prerelease) tags = the release delta —
   recorded with date + command; **never** the issue's 22/27 figures.
3. Fetch `<release>/checksums.txt` ONCE; extract the `linux_amd64` and `linux_arm64`
   rows — both arch values come from this ONE file.
4. Download both tarballs; `sha256sum` each and compare to the extracted rows AND to
   what is about to be embedded (embedded > downloaded — the checksums file and the
   tarballs ship from the same host; the reviewed embed is the trust anchor).
5. Edit the three `locals` lines; re-anchor the comment block to the sidecar.
6. `terraform fmt apps/web-platform/infra/inngest.tf` — `terraform fmt -check` is an
   existing `inngest.test.sh` assertion.
7. Sweep: `git grep -n 'd023b266…\|30a3f014…\|v1\.19\.4'` → zero outside
   `knowledge-base/` migration records; update the `inngest-userdata-budget.sh` stub
   row (size fixture, kept coherent anyway); correct every follower comment whose
   version-scoped claim the re-spike changed.

### The freshness owner (detection + enforcement, mirroring #7283)

- **Enforcement (PR-A, per-PR):** `apps/web-platform/infra/inngest-cli-staleness.test.sh`
  — deterministic, offline, exit-code contract `0` fresh / `10` drift / `2` detector
  failure (never overload 1). Registered by filesystem glob into the
  `deploy-script-tests` infra matrix; fires on every `apps/*/infra/**` PR via
  `infra-validation.yml`.
- **Detection (PR-B, 1st + 15th):** a `Detect inngest CLI pin drift` step on
  `rule-audit.yml`, cloned from `Detect zot pin staleness`: run the offline gate
  (honor the rc contract), parse `inngest_cli_version` anchored on the assignment,
  `gh api repos/inngest/inngest/releases/latest`, compute the tag-ordered delta, HEAD-
  probe that the pinned tarballs still exist upstream, and find-or-update ONE
  idempotent issue — `gh label create inngest-pin-drift` idempotently, then
  `gh issue create --label inngest-pin-drift --label action-required` (the
  `action-required` label is what the weekly digest harvests — zot precedent,
  `rule-audit.yml:355`); the body carries the delta, the sidecar link, and the
  `/soleur:one-shot` remediation entry point. Mirror the zot exit semantics exactly:
  **drift files the issue and the step exits 0** (the issue is the channel);
  **a probe that could not run exits non-zero** so the ops email fires — detector
  failure is never folded into "fresh".
- **Drift threshold (decided, not deferred):** the poll files when
  `releases_behind >= 5` **OR** the pinned release's upstream date is `>= 45 days`
  old — inngest ships ~weekly (v1.19.4→v1.45.1 spans ~4.5 months at
  ~5.8 days/release), so the zot
  "any delta" rule would mint a permanently-open ticket within days of every bump.
  The threshold is recorded in the step AND in the sidecar so the two cannot diverge.
  The offline age gate (`MAX_AGE_DAYS=60` on the sidecar's Capture-date field) is the
  independent backstop for the poll's own failure — the two mechanisms are different
  failures, not redundancy.
- **Analysis of record:** `apps/web-platform/infra/inngest-cli.provenance.md`,
  mirroring `zot-image.provenance.md` / `cosign-trusted-root.provenance.md` — pinned
  version, upstream release date, capture date, both arch rows + the checksums.txt URL
  they came from, the previous known-good pin (rollback target), the flag/sentinel
  re-verification table, `## Bump procedure`.

### The re-spike (P3, work Phase 0 — all local)

Replay `phase0-empirical-spike.md`'s docker harness against the pinned NEW version
(server + redis + two Postgres containers + two SDK apps; no production writes — the
constraint only forbids production mutations):

1. Flag surface: `inngest start --help` at the pinned tag; every flag the repo passes
   still exists; **units verified against `cmd/start` SOURCE at the pinned tag** (the
   `urfave/cli` IntFlag declaration and its multiplier — help text is corroboration,
   not the source). Explicitly: `postgres-conn-max-idle-time` (MINUTES on both
   endpoints measured at plan time), `postgres-conn-max-lifetime` (not passed —
   record its unit anyway so nobody "fixes" it wrongly later), `poll-interval`
   (seconds), `tick` (ms).
2. `signkey-prod-` strip: `inngest start` rejects/accepts as measured on v1.45.1 —
   re-verify on the pinned tag's binary.
3. ADR-100 finding 1 (route-once fan-out): two `--sdk-url`s, same app id → one app,
   last-writer-wins URL, flap window — re-run on the new version.
4. ADR-100 finding 2 + the follower-claim set: `runs(filter: RunsFilterV2!)`
   enumeration works; `/v1/functions` still unregistered-404 (or record the new
   status); `eventsV2` envelope shape; `startedAt` present; `cronSchedule`/`eventName`
   still null; `scheduled_tick` still absent; epoch bound still rejected as
   out-of-range `Time!`.
5. ADR-100 finding 3 (FLUSHALL mandate): re-run the Postgres-swap-with-retained-Redis
   experiment on the new version.
6. Changelog walk across the delta: flag deprecations/renames, GQL schema changes,
   log-text changes that break `betterstack-logs-alerts.tf`'s error needles or any
   probe's parse — AND an **explicit migration census**: enumerate every goose
   migration added between v1.19.4 and the target (upstream runs them automatically
   on `start` — verified; the v1.19.4→target delta includes at least one DESTRUCTIVE
   cleanup class, e.g. v1.22.0's `apps_unique_active_name` pre-archiving same-name
   duplicate apps). Each destructive/cleanup migration gets a named line in the
   respike doc + the sidecar, because that is the irreversible half of the apply
   window.
7. New-in-v1.4x gRPC listeners (`--connect-*-grpc-*`): confirm loopback binding /
   firewall posture unchanged.
8. Record everything in
   `knowledge-base/project/specs/feat-one-shot-7463-inngest-cli-pin-bump/phase0-respike-evidence.md`
   and cite the re-verified-vs-corrected verdict per claim in the sidecar.

## Technical Considerations

- **Arch-swap is the named defect class.** `local.inngest_arch` selects amd64 vs arm64
  via a ternary; a swapped pair of checksums looks well-formed and fails only on the
  (unused-today) arm arm — or, worse, on the NEXT cax provision. The gate asserts
  arch-keyed coherence in BOTH directions (tf↔sidecar), exactly like zot checks 2/4/5.
- **A coherent two-file edit can fake freshness offline.** Editing `inngest.tf` and
  the sidecar consistently to an older/wrong release passes every offline check —
  that case is the poll's job (upstream ground truth), declared, not claimed.
- **`terraform fmt` drift.** Anchors use `[[:space:]]*` around `=`.
- **Decoy-in-a-comment.** Pin assertions count exactly-once on the assignment form, so
  a commented-out old pin cannot satisfy them.
- **The stub-sha follower.** `inngest-userdata-budget.sh` embeds the amd64 sha as a
  size fixture. It is NOT part of the guard's assembly (its value is irrelevant to the
  property), but the bump updates it anyway so the old-sha grep sweep returns zero.
- **NFR impacts:** availability (scheduler substrate — the whole reason for the
  re-spike), security/supply-chain (checksum provenance), operability (the monitor).
  No new failure domain is introduced; the merge is host-inert (pipeline-active by
  design — see §Apply path).
- **Upstream's own update notifier is inert here — recorded, not relied on.** The
  inngest binary ships a "new version available" check suppressed under
  `INNGEST_NO_UPDATE_NOTIFIER`/`DO_NOT_TRACK`/`CI`/non-TTY — the systemd unit is
  non-TTY, so it never prints anywhere an operator sees. The committed monitor is the
  ONLY operative freshness signal; the mechanism-coverage row for P2 stays honest.
- **Why the poll lives on GH Actions, not Inngest cron (scheduled-work check, ran:
  54 `cron-*` functions + 17 `scheduled-*` workflows exist).** GH Actions is the
  acceptable arm here for three compounding reasons: (a) the work is purely
  repo/upstream-scoped — no app context, app secrets, or Sentry; (b) precedent — the
  sibling zot poll already lives on `rule-audit.yml`; (c) decisive — the monitor
  watches the scheduler's own substrate pin, so it must not run ON that substrate: a
  dead or mis-versioned inngest is exactly when the freshness signal must still fire
  (self-monitoring circularity).
- **SpecFlow-style edge enumeration (inline — no subagent spawn in this harness):**
  (a) upstream `releases/latest` returns a `-beta`/`-test` tag → the walk anchors on
  stable tags only, matching `^v\d+\.\d+\.\d+$` and discarding suffixes; (b) the
  checksums.txt row count or name format changes upstream → the bump procedure fails
  LOUD at step 3, never guesses; (c) pinned assets deleted/replaced upstream → the
  poll's HEAD probe catches it (mirrors zot's MANIFEST_UNKNOWN probe); (d) sidecar
  capture date in the future → FAIL, never parse-weird; (e) `releases/latest` vs the
  pin compare unequal *because* a hotfix tag exists — delta is computed tag-ordered,
  not date-ordered.

## User-Brand Impact

- **If this lands broken, the user experiences:** the sole scheduler goes dark at the
  next provisioning event or in-place upgrade — every cron, oneshot and HTTP-armed
  reminder silently stops firing (the ADR-100 `single-user incident` shape: dropped
  autonomous work with no error surfaced). The concrete artifact is
  `scheduled-inngest-health.yml` red + a dead `/hooks/deploy-status` inngest read.
  A wrong-sha256 embed is fail-closed (bootstrap refuses at verify), so the bad
  outcome is *a host that cannot run the new binary*, not a corrupt one.
- **If this leaks, the user's workflow is exposed via:** a wrong or hostile checksum on
  the binary that runs every scheduled job in the system. Mitigations in this diff:
  per-arch checksums sourced from one release `checksums.txt` and embedded as reviewed
  constants; tarball re-hash against the embedded values at bump time; the arch-keyed
  offline gate; the upstream poll (PR-B) as the only path that catches a coherent
  two-file fake; a human-opened, CI-gated PR — nothing auto-writes the pin.
  No user PII is touched.
- **Brand-survival threshold:** `single-user incident` — same class as ADR-100's own
  declaration and the zot plan's sole-pull-path framing; the merge is inert but the
  next apply is a one-way door onto the only scheduler.

Consequences: `requires_cpo_signoff: true` at plan time;
`soleur:engineering:review:user-impact-reviewer` at review; plan-review escalates to
the 5-agent panel.

## Observability

```yaml
liveness_signal:
  what: "The freshness owner itself — two legs: (a) `inngest-cli-staleness.test.sh`
         green on every infra PR; (b) the `Detect inngest CLI pin drift` step on
         rule-audit.yml (1st + 15th) that files ONE idempotent `inngest-pin-drift`
         issue. The scheduler's own liveness (heartbeat, consumer probe,
         scheduled-inngest-health.yml */15) is unchanged and out of scope."
  cadence: "per-PR (gate) / semi-monthly (poll)"
  alert_target: "GitHub issue `inngest-pin-drift` (idempotent) + RED CI check"
  configured_in: "apps/web-platform/infra/inngest-cli-staleness.test.sh;
                  .github/workflows/rule-audit.yml (PR-B)"
error_reporting:
  destination: "CI check failure (PR-time) and the filed GitHub issue (drift);
                detector failure exits rc=2 and fails the step loudly — never
                conflated with 'fresh'"
  fail_loud: true
failure_modes:
  - mode: "Bumped in repo, production still on the old binary (expected until the
           operator window)"
    detection: "pending hcloud_server.inngest user_data diff in
                scheduled-terraform-drift.yml output + the follow-through tracker
                issue (§Non-goals); the sidecar records the staged state"
    alert_route: "the drift report + tracker issue, not telemetry — no running-version
                surface exists yet (#7308, out of scope)"
  - mode: "New version fatals on this config at the apply window — scheduler
           crash-loops"
    detection: "scheduled-inngest-health.yml (*/15, existing) + betteruptime_heartbeat
                in inngest.tf; the re-spike is the pre-merge mitigation"
    alert_route: "existing health workflow → issue; NOT a new mechanism"
  - mode: "One arch bumped, the other left stale / the two shas swapped"
    detection: "inngest-cli-staleness.test.sh arch-keyed checks — per-arch pin form,
                cross-arch version coherence, sha DISTINCTNESS, tf↔sidecar arch-keyed
                equality"
    alert_route: "RED on that PR"
  - mode: "Pin bumped but sidecar left stale — changelog never read, analysis rots"
    detection: "sidecar↔tf coherence assertions + capture-date freshness in the gate"
    alert_route: "RED on that PR"
  - mode: "The poll silently breaks (token, API shape, repo rename) — the #7308
           recurrence"
    detection: "MAX_AGE_DAYS=60 sidecar-age gate — needs no network and reddens on the
                recorded date alone"
    alert_route: "RED on the next infra-touching PR + the poll's own idempotent issue
                on rc=10"
  - mode: "rc conflation — a checker that can't check reports 'fresh'"
    detection: "rc=2 detector-failure contract, positive control proving both counters
                move, MIN_ASSERTIONS floor"
    alert_route: "step fails loudly (rc=2 is fatal to the step, not an issue)"
logs:
  where: "CI job logs (gate + poll step); the monitor writes no host-side logs — the
          bump changes no running service at merge"
  retention: "Actions retention; issue history is the durable record"
discoverability_test:
  command: bash apps/web-platform/infra/inngest-cli-pin-probe.sh
  expected_output: "VERDICT=fresh"
```

### Affected-surface observability (2.9.2)

Not applicable in the blind-surface sense: the change authors no code that RUNS inside
a sandbox/container/cron worker the operator cannot inspect — the gate runs in CI and
the poll reads public upstream state. The one genuinely blind surface it *informs*
(the dedicated host's running version) is explicitly scoped out to #7308 and named as
a failure mode above rather than pretended away.

## Encryption Posture

Detection fires on `inngest.tf`. **No new store and no new connection** — this section
records the unchanged posture:

```yaml
at_rest: []
in_transit:
  - connection: "inngest host / CI image build -> github.com (inngest/inngest releases)"
    enforced_at: "apps/web-platform/infra/inngest-bootstrap.sh (curl -fsSL +
                  sha256sum verify); build-inngest-bootstrap-image.yml (same verify)"
    tls: "HTTPS / TLS >= 1.2 (github.com)"
    cert_verification: on
    does_not_defend: "a compromised upstream release asset — mitigated by the embedded,
                      reviewed sha256 constants (verify-then-extract), not by transport"
    disclosed_as: "ADR-100 + this plan + the new model.c4 inngestReleases element"
```

No `exception` block: no plaintext mechanism and no cert-off row is introduced or
widened by this change.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/inngest.tf` **only** — three `locals` values and their
comment block. No new provider, resource, variable, or `TF_VAR_*`;
`hr-tf-variable-no-operator-mint-default` does not fire.

### Apply path

**(d) — deliberately none in this PR for the host, with one designed pipeline
consequence.** `hcloud_server.inngest` and its companions are
`OPERATOR_APPLIED_EXCLUSIONS`; the per-merge apply allow-list cannot reach them, and
the sha256 template var change surfaces only as a pending `user_data` diff to
`scheduled-terraform-drift.yml`. What the merge DOES start automatically (by design,
ADR-232 + the runbook's "Bootstrap-image release" section):
`mint-inngest-bootstrap-tag.yml` → `vinngest-v*` tag on main's tip →
`build-inngest-bootstrap-image.yml` → image pushed to GHCR + zot →
`bump-cloud-init-pin` opens the cloud-init image-pin PR as `soleur-ai`. The live flip
then needs, in the operator-scheduled window: that auto-PR merged, plus a
`deploy inngest` dispatch or `apply_target=inngest-host-replace` — **after** the
shared-Postgres window the issue describes is clear, since first-boot of the new
binary runs goose migrations against it. Expected blast radius at the flip: ~5s
drain/restart on the in-place path (per the runbook) to a full host replace (minutes);
a goose migration under a dual-version fleet is the one irreversible step — the reason
the window is separate. The follow-through tracker issue carries this sequence so the
inert-merge staging cannot strand it.

### Distinctness / drift safeguards

- `inngest_cli_version`/`sha256` are env-agnostic values consumed identically wherever
  an inngest host exists; no dev/prd divergence is introduced.
- No secret enters `terraform.tfstate`.
- The staged-pin consequence (pending replace in drift output) is recorded in the PR
  body per Phase 0 P4, mirroring the zot plan's staged-merge behavior.

### Vendor-tier reality check

None — no new vendor relationship; the poll runs on Actions minutes with the built-in
`GITHUB_TOKEN`.

## Downtime & Cutover

**Trigger accounting (deepen-plan Phase 4.55):** the `locals` diff feeds
`hcloud_server.inngest`'s `user_data`, so a targeted `terraform plan` WILL render
`-/+ must be replaced` on the sole scheduler host once the pin lands. The trigger
fires; the section follows.

1. **The offline-inducing operation and surface:** a host replace or an in-place
   bootstrap re-run that swaps the running `inngest` binary on the singleton
   dedicated host — the surface is every scheduled execution in the platform
   (54 `cron-*` Inngest functions + oneshot/HTTP-armed reminders).
2. **Zero-downtime evaluation:** a singleton stateful host cannot do true
   blue-green within one host (the Postgres it serves is the point of the window).
   The designed lower-downtime path already exists and is the DEFAULT: the
   `deploy inngest` verb re-runs `inngest-bootstrap.sh`, which detects the version
   mismatch, drains, restarts, resumes — ~5s of scheduler downtime on loopback per
   the runbook. The heavier path (`apply_target=inngest-host-replace` → fresh host
   into existing volumes) is the fallback, not the default — it trades ~minutes of
   scheduler gap for a clean-slate install and is the right call only if the
   in-place path corrupts.
3. **Residual downtime + bounds + sign-off:** residual is seconds on the default
   path, inside an operator-chosen window — the dispatch is a manual
   `workflow_dispatch`/verb call, so operator sign-off is structural, not
   ceremonial. The window's OTHER bound is pre-flip: (a) the shared-Postgres
   condition from the issue (no concurrent v1.19.4 + new-version schedulers against
   the same event store while goose migrations could run), and (b) a **Postgres
   backup/snapshot before the flip** — upstream runs goose migrations automatically
   on `start` (verified via the inngest-helm upgrade note "Inngest handles database
   migrations automatically on startup. Ensure you have backups before upgrading"),
   and the v1.19.4→target delta contains at least one destructive cleanup migration
   class (e.g. v1.22.0's `apps_unique_active_name` pre-archives same-name duplicate
   apps). Both preconditions live in the follow-through tracker, not in code.
4. **Merge-time downtime: none.** The PRs change no running service; the pending
   `user_data` replace is inert until an operator-gated apply.

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-100`** (`…/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`)
with a "CLI pin freshness" clause recording: (a) the pin has a named freshness owner —
detection: the `rule-audit.yml` poll step; enforcement: `inngest-cli-staleness.test.sh`;
analysis of record: `inngest-cli.provenance.md`; (b) nothing auto-writes the pin — the
monitor files an issue and a human opens the CI-gated PR; (c) the re-spike verdicts
against the new version (each of the three Phase-0 findings restated as
holds/changed-with-evidence, citing the respike doc); (d) the `inngest pause`
absence finding (drain is sleep-only on both endpoints). No new ordinal — an
amendment, so the ADR-Ordinal Collision Gate has nothing to re-derive.

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` were read. Enumeration per the
completeness mandate:

| Category | Item | Modeled today? | Action |
|---|---|---|---|
| External system | `inngest/inngest` upstream releases (github.com release assets + API) | **NO** — the `github` element models OUR GitHub usage; the upstream binary source has no node (the `projectZot` precedent: upstream vendors get their own `#external` element) | **ADD** `inngestReleases = system "inngest/inngest upstream releases (public)"` with `#external` |
| Access relationship | `inngest -> inngestReleases` — bootstrap `curl`s the pinned tarball + sha256-verifies at install/upgrade (live edge today, unmodeled) | NO | **ADD** edge (HTTPS, sha256-pinned, anonymous) |
| Access relationship | `github -> inngestReleases` — `build-inngest-bootstrap-image.yml` downloads + verifies at image build; the PR-B poll reads `releases/latest` | NO | **ADD** edge |
| Container | `inngest` container description | present, carries no version claim | optionally extend one clause to name the pinned-CLI provenance + freshness owner (amendment of an already-edited description, `rf-review-finding-default-fix-inline`) |
| External human actor | none | — | No new human actor |
| Views | `views.c4` include lists | — | **ADD `inngestReleases`** to the **context** and **containers** enumerations (there are three `include` lists; it does NOT belong in the L3 plugin view). An `include` naming an undefined element fails `c4-render.test.ts`. |

### Sequencing

The ADR amendment and C4 edits describe the state PR-A/PR-B ship (the pin has an
owner), not a future state. The *live binary flip* is separately tracked and changes
no relationship.

## Guard Contract

The deliverable includes one new guard (the staleness/coherence gate) and extends one
existing guarded surface (the poll step in PR-B is a detector, not a gate).

### Guard 1 — `inngest-cli-staleness.test.sh`

**Property.** The inngest CLI pin is well-formed, coherent and fresh: exactly one
`vX.Y.Z` version local, exactly one 64-hex sha per arch, both arch shas equal the
sidecar's arch-keyed rows for the SAME version, the sidecar records one
`checksums.txt` URL for that version, and the sidecar's capture date is younger than
`MAX_AGE_DAYS`.

**Assembly.** Two committed artifacts, both chokepoints enumerated: (1) the `locals`
block of `apps/web-platform/infra/inngest.tf` — the ONLY pin the host/build read
(`build-inngest-bootstrap-image.yml` greps the `=` lines; `inngest-host.tf` reads the
locals by name); (2) `apps/web-platform/infra/inngest-cli.provenance.md` — the analysis
of record the gate reads its expected values from. The `inngest-userdata-budget.sh`
stub is deliberately OUT of the assembly — its sha is a size fixture with no property
attached; asserting on it would couple the gate to a value with no meaning.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Swap the values of `inngest_cli_sha256` and `inngest_cli_sha256_arm64` in `inngest.tf` | RED — arch-keyed check fails |
| 2 | Bump `inngest_cli_version` but leave both shas at the previous release's values | RED — version↔sha incoherence vs sidecar |
| 3 | Set the sidecar capture date > MAX_AGE_DAYS ago | RED — age gate |
| 4 | Add a second, commented-out pin line (`# inngest_cli_version = "vOld"`) | RED — exactly-once decoy guard counts assignments only and must still see one; a whole-line comment must not satisfy, and a second ACTIVE assignment must fail |
| 5 | Make the sidecar carry only the amd64 row (drop the arm64 row) | RED — second-member coverage: a check that stops at the first arch is the defect itself |
| 6 | Neuter the suite's `pass()`/`fail()` to no-ops (harness mutation) | RED — anti-vacuity floor + positive control exit 2 |
| 7 | A well-formed, internally-coherent pin+sidecar naming a DIFFERENT version than main's canonical (contract-permitted variance) | GREEN — must-PASS row: the gate checks coherence, not identity with main |
| 8 | Coherently edit BOTH `inngest.tf` and the sidecar to an older (but consistent) release | GREEN offline — declared coverage boundary: only the PR-B upstream poll catches a coherent two-file fake; recorded so nobody claims the offline suite closes it |

**Anchor.** The stored values the guard compares (sidecar rows + capture date) are
weakened-together with the pin inside ONE commit — so the guard proves consistency,
not integrity. The integrity anchor is outside the commit: the upstream release itself
(`checksums.txt` at the recorded URL + the PR-B poll comparing pin vs
`releases/latest`), and the reviewed merge history of `inngest.tf` + the sidecar
moving together.

**Failure-text directionality (per the wrong-channel learning
`2026-07-16-a-drift-guard-can-recreate-its-own-bug-…`).** The sidecar is the analysis
of record and the `tf` locals follow it; upstream is the poll's authority. Every RED
message must name that direction — "sidecar and inngest.tf disagree; the sidecar is
authoritative — update the pin or re-derive the sidecar" — and must never print a
remedy that reduces to "make the two files agree" (the coherent-fake hole is the
poll's job, declared in row 8). Both files are read independently; neither is derived
from the other.

## Domain Review

**Domains relevant:** Engineering.

### Engineering (CTO)

**Status:** reviewed (inline — infrastructure/tooling change, no cross-domain surface;
no subagent-spawn capability in this harness, so the leader's lens was applied inline).
**Assessment:** the load-bearing judgements are (a) detection and enforcement are
separate mechanisms and both are required — the per-PR gate alone never notices
upstream moving, the poll alone lets a coherent fake pass; (b) the pin bump must not
invent a staging mechanism — `OPERATOR_APPLIED_EXCLUSIONS` already provides one; (c)
every `v1.19.4`-scoped claim is a *measured* claim about a binary — the re-spike
re-measures, it does not re-assert; (d) the PR split is the correct reading of the
UNTRUSTED-CI rule — PR-A deliberately carries no `.github/workflows/` edit so the
admin-merge path stays open, and the poll's trigger is the only thing priced into
PR-B.

### Product/UX Gate

Not applicable. The mechanical UI-surface override does **not** fire: `## Files to
Create`/`## Files to Edit` contain zero paths matching `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx`, and no UI-surface term. Product = **NONE**.

**GDPR / compliance (2.7):** skipped — no schema, migration, auth flow, API route or
`.sql` file; no new processing activity; no LLM/external-API processing of operator
data; no new artifact distribution surface. Triggers (a)–(d) do not fire.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned no
issue whose body names `apps/web-platform/infra/inngest.tf`,
`inngest-bootstrap.sh`, `inngest-userdata-budget.sh`, `rule-audit.yml`,
`suite-shard-legs.tsv`, `ADR-100-…`, or `model.c4`.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/inngest-cli.provenance.md` | Analysis of record: target version, upstream release date, capture date, both arch rows + the single `checksums.txt` URL, previous known-good pin (rollback), re-verification table (flags/units/sentinels/spike findings), `## Bump procedure`. Mirrors `zot-image.provenance.md`. |
| `apps/web-platform/infra/inngest-cli-staleness.test.sh` | The offline enforcement gate (rc 0/10/2 contract; anti-vacuity floor + positive control; arch-keyed coherence; age gate). Cloned shape from `zot-image-staleness.test.sh`. Auto-registered by filesystem glob. |
| `apps/web-platform/infra/inngest-cli-staleness-mutation.test.sh` | The mutation battery driving Guard 1's matrix. |
| `apps/web-platform/infra/inngest-cli-pin-probe.sh` | The sub-second discoverability probe: reads `inngest.tf`'s version local + the sidecar's capture date offline and prints `PINNED=<v>` `CAPTURE_DATE=<d>` `VERDICT=fresh|stale|unverifiable` — deliberately NOT the full suite (Check 10's 15s cap rejects suite-shaped commands; the probe is the smallest command that emits the liveness signal). |
| `knowledge-base/project/specs/feat-one-shot-7463-inngest-cli-pin-bump/phase0-respike-evidence.md` | The re-spike record vs the pinned new version (mirrors `phase0-empirical-spike.md`). |

## Files to Edit

**PR-A:**

| Path | Change |
|---|---|
| `apps/web-platform/infra/inngest.tf` | `inngest_cli_version` + both sha256s → target release; rewrite the freshness comment to point at the sidecar + the (PR-B) poll step — never claim a bot manages the pin. |
| `apps/web-platform/infra/inngest-userdata-budget.sh` | Update the amd64 stub sha (size fixture; keeps the old-sha grep sweep at zero). |
| `apps/web-platform/infra/inngest-bootstrap.sh` | Only if the re-spike changes a claim it pins (e.g., the `pause` comment noting the dead call — the strip/unit comments were verified unchanged at plan time). |
| `apps/web-platform/infra/{inngest-inventory,inngest-enumerate-reminders,inngest-doublefire-probe,inngest-wiped-volume-verify}.sh` + matching `.test.sh` | Per-claim verdicts from the re-spike: re-stamp "verified vs vX.Y.Z" or correct the claim. Only comments whose assertions the re-spike re-verified — no blanket version-string churn. |
| `apps/web-platform/infra/{ci-deploy.sh,betterstack-logs-alerts.tf,inngest-host.tf}` + `scripts/cutover-inngest.sh` + `tests/scripts/test-inngest-host-dark-gate.sh` | Same re-spike-gated treatment for their `v1.19.4` claims (the betterstack error-text needles especially — if upstream changed the strings, the alert goes quiet, which is worse than red). |
| `knowledge-base/engineering/architecture/decisions/ADR-100-…md` | "CLI pin freshness" + re-spike verdicts amendment (§ADR). |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Add `inngestReleases` `#external` system + the two edges (§C4). |
| `knowledge-base/engineering/architecture/diagrams/views.c4` | Add `inngestReleases` to context + containers `include` lists. |

**PR-B (normal review-gated merge):**

| Path | Change |
|---|---|
| `.github/workflows/rule-audit.yml` | Add `Detect inngest CLI pin drift` step cloned from `Detect zot pin staleness` — rc contract honored, assignment-anchored parse, `releases/latest` poll, tag-ordered delta, tarball HEAD probe, one idempotent `inngest-pin-drift` + `action-required` issue (label created idempotently; mirrors the zot step exactly — no milestone flag, the zot step carries none) |
| `apps/web-platform/infra/rule-audit-inngest-pin-workflow-guard.test.sh` | Workflow-guard suite pinning the step's contract — presence, rc-discrimination, label, idempotent find-or-update shape — **plus a parity assertion against the zot step's shared skeleton** (the copy-adapted-gate learning `2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin`: the halves that must match — rc semantics, label-create idempotence, upsert shape — are pinned as a pair, not re-derived loosely) — lands WITH the step |

## Implementation Phases

### Phase 0 — Preconditions + re-spike (local only, no production writes)

- P1. Re-resolve `gh api repos/inngest/inngest/releases/latest`; if newer than the
  plan-recorded v1.45.1, re-run the flag probe + changelog walk against it and record
  the new target in the sidecar with the deciding evidence.
- P2. Tag-ordered walk → true release delta (stable tags only); record delta + date +
  command in the sidecar.
- P3. Run the re-spike battery (§Proposed Solution) against the pinned binary;
  produce `phase0-respike-evidence.md`. Halt on any finding that breaks a
  load-bearing invariant (a removed flag, a changed unit, route-once or FLUSHALL
  semantics changing) — the bump re-scopes rather than shipping on a broken premise.
- P4. Record in the PR body whether `scheduled-terraform-drift.yml` already shows the
  pending `hcloud_server.inngest` user_data diff (measured, not inferred).
- P5. Verify checksums end-to-end: fetch `checksums.txt` once, extract both arch
  rows, re-hash both tarballs, compare all four values.

### Phase 1 — RED: the gate before the bump (`cq-write-failing-tests-before`)

Write `inngest-cli-staleness.test.sh` + the mutation battery FIRST: it must fail now
(no sidecar exists yet → detector failure, then drift once the sidecar lands), and the
battery must drive it red on every matrix row.

### Phase 2 — The bump + sidecar + follower sweep

Edit `inngest.tf` (3 locals), `inngest-userdata-budget.sh` stub, write the sidecar,
`terraform fmt`, old-sha/old-version grep sweep to zero outside `knowledge-base/`, and
the re-spike-gated follower-comment updates.

### Phase 3 — ADR amendment + C4 edits

ADR-100 clause; `model.c4` `inngestReleases` + edges; `views.c4` includes; run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 4 — PR-A ship prep

Run `apps/web-platform/infra/inngest.test.sh`, `inngest-host.test.sh`,
`cloud-init-inngest-bootstrap.test.sh`, the new gate + battery, and — **only if the
diff added an inngest-server state-change writer line under
`apps/web-platform/infra/`** — `ci-deploy.test.sh` (its start-writer inventory, which
counts `systemctl` start/restart/enable verbs against inngest-server, is repo-global).
PR-A body: `Ref #7463`, `Ref #7308`, `## Changelog`. File the follow-through tracker
issue ("apply window: inngest CLI bump") and the `inngest pause` micro-issue.

### Phase 5 — PR-B (separate branch/PR, normal merge)

Branch off main after PR-A merges (the step consumes the gate + sidecar). Add the
`rule-audit.yml` step + the workflow-guard suite; PR-B body: `Ref #7463`,
`Ref #7308`, `## Changelog`. **No admin-merge.**

## Acceptance Criteria

**PR-A:**

- [ ] `inngest_cli_version` names the target release; `inngest_cli_sha256` and
      `inngest_cli_sha256_arm64` equal the two arch rows of that release's ONE
      `checksums.txt`, each re-verified by tarball re-hash (command + output in the
      sidecar).
- [ ] `apps/web-platform/infra/inngest-cli.provenance.md` exists with the full field
      set including `## Bump procedure` and a previous-known-good rollback pin.
- [ ] `inngest-cli-staleness.test.sh` exists, exits 0/10/2 correctly, carries
      anti-vacuity floor + positive control, and `inngest-cli-staleness-mutation.test.sh`
      drives every matrix row red — both auto-registered and green in
      `infra-validation.yml`.
- [ ] `phase0-respike-evidence.md` records a verdict for each ADR-100 finding, each
      flag unit (verified vs the pinned tag's `cmd/start` source), the durable
      sentinel, the signkey strip, and the follower-claim set — with changed-vs-holds
      explicitly marked.
- [ ] `git grep` for the old sha256s returns zero outside `knowledge-base/`;
      `v1.19.4` remains only where it is a deliberate historical/migration record.
- [ ] `terraform fmt -check` clean on `inngest.tf`; `inngest.test.sh`,
      `inngest-host.test.sh`, `cloud-init-inngest-bootstrap.test.sh` green.
- [ ] ADR-100 amendment + C4 element/edges landed; `c4-code-syntax.test.ts` +
      `c4-render.test.ts` green.
- [ ] PR-A body carries `Ref #7463`, `Ref #7308` and **no** Closes/Fixes/Resolves;
      `## Changelog` present; `semver:patch` label. Its **first line answers "does
      merging THIS alone mutate production?"** — "No host mutation; it auto-fires the
      bootstrap-image mint+build pipeline (repo/registry writes only) and stages a
      pending `hcloud_server.inngest` user_data diff."
- [ ] Follow-through tracker issue for the operator apply window filed with the
      verified-existing labels `action-required` + `follow-through`, carrying the
      sequence: merge the auto-authored cloud-init pin PR → confirm no concurrent
      v1.19.4+new schedulers share the event store → take a Postgres backup/snapshot
      (upstream auto-runs goose migrations on `start`; the delta contains a
      destructive cleanup migration class) → dispatch `deploy inngest`
      (or `apply_target=inngest-host-replace`) → verify via the runbook's no-SSH host-
      state path (`deploy inngest` `.reason` + `scheduled-inngest-health.yml` green,
      not SSH) → close #7463. `inngest pause` micro-issue filed.

**PR-B:**

- [ ] `Detect inngest CLI pin drift` step on `rule-audit.yml`: honors the rc=0/10/2
      contract, parses the pin anchored on the assignment, polls
      `releases/latest`, computes the tag-ordered delta, HEAD-probes the pinned
      tarballs, and creates-or-updates exactly one `inngest-pin-drift`-labeled issue
      when the drift threshold (`delta >= 5` releases OR pin age `>= 45` days) trips —
      never a second issue while one is open.
- [ ] The drift issue body names the delta, links the sidecar's `## Bump procedure`,
      and gives the `/soleur:one-shot` remediation entry point.
- [ ] `rule-audit-inngest-pin-workflow-guard.test.sh` green in CI.
- [ ] PR-B merged via **normal review-gated merge (no admin-merge)**; body carries
      `Ref #7463`, `Ref #7308`, `## Changelog` (no Closes — the apply-window step
      tracked by the follow-through issue owns the closure).

## Test Scenarios

- Given a swapped amd64/arm64 sha pair in `inngest.tf`, when the gate runs, then it
  exits 10 naming the arch-keyed failure.
- Given `inngest_cli_version` bumped with shas left at the old release, when the gate
  runs, then it exits 10 on version↔sha incoherence.
- Given a sidecar capture date older than `MAX_AGE_DAYS`, when the gate runs, then it
  exits 10; given an unparseable/absent sidecar, it exits 2 (detector failure), never 0.
- Given the mutation battery, when each matrix row is applied, then the gate reds on
  every row including the neutered-harness row (exit 2) — and the must-PASS
  coherent-variant row stays green.
- Given the poll step with a stubbed `gh api` returning `latest != pinned` and the
  delta over threshold, then exactly one `inngest-pin-drift` issue exists after two
  consecutive runs (idempotent find-or-update).
- `bash apps/web-platform/infra/inngest-cli-staleness.test.sh` prints `RESULT: …
  passed, 0 failed`.

## Success Metrics

- The pin is off v1.19.4 with both checksums single-sourced and re-hashed.
- The next time the pin ages past the threshold, a filed issue — not an incident —
  is what says so.
- Every load-bearing claim about the new binary is measured, not inherited.

## Rollback — if the new CLI misbehaves at the apply window

The rollback target is recorded IN the sidecar (previous known-good pin = `v1.19.4`
with its two checksums — already proven end-to-end against upstream at plan time).
Layers, cheapest first:

1. **Re-deploy the previous image pin:** revert/merge-back the auto-authored
   cloud-init pin PR (it converges all four sites idempotently), then `deploy
   inngest` again — the same drain→restart path reverts the binary in seconds. Goose
   migrations already applied stay applied; that is why the pre-flip backup exists —
   if the migration itself broke state, restore the snapshot, then redeploy the old
   pin.
2. **Repo-level pin revert:** `git revert` the `inngest.tf` locals + stub; the mint
   workflow sees the inputs change back and mints a corrective `vinngest-v*` tag the
   same way (idempotent, designed).
3. **Never** hand-edit the host — `hr-prod-host-config-change-immutable-redeploy`:
   every host-state correction flows through the image/cloud-init pin path.

## Dependencies & Risks

- **The host-side flip is an operator window** — tracked by the follow-through issue;
  the merge changes nothing on production hosts (verified via
  `OPERATOR_APPLIED_EXCLUSIONS`) while auto-firing the designed image pipeline.
- **Goose migrations on first start of the new binary** run against shared Postgres —
  the reason the issue demands its own window. Out of scope here, but the sidecar +
  follow-through issue carry the constraint forward so the apply doesn't get fired
  casually alongside anything else.
- **Upstream asset-name drift** (`inngest_<ver>_linux_<arch>.tar.gz`) — the bump
  procedure and the poll's HEAD probe both fail loud on it.
- **`v1.19.5-beta.1` and `-test.N` tags pollute the release list** — the delta walk
  counts stable tags only.
- **An always-open drift issue becomes noise** — mitigated by the explicit
  `delta >= 5 OR age >= 45d` threshold rather than any-delta.

## Non-goals / deferred

- **The live host-side bump** — operator-gated apply window; tracked by the
  follow-through issue filed in Phase 4 (not silently left).
- **Running-version surface on `/hooks/deploy-status`** — remains on #7308 (PRs say
  `Ref #7308`, never Closes/Fixes/Resolves).
- **Inngest Node SDK 3.x→4.x** — open issue #8628.
- **`inngest pause` dead call** — pre-existing on v1.19.4 already (measured); drain is
  sleep-only on both endpoints. Triaged: harmless `|| warn` path today, so deferred
  to a micro follow-up issue filed in Phase 4 rather than widened into this PR.
- **GHCR retirement (ADR-096 §5.3–5.5), live host replaces, legal cluster
  (#5150/#6894/#7779/#8528/#8529/#8624), `zot-soak-6122.sh`** (sibling #9097 worktree)
  — all explicitly out of scope.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or threshold-less fails
  deepen-plan Phase 4.6 — filled above.
- The old-sha grep sweep uses full 64-hex anchored patterns, never prefixes
  (sha-pin-prefix-match learning).
- The `checksums.txt` is a plain sha256sum file — describe it as release-shipped,
  never "GPG-signed"; no signature step may be promised (CLI-verification gate).
- `terraform fmt` re-aligns `=` — all pin greps anchor on `[[:space:]]*`.
- The gate must count assignments, not textual presence — a commented-out pin is a
  decoy, not a hit.
- Restating either "22" or "27" is a defect; the delta is measured with the command
  recorded, at bump time.
- `infra-validation.yml` is `paths:`-filtered — the per-PR gate cannot catch calendar
  aging; the PR-B poll is the time-based half and is NOT optional.
- `expected_output` uses `"passed, 0 failed"` (not `"0 failed"`, which
  substring-matches inside `"10 failed"`).
- Conditional `ci-deploy.test.sh` run: only if the diff adds an inngest-server
  state-change writer line — the inventory pins 19 such lines across 10 files.
- Neither PR may add an inngest-server state-change writer line.
- **The merge is pipeline-active, not silent:** every push touching
  `apps/web-platform/infra/inngest*` runs `mint-inngest-bootstrap-tag.yml`. The pin
  bump mints a `vinngest-v*` tag + image build + auto-authored cloud-init pin PR —
  expected, designed (ADR-232), and still host-inert; but reviewer-facing prose must
  say so, and the auto-PR is a downstream artifact to track, not a surprise.
  Conversely `inngest_cli_sha256_arm64` is NOT in the mint's watched `PINS` set —
  an arm64-only drift mints nothing (harmless today: amd64 host; recorded so nobody
  assumes arm64 bumps propagate by image alone).
- `discoverability_test.command` survives the preflight shell-token reject (no
  `|`, `;`, `&`, `<`, `>`, `$`, backtick): `bash
  apps/web-platform/infra/inngest-cli-staleness.test.sh` is plain-words only.
- The guard reads HCL by anchored assignment regex, not line-0 scan: whole-line
  comments and quoted-context hits are fixture-covered decoys (mutation row 4); the
  locals block is flat, no heredoc case exists in it — but the parser must still
  count assignments, not lines containing the name.
- The plan's own sweep ACs (`git grep` for the old sha/version) must exclude the
  plan/spec trees they are quoted in — scoped "outside `knowledge-base/`", which
  covers both.

## References & Research

- Issue: #7463 (spec), #7308 (cross-ref), #7283 / #7282 (zot precedent), #8628 (SDK
  major), #6258 (flag-unit precedent), ADR-100 (Phase-0 findings), ADR-096 §5.3–5.5
  (out-of-scope boundary), ADR-232 (the auto-authored cloud-init pin-bump PR — the
  designed downstream of this bump; our monitor watches the UPSTREAM-vs-tf delta, a
  different axis than ADR-232's image-pin drift guard).
- Canonical bump runbook:
  `knowledge-base/engineering/operations/runbooks/inngest-server.md` — "CLI version
  bump" + "Bootstrap-image release (tag → build → deploy → verify)" sections; the
  plan's Phase 2 bump + Phase-4 follow-through mirror that documented flow.
- Mint/dispatch machinery: `.github/workflows/mint-inngest-bootstrap-tag.yml`
  (`paths:` watch), `.github/scripts/mint-inngest-bootstrap-tag.sh` (`PINS` set +
  `--dry-run`), `.github/workflows/build-inngest-bootstrap-image.yml`
  (`bump-cloud-init-pin` job).
- Plan precedent:
  `knowledge-base/project/plans/2026-08-04-chore-zot-image-pin-bump-and-freshness-cadence-plan.md`.
- Spike methodology: `knowledge-base/project/specs/feat-inngest-dedicated-host/phase0-empirical-spike.md`.
- Gate/sidecar exemplars: `apps/web-platform/infra/zot-image.provenance.md`,
  `zot-image-staleness.test.sh`, `zot-image-staleness-mutation.test.sh`,
  `cosign-trusted-root-staleness.test.sh`, `cosign-trusted-root.provenance.md`,
  `Detect zot pin staleness` step in `.github/workflows/rule-audit.yml`.
- Plan-time binary evidence: v1.19.4 and v1.45.1 linux_amd64 tarballs (both
  sha256-verified against their release `checksums.txt`), `inngest start --help`
  outputs diffed — recorded in §Premise Validation.
