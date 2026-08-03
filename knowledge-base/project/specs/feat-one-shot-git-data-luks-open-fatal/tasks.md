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
  - [ ] 0.2.5 **[R7-adv]** Probe whether **`project`** is offline-addable via `tune2fs`, not only `quota`. If both are, criterion (b) stops distinguishing `-O project` from plain mkfs and sibling parity becomes the simpler answer.
- [ ] **0.3** Re-fetch `ubuntu-24.04-server-cloudimg-amd64.manifest`; pin the observed `linux-*` package set and the fetch date into the fix's comment block. Confirm `linux-modules-extra-*` absent.
- [ ] **0.4** Write the fix-selection decision into the plan record **before** Phase 1 starts, against the canonical five-candidate table (a)-(e). Criterion (c) is discharged **by construction** (a feature-bit argument), never by a container mount rc — the container's kernel has `quota_v2`, and a `modprobe.d` blacklist inside it does nothing because `request_module` runs in the init namespace.
- [ ] **0.5** Run `/soleur:gdpr-gate` against this plan (trigger (b): `single-user incident` threshold). Advisory only.
- [ ] **0.6** **[R8]** Measure the emitter's detail budget: hand-write a representative detail file (20 dmesg lines + a realistic multi-line mount stderr, and the reverse ordering), run each through the shipped `_clean`, report which bytes survive `tail -n 20 | … | tail -c 180`. This is what Phase 1.4 gates on.
- [ ] **0.7** **[R2]** Decide R2's disposition explicitly: drop / promote rung 1 to privileged / push to rung 2. If "promote", the rung-taxonomy change goes in the Phase 4 ADR.
- [ ] **0.8** **[R2]** Feasibility-check the container shape R1 will actually use (unprivileged `docker run`, `e2fsprogs` installed, `mkfs.ext4` on a regular file, `dumpe2fs -h` on that file).

## Phase 1 — Fix the template

- [ ] **1.1** RED first: write the Phase-2 assertions and watch them fail against the unmodified template (`cq-write-failing-tests-before`).
- [ ] **1.2** Apply the selected `mkfs` change in `apps/web-platform/infra/cloud-init-git-data.yml`.
- [ ] **1.3** Replace the `#6982 W5/R31` comment with the measured mechanism (feature bit → `ext4_enable_quotas` → `find_quota_format` → `ESRCH`), the image fact + fetch date, and what capability was preserved vs deferred.
- [ ] **1.4** **[R8]** Make the whole stage cause-carrying, independently of 1.2:
  - [ ] 1.4.1 Seed a stage detail file at **stage entry** (not at mount time) so `luks_err`'s detail source is always readable. Without this, a non-mount failure makes the emitter fall through to `_san "$DETAIL_SRC"` and ship the **literal path string** as the diagnostic.
  - [ ] 1.4.2 Have every command in the stage append its stderr (`2>>`) to that file. Plain redirect — **not** `exec 2> >(tee …)`; the heredoc's existing comment (`:482-485`) explains why a process substitution under `set -euo pipefail` can hang the boot. Say so in the new comment.
  - [ ] 1.4.3 Write **dmesg first, the failing command's stderr last** — the emitter keeps `tail -n 20` then `tail -c 180`, so the reverse ordering would push the mount error out of the window entirely.
  - [ ] 1.4.4 Put `|| true` on the **`dmesg` capture** (required: `luks_err` runs with `set -euo pipefail` armed, so a failing/SIGPIPE'd `dmesg` would abort the handler before `git-data-emit`). Keep `luks_err`'s existing `… "rc=$rc" || true`. Neither is a violation — the hard constraint is about the **mount**.
  - [ ] 1.4.5 Keep the mount fatal — no `|| true` on it, no fallback mount of the raw device.
- [ ] **1.5** Apply the Phase-0.6 budget result: reorder further, or raise the cap for the **detail-file path only** with the reason in the comment. Do not disturb the redaction ordering.
- [ ] **1.6** **[R9]** Re-run `bash apps/web-platform/infra/git-data-userdata-budget.sh --json`; record `stored` ≤ 32768 and the headroom (baseline `stored=22772`, `headroom=9996`).

## Phase 2 — Regression test that can fail on the unfixed template

> Executable order is **Phase 0 → these assertions (RED) → Phase 1's fix (GREEN) → the remainder**. The numbering is not the order.

- [ ] **2.1** Extend `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — **R1**, the kernel-independent superblock **fingerprint**:
  - [ ] 2.1.1 **[R2]** Extract the `mkfs` line from the template **bytes** (it carries no `${}` interpolation) — do **not** re-render via `git-data-userdata-budget.sh`, which hardcodes its template path and is byte-parity-guarded with three consumers.
  - [ ] 2.1.2 **[R2]** Run it against a **regular file**, unprivileged. No loop device, no `cryptsetup`, no `--privileged`. Add `e2fsprogs` to the container step.
  - [ ] 2.1.3 **[R6]** Read `dumpe2fs -h`; assert the feature set **equals** the fingerprint fixture (equality, not absence-of-known-bad — a one-entry denylist is fail-open against the next module-dependent feature).
  - [ ] 2.1.4 **[R6/R17]** Create `apps/web-platform/infra/git-data-birth-fs-fingerprint.txt` with `source:`, `fetched:` and `expires_on:` lines, derived from the measured-good sibling baseline (`cloud-init-registry.yml:790`, `workspaces-cutover.sh:1042`). R1 fails if `expires_on` has passed.
  - [ ] 2.1.5 **[R3]** Demonstrate fail-on-unfixed **in the same run** by injecting `-O quota` into the extracted line in-test (`assert_mutation` idiom) and asserting R1 rejects it. **Not** `git show <merge-base>:…` — that control inverts the moment this PR merges.
- [ ] **2.2** **[R2]** **R2** — implement the Phase-0.7 disposition (drop / privileged / rung 2). Whichever is chosen, write the reasoning into the test body. Do **not** ship an arm that fails EPERM on both templates.
- [ ] **2.3** **[R4]** **R3**, re-scoped to what the container can observe: the stage detail file is written at stage entry, passed as the emitter's 4th argument, and readable (so the emitter takes its `[ -r … ]` branch, not the `_san` literal fallback). The "carries dmesg" claim is a documented limitation in the body, not an assertion — `dmesg` is EPERM-blocked here.
- [ ] **2.4** Re-aim **B16** in `apps/web-platform/infra/git-data-luks.test.sh` at the post-fix invariant; keep its mutation arms and add one catching a re-introduction of `quota`; rewrite its comment to cite #7204, the measured mechanism, and **[R19]** the AP-018 authority split (R1 authoritative runtime gate; B16 a non-coverage-bearing static pre-filter).
- [ ] **2.5** **[R11]** Raise all three minimum-assertion floors with the arms that made them necessary: `git-data-luks.test.sh:1039` (101), `git-data-runcmd-rehearsal.test.sh:675` (19), `git-data-rung2-rehearsal.test.sh:1345` (65).
- [ ] **2.6** No new suite is created, so no `infra-validation.yml` registration is needed. Do **not** count the "no orphan suite" check as coverage — it is trivially satisfied.

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
- [ ] **6.7** **[R13]** PR body carries the dispatch command and **all three** verdict branches, not just PASS:
  - PASS → merge the evidence file (the workflow already prints the four commands at `git-data-rung2-rehearsal.yml:370-374`).
  - FAIL → **stop.** Read the now-selected `detail` column for the cause; open an issue. Do not re-dispatch.
  - TRANSIENT → **do not simply retry.** #7116 (OPEN) mis-reports TRANSIENT for exactly the early-boot fatals it could read from Sentry; attempt 1 of run 30649892865 was that mis-report. Confirm against Sentry (`host_name:soleur-git-data-rehearsal-<run-id>`, org `jikigai-eu`, project `web-platform`) first; a `level:fatal` row means treat it as FAIL.
  - **Hard cap: two `dry_run=false` dispatches per fix attempt.** Three paid hosts have already been spent on failures.
- [ ] **6.7b** **[R1]** PR body states plainly that merging **does** run `apply-web-platform-infra.yml` (filter `apps/web-platform/infra/**`), why the apply is a no-op for scope reasons, and whether `[skip-web-platform-apply]` was used.
- [ ] **6.8** **STOP.** Do not dispatch the rehearsal. Do not dispatch the birth.
