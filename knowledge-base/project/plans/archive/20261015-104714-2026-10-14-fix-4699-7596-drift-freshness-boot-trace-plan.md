---
title: "fix(infra): vinngest published-digest freshness reconciler + inngest boot-trace allowlist proof"
date: 2026-10-14
slug: drift-freshness-boot-trace
branch: feat-one-shot-4699-7596-drift-freshness-boot-trace
issue: 4699
closes: 4699
refs: 7596
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start -->
<!-- Phase 2.8 justification: this PR ships zero infrastructure changes — CI scripts, a read-only scheduled workflow, suite assertions, and runbook text only. Every deferred item routes through EXISTING Terraform apply targets (inngest-host-replace) or existing workflow dispatches; nothing here is provisioned by hand. -->
<!-- lint-infra-ignore end -->

## Enhancement Summary

**Deepened on:** 2026-10-14 (manual sequential pass — this harness has no Task/Agent tool; per-section, skills, learnings and review fan-outs ran inline by the author, `Reviewed-Coverage: sequential-fallback` — no independent review is claimed)
**Sections enhanced:** Proposed Solution (the recorded-digest source of truth is git pin history — the bump commits ARE the publish-workflow-authored record, verified against `git log -G` on this branch, rather than a new maintained ledger), Observability (the reconciler's own liveness is the scheduled run + wiring pins; could-not-measure is a named class, never a content verdict), Scope Check (two issues mapped to one PR; #7596's close condition verified unsatisfiable pre-replace and routed to the runbook + an optional followthrough probe).

### Key Improvements

1. **The smallest honest published-digest comparison.** #4699 asks for a check that a `vinngest-v*` tag's registry content still equals what its publish recorded. No new durable artifact is needed: for every merged tag, the digest it was pinned at IS the publish workflow's record (the bump job resolves `crane digest` at publish time and cross-checks it against the signed digest). A scheduled reconciler derives that record from git pin history and compares it to a live `crane digest` — one script, one weekly workflow, one battery.
2. **#7596's two halves separated correctly.** The repo-side deliverable is verifiable now — a GuardA-adjacent pin proving both `#7457` identifiers are in the pinned tag's `vector.toml` (so the next bake provably carries them) plus the missing `inngest-bs-token-restage` emitter↔allowlist lockstep in `journald-config.test.sh`. The close condition is unsatisfiable until a host replace and is recorded where the replace runbook will find it, keyed on `SOLEUR_INNGEST_BS_TOKEN_RESTAGED` — the one boot-trace identifier that emits on success.
3. **#7462 verified closed, not assumed open.** Both #7462 and its successor #7674 are CLOSED (the host was replaced 2026-08-20 and restored through step 6); the next `inngest-host-replace` is ordinary machinery, not a tracked window — so the plan carries the measured close condition in the runbook itself rather than delegating to a closed issue's checklist.

## Overview

One PR covers two coupled gaps in the inngest-bootstrap image/observability surface. They share no code path but one theme: *"tag exists / config merged" reading as "content correct / delivered" — the silence-that-reads-as-health class.*

- **#4699** — AC6 of `cloud-init-inngest-bootstrap.test.sh` asserts `pin == semver-max vinngest-v* tag merged into HEAD` (a *name* check). Nothing checks that a tag's GHCR *content* is still what its publish recorded: a `workflow_dispatch` re-publish of a non-max tag (the CVE-base-image-rebuild escape hatch) rebuilds and re-pushes the same tag, moving its digest, while "tag exists" stays true everywhere. The drain elected to close it ahead of its own re-evaluation trigger ("promote if cloud-init ever pins a non-max tag"). This PR ships a scheduled reconciler: for every merged `vinngest-v*` tag, compare the live `crane digest` against the digest the pin history recorded.
- **#7596** — #7457's `inngest-boot-phone-home` + `inngest-bs-token-restage` Source-4 entries are in repo `vector.toml` (verified at :293,:301) and reached web-1 via `apply_target=vector-redeliver`, where they are inert — the identifiers emit only on the dedicated host, which receives `vector.toml` solely inside the baked image. The fix is an image bake + host replace (not this PR). This PR ships the provable scaffolding: CI pins that the pinned image's `vector.toml` carries both identifiers, and the measured post-replace close condition written into `inngest-server.md`.

## Research Insights

**Premise validation (2026-10-14, this branch).** #4699 and #7596 both OPEN (`gh issue view`). PR #10272 is this branch's draft. #7462 and #7674 are both CLOSED — the dedicated host was replaced 2026-08-20 and restored through all six sequence steps; the image it booted predates a bake containing the `vector.toml` entries, which is exactly the inert state #7596 describes.

**Verified on this branch:**

- AC6 (`cloud-init-inngest-bootstrap.test.sh` ~L335-459) compares both cloud-init pins against `LATEST_TAG = git tag --merged HEAD --list 'vinngest-v*' | sort -V | tail -1` — a name comparison only; no digest or content comparison exists anywhere in the suite.
- Guard B (~L1062-1182) binds the four pin *sites* to one tag+one digest and uses git history (row 6) to catch "tag moved, digest didn't" — but only across commits of the pin itself; it cannot see the tag's registry-side digest move.
- Guard A (~L1316-1443) byte-compares every baked carrier at the pinned tag against HEAD — its own commentary names the three residuals it does NOT close, including "(1) a default workflow_dispatch re-runs docker build and re-pushes the same tag, so the tag's GHCR digest MOVES". That residual is #4699, verbatim.
- `build-inngest-bootstrap-image.yml` is the only publish path (dispatch-only since #9262). Its own header: "a default workflow_dispatch re-runs `docker build` and pushes the SAME tag, so the tag's GHCR digest MOVES… Use `mirror_only` when the goal is only to get an already-published tag onto zot; it cannot move a digest because it never builds."
- The bump job's `bump-inngest-bootstrap-pin.sh` resolves `crane digest $IMAGE:$TARGET` at publish time, cross-checks it against `SIGNED_DIGEST` when the signed tag is the target, and writes `tag@digest` into all four pin sites — so **git pin history is the publish workflow's own recorded digest**. Verified: `git log -G 'soleur-inngest-bootstrap:v1\.1\.51@'` returns the authored bump commits (#10107, #10172-era).
- The bump job already logs into GHCR with `packages: read` + installs pinned crane (`v0.20.2`, sha-pinned) — the complete auth+tooling recipe the reconciler needs, proven in the same file.
- `vector.toml` Source-4 `include_matches.SYSLOG_IDENTIFIER` contains both `#7457` identifiers (`inngest-boot-phone-home` :293, `inngest-bs-token-restage` :301). The pinned tag `vinngest-v1.1.52` carries them in its tree at the same positions — so an identifiers-at-the-pinned-tag assertion is green today.
- `journald-config.test.sh` CF-4 covers `inngest-boot-phone-home` (derived tag → allowlist, silent-on-success) but `inngest-bs-token-restage` has NO emitter↔allowlist pin — deleting the entry greens today.
- `inngest-bs-token-restage.service` emits `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` via `logger -t` on SUCCESS (`cloud-init-inngest.yml` :794) — ~1 row per boot — making it the only boot-trace identifier usable as a post-replace positive control; `inngest-boot-phone-home` is deliberately silent-on-success (CF-4c).
- `inngest-host-state.sh`/`deploy-status` cannot read the host's `/etc/vector/vector.toml` (the `/hooks` channel terminates on web-1; the host is deny-all-public) — the only post-replace measured read is the journald→vector→Better Stack row itself, matching the issue's suggested close condition.
- Suite registration: `.github/scripts/test/test-*.sh` auto-globs into `run-all.sh` → `guard-script-fixture-tests` (REQUIRED check; BASH-ONLY contract; `MIN_SUITES=14` floor needs no edit). `apps/web-platform/infra/*.test.sh` auto-registers via `run-registered-suites.sh` (ADR-252); a NEW infra suite would need `suite-durations.tsv`/`suite-shard-legs.tsv` rows via `scripts/regenerate-shard-manifest.py --incremental --write` — the recommended shape adds blocks inside existing suites and avoids that entirely.
- 41 `vinngest-v*` tags are merged into HEAD; the pin today is `v1.1.52@sha256:67c90515…` at all four sites.

**Property List.**

- P1. A digest move on ANY merged `vinngest-v*` tag — whatever its cause (sanctioned CVE rebuild, tag re-point, an unprescribed push) — surfaces within one reconciliation period as a named verdict, never silently.
- P2. A digest move or disappearance on the PINNED tag is a hard, alerted verdict: it orphans the pin's `@sha256` (GHCR keeps it as an untagged manifest; zot's 5-tag retention can evict it — the workflow's own "bounded fuse" warning).
- P3. Could-not-measure is never a content verdict: crane/auth/history failures classify `unmeasurable` (exit 2), the `QUERY_UNAVAILABLE` precedent.
- P4. The pinned image's `vector.toml` provably carries both `#7457` identifiers — asserted at the pinned tag's tree, not just at HEAD, so a future pin to a tag lacking them reds.
- P5. The `#7596` close condition is a measured read, not config presence — `SOLEUR_INNGEST_BS_TOKEN_RESTAGED` from `host=soleur-inngest` — and is written where the replace runbook will find it.

**Cut List (mechanism → property → what already covers it).**

- A committed `vinngest-image-digests.tsv` ledger maintained by the bump job: cut — the record already exists (git pin history IS the bump's authored record); a ledger adds a maintained artifact plus a ledger-only-PR machinery on every non-max re-publish, to cover a state already self-announcing as `never-recorded`. Decision row D2.
- A digest check inside `build-inngest-bootstrap-image.yml` itself (pre/post digest at publish): cut as the primary mechanism — it sees only the sanctioned path and cannot observe movement by any other route; the scheduled resolver sees both. Recorded as D1 dissent.
- An Inngest-cron dispatch-hybrid (`cron-vinngest-digest-freshness.ts` + workflow): cut — the subject is outside the product and the check must fire while the inngest scheduler is down; the `gate-override` scheduled-workflow precedent covers this exactly. Decision row D5.
- A `sentry_cron_monitor` absence heartbeat for the new workflow: deferred — the check is weekly drift-watch, not liveness-critical; wiring pins make its deletion advisory-red (`deploy-script-tests` is not a required context — the `.github/scripts/test/` battery is the merge-blocking arm). Named follow-up.
- Refusing a digest-moving re-publish: never — the `workflow_dispatch` non-`mirror_only` path is the *designed* CVE escape hatch; the check records and alerts, it does not gate.
- Editing `vector.toml`, `cloud-init-inngest.yml`, any carrier, or any pin: none — this PR asserts, it does not ship content. GuardA stays green.

**Institutional precedents used.** `inngest-config-drift.yml` + `inngest-config-drift-compare.sh` (off-box comparator workflow + fixture-tested script + could-not-measure class); `scheduled-marketplace-drift.yml` (`gate-override` GitHub schedule for an outside-the-product subject); the bump job's GHCR-login + pinned-crane recipe; `test-bump-inngest-bootstrap-pin.sh` (fixture-git-repo + stub-`crane` battery shape); `journald-config.test.sh` CF-4 (emitter-derived tag → allowlist lockstep); GuardA/GuardB section-floor conventions; `scripts/followthroughs/*` + `soleur:followthrough` enrollment (#7674 precedent); `scheduled-prod-version-drift.yml`'s `sentry-heartbeat` composite (the deferred absence-heartbeat shape).

## Hypotheses

No `firewall`/network-outage keyword in the issues — the L3→L7 checklist does not fire. The failure modes are coverage gaps: a name-level guard where a content-level one is needed (#4699), and an allowlist delivered to the wrong host with the gap invisible to config-presence checks (#7596). Both are named in the issue bodies with file/line evidence, verified above.

## Research Reconciliation — Spec vs. Codebase

| Brief/issue claim | Reality (read 2026-10-14, this branch) | Plan response |
|---|---|---|
| #4699: "AC6 only ever compares the pin against the semver-max tag; a non-max re-publish may diverge in content, never looked at" | Confirmed. AC6 is name-only; GuardB binds pin-internal consistency; GuardA binds tag→source; NOTHING binds tag→published-digest freshness. GuardA's own residual list names this exact hole. | Scheduled reconciler comparing live `crane digest` vs pin-history record per merged tag (D1–D4). |
| #4699: "Closing this would need a published-digest / content check — a separate, larger design" | The check is small once the record is located: git pin history already records each published tag's digest via the bump commits. | Reuse the record; ship script + workflow + battery + wiring pin. |
| #4699 re-evaluation criterion: "Promote and add a published-digest check if cloud-init ever pins a non-max tag" | The trigger has not fired (pin is the max, `v1.1.52`, and AC6 enforces that) — but the drain elected to ship it anyway. | The plan carries the trigger forward in the PR body: if the pin ever legitimately goes non-max, this check is what makes that state safe rather than blind. |
| #7596: "the fix is necessarily rebuild the bootstrap image, then replace the host — i.e. #7462's sequence" | #7462 is CLOSED and its replace already fired (2026-08-20); #7674 (successor) is also CLOSED. The delivery now rides the NEXT ordinary replace — there is no open tracked window to attach to. | The PR-side verifiable half ships (CI pins); the close condition is recorded in `inngest-server.md` where the replace procedure lives, keyed on the success-emitting identifier; `Ref #7596` only. |
| #7596: "close on a measured read … an off-host query returns rows for inngest-boot-phone-home (or the host's boot-stage markers) from the inngest host" | `inngest-boot-phone-home` is silent-on-success by design (CF-4c) — a healthy replaced host emits ZERO rows for it. `inngest-bs-token-restage` emits `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` on success every boot — the correct positive control. | The runbook step keys the measured read on the restage row; the phone-home identifier's presence is the CI-side pin's job. |
| Bump target is semver-max, so a non-max republish "reconciles to it (normally a no-op)" | Confirmed — the bump job resolves only TARGET=max and noop's on a non-max run; the non-max tag's new digest is recorded nowhere durable. | Exactly the gap the reconciler's per-tag sweep closes. |

## Problem Statement

Two "looks-covered but is not" gaps on the dedicated inngest host's supply/observability chain:

1. **Tag names are guarded; tag content is not.** AC6 asserts the pin equals the semver-max `vinngest-v*` tag *name*. `build-inngest-bootstrap-image.yml`'s designed escape hatch (non-`mirror_only` `workflow_dispatch` of an existing tag) rebuilds and re-pushes that tag, moving its GHCR digest — sanctioned, but today *silent*: nothing compares the tag's live digest against what its publish recorded, for the pinned tag or any other. A moved digest on the pinned tag orphans the `@sha256` the fleet pulls (zot's 5-tag retention makes that a bounded fuse); a moved non-max tag is invisible until someone pins it. "Tag exists" is necessary, not sufficient.
2. **The boot-trace allowlist lives on the wrong host, and nothing proves the right bake contains it.** `vector.toml`'s `inngest-boot-phone-home`/`inngest-bs-token-restage` entries reached web-1 via `vector-redeliver` (inert — the identifiers emit only on the inngest host) and reach the inngest host only inside the baked image. Until a bake+replace delivers them, the host's boot-trace death channel is dark — the #7228 condition. The PR-side gap: no CI pin proves the pinned image carries the entries (a future pin to an older tag would silently un-carry them), no suite pins the restage emitter↔allowlist lockstep, and no runbook records the measured close condition.

## Proposed Solution

Rulings are recorded in `knowledge-base/project/specs/feat-one-shot-4699-7596-drift-freshness-boot-trace/decision-challenges.md` — every technical row is `pending - assumed:` (no Agent tool on this harness); a `soleur:engineering:cto` ruling at review supersedes them.

### Workstream A — #4699: the published-digest freshness reconciler

1. **`.github/scripts/vinngest-digest-freshness.sh` — the comparator core** (fixture-tested, the `inngest-config-drift-compare.sh`/`bump-inngest-bootstrap-pin.sh` split convention). For each `vinngest-v*` tag merged into HEAD — the AC6 selector minus `tail -1`, so ALL merged tags (D3):
   - *Recorded digest:* `git log --format=%H -n1 -G 'soleur-inngest-bootstrap:<T>@' -- cloud-init.yml cloud-init-inngest.yml` finds the commit where `T`'s pin line last changed; extract `T@sha256:<64hex>` from whichever side of that commit still carries it (the newest -G hit may be the bump-AWAY commit, whose tree no longer pins T — check `hit:` then `hit^:`). This IS "what the build workflow recorded" — every bump commit is the publish workflow's authored, crane-resolved, cross-checked record (D2).
   - *Live digest:* `crane digest ghcr.io/jikig-ai/soleur-inngest-bootstrap:<T>` (retried, bounded `timeout`, parsed fail-closed to `^sha256:[0-9a-f]{64}$`).
   - *Verdict per tag:* `unchanged` | `moved` | `never-recorded` | `unresolvable`; `unmeasurable` for instrument failure (crane/auth/history), which is its own class and never a content verdict. `moved` or `unresolvable` on the PINNED tag (read from `cloud-init-inngest.yml`) → `::error::` + exit 1; `moved` OR `unresolvable` on a non-pinned tag → `::warning::` + exit 0 (CTO D4: a merged tag whose manifest is gone — publish died before push, untagged-manifest GC — is the same silent-divergence class; it cannot break a build nothing pins, but it must never be silent); `never-recorded` → step-summary only (legitimately superseded tags land here); `unmeasurable` → exit 2. When a tag is both never-recorded AND unresolvable the CONTENT verdict wins the row (the recorded side governs only the comparison — CTO D4). Result contract: `result=ok|findings|unmeasurable` (D4) — the Slack step branches on this output, NEVER `if: failure()` (the ⚠️ findings path exits 0 — CTO D4).
   - Env seams `VDF_REPO_DIR` / `VDF_CRANE` / `VDF_IMAGE` (the `BUMP_REPO_DIR` convention — this script never runs from an untrusted tree, so no argv gate); xtrace refusal + the `_bearer_ok`-family discipline for any credential it touches; `set -uo pipefail`.
2. **`.github/workflows/scheduled-vinngest-digest-freshness.yml` — the executor.** `gate-override: new-scheduled-cron-prefer-inngest` header (the scheduled-marketplace-drift justification, adapted: the subject is outside the product AND the check must fire while the inngest scheduler is down — D5). `schedule:` weekly + `workflow_dispatch`. `permissions: contents: read` + `packages: read`. Checkout `fetch-depth: 0` + `fetch-tags: true` (the recorded-digest derivation needs full history — the bump job's identical requirement). `docker/login-action` to GHCR + the pinned crane install block byte-parity with the bump job's (the cross-workflow parity pin precedent). Runs the script; a Slack step gated on the script's `result=` output (never `if: failure()` — the ⚠️ findings path exits 0, CTO D4) posts ❌ on error-class verdicts and ⚠️ on findings via `SLACK_RELEASES_WEBHOOK_URL` with jq `--arg` payloads. The gate-override comment block must explicitly assert **"no prd secrets"** — the schedule SKILL contract requires the assertion verbatim, not implied (CTO D5).
3. **`.github/scripts/test/test-vinngest-digest-freshness.sh` — the fixture battery** (auto-globbed by `run-all.sh`; BASH-ONLY). A fixture git repo carrying synthetic pin history on the two cloud-init files + a stub `crane` bin; drives every verdict class, the `hit`/`hit^` derivation edge, the could-not-measure class, and the empty-tag-set anti-vacuity arm.
4. **AC6d wiring pin in `cloud-init-inngest-bootstrap.test.sh`** — structural assertions that the workflow exists, is scheduled + dispatchable, invokes the script; and that the script exists and carries the recorded-digest derivation, the `crane digest` call, and the all-tags selector (the "guard exists and cannot be silently deleted" property — D9).
5. **Runbook:** `inngest-server.md` §Bootstrap-image release gains the digest-movement semantics paragraph — a non-`mirror_only` dispatch MOVES the tag's digest (the workflow's own CAUTION), the reconciler is the detector that makes movement non-silent, and a `moved` verdict on the pinned tag means the pin is orphaned: the response is a NEW tag, never a re-pin to the moved digest and never a blind `mirror_only` of the moved content.

### Workstream B — #7596: the boot-trace allowlist proof + close condition

6. **`journald-config.test.sh` — the missing `inngest-bs-token-restage` lockstep.** Derive `SyslogIdentifier=` from the `inngest-bs-token-restage.service` payload in `cloud-init-inngest.yml`; assert the derived tag is in the Source-4 include list (CF-4b shape) and the unit exists (an allowlist entry with no emitter is a dead no-op — CF-4a's inverse). Green-guard: both sides exist today; this closes an unasserted lockstep independent of #7596 (D6a).
7. **`cloud-init-inngest-bootstrap.test.sh` — identifiers-at-the-pinned-tag block** (new counted span after GuardA2 with its own floor — never inside the GuardA `expected 11` span). Assert `inngest-boot-phone-home` AND `inngest-bs-token-restage` are present in `git show "$GA_TAG_REF":apps/web-platform/infra/vector.toml` AND in HEAD's `vector.toml`. GuardA already proves the image's carriers byte-identical at the pinned tag; this names the content claim: *the image the next replace boots carries the allowlist* (D6b). Green today at `vinngest-v1.1.52`.
8. **`inngest-server.md` — the measured close condition.** New short step ("Post-replace: the boot-trace allowlist (#7596)") beside the replace/recovery flow: after an `inngest-host-replace`, query Better Stack for a `SYSLOG_IDENTIFIER=inngest-bs-token-restage` row from `host=soleur-inngest` — `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` fires on success every boot, so its arrival proves the entry is live on the host. Explicitly: do NOT close on repo config presence, on a web-1 read, or on `inngest-boot-phone-home` absence (silent-on-success by design).
9. **`vector-redeliver.md`** — update the "inngest host emits" Do-NOT-fire row: #7462 is closed; the remedy (rebake + replace) is unchanged; the close condition is the measured read now in `inngest-server.md` (Ref #7596).
10. **Optional wired half (D7):** `scripts/followthroughs/inngest-bs-token-restage-7596.sh` — a committed probe asserting the same row (TRANSIENT until the replace, never an absence arm), plus the `soleur:followthrough` directive comment on #7596 with `earliest=` pushed out per the #7674 amendment. Ships only if the ruling affirms the wired form.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Committed ledger file maintained by the bump job | A second maintained artifact plus a new ledger-only-PR machinery on every non-max re-publish (today the bump correctly noops there); buys coverage of the `never-recorded` class, which the check already reports as a named, non-alarming class. D2 dissent. |
| Digest check inside the publish workflow (pre/post `crane digest` around the push) | Sees only the sanctioned path; a tag moved by any other route (an unprescribed push, tag delete+recreate) escapes it. The scheduled resolver sees every movement. Useful as defense-in-depth later; not the close. D1 dissent. |
| Extending AC6 / the test suite to do the resolution | Structurally impossible — `deploy-script-tests` has no crane and no registry credential, and GuardA's commentary already records why adding them would red every PR permanently. The suite's role is the wiring pin only. |
| Inngest dispatch-hybrid (`cron-vinngest-digest-freshness.ts`) | The subject is outside the product, needs only GHA-native perms, and must fire while inngest is down — dispatch-hybrid couples the supply-chain check to the thing it watches. D5 dissent; the gate-override precedent covers this. |
| Issue-filing verdicts (scheduled-prod-version-drift shape) | `issues: write` + dedupe + close-on-recovery machinery for a signal already carried by Slack + step summary. Ports directly if the ruling wants persistence. D4 dissent. |
| Closing #7596 on the CI pin | The issue's own close condition forbids it — a measured read off the replaced host, or the identifier present in the host's LIVE `/etc/vector/vector.toml`. Repo config presence is the trap the issue was filed about. `Ref #7596` stands. |
| Asserting the identifiers at HEAD only | HEAD's vector.toml is not the image — the pinned tag's tree is. GuardA binds them today, but the explicit at-the-tag assertion survives a GuardA carve-out and names the content claim directly. |

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** `test-vinngest-digest-freshness.sh` battery (RED — script absent); AC6d wiring pins in `cloud-init-inngest-bootstrap.test.sh` (RED — workflow + script absent); the identifiers-at-tag block and the journald lockstep are GREEN-GUARD additions (both sides exist today — write them last of the RED set, verified passing on main).

**Phase 1 — Workstream A.** The freshness script + battery; the scheduled workflow; AC6d; infra-validation path-map comment entries if the detect globs require them.

**Phase 2 — Workstream B.** `journald-config.test.sh` lockstep + floor ratchet; the identifiers-at-tag block + its own floor; the two runbook edits; the optional followthrough probe + directive.

**Phase 3 — Suites green + floors.** `run-all.sh` green (MIN_SUITES floor untouched); `cloud-init-inngest-bootstrap.test.sh`, `journald-config.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `inngest-boot-emitter.test.sh`, `fresh-boot-parity.test.sh`, `vector-pii-scrub.test.sh` green at measured floors; `bash plugins/soleur/test/c4-count-parity.test.sh` green (no C4 change — no new actor/system/container).

**Phase 4 — Docs + handoff.** Runbook digest-semantics paragraph; PR body with the production-mutation first line, `Closes #4699` / `Ref #7596`, and the unrun operator list.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6d wiring pins (Workstream A); the identifiers-at-the-pinned-tag block (Workstream B) in a new counted span with its own floor.
- `apps/web-platform/infra/journald-config.test.sh` — `inngest-bs-token-restage` two-sided lockstep; `MIN_TOTAL`/floor ratchet to measured.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — the post-replace measured-read step + the §Bootstrap-image-release digest-movement paragraph.
- `knowledge-base/engineering/operations/runbooks/vector-redeliver.md` — the "inngest host emits" row: #7462 closed; point at the runbook close condition (Ref #7596).
- `.github/workflows/infra-validation.yml` — path-map comment entries only if the detect/path globs do not already cover the new `.github/workflows/` + `.github/scripts/` paths.

## Files to Create

- `.github/scripts/vinngest-digest-freshness.sh` — the comparator core.
- `.github/workflows/scheduled-vinngest-digest-freshness.yml` — weekly + dispatch, gate-override header, GHCR login + pinned crane, Slack on findings.
- `.github/scripts/test/test-vinngest-digest-freshness.sh` — the fixture battery (auto-globbed).
- `scripts/followthroughs/inngest-bs-token-restage-7596.sh` — OPTIONAL, D7-contingent (the wired close-condition probe).
- `knowledge-base/project/specs/feat-one-shot-4699-7596-drift-freshness-boot-trace/{decision-challenges.md,tasks.md}` — spec artifacts (this delivery).

Not edited, by design: `vector.toml` (the identifiers are already there — asserting, not shipping content), `cloud-init-inngest.yml` / `cloud-init.yml` (no pin or payload change — GuardA stays green; a carrier edit would manufacture the advisory-red + mint+pin-bump dance for zero content), `build-inngest-bootstrap-image.yml` / `mint-inngest-bootstrap-tag.yml` / `bump-inngest-bootstrap-pin.sh` (the record this design reads is already written correctly — no publish-path change), `inngest-bootstrap.sh`, the four `vinngest` pin sites (ADR-232 owns them), and no `cron-*.ts` (D5 — GHA-scheduled instead).

## Open Code-Review Overlap

Open PRs touching shared files (checked 2026-10-14): **#10255** (vector journald admission partition) edits `vector.toml` Sources 1/2 and `journald-config.test.sh` — textual conflict surface on the suite (my restage block sits beside CF-4); their ruling explicitly leaves the Source-4 include array untouched, so no semantic clash. **#10257** (inngest image lifecycle) adds AC6c + write_files pins to `cloud-init-inngest-bootstrap.test.sh` and a `inngest-config-refresh` tag to `vector.toml` — different regions of the same suite; whoever merges second rebases. **#10081 PARKED** strips `cloud-init-inngest.yml` — no overlap (this PR does not edit it). **#10268** (retire inngest host dark-gate) — adjacent machinery, watch its diff on the same runbook/suite territory.

## User-Brand Impact

**If this lands broken, the user experiences:** the sole Inngest scheduler — every statutory-deadline and notification cron fires from it — losing its supply-chain visibility twice over. A re-published bootstrap tag whose content diverged from its recorded digest stays invisible: a later `inngest-host-replace` or `mirror_only` backfill could pin/serve image bytes nobody recorded, and the host boots them as root. Meanwhile the host's boot-trace death channel (#7228's fix) remains dark with the false comfort of "the config is on main": if the host ever fails to boot, the diagnostic that exists precisely for that moment is absent, and the silence reads as health — the exact failure mode that made the host "dark forever" once already. In the worst case a bad or unrecorded image reaches the sole scheduler and no one can tell, off-box, why it did not come up.
**If this leaks/is subverted, the user's [data/workflow/money] is exposed via:** the reconciler is read-only (GHCR manifest HEADs + git history — no write surface beyond a Slack post); the only new credential touch is `packages: read` GITHUB_TOKEN inside the workflow, the bump job's existing recipe. No user data path is touched.
- **Brand-survival threshold:** `aggregate pattern` — the blast radius of a wrong verdict or a silently-deleted check is fleet-wide scheduler integrity/observability, not a single user record; every component fails loud (`::error::`, Slack, suite RED, `unmeasurable`-as-its-own-class).

## Observability

```yaml
liveness_signal:
  what: "the reconciler's own scheduled run: weekly tick + workflow_dispatch; per-tag verdict table in the step summary; the suite wiring pin (AC6d) makes the check's deletion a CI red"
  cadence: "weekly schedule (staggered cron) + on-demand dispatch"
  alert_target: "Slack ❌ on error-class verdicts (moved/unresolvable on the pinned tag; unmeasurable), ⚠️ on non-pinned moved; ::error::/::warning:: annotations in the run log"
  configured_in: ".github/workflows/scheduled-vinngest-digest-freshness.yml"
error_reporting:
  destination: "GitHub Actions run log (::error::/::warning::) + step summary verdict table + SLACK_RELEASES_WEBHOOK_URL post; the comparator's result= contract is machine-readable"
  fail_loud: "every verdict class is named; could-not-measure is exit 2 and never a content verdict (the QUERY_UNAVAILABLE precedent); a missing script/workflow/seam is a suite red via AC6d"
failure_modes:
  - mode: "a merged tag's live digest moved vs its recorded digest"
    detection: "the reconciler itself: crane digest vs git pin history -> moved (pinned tag: exit 1 + Slack; non-pinned: ::warning:: + Slack) — layer 6 (workflow run log / synchronous workflow signal)"
    alert_route: "layer 6 — ::error:: + Slack webhook (the pin-bump-failure Slack precedent)"
  - mode: "the pinned tag's digest disappears (untagged-manifest GC or tag delete+recreate)"
    detection: "crane digest resolves nothing -> unresolvable on the pinned tag -> exit 1 — layer 6"
    alert_route: "layer 6 — ::error:: + Slack"
  - mode: "crane/GHCR auth or git history unreadable (instrument failure)"
    detection: "unmeasurable exit 2 — never a content verdict — layer 6"
    alert_route: "layer 6 — ::error:: + Slack"
  - mode: "the check itself is deleted or de-wired"
    detection: "AC6d structural pins in cloud-init-inngest-bootstrap.test.sh (workflow exists, scheduled+dispatch, invokes the script; script carries derivation + crane call + all-tags selector) — layer 6"
    alert_route: "CI infra-validation reds the PR — layer 6"
  - mode: "a future pin lands on a tag whose vector.toml lacks the #7457 identifiers"
    detection: "the identifiers-at-the-pinned-tag block (GuardA-adjacent) reds — layer 6"
    alert_route: "CI suite red — layer 6; the post-replace measured read rides journald -> vector -> Better Stack (layer 3, Vector journald shipper) as the production-side close condition recorded in the runbook"
  - mode: "the schedule silently stops firing (GitHub-side)"
    detection: "no Sentry check-in is wired in v1 — named deferred: optional sentry_cron_monitor resource + sentry-heartbeat composite (the scheduled-prod-version-drift shape) — layer 6 residual"
    alert_route: "deferred — see Deferred; residual stated honestly"
logs:
  where: "run log + step summary of scheduled-vinngest-digest-freshness runs; the suite's own output for the pins; the post-replace close-condition row lands in Better Stack soleur-inngest source via journald tag inngest-bs-token-restage -> Vector Source 4 (layer 3)"
  retention: "GHA run-log retention for the reconciler; Better Stack source retention (inherited) for the close-condition row"
discoverability_test:
  command: grep -c 'vinngest-digest-freshness' .github/workflows/scheduled-vinngest-digest-freshness.yml .github/scripts/vinngest-digest-freshness.sh
  expected_output: ">= 2 hits across the two files"
```

## Encryption Posture

```yaml
at_rest:
  - store: "none new — no state file, no ledger, no secrets on disk; the recorded digest lives in git history (the bump commits), the live digest is read per-run"
    mechanism: n/a
    evidence: "the comparator is stateless by construction (D2)"
    defends_against: "n/a"
    does_not_defend: "n/a"
    disclosed_as: "this plan"
    live_verification: "the reconciler itself"
in_transit:
  - path: "GHA runner -> ghcr.io (TLS): crane digest manifest HEADs"
    protection: "packages: read GITHUB_TOKEN via docker/login-action — the bump job's existing recipe; read-only"
  - path: "GHA runner -> Slack webhook (TLS): finding posts"
    protection: "SLACK_RELEASES_WEBHOOK_URL repo secret; jq --arg payloads are injection-inert; digest values are integrity metadata, not secrets"
```

## Guard Contract

### Guard 1 — Every merged vinngest tag's live digest is compared against its recorded digest, per period

**Property.** The reconciler emits exactly one verdict per merged `vinngest-v*` tag — never zero rows (that is `unmeasurable`, never a silent pass), never a skipped tag. `moved`/`unresolvable` on the pinned tag always exits nonzero and posts; `moved`/`unresolvable` on a non-pinned tag always warns and posts.

**Assembly.** `vinngest-digest-freshness.sh` (the single chokepoint every verdict flows through) + the workflow's GHCR login + pinned crane.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | selector regresses to `tail -1` (max only — the AC6 blind spot) | RED: battery fixture with 2 tags asserts BOTH are classified |
| 2 | `moved` on the pinned tag exits 0 | RED: fixture stub crane returns a different digest for the pinned tag → exit 1 |
| 3 | recorded-digest derivation reads `hit:` only (misses bump-AWAY commits) | RED: fixture whose newest -G hit is the move-away commit; the digest must come from `hit^:` |
| 4 | crane failure collapses into `unresolvable` (instrument reads as content) | RED: stub crane exits nonzero → `unmeasurable` exit 2, never `unresolvable` |
| 5 | empty merged-tag set reports green | RED: anti-vacuity arm — zero tags is a named failure |
| 6 | `never-recorded` alarms | RED: a fixture tag with no pin history is listed, exit stays clean |
| 7 | workflow loses `fetch-depth: 0`/`fetch-tags: true` or the GHCR login | RED: AC6d wiring pins + the workflow's own step shape |
| 8 | `docker push`/`packages: write`/`id-token` added to the workflow | RED: forbidden-token assertion in the battery (the check lane is read-only, the check-inngest-bootstrap-build precedent) |

**Harness rows.** Fixture git repo + stub `crane` on PATH via `VDF_CRANE`; every arm is a synthesized repo, never the live one (cq-test-fixtures-synthesized-only). Floor: `executed >= <measured>` after implementation.

**Anchor.** The suite-side AC6d asserts the wiring; the workflow's own weekly green is the external anchor; the first `moved` verdict in production is the functional proof.

### Guard 2 — The pinned image provably carries the boot-trace allowlist; the close condition is measured, not assumed

**Property.** Both `#7457` identifiers are asserted present in `vector.toml` at the pinned tag AND at HEAD (the bake-content claim); the `inngest-bs-token-restage` emitter↔allowlist lockstep is pinned on both sides (a deletion of either side reds); the runbook records a measured-read close condition keyed on the success-emitting identifier.

**Assembly.** The GuardA-adjacent block (asserts at `git show $GA_TAG_REF:vector.toml`, the same tag ref GuardA already resolves) + the `journald-config.test.sh` lockstep block (derives the tag from the unit payload — never a restated literal).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | an identifier dropped from HEAD's vector.toml | RED: both blocks fail |
| 2 | pin moved to a tag whose vector.toml lacks an identifier | RED: the at-tag assertion fails (this is the "next bake contains it" proof) |
| 3 | allowlist entry present but the unit's SyslogIdentifier renamed | RED: the derived-tag lockstep fails — the entry becomes a dead no-op |
| 4 | unit payload removed from cloud-init-inngest.yml | RED: the emitter-side derivation fails, never vacuous |
| 5 | block appended inside the GuardA counted span (floor says expected 11) | RED: floor mismatch — the new block lives in its OWN counted span |
| 6 | restage assertion written as a hardcoded literal (tag restated, not derived) | RED at review: the derivation is load-bearing — two hardcoded copies agree while both disagree with reality (the CF-4 rationale) |

**Anchor.** The close condition is not satisfiable from this PR — the runbook step + optional followthrough probe carry it to the replace window, keyed on `SOLEUR_INNGEST_BS_TOKEN_RESTAGED` from `host=soleur-inngest`.

## Infrastructure (IaC)

### Terraform changes

None. No new resource, variable, secret, or provider. (The optional `sentry_cron_monitor` absence heartbeat is a named deferred item, not this PR.)

### Apply path

Code-only at merge. Nothing reaches a host: no carrier file is edited, no `user_data` re-renders, the scheduled workflow is read-only. The `#7457` allowlist reaches the inngest host only via a future image bake + `inngest-host-replace` — ordinary machinery, explicitly not this PR.

### Host fan-out

None. The reconciler runs entirely in GHA.

### Distinctness / drift safeguards

The recorded digest is derived from git pin history — the same bytes the bump job wrote — so there is no second record to drift. The crane install block is byte-parity-pinned against the bump job's (the established cross-workflow parity convention). AC6d pins the workflow↔script wiring.

### Vendor-tier reality check

`crane digest` is a manifest HEAD against GHCR — anonymous reads do not apply (the package is private; `packages: read` GITHUB_TOKEN is sufficient and already proven in the bump job). 41 tags → 41 HEADs per weekly run: trivially within GHCR rate expectations.

## Architecture Decision (ADR/C4)

### ADR

No new ADR. The check extends the ADR-232 pin-machinery posture (the publish workflow is the sole author of pin records) without amending it — the recorded-digest source IS the bump commits. If the CTO ruling prefers the ledger (D2 dissent), a dated ADR-232 amendment naming the ledger as the record ships in-PR.

### C4 views

No C4 change: no new human actors, no new external systems (GHCR, Slack, git already modeled), no new containers — a scheduled read-only workflow. Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` at implementation to confirm.

### Sequencing

N/A — no status flips.

## Downtime & Cutover

- **Offline-inducing operations:** none. Every change is CI/tests/scripts/runbook text plus a read-only scheduled workflow.
- **Surface affected:** CI signal + the inngest image supply-chain visibility only.
- **Zero-downtime evaluation:** trivially satisfied — nothing executes on or writes to a host.
<!-- lint-infra-ignore start -->
- **Residual downtime acceptance:** none requested.
<!-- lint-infra-ignore end -->

## Domain Review

**Domains relevant:** none

No cross-domain implications — internal CI/infra machinery. Technical forks are `pending - assumed:` rows in `decision-challenges.md`. Product/UX gate: no UI-surface file. GDPR gate: no schema/auth/API-route/.sql surface; the reconciler reads image manifests and git history, no regulated data path.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | #4699: "Closing this would need a published-digest / content check" | Workstream A §1–§5 | mapped — the check is "the tag's resolved digest vs what the build workflow recorded", per merged tag |
| 2 | #4699 re-evaluation: "Promote … if cloud-init ever pins a non-max vinngest-v* tag" | PR body + decision D8 | carried forward — the trigger is recorded verbatim so a reader knows when the check becomes load-bearing |
| 3 | #7596: "(a) a CI-side assertion that the inngest image's baked vector.toml carries both identifiers" | Workstream B §6–§7 | mapped — journald lockstep + identifiers-at-the-pinned-tag block |
| 4 | #7596: "(b) the post-replace measured-read close condition recorded where the replace runbook will find it" | Workstream B §8–§9 (+§10 optional) | mapped — inngest-server.md step keyed on SOLEUR_INNGEST_BS_TOKEN_RESTAGED; vector-redeliver.md pointer refreshed |
| 5 | #7596: "Do NOT close on config presence" | PR body `Ref #7596`; D7/D8 | honored — the host has not been replaced |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Scheduled reconciler (script + workflow + battery + wiring pin) | "Closing this would need a published-digest / content check" | asked (shape is the "smallest comparison" the brief names) |
| Recorded digest = git pin history | "comparing the tag's resolved digest against what the build workflow recorded" | asked — the bump commits ARE the workflow-authored record (verified `git log -G` returns them) |
| Identifiers-at-the-pinned-tag block | "a CI-side assertion that the inngest image's baked vector.toml carries both identifiers" | asked |
| `inngest-bs-token-restage` journald lockstep | "the trap `journald-config.test.sh` already guards for this identifier" | inferred — justification: the file guards it for `inngest-boot-phone-home` only; the restage entry is the same trap, unguarded (deleting it greens today) |
| Runbook close-condition step | "recorded where the replace runbook will find it (inngest-server.md / the replace procedure)" | asked — keyed on `inngest-bs-token-restage`, not `inngest-boot-phone-home`, because the latter is silent-on-success (issue's own methodology note: identifier probe needs a liveness-positive signal) |
| Followthrough probe (optional, D7) | — | inferred — justification: #7674's enrollment precedent makes the close condition self-executing rather than operator-memory-dependent |
| `gate-override` schedule justification | — | inferred — justification: ADR-033 makes Inngest the default substrate; the override needs the same recorded reasoning scheduled-marketplace-drift carries |

### Split Assessment

- Subsystems touched: 3 — `.github`, `apps/web-platform`, `knowledge-base`
- Planned files: ~5 edited + 5 created | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the brief fixes this PR to cover both issues; the two workstreams share the "tag exists ≠ content correct" theme and are independently reviewable.

## Acceptance Criteria

- [ ] `.github/scripts/vinngest-digest-freshness.sh` exists; classifies `unchanged|moved|never-recorded|unresolvable` per merged tag; `unmeasurable` is exit 2 and never a content verdict; pinned-tag `moved`/`unresolvable` exits 1.
- [ ] `bash .github/scripts/test/test-vinngest-digest-freshness.sh` exits 0 at its measured floor, including the `hit`/`hit^` derivation edge and the anti-vacuity arms.
- [ ] `.github/workflows/scheduled-vinngest-digest-freshness.yml` exists: `gate-override` header, `schedule:` + `workflow_dispatch`, `contents: read` + `packages: read`, `fetch-depth: 0` + `fetch-tags: true`, GHCR login, pinned crane, Slack step; no `docker push`/`packages: write`/`id-token`.
- [ ] `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` exits 0 incl. AC6d (wiring pins) and the identifiers-at-the-pinned-tag block at its own measured floor.
- [ ] `bash apps/web-platform/infra/journald-config.test.sh` exits 0 at its ratcheted floor incl. the `inngest-bs-token-restage` two-sided pin.
- [ ] `bash .github/scripts/test/run-all.sh` exits 0 (`MIN_SUITES` floor untouched); `bash apps/web-platform/infra/inngest-boot-emitter.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `fresh-boot-parity.test.sh`, `apps/web-platform/test/infra/vector-pii-scrub.test.sh` all exit 0.
- [ ] `inngest-server.md` carries the post-replace measured-read step keyed on `SOLEUR_INNGEST_BS_TOKEN_RESTAGED`/`inngest-bs-token-restage` from `host=soleur-inngest`, and the §Bootstrap-image-release digest-movement paragraph; `vector-redeliver.md`'s Do-NOT-fire row no longer cites the closed #7462 as the window.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
- [ ] `git diff --name-only origin/main...HEAD` contains neither `vector.toml` nor `cloud-init-inngest.yml` (assertions only — GuardA stays green, no advisory drift expected).
<!-- lint-infra-ignore start -->
- [ ] PR body's FIRST line answers "does merging this mutate production?" (`no — CI scripts, a read-only scheduled reconciler, suite assertions, and runbook text only; no carrier or pin change, nothing reaches a host`), carries `Closes #4699` `Ref #7596` (the Closes contingent on D8), carries the #4699 re-evaluation trigger forward in one line, and lists unrun operator steps: `inngest-host-replace` (Ref #7596), the post-replace measured read (Ref #7596), the optional followthrough-directive enrollment (Ref #7596), the optional sentry_cron_monitor apply.
<!-- lint-infra-ignore end -->

## Acceptance-criteria → workstream map

| AC | Workstream |
|---|---|
| Freshness script verdicts + battery | A |
| Scheduled workflow + auth/tooling + Slack | A |
| AC6d wiring pin | A |
| Digest-movement runbook paragraph | A |
| identifiers-at-the-pinned-tag block | B |
| journald restage lockstep | B |
| Post-replace measured-read step + vector-redeliver row | B |
| c4 parity / no-carrier-edit / PR-body requirements | both |

## Test Scenarios

- Given merged tags T1 (pinned, recorded D1) and T2 (non-pinned, recorded D2), when the reconciler runs against a stub crane returning D1 and D2', then T1 reports `unchanged`, T2 reports `moved`, and the run exits 0 with `::warning::` (sanctioned-movement-visibility arm). (battery)
- Given the stub crane returns D1' for the pinned tag, when the reconciler runs, then the verdict is `moved` on the pinned tag → `::error::` + exit 1. (battery)
- Given the newest `git log -G` hit for T is the bump-AWAY commit, when the derivation runs, then the recorded digest comes from `hit^:` — the bump-TO side — and classifies correctly. (battery)
- Given stub crane exits nonzero for one tag, when the reconciler runs, then the whole run is `unmeasurable` exit 2 — never an `unresolvable` content verdict. (battery)
- Given zero merged vinngest tags, when the reconciler runs, then it fails with a named error rather than a vacuous green. (battery)
- Given a fixture tag with no pin history, when the reconciler runs, then it is listed `never-recorded` and the run stays clean. (battery)
- Given a PR deleting `"inngest-bs-token-restage"` from the Source-4 list (or renaming the unit's `SyslogIdentifier=`), when the suite runs, then `journald-config.test.sh` reds on the lockstep. (structural)
- Given a future pin to a tag whose `vector.toml` lacks either `#7457` identifier, when the bootstrap suite runs, then the at-tag block reds. (structural)
- Given the workflow loses `fetch-tags: true` or gains `docker push`/`id-token`, when AC6d runs, then it reds on the wiring pins. (structural)
- Given the next `inngest-host-replace` lands, when the post-replace query runs, then a `SOLEUR_INNGEST_BS_TOKEN_RESTAGED` row from `host=soleur-inngest` closes #7596 — and its absence correctly does not. (deferred, runbook step)

## Dependencies & Risks

- **The `never-recorded` class is real but bounded** — a merged tag superseded before its bump PR merged was never pinned, so pin history holds no record for it. It is reported, not alarmed (a legitimately superseded tag is the common case); if the ruling wants it covered, the D2 ledger is the follow-up.
- **A `moved` verdict is not self-remediating** — by design. A sanctioned CVE rebuild moves the digest deliberately; the check makes the movement non-silent and the runbook names the response (new tag, never re-pin to moved content). Auto-remediation was considered and rejected.
- **`git log -G` per tag is 41 history walks** — on a `fetch-depth: 0` checkout this is seconds per run; acceptable weekly. The suite-side wiring pin does no history walk.
- **Sibling PR drift.** #10255 touches `journald-config.test.sh` + `vector.toml`; #10257 touches `cloud-init-inngest-bootstrap.test.sh` + `vector.toml`. Textual conflicts expected on the suite files; neither changes the Source-4 include array's semantics. Whoever merges second rebases.
- **Slack secret availability** — `SLACK_RELEASES_WEBHOOK_URL` is already a repo secret consumed by sibling steps; an unset value degrades to `::warning::` (the established pattern), never a hard fail.
- **GitHub schedule reliability** — `schedule:` delivery is best-effort (the scheduled-inngest-health commentary measured */15 crons firing once per 2-7 h under load); a weekly cadence tolerates this. The deferred `sentry_cron_monitor` covers "the schedule stopped firing entirely".
- **PARKED PR #10081** strips `cloud-init-inngest.yml` — untouched by this PR; if it ever merges first it cannot conflict.

## Sharp Edges

- **No carrier edits.** The instant `vector.toml` or `cloud-init-inngest.yml` payload lines change, GuardA goes advisory-red and the merge triggers the mint+pin-bump machinery for zero content gain — every assertion in this PR reads the carriers, none writes them. If a fork lands a vector.toml edit anyway, the AC asserting "no carrier edit" must be revisited, not the machinery.
- **The derivation must check BOTH sides of the newest `-G` hit.** `git log -G 'bootstrap:T@'` returns the commit where T's pin *changed* — which is the bump-AWAY commit for every superseded tag, whose tree no longer contains `T@`. Reading `hit:` only yields empty for every non-current tag: the check would report `never-recorded` on the whole fleet and look correct. The battery has a dedicated arm for this edge.
- **`unmeasurable` ≠ `unresolvable`.** A crane failure (auth blip, 5xx) must not degrade into "the tag has no image" — the could-not-measure class exists so an instrument outage never produces a content verdict (the `QUERY_UNAVAILABLE` precedent; mirror the inngest-config-drift split).
- **The selector must be all-tags, not `tail -1`.** Copying AC6's pipeline verbatim re-imports exactly the blind spot being fixed. The battery pins the selector covering ≥2 tags; the AC6d pin asserts the script's selector derives every merged tag.
- **`inngest-boot-phone-home` cannot be the close-condition probe.** It is silent-on-success by design (CF-4c — every logger call sits in a failure arm). A healthy replaced host emits zero rows for it; an absence-check there is the fail-open trap the issue's methodology note already names. `inngest-bs-token-restage` emits on success every boot — it is the positive control.
- **`git show` in a worktree needs `git -C "$SCRIPT_DIR"`, never bare `git`** — the AC6/GuardA lesson in this same file: bare git resolves against process CWD and can pair one repo's blobs with another tree's files.
- **Suite floors move by MEASURED count only**, and the new identifiers block gets its OWN counted span — never inside GuardA's `expected 11` inventory.
- **TEST-AUTHORING RULE stands** (the drain's detector): no bare `<<`/`<<<` outside a real heredoc (assemble `_lt='<'`), tail floors outside heredoc-blanked spans self-exiting `exit 1`, no `producer | grep -q`, no counter words beside `-lt` on arm-level `if` lines.
- **`.github/scripts/test/` batteries are BASH-ONLY** (the run-all.sh contract — `guard-script-fixture-tests` is REQUIRED, merge_group-triggered, unfiltered): the stub `crane` is a shell script on PATH via `VDF_CRANE`, never a real binary or network call.
- **Do not "fix" `never-recorded` by fabricating a record.** A merged tag with no pin-history row is honestly unverifiable — listing it is the signal; synthesizing a digest from the build log would be a second, weaker record with all the drift problems D2 rejected.

## Deferred

<!-- lint-infra-ignore start -->
- **`inngest-host-replace` dispatch (operator authorization).** The `#7457` allowlist reaches the inngest host only inside the next baked image via the ordinary replace machinery — the delivery vehicle for #7596, not this PR's work. Listed unrun in the PR body. `Ref #7596`.
- **Post-replace measured read (the recorded runbook step).** The Better Stack query written into `inngest-server.md` — run after the next replace; its positive row is #7596's close condition. `Ref #7596`.
- **Followthrough-directive enrollment (D7-contingent).** If the wired half is affirmed: the `soleur:followthrough` comment on #7596 carrying `scripts/followthroughs/inngest-bs-token-restage-7596.sh` with `earliest=` pushed out (TRANSIENT is the legitimate state until the replace; the #7674 amendment). `Ref #7596`.
- **`sentry_cron_monitor` absence heartbeat for the reconciler (optional).** A new TF resource + apply plus the `sentry-heartbeat` composite step — covers "the weekly schedule silently stops firing". Not required for v1: wiring pins make deletion advisory-red, the battery is merge-blocking, and findings are already Slack-posted.
- **Digest-ledger escalation (D2 dissent).** If a ruling wants `never-recorded` covered: the committed `vinngest-image-digests.tsv` written by the bump job + a ledger-only PR path for non-max republishes. Recorded shape, not built.
- **First manual reconciler run (optional).** `gh workflow run scheduled-vinngest-digest-freshness.yml` post-merge to watch the first live verdict table — optional because the weekly tick will produce it regardless; the run is read-only either way.
<!-- lint-infra-ignore end -->
