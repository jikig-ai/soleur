# Tasks — feat-one-shot-8743-web2-plugin-mount-fchmodat2

Derived from `knowledge-base/project/plans/2026-10-19-fix-web2-plugin-mount-fchmodat2-plan.md` (issue #8743).

## Phase 1 — Ownership-agnostic plugin-mount seed (root cause)

- 1.1 In `apps/web-platform/infra/ci-deploy.sh`, replace the `docker create` + `docker cp` + `docker rm` seed block with one container-side `docker run --rm -u 0 --entrypoint /bin/sh -v "$PLUGIN_MOUNT_DIR":/plugin-mount -e "SEED_TAG=$TAG" "$VERIFIED_REF" -c '…'` (clear → `cp -a` → `.seed-complete`, all inside the container). Keep `docker rm -f soleur-plugin-seed` pre-clean and `mkdir -p`. Abort path still `final_write_state 1 "plugin_seed_copy_failed"`.
- 1.2 Emit `PLUGIN_SEED_PROBE dst_owner=… marker=… findmnt=…` inside the container BEFORE mutating (journald → Better Stack discriminating probe).
- 1.3 Update stale comments ("shared POSIX form with cloud-init.yml") and the `cloud-init-plugin-seed.test.sh` header (cloud-init-only coverage now).
- 1.4 Update `ci-deploy.test.sh`: trace assertions for the new `docker run` argv; grep-pin that no `docker cp soleur-plugin-seed` survives; `-u 0` + `--entrypoint /bin/sh` + `-v` present; failure path still writes `plugin_seed_copy_failed`.

## Phase 2 — Persist fan-out peers + peer-status merge

- 2.1 `ci-deploy.sh` `write_state`/`final_write_state`: persist `fanout_peers` (effective `SOLEUR_DEPLOY_PEERS` minus self, same filter as `fan_out_to_peers`). Absent on `deploy-peer`-received runs.
- 2.2 `cat-deploy-state.sh`: add `peers_json()` — per peer, `curl --max-time 3` `GET http://<peer>:9000/hooks/deploy-status` HMAC-signed over empty body (shared secret from hooks.json, stdin `--config` — same pattern as `fan_out_to_peers`); emit `peers: {"<ip>": <peer JSON> | {"error":"unreachable|http_<code>|not_json"}}`; merge into the final `jq` block. Fail-open.
- 2.3 `cat-deploy-state.test.sh`: cover peer-ok, peer-failing, unreachable, absent-`fanout_peers`, non-JSON body.

## Phase 3 — Per-host verdict gate in the release run

- 3.1 `.github/workflows/web-platform-release.yml`: add `Verify peer deploy completion` step after `Verify deploy script completion`; poll `deploy.soleur.ai/hooks/deploy-status` on `STATUS_POLL_*` budget; expected peers = `WEB_HOST_PRIVATE_IPS` minus `10.0.1.10`; each peer must reach `exit_code==0 && tag=="v$VERSION"` (tolerate -1/-2/-3/absent while polling; anything else or budget-exhausted → `::error::` + `exit 1`). Fail-closed (CTO ruling 2026-10-19).
- 3.2 Pin the expected-peer derivation in `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` (or a sibling assertion file).

## Phase 4 — PIR, follow-through, recorded architecture

- 4.1 Write PIR `knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md`; file follow-ups as issues.
- 4.2 Create `scripts/followthroughs/web2-plugin-seed-8743.sh` + `.test.sh` (absence of `fchmodat2` rows on soleur-web-2 post-fix + positive control + post-fix seed marker); add the `<!-- soleur:followthrough … -->` directive + `follow-through` label on #8743.
- 4.3 ADR-068 implementation-note amendment (async peer verdict realized by `peers` merge + release gate).
- 4.4 `deploy-status-debugging.md`: `plugin_seed_copy_failed` reason row + `peers`/`ok_peer_fanout_degraded` docs.

## Phase 5 — Verification (post-merge, no-SSH)

- 5.1 After `apply-deploy-pipeline-fix` delivery: confirm `peers["10.0.1.11"].ci_deploy_sha256` matches `origin/main`'s `ci-deploy.sh` sha (via `/hooks/deploy-status`).
- 5.2 Next release: `PLUGIN_SEED_PROBE` row on soleur-web-2; `peers["10.0.1.11"].exit_code==0`; zero new `fchmodat2` rows (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`).
