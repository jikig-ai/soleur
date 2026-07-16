# Tasks — feat-one-shot-3366-supabase-advisor-scan

```yaml
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-16-feat-supabase-advisor-rls-public-table-gate-plan.md
closes: [3366, 6506]
pr: 6520
brand_survival_threshold: single-user incident
```

Derived from the finalized (post-review) plan. Phase order is **load-bearing**: the script seam (2)
must exist before the tests that drive it (7), and the dispatch-credential precondition (0.6) must be
settled before the four-site registration (6).

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Re-run live advisor counts for all 3 refs; confirm `rls_disabled_in_public == 0`. **If any is
      non-zero → STOP** (live security finding; the day-one-green premise needs re-deciding).
- [ ] 0.2 Confirm `scripts/lib/strip-log-injection.sh` exists and exposes `strip_log_injection`.
- [ ] 0.3 Confirm `apply-sentry-infra.yml`'s `-target=` list is still enumerated (not wildcarded).
- [ ] 0.4 `gh secret list | grep SUPABASE_ACCESS_TOKEN` — confirm still wired (expect: yes, since 2026-06-18).
- [ ] 0.5 **Pin the advisor lint's object-metadata shape** (load-bearing for 3.3). No live sample of
      `rls_disabled_in_public` exists (all refs at 0) — sample the envelope from a non-zero sibling
      (`rls_enabled_no_policy`, 28 on dev) or Supabase lint docs. **Do not assume field names.** If no
      reliable table identity exists → pre-decided degradation: any advisor-fires + catalog-clean
      disagreement is a **FAIL**.
- [ ] 0.6 **Verify the dispatch credential path BEFORE Phase 6.** Confirm `cron-terraform-drift.ts:69-70`'s
      `mint-installation-token` is reachable with `actions: write` (GitHub **App** token —
      `hr-github-app-auth-not-pat` forbids a PAT). If absent → re-make the substrate decision **now**.

## Phase 1 — Extract the `scrub_pat` helper

- [ ] 1.1 Create `scripts/lib/scrub-supabase-pat.sh` with `scrub_pat()` lifted **verbatim** from
      `apply-inngest-rls.yml:102-104`. Header mirrors `strip-log-injection.sh` (incl. the octal-vs-hex
      `tr` note — do NOT "modernize" the byte-set).
- [ ] 1.2 **Do NOT** refactor the 4 pre-existing inline copies (separate sweep). Obligation is only to
      not *add* a copy.

## Phase 2 — `scripts/supabase-advisor-scan.sh` (the testable seam)

- [ ] 2.1 Create the script. Contract: env in (`REF`, `PROJECT_NAME`, `SUPABASE_ACCESS_TOKEN`); stdout
      counts + census; exit 0/1; emits `fail_mode`. Source both libs; `sanitize()` wrapper. Pin
      `API="https://api.supabase.com"` — **no env override** (testability comes from stubbing `curl`, not
      from an overridable host). Token via env, never argv; `curl … 2>/dev/null`.
- [ ] 2.2 Implement the **fail-closed ladder**, in order:
  - [ ] 2.2.1 Identity preflight: `GET /v1/projects/{ref}` → HTTP 200 **and** `.name == $PROJECT_NAME`.
        Pinned: `mlwiodleouzwniehynfz`→`soleur-dev`, `ifsccnjhymdmidffkzhl`→`soleur-web-platform`,
        `pigsfuxruiopinouvjwy`→`soleur-inngest-prd`.
  - [ ] 2.2.2 Transport: `-w '%{http_code}'`; **HTTP != 200 → FAILURE**, never a zero.
  - [ ] 2.2.3 Structure: `jq -e 'has("lints") and (.lints|type=="array")'` → else FAILURE, never a zero.
  - [ ] 2.2.4 **Only then** count: `[.lints[] | select(.name=="rls_disabled_in_public")] | length` —
        `[]` **without** `?`.
- [ ] 2.3 Emit the non-asserting lint census (sanitized).
- [ ] 2.4 Create `.github/workflows/scheduled-supabase-advisor-scan.yml`: loops the script over all 3 refs,
      **accumulates per-ref status, fails ONCE at the end** (no first-ref abort). `on: workflow_dispatch:`
      **only**, with `inputs.source`. `permissions: {contents: read, issues: write}`; `concurrency`;
      `ubuntu-24.04`; `timeout-minutes: 10`; SHA-pinned `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`.
  - [ ] 2.4.1 **Header-comment hazard:** the hook regex is UNANCHORED — a comment containing ` schedule:`
        **denies the Write**. Backtick-wrap (`` `schedule:` ``) or hyphenate every schedule/cron token.

## Phase 3 — Two assertions, correctly oriented

- [ ] 3.1 **Catalog assertion — UNCONDITIONAL, per ref** (authoritative, coverage-bearing):
      `select count(*) as rls_off from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relkind in ('r','p') and c.relrowsecurity=false`
      → **`rls_off > 0` = FAIL**, regardless of the advisor. Backstop against a stale-clean advisor.
      **Must NOT be nested inside an advisor-non-zero conditional.**
- [ ] 3.2 **Advisor assertion — always runs; subordinate.** It may only ever **ADD** a failure, never
      suppress 3.1. (This orientation is what makes the ADR-112 citation true.)
- [ ] 3.3 **Object-scoped carve-out** (advisor fires + catalog clean): read the advisor-**named** tables
      (shape from 0.5) and check each **without** the relkind filter:
      `select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname = $schema and c.relname = $table`
  - [ ] all named tables `true` → **WARN** (`stale_advisor`), pass.
  - [ ] any `false` **or no row** → **FAIL** (`confirm_indeterminate`).
- [ ] 3.4 Every query fail-closed (HTTP 200 + structure + non-`err` integer), else FAIL.

## Phase 4 — Failure-issue filing

- [ ] 4.1 Port `apply-inngest-rls.yml:255-307` (create-or-comment + auto-close on recovery), with **two
      classes / two titles / independent dedupe + close-search**:
  - [ ] `[ci/supabase-advisor] public table without RLS` — `ci/supabase-advisor`, `type/security`,
        `priority/p1-high` (real violation, `confirm_indeterminate`).
  - [ ] `[ci/supabase-advisor] scan failed` — `ci/supabase-advisor`, `priority/p2-medium`, **no**
        `type/security` (`advisor_unreachable`, `advisor_malformed`, `identity_mismatch`, `unknown_error`).
- [ ] 4.2 **`if: failure()` UNCONDITIONAL.** Do NOT port the source's
      `&& steps.x.outputs.failure_mode != ''` conjunct — an unanticipated abort under `set -euo pipefail`
      exits before the output is written → red run, **no issue**. Use
      `FAIL_MODE: ${{ steps.scan.outputs.failure_mode || 'unknown_error' }}`. Auto-close: `if: success()`.
- [ ] 4.3 **Dedupe by LABEL, not `--search`** (`--search` can return empty under some token contexts → a
      duplicate issue every night). Use `scheduled-terraform-drift.yml:144-148`'s
      `gh issue list --label … --json number,title --jq 'map(select(.title == "…")) | .[0].number // empty'`.
- [ ] 4.4 `--milestone "Post-MVP / Later"` (a hook rejects `gh issue create` without it); labels created
      idempotently (`gh label create … || true`).
- [ ] 4.5 Body: per-ref status incl. `not_scanned`, advisor counts, catalog result, census, `RUN_URL`,
      `fail_mode`. All sanitized.

## Phase 5 — Sentry heartbeat + IaC

- [ ] 5.1 Add `./.github/actions/sentry-heartbeat`, `if: always()`, `continue-on-error: true`,
      `monitor-slug: scheduled-supabase-advisor-scan`.
  - [ ] 5.1.1 **In the GHA workflow at the END of the run** — never from the Inngest fn at dispatch time
        (that would cover only the first hop).
  - [ ] 5.1.2 **Gate on `github.event.inputs.source == 'inngest'`** — else any manual `gh workflow run`
        posts `ok` and forges liveness while Inngest is dead.
- [ ] 5.2 Add `sentry_cron_monitor.scheduled_supabase_advisor_scan` to `cron-monitors.tf`, `name` written
      **slug-shaped**, `schedule = { crontab = "37 3 * * *" }`, mirroring `:83-93`.
- [ ] 5.3 **Add the `-target=` line to `apply-sentry-infra.yml`** — without it 5.2 is inert (monitor
      declared, never applied, liveness dark).

## Phase 6 — Inngest scheduler

- [ ] 6.1 Create `apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts` modelled on
      `cron-terraform-drift.ts`: `{ cron: "37 3 * * *" }` (20 min after the `:17` self-heal — deliberate),
      mint `actions: write` App token in `step.run`, `POST …/dispatches` with the workflow **file
      basename**, passing **`inputs: { source: "inngest" }`**. Dispatch-only. Failure →
      `reportSilentFallback` (token redacted).
- [ ] 6.2 Register at **all four** sites (a miss = silently dead cron):
  - [ ] 6.2.1 `apps/web-platform/app/api/inngest/route.ts` — import + `functions: [...]`.
  - [ ] 6.2.2 `apps/web-platform/server/inngest/cron-manifest.ts` — `"cron-supabase-advisor-scan"`.
  - [ ] 6.2.3 `apps/web-platform/server/inngest/routine-metadata.ts` — metadata entry (Engineering / CTO /
        `Daily 03:37 UTC` / `manualTrigger: allowed`).
  - [ ] 6.2.4 Run the parity tests that enforce 6.2.1-3.

## Phase 7 — Tests + guards

- [ ] 7.1 **`tests/scripts/test-supabase-advisor-scan.sh`** — the real AC7 harness. Stub `curl` on `PATH`
      emitting **synthesized** bodies (`cq-test-fixtures-synthesized-only`): `401`, empty, HTML `502`,
      `.lints`-renamed, clean, violation, wrong-`.name`. Assert exit + `fail_mode` for each. Also covers
      ref↔name **pairing** and the HTTP-status assertion (neither is grep-able).
- [ ] 7.2 **Quadrant harness** (AC7b): advisor×catalog matrix — clean/clean → pass; clean/**dirty** →
      **FAIL**; fires/clean + named-table-true → **WARN+pass**; fires/clean + false-or-no-row → **FAIL**;
      fires/dirty → **FAIL**.
- [ ] 7.3 **`apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh`** — shape guard (auto-run by
      `infra-validation.yml`; actionlint runs in ZERO workflows so this is the only enforceable gate).
      Assert:
  - [ ] workflow trips neither the hook's exact regex nor the hook itself (pipe a synthetic Write payload
        through `new-scheduled-cron-prefer-inngest.sh` → `permissionDecision == "allow"`);
  - [ ] host literal pinned, no `${{ }}` interpolation;
  - [ ] 3 refs + names present and **paired**;
  - [ ] HTTP-status + `has("lints")` guards present (anti-fail-open sentinel);
  - [ ] `.lints[]` **without** `?`;
  - [ ] both libs sourced, no inline redefinition;
  - [ ] catalog assertion **not** nested in an advisor-non-zero conditional;
  - [ ] heartbeat in the GHA workflow, `if: always()`, **source-gated**; Inngest fn has **no** check-in;
  - [ ] issue step `if: failure()` with **no** `failure_mode != ''` conjunct;
  - [ ] `slugify(cron-monitors.tf name) == monitor-slug`;
  - [ ] `cron-monitors.tf` ↔ `apply-sentry-infra.yml` `-target=` set agree;
  - [ ] `model.c4:444` counts match `cron-monitors.tf`.
- [ ] 7.4 `apps/web-platform/test/server/inngest/cron-supabase-advisor-scan.test.ts` — registration-shape +
      dispatch unit test (mirror `cron-terraform-drift.test.ts`).
- [ ] 7.5 Local: `actionlint <workflow>` → **exit 0** (**never** piped to `head` — masks the exit code);
      `shellcheck` both new scripts. Do NOT run actionlint against `.github/actions/*/action.yml`.

## Phase 8 — C4 + ship

- [ ] 8.1 **Description refresh only** on `model.c4:444` `github -> sentry`: 5→6 workflows, 2→3
      Inngest-dispatched (name the new workflow), 48→49 monitors, 5→6 checking in from CI. **No new
      element or relationship.** (Precedent: ADR-030's 2026-06-29 amendment — description refresh is not
      a structural change.)
- [ ] 8.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
- [ ] 8.3 PR body: `Closes #3366`, `Closes #6506` + the Overview's "why now" + surface
      `decision-challenges.md` (DC-A..DC-D).

## Exit gate — run every AC

- [ ] AC1 hook regex + live hook `allow`
- [ ] AC2 host literal pinned
- [ ] AC3 ref↔name pairing (via 7.1)
- [ ] AC4 `has("lints")` present
- [ ] AC5 `! grep -qF '.lints[]?' scripts/supabase-advisor-scan.sh` (explicit **file**; do NOT switch to
      `grep -cE` — it makes `]` optional and permanently false-fails)
- [ ] AC6 libs sourced, not redefined
- [ ] AC7 `bash tests/scripts/test-supabase-advisor-scan.sh` → exit 0 ← **the load-bearing one**
- [ ] AC7b quadrant harness
- [ ] AC8 shape guard exit 0
- [ ] AC9 `-target=` line present + `slugify(name) == monitor-slug`
- [ ] AC10 sentry scope-guard + counter suites still exit 0 (unmodified)
- [ ] AC11 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] AC12 `cd apps/web-platform && ./node_modules/.bin/vitest run …` (4 registration tests) — **the `cd`
      is load-bearing; vitest is absent at repo root**
- [ ] AC13 c4 tests + `git diff origin/main...HEAD -- 'knowledge-base/engineering/architecture/diagrams/'`
      shows only the `:444` description refresh — **ASCII `...`, and assert the exit code**, not just
      empty stdout
- [ ] AC14 `actionlint <workflow>` → exit 0
- [ ] AC15 `model.c4:444` counts == live `cron-monitors.tf` count (49)
- [ ] AC16 PR body has `Closes #3366` + `Closes #6506`
