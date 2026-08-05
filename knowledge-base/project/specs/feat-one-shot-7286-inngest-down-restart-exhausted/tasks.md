# Tasks — #7286 inngest-redis crash-loop + dark error channel

Derived from [`knowledge-base/project/plans/2026-08-06-fix-inngest-redis-crash-loop-dark-error-channel-plan.md`](../../plans/2026-08-06-fix-inngest-redis-crash-loop-dark-error-channel-plan.md).

`lane: cross-domain` (no spec.md on this branch — TR2 fail-closed default).

**Read the plan's § Deepen-Pass Review Findings before starting.** Several instructions here reverse what an earlier draft said; the reversals are deliberate and evidence-backed.

---

## Phase 0 — Preconditions (PR-1)

- [ ] 0.1 `GET /hooks/deploy-status`; assert `.host_id == "hetzner-123931471"` **first**, then confirm `services.inngest_server != "active"` and the tail still shows the Redis refusal. If self-healed → re-scope per plan Phase 0.1.
- [ ] 0.2 Read `infra-config-apply.sh` (`FILE_MAP`, `RESTART_MAP`, the #4804 note at `:396-404`), `infra-config-install.sh` (`DEST_SPEC`, shape gate `:248-250`), `hooks.json.tmpl` (`infra-config` + `deploy-status` hooks).
- [ ] 0.3 Read `cat-deploy-state.sh` in full — `service_status()` `:71`, `service_journal_tail()` `:91`, scrubber `:98-107`, JSON assembly `:460-470`.
- [ ] 0.4 Read `10-inngest-server-doppler-token.conf` and `10-inngest-heartbeat-doppler-token.conf` (the invariant Phase 3.2 enforces is stated in the latter).
- [ ] 0.5 Baseline suites: `cat-deploy-state.test.sh`, `vector-pii-scrub.test.sh`, `infra-config-install.test.sh`, `journald-config.test.sh`.
- [ ] 0.6 Re-derive the ADR ordinal against freshly-fetched `origin/main` (provisional ADR-169).
- [ ] **0.7 BLOCKING PROBE** — `terraform plan -target=terraform_data.deploy_pipeline_fix` under `prd_terraform`. Confirm a clean plan whose graph excludes `doppler_service_account.token_drift`. **If it errors, STOP** — Phase 1 has no delivery path. Record the verdict verbatim.
- [ ] 0.8 Capture the AC2 baseline: `grep -c 'journalctl' apps/web-platform/infra/cat-deploy-state.sh`.

## Phase 1 — Probe + inert-if-unneeded fix (PR-1, ships alone)

### 1.1 Extend `cat-deploy-state.sh`
- [ ] Add `services.inngest_redis` (`service_status`).
- [ ] Add `services.inngest_redis_journal_tail` via the **shared** `service_journal_tail()`.
- [ ] Add `services.inngest_redis_result` — `systemctl show -p Result,ExecMainStatus,ExecMainCode,NRestarts,MemoryPeak,ExecMainStartTimestamp,ActiveEnterTimestamp`. **Drop `--value`; parse `KEY=VALUE` by key** (canonical ordering + blank line for unsupported `MemoryPeak` on systemd < 253).
- [ ] Add `services.inngest_redis_dropin` — **`systemctl show -p DropInPaths,EnvironmentFiles`** (systemd's LOADED view, NOT a filesystem check). Basenames only; never `cat` drop-in content.
- [ ] Add `services.inngest_redis_credfile` — presence + mtime + **byte length only** of `/etc/default/soleur-doppler-token`.
- [ ] Add `services.inngest_redis_datadir` — `/mnt/data/redis` presence + `stat -c '%U:%G %a'` + `df` used-pct. `lstat`-refuse symlinks before any read.
- [ ] Add `services.inngest_redis_binary` — absolute `/usr/bin/redis-server --version` under `timeout 5`; `systemctl is-enabled redis-server || true`.
- [ ] Add `services.inngest_redis_tail_status` — enum `ok|empty|no-journalctl|unit-unknown`.
- [ ] Add `services.vector_config_identity` — sha256 + mtime of `/etc/vector/vector.toml`.
- [ ] **Do NOT add `inngest_redis_secret_len`** (dropped — unobtainable and unsafe; see plan Phase 1.1).
- [ ] **Extend** the shared scrubber sed stage at `:104-105` (must precede the `tr '\n' '|'` at `:106`): `requirepass\s+\S+`, `redis://[^@]*@`, `dp\.(st|sa|pt|ct)\.[A-Za-z0-9._-]+`, `AUTH\s+\S+`, `masterauth\s+\S+`. Do **not** add a second scrubber.
- [ ] Add `"include-command-output-in-response-on-error": true` to the `deploy-status` hook in `hooks.json.tmpl` (`:116-119`).
- [ ] Update `cat-deploy-state.test.sh`: per-key assertions; synthesized-secret scrub test; missing-unit → empty + exit 0; `systemctl`/`redis-server` off `PATH` → exit 0 + valid JSON.

### 1.2 Deliver the drop-in across all SEVEN surfaces
- [ ] Create `apps/web-platform/infra/10-inngest-redis-doppler-token.conf` (`[Service]` + `EnvironmentFile=-/etc/default/soleur-doppler-token`; the `-` is load-bearing).
- [ ] Surface 2 — `push-infra-config.sh` payload key `inngest_redis_doppler_token_conf_b64`.
- [ ] Surface 3 — `hooks.json.tmpl` `pass-file-to-command` entry → `INNGEST_REDIS_DOPPLER_TOKEN_CONF_B64`.
- [ ] Surface 4 — `infra-config-apply.sh` `FILE_MAP` row.
- [ ] Surface 5 — `infra-config-install.sh` `DEST_SPEC` row.
- [ ] Surface 6 — `server.tf` `terraform_data.deploy_pipeline_fix` `triggers_replace` (**the only permitted `.tf` change**).
- [ ] Surface 7 — `apply-deploy-pipeline-fix.yml` `paths:` filter.
- [ ] Add the five-surface parity assertion to `infra-config-apply.test.sh`; **prove it fails** with any one surface removed.
- [ ] Move the two now-stale comments in `infra-config-install.sh` (`:208` "three dests" → four; `:236`/`:243-244` grant-coverage note).
- [ ] **Expect TWO pushes.** Push 1 may report `exit_code=1` with the drop-in `missing_env` — that is #4804 by design, not channel failure. Verify by field (`inngest_redis_dropin`), never by exit code.

### 1.3 Runbook SSH removal (no delivery dependency)
- [ ] Extend `scripts/lint-infra-no-human-steps.py` SSH pattern (`:93`, `:161`) with `\bssh\s+\S*@`; **ship a proof-of-red** (must FAIL on `origin/main`'s runbook).
- [ ] Delete the 7 host-login instructions (lines 84, 89, 93, 184, 260, 338, 378) and the `### Last-resort (host login)` heading at 179. Line 378 heads a 3-line fenced command — remove the whole block.
- [ ] For **each** of the 7, record: the existing webhook verb it maps to, the verb + sudoers grant added here, or an explicit retirement rationale. Three (`:260`, `:338`, `:378-380`) have **no** existing verb (`ci-deploy.sh:2346` accepts `deploy|restart|quiesce|enable`, and `restart` accepts only component `inngest`).

### 1.4 Verify by read-back
- [ ] Dispatch `/hooks/infra-config`; then `GET /hooks/deploy-status`, assert `.host_id`, then assert every new key present and non-placeholder. Delivery ≠ activation — the channel's own success code does not satisfy this.
- [ ] Record the adjudicating payload excerpt in the PR body; resolve the § Hypotheses row.

### 3.2 Class-closing invariant test (ships in PR-1)
- [ ] Assert in `inngest.test.sh` (or nearest registered suite): every unit with `EnvironmentFile=/etc/default/inngest-server` has a matching drop-in across the **full** lockstep (payload key + bridge + `FILE_MAP` + `DEST_SPEC`), not `FILE_MAP` alone.
- [ ] **Prove it fails on `origin/main`** (where `inngest-redis.service` is the violation) before it passes on the branch.

## Phase 1b — Escape hatch (PR-2, only if triggered)
- [ ] Trigger: dropin loaded, credfile fresh, datadir/binary ok, tail **empty**, `Result=exit-code ExecMainStatus=1`.
- [ ] Timebox ≤ one watchdog tick after AC12 passes. Do not re-run the same instrument.
- [ ] Escalate in order: deeper `--output=verbose` tail → `systemd-analyze verify` → one-shot `ExecStartPre` diagnostic wrapper (bootstrap-image release).
- [ ] If still empty: file a loud UNKNOWN, keep the Phase-3 detector, escalate the availability decision explicitly. **Never** reach for a silent SQLite fallback.

## Phase 2 + 4 — Watchdog evidence (PR-2)
- [ ] Fetch `/hooks/deploy-status` on the `inngest_down`/`inngest_unhealthy` path using the secrets the workflow already holds.
- [ ] Embed `host_id`, `services.inngest_server`, `services.inngest_redis`, `_result`, `_dropin` + bounded tails in a `<details>` block.
- [ ] Delete the hard-coded "likely a lost `inngest-redis.service`" sentence.
- [ ] Non-2xx: `-o /tmp/deploy-status-body`, `cat` it, run through `strip_log_injection`, echo into the comment **and** `::error::`. Never fail the workflow on the evidence fetch.
- [ ] Gate the evidence block on the key being **present**, with an explicit fallback string when absent.
- [ ] De-flap `derive_durability_state` in `inngest-inventory.sh`; **pin the emitted `SOLEUR_INNGEST_LIVENESS_VERDICT` token format** — AC16 and the follow-through script both grep it.

## Phase 3 + ADR + C4 (PR-2)
- [ ] Write `ADR-169-inngest-redis-outage-detect-fail-loud.md`, `status: accepted`; record rejected alternative (b) (runtime SQLite fallback) with its rationale.
- [ ] Correct `model.c4` `inngestRedis` (`:196-198`) — distinguish the LUKS-backed web-1 arm from the plaintext dedicated-host volume.
- [ ] Correct `model.c4` `hetzner -> inngest` (`:486`) — annotate the residual co-located arm; cite #7228/#7230.
- [ ] Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] Re-derive the ADR ordinal immediately before merge; sweep `knowledge-base/project/{plans,specs}/feat-one-shot-7286-*/` if it moves.

## Phase 5 — Runbook, evidence-shaped (PR-3)
- [ ] Add `## inngest-redis down / crash-looping` with the measured signature (postgres OK → `error creating redis client` → `Failed with result 'exit-code'` at 5 s, `NRestarts` climbing, no `failed` latch).
- [ ] First triage step is the no-SSH `/hooks/deploy-status` curl **including the `.host_id` assertion**.
- [ ] Decision table mapping each `inngest_redis_*` field pattern → remedy. **Only document arms Phase 6 actually built.**
- [ ] Correct the #5542 cross-reference; cite #7286.
- [ ] Document the Phase-3 invariant and why there is deliberately no silent SQLite fallback.
- [ ] Re-run the extended `lint-infra-no-human-steps.py` over the new section.

## Phase 6 — Remedy + restore (PR-3)
- [ ] Build **only** the arm Phase 1 named (6.1 H7 / 6.2 H3 / 6.3 H2 / 6.4 H4-H6). Defer 6.5 (AOF) unless Phase 1 names it.
- [ ] 6.6: **zero repo edits** to `vector.toml`, `vector-pii-scrub.test.sh`, `journald-config.test.sh`. If `vector_config_identity` mismatches the repo file → bootstrap-image re-stage only.
- [ ] Capture the **pre**-recovery armed-reminder baseline before any remedy runs.
- [ ] If a bootstrap-image release is needed, cut the tag **in-workflow** — never an operator step.
- [ ] Verify: `host_id` + `inngest_redis == active` + `inngest_server == active` + stable `NRestarts` across two reads ≥60 s apart; `/hooks/inngest-liveness` 200 with `functions >= 68` **and** `host_id`; one function **executes** end-to-end; `durability=durable` across ≥3 ticks; #7286 auto-closes.
- [ ] Post-recovery reminder count **≥** baseline (negative delta FAILS).

## Follow-through
- [ ] Write `scripts/followthroughs/inngest-redis-durable-7286.sh` (exit 0 only when the last 3 verdicts read `mode=healthy durability=durable`, `start=` pinned after the deploy).
- [ ] Add the tracker directive + `follow-through` label; verify `BETTERSTACK_QUERY_*` is already carried by the sweeper.
- [ ] File the `inngest-heartbeat` dark-channel finding as its own issue (plan §Risks 11) — do not absorb it.

## PR hygiene
- [ ] PR body uses `Ref #7286`, **not** `Closes #7286` (remediation is post-merge).
- [ ] Full registered suite green vs the Phase-0.5 baseline.
