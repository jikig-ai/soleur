# Tasks — fix(#6536) inngest-heartbeat.service exits non-zero every 60s

Plan: `knowledge-base/project/plans/2026-07-16-fix-6536-inngest-heartbeat-exit-code-plan.md`
Lane: `cross-domain` · Threshold: `single-user incident` · Issue: #6536

> **BLOCKER — do not start Phase 2 until this clears.**
> `plan-review` did NOT complete (6/7 reviewers died on API errors; only `cto` returned) and
> `requires_cpo_signoff: true` is **unmet**. Re-run in **small batches (2-3 agents)**, never
> 7-way parallel. Deepen-plan settled the delivery split and the flip enum (below) — those two
> blockers are CLEARED.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-run `plan-review` in small batches (2-3 agents); fold findings in.
- [ ] 0.2 Obtain CPO sign-off (threshold = single-user incident) via `user-impact-reviewer`.
- [x] 0.3 **Delivery split — SETTLED (deepen-plan).** v2's split was FALSE. `cloud-init-inngest.yml:337`
      pins `IREF=…/soleur-inngest-bootstrap:v1.1.19`; **both** `inngest-bootstrap.sh` **and**
      `vector.toml` are docker-cp'd from that image at boot (`:368`, `:370`). So **FR5 is replace-class
      too**, not replace-free. The replace trigger is the **`IREF` bump** (`user_data` via
      `inngest-host.tf:200`, no `ignore_changes` at `:244`) — not the bootstrap edit itself.
      **Decision: ONE PR.** Splitting buys nothing: FR3/FR4/FR5 share one image and one bump.
- [x] 0.4 **Flip-state enum (AC5b) — SETTLED (deepen-plan).** v2's enum was incomplete: it missed
      **`flushed`**, **`aborted`**, **`rolled-back`**. Authoritative FSM is
      `armed → flipping → flushed → done` (`cutover-inngest.yml:764`); G1's arms are
      `""|unset|aborted|rolled-back` (`:703`) vs `armed/flipping/flushed/done` (`:706`);
      `op=rollback` writes transitional `rollback` (`:668`). Rule = **"is this host the intended
      pusher?"** — evaluated as **project FIRST, then flip** (CPO P1-1): `DOPPLER_PROJECT != soleur-inngest`
      (the live co-located host, which has no flip by design) → **exit 1** unconditionally; else exit 0 for
      `""|unset|aborted|rollback|rolled-back`; exit 1 for `armed|flipping|flushed|done`; `*)`
      **fails closed** → exit 1. Use a `case`, mirroring `:703`/`:706`. **Never `= "armed"`.**
      Full 10-row table + prescribed shape in plan §AC5b.
- [x] 0.5 **`INNGEST_CUTOVER_FLIP` env injection — SETTLED (deepen-plan).** The unit's ExecStart is
      `doppler run --project soleur-inngest --config prd -- $HEARTBEAT_SCRIPT`
      (`inngest-bootstrap.sh:193`); `doppler run` injects **every** secret in the config into the
      child env. That is the identical mechanism carrying `INNGEST_HEARTBEAT_URL` today, so the
      discriminator works by construction. Key absent today ⇒ not injected ⇒ `${…:-unset}` ⇒
      `unset` ⇒ dark arm ⇒ exit 0. Correct. Re-assert as a test, not an assumption (1.9).
- [ ] 0.6 File tracking issues for the items in §Descoped (now **9**). Priority order:
      **#7 (live shipper != repo vector.toml — file FIRST)**, #4 (op=rollback leaves the URL →
      two pushers), #5 (stale `:416` FSM comment), #8 (heartbeat proves host, not scheduler).
- [ ] 0.7 **AC15 ordering gate — BOTH keys** (CPO P1-3). Assert `INNGEST_HEARTBEAT_URL` **and**
      `INNGEST_CUTOVER_FLIP` are absent from `soleur-inngest/prd` at apply time
      (`doppler secrets --only-names -p soleur-inngest -c prd`). The URL is the **primary**
      trip-wire — `op=arm` writes it FIRST (G4 `:759`) and the flip LAST (G5 `:669`), so a failed
      arm leaves URL-present/flip-absent **durably**, a state v2's flip-only gate passed. Both
      absent → proceed. URL present + flip absent → **HALT** (failed/partial arm). Flip present →
      **HALT**.

## Phase 1 — Observability first (the discriminating probe)

Ships BEFORE the fix so the next fire self-reports which defect was live.

- [ ] 1.1 RED: test asserting the heartbeat unit heredoc contains `SyslogIdentifier=inngest-heartbeat`
      (`cloud-init-inngest-bootstrap.test.sh`).
- [ ] 1.2 GREEN: add `SyslogIdentifier=inngest-heartbeat` to the unit (`inngest-bootstrap.sh:178-194`).
      Retags doppler's AND curl's stderr (today systemd derives the tag from the ExecStart basename
      → `doppler`).
- [ ] 1.3 RED: test asserting the ping script emits one structured pre-exec line carrying
      `project=` + `url_present=` + `flip=` **together**. NOTE (obs P1-1): this row does **NOT**
      discriminate H4 — it runs inside `doppler run`'s child, so a Doppler-class failure emits
      ZERO rows. `project=` is a branch-recording field (FR3 gates on it), not an H4 probe. The H4
      signature is *no row + unit `failed`*, readable only because FR4 retags the unit's stderr.
      Do not re-add `resolved=`.
- [ ] 1.4 GREEN: emit it via `logger -t "$LOG_TAG"` with `LOG_TAG="inngest-heartbeat"` as a real
      assignment in the ping script — **NOT** a bare `logger -t inngest-heartbeat` literal. The
      drift fixture (`vector-pii-scrub.test.sh:404`) derives EXPECTED_TAGS from
      `^\s*(readonly\s+)?LOG_TAG="…"` in `infra/*.sh`; a literal pulls the file into the loop
      (grep is heredoc-blind), yields NO tag, and hard-fails AC3's set-equality — taking AC7/AC9
      with it (obs P1-2). Do NOT "fix" that by appending to `SYSTEMD_UNIT_IDENTIFIERS` — `:412`
      forbids it (*"not a drift-guard bypass"*). **Presence booleans only — NEVER the URL value.**
- [ ] 1.5 RED: leak gate (AC3) — **value-based, not source-grep** (CPO P1-2). Run the ping script
      with `INNGEST_HEARTBEAT_URL=https://uptime.betterstack.com/api/v1/heartbeat/CANARY_SENTINEL`,
      capture stdout+stderr+logger output, assert `CANARY_SENTINEL` appears **zero** times. v2's
      regex caught 1 of 3 shapes and missed `${…}` brace form — this plan's own house style.
- [ ] 1.6 GREEN: add `"inngest-heartbeat"` to `vector.toml`
      `[sources.host_scripts_journald].include_matches.SYSLOG_IDENTIFIER` with a `#6536` comment.
      **Source 4 only** — Source 1's `PRIORITY 0-4` cut drops the unit's PRIORITY-6 output.
      Assert block scoping with the flag-based `awk` form, **not** an `/a/,/b/` range (AC2).
- [ ] 1.7 Extend `vector-pii-scrub.test.sh` for the new tag + the URL-never-shipped assertion.
- [ ] 1.8 `cat-deploy-state.sh:344` — add `service_journal_tail inngest-heartbeat.service`
      (+ assertion in `cat-deploy-state.test.sh`).
- [ ] 1.9 RED/GREEN: assert the unit's ExecStart wraps the script in `doppler run --project` so the
      flip/URL env injection path (0.5) cannot silently regress.

## Phase 2 — Fix the sole live defect (H5)

- [ ] 2.1 RED: table-driven test over **all ten** cases from 0.4. **Project gate FIRST**:
      `DOPPLER_PROJECT=soleur` + URL absent → **exit 1** (the live co-located pusher; CPO P1-1).
      Then, for `DOPPLER_PROJECT=soleur-inngest`: exit **0** for `""`, `unset`, `aborted`,
      `rollback`, `rolled-back`; exit **1** for `armed`, `flipping`, `flushed`, `done`; exit **1**
      for an unknown value (fail-closed `*)` arm).
- [ ] 2.2 GREEN: implement the `case` branch in the ping script (`inngest-bootstrap.sh:160-164`)
      exactly as prescribed in plan §Phase 3 / §AC5b. Keep `exec curl` on the happy path.
- [ ] 2.3 Verify the branch under `sh` (not bash) with the var **unset** — the script is `#!/bin/sh`.
      `${INNGEST_CUTOVER_FLIP:-unset}` must not trip `set -u` if it is ever added.

## Phase 3 — Correct the record

- [ ] 3.1 `inngest-host.tf:137-151` — replace the false *"the dark host's heartbeat curl no-ops"*
      claim with the measured truth (`curl -fsS --max-time 10 ""` → **rc=2**); state that the no-op
      is implemented explicitly in the ping script. Cite #6536.
- [ ] 3.2 RED/GREEN: guard in `inngest-host.test.sh` so the false claim cannot return (AC6).

## Phase 4 — Delivery (replace-class — see plan §Downtime & Cutover)

- [ ] 4.1 Bump `IREF` at `cloud-init-inngest.yml:337` to the new `soleur-inngest-bootstrap` tag —
      this is the `user_data` diff that actually delivers FR3/FR4/FR5. Confirm the image-publish
      workflow produced the tag BEFORE the bump (a bump to a non-existent tag bricks cold boot).
- [ ] 4.2 `terraform plan` shows **exactly one** `hcloud_server` replace + volume re-attach, and
      **no** co-located resource in the diff (AC10). Re-assert 0.7 immediately before apply.

## Phase 5 — Exit gate

- [ ] 5.1 `bash -n` every touched shell script.
- [ ] 5.2 Run: `cloud-init-inngest-bootstrap.test.sh`, `inngest-host.test.sh`,
      `cat-deploy-state.test.sh`, `vector-pii-scrub.test.sh`.
- [ ] 5.3 `validate-vector-config.yml` gate green.
- [ ] 5.4 Full infra suite (orphan suites only surface here).
- [ ] 5.5 PR body: `Closes #6536`.
