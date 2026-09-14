# Decision challenges — feat-one-shot-8028-supabase-pat-retire

Decisions taken headlessly during `/plan` (plan review + advisor consult) that go against
the operator's stated direction or that reviewers recommended and the plan declined.
Recorded per ADR-084 so they are auditable outside this session; `ship` Phase 6 renders
this into the PR body under `## Model Dissents (informational)`.

---

## DC-1 — Dev CI gets no Management-API credential (declines both operator-offered arms)

**Date:** 2026-09-13
**Classification:** User-Challenge (the pipeline brief offered exactly two arms for dev; the plan takes neither)
**Status:** open — decided in the plan, awaiting operator acknowledgement at ship time

**Operator's stated direction.** "dev currently lacks it per the issue table — decide what the
script should do in dev: fail loudly, or the plan must add the token to dev via the Doppler
CLI from the existing prd value — pick one and justify."

**What the plan does instead.** Dev CI (`.github/workflows/tenant-integration.yml`, "Apply
migrations to dev") keeps the script's absence-soak: `SUPABASE_ACCESS_TOKEN` is not set there,
the reload hook exits 0 with a `::notice::… is not set` (absence is informational, never a warning), and PostgREST's ~10-minute natural
poll remains the fallback — the operating state since the PAT died. Operators running the
script by hand against dev read the token on demand from Doppler `prd_terraform` (the
`scripts/rotate-supabase-db-credential.sh` precedent), which `--help` documents.

**Why neither arm.** `tenant-integration.yml` triggers on `pull_request` with the PR's merge
ref checked out, so PR-authored migration SQL and shell run inside that job. `SUPABASE_ACCESS_TOKEN`
is account-scoped: it can `POST /v1/projects/{prd-ref}/database/query` (arbitrary SQL on prd).
Copying it into Doppler `dev`/`dev_scheduled` hands it to that job (the job reads
`dev_scheduled`); injecting the GH secret as step env (plan v1) does the same. Every existing
consumer of `secrets.SUPABASE_ACCESS_TOKEN` is `push`/`schedule`/`workflow_dispatch`-only for
this reason, and Supabase exposes no project-scoped Management-API credential to narrow to
(`apps/web-platform/infra/variables.tf`). "Fail loudly on absence" would red every
migration-carrying PR for a credential CI must not hold; the issue's "fail loudly" is about a
*present* dead token, which the plan does make loud. Raised as a P0 by
`architecture-strategist` at plan review; `hr-dev-prd-distinct-supabase-projects`.

**Cost accepted.** PGRST205 flakes in dev tenant-integration tests after a PR applies a new
table remain possible for ≤10 min — unchanged from today.

**Reopen trigger.** Supabase ships a project-scoped Management-API token, or
`tenant-integration.yml` stops running on `pull_request`.

---

## DC-2 — Soft-fail policy stays in the script's `--best-effort` flag (DHH recommendation not applied)

**Date:** 2026-09-13
**Classification:** Taste

DHH (plan review P1): "a flag named best-effort that exits 2 is a contradiction"; move the
policy into `run-migrations.sh` (skip the hook when token/URL unset, soak rc 1, propagate rc 2)
and delete `--best-effort`/`fail_or_skip`. Not applied: it deletes a documented flag, rewrites
T2/T8, and duplicates the script's preconditions in the caller for the same P2 outcome. The
narrower change (one hard arm for a JSON-bodied 401/403, documented in `--help` as the
flag's single exception) is the smaller diff. Revisit if a second caller of the script appears.

---

## DC-3 — No retry before classifying a non-2xx (spec-flow / architecture recommendation not applied)

**Date:** 2026-09-13
**Classification:** Taste

Both correctness reviewers suggested one retry (~5 s) before treating a 401/403 as durable,
citing edge/WAF 403s and the `000` probe flake seen during planning. Applied instead: a
401/403 whose body is not a Management-API JSON error is classified transient (soaked under
`--best-effort`, exit 1 strict), and the runner now invokes the hook on every migration run so
a transient JSON-bodied rejection costs one job re-run that reloads. A retry loop inside a
15-second best-effort hook was judged machinery for a case the body discrimination already
narrows. Revisit if a JSON-bodied transient 403 is ever observed.

---

## DC-4 — Runbook / secret-scanning / learning doc edits stay on the critical path (DHH recommendation not applied)

**Date:** 2026-09-13
**Classification:** Taste

DHH: the `secret-scanning.md` fan-out rewrite and the dated learning annotation are
nice-to-have and belong in `compound`. Kept: the COO's Operations assessment asked for the
rotation-runbook fan-out (P1 there), and the 2026-05-21 learning's §Prevention 3 is
runbook-shaped and instructs minting the very token this plan retires — leaving it would
re-create the defect on the next reader. Each is a one-line edit with a grep AC.
