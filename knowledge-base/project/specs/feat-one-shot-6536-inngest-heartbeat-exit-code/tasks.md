# Tasks — fix(#6536) inngest-heartbeat.service exits non-zero every 60s

Plan: `knowledge-base/project/plans/2026-07-16-fix-6536-inngest-heartbeat-exit-code-plan.md`
Lane: `cross-domain` · Threshold: `single-user incident` · Issue: #6536

> **BLOCKER — do not start Phase 2 until these clear.**
> 1. `plan-review` did NOT complete (6/7 reviewers died on API errors; only `cto` returned).
>    Re-run it in **small batches (2-3 agents)**, never 7-way parallel.
> 2. `requires_cpo_signoff: true` is **unmet**.
> 3. Deepen-plan must settle the **delivery split** (§Apply path) and the **flip-state enum**
>    (AC5b) before any code is written.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-run `plan-review` in small batches; fold findings in.
- [ ] 0.2 Obtain CPO sign-off (threshold = single-user incident).
- [ ] 0.3 **Settle the delivery split.** FR5/FR6/FR7 need no host replace. FR3/FR4 edit
      `inngest-bootstrap.sh` → `user_data` diff → **replace of the SOLE scheduler**
      (`inngest-host.tf:244`, ADR-100). Decide: one PR or split? Confirm #6178 cutover interaction.
- [ ] 0.4 **Settle the flip-state enum (AC5b).** `inngest-bootstrap.sh:416` names
      `{armed, flipping, done}`; `cutover-inngest.yml` also writes `rollback`; the key is currently
      **absent** on `soleur-inngest/prd`. Classify the correct exit code for EVERY state:
      `unset | armed | flipping | done | rollback`. A bare `= "armed"` test lumps `flipping`/`done`
      into the dark branch → **silent liveness hole**.
- [ ] 0.5 Confirm `INNGEST_CUTOVER_FLIP` is actually injected into the unit's env by
      `doppler run` (it is absent from the config today — if never injected, the FR3 discriminator
      does not work as written and must be redesigned).
- [ ] 0.6 File tracking issues for the 3 items in §Descoped.

## Phase 1 — Observability first (the discriminating probe)

Ships BEFORE the fix so the next fire self-reports which defect was live.

- [ ] 1.1 RED: test asserting the heartbeat unit heredoc contains `SyslogIdentifier=inngest-heartbeat`
      (`cloud-init-inngest-bootstrap.test.sh`).
- [ ] 1.2 GREEN: add `SyslogIdentifier=inngest-heartbeat` to the unit (`inngest-bootstrap.sh:178-194`).
      Retags doppler's AND curl's stderr (today systemd derives the tag from the ExecStart basename
      → `doppler`).
- [ ] 1.3 RED: test asserting the ping script emits one structured pre-exec line carrying
      `project=` + `url_present=` + `flip=` **together** (one row discriminates all hypotheses).
- [ ] 1.4 GREEN: emit it via `logger -t inngest-heartbeat`. **Presence booleans only — NEVER the
      URL value.**
- [ ] 1.5 RED: leak gate (AC3) — assert no `logger`/`echo` of `$INNGEST_HEARTBEAT_URL` anywhere.
- [ ] 1.6 GREEN: add `"inngest-heartbeat"` to `vector.toml`
      `[sources.host_scripts_journald].include_matches.SYSLOG_IDENTIFIER` with a `#6536` comment.
      **Source 4 only** — Source 1's `PRIORITY 0-4` cut drops the unit's PRIORITY-6 output.
- [ ] 1.7 Extend `vector-pii-scrub.test.sh` for the new tag + the URL-never-shipped assertion.
- [ ] 1.8 `cat-deploy-state.sh:344` — add `service_journal_tail inngest-heartbeat.service`
      (+ assertion in `cat-deploy-state.test.sh`).

## Phase 2 — Fix the sole live defect (H5)

- [ ] 2.1 RED: ping script exits **0** when URL absent + flip unarmed; **non-zero** when URL absent
      + flip in a state where this host is the intended pusher. Cover EVERY state from 0.4.
- [ ] 2.2 GREEN: implement the scoped branch in the ping script (`inngest-bootstrap.sh:160-164`).
      Keep `exec curl` on the happy path.
- [ ] 2.3 Verify `[ "$X" = "armed" ]` semantics under `sh` with the var unset.

## Phase 3 — Correct the record

- [ ] 3.1 `inngest-host.tf:137-151` — replace the false *"the dark host's heartbeat curl no-ops"*
      claim with the measured truth (`curl -fsS --max-time 10 ""` → **rc=2**); state that the no-op
      is implemented explicitly in the ping script. Cite #6536.
- [ ] 3.2 RED/GREEN: guard in `inngest-host.test.sh` so the false claim cannot return.

## Phase 4 — Exit gate

- [ ] 4.1 `bash -n` every touched shell script.
- [ ] 4.2 Run: `cloud-init-inngest-bootstrap.test.sh`, `inngest-host.test.sh`,
      `cat-deploy-state.test.sh`, `vector-pii-scrub.test.sh`.
- [ ] 4.3 `validate-vector-config.yml` gate green.
- [ ] 4.4 Full infra suite (orphan suites only surface here).
- [ ] 4.5 PR body: `Closes #6536`.
