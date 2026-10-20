---
title: Art. 30 PA-8 re-verification trigger actuation (partial)
status: specified
issue: 7893
brainstorm: knowledge-base/project/brainstorms/2026-10-20-art30-trigger-actuation-brainstorm.md
branch: feat-7893-art30-trigger-actuation
pr: 10620
date: 2026-10-20
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
---

# Spec: Art. 30 PA-8 re-verification trigger actuation

The implementation pull request tracks #7893 and leaves it open. Do not put a GitHub closing keyword for #7893 in the pull-request body, the commit message, or this spec's frontmatter.

## Problem Statement

PA-8 §(f) of the Article 30 compliance register (`knowledge-base/legal/article-30-register.md`) has a closed list of seven re-verification triggers. The compliance-posture Active Items row that cites #7893 says the defect is the control: every trigger is still prose plus a register cell, so nothing fails when an anchor changes without a dated review entry. The runbook copy is `knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md` ("### Re-verification triggers"). Those two copies disagree on the predicates for items 3 and 4. A path gate cannot see the annual review (1) or the Better Stack source checks (6 and 7).

The historical in-repo miss was #4786 (2026-06-02): the app container moved to `docker run --log-driver journald` while trigger 2 still watched the `daemon.json` `"log-driver": "json-file"` block. The published privacy policy kept the old retention account until 2026-09-07.

## Goals

- A blocking check fails a pull request that changes an in-scope anchor for re-verification triggers 2, 4, or 5 unless the same diff adds a review hunk in the PA-8 §(f) cell.
- One machine-readable manifest is the only predicate and anchor copy the check executes.
- The allowed claim is partial actuation of re-verification triggers 2, 4, and 5. #7893 and the compliance-posture row stay open.
- Ids 1, 3, 6, and 7 remain on the manifest and on #7893 with class `unactuated`.

## Non-Goals

- Closing #7893, clearing the posture residue, or describing the closed list as actuated.
- Actuating the annual review (1), choosing or watching a trigger-3 predicate, or calling the Better Stack API for triggers 6 and 7.
- A repo-wide denylist of `--log-driver`, journald unit syntax, or TOML. The registry-host and egress-gateway `--log-driver journald` runs are outside this list.
- Editing `scripts/lint-legal-registers.sh`, `scripts/lint-legal-scope-block-placement.sh`, `scripts/lint-legal-mirror-drift-baseline.sh`, `scripts/probe-legal-corpus-truth.sh`, or `scripts/generate-article-30-register.sh`.
- Reading log bodies, replacing journald `NOT RECORDED` with a computed duration, opening Flow 2, or adding a vendor spend.
- Absorbing #7892. A third prose copy of the trigger sentences in compliance-posture.
- An advisory soak. Parsing `docs/legal/` to judge the published sentences.
- A counsel-review attestation. This spec does not authorise changing the posture cell to "actuated."

## Functional Requirements

### FR1: Manifest

A new committed manifest holds ids {1, 2, 3, 4, 5, 6, 7}. Each record has a class: `path-token`, `file`, or `unactuated`. Classes `path-token` and `file` carry the paths and tokens the check executes. Ids 1, 3, 6, and 7 are `unactuated` and carry no executable predicate. The manifest is not `scripts/generate-article-30-register.sh` and not `scripts/lib/betterstack-sources.sh`.

Trigger 2 and trigger 4 share one `path-token` record set: paths `apps/web-platform/infra/cloud-init.yml` and `apps/web-platform/infra/ci-deploy.sh`; tokens `--log-driver`, `--log-opt`, and `--restart`. Trigger 5 is class `file` on `apps/web-platform/infra/journald-soleur.conf` with no token filter.

A manifest edit that drops one of those two paths, points trigger 2 or 4 at `daemon.json`, or marks 1, 3, 6, or 7 `actuated` fails the check. A manifest edit does not satisfy the PA-8 §(f) review requirement.

### FR2: Hit predicate

The check looks at added and removed lines in the two paths. A line whose first non-whitespace character is `#` does not match. A match is the CLI flag `--log-driver`, `--log-opt`, or `--restart`, in space form or `--flag=value`. `--log-driver` or `--log-opt` fires ids {2, 4}. `--restart` alone fires {4}. `daemon.json` keys `log-driver` and `log-opts` do not fire trigger 2.

Any diff to `apps/web-platform/infra/journald-soleur.conf` fires id 5, including `SystemKeepFree=` and `RuntimeMaxUse=`. The register sentence that anchors item 5 on the `SystemMaxUse=` line is not the predicate.

One added review hunk names every fired id. The check does not watch `apps/web-platform/infra/vector.toml` and does not token-scan shipper names. It does not scan `cloud-init-registry.yml` or `egress-gateway-bootstrap.sh`.

### FR3: Review hunk

When FR2 fires, the same pull request's diff adds text inside the PA-8 §(f) retention cell of `knowledge-base/legal/article-30-register.md`. The added hunk contains a non-empty ISO date `YYYY-MM-DD`, every fired id, and a non-whitespace statement beyond that date and those ids. The check sees the added hunk only.

These do not pass: a date already in the cell; an empty or non-ISO date; a date with no further statement; a hunk that omits a fired id; a manifest date bump; a compliance-posture edit while §(f) is untouched; a pull-request comment; a runbook "reviewed" sentence; a retroactive FIRED mark.

The check does not grade who, role, before and after, or the Art. 30(1)(f) conclusion. Passing the check is not Art. 5(2) demonstrated. No script writes the entry, marks FIRED, or advances a next-due date.

The human entry, written in that hunk by the reviewer in the legal role, carries what the CLO required: the date of this review; who reviewed and in what role; which id fired and which anchor moved; the retention-relevant before and after; the Art. 30(1)(f) conclusion (mechanism still holds, or this pull request updates it, or `NOT RECORDED` still holds and which bound governs); and whether the cell was amended or expressly confirmed. The product outcome adds one fact inside that before-and-after: whether the published privacy-policy retention sentences still match. The gate does not grade it.

### FR4: Closure check

While the runbook section and the PA-8 §(f) cell still contain numbered enumerations, the check asserts set-equality of ids {1..7} across the manifest and those two enumerations. It does not byte-compare sentences and does not parse either prose copy for paths, tokens, or shipper names. Compliance-posture is not a third copy.

### FR5: Claim boundary

Docs, the pull-request body, and the posture row for this slice say partial actuation of re-verification triggers 2, 4, and 5. They do not say the closed list is actuated. The implementation does not edit the posture row into a resolved state and does not close #7893.

## Technical Requirements

### TR1: New check, reused base

The check is a new script, registered as a blocking required check (the `enforce` name in `scripts/required-checks.txt` is the precedent for "required on day one"). It reuses `legal_resolve_base` in `scripts/lib/legal-base-ref.sh`. Exit 2 when the base cannot be decided. It does not add a second base-ref resolver or a second copy of `scripts/lib/legal-normalise.sh`.

On `merge_group`, the diff base is `MERGE_GROUP_BASE_SHA`. An empty base is a hard failure. Otherwise the diff is three-dot against the pull-request base, matching the legal-doc lockstep step in `.github/workflows/pr-quality-guards.yml` job `enforce`. That step's `surface_patterns` stay the DSAR files. This check does not add the log anchors to that DSAR list and does not require `docs/legal/privacy-policy.md` to appear in the diff.

### TR2: Tests

Tests are synthesized fixtures. They cover at least: a flag added at each of the two paths fails without a new PA-8 §(f) hunk; the same diff with a hunk that names the fired ids passes the mechanical check; a comment line that contains `--restart` does not fire; a `daemon.json` `log-driver` edit does not fire trigger 2; a `SystemKeepFree=` edit fires id 5; a pre-existing date in the cell does not satisfy a new flag edit; a manifest that marks id 6 `actuated` fails; id-set drift (an enumeration that drops an id) fails; the check exits non-zero when the base cannot be decided. A document-only manifest edit does not exempt an anchor diff.

### TR3: GDPR gate

Plan Phase 2.7 runs `soleur:gdpr-gate` because `brand_survival_threshold` is `single-user incident`. The bounded check reads git diffs of retention configuration. Work Phase 2 exit runs the gate again if the diff adds a migration, an auth surface, an API route, a `.sql` file, or any read of log bodies.

### TR4: Wording left to the CLO

If the implementation edits the runbook's re-verification section, the CLO drafts the pointer at the manifest. The check does not depend on that prose being deleted. Trigger 3's predicate is not chosen in this spec.
