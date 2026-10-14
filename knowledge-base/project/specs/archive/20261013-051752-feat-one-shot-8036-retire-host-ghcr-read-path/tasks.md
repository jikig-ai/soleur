# Tasks — retire the host-side GHCR read path (#8036 item 1c)

Derived from `knowledge-base/project/plans/2026-09-23-fix-retire-host-ghcr-read-path-plan.md`
(post-review). Lane: `cross-domain` (no spec.md — TR2 fail-closed).

Ordering is load-bearing in one place only: **2.x precedes 3.x** (contract before consumers). The
earlier "narrow the consumers first" constraint was cut at review — the emitter has been structurally
dark since #7071, so there is no window to protect.

## Phase 1 — RED (write the failing tests first)

- [x] 1.1 `T-1c-1` residual-zero: zero `_docker_login_capture ghcr.io` call sites, no
      `refetch_ghcr_and_relogin` definition. Measured baseline to drive to zero: **2** and **1**.
- [x] 1.2 `T-1c-2` the sweep clears `ghcr.io` from `$DEPLOY_DOCKER_CONFIG_FILE`, leaves the zot entry
      equal as a JSON value (`jq -S`, never a byte compare), preserves mode 0600, and a second deploy
      changes no mtime.
- [x] 1.3 `T-1c-4` the marker reads `deploy_ghcr_auth=none swept=yes`, then `swept=no` on a clean
      second deploy.
- [x] 1.4 `T-1c-5` the SENTRY_* Doppler refresh still runs and still precedes `zot_gate_and_login`.
- [x] 1.5 `T-1c-6` `ZOT_ACTIVE=0` with no local-cache candidate → `image_pull_failed`, zero
      `docker pull` against any `ghcr.io/` ref, previous container still running.
- [x] 1.6 `T-1c-7` (**P7**) the transient retry fires on the **zot** arm; the empty-value break-glass
      disable lever still works.
- [x] 1.7 `T-1c-8` harness must-PASS: `auths` without a `ghcr.io` key, and no `auths` key at all.
- [x] 1.8 `T-1c-9` harness must-RED: stub the sweep to a no-op.
- [x] 1.9 `T-1c-13` every pull-path emitter names the ref actually pulled, never the global `IMAGE`.
- [x] 1.10 `T-1c-14` the FR-C1 breadcrumb survives, reports the final attempt's stderr, drops
      `falling back to GHCR`, stays single-line and ≤400 bytes.
- [x] 1.11 `T-1c-16` zero `secrets get GHCR_READ_USER` / `GHCR_READ_TOKEN` calls in the doppler trace.
- [x] 1.12 Prove every row RED on `origin/main`'s `ci-deploy.sh` before any deletion.
- [x] 1.13 Do NOT author rows for `_try_local_cache_reload` — the `#6512` block already covers all
      three arms and that function is not edited here.

## Phase 2 — script surgery (`apps/web-platform/infra/ci-deploy.sh`)

- [x] 2.1 Delete `refetch_ghcr_and_relogin()`.
- [x] 2.2 Split `ghcr_prelude_and_login()` into `prefetch_deploy_secrets`,
      `sweep_stale_registry_auth`, `emit_registry_config_marker`; hoist the ordering to the one call
      site with a comment naming BOTH orderings (before the marker, before `zot_gate_and_login`).
- [x] 2.3 Rewrite the `elif [[ -z "$ghcr_user" || -z "$ghcr_token" ]]` arm — deleting the locals
      without it aborts the deploy under `set -u`.
- [x] 2.4 Implement `sweep_stale_registry_auth` via `docker logout ghcr.io`: deploy config only,
      symlink-refusing, `jq` predicate matching the marker's, `SWEPT_STATE` out-parameter.
- [x] 2.5 Add the `swept=yes|no|na` token to the marker; name `root_ghcr_auth=inline` as
      expected-and-out-of-scope in the in-code comment, citing the 1d issue.
- [x] 2.6 Delete `_ghcr_pull_or_recover`'s auth arm; rename to `_pull_with_transient_retry`; add a ref
      parameter.
- [x] 2.7 `pull_image_with_fallback`: delete both GHCR arms and the stale `RETIREMENT TRIPWIRE`
      comment; route the zot arm through the retry helper; preserve and relocate the FR-C1 breadcrumb.
- [x] 2.8 Fix the four wrong-ref emit sites (two `docker pull`, `pull_auth_recovery_event`,
      `pull_failure_event` on both the `ZOT_ACTIVE=1` and `ZOT_ACTIVE=0` arms).
- [x] 2.9 Do NOT rename `GHCR_DOCKER_CONFIG` — fix its misleading header comment instead.
- [x] 2.10 Keep every shared helper (`_docker_login_capture`, `_login_hatch`, `_pull_result_is_*`,
      `pull_auth_recovery_event`, `registry_pull_event`, `_try_local_cache_reload`).
- [x] 2.11 Rewrite the GHCR arms of `apps/web-platform/infra/ci-deploy.test.sh`; delete the
      `refetch_ghcr_and_relogin` awk extraction outright.

## Phase 3 — consumer reconciliation

- [x] 3.1 `sentry-zot-mirror-fallback-alert-op-contract.test.ts` — three `ghcr-fallback` expectations
      **plus** `expect(alarm.size).toBe(5)` and `expect(soakFailQueries().size).toBe(5)` → 4.
- [x] 3.2 `soleur-host-bootstrap-observability.test.sh` — AC20 clause (3) and the positional
      `_doppler_get_or_report` greps; keep clauses (1) and (2).
- [x] 3.3 `zot-soak-6122.sh` — drop `FAIL_QUERIES[rolling]` **and** move the floor `!= 5` → `!= 4`.
- [x] 3.4 `zot-soak-6122.test.sh` — the 4 `ghcr-fallback=` fixture lines; floor row asserts 4.
- [x] 3.5 `tests/scripts/test-sentry-alert-live-fidelity.sh` — positional `[0]`/`[2]` → key lookup.
- [x] 3.6 `sentry/issue-alerts.tf` — drop the one `ghcr-fallback` condition; keep the other four; do
      not touch its `lifecycle`.
- [x] 3.7 `sentry/alert-reference.json` — regenerate.
- [x] 3.8 `scheduled-zot-restart-loop.yml` — rewrite the `--grep ghcr-fallback` remediation text.
- [x] 3.9 `variables.tf` — `ghcr_read_token` description; name the 1d divergence.
- [x] 3.10 `cloud-init.yml` (2 comments) + `cloud-init-ghcr-seed-login.test.sh` (1 comment) +
      `registry-replace-preflight.sh` (1 comment) — name-anchored citations only.
- [x] 3.11 `zot-registry-revert.md` — the five-signal list.
- [x] 3.12 `zot-login-gate-erofs-repaired-6565.sh` — drop the dead `PRELUDE: docker login ghcr.io ok`
      disjunct; note the probe is now one-legged.
- [x] 3.13 `zot-login-gate-names-failure-6497.sh` — correct its 3-state taxonomy.
- [x] 3.14 Retire `deploy-ghcr-pull-recovery-6400.sh`; add one line to the 2026-07-14 post-mortem that
      cites it by path.

## Phase 4 — architecture record (deliverables of THIS PR)

- [x] 4.1 ADR-096 — split 5.3 into 5.3a/5.3b; record the FAIL verdict as standing and un-consumed;
      add the "wait for the soak" alternative row; cross-reference rather than restate.
- [x] 4.2 ADR-087 — move the header's zot note into `## Decision`; keep the inline-not-`credStore`
      requirement verbatim (spell it as the file does).
- [x] 4.3 ADR-169 — one line under Named residual 3.
- [x] 4.4 `model.c4` — DELETE the `hetzner -> ghcr` DEAD EDGE; amend `hetzner -> zotRegistry`; amend
      the `//` comment carrying "hosts read GHCR_READ_TOKEN unchanged" (a comment, not an edge). Do
      NOT touch the cosign-verifier edge.
- [x] 4.5 Run `c4-count-parity.test.sh` (assert the entry count moved), `c4-code-syntax.test.ts`,
      `c4-render.test.ts`.

## Phase 5 — close criterion

- [x] 5.1 Write `scripts/followthroughs/ghcr-read-retired-8036.sh` by repurposing the retired
      `deploy-ghcr-pull-recovery-6400.sh`; grade the three-leg conjunction; `--explain` prints
      `PROBE-READY` with no network; state that `na` fails closed and that `jq` is a hard dependency.
- [x] 5.2 Write its `.test.sh` with Guard 3's four rows.
- [ ] 5.3 Enrol on #8036: `follow-through` label, directive with `earliest=<apply completion + ~30m>`
      and the three already-wired `BETTERSTACK_QUERY_*` secrets.
- [x] 5.4 Run the follow-through family's own gates (exec-bit, predicate-parity, varq-ban,
      ship-followthrough-directive, ship-soak-followthrough-enrollment-gate).

## Phase 6 — ship

- [ ] 6.1 PR body's FIRST line answers "does merging this alone mutate production?" — **yes**, both
      apply workflows fire on merge.
- [ ] 6.2 `Closes #7295`; **`Ref #8036`**, never `Closes`.
- [ ] 6.3 Comment on #6565, #6630 and #6400's tracker; file the 1d issue and the follow-through-lib
      debt issue, both with milestone `Phase 4: Validate + Scale`.
- [ ] 6.4 Render `decision-challenges.md` (DC-1, DC-2) into the PR body and file the
      `action-required` issue.
- [x] 6.5 Post-merge re-pin: **NOT APPLICABLE to this change**, established by measurement rather
      than performed as a no-op. The frozen-rule pin covers only `.tf` blocks carrying
      `legacy_trigger_conditions` under `ignore_changes = all` -- rules terraform NEVER writes.
      That set is `auth_per_user_loop` and `sandbox_startup_failure`. `zot_mirror_fallback_rate`
      carries only `ignore_changes = [environment]` and terraform planned it as *updated
      in-place*, so it is MANAGED and is checked against `alert-reference.json`, which `plan_pr`
      verified (`sentry alert reference gate: PASS (30 rules, plan == alert-reference.json)`).
      Being present in the 2026-09-09 capture is NOT the same as being in the frozen set -- the
      task's wording elides that, and taking it at face value would have meant a needless
      live-credentialed write against production Sentry.
      Confirmed live, not just by reading the tf: dispatched `scheduled-sentry-alert-drift.yml`
      (run 35904015947) after the apply landed the narrowed rule -> **success**.

## Phase 7 — #8600 review round (10-seat panel, all seats BLOCKING)

- [x] 7.1 `sweep_stale_registry_auth`: sweep all three ghcr.io carriers (`auths`, `credHelpers`,
      helper-held secret), verify the post-state before reporting `swept=yes`, and split the
      refusal token (`na_nojq` / `na_absent` / `na_symlink` / `na_notfile` / `na_readonly`,
      plus `failed`). Measured: `docker logout` alone leaves a helper-shaped config byte-identical.
- [x] 7.2 Make the `docker logout` test double model the REAL verb (auths-only, and a no-op when a
      helper is in play) so `T-1c-2` grades the sweep instead of the fixture.
- [x] 7.3 Probe leg 1: grade `deploy_ghcr_helper` too, accept `deploy_cfg=absent` as clean, refuse
      the `na_*` and `failed` tokens.
- [x] 7.4 Probe leg 2: count `relogin_failed` only NEWER than the host's latest marker (the latch
      made #8036 permanently unclosable on any host that saw one pre-1c deploy in the window).
- [x] 7.5 Probe leg 3: closed allowlist (`ok` only -- see LEG3_ALLOW_RE); `cosign_absent`,
      `wrong_identity`, `unsigned` and a missing verdict are ACTION REQUIRED, not PASS.
- [x] 7.6 Probe: saturation guard — an absence verdict over a truncated window is not evidence.
- [x] 7.7 Probe suite 19 -> 28 rows; `MIN_CHECKS` raised to 28 in the same edit and mutation-proven.
- [x] 7.8 `T-1c-17`/`T-1c-18`: the central deletion gets a RUNTIME guard (zero `ghcr.io` logins,
      with the zot login as denominator). The login mock now records the registry.
- [x] 7.9 `T-1c-19`: no emitted operator-facing line may claim a GHCR path or a second registry.
- [x] 7.10 `T-1c-20`: `pull_failure_event` EMITS `zot_gate_status` (journald field + Sentry tag).
      It previously used its detail argument only to classify, then discarded it.
- [x] 7.11 Emit a degraded reason on EVERY dark return, including the arm with `ZOT_REGISTRY_URL`
      set, which was silent and is now terminal.
- [x] 7.12 Split `no_credential_source` into `no_doppler_binary` / `no_doppler_token`.
- [x] 7.13 Narrow `registry_pull_event` to `{zot, local-cache}`; drop the unreachable
      `ghcr-fallback` level arm and correct its docstring.
- [x] 7.14 Rewrite the stale docblocks: `pull_image_with_fallback`, `zot_gate_and_login`,
      `_try_local_cache_reload`, both call sites, and the `GHCR path` logger literals.
- [x] 7.15 Runbook: re-arm condition needs a CODE change not a credential; Effect bullet says
      terminal; delete the SSH-gated blessed use; record the one-way sweep; bump `last_reviewed`.
- [x] 7.16 `scheduled-zot-restart-loop.yml`: the filed issue said deploys still succeed, three
      lines above a Remediation paragraph saying the opposite.
- [x] 7.17 ADR-096: repair the markdown lazy continuation that re-attributed ~10 lines of dated
      §5.3 text (including "Do NOT retire the alarm at 5.3") to the 2026-09-23 amendment.
- [x] 7.18 ADR-087: restore the deleted dated 2026-07-06 note verbatim under a `Superseded` marker
      instead of replacing it with a paraphrase.
- [x] 7.19 ADR-169 + code: qualify "the ONLY tier" — local-cache rescues same-version `web` only,
      so inngest and every new-version deploy have zero tiers.
- [x] 7.20 ADR-088 + ADR-096 body: amend the passages still naming `ci-deploy.sh` /
      `_ghcr_pull_or_recover` as live GHCR-read consumers.
- [x] 7.21 `registry-pull-path-health.sh`: amend the dark-operand paragraph its sibling preflight
      already carries, so the two D10 gates do not disagree about whether the emitter exists.
- [x] 7.22 `issue-alerts.tf`: amend the `local_cache_reload_rate` rationale, which asserted the
      claim this PR retires 500 lines below it in the same file.
- [x] 7.23 `variables.tf`: enumerate all THREE fresh-boot login sites, not one.
- [x] 7.24 Sibling probes (6565, 6497): discard query stderr instead of merging it into a public
      issue comment; cap machine ids at 12 hex; field-isolate on `SYSLOG_IDENTIFIER`.
- [x] 7.25 Plan: delete the drifted verbatim copy of `sweep_stale_registry_auth`; re-point the
      `failure_modes` detection at the probe that carries the leg; fix the self-contradicting
      rollback paragraph.
- [x] 7.26 `decision-challenges.md` DC-W6: record that the stated `ZOT_GATE_STATUS` repayment did
      not exist as written, and what it is now.
- [x] 7.27 CI: neutralize two resolvable home-docker-config path literals (the `~/.docker/`
      directory-only form is what the gate accepts); move the
      `cloud-init.yml` prose to `server.tf` to get back under the gzip budget without raising it.
- [x] 7.28 DONE 2026-09-23: struck the `soleur:followthrough` directive from
      #6400's body, which still names the deleted `deploy-ghcr-pull-recovery-6400.sh`.
      **Severity corrected by measurement.** The review panel reported this as a post-merge
      breakage — the sweeper hitting `script missing in repo HEAD` and failing indefinitely. It
      does not: #6400 is CLOSED and was closed 63 days ago, the open-set query is `--state open`,
      and the closed-set query is `closed:>=now-CLOSED_LOOKBACK_DAYS` with the default 14 — so
      #6400 is not selected by either and the directive is inert. (`fail()` is also an stderr
      print, not the run's `exit 1`.) Worth striking anyway: a reopen, or a raised
      `CLOSED_LOOKBACK_DAYS`, would make a dangling script path live. No repo-local gate can see
      it, because the reference is in a GitHub issue body.
      Applied by indenting the directive one space so it no longer matches the sweeper's
      column-0 anchor (`/^<!-- *soleur:followthrough/`), with a note above it saying why. The
      record of what was enrolled is preserved rather than deleted.
