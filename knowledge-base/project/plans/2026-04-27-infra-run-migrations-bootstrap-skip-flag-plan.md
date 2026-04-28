# infra: add `--bootstrap=skip` flag to `run-migrations.sh` for fresh-DB applies

**Issue:** #2911
**Parent:** #2887 (dev/prd Supabase isolation)
**Type:** infra / bug fix
**Priority:** P2 (important, workaround exists)
**Worktree:** `.worktrees/feat-one-shot-2911-bootstrap-skip-flag/`
**Branch:** `feat-one-shot-2911-bootstrap-skip-flag`

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** Overview line-ref, Phase 1 arg-parser (strict-mode safety), Phase 2 verification (Docker-free path), Risks, Notes.

### Key Improvements

1. Corrected line-range citation (`44-64` → `47-64`) verified against current `run-migrations.sh`.
2. Hardened the arg-parser sketch for `set -euo pipefail` interactions: explicit handling of `"$@"` when no args are passed (`${1-}`-style guard not needed because the `for ... in "$@"` form is empty-safe; documented inline so reviewers can confirm).
3. Pre-verified the env-var name `BOOTSTRAP_MIGRATIONS` against `doppler secrets get ... -p soleur -c {dev,prd}` — both return "secret not found" → no namespace collision.
4. Pre-verified `shellcheck 0.10.0` is on PATH on this host (already noted; now version-pinned).
5. Added a Docker-free verification path (Supabase local CLI) as fallback for hosts without Docker.
6. Confirmed ADR-023 already references the `--bootstrap=skip` flag at lines 113 and 128 — Phase 4 is a wording-softening pass only, no new content needed.

### New Considerations Discovered

- The CI invocation at `web-platform-release.yml:56` is `doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh` (no shell array splat, no nested args) — adding an arg parser is safe, the existing call passes zero positional args.
- `set -euo pipefail` already in use (line 2) — the `for arg in "$@"` loop is empty-safe under `nounset` because `$@` is special-cased by bash. No `${1-}` guard needed.
- The `--help` exit code MUST be 0 (not 2) per `getopt`/`man` convention — already in plan; called out explicitly under Risks.

## Overview

`apps/web-platform/scripts/run-migrations.sh` has a bootstrap path (the `if [[ "$row_count" -eq 0 ]]; then ... fi` block at lines 47-64; line 47 reads `row_count`, line 48 opens the conditional, line 64 closes the `fi`) that
inserts sentinel rows into `public._schema_migrations` for migrations 001-010 the
first time it sees an empty tracking table. The intent was historical: 001-010 had
been applied to the original prd Supabase project before the runner existed, so the
runner needed a way to mark them "already applied" without re-running their DDL.

On a **fresh Supabase project** (e.g., the new dev project provisioned for #2887),
the same bootstrap fires unconditionally — the table is empty for the new reason
("schema is empty too"), but the runner cannot distinguish that from the original
"schema already exists, just no tracking yet." It silently records 001-010 as
applied and only runs 011+, leaving the new project with a half-built schema.

This plan adds a `--bootstrap=skip` flag that disables the INSERT block, so a fresh
provisioning run applies all 39 migrations in filename order. Default behaviour is
unchanged — the prd CI `migrate` job still bootstraps as before, and the runner
remains a single-file shell script with no new dependencies.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| "Bootstrap code: `run-migrations.sh:50-85`" | Bootstrap conditional is lines **47-64** (line 47 captures `row_count`, line 48 opens `if`, line 64 is closing `fi`); lines 66-95 are the apply loop. | Use symbol-anchored references (`if [[ "$row_count" -eq 0 ]]`) in the plan and code comments per `cq-code-comments-symbol-anchors-not-line-numbers`. |
| "All 39 migrations apply in order" | `ls apps/web-platform/supabase/migrations/ \| wc -l` = 39 confirmed. | Use 39 as the post-condition row count when bootstrap is skipped against a fresh DB. |
| Issue title says `--bootstrap=skip` flag, body also mentions `BOOTSTRAP_MIGRATIONS=0` env var as alternative. | Both are reasonable; the flag is more discoverable from `--help` and matches CLI conventions. | Implement the flag as primary surface; accept `BOOTSTRAP_MIGRATIONS=0` env as a secondary form so CI/cron callers can opt out without changing argv. Document both in `--help`. |
| Bootstrap is documented in `supabase-migrations.md` runbook | The current runbook §0 prescribes the dev rehearsal step but does NOT mention the bootstrap behaviour or the new flag. Bootstrap is described in `ADR-023-supabase-environment-isolation.md` line 112 and the parent plan `2026-04-27-fix-supabase-env-isolation-plan.md`. | Add a §0 sub-section "First-time provisioning: skip bootstrap" to the runbook documenting the flag and the trigger condition (fresh project, empty schema). |
| Issue says "no regression for the CI `migrate` job" | CI invocation (`web-platform-release.yml` migrate job) is `doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh` — no flag passed. | Default behaviour (no flag, no env var) MUST be byte-identical bootstrap path. Verified by inspection of the diff and a grep for the CI invocation site. |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returns 0 issues.

## Hypotheses

N/A — issue is a known-cause infrastructure fix with the parent plan documenting the
exact bootstrap line range and the workaround that the flag replaces. No
network-outage or SSH triggers; Phase 1.4 firewall checklist does not apply.

## Implementation Phases

### Phase 1 — Add the `--bootstrap=skip` flag

**File:** `apps/web-platform/scripts/run-migrations.sh`

1. After the existing usage/header comment and before the `SCRIPT_DIR=` line, add a
   minimal argument parser:

   ```bash
   # Argument parsing
   bootstrap_mode="auto"  # auto = legacy bootstrap fires when table empty
   for arg in "$@"; do
     case "$arg" in
       --bootstrap=skip) bootstrap_mode="skip" ;;
       --bootstrap=auto) bootstrap_mode="auto" ;;
       --help|-h)
         cat <<'USAGE'
   Usage: run-migrations.sh [--bootstrap=skip|auto]

   Applies SQL files from supabase/migrations/ in filename order, tracking state
   in public._schema_migrations.

   Options:
     --bootstrap=auto   (default) On an empty tracking table, seed sentinel rows
                        for migrations 001-010 (assumed pre-applied on legacy prd).
                        Required for the prd CI migrate job.
     --bootstrap=skip   Disable the bootstrap seed. Use this on first-time
                        provisioning of a fresh Supabase project where 001-010
                        have NOT been applied. All 39 migrations run in order.
                        Equivalent: BOOTSTRAP_MIGRATIONS=0 bash run-migrations.sh.

   Environment:
     DATABASE_URL_POOLER  Preferred (IPv4 pooler) for CI.
     DATABASE_URL         Fallback (direct connection, IPv6).
     BOOTSTRAP_MIGRATIONS=0  Same effect as --bootstrap=skip.
   USAGE
         exit 0 ;;
       *)
         echo "::error::Unknown argument: $arg" >&2
         echo "Run with --help for usage." >&2
         exit 2 ;;
     esac
   done

   # Env-var override: BOOTSTRAP_MIGRATIONS=0 forces skip mode regardless of flag.
   # Set when CI/cron callers need to opt out without changing argv.
   if [[ "${BOOTSTRAP_MIGRATIONS:-1}" == "0" ]]; then
     bootstrap_mode="skip"
   fi
   ```

2. Wrap the existing bootstrap block (the `if [[ "$row_count" -eq 0 ]]; then ... fi`
   from current lines 48-64) with a guard on `bootstrap_mode`:

   ```bash
   row_count=$(run_sql "SELECT count(*) FROM public._schema_migrations;")
   if [[ "$row_count" -eq 0 ]]; then
     if [[ "$bootstrap_mode" == "skip" ]]; then
       echo "Empty tracking table detected — skipping bootstrap (--bootstrap=skip)."
       echo "All migrations will apply in filename order."
     else
       echo "Empty tracking table detected — bootstrapping known migrations..."
       run_sql "INSERT INTO public._schema_migrations (filename) VALUES
         ('001_initial_schema.sql'),
         ...
         ('010_tag_and_route.sql')
       ON CONFLICT (filename) DO NOTHING;"
       echo "Bootstrapped pre-existing migrations."
     fi
   fi
   ```

3. No changes to the apply loop, the tracking-table CREATE, or the
   DATABASE_URL/psql resolution. The flag's only effect is skipping the INSERT.

**Files to edit:**

- `apps/web-platform/scripts/run-migrations.sh` — add flag parsing, wrap bootstrap.

**Files to create:** none.

### Research Insights

**Bash strict-mode interactions (`set -euo pipefail` is on at line 2):**

- `for arg in "$@"; do ... done` is **empty-safe under `set -u`** — bash special-cases `"$@"` so an empty argument list expands to nothing without tripping `nounset`. No `${1-}` or `${@-}` guard needed.
- `${BOOTSTRAP_MIGRATIONS:-1}` uses the `:-` default form, which is the correct strict-mode pattern (does NOT trip `nounset` even when the var is unset). Plain `$BOOTSTRAP_MIGRATIONS` would crash under `set -u`.
- `case "$arg" in ... esac` does NOT need a wildcard `*) ;;` for empty input — the loop won't enter the body if `$@` is empty.
- `cat <<'USAGE' ... USAGE` (single-quoted heredoc) prevents `$VAR` expansion inside the help text — the right call here because the help text is static.

**Arg-parser pitfalls avoided:**

- No `getopts` — long options (`--bootstrap=skip`) require `getopt` (different tool, GNU-only) or manual parsing. Manual `case` is the simplest correct option for two flags.
- No `shift` mid-loop — the `for arg in "$@"` form iterates a snapshot, so positional shuffling isn't a concern.
- Argument-parser placed BEFORE the `command -v psql` and `DATABASE_URL` checks so `--help` works without psql installed and without DATABASE_URL set (the help-renders-without-side-effects convention).

**Idempotency reasoning:**

- The apply loop's `already_applied=$(run_sql "SELECT count(*) ...")` check is independent of the bootstrap path. After scenario-2 (skip path) runs, scenario-4 (re-run with `--bootstrap=skip`) skips all 39 because they're tracked — proving the flag does not break re-running.
- `ON CONFLICT (filename) DO NOTHING` on the bootstrap INSERT means even the legacy path is idempotent across re-runs (defense-in-depth for the case where the table is repopulated externally).

**References:**

- BashFAQ #50 on argument parsing: <https://mywiki.wooledge.org/BashFAQ/035>
- ShellCheck rules SC2086, SC2046 on quoting: already enforced by `shellcheck 0.10.0` on this host.

### Phase 2 — Verify default behaviour is unchanged (regression guard)

The prd CI `migrate` job (`.github/workflows/web-platform-release.yml`) invokes
`bash apps/web-platform/scripts/run-migrations.sh` with no arguments. The default
must be byte-equivalent to today's behaviour.

**Mechanical checks (run during work phase):**

1. `grep -n "bash apps/web-platform/scripts/run-migrations.sh" .github/workflows/web-platform-release.yml`
   — confirm no caller passes args.
2. `grep -rn "run-migrations.sh" knowledge-base/ apps/ --include='*.md' --include='*.sh' --include='*.yml'`
   — enumerate every caller to ensure none accidentally trips the new arg parser.
3. Run `shellcheck apps/web-platform/scripts/run-migrations.sh` — must exit 0.

**Functional check (run during work phase):**

Use a local ephemeral Postgres container (or local Supabase if available) to
exercise both paths. The test is shell-only — no new test framework, per
constitutional preference and the absence of `bats` in this repo.

```bash
# Start ephemeral Postgres (pin a version close to Supabase's)
docker run --rm -d --name pg-mig-test -e POSTGRES_PASSWORD=test \
  -p 55432:5432 postgres:15
sleep 3
export DATABASE_URL="postgresql://postgres:test@localhost:55432/postgres"

# Default path (legacy bootstrap fires)
bash apps/web-platform/scripts/run-migrations.sh
psql "$DATABASE_URL" -tAc "SELECT count(*) FROM public._schema_migrations;"
# Expect: 39 rows total (10 sentinel + 29 actually-applied) — same as today.
# But: tables 001-010 should DIFFER between default and skip paths
# (bootstrap leaves them un-created; skip creates them).

# Tear down and restart for skip path
docker rm -f pg-mig-test
docker run --rm -d --name pg-mig-test -e POSTGRES_PASSWORD=test \
  -p 55432:5432 postgres:15
sleep 3
bash apps/web-platform/scripts/run-migrations.sh --bootstrap=skip
psql "$DATABASE_URL" -tAc "SELECT count(*) FROM public._schema_migrations;"
# Expect: 39 rows. AND tables from 001-010 (e.g., public.users) MUST exist.

# Verify env-var equivalence
docker rm -f pg-mig-test
docker run --rm -d --name pg-mig-test -e POSTGRES_PASSWORD=test \
  -p 55432:5432 postgres:15
sleep 3
BOOTSTRAP_MIGRATIONS=0 bash apps/web-platform/scripts/run-migrations.sh
psql "$DATABASE_URL" -tAc "SELECT count(*) FROM public._schema_migrations;"
# Expect: same as --bootstrap=skip.

docker rm -f pg-mig-test
```

The verification commands belong in the work-phase commit log (or a transient
verify script under `apps/web-platform/scripts/`) — they are not committed as a
permanent test because there is no existing bash-test framework in this repo and
adding one is out of scope for #2911.

**Docker-free fallback (if the work-phase host does not have Docker):**

If `command -v docker` returns nothing, use `supabase start` (Supabase local CLI)
which provisions a local Postgres on `localhost:54322` with `postgres:postgres` creds.
Set `DATABASE_URL=postgresql://postgres:postgres@localhost:54322/postgres` and run the
same three scenarios. `supabase stop --no-backup` cleans up.

If neither Docker nor the Supabase CLI is available, the dev Doppler config can be
used as a soft-verify (since `soleur-dev` is now a fresh isolated project per #2887):
`doppler run -p soleur -c dev -- bash apps/web-platform/scripts/run-migrations.sh --bootstrap=skip`
— this is the operator-runbook flow and exercises the production code path. It
does mutate dev state, so coordinate with the #2887 follow-up sequence.

### Research Insights

**Industry pattern — flag-then-env-var precedence:**

Most CLI tools (kubectl, docker, terraform) treat env vars as defaults and
explicit flags as overrides. This plan inverts that for one specific reason: the
env var here is an **opt-out** for callers that cannot change argv (cron, container
ENTRYPOINT). When `BOOTSTRAP_MIGRATIONS=0` is set, it forces skip mode regardless of
flag — there's no scenario where the operator wants both `BOOTSTRAP_MIGRATIONS=0`
AND `--bootstrap=auto` (that would be a typo/contradiction).

If we want the more conventional "flag wins" precedence, the parser needs a
"was the flag explicitly passed" sentinel — adds complexity for a case that does
not arise. Documented as intentional.

**Edge case — `--bootstrap=` with no value:**

`case "$arg" in --bootstrap=*) ...` would match `--bootstrap=` (empty value) and
fall through to the unknown-arg branch via the trailing `*)` only if structured
correctly. The plan's `case` uses literal matches (`--bootstrap=skip` and
`--bootstrap=auto`), so `--bootstrap=` falls through to the unknown branch, exits
2, prints the hint. Correct behaviour — verified mentally; will be confirmed by
test scenario 6.

### Phase 3 — Document the flag in the runbook

**File:** `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`

Add a sub-section to §0 (between the existing "Apply Order: dev FIRST, then prd"
and the "Pre-deploy Checklist"):

```markdown
### First-time provisioning: skip bootstrap

`run-migrations.sh` has a legacy bootstrap that inserts sentinel rows for
migrations 001-010 the first time it sees an empty `_schema_migrations`
table. This was correct for the original prd, where 001-010 had been
applied via psql before the runner existed.

**On a fresh Supabase project (e.g., a new dev/staging project), pass
`--bootstrap=skip`:**

```bash
cd apps/web-platform
doppler run -p soleur -c dev -- bash scripts/run-migrations.sh --bootstrap=skip
```

The flag disables the sentinel INSERT so all 39 migrations apply in
filename order against the empty schema. Trigger condition: any new
Supabase project ref that has never had its DDL applied.

The CI `migrate` job in `web-platform-release.yml` runs without the flag
(default `auto` mode) — prd's bootstrap is still required because 001-010
were applied pre-runner.

`BOOTSTRAP_MIGRATIONS=0` is an equivalent env-var form for callers that
cannot easily change argv (cron, container ENTRYPOINT).
```

**Files to edit:**

- `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` — add sub-section.

### Phase 4 — Update ADR-023 cross-reference (deepen-verified: optional)

**File:** `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md`

ADR-023 already references the `--bootstrap=skip` flag at lines 113 (in a parenthetical
note about the bootstrap trap) and 128 (in the "Follow-up issues" cross-reference).
Both references frame the flag as the resolution path for the bootstrap-trap concern.

The current wording does not need a structural change — but at ship time, the PR
number can be added as a sibling reference next to issue #2911 (e.g.,
`#2911 (PR #N)`). This is cosmetic; if the PR number injection is non-trivial at
ship, defer to a small follow-up commit on main rather than blocking #2911 on it.

**Files to edit (deepen-pass classification):**

- `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md` — optional cosmetic PR-ref injection at ship time. Skip if friction.

## Files to Edit

- `apps/web-platform/scripts/run-migrations.sh` (Phase 1)
- `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` (Phase 3)
- `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md` (Phase 4)

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash apps/web-platform/scripts/run-migrations.sh --help` prints usage with both `--bootstrap=auto` and `--bootstrap=skip` documented and `BOOTSTRAP_MIGRATIONS=0` named.
- [ ] `bash apps/web-platform/scripts/run-migrations.sh --unknown-flag` exits with code 2 and a usage hint (no silent acceptance of typos).
- [ ] `shellcheck apps/web-platform/scripts/run-migrations.sh` exits 0.
- [ ] Diff against current main shows the apply loop unchanged — only the bootstrap block is wrapped and a flag parser is prepended.
- [ ] `grep -rn "run-migrations.sh" .github/workflows/` shows the CI `migrate` invocation has NOT been changed (still `bash apps/web-platform/scripts/run-migrations.sh` with no args).
- [ ] Local docker-postgres verification (Phase 2 functional check) shows: default path produces 39 rows + bootstrap-style schema (no 001-010 tables); `--bootstrap=skip` path produces 39 rows + full schema including 001-010 tables; `BOOTSTRAP_MIGRATIONS=0` produces the same result as `--bootstrap=skip`.
- [ ] Runbook update lands in same PR; the §0 sub-section names the flag, the trigger condition, and the env-var form.
- [ ] PR body uses `Closes #2911`.
- [ ] `bash apps/web-platform/scripts/run-migrations.sh --help` exits 0 even when `DATABASE_URL` is unset (verifies argument-parser runs before the env-check block).
- [ ] `bash apps/web-platform/scripts/run-migrations.sh --bootstrap=` (empty value) exits 2 (verified by test scenario 8).

### Post-merge (operator)

- [ ] After merge, prd CI `migrate` job runs successfully on the post-merge release workflow (verifies default behaviour with no args).
- [ ] When the next fresh Supabase project is provisioned (e.g., a staging project for #2910), `--bootstrap=skip` is used per the runbook and `_schema_migrations` row count = 39 with all tables present.
- [ ] ADR-023 cross-reference updated post-merge with PR number (Phase 4).

## Test Scenarios

Bash-only verification (no new test framework — see Sharp Edges note in plan skill).
Manual verification scripts run during work phase against ephemeral local Postgres:

1. **Default = legacy bootstrap.** Empty DB → run with no args → bootstrap fires →
   001-010 sentinels inserted → 011+ apply → 39 rows in `_schema_migrations`,
   public.users etc. NOT created (bootstrap skipped 001-010 DDL).
2. **`--bootstrap=skip` = full apply.** Empty DB → run with `--bootstrap=skip` →
   bootstrap skipped → all 39 files apply → 39 rows + full schema.
3. **`BOOTSTRAP_MIGRATIONS=0` = full apply.** Empty DB → run with env var → same
   result as scenario 2.
4. **Idempotent re-run with flag.** Run scenario 2, then re-run with
   `--bootstrap=skip` → 0 applied, 39 skipped (loop's `already_applied` check
   handles this independently of bootstrap mode).
5. **Idempotent re-run without flag.** After scenario 1, re-run with no args → 0
   applied, 39 skipped (table not empty → bootstrap branch not taken).
6. **Unknown flag rejected.** `--bootstrap=lol` → exit 2, usage hint, no DB writes.
7. **Argument-parser does not break existing CI invocation.** `bash run-migrations.sh`
   (no args) parses as `bootstrap_mode=auto` → identical to today's behaviour.
8. **Empty value rejected.** `--bootstrap=` (trailing equals, no value) → exit 2,
   usage hint, no DB writes. Same path as scenario 6.
9. **`--help` works without env.** `bash run-migrations.sh --help` (no
   `DATABASE_URL` set, no `psql` on PATH) → prints usage and exits 0. Confirms
   help-renders-without-side-effects.

## Risks

- **Risk:** Adding argv parsing to a script that previously took no arguments could
  silently swallow a future caller that passes a different flag. **Mitigation:**
  unknown-arg branch exits 2 with a hint (test scenario 6).
- **Risk:** Env-var form (`BOOTSTRAP_MIGRATIONS=0`) collides with a hypothetical
  CI environment that already exports a value. **Mitigation:** verified at deepen
  time — `doppler secrets get BOOTSTRAP_MIGRATIONS -p soleur -c prd --plain` and
  `... -c dev --plain` both return `Could not find requested secret:
  BOOTSTRAP_MIGRATIONS`. Also greped repo for `BOOTSTRAP_MIGRATIONS` across `*.sh`,
  `*.yml`, `*.ts`, `*.json` — only references are this plan and the script being
  modified. No collision.
- **Risk:** Operator forgets the flag on a future fresh-project provision and
  silently half-builds a schema (the original problem). **Mitigation:** runbook §0
  sub-section names the trigger condition explicitly; preflight Check 4
  (`hr-dev-prd-distinct-supabase-projects`) already enforces distinct project refs,
  so a fresh project is the only state where the flag matters.
- **Risk:** A future caller (e.g., a test seed script) reads the script's exit code
  on `--help` and breaks. **Mitigation:** `--help` exits 0 (matches `man`/`getopt`
  convention). Documented in usage block.

## Non-Goals / Out of Scope

- Changing the legacy bootstrap list (001-010). The frozen list remains correct for
  the original prd; only fresh provisioning skips it.
- Auto-detecting "fresh project" without the flag. Heuristics (e.g., "no public
  tables exist") were considered and rejected — too fragile, hides a deliberate
  choice that should be visible in the operator's command line.
- Adding a bash test framework (`bats`, `bash-spec`). No existing infrastructure;
  out of scope for a 1-flag fix per `cq-tests-and-fixtures-must-be-pinned-pre-merge`
  (verify framework is installed before prescribing).
- Migrating CI to `--bootstrap=skip`. Production's history requires `auto`.

## Dependencies / Pre-requisites

- None. The script is self-contained and the flag does not change any external
  contract (DATABASE_URL, doppler config, CI workflow).

## Roll-back Plan

If the flag introduces a regression (e.g., the arg parser malfunctions on the CI
default path), revert the PR. The flag has no DB-side state; reverting restores
the prior single-path script.

## Domain Review

**Domains relevant:** Engineering (CTO).

This is a single-script infrastructure fix in the data-layer/CI domain.
- **Product (CPO):** not relevant — no user-facing surface change.
- **CMO/CRO/COO:** not relevant — no marketing, conversion, or expense impact.
- **Security:** marginally relevant only as risk-reduction (the bootstrap bug
  could leave a fresh project with a half-built schema); the fix does not change
  the security model. No dedicated CISO review needed; the work-phase shellcheck
  pass and the verification scenarios are sufficient.

No Product/UX Gate (NONE tier) — the change has no UI surface, no new component
files, and no `app/**/page.tsx` or `components/**/*.tsx` paths.

## Notes / Sharp Edges

- **Symbol-anchored references.** Plan and code comments reference the bootstrap
  block by the conditional (`if [[ "$row_count" -eq 0 ]]`) rather than line
  numbers, per `cq-code-comments-symbol-anchors-not-line-numbers`.
- **Bash test framework absent.** Per `## Sharp Edges` in plan-skill ("verify
  framework is actually installed"), no `bats` is installed and no existing
  `*.bats` / `*_test.sh` convention exists in this repo. Verification is
  shell-script-driven during work phase, not a permanent committed test. If a
  future PR formalizes a `tests/scripts/` convention, the verification commands
  here can be promoted at that time.
- **CLI verification gate.** Embedded CLI invocations:
  - `psql ... --no-psqlrc --set ON_ERROR_STOP=1` — pattern reused verbatim from the
    existing `run-migrations.sh:33` (already exercised by every CI run).
  - `shellcheck` — `shellcheck --version` confirms presence at `~/.local/bin/shellcheck`
    on this host. <!-- verified: 2026-04-27 source: shellcheck --version -->
  - `docker run postgres:15` — standard Docker Hub image; no Soleur-specific tooling.
  - `doppler run -p soleur -c prd -- bash scripts/run-migrations.sh` — already in
    runbook and CI; not new.
  No new CLI tokens introduced into user-facing docs; the runbook addition reuses
  existing tokens already exercised by the prior runbook content.
- **Closes vs Ref.** Issue #2911 is a code-only fix executed pre-merge (the runbook
  edit ships in the same PR). `Closes #2911` in the PR body is correct — there is
  no post-merge operator action that would invalidate auto-close. ADR-023 update is
  cosmetic and does not gate the issue close.

## References

- Parent: #2887 (dev/prd Supabase isolation P0)
- Parent plan: `knowledge-base/project/plans/2026-04-27-fix-supabase-env-isolation-plan.md`
- Bootstrap code: `apps/web-platform/scripts/run-migrations.sh` (block guarded by `if [[ "$row_count" -eq 0 ]]`)
- Runbook: `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md`
- Related learning: `knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md`
