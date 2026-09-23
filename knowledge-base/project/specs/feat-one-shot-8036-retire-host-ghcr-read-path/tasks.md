# Tasks — retire the host-side GHCR read path (#8036 item 1c)

Derived from `knowledge-base/project/plans/2026-09-23-fix-retire-host-ghcr-read-path-plan.md`
(post-review). Lane: `cross-domain` (no spec.md — TR2 fail-closed).

Ordering is load-bearing in one place only: **2.x precedes 3.x** (contract before consumers). The
earlier "narrow the consumers first" constraint was cut at review — the emitter has been structurally
dark since #7071, so there is no window to protect.

## Phase 1 — RED (write the failing tests first)

- [ ] 1.1 `T-1c-1` residual-zero: zero `_docker_login_capture ghcr.io` call sites, no
      `refetch_ghcr_and_relogin` definition. Measured baseline to drive to zero: **2** and **1**.
- [ ] 1.2 `T-1c-2` the sweep clears `ghcr.io` from `$DEPLOY_DOCKER_CONFIG_FILE`, leaves the zot entry
      equal as a JSON value (`jq -S`, never a byte compare), preserves mode 0600, and a second deploy
      changes no mtime.
- [ ] 1.3 `T-1c-4` the marker reads `deploy_ghcr_auth=none swept=yes`, then `swept=no` on a clean
      second deploy.
- [ ] 1.4 `T-1c-5` the SENTRY_* Doppler refresh still runs and still precedes `zot_gate_and_login`.
- [ ] 1.5 `T-1c-6` `ZOT_ACTIVE=0` with no local-cache candidate → `image_pull_failed`, zero
      `docker pull` against any `ghcr.io/` ref, previous container still running.
- [ ] 1.6 `T-1c-7` (**P7**) the transient retry fires on the **zot** arm; the empty-value break-glass
      disable lever still works.
- [ ] 1.7 `T-1c-8` harness must-PASS: `auths` without a `ghcr.io` key, and no `auths` key at all.
- [ ] 1.8 `T-1c-9` harness must-RED: stub the sweep to a no-op.
- [ ] 1.9 `T-1c-13` every pull-path emitter names the ref actually pulled, never the global `IMAGE`.
- [ ] 1.10 `T-1c-14` the FR-C1 breadcrumb survives, reports the final attempt's stderr, drops
      `falling back to GHCR`, stays single-line and ≤400 bytes.
- [ ] 1.11 `T-1c-16` zero `secrets get GHCR_READ_USER` / `GHCR_READ_TOKEN` calls in the doppler trace.
- [ ] 1.12 Prove every row RED on `origin/main`'s `ci-deploy.sh` before any deletion.
- [ ] 1.13 Do NOT author rows for `_try_local_cache_reload` — the `#6512` block already covers all
      three arms and that function is not edited here.

## Phase 2 — script surgery (`apps/web-platform/infra/ci-deploy.sh`)

- [ ] 2.1 Delete `refetch_ghcr_and_relogin()`.
- [ ] 2.2 Split `ghcr_prelude_and_login()` into `prefetch_deploy_secrets`,
      `sweep_stale_registry_auth`, `emit_registry_config_marker`; hoist the ordering to the one call
      site with a comment naming BOTH orderings (before the marker, before `zot_gate_and_login`).
- [ ] 2.3 Rewrite the `elif [[ -z "$ghcr_user" || -z "$ghcr_token" ]]` arm — deleting the locals
      without it aborts the deploy under `set -u`.
- [ ] 2.4 Implement `sweep_stale_registry_auth` via `docker logout ghcr.io`: deploy config only,
      symlink-refusing, `jq` predicate matching the marker's, `SWEPT_STATE` out-parameter.
- [ ] 2.5 Add the `swept=yes|no|na` token to the marker; name `root_ghcr_auth=inline` as
      expected-and-out-of-scope in the in-code comment, citing the 1d issue.
- [ ] 2.6 Delete `_ghcr_pull_or_recover`'s auth arm; rename to `_pull_with_transient_retry`; add a ref
      parameter.
- [ ] 2.7 `pull_image_with_fallback`: delete both GHCR arms and the stale `RETIREMENT TRIPWIRE`
      comment; route the zot arm through the retry helper; preserve and relocate the FR-C1 breadcrumb.
- [ ] 2.8 Fix the four wrong-ref emit sites (two `docker pull`, `pull_auth_recovery_event`,
      `pull_failure_event` on both the `ZOT_ACTIVE=1` and `ZOT_ACTIVE=0` arms).
- [ ] 2.9 Do NOT rename `GHCR_DOCKER_CONFIG` — fix its misleading header comment instead.
- [ ] 2.10 Keep every shared helper (`_docker_login_capture`, `_login_hatch`, `_pull_result_is_*`,
      `pull_auth_recovery_event`, `registry_pull_event`, `_try_local_cache_reload`).
- [ ] 2.11 Rewrite the GHCR arms of `apps/web-platform/infra/ci-deploy.test.sh`; delete the
      `refetch_ghcr_and_relogin` awk extraction outright.

## Phase 3 — consumer reconciliation

- [ ] 3.1 `sentry-zot-mirror-fallback-alert-op-contract.test.ts` — three `ghcr-fallback` expectations
      **plus** `expect(alarm.size).toBe(5)` and `expect(soakFailQueries().size).toBe(5)` → 4.
- [ ] 3.2 `soleur-host-bootstrap-observability.test.sh` — AC20 clause (3) and the positional
      `_doppler_get_or_report` greps; keep clauses (1) and (2).
- [ ] 3.3 `zot-soak-6122.sh` — drop `FAIL_QUERIES[rolling]` **and** move the floor `!= 5` → `!= 4`.
- [ ] 3.4 `zot-soak-6122.test.sh` — the 4 `ghcr-fallback=` fixture lines; floor row asserts 4.
- [ ] 3.5 `tests/scripts/test-sentry-alert-live-fidelity.sh` — positional `[0]`/`[2]` → key lookup.
- [ ] 3.6 `sentry/issue-alerts.tf` — drop the one `ghcr-fallback` condition; keep the other four; do
      not touch its `lifecycle`.
- [ ] 3.7 `sentry/alert-reference.json` — regenerate.
- [ ] 3.8 `scheduled-zot-restart-loop.yml` — rewrite the `--grep ghcr-fallback` remediation text.
- [ ] 3.9 `variables.tf` — `ghcr_read_token` description; name the 1d divergence.
- [ ] 3.10 `cloud-init.yml` (2 comments) + `cloud-init-ghcr-seed-login.test.sh` (1 comment) +
      `registry-replace-preflight.sh` (1 comment) — name-anchored citations only.
- [ ] 3.11 `zot-registry-revert.md` — the five-signal list.
- [ ] 3.12 `zot-login-gate-erofs-repaired-6565.sh` — drop the dead `PRELUDE: docker login ghcr.io ok`
      disjunct; note the probe is now one-legged.
- [ ] 3.13 `zot-login-gate-names-failure-6497.sh` — correct its 3-state taxonomy.
- [ ] 3.14 Retire `deploy-ghcr-pull-recovery-6400.sh`; add one line to the 2026-07-14 post-mortem that
      cites it by path.

## Phase 4 — architecture record (deliverables of THIS PR)

- [ ] 4.1 ADR-096 — split 5.3 into 5.3a/5.3b; record the FAIL verdict as standing and un-consumed;
      add the "wait for the soak" alternative row; cross-reference rather than restate.
- [ ] 4.2 ADR-087 — move the header's zot note into `## Decision`; keep the inline-not-`credStore`
      requirement verbatim (spell it as the file does).
- [ ] 4.3 ADR-169 — one line under Named residual 3.
- [ ] 4.4 `model.c4` — DELETE the `hetzner -> ghcr` DEAD EDGE; amend `hetzner -> zotRegistry`; amend
      the `//` comment carrying "hosts read GHCR_READ_TOKEN unchanged" (a comment, not an edge). Do
      NOT touch the cosign-verifier edge.
- [ ] 4.5 Run `c4-count-parity.test.sh` (assert the entry count moved), `c4-code-syntax.test.ts`,
      `c4-render.test.ts`.

## Phase 5 — close criterion

- [ ] 5.1 Write `scripts/followthroughs/ghcr-read-retired-8036.sh` by repurposing the retired
      `deploy-ghcr-pull-recovery-6400.sh`; grade the three-leg conjunction; `--explain` prints
      `PROBE-READY` with no network; state that `na` fails closed and that `jq` is a hard dependency.
- [ ] 5.2 Write its `.test.sh` with Guard 3's four rows.
- [ ] 5.3 Enrol on #8036: `follow-through` label, directive with `earliest=<apply completion + ~30m>`
      and the three already-wired `BETTERSTACK_QUERY_*` secrets.
- [ ] 5.4 Run the follow-through family's own gates (exec-bit, predicate-parity, varq-ban,
      ship-followthrough-directive, ship-soak-followthrough-enrollment-gate).

## Phase 6 — ship

- [ ] 6.1 PR body's FIRST line answers "does merging this alone mutate production?" — **yes**, both
      apply workflows fire on merge.
- [ ] 6.2 `Closes #7295`; **`Ref #8036`**, never `Closes`.
- [ ] 6.3 Comment on #6565, #6630 and #6400's tracker; file the 1d issue and the follow-through-lib
      debt issue, both with milestone `Phase 4: Validate + Scale`.
- [ ] 6.4 Render `decision-challenges.md` (DC-1, DC-2) into the PR body and file the
      `action-required` issue.
- [ ] 6.5 Post-merge: re-pin `scripts/sentry-alert-live-fidelity.sh`'s capture once the apply reads
      back (it cannot be done inside the PR that fires the apply).
