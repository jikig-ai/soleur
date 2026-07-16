# Tasks — fix(#6536) inngest-heartbeat.service exits non-zero every 60s

Plan: `knowledge-base/project/plans/2026-07-16-fix-6536-inngest-heartbeat-exit-code-plan.md`
Lane: `cross-domain` · Threshold: `single-user incident` · Issue: #6536

> **BLOCKER — do not start Phase 2 until this clears.**
> `plan-review` did NOT complete (6/7 reviewers died on API errors; only `cto` returned) and
> `requires_cpo_signoff: true` is **unmet**. Re-run in **small batches (2-3 agents)**, never
> 7-way parallel. Deepen-plan settled the delivery split and the flip enum (below) — those two
> blockers are CLEARED.
>
> **UPDATE — CPO SIGN-OFF GRANTED** (2026-07-16) after both P1 rounds landed, conditional on
> FR4c + the Risks rewrite, both now applied. 0.2 is CLEARED. 0.1 remains: the wider panel
> (dhh / kieran / code-simplicity / architecture-strategist / spec-flow-analyzer) never ran.

## Phase 0 — Preconditions

- [x] 0.1 **Panel run** (small batches — the 7-way spawn is what died): `cto`, `user-impact-reviewer`
      (CPO, 2 rounds), `observability-coverage-reviewer`, `code-simplicity-reviewer`,
      `architecture-strategist`. **v5 folds in the last two, which independently refuted the
      premise that justified ~60% of v4.**
- [x] 0.2 **CPO sign-off — GRANTED** (conditions applied, then FR4c superseded by v5's render split,
      which removes the hazard structurally rather than gating it — strictly stronger than the
      design signed off).
- [x] 0.3 **Delivery — SETTLED + BLOCKER FIXED (arch F1).** `IREF` bump (`cloud-init-inngest.yml:337`)
      is the `user_data` diff; FR3/FR4/FR5 all ride that one image. **Merging delivers NOTHING**:
      `hcloud_server.inngest` is stripped from per-merge coverage (`apply-web-platform-infra.yml:1401`)
      and the replace is dispatch-only (`:1552`, ADR-100 Amendment 6b). Delivery =
      `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace`, run by
      **the pipeline, not the operator**.
- [x] 0.4 **Flip enum — CUT (v5).** No FSM in the ping script. URL-presence is sufficient (`op=arm`
      writes the URL before `armed`). ADR-100 / `inngest-cutover-flip.sh:214` owns the FSM;
      `inngest-bootstrap.sh:416` is already a stale copy #2. Don't add copy #3.
- [x] 0.5 **FR4c — CUT (v5).** `DOPPLER_PROJECT` is a Doppler **reserved/computed** secret derived
      from `--project` (measured across 3 configs + a live `doppler run` probe). The drift class
      FR4c removed does not exist.
- [x] 0.6 **Image baseline — MEASURED (arch F6).** `IREF` tag → `sha256:61bcdff0…`. The image is NOT
      the commit: its `vector.toml` lacks `"webhook"` (#6315) and hardcodes `host_name` (#6396);
      its bootstrap is 19 lines behind. **The replace ships all of that too** — enumerate it in the
      PR body. Lockstep OK: repo bootstrap renders `@@HOST_NAME@@` (`:609`) ↔ repo `vector.toml`
      has the sentinel.
- [ ] 0.7 **AC15 ordering gate — BOTH keys** (CPO P1-3). Assert `INNGEST_HEARTBEAT_URL` **and**
      `INNGEST_CUTOVER_FLIP` absent from `soleur-inngest/prd` at apply time. URL is the **primary**
      trip-wire (`op=arm` writes it FIRST, G4 `:759`; flip LAST, G5 `:669`), so a failed arm leaves
      URL-present/flip-absent **durably** — a state a flip-only gate passes. Both absent → proceed.
      URL present + flip absent → **HALT**. Flip present → **HALT**.
- [ ] 0.8 File the 7 §Descoped issues — **alongside, not blocking**. `#5` (live shipper ≠ repo
      `vector.toml`) **first**: it is the highest-signal finding here and outranks #6536 itself.

## Phase 1 — Observability (verification infrastructure for AC12)

*(v5: dropped the "probe ships BEFORE the fix" ordering. It was fiction — FR3/FR4/FR5 ride one
image, one bump, one replace, so no fire occurs between them. And there is nothing left to
discriminate: H5 is confirmed, H4 refuted+descoped, and the probe cannot see H4 anyway.)*

- [ ] 1.1 RED: unit heredoc contains `SyslogIdentifier=inngest-heartbeat`.
- [ ] 1.2 GREEN: add it (`inngest-bootstrap.sh:178-194`). **Highest-value line in the PR** — it
      retags doppler's AND curl's stderr onto a shipping channel (today systemd derives the tag
      from the ExecStart basename → `doppler`), and it is what makes the "no row + unit failed"
      signature readable at all.
- [ ] 1.3 GREEN: `LOG_TAG="inngest-heartbeat"` as a **real assignment** in the ping script — NOT a
      bare `logger -t inngest-heartbeat` literal. The drift fixture (`vector-pii-scrub.test.sh:404`)
      derives EXPECTED_TAGS from `^\s*(readonly\s+)?LOG_TAG="…"`; a literal pulls the file into
      the loop (grep is heredoc-blind), yields NO tag, and hard-fails AC3 — taking AC7/AC9 with it.
      Do NOT "fix" that via `SYSTEMD_UNIT_IDENTIFIERS` — `:412` forbids it.
- [ ] 1.4 RED: leak gate (AC3) — **value-based**. Run the script with
      `INNGEST_HEARTBEAT_URL=…/CANARY_SENTINEL`; assert `CANARY_SENTINEL` appears **zero** times in
      stdout+stderr+logger output. (v2's source-grep caught 1 of 3 shapes.)
- [ ] 1.5 GREEN: add `"inngest-heartbeat"` to `vector.toml` Source 4's allowlist with a `#6536`
      comment. **Source 4 only** — Source 1's `PRIORITY 0-4` cut drops PRIORITY-6 output. Scope the
      AC with the flag-based `awk` form, not an `/a/,/b/` range.
- [ ] 1.6 Extend `vector-pii-scrub.test.sh`; `cat-deploy-state.sh:344` + its test (FR7).
- [ ] 1.7 **No success-path log row.** v4 added `url_present=yes … pinging` every 60s on BOTH hosts
      (~2,880/day) to duplicate what the monitor already asserts, against ~5k/day headroom
      (`vector.toml:166-171`, engineered ~20% under 25k after #5110's AC12 FAIL at 2.3x). Cut.

## Phase 2 — The fix (render-time split)

- [ ] 2.1 RED: three cases on the **rendered** artifact — dedicated+URL-absent → exit 0 + one row;
      dedicated+URL-present → `exec curl`; **web render → NO dark arm** (rc=2, loud).
- [ ] 2.2 GREEN: `@@DARK_ARM@@` sentinel in the **quoted** heredoc, substituted by `sed -i` per
      `DOPPLER_PROJECT` — the pattern `:609` (`@@HOST_NAME@@`) and `:405-418`
      (`@@FLIP_GUARD_EXECSTARTPRE@@`) already use. **NEVER unquote the heredoc** (§Sharp Edges: it
      bakes the bearer URL into a 0755 file and AC3 structurally cannot catch it).
- [ ] 2.3 Verify under `sh`, not bash — the script is `#!/bin/sh`.

## Phase 3 — Correct the record

- [ ] 3.1 `inngest-host.tf:137-151` — replace the false *"the dark host's heartbeat curl no-ops"*
      claim with the measured truth (rc=2). Cite #6536. This false comment authorized the bug.
- [ ] 3.2 RED/GREEN: guard in `inngest-host.test.sh` so it cannot return (AC6).
- [ ] 3.3 Fix `inngest-bootstrap.sh:416`'s stale FSM comment **in this PR** (arch rec 6) — one line,
      the correct enum is known, and post-v5 it is the last FSM copy outside the flip script.

## Phase 4 — Delivery (dispatch-gated replace)

- [ ] 4.1 Bump `IREF` (`cloud-init-inngest.yml:337`) to the new tag. Confirm the image-publish
      workflow produced it BEFORE the bump (a bump to a non-existent tag bricks cold boot).
- [ ] 4.2 Enumerate the rides-along drift (0.6) in the PR body.
- [ ] 4.3 Re-assert 0.7, then dispatch `-f apply_target=inngest-host-replace`. Plan must show
      exactly one `hcloud_server.inngest` replace + 2 dependents, `hcloud_volume.inngest_redis`
      **preserved** (AC14).

## Phase 5 — Exit gate

- [ ] 5.1 `bash -n` every touched shell script.
- [ ] 5.2 Run: `cloud-init-inngest-bootstrap.test.sh`, `inngest-host.test.sh`,
      `cat-deploy-state.test.sh`, `vector-pii-scrub.test.sh`, `heartbeat-reprovision-parity.test.ts`,
      `terraform-target-parity.test.ts`.
- [ ] 5.3 `validate-vector-config.yml` green. 5.4 Full infra suite. 5.5 PR body: `Closes #6536`.
