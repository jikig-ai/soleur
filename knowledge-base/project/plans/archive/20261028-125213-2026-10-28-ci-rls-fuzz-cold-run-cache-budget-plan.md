---
title: "ci(rls-fuzz): cold-run image pull + tar write cannot fit timeout-minutes:30 under sustained ECR/ghcr saturation"
type: fix
date: 2026-10-28
slug: ci-rls-fuzz-cold-run-cache-budget
branch: feat-one-shot-11386-cold-run-cache-warm
issue: 11386
closes: [11386]
lane: cross-domain
priority: p2-medium
domain: engineering
---

# ci(rls-fuzz): cold-run image pull + tar write cannot fit timeout-minutes:30 under sustained ECR/ghcr saturation

## Overview

The `rls-authz-fuzz` job restores a Supabase image-set tarball via `actions/cache`, then runs a serial pre-pull script before `supabase start`. Under sustained registry saturation a cold-cache run cannot fit inside `timeout-minutes: 30`: every image pays ~65s of throttled ECR retries before the ghcr fallback, and the post-pull `docker save | gzip` write needs ~10 min, so the cache that makes subsequent runs cheap can never be populated while the throttle window lasts (measured runs 40653699076, 40657761446; control run 40661730763 succeeded in ~20 min in a calmer window). This plan makes the worst-case budget fit: an ECR-dead latch in the pre-pull script that stops paying the ~65s-per-image dead tax once ECR is provably saturated for this run, a job timeout bump to 45 minutes, a faster tar write, and a best-effort pull loop that saves a partial image set so a failed or timed-out run still leaves cache progress for the next run.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed; no spec.md exists for this branch).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified 2026-10-28) | Plan response |
|---|---|---|
| "each tries `public.ecr.aws/<ref>` first … 3 attempts, `GHCR_PULL_RETRY_SLEEPS` default `20 45` → ~65s burn" | Confirmed — `ghcr-pull-with-retry.sh:45` (`:-20 45`), `ATTEMPTS=3` at `:41`; ECR-first at `supabase-pre-pull-images.sh:94-103` | Latch caps the burn at `SUPABASE_ECR_DEAD_AFTER` images per run instead of all 14 |
| "After ALL pulls it writes one tar: `docker save … \| gzip`" | Confirmed — `supabase-pre-pull-images.sh:112` | Save moves to present-refs only, `gzip -1`/`pigz -1` |
| "post-action cache save (skipped on timeout-cancel)" | Consistent with `actions/cache` post-job semantics — a cancelled job never runs post steps; a **failed** job does | Therefore partial progress must be written by a step that *completes* (fails), not by incremental writes mid-run that only a cancelled run leaves behind — see Cut List |
| "a partial tar under the `supabase-imgs-` restore-keys still helps the next run via the `%d/%d` partial-restore path" | Confirmed — `supabase-pre-pull-images.sh:78-89` loads the tar, counts inspect-present refs, prints `cache restore gave %d/%d` and pulls only the remainder | FR-4 writes the partial set so this path actually receives one |

## Hypotheses

Phase 1.4 fired on the `timeout` token. The failure is a job-budget exhaustion, not an SSH/host outage; each layer verified against measured run artifacts rather than re-probed (the runners are ephemeral).

1. **L3 firewall allowlist.** [verified — N/A with artifact] No host firewall is in the path: the runner is GitHub-hosted, egress is shared-IP, and the registries *answered* with HTTP-level throttle responses (`toomanyrequests: Data limit exceeded`, run 40653699076). A dropped-packet failure cannot produce a registry error body.
2. **L3 DNS/routing.** [verified] `public.ecr.aws` and `ghcr.io` resolved and served pulls — run 40657761446 completed all 14 pulls by 08:55:39Z; routing reached both registries.
3. **L7 TLS/proxy.** [verified] Throttle responses are HTTP replies over working TLS to both registries in the same runs; SNI/cert path is fine (the signature is an application verdict, not a handshake failure).
4. **L7 application layer.** [verified — this is the layer] The measured signature is `toomanyrequests` on pull attempts plus the job-level timeout-cancel at 30 min (runs 40653699076/40657761446). Same code in a calmer window succeeded end-to-end in ~20 min (run 40661730763), so the wiring is sound; the deficit is budget arithmetic, not a service defect.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

Checklist pass over the four layers: each layer above carries a concrete artifact (run IDs + the measured signature line) rather than "obvious/unlikely". No lower-layer gap remains open — the only live hypothesis is the L7 budget-arithmetic one this plan fixes.

## Research Insights

### Premise Validation (Phase 0.6)

Checked: issue #11386 is OPEN (`gh issue view 11386`); cited predecessor #10868 is CLOSED by merged PR #11295 — the resilience scaffolding this fix builds on is real and shipped. All four cited paths exist on `origin/main` and are byte-identical in this worktree. ADR corpus grepped for `ecr|supabase.*cache|image.*pull|throttle|toomanyrequests` — ADR-257 (latched retrying unit) uses a *latch* for a different surface (systemd provisioning) and endorses the pattern; no ADR's rejected-alternatives table names any proposed mechanism. Collision precheck: PR #11396 is this branch's own draft (expected); two `test-all.sh` processes belong to an unrelated inngest worktree. Nothing stale.

### Property List (Phase 0.6b)

1. A cold-cache run fits the job budget under sustained registry saturation (pull + save + suite).
2. The ~65s-per-image ECR dead tax is not paid once ECR is provably saturated for the run.
3. Partial pull progress survives a failed run and warms the next run's cache monotonically.
4. The tar write takes materially less than ~10 min.
5. Failure semantics stay honest: an incomplete image set still fails the job (no silent green with missing images).

### Cut List (Phase 0.6b)

- **Incremental per-image tar write** (issue option 3, second half) — property 3's stated mechanism — **cut/reshaped.** `actions/cache`'s post-job save is skipped on timeout-*cancel*, so a partial tar written mid-run reaches the cache only if the step completes. The property is served instead by FR-4: a best-effort pull loop that *finishes* the step (failed, not cancelled) and writes the inspect-present subset — the post-step save does run on a failed job.
- **Registry reachability probe** — buys property 2 but is cut: already rejected by measured evidence pinned in the workflow comment (`rls-authz-fuzz.yml:77-82`, runs 40525753531/40561028313/40572250940/40573437435/40574945720/40575928811) — every registry throttles even single manifest calls on a shared runner IP, so a probe is a failure source, not a signal. The pull loop itself is the probe.
- **Parallel image pulls** — buys property 1 nominally; cut: re-bursts the same shared-IP bucket the serial design (#10868) exists to pace, and `supabase start`'s own fan-out already demonstrated the loss (script header `:6-13`).
- **Distinct throttle-exhaustion rc in `ghcr-pull-with-retry.sh`** — buys a cleaner latch signal; cut: changes the helper's rc-propagation contract pinned by `b:exhaust-rc`/`b:non-sig-rc` rows and reaches the `supabase start` call site, for no property the output-tail classification doesn't already buy.
- **Dropping ECR entirely** — buys property 2 absolutely; cut: ECR is a real second bucket that *does* serve pulls in unsaturated windows (run 40661730763); the latch keeps the upside and only skips the dead tax.

### Relevant file paths

- `.github/scripts/supabase-pre-pull-images.sh` — pull loop `:93-108`, cache write `:110-114`, cache restore `:77-90`, extraction floor `:69-73`.
- `.github/scripts/ghcr-pull-with-retry.sh` — retry helper; **unchanged by this plan** (contract pinned by `b:*` suite rows).
- `.github/workflows/rls-authz-fuzz.yml` — `timeout-minutes: 30` at `:41`; cache wiring `:99-109`.
- `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` — `wiring:timeout-30` assert at `:262-263`; docker stub `:566-586`; `run_prepull` harness `:589-600`; `c:exhaust-*` rows `:691-694`; `MIN_ASSERTIONS=138` at `:709`.

### Institutional learnings that bind the fix

- `best-practices/2026-07-14-extracting-nonzero-returning-helper-into-command-sub-aborts-under-set-e.md` — the latch's throttle classification must happen inside `if`/negated-`if` conditions or with `|| true`; a `x="$(…)"` capture of a nonzero-returning helper aborts the script under `set -euo pipefail`.
- `2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md` — new docker-stub arms must model the real classification boundary (throttle signature in output tail vs deterministic failure), not just configured rcs.
- `2026-10-21-docker-run-implicit-pull-misattribution.md` — adding bounded operations requires re-deriving enclosing budgets in the same diff; the `timeout-minutes` bump and the `wiring:timeout-*` suite pin move together, with the arithmetic stated.
- `2026-10-23-timeout-record-satisfies-verdicts-in-both-directions.md` — latch rows assert exact pull counts (`== N`), never `!=`/presence-only, so an early abort cannot satisfy them vacuously.
- `2026-06-09-no-test-asserts-X-must-grep-workflow-step-names-in-ci-test-sh.md` — swept `*.test.sh` for other pins on this workflow: only the resilience suite's `wiring:timeout-30` asserts on the job block (`test-bump-inngest-*`/`test-mint-*` pin *their* workflows' timeouts).
- `2026-09-30-one-throttle-over-a-repeating-and-a-once-only-signal-silences-the-once-only-one.md` — the latch-trip `::warning::` is a once-only signal: emit it on the state transition only, never bundled into a per-image or throttled message.

### Related issues and PRs

- #11386 (this fix), #10868 (predecessor resilience work, closed by PR #11295), PR #11396 (this branch's draft).
- Measured runs: 40653699076 (~11/14 images in 30 min, cancelled at timeout), 40657761446 (14 pulled by ~20 min, killed mid-`docker save` at ~09:05:34), 40661730763 (same code, calmer window, full success ~20 min).

### Repository conventions

Scripts are bash with `set -euo pipefail`, heavy header comments citing measured run IDs, `::warning::`/`::error::` annotations naming measured signature lines (ADR-166). Never `xargs -r`, `readlink -f`, `sed -i` (POSIX/macOS portability). Test suite uses `SOLEUR_*`-style row names (`wiring:*`, `b:*`, `c:*`), PATH-stubbed commands logging to `$STUB_CALLS`, exact-count assertions, and an anti-vacuity `MIN_ASSERTIONS` floor that must be raised to the new exact count.

## Proposed Solution

Four changes, all inside the rls-authz-fuzz surface:

- **FR-1 — ECR-dead latch** in `supabase-pre-pull-images.sh`: count *consecutive* ECR attempts whose helper invocation ends in throttle-signature exhaustion; once the count reaches `SUPABASE_ECR_DEAD_AFTER` (default 2), skip the `public.ecr.aws` attempt for all remaining images and go straight to the ghcr fallback. Reclaim ~13 min under full saturation (issue's measured figure) for ~2 min of probing cost.
- **FR-2 — `timeout-minutes: 30` → `45`** in `rls-authz-fuzz.yml`, with the measured budget arithmetic in a comment. 45 covers the measured worst case (saturated pulls ~20-30 min post-latch + ~4 min tar write + ~10 min suite) with headroom; a larger value only extends the blast radius of a genuinely hung job, and the partial-save path (FR-4) makes a residual overrun converge rather than restart.
- **FR-3 — faster tar write**: `docker save … | gzip -1`, preferring `pigz -1` when `pigz` is on PATH (present on GitHub ubuntu-latest images; the `command -v` fallback keeps the script portable).
- **FR-4 — best-effort pull loop + partial save**: an exhausted image is recorded in `failed=()` and the loop continues instead of dying under `set -e`; after the loop the tar is written from the `docker image inspect`-present subset only; if `failed` is non-empty the script emits `::error::` naming the unfetched refs and exits 1 — the step *completes* (failed), so the post-action cache save still runs and uploads the partial tar, warming the next run via the existing `%d/%d` partial-restore path.

## Technical Considerations

- **Latch signal**: classify by the ECR attempt's captured output tail (`tail -n 40 | grep -qi toomanyrequests`) — the same tail-scope semantics the helper itself uses (`ghcr-pull-with-retry.sh:79`), so a deterministic ECR failure (`name unknown` for an unmirrored image) can never increment the counter, and a mid-log throttle token that recovered cannot either.
- **Reset semantics**: any non-throttle ECR outcome — success *or* a deterministic answer — resets the consecutive counter to 0. A deterministic answer proves the registry is responding, which is evidence *against* saturation, not for it.
- **Cache-key note**: the cache key hashes `supabase-pre-pull-images.sh`, so merging this PR rotates the key once; `restore-keys: supabase-imgs-` prefix-matching still restores the most recent older entry, so the first post-merge run degrades to a partial restore rather than a true cold start — exactly the path FR-4 strengthens.
- **`docker save` partial-set correctness**: `docker save` exits nonzero when a ref is absent, so the save MUST be built from `docker image inspect`-verified refs, never from the intended `refs[]` list.
- **NFR impact**: availability/CI-reliability only; no new store, connection, credential, or attack surface.

## Implementation Phases

### Phase 1 — `supabase-pre-pull-images.sh` (latch + best-effort + partial save + fast compress)

1. Header comment: extend the `ECR MIRROR`/`ACTIONS CACHE` blocks with the 2026-10-28 run IDs (40653699076/40657761446/40661730763) and the latch rationale.
2. Before the pull loop (`:92`), initialize `ECR_DEAD_AFTER="${SUPABASE_ECR_DEAD_AFTER:-2}"`, `ecr_consec_throttle=0`, `ecr_dead=0`, `failed=()`, and a per-image ECR log dir (`mktemp -d` + owning `trap` cleanup, mirroring the helper's own pattern at `ghcr-pull-with-retry.sh:54-55`).
3. Pull loop: keep the `docker image inspect` cached-skip. When `ecr_dead == 0`, run `bash "$RETRY" docker pull "$ecr" 2>&1 | tee "$ecr_log"` inside an `if` condition (set-e-exempt); on success `docker tag` + reset counter + `continue` as today. On failure, classify the tail: `toomanyrequests` → increment counter, trip the latch (`::warning::` once, on the transition only) at `ECR_DEAD_AFTER`; otherwise reset counter to 0. When `ecr_dead == 1`, skip the ECR attempt entirely and emit a per-image `pre-pull: %s ecr skipped (latch)` line.
4. ghcr fallback: wrap `bash "$RETRY" docker pull "$ghcr"` in `if ! …; then failed+=("$img"); ::warning:: per-image; continue; fi` — best-effort, no `set -e` abort. Keep the `pre-pull: %s via ghcr` marker on success.
5. Post-loop: build `present_refs` by `docker image inspect` over `refs[]`; if `SUPABASE_IMG_CACHE_DIR` set and `present_refs` non-empty, `docker save "${present_refs[@]}" | "$Z" > "$CACHE_TAR"` where `Z` is `pigz -1` when `command -v pigz` else `gzip -1`; if `failed` non-empty, `::error::` naming the unfetched refs then `exit 1`.

### Phase 2 — `rls-authz-fuzz.yml` (budget)

- `:41` `timeout-minutes: 30` → `45`, with a comment carrying the arithmetic: ~13 min ECR dead tax pre-latch + ~20-30 min throttled pulls + ~10 min default-gzip tar write > 30 measured on runs 40653699076/40657761446; 45 covers the post-latch worst case with suite headroom.

### Phase 3 — `test-rls-fuzz-ghcr-resilience.sh` (extend the contract)

1. `wiring:timeout-30` (`:262-263`) → `wiring:timeout-45` asserting `timeout-minutes: 45`; header comment `:12` "timeout 30" → "timeout 45".
2. New wiring greps on the script: `SUPABASE_ECR_DEAD_AFTER`, the latch-skip marker, `gzip -1`/`pigz`.
3. Docker stub (`:566-586`): add a pulled-ref registry (`pulled <ref>` lines on pull success) and a `pull-tracked` inspect arm that answers present iff the ref was pulled; new `DOCKER_MODE`s:
   - `ecr-throttle-ghcr-ok` — every `public.ecr.aws` pull emits `toomanyrequests` + exit 1 (all attempts); every `ghcr.io` pull succeeds. Expect: img-a/img-b burn 3 ECR attempts each, img-c..img-l skip ECR entirely — ECR pulls == 6, ghcr pulls == 12, total == 18, rc 0, exactly one latch `::warning::`, `ecr skipped (latch)` lines present.
   - `ecr-flap` — img-a throttles (×3), img-b fails deterministically (×1, resets counter), img-c throttles (×3 → latch trips for img-d+). Expect ECR pulls == 7 and img-d.. skipped — proves reset-on-deterministic.
   - `partial-fail` — one ref fails on *both* registries (all attempts throttle); all others succeed. Expect rc 1, `::error::` names the failed ref, `docker save` argv contains every present ref and NOT the failed one, save call count == 1.
4. Update `c:exhaust-*` rows (`:691-694`) for best-effort semantics: `always` mode now walks all 12 images — img-a (3 ECR + 3 ghcr), img-b (3 ECR + 3 ghcr, latch trips), img-c..img-l (3 ghcr each) — pulls == 42, rc 1, zero `save` invocations (nothing present), `::error::` names the unfetched set.
5. Raise `MIN_ASSERTIONS` to the new exact green count.

### Phase 4 — verification

- `bash .github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` → `0 failed`; `bash .github/scripts/test/run-all.sh` → full suite green.
- Live proof is environmental by definition (the failure only manifests under shared-egress saturation); the suite covers the mechanism deterministically, and a `workflow_dispatch` warm run on the merged code provides the confirmation datapoint.

## Files to Edit

- `.github/scripts/supabase-pre-pull-images.sh` — ECR-dead latch (`:92-108`), best-effort ghcr fallback (`:106`), present-subset save + `pigz`/`gzip -1` (`:110-114`), header comment, `mktemp` ECR log dir.
- `.github/workflows/rls-authz-fuzz.yml` — `timeout-minutes: 30` → `45` (`:41`) + budget comment.
- `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` — `wiring:timeout-45` (`:262-263`), latch/compression wiring greps, pulled-ref registry + `pull-tracked` inspect arm, `ecr-throttle-ghcr-ok`/`ecr-flap`/`partial-fail` stub modes, updated `c:exhaust-*` (`:691-694`), `MIN_ASSERTIONS` (`:709`), header comment (`:12`).

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 issues) bodies contain no reference to `supabase-pre-pull-images.sh`, `rls-authz-fuzz.yml`, `test-rls-fuzz-ghcr-resilience.sh`, `ghcr-pull-with-retry.sh`, or `run-all.sh`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "ECR-dead latch in `.github/scripts/supabase-pre-pull-images.sh`: after the first N consecutive ECR throttle exhaustions in a run, skip the ECR attempt for remaining images (~13 min reclaimed)" | FR-1 / Phase 1.2-1.3 / `supabase-pre-pull-images.sh` | mapped |
| 2 | "Bump `timeout-minutes` 30 -> 45 in `rls-authz-fuzz.yml` to cover pull + save + suite under cold-cache saturation" | FR-2 / Phase 2 / `rls-authz-fuzz.yml` | mapped |
| 3 | "Faster tar write: `gzip -1`/`pigz`, or incremental per-image save so partial progress survives a timeout (a partial tar under the `supabase-imgs-` restore-keys prefix still shortens the next run via the `%d/%d` partial-restore path)" | FR-3 (gzip/pigz) + FR-4 (partial progress via best-effort + subset save — the mechanism reshaped, see Cut List) / Phase 1.4-1.5, Phase 3.4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| FR-1 ECR-dead latch | "after the first N consecutive ECR throttle exhaustions in a run, skip the ECR attempt for remaining images" | asked |
| FR-2 timeout 45 | "Bump `timeout-minutes` 30 -> 45 in `rls-authz-fuzz.yml`" | asked |
| FR-3 gzip -1 / pigz | "Faster tar write: `gzip -1`/`pigz`" | asked |
| FR-4 best-effort pull + present-subset save | "so partial progress survives a timeout — a partial tar under the `supabase-imgs-` restore-keys prefix still shortens the next run via the `%d/%d` partial-restore path" | inferred — justification: serves the stated property; the stated *mechanism* (incremental save) cannot deliver it because `actions/cache`'s post-save is skipped on timeout-cancel while it does run on a failed step (Cut List row 1) |
| Test-suite extension (`wiring:timeout-45`, stub modes, `MIN_ASSERTIONS`) | — | inferred — justification: repo convention `cq-write-failing-tests-before` and the suite's own header contract pin every behavior change to a fixture row; the `wiring:timeout-30` assert goes red without the update |
| Header/comment updates citing run IDs | — | inferred — justification: repo convention "heavy header comments citing measured run IDs" (both touched files carry them; a silent threshold change would violate it) |

### Split Assessment

- Subsystems touched: 1 — `.github`
- Planned files: 3 | Estimated changed lines: ~180 (script ~50, workflow ~5, suite ~125)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to an existing CI workflow and its two test-pinned scripts. (Domain-leader Task fan-out unavailable in this harness — assessed inline; the change touches no product, marketing, legal, finance, sales, support, or operations surface.)

## User-Brand Impact

- **If this lands broken, the user experiences:** the required `RLS authz fuzz` check never completes during registry-saturation windows, so migration-touching PRs stay unmergeable — an availability defect on an internal CI gate, no end-user surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the script performs unauthenticated public-registry pulls and writes a local image tarball; no credentials, user data, or money flow is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** worst case is a required check staying red — an internal productivity cost, not a user-facing breach or leak.

## Observability

```yaml
liveness_signal:
  what: "RLS authz fuzz job green on PRs and workflow_dispatch; latch state visible as the single `::warning::ecr latch` annotation in the Pre-pull step"
  cadence: "per-run"
  alert_target: "PR required-check status + step annotations (operator-visible in the run log)"
  configured_in: ".github/workflows/rls-authz-fuzz.yml:105-109"

error_reporting:
  destination: "GitHub Actions step annotations — `::error::`/`::warning::` in the Pre-pull Supabase image set step"
  fail_loud: "`::error::pre-pull: N image(s) unpulled: …` + step exit 1; latch trip emits `::warning::ecr latch: 2 consecutive throttle exhaustions`"

failure_modes:
  - mode: "sustained ECR saturation"
    detection: "`::warning::ecr latch` annotation + `ecr skipped (latch)` lines in step output"
    alert_route: "annotation on the run; job stays green via ghcr fallback"
  - mode: "partial pull (some images unfetched on both registries)"
    detection: "`::error::` naming the failed refs; partial tar still uploaded by the post-action cache save"
    alert_route: "job red on the pre-pull step"
  - mode: "corrupt/truncated cache tar"
    detection: "`pre-pull: no usable image cache` line (docker load fails) → full pull path"
    alert_route: "step output; pre-existing behavior unchanged"
  - mode: "residual timeout despite all measures"
    detection: "job cancelled at 45 min — required check red; partial progress banked iff pulls completed before the kill"
    alert_route: "PR check status"

logs:
  where: "GitHub Actions step logs (Pre-pull Supabase image set), `gh run view --log`"
  retention: "GitHub run-log retention (~90 days)"

discoverability_test:
  command: grep -c '::warning::ecr latch' .github/scripts/supabase-pre-pull-images.sh
  expected_output: "1"
```

## Encryption Posture

The plan writes into one existing store (the `actions/cache` image tarball at `${{ runner.temp }}/supabase-img-cache`, uploaded by the cache action's post step) and reuses two existing connections (anonymous `docker pull` against `public.ecr.aws` and `ghcr.io`). No new store or connection is introduced; the posture below declares the surfaces the diff touches.

```yaml
at_rest:
  - store: actions/cache entry "supabase-imgs-*" (GitHub-hosted cache blob)
    mechanism: provider-managed:GitHub Actions cache storage (GitHub Actions cache docs, retrieved 2026-10-28)
    evidence: https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows
    defends_against: direct object-store access outside the actions/cache API (repo-scoped cache isolation; forks get read-only base-branch entries)
    does_not_defend: cache poisoning via a compromised same-repo workflow run, a leaked token with actions:write, or malicious tar content loaded by `docker load` in a later run — the tar holds public Supabase images only, and the loader is the same runner that built it
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:requires a GitHub-hosted runner (cache API is not locally enumerable)
in_transit:
  - connection: runner -> public.ecr.aws / ghcr.io (docker pull)
    enforced_at: .github/scripts/supabase-pre-pull-images.sh (docker daemon pull path)
    tls: HTTPS TLS >= 1.2 via the docker daemon's registry transport
    cert_verification: on
    does_not_defend: content integrity beyond the registry's — no digest pinning; tag-to-tag pulls trust the registry's name mapping (pre-existing; unchanged by this plan)
    disclosed_as: not-publicly-claimed
  - connection: runner -> GitHub cache storage (actions/cache save/restore)
    enforced_at: .github/workflows/rls-authz-fuzz.yml `uses: actions/cache@<sha>`
    tls: HTTPS TLS >= 1.2 (actions/cache Azure-backed blob endpoint)
    cert_verification: on
    does_not_defend: cache-key prefix collisions under `restore-keys: supabase-imgs-` restoring stale-but-intended content
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — cold-run convergence contract (test-rls-fuzz-ghcr-resilience.sh extension)

**Property.** Under sustained ECR saturation a cold-cache run stops paying the per-image ECR dead tax after `SUPABASE_ECR_DEAD_AFTER` consecutive throttle exhaustions, banks whatever subset it did pull as a partial cache tar, and still exits nonzero naming every unfetched ref — i.e. progress is monotonic across runs and failure is never silent.

**Assembly.** Every registry call the job makes flows through the single pull loop in `supabase-pre-pull-images.sh` (the only chokepoint — `MIN_IMAGES`-bounded `IMAGES` array × {ECR, ghcr} × the retry helper). The guard quantifies over: that loop's per-image registry choice (latch state), the post-loop save's ref subset, the workflow `timeout-minutes` literal, and the suite's own wiring/behavior rows in `test-rls-fuzz-ghcr-resilience.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the latch's skip branch (`ecr_dead` never consulted) | RED — `ecr-throttle-ghcr-ok` arm counts ECR pulls 6→36 (12 images × 3 attempts) |
| 2 | Trip check reads `>= 999` / counter never incremented (guard's own dispatch dead) | RED — same arm: latch `::warning::` absent, `ecr skipped (latch)` absent, exact-count fails |
| 3 | Counter resets on throttle too (increment line removed, reset kept) | RED — latch never trips; ECR pull count explodes |
| 4 | Save passes `refs[]` (intended set) instead of `present_refs` | RED — `partial-fail` arm: save argv contains the absent ref (and a real `docker save` would die on it) |
| 5 | ghcr failure aborts the loop (`set -e` semantics restored via unguarded call) | RED — `partial-fail` arm: pull count collapses to the first failure's 6 instead of walking all images |
| 6 | `timeout-minutes` back to 30 (or any non-45 literal) | RED — `wiring:timeout-45` fails |
| 7 | Reorder: latch check moved *after* the ECR attempt rather than gating it | RED — every image still burns one ECR attempt post-trip; exact-count rows fail |
| 8 | Deterministic ECR failure counted as throttle (misclassified tail) | RED — `ecr-flap` arm: latch trips one image early; ECR count 7→4 fails the exact pin |
| 9 | must-PASS: `ok` mode (ECR healthy) still pulls all 12 via ECR with zero latch warnings | PASS — latch must not fire when the registry answers |
| 10 | must-PASS: `ecr-fail` (deterministic misses everywhere) still tries ECR 12× then ghcr 12× | PASS — the latch may not suppress legitimate cheap ECR attempts |

**Anchor.** The floor the matrix protects — `MIN_ASSERTIONS` — is itself pinned by the suite's instrument self-test and must move to the new exact count in the same diff (ADR-193); a matrix row silently passing by being deleted is caught by the floor.

## Acceptance Criteria

- [x] AC1: `supabase-pre-pull-images.sh` skips the `public.ecr.aws` pull for remaining images after `SUPABASE_ECR_DEAD_AFTER` (default 2) *consecutive* ECR throttle-signature exhaustions in a run, and emits exactly one `::warning::ecr latch` annotation on the transition.
- [x] AC2: the consecutive counter resets to 0 on any non-throttle ECR outcome (success or deterministic failure), so a flapping-but-answering ECR never latches.
- [x] AC3: an exhausted per-image pull (ECR and ghcr both fail) is recorded and the loop continues over the remaining images; the script exits nonzero only after attempting every image.
- [x] AC4: the cache tar is written from `docker image inspect`-verified present refs only; on a partial pull the subset is saved and the script emits `::error::` naming the unfetched refs before `exit 1`; on zero present refs no `docker save` is attempted.
- [x] AC5: the tar write uses `pigz -1` when `command -v pigz` succeeds and `gzip -1` otherwise; never the default gzip level.
- [x] AC6: `rls-authz-fuzz.yml` carries `timeout-minutes: 45` with a comment citing runs 40653699076/40657761446.
- [x] AC7: `ghcr-pull-with-retry.sh` is unchanged on this branch (`git diff --name-only origin/main...HEAD -- .github/scripts/ghcr-pull-with-retry.sh` is empty — merge-base form, not the moving tip).
- [x] AC8: the resilience suite asserts the new contract — `wiring:timeout-45`, latch wiring greps, `ecr-throttle-ghcr-ok`/`ecr-flap`/`partial-fail` behavioral arms with exact pull counts, updated `c:exhaust-*` expectations — and prints `0 failed` locally.
- [x] AC9: pre-existing behavioral rows still hold: full cache hit (zero pulls), partial restore (`%d/%d` + only-missing pulls), glue-cut tag extraction, `MIN_IMAGES` floor, missing-CLI exit 2.
- [x] AC10: `MIN_ASSERTIONS` is raised to the new exact assertion count in the same diff (ADR-193) and `bash .github/scripts/test/run-all.sh` exits 0.

## Test Scenarios

All rows land in `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` (fixture/stub layer — `unit`-equivalent; no e2e scenario: the real throttle is environmental and cannot be synthesized deterministically).

- **Latch trip** — Given `DOCKER_MODE=ecr-throttle-ghcr-ok`, when the pre-pull runs, then ECR pulls == 6 (images 1-2 only), ghcr pulls == 12, rc 0, one latch `::warning::`, `ecr skipped (latch)` present for images 3+.
- **Latch reset on deterministic answer** — Given `DOCKER_MODE=ecr-flap`, when img-b's ECR attempt fails deterministically after img-a's throttle, then the counter resets and img-c pays ECR again (ECR pulls == 7) before the latch trips for img-d+.
- **No latch on healthy ECR** — Given `DOCKER_MODE=ok`, when the run completes, then ECR pulls == 12, ghcr pulls == 0, no latch warning, rc 0.
- **No latch on deterministic misses** — Given `DOCKER_MODE=ecr-fail`, when all images miss ECR deterministically, then ECR pulls == 12, ghcr pulls == 12 (existing row shape, re-verified).
- **Partial save on failed pull** — Given `DOCKER_MODE=partial-fail` (one ref fails both registries), when the run ends, then rc 1, `::error::` names the failed ref, exactly one `docker save` call whose argv contains all present refs and not the failed one.
- **Total exhaustion converges, not spirals** — Given `DOCKER_MODE=always`, when all pulls throttle, then pulls == 42 (latch truncates ECR probing at img-b), rc 1, zero `save` calls, `::error::` names the unfetched set.
- **Timeout budget** — Given the workflow file, when `wiring:timeout-45` greps the `rls-fuzz:` job block, then `timeout-minutes: 45` is present and `timeout-minutes: 30` absent.
- **Compression wiring** — Given the script, when greps run, then `pigz -1`/`gzip -1` tokens are present and no bare `| gzip >` remains.

## Success Metrics

- Cold-cache `workflow_dispatch` run completes inside 45 min during a future saturation window (previously: cancelled at 30 twice consecutively).
- Partial progress: a run that fails at pull k of 14 leaves a cache entry restoring those k images on the next run (observable via the `cache restore gave k/14` line).
- Suite: `0 failed` with the raised `MIN_ASSERTIONS` floor.

## Dependencies & Risks

- **Risk**: a saturation window that also saturates ghcr for the full run still overruns 45 min — mitigated: partial progress banks per run (monotonic convergence), so each subsequent cold run starts warmer.
- **Risk**: `pigz` absent on a future runner image — mitigated: `command -v` fallback to `gzip -1`; never required.
- **Risk**: latch threshold mispredicts (ECR recovers mid-run after 2 exhaustions) — accepted: cost of a false latch is ECR upside foregone for the remainder of *one run only* (in-memory state); `SUPABASE_ECR_DEAD_AFTER` remains env-tunable.
- **Dependency**: none beyond existing runner tooling (`docker`, `gzip`; `pigz` opportunistic).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6 — filled above.
- **Do NOT reintroduce** `x="$(bash "$RETRY" …)"` captures — under `set -euo pipefail` a nonzero helper aborts the whole script before classification (learning 2026-07-14); helper invocations stay inside `if`/negated-`if` conditions.
- **Do NOT** change `ghcr-pull-with-retry.sh`'s rc contract to signal throttle — `b:exhaust-rc`/`b:non-sig-rc` pin it and the `supabase start` call site consumes it.
- **Do NOT** write the tar incrementally expecting it to survive a timeout-*cancel* — `actions/cache` post-save is skipped on cancel; partial progress must be written by a step that completes (failed steps still run post steps).
- **`docker save` must never receive an absent ref** — build the argv from `docker image inspect` results; the intended `refs[]` list dies on the first missing image.
- The latch `::warning::` is once-only — bundling it into a per-image or otherwise-throttled line silences it (learning 2026-09-30).
- Exact-count assertions, never `!=`/presence — a deadline kill satisfies a negative verdict vacuously (learning 2026-10-23).
- Cache key rotates on merge (the key hashes this script) — expected one-time degradation to `restore-keys` partial restore; not a regression.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Incremental per-image `docker save` | rejected (reshaped into FR-4) | Post-job cache save is skipped on timeout-cancel; only a completing step's tar reaches the cache. Per-image saves also serialize ~10 min of disk IO into the pull window. |
| Parallel image pulls | rejected | Re-bursts the shared-IP bucket the serial design exists to pace (#10868). |
| Distinct throttle-exhaustion rc in the helper | rejected | Changes a contract pinned by `b:*` rows and consumed by `supabase start`; output-tail classification in the caller buys the same signal. |
| Drop ECR, pull ghcr only | rejected | ECR is a real second bucket that serves in unsaturated windows; the latch keeps the upside. |
| `timeout-minutes: 60` | rejected in favor of 45 | 45 covers the measured post-latch worst case; 60 only extends a genuinely-hung job's blast radius while partial progress already makes overruns converge. |
| Split into a dedicated cache-warming job | rejected | A second job's scheduling adds a new autonomous surface (Task-Design gate) to solve what an in-job latch + partial save already solves. |

## Out of Scope

- Changes to `ghcr-pull-with-retry.sh` or `supabase-local.sh` (contract surfaces held stable).
- Any `content-publisher`/`supabase` workflow changes (explicitly unrelated per the issue).
- Registry-level fixes (vendor throttling policy) — not ours to change.

## References & Research

- Issue: #11386; predecessor #10868 (closed by PR #11295); draft PR #11396.
- Measured runs: 40653699076, 40657761446, 40661730763, plus the #10868 series 40525753531/40561028313/40572250940/40573437435/40574945720/40575928811 pinned in the workflow comment.
- Files: `.github/scripts/supabase-pre-pull-images.sh`, `.github/scripts/ghcr-pull-with-retry.sh`, `.github/workflows/rls-authz-fuzz.yml`, `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh`, `.github/scripts/test/run-all.sh`.
- Learnings cited above in Research Insights.

## Enhancement Summary

deepen-plan pass, 2026-10-28 (harness: Devin subagent — no Task-spawn capability; gates and fan-outs executed inline):

- Phase 4.4 precedent-diff: latch/circuit-breaker precedent found — the retry helper's own tail-classification (`ghcr-pull-with-retry.sh:79`) and ADR-257's latched retrying unit; the new stub arms follow the existing suite's stub convention in the same file. No scheduled job introduced; Inngest-vs-GHA-cron check N/A.
- Phase 4.5 network-outage deep-dive: fired on `timeout`; all four layers carry artifacts (see `## Hypotheses` + `### Network-Outage Deep-Dive`). Telemetry emitted.
- Phase 4.55 downtime/cutover: skipped — CI-config-only change; no serving surface goes offline.
- Phase 4.6 user-brand halt: section present, `none` threshold, no sensitive-path match → pass.
- Phase 4.7 observability: section present; `discoverability_test.command` rewritten during this pass from the suite invocation (matched the Check-10 suite-shape rejection) to `grep -c '::warning::ecr latch' …` expecting `1` — smallest command that proves the once-only signal surface exists.
- Phase 4.8 PAT halt: zero hits.
- Phase 4.9 UI wireframe: no UI-surface files → pass.
- Phase 4.10 encryption posture: detection fires on the `cache` prose — `## Encryption Posture` added for the existing actions/cache store and the two registry/cache connections (no new store introduced).
- Phase 4.11 guard contract: `scripts/lint-guard-contract.py` green (1 guard entry); assembly read as structural (the single pull-loop chokepoint, not a member list); matrix carries own-dispatch, second-member, reorder, and two must-PASS rows.
- Phase 4.12 scope check: exactly one unfenced `## Scope Check`; all asks mapped; `inferred` rows carry justifications; split assessment `single PR`.
- Phase 4.13 task-design: no new autonomous surface → pass.
- Phases 3/4 research + Phase 5 review agents: no external-research value for a measured CI-script fix; institutional learnings applied inline (Research Insights). Review-panel checks applied inline: no AC depends on concurrent ambient state (all assert file contents or fixture-stub behavior); every mechanism maps to a Property-List item or is on the Cut List; spec-flow branch enumeration covered in Test Scenarios.

### Key improvements made during deepen pass

- `discoverability_test` probe fixed to a Check-10-compliant form.
- `## Encryption Posture` section added (4.10 detection fires on the cache store).
- `### Network-Outage Deep-Dive` subsection added per Phase 4.5.
- AC7 corrected to merge-base diff form (`origin/main...HEAD`).

### New considerations discovered

- `actions/cache` post-job save semantics drive the FR-4 design: skipped on cancel, runs on failure — the reason partial progress is banked by a completing failed step, not incremental mid-run writes.
