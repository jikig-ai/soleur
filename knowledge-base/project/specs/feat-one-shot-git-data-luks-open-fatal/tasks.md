# Tasks — fix the git-data `stage:luks_open` boot fatal

Plan: `knowledge-base/project/plans/2026-08-03-fix-git-data-luks-open-boot-fatal-plan.md`
Issue: **#7204** · Branch: `feat-one-shot-git-data-luks-open-fatal`
Threshold: `single-user incident` (`requires_cpo_signoff: true`)

**Hard constraint on every task below:** no change may make the LUKS mount succeed by reducing what is encrypted. If the corrected template cannot mount the mapper, it must fail loud with the cause named — never fall through.

---

## Phase 0 — Probe first. Ships alone, before any fix line is written.

- [ ] **0.1** Re-run the four-arm privileged-container probe (loop file → `luksFormat` → `luksOpen` → mkfs arm → `mount`) and record that **all arms pass on a kernel providing `quota_v2`**. This is the evidence that a naive container mount test cannot fail on the unfixed template.
  - [ ] 0.1.1 Record kernel version, `dumpe2fs -h` features and `mount` rc per arm into the commit message.
- [ ] **0.2** Measure the candidate fix set in the same container, recording features + mount rc for each:
  - [ ] 0.2.1 `mkfs.ext4 -q -O project` (no `quota`) — does mke2fs accept it, and does the superblock carry `quota`?
  - [ ] 0.2.2 `tune2fs -O quota <dev>` on a `project`-only fs — is `quota` addable later, offline, without recreating the volume?
  - [ ] 0.2.3 `mkfs.ext4 -q` (plain) — the sibling-parity baseline (`cloud-init-registry.yml:790`).
  - [ ] 0.2.4 `mkfs.ext4 -q -O quota,project` + `mount -o noquota` — does the mount option escape the feature-driven enable path? (Expected NO; probe rather than assume.)
- [ ] **0.3** Re-fetch `ubuntu-24.04-server-cloudimg-amd64.manifest`; pin the observed `linux-*` package set and the fetch date into the fix's comment block. Confirm `linux-modules-extra-*` absent.
- [ ] **0.4** Write the fix-selection decision into the plan record **before** Phase 1 starts. The chosen candidate must (a) produce a filesystem whose mount does not depend on `quota_v2`, (b) preserve the most future capability at zero present cost, (c) be correct whether or not assumption A1 holds.
- [ ] **0.5** Run `/soleur:gdpr-gate` against this plan (trigger (b): `single-user incident` threshold). Advisory only.

## Phase 1 — Fix the template

- [ ] **1.1** RED first: write the Phase-2 assertions and watch them fail against the unmodified template (`cq-write-failing-tests-before`).
- [ ] **1.2** Apply the selected `mkfs` change in `apps/web-platform/infra/cloud-init-git-data.yml`.
- [ ] **1.3** Replace the `#6982 W5/R31` comment with the measured mechanism (feature bit → `ext4_enable_quotas` → `find_quota_format` → `ESRCH`), the image fact + fetch date, and what capability was preserved vs deferred.
- [ ] **1.4** Make the mount cause-carrying, independently of 1.2:
  - [ ] 1.4.1 Capture the mount's own stderr to a file; pass that file to `git-data-emit` as the detail source.
  - [ ] 1.4.2 Append `dmesg | tail -n 20` to the detail file on failure.
  - [ ] 1.4.3 Keep the failure fatal — no `|| true`, no fallback mount of the raw device.
- [ ] **1.5** Do **not** widen `_clean`'s `tail -c 180` unless 0.1/1.4 show the targeted detail file still truncates below usefulness; if needed, raise it for the detail-file path only, with the reason in the comment.

## Phase 2 — Regression test that can fail on the unfixed template

- [ ] **2.1** Extend `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — **R1**, the kernel-independent feature-set allowlist:
  - [ ] 2.1.1 Render the real template, extract the LUKS heredoc, run its `mkfs` line against a loop-backed LUKS mapper.
  - [ ] 2.1.2 Read `dumpe2fs -h`; assert the feature set contains nothing on the denylist.
  - [ ] 2.1.3 Create the committed denylist fixture (today: `quota`), each entry carrying its provenance URL and fetch date.
  - [ ] 2.1.4 **Demonstrate fail-on-unfixed in the same run:** re-run R1 against `git show <merge-base>:apps/web-platform/infra/cloud-init-git-data.yml` and assert non-zero exit.
- [ ] **2.2** **R2** — mount sanity: after R1's mkfs, mount the mapper and assert `mountpoint -q`. Write its kernel-dependence limitation into the test body so a green run is not over-read.
- [ ] **2.3** **R3** — diagnosability: force a mount failure deterministically (corrupt superblock) and assert the emitted event's `detail` names the mount error **and** carries `dmesg` context. Must go RED on the unfixed template.
- [ ] **2.4** Re-aim **B16** in `apps/web-platform/infra/git-data-luks.test.sh` at the post-fix invariant; keep its mutation arms and add one that would catch a re-introduction of the `quota` feature; rewrite its comment to cite #7204 and the measured mechanism. Do not delete it.
- [ ] **2.5** Register per `apps/web-platform/infra/run-registered-suites.sh` conventions — extend the three named suites, create no fourth (no orphan suite).

## Phase 3 — Make the rehearsal report a cause (bounded)

- [ ] **3.1** Add `JSONExtractString(raw,'detail') AS detail` and `rc` to `HOST_SQL` in `scripts/followthroughs/git-data-rung2-evidence-capture.sh`.
- [ ] **3.2** Correct the header's Sentry-capability claim to what is measured today (search **is** available via `SENTRY_ISSUE_RO_TOKEN`), citing `hr-verify-repo-capability-claim-before-assert`. Do not implement the Sentry read path (#7116 owns it).
- [ ] **3.3** Extend `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` to pin that `HOST_SQL` selects `detail`, with a mutation arm.
- [ ] **3.4** Out of scope, do not touch: the three-state verdict contract, the anchor query, the poll bounds.

## Phase 4 — ADR

- [ ] **4.1** Write the birth-filesystem feature-set ADR under `knowledge-base/engineering/architecture/decisions/` (provisional ordinal **ADR-158**; `/ship` re-verifies against `origin/main`).
- [ ] **4.2** `## Decision` names the selected candidate; `## Alternatives Considered` carries the Phase-0 measurement for all four candidates, including `mount -o noquota` and `tune2fs -O quota`.
- [ ] **4.3** Status `accepted` if Phase 0 confirms; `adopting` if any measurement is ambiguous.
- [ ] **4.4** On any renumber, sweep `grep -rn 'ADR-158' knowledge-base/project/{plans,specs}/feat-one-shot-git-data-luks-open-fatal/` in the same edit.

## Phase 5 — C4 correction

- [ ] **5.1** Correct the `gitDataStore` "deliberately UNFIRED" sentence in `knowledge-base/engineering/architecture/diagrams/model.c4` (~line 214) — the route has fired four times and consumed three paid hosts. Add the current birth-blocking fact.
- [ ] **5.2** Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

## Phase 6 — Verification and hand-off

- [ ] **6.1** Run `bash apps/web-platform/infra/run-registered-suites.sh` by its own invocation (not a hand-enumerated file list); record the suite count it reports.
- [ ] **6.2** Run the three named suites individually.
- [ ] **6.3** Verify AC11's three greps return 0 (`.tf` diff, new `TF_VAR_*`, `web-git-data-probe` files).
- [ ] **6.4** Verify AC13's citation grep prints nothing (excluding the documented `spec.md` absence).
- [ ] **6.5** File the deferral tracking issues: (a) the `if ! cryptsetup isLuks` 126/127-swallowing hole; (b) project-quota enforcement, if deferred by the Phase-0 choice; (c) the emitter's 180-byte detail cap, if it still bites.
- [ ] **6.6** PR body uses **`Ref #7204`**, not `Closes` — the issue closes when a rehearsal passes against the corrected template, which is a separate operator dispatch.
- [ ] **6.7** PR body carries the exact rehearsal dispatch command and the PASS/FAIL/TRANSIENT semantics, plus an explicit statement that the rehearsal was **not** re-dispatched and that doing so spends a paid host.
- [ ] **6.8** **STOP.** Do not dispatch the rehearsal. Do not dispatch the birth.
