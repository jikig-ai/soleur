---
title: "chore: bump the git-data rehearsal ubuntu:24.04 base pin (#9252, ubuntu part only)"
date: 2026-10-08
slug: bump-ubuntu-base-digest-git-data-rehearsal
branch: feat-one-shot-9252-ubuntu-base-digest
issue: 9252
type: chore
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore: bump the git-data rehearsal ubuntu:24.04 base pin (#9252, ubuntu part only)

Spec lacks valid `lane:` (no spec.md exists for this one-shot branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`rule-audit.yml` (#7544) reports that `ubuntu:24.04` has moved under the git-data rung-1
rehearsal. The pin literal `UBUNTU_BASE` in
`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` still names the 2026-09-02 manifest-list
digest `sha256:33ceb71981b6...`. This change moves the pin to the live manifest-list digest, backed
by a fresh `mke2fs -V` measurement inside the new image and an explicit R1 ext4-feature
classification pass against the allowlist (`git-data-birth-fs-fingerprint.txt`). It is the
`ubuntu:24.04` half of #9252 only. The zot half (pin `v2.1.20` -> upstream, registry-host replace)
is a `cloud-init-registry.yml` render input and stays held, per
`knowledge-base/project/plans/2026-10-08-chore-zot-adr096-tail-9382-9252-plan.md` Phase 2.

Because the zot half remains, the PR MUST use `Ref #9252`, never `Closes #9252` (wg-use-closes-n).

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issue | Reality (measured 2026-10-08) | Plan response |
|---|---|---|
| Issue says live digest is `sha256:008173c2...` | Stale. `docker buildx imagetools inspect ubuntu:24.04` reports index digest `sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55`; amd64 child `f610ab94...`, created 2026-09-17 | Pin `534baea6...`; re-resolve again at work time and at ship (rolling tag) |
| "Confirm whether the existing pin is an index or a platform digest" | Existing `33ceb719...` inspects as `application/vnd.oci.image.index.v1+json` (index). The new `534baea6...` is also `application/vnd.oci.image.index.v1+json` with 6 platforms (amd64, arm64/v8, arm/v7, ppc64le, riscv64, s390x) | Pin the same kind: the index digest. Never a platform child digest |
| "Update UBUNTU_BASE in the rehearsal test" (one file) | The identical literal also lives in `git-data-ownership.test.sh:29` ("the same digest git-data-runcmd-rehearsal.test.sh spins") and `cloud-init-inngest-provision-unit.test.sh:1392` (Tier B). `git-data-cutover-access.test.sh:63` reads the rehearsal's literal by `sed`, so it follows automatically. The rule-audit detector parses only the rehearsal file, so stale copies would be invisible forever | Bump all three literals in one commit (see Scope Check, items 3-4) |
| R1 allowlist "built for a specific e2fsprogs" may not survive the bump | Measured: new image reports `mke2fs 1.47.0 (5-Feb-2023)`, EXT2FS 1.47.0, dpkg `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1`. Identical to the old image. Feature sets for plain, `-O project`, `-O casefold` are byte-identical across both images | Reclassification outcome: no allowlist row added, removed or changed. Record the measurement in the stanza comment and PR body; the fixture file is not edited |

## Research Insights

**Premise Validation (Phase 0.6).** #9252 is OPEN (labels `zot-pin-drift`, `priority/p3-low`); PR #9783 is the draft for this branch, empty diff. #9382 (cited indirectly via the held-registry plan) is OPEN. The mechanism (re-pin the digest) is not in any ADR's rejected-alternatives table: ADR-096 only mentions `UBUNTU_BASE` as a drift item. Cited paths exist on `origin/main`: `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (3918 lines), `git-data-birth-fs-fingerprint.txt`, `.github/workflows/rule-audit.yml:238`. Held: the issue's `008173c2` digest is stale (see above).

**Property List.** P1: the rehearsal harness runs the current upstream `ubuntu:24.04` index, so rule-audit stops reporting `ubuntu-base` drift. P2: the pin is the manifest-list kind, architecture-neutral. P3: R1's allowlist classification is demonstrably valid for the e2fsprogs in the NEW image (measured, not assumed). P4: every consumer of the same pin stays in lockstep. P5: nothing in the zot/registry render path moves.

**Cut List.** (1) A fixture refresh / regenerated feature table -> cut; P3 is met by a measurement record plus unchanged rows, and the fixture's own header forbids a wholesale refresh. (2) Any `rule-audit.yml` edit -> cut; the detector already parses the new literal (anchored regex `^UBUNTU_BASE='ubuntu:24\.04@sha256:[0-9a-f]{64}'`), and a `.github/workflows` touch removes the agent admin-merge path. (3) A new parity test across the three pin copies -> cut (YAGNI); AC-2 greps once, and a standing test is a separate decision. (4) A `re_measured:` line in the fingerprint fixture -> cut at plan-review (three copies of one fact: stanza comment, PR body, fixture; the fixture stays untouched). (5) Bumping `expires_on` -> cut; it is tied to the git-data host birth (R1-EXPIRY), unrelated.

**Learnings applied.**
- `knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md`: pin the manifest-list digest; Docker ignores the tag when a digest is present, so a platform digest would pin one architecture.
- The R1 fixture header ("WHY AN ALLOWLIST AND NOT SET-EQUALITY"): a bump emitting only classified features stays green; a novel feature reds R1(a) and the remedy is a one-line classification with rationale.
- `#7535` comment in `r1-drive.sh`: e2fsprogs comes from the image layer, so e2fsprogs drift is carried by the digest itself.

**Measurements (command: `docker run --rm <image> bash -c 'mke2fs -V; dpkg -s e2fsprogs; truncate -s 10G x; mkfs.ext4 -F -q [-O ...] x; dumpe2fs -h x'`).**

| Image | `mke2fs -V` | dpkg e2fsprogs | plain `mkfs.ext4 -q` features | `-O project` adds | `-O casefold` adds |
|---|---|---|---|---|---|
| OLD `33ceb719...` | 1.47.0 (5-Feb-2023) | 1.47.0-2.4~exp1ubuntu4.1 | has_journal ext_attr resize_inode dir_index filetype extent 64bit flex_bg sparse_super large_file huge_file dir_nlink extra_isize metadata_csum | project | casefold |
| NEW `534baea6...` | 1.47.0 (5-Feb-2023) | 1.47.0-2.4~exp1ubuntu4.1 | identical | project | casefold |

The production birth line is `mkfs.ext4 -q -O project /dev/mapper/git-data` (`cloud-init-git-data.yml:1183`), i.e. the `-O project` column. Every feature in it is a row in the allowlist (`in-tree`); `casefold` is still absent from the table, so the UNCLASSIFIED CONTROL keeps its failing direction; `quota` is still `module-dep`.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open`, bodies searched for each of the four planned file paths: no matches.)

## Files to Edit

- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — the `UBUNTU_BASE` literal (line ~70), and the stanza comment above it: `resolved 2026-09-02` becomes a dated pair (`2026-09-02` previous, `2026-10-08` current) plus one sentence recording that `mke2fs -V` was re-measured in the new image (1.47.0, unchanged) and the allowlist needed no change. The R1(a) failure-message sentence "Measured inside the PINNED image ..." stays true; append the re-measure date only.
- `apps/web-platform/infra/git-data-ownership.test.sh` — the `UBUNTU_BASE` literal (line 29).
- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` — the `UBUNTU_BASE` literal (line ~1392); the Tier B image cache tag is derived from the literal (`sha256sum` of it), so the cached tier-B image rebuilds once.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9252-ubuntu-base-digest/tasks.md` (plan derivative).

Not touched (explicit): `apps/web-platform/infra/git-data-birth-fs-fingerprint.txt` (plan-review cut: the reclassification outcome is recorded in the rehearsal stanza comment and the PR body, so the fixture stays byte-identical), `apps/web-platform/infra/zot-registry.tf`, `zot-image.provenance.md`, `cloud-init-registry.yml` and its render inputs, the `docker.pkg.github.com` hosts-file deny, any registry host, `.github/workflows/*`, any `apply-*` workflow.

## Implementation Phases

### Phase 1 — Re-resolve and measure (no edits)

1. `docker buildx imagetools inspect ubuntu:24.04 | awk '/^(MediaType|Digest):/'`. Must print an `image.index.v1+json` media type. Record the digest. If it differs from `534baea6...`, use the new value and redo step 2 against it (the measurement is the deliberate act, the literal merely records it).
2. Run the measurement in the exact image that will be pinned: `docker run --rm ubuntu:24.04@sha256:<NEW> bash -c '...'` (command in Research Insights). Compare against the OLD image. Branches:
   - identical feature sets and the same e2fsprogs (today's result) -> allowlist unchanged;
   - a different `mke2fs -V` -> also update the two prose claims that name 1.47.0: the pin stanza comment ("mke2fs measures 1.47.0 inside this image") and the R1(a) failure message "Measured inside the PINNED image", plus the fingerprint's `mke2fs_measured` context line (then, and only then, the fixture is edited, as a one-line context update);
   - a feature present in the new set but not in the table -> classify it with a one-line `in-tree`/`module-dep` rationale citing kernel source (never copy the measured set over the table), and R1(a) stays green only because of that row;
   - a feature that is `module-dep` -> STOP: that is the #7204 class; do not bump, report on #9252.

### Phase 2 — Edit

Apply the four edits in Files to Edit. Keep each `UBUNTU_BASE` assignment on a single line and anchored at column 0 in the rehearsal file (rule-audit's regex and `git-data-cutover-access.test.sh:63` both anchor on `^UBUNTU_BASE='...'`).

### Phase 3 — Verify locally (bounded output; exit code preserved)

Run each suite as `cd <worktree> && bash <suite> > "$SCRATCH/<name>.log" 2>&1; echo "rc=$?"; tail -25 "$SCRATCH/<name>.log"` (a bare `| tail` hides the suite's exit code): `git-data-runcmd-rehearsal.test.sh` (R1-PIN arms, R1 a/b/c and the three controls) and `git-data-ownership.test.sh`. `git-data-cutover-access.test.sh` (reads the pin by `sed`) and the inngest Tier B suite are left to CI. A suite red for an environment reason (no docker, no network) is reported as such; CI is the authority. Local `node_modules` is stale: no typecheck is claimed locally.

### Phase 4 — PR

Update draft PR #9783: body states the digest move, the measurement table, the allowlist outcome, the sibling bumps, `Ref #9252`, and that the zot half is untouched. Mark ready for review only when CI is green. Merge authority stays with the operator. No `[ack-destroy]` line anywhere. The commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; the PR body ends with the Generated-with-Claude-Code line.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The change is confined to infra CI rehearsal harnesses; the worst case is a red infra-test CI job on the next PR that touches `apps/web-platform/infra/`.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. No secret, credential, or production resource is read or written; the pin is a public image digest.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the change cannot reach a user-facing surface or a production host; the only production-adjacent claim (the birth filesystem is mountable on the target kernel) is unchanged because the measured feature set is identical.

threshold: none, reason: test-harness base-image pin under `apps/web-platform/infra/` (tests and a comment-only fixture edit); no production resource, secret, or customer data path is touched.

## Observability

```yaml
liveness_signal:
  what:            rule-audit.yml image-pin drift detector (#7544) comparing UBUNTU_BASE to the live Docker Hub index digest
  cadence:         scheduled (the workflow's cron)
  alert_target:    action-required GitHub issue #9252 (label zot-pin-drift), ops email on probe failure
  configured_in:   .github/workflows/rule-audit.yml:238

error_reporting:
  destination:     GitHub issue body and the rule-audit workflow run summary (no Sentry; CI-only surface)
  fail_loud:       R1-PIN / R1(a) FAIL lines in the rehearsal suite; rule-audit PROBLEMS and DRIFT sections

failure_modes:
  - mode:          pin drifts from upstream again after this bump
    detection:     rule-audit step (5) compares anchored UBUNTU_BASE digest to live Docker-Content-Digest
    alert_route:   #9252 reopened or updated, label zot-pin-drift
  - mode:          new image emits an unclassified ext4 feature
    detection:     R1(a) in git-data-runcmd-rehearsal.test.sh in CI
    alert_route:   red infra-tests job on the PR

logs:
  where:           GitHub Actions run logs for rule-audit.yml and the infra test job
  retention:       GitHub Actions default log retention

discoverability_test:
  command:         grep -oE "^UBUNTU_BASE='ubuntu:24[.]04@sha256:[0-9a-f]{64}'" apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
  expected_output: sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Update UBUNTU_BASE in apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh from pinned sha256:33ceb719... to the LIVE ubuntu:24.04 digest" [brief] | Phase 2, Files to Edit entry 1 | mapped |
| 2 | "re-resolve it first with `docker buildx imagetools inspect ubuntu:24.04`" [brief] | Phase 1 step 1 | mapped |
| 3 | "confirm whether the existing pin is an index or a platform digest and pin the same kind" [brief] | Research Reconciliation row 2, Phase 1 step 1 | mapped |
| 4 | "a fresh `mke2fs -V` measurement inside the new image" [brief] | Phase 1 step 2, Research Insights measurements | mapped |
| 5 | "a deliberate R1 ext4-feature reclassification against the allowlist in that test file, never a wholesale fixture refresh" [brief] | Phase 1 step 2 branches, Files to Edit entry 1 stanza comment + PR body; fixture deliberately unedited | mapped |
| 6 | "Do NOT touch the zot pin (v2.1.20) or the cloud-init-registry.yml render inputs; do NOT touch the docker.pkg.github.com hosts-file deny; do NOT replace the registry host." [brief] | Files to Create/Edit "Not touched" list; AC-3 | mapped |
| 7 | "never add an [ack-destroy] line; do not run apply-web-platform-infra.yml or any production apply; do not run the web-2 rebirth or web-host-replace" [brief] | Phase 4; AC-3 | mapped |
| 8 | "Stop at a ready-for-review PR with green CI; merge authority stays with the operator." [brief] | Phase 4; AC-5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Rehearsal `UBUNTU_BASE` literal + stanza comment | "Update UBUNTU_BASE in apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh" | asked |
| `git-data-ownership.test.sh` literal | — | inferred — justification: its own comment states it is "the same digest git-data-runcmd-rehearsal.test.sh spins (#7544)"; left stale it contradicts that contract and no detector (rule-audit reads only the rehearsal) would ever flag it |
| `cloud-init-inngest-provision-unit.test.sh` Tier B literal | — | inferred — justification: same literal, same drift, same undetectable-staleness reason |
| Phase 3 local suite runs | "Stop at a ready-for-review PR with green CI" | asked (precondition to green CI) |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform/infra/` (+ `knowledge-base/` plan artifacts)
- Planned files: 4 (3 edited + the plan artifacts) | Estimated changed lines: ~12
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: The rehearsal file's pinned digest equals the live index digest AND is an index. `docker buildx imagetools inspect ubuntu:24.04 | awk '/^Digest:/{print $2}'` equals the output of `grep -oE "^UBUNTU_BASE='ubuntu:24\.04@sha256:[0-9a-f]{64}'" apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh | grep -oE 'sha256:[0-9a-f]{64}'` (rule-audit's own parse; exactly one digest printed), and `docker buildx imagetools inspect ubuntu:24.04@sha256:<pin> | grep '^MediaType:'` reads `application/vnd.oci.image.index.v1+json`. Re-check AFTER the last CI rerun and immediately before marking ready (rolling tag). Today: `sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55`.
- [ ] AC-2: Lockstep. `git grep -n "33ceb71981b6" -- ':!knowledge-base/**'` prints nothing, and `git grep -ho "ubuntu:24.04@sha256:[0-9a-f]\{64\}" -- 'apps/web-platform/infra/*.test.sh' | sort -u | wc -l` prints `1`.
- [ ] AC-3: Scope fences. `git diff origin/main --name-only` lists none of `zot-registry.tf`, `zot-image.provenance.md`, `cloud-init-registry.yml`, `git-data-birth-fs-fingerprint.txt`, nor any `.github/workflows/*`; `git diff origin/main | grep -c -e 'docker.pkg.github.com' -e 'ack-destroy'` prints `0`. No production apply or workflow dispatch was run.
- [ ] AC-4: The PR body carries the fresh `mke2fs -V` output from inside the new pinned image (`mke2fs 1.47.0 (5-Feb-2023)`), the dpkg e2fsprogs version, and the R1 outcome (no allowlist row added, removed or changed; casefold still unclassified; quota still module-dep).
- [ ] AC-5: PR #9783 is ready for review, its body uses `Ref #9252` (not a closing keyword) and ends with the Generated-with-Claude-Code line, and every required CI check is green, including the rehearsal suite's R1-PIN arms (shape, exactly 6 spin sites, 0 bare refs) and R1 (a), (b), (c) with the three controls. Merge is left to the operator.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (test-harness pin in `apps/web-platform/infra/`; no UI, schema, auth, or data surface). Phase 2.7 GDPR gate, 2.8 IaC routing, 2.10 ADR/C4, 2.11 encryption posture and 2.12 guard contract all skip: no persistent store or connection is introduced, no architectural decision is made or reversed, and the deliverable adds no guard (R1 and R1-PIN already exist and are unchanged).

## Dependencies & Risks

- **Rolling tag.** `ubuntu:24.04` can move between plan, work and ship. Mitigation: Phase 1 re-resolves, AC-1 re-checks after the last CI rerun, right before ready-for-review; a move means re-measure, not just re-paste.
- **Tier B in the inngest provision suite** rebuilds its cached systemd image because the cache key hashes the pin literal. It installs systemd from the live archive at runtime, so the image digest affects only the base layer. It is a plain literal swap; if Tier B reddens for a reason attributable to the image, report it on the PR rather than pre-deciding a revert here.
- **Docker Hub rate limits** on pull in CI: unchanged exposure (the old digest was pulled the same way).
- **Out of scope, tracked elsewhere:** zot `v2.1.20` -> upstream and the registry-host replace (#9252 zot half, bundled with #9390 per the 2026-10-08 held-registry plan). After this merges, rule-audit should re-file #9252 with only the zot condition; if the issue body still names `ubuntu-base` on the next scheduled run, that is a detector finding, not a reason to touch the workflow here.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one carries a concrete `none` threshold with the scope-out line.
- Do not paste the measured feature set over the allowlist table: the table is derived from the production sibling baseline, and R1's header forbids deriving it from the thing under test.
- Keep the `UBUNTU_BASE='...'` assignment on one line starting at column 0: three consumers (the R1-PIN grep, `git-data-cutover-access.test.sh`'s `sed`, and rule-audit's anchored `grep -oE`) parse that exact shape.
- `Ref #9252` only. A closing keyword would close the issue with the zot half undone.

## References

- Issue #9252; draft PR #9783
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (pin stanza ~L49-70, R1 ~L2291-2546)
- `apps/web-platform/infra/git-data-birth-fs-fingerprint.txt`
- `.github/workflows/rule-audit.yml` (step 5, ~L221-265)
- ADR-096, ADR-163; `knowledge-base/project/plans/2026-10-08-chore-zot-adr096-tail-9382-9252-plan.md`
