# Tasks — fix(6969): cloud-init doppler_download error channel

Derived from
[`2026-07-26-fix-cloud-init-doppler-download-error-channel-plan.md`](../../plans/2026-07-26-fix-cloud-init-doppler-download-error-channel-plan.md)
after CTO review + a four-agent plan-review panel. Read the plan's **Research Reconciliation** before
starting — it records five defects (R9, R15, R19, R20, R26) that are invisible from the code alone.

`lane: cross-domain` · `brand_survival_threshold: single-user incident` · `requires_cpo_signoff: true`

---

## Phase 0 — Preconditions

- [x] **0.1** Re-read `hcloud_server.web`'s `lifecycle` block and confirm `ignore_changes` still contains
      `user_data` before touching `cloud-init.yml`.
- [x] **0.2** Record the byte-budget baseline: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`.
      Expect render ≈ **23,180–23,184 B** vs `WEB_GZIP_BUDGET = 23_700` (the two model runs differ by ~4 B;
      quote the number the shipped test prints). Budget for `/work`: **≈1,100 raw bytes** of new inline
      shell (novel shell costs ~0.46 gzipped B per raw byte).
- [x] **0.3** **Ingestion probe (G2 / R21).** POST the **full** new tag set (`stage`, `host_id`, `region`,
      `host_name`, `exit_code`, `detail`) to the Sentry store API; confirm HTTP 200 **and** that the tags
      render. Local JSON validity is a proxy — ingestion is the invariant, and on a fail-open emitter a
      rejected payload is worse than today. Drop any rejected tag. Record the verdict for the PR body.
- [x] **0.4** Capture green baselines: observability suite (**95 pass**), op-contract vitest (**4 pass**).

## Phase 1 — Error channel in the shared baked emitter (`soleur-host-bootstrap.sh`, 0 `user_data`)

> **If anything must be cut, everything else goes first and this ships alone.**

- [x] **1.1** Add `@@SOLEUR_HOST_NAME@@` to the `soleur-boot-emit` heredoc + a second `sed -i` splice
      beside the existing DSN splice (non-`/` delimiter; `${SOLEUR_HOST_NAME:-$(hostname)}` fallback).
- [x] **1.2** Assert **no residual `@@`** survives the splice — a typo ships
      `host_name=@@SOLEUR_HOST_NAME@@` on every event, silently.
- [x] **1.3** Add the `detail` tag: read `/run/soleur-stage-detail.d/$STAGE`, falling back to the legacy
      `/run/soleur-stage-detail` when absent. **Leave all legacy producers and the inline `_emit`
      untouched** (R18).
- [x] **1.4** Sanitizer, in order: drop `^Using ` preamble → `LC_ALL=C` → strip control chars → drop `"`
      and `\` → fold newlines to spaces → **trim** → **`tail -c 180`** → **ASCII-only pass after the cap**
      (R31c: `tail -c` can split UTF-8; an invalid tag value loses the breadcrumb on a fail-open emitter).
- [x] **1.5** Carry `exit_code` and `attempts` **inside the detail string**, not as new positional args —
      the emitter's signature is `<stage> [level]` and three call sites pass two args.
- [x] **1.6** Author `/usr/local/bin/soleur-doppler-download` as a **heredoc** (like `soleur-boot-emit`),
      **not** via the `install -D` loop — a seed file would force edits to `local.host_script_files`, the
      image bake and the coherence preflight (R25).
- [x] **1.7** Add `FAILED_FILE` + `test -x` assertions for **both** helpers (a truncated heredoc otherwise
      still writes `/run/soleur-hostscripts.ok`, and the boot dies `command not found`).
- [x] **1.8** Do **not** change the emitter's `message` literal or any alert-filtered stage name.

## Phase 2 — Bounded, self-reporting download (baked helper)

- [x] **2.1** **Stdout is reserved for the secret payload.** Any `echo`/`set -x` in the helper corrupts
      `$TMPENV` → malformed env-file → a fatal mis-naming `docker_run`. Diagnostics go to stderr or `.d/`.
- [x] **2.2** stderr-only capture to a `mktemp` file, `chmod 600`. **The helper owns its own EXIT trap**
      for it (R30 — it is a separate process; the cloud-init trap cannot see that variable).
- [x] **2.3** `timeout 45` per attempt (mirrors the 11 bounded siblings); record **`rc=124`** as a
      distinct named condition (R19).
- [x] **2.4** `NO_COLOR=1`.
- [x] **2.5** **Call site (R9 + R26 — the most dangerous line in the change):**
      ```sh
      soleur-doppler-download "$TMPENV" && rc=0 || rc=$?
      [ "$rc" = 0 ] || exit "$rc"
      ```
      The AND-OR list is `set -e`-exempt; **without the re-raise the boot continues** and can reach
      `cloud_init_complete` with no prd secrets.
- [x] **2.6** Retry `N = 3`, backoff `sleep 5` then `sleep 10` (worst case ≈150 s against a 900 s window).
- [x] **2.7** Loop order, exactly: `rc` capture → scrub → write `.d/doppler_retry` → emit `warning` →
      `n=$((n+1))` → exhaust-check → sleep. (`n=$((n+1))` resets `$?`; emitting after the exhaust-check
      loses the final attempt's breadcrumb.)
- [x] **2.8** Attempts emit `stage=doppler_retry` — **never** `doppler_download_attempt`, which
      string-prefixes `doppler_download` and makes the op-contract anti-rename test vacuous (R20). Skip
      the warning on the exhausting attempt.
- [x] **2.9** **Before returning non-zero, write `.d/doppler_download`** with rc + attempts + scrubbed
      stderr. This is the line that keeps R15 dead — the trap emits `doppler_download` and reads that file.
- [x] **2.10** Scrub `dp\.[a-z]*\.[A-Za-z0-9_-]*` before any write.
- [x] **2.11** Escape only the **brace** form as `$${...}`; leave `$?`, `$rc`, `$stage` bare (R31a).
- [x] **2.12** Re-measure the render; stay under `WEB_GZIP_BUDGET`.

## Phase 3 — `docker_run` sibling only

- [x] **3.1** Capture `docker run` stderr to `.d/docker_run`.
- [x] **3.2** File **one** tracking issue for the remaining stages (and for `host_name` on the `bootcmd`
      beacon + inline `_emit`, per DC-2) **before the PR is marked ready**.

## Phase 4 — Make the failing run self-reporting

- [x] **4.1** Interpolate `detail`/`exit_code`/`host_name` into the **`::error::` annotation strings**,
      not only the trail printer — annotations surface at the top of the run page.
- [x] **4.2** Add `host_name` to the `LAST_STAGE`/fatal **selection**, not just the printed line.
- [x] **4.3** Emit a `::warning::` when a **green** birth's trail contains any `doppler_retry`.
- [x] **4.4** Leave `QUERY` message literals byte-identical.
- [x] **4.5** Refresh the stale `cloud-init.yml:825 of 835` line-number comment in that step.

## Phase 5 — Records

- [x] **5.1** Write **ADR-147** (ordinal provisional — re-verify against `origin/main` at ship; if
      renumbered, sweep `knowledge-base/project/{plans,specs}/feat-one-shot-6969-*`). Record the four
      frozen contract constraints.
- [x] **5.2** Add a one-line pointer from ADR-082 Item 5 to ADR-147.
- [x] **5.3** Correct **both** payload comments in `sentry/issue-alerts.tf` (R31b). No filter/threshold/
      action change.
- [x] **5.4** No `model.c4` edit — the enumeration concludes no new elements or edges.

## Phase 6 — Tests

> Use the heredoc **extraction harness** prior art in
> `apps/web-platform/infra/fresh-boot-ready.test.sh` (`awk`-extract the heredoc body, then run it).
> Without it every behavioural AC degrades to a static grep and the R9/R26 defences ship unverified.
> **Never** `grep -c … = 0` (exits 1 under `set -euo pipefail`); anchor absence-checks on non-comment lines.

- [x] **6.1** T1 sanitizer: real + adversarial fixtures (**synthesized only**) → AC-A.
- [x] **6.2** T2 exhaustion → helper → trap → **real** emitter: one `fatal` tagged `doppler_download`
      **with a non-empty detail containing the CLI error line, exit code and attempt count** → AC-B.
- [x] **6.3** T3 fail-once-then-succeed: succeeds, one `doppler_retry` warning, no fatal → AC-C.
- [x] **6.4** T4 exit 7 → `7`; hang → `124`; **fail-closed arm**: execution does not reach `docker_run` → AC-E.
- [x] **6.5** T5 temp-file hygiene on both paths.
- [x] **6.6** T6 stream separation across **both** files, scoped to the helper body → AC-H.
- [x] **6.7** T7 channel isolation + legacy byte-identical parity → AC-I.
- [x] **6.8** T8 helper install + sentinel splice → AC-F. T9 `docker_run` capture → AC-G.
- [x] **6.9** T10 lockstep: `bash …/soleur-host-bootstrap-observability.test.sh` and
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-web-terminal-boot-fatal-op-contract.test.ts`.
- [x] **6.10** T11 byte budget → AC-L. T12 gate printer + `::error::` interpolation → AC-M.
- [x] **6.11** Full infra suite; confirm no regression against the Phase 0.4 baselines.
      Ran every `apps/web-platform/infra/*.test.sh` (superset of the 73 CI-registered set).
      Sole failure: `workspaces-luks-loopback.test.sh` exit 2 `LOOPBACK_UNAVAILABLE` — **pre-existing
      and environmental**, reproduced identically on pristine `origin/main`; needs root/sudo, which
      CI runners have. Baselines held: observability **95/0** (was 95), op-contract **4/4** (was 4),
      size test **30 pass**. New suite **70/70**. Registration verified at
      `infra-validation.yml:406` + the registration-drift meta-test (11/0).

## Phase 7 — Ship

- [ ] **7.1** PR body: `Closes #6969`; the measured before/after render; the G2 verdict; that this reaches
      **no running host**, does **not** repair `soleur-web-2`, and that destroying it re-arms the
      `host_creates` HALT (recommended sequence: land this first, then destroy-and-rebirth in one window).
      Note that `terraform plan` shows **no diff** for the cloud-init half — expected, not evidence of
      no effect — and that a pre-merge `image_tag` will now fail the coherence preflight.
- [ ] **7.2** Confirm `decision-challenges.md` (DC-1 retry, DC-2 `host_name` scope) is rendered by `/ship`.
- [ ] **7.3** CPO sign-off recorded (threshold `single-user incident`).
