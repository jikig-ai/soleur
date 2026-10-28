# Tasks — feat-one-shot-11386-cold-run-cache-warm

Plan: `knowledge-base/project/plans/2026-10-28-ci-rls-fuzz-cold-run-cache-budget-plan.md`
Issue: #11386 | PR: #11396

## Phase 1 — Failing tests first (RED)

- 1.1 In `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh`, change `wiring:timeout-30` (~line 262) to `wiring:timeout-45` asserting `timeout-minutes: 45`; update the header comment "timeout 30" → "timeout 45".
- 1.2 Add wiring greps on `supabase-pre-pull-images.sh` for `SUPABASE_ECR_DEAD_AFTER`, the latch-skip marker, and `pigz`/`gzip -1` (fails RED until Phase 2).
- 1.3 Extend the docker stub: pulled-ref registry (`pulled <ref>` lines on pull success) + `pull-tracked` inspect arm answering present iff pulled; new `DOCKER_MODE`s `ecr-throttle-ghcr-ok`, `ecr-flap`, `partial-fail`.
- 1.4 Add behavioral rows: latch trip (ECR pulls == 6, ghcr == 12, one `::warning::ecr latch`), latch reset on deterministic answer (ECR pulls == 7), partial save on failed pull (rc 1, save argv lacks the failed ref), total exhaustion (pulls == 42, rc 1, zero `save` calls). Update `c:exhaust-*` rows for best-effort semantics.
- 1.5 Raise `MIN_ASSERTIONS` to the new exact green count (fill in after GREEN).
- 1.6 Confirm RED: `bash .github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` fails on the new rows.

## Phase 2 — Script + workflow (GREEN)

- 2.1 `.github/scripts/supabase-pre-pull-images.sh`: init `ECR_DEAD_AFTER="${SUPABASE_ECR_DEAD_AFTER:-2}"`, `ecr_consec_throttle=0`, `ecr_dead=0`, `failed=()`, and a `mktemp -d` ECR log dir with owning trap.
- 2.2 Pull loop: when `ecr_dead == 0`, run `bash "$RETRY" docker pull "$ecr" 2>&1 | tee "$ecr_log"` inside `if` (set-e-exempt); success → `docker tag` + reset counter + continue; failure → classify `tail -n 40 "$ecr_log" | grep -qi toomanyrequests`: throttle → increment counter, trip latch (one `::warning::ecr latch`) at `ECR_DEAD_AFTER`; otherwise reset to 0. When `ecr_dead == 1`, skip ECR and print `pre-pull: %s ecr skipped (latch)`.
- 2.3 ghcr fallback: `if ! bash "$RETRY" docker pull "$ghcr"; then failed+=("$img")` + per-image `::warning::`, continue (no set -e abort). Keep `via ghcr` on success.
- 2.4 Post-loop: build `present_refs` via `docker image inspect`; if `SUPABASE_IMG_CACHE_DIR` set and `present_refs` non-empty, `docker save "${present_refs[@]}" | "$Z" > "$CACHE_TAR"` where `Z` = `pigz -1` if `command -v pigz` else `gzip -1`; if `failed` non-empty, `::error::` naming unfetched refs then `exit 1`.
- 2.5 Header comment: add runs 40653699076/40657761446/40661730763 and the latch rationale.
- 2.6 `.github/workflows/rls-authz-fuzz.yml` line 41: `timeout-minutes: 30` → `45` + budget-arithmetic comment citing the same runs.

## Phase 3 — Verify

- 3.1 `bash .github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` → `0 failed`; set `MIN_ASSERTIONS` to the exact green count.
- 3.2 `bash .github/scripts/test/run-all.sh` → exit 0.
- 3.3 `git diff --name-only origin/main...HEAD -- .github/scripts/ghcr-pull-with-retry.sh` → empty.
- 3.4 Confirm every AC in the plan (AC1–AC10) against the diff.
