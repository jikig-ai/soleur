---
title: "Fail-loud on Sentry POST failures from ci-deploy.sh (D-6)"
issue: 6475
branch: feat-one-shot-6475-ci-deploy-sentry-fail-loud
type: feat
lane: single-domain
brand_survival_threshold: none
date: 2026-07-18
---

# Fail-loud on Sentry POST failures from ci-deploy.sh (D-6) — #6475 Item 2

> No `spec.md` present (one-shot pipeline: plan precedes spec). `lane:` set to
> `single-domain` — this is a single-domain (engineering / CI-infra observability)
> change: one follow-through probe script plus a tracker enrollment.

## Overview

`ci-deploy.sh` emits best-effort Sentry events at eight fallback/degraded-state
sites (CRON_DRAIN timeout, SANDBOX_CANARY fail, IMAGE_VERIFY, IMAGE_PULL,
IMAGE_PULL_RECOVERY, ZOT_GATE, …). Each POST is fail-open (`curl … --max-time 10`
followed by `|| logger -t "$LOG_TAG" "<TAG>: Sentry POST failed"`). This is
**correct** on-host behaviour — a deploy must never abort because Sentry
telemetry is unreachable — but it means the *failure of the alarm path itself*
is journald-only. Per `hr-no-ssh-fallback-in-runbooks`, nobody reads a host's
journald, so a Sentry POST failure during a **real** fallback event is silently
unalarmed. D-6 closes that blind spot by making the POST-failure signal
**loud**: actively queried on a schedule and surfaced onto a tracker issue.

**The mechanism is already 90% wired.** The eight emitters already `logger -t
"$LOG_TAG"` with `LOG_TAG="ci-deploy"`, and `ci-deploy` is **already** in
`apps/web-platform/infra/vector.toml` Source 4
(`host_scripts_journald`) SYSLOG_IDENTIFIER allowlist — so every "Sentry POST
failed" line **already ships to Better Stack Logs** (source 2457081, ClickHouse
SQL-queryable via `scripts/betterstack-query.sh`). What is missing is the
*active query + alarm*: a scheduled poller that fails loud when such a line
appears. The repo already has the exact substrate for this — the
`scripts/followthroughs/*.sh` + `scheduled-followthrough-sweeper.yml` pattern,
which the sweeper's **exit-1 = comment + leave-open** branch turns into a loud
alarm on a tracker issue.

This is a **Soak-shaped follow-through** (per
`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
§Trigger→verification mapping): *"the ci-deploy Sentry-POST-failure rate stays
at ~0 for N days"*. Zero POST-failure lines over the soak window → PASS (exit 0)
→ sweeper closes #6475 (both items resolved; Item 1 done via #6458). A POST
failure appearing in the window → **FAIL (exit 1) → sweeper comments #6475 and
leaves it open** = the fail-loud alarm. Any query/auth failure or absent
liveness → TRANSIENT (exit 2) → retry next sweep, never a false close.

Deliverable: **one new probe script + tracker enrollment.** No on-host
`ci-deploy.sh` change (the emit→ship path is already live and the fail-open POST
is deliberate), no new secret (the `BETTERSTACK_QUERY_*` creds are already in the
sweeper env), no Terraform, no ADR/C4 change.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6475 Item 2) | Reality (verified on this branch) | Plan response |
|---|---|---|
| "the earlier design was fabricated — an initial draft proposed a route that does not exist" | Confirmed anti-pattern: a Sentry-*query* probe would PASS vacuously, because a **failed** Sentry POST never reaches Sentry. The only queryable sink for the POST-failure line is Better Stack (journald→Vector), mirroring the exact `#5934` lesson recorded in `chardevice-wedge-nonrecurrence-5934.sh`. | Probe queries **Better Stack**, never Sentry. Documented in-script + here. |
| "the real mechanism is `scripts/followthroughs/*.sh` + `scheduled-followthrough-sweeper.yml`" | Confirmed. Sweeper wires `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` already (added for `#5934`/`#5110`). | Build the probe on this substrate; no workflow env change. |
| Sentry POST failures are "journald-only" | Partly stale: the line is journald-only *for paging*, but `ci-deploy` **is** in `vector.toml` Source 4 allowlist, so it already lands in Better Stack Logs. The gap is the *active query*, not the shipping. | No on-host change; build only the poller. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is an
internal CI/infra observability watchdog with no user-facing surface. The worst
failure mode is the *status quo* (a Sentry POST failure stays unalarmed), i.e.
no regression versus today.

**If this leaks, the user's data is exposed via:** N/A — the probe reads
operational CI journald log lines (`"<TAG>: Sentry POST failed"`) from Better
Stack Logs; it handles no user data, PII, secrets, or workflow content. Better
Stack creds are read-only ClickHouse query creds already provisioned.

**Brand-survival threshold:** none. `threshold: none, reason: internal CI-infra
observability probe — no user-facing surface, no regulated-data path, no
sensitive-path file (scripts/followthroughs/*.sh is not schema/migration/auth/API/.sql).`

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Confirm the eight emitter fallback lines still share the greppable marker and
tag:
`grep -n '|| logger -t "\$LOG_TAG"' apps/web-platform/infra/ci-deploy.sh` — expect
the 7 "Sentry POST failed" lines (437, 517, 541, 609, 635, 666, 1157) plus the
non-Sentry lease line (2596, out of scope). Confirm `readonly LOG_TAG="ci-deploy"`.

0.2 Confirm `ci-deploy` is in `vector.toml` Source 4 allowlist:
`grep -n '"ci-deploy"' apps/web-platform/infra/vector.toml` (expect the
`host_scripts_journald` `include_matches.SYSLOG_IDENTIFIER` block).

0.3 Confirm sweeper already exports the Better Stack query creds:
`grep -n 'BETTERSTACK_QUERY_' .github/workflows/scheduled-followthrough-sweeper.yml`
(expect HOST/USERNAME/PASSWORD). No workflow edit needed.

0.4 Confirm `betterstack-query.sh` raw-SQL mode is available for AND-scoping
(`--grep` is OR-only): read `scripts/betterstack-query.sh` mode-1 branch
(`^[[:space:]]*(SELECT|WITH|SHOW)` gate) and the `$BS_TABLE` / `$BS_TABLE_S3`
substitution tokens.

### Phase 1 — Write the follow-through probe (RED then GREEN)

Create `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh`, structurally
mirroring `chardevice-wedge-nonrecurrence-5934.sh` (Better Stack query +
liveness gate + fail-safe TRANSIENT). Contract:

- **Query (AND-scoped, raw-SQL mode)** — count Better Stack rows over the soak
  window where the raw journald payload contains BOTH the `ci-deploy` identifier
  AND the marker. Use `betterstack-query.sh` mode-1 with the `$BS_TABLE` /
  `$BS_TABLE_S3` tokens and a UNION-ALL hot+archive body (so a multi-day window
  isn't silently truncated to the ~40-min hot window):

  ```sql
  SELECT dt, raw FROM (
    SELECT dt, raw FROM remote($BS_TABLE)
      WHERE dt >= now() - INTERVAL <N> DAY
        AND raw LIKE '%SYSLOG_IDENTIFIER":"ci-deploy%'
        AND raw LIKE '%Sentry POST failed%'
    UNION ALL
    SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3)
      WHERE _row_type = 1 AND dt >= now() - INTERVAL <N> DAY
        AND raw LIKE '%SYSLOG_IDENTIFIER":"ci-deploy%'
        AND raw LIKE '%Sentry POST failed%'
  ) ORDER BY dt DESC LIMIT 200 FORMAT JSONEachRow
  ```

  (Phase 1 verifies the exact `SYSLOG_IDENTIFIER` field spelling in `raw` against
  one real Better Stack row before freezing the LIKE; if the field is not
  literally `SYSLOG_IDENTIFIER":"ci-deploy`, fall back to `--grep "Sentry POST
  failed"` mode-2 + a post-filter `grep 'ci-deploy'` on the JSONEachRow output,
  as `chardevice`'s `denied_count()` does.)

- **Liveness gate (fail-safe against vacuous PASS, per convention #5934 lesson):**
  a separate query counts *any* `ci-deploy` rows in the window (proof the
  emit→Better-Stack path is live and deploys occurred). If zero `ci-deploy` rows
  → **TRANSIENT (exit 2)** ("no ci-deploy activity observed in window;
  inconclusive"), NOT PASS — a dark Vector/journald or a quiet deploy period must
  never read as "zero POST failures".

- **Exit semantics** (`sweep-followthroughs.sh` contract):
  - `0 = PASS` — liveness ≥ 1 ci-deploy row AND zero POST-failure rows → sweeper closes #6475.
  - `1 = FAIL` — ≥ 1 POST-failure row → **the fail-loud alarm** (sweeper comments #6475, leaves open); print the offending `dt`/`raw` lines (last-4KB captured as the comment).
  - `2 = TRANSIENT` — any query/auth/network failure, unparseable count, OR zero-liveness → retry next sweep.

- **Guards (per convention):** `set -uo pipefail`; NO `: "${VAR:?}"` gate (that
  aborts with status 1 = FAIL under non-interactive shell) — use
  `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: …" >&2; exit 2; fi` for the
  `BETTERSTACK_QUERY_*` presence check (or delegate to `betterstack-query.sh`'s
  own exit-3 and map non-zero → exit 2). Window overridable via
  `CI_DEPLOY_SENTRY_SOAK_WINDOW` (default `7d`, validated `^[0-9]+[hmd]$`).

`chmod +x` the script.

### Phase 2 — Probe unit tests

Create `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh` mirroring
`chardevice-wedge-nonrecurrence-5934` /`hostname-mislabel-web1-6616` test style
(stub `betterstack-query.sh` via a PATH shim / `BQ` override; assert exit codes):

- POST-failure row present + liveness present → exit 1 (FAIL, loud). **Load-bearing**: this is the alarm.
- Zero POST-failure rows + liveness present → exit 0 (PASS).
- Zero liveness rows → exit 2 (TRANSIENT), never PASS.
- `betterstack-query.sh` non-zero / unreachable → exit 2 (TRANSIENT).
- Empty/unset `BETTERSTACK_QUERY_*` → exit 2 (TRANSIENT), never exit 1.
- Invalid `CI_DEPLOY_SENTRY_SOAK_WINDOW` → exit 2.

Register in the followthrough test convention (whatever `test-all.sh` /
`validate-vector-config`-adjacent harness discovers `scripts/followthroughs/*.test.sh`;
confirm discovery in Phase 0).

### Phase 3 — Enroll #6475 as the follow-through tracker (no operator step)

3.1 Add the directive to the #6475 body (via `gh issue edit`, automatable — not
an operator step). Place inline anywhere:

```html
<!-- soleur:followthrough
  script=scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh
  earliest=<merge-date + 7d, UTC ISO-8601>
  secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD
-->
```

3.2 Add the `follow-through` label to #6475 (`gh issue edit 6475 --add-label
follow-through`). The `.claude/hooks/follow-through-directive-gate.sh` + sweeper
require the `script=` path to exist + be executable on disk *before* the directive
is honored — it does (lands in this PR's branch, and the sweeper checks out the
merged tree).

3.3 The PR body uses **`Ref #6475`, NOT `Closes #6475`** — closure is deferred to
the soak PASS (the sweeper closes it), matching the ops-remediation
`Ref-not-Closes` pattern. `earliest = merge + 7d` gives one clean soak window of
production ci-deploy activity before the first verdict.

## Files to Create

- `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` — the Better Stack POST-failure soak probe.
- `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh` — exit-code unit tests.

## Files to Edit

- **GitHub issue #6475 body + labels** (via `gh issue edit`, in Phase 3) — add the `soleur:followthrough` directive + `follow-through` label. (Not a repo file; a tracker-state edit performed by /work or /ship, automatable.)
- No repo source file is edited. `ci-deploy.sh`, `vector.toml`, and `scheduled-followthrough-sweeper.yml` are **unchanged** (already wired — see Overview).

## Open Code-Review Overlap

One open code-review issue touches `ci-deploy`: **#3053** (review: empty-mount
window during ci-deploy seed). **Disposition: Acknowledge** — different concern
(a seed-time mount race), no file overlap (this plan edits no `ci-deploy.sh`
line), remains open on its own cycle.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` exists, is executable (`test -x`), and `bash -n` parses clean.
- [ ] AC2 — The probe queries **Better Stack** and **never Sentry**: `grep -c 'sentry\.io\|SENTRY_AUTH_TOKEN\|/api/0/' scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` returns 0; `grep -c 'betterstack-query.sh' …` returns ≥ 1.
- [ ] AC3 — The probe has NO `: "${VAR:?}"` exit-gate: `grep -cE ':\s*"\$\{[A-Z_]+:\?' scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` returns 0.
- [ ] AC4 — Query is AND-scoped to the ci-deploy identifier: the SQL/post-filter references BOTH `ci-deploy` and `Sentry POST failed` (assert via grep for both literals in the script).
- [ ] AC5 — `bash scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh` exits 0 (all six exit-code cases pass, including the FAIL=1 alarm case and zero-liveness=2 fail-safe case).
- [ ] AC6 — `#6475` carries the `follow-through` label AND a `soleur:followthrough` directive whose `script=` is the new path and `secrets=` names the three `BETTERSTACK_QUERY_*` names: `gh issue view 6475 --json labels,body` shape check. (Verify the sweeper already exports those three: `grep -c 'BETTERSTACK_QUERY_' .github/workflows/scheduled-followthrough-sweeper.yml` ≥ 3 — no workflow edit expected.)
- [ ] AC7 — PR body says `Ref #6475` (NOT `Closes #6475`): closure is the sweeper's job on soak PASS.

### Post-merge (operator — automatable, no SSH)

- [ ] AC8 — Dry-run the sweeper against #6475: `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true` then confirm the run parsed #6475's directive and executed the probe (TRANSIENT expected before `earliest`, or a real verdict after). `Automation: gh CLI` — no operator judgement.
- [ ] AC9 — Discoverability (no SSH): `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 7d --grep "Sentry POST failed"` returns rows-or-empty (proves the sink is queryable end-to-end). `Automation: doppler + betterstack-query.sh`.

## Observability

```yaml
liveness_signal:
  what: "≥1 SYSLOG_IDENTIFIER=ci-deploy row in Better Stack Logs over the soak window (proof the emit→Vector→Better Stack path is live and deploys ran)"
  cadence: "checked each daily sweep (0 18 * * * UTC) once now >= earliest"
  alert_target: "zero-liveness → probe exits 2 (TRANSIENT); #6475 stays open, never false-closes"
  configured_in: "scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh (liveness gate) + scheduled-followthrough-sweeper.yml"
error_reporting:
  destination: "GitHub issue #6475 comment (sweeper posts last-4KB of probe stderr/stdout on exit 1)"
  fail_loud: true   # exit 1 = comment + leave-open = the D-6 alarm; the whole feature IS the fail-loud path
failure_modes:
  - mode: "ci-deploy Sentry POST failed during a real fallback event"
    detection: "betterstack-query over Better Stack Logs for raw LIKE ci-deploy AND 'Sentry POST failed' (in-repo GH-cron poll, ADR-096 pattern — not a native Better Stack alert)"
    alert_route: "probe exit 1 → sweeper comments #6475 (issues:write), leaves open"
  - mode: "Better Stack query unreachable / auth failure / creds unset"
    detection: "betterstack-query.sh non-zero OR empty BETTERSTACK_QUERY_* → probe exit 2"
    alert_route: "TRANSIENT — retry next sweep; #6475 stays open (can never false-close)"
  - mode: "emit→Better Stack path dark (Vector/journald down) or no deploys in window"
    detection: "zero ci-deploy liveness rows → probe exit 2"
    alert_route: "TRANSIENT — inconclusive, never PASS"
logs:
  where: "sweeper run logs in GitHub Actions (Scheduled: Follow-Through Sweeper); the underlying ci-deploy 'Sentry POST failed' lines in Better Stack Logs source 2457081"
  retention: "GitHub Actions default; Better Stack Logs per source retention (hot ~40min + s3 archive)"
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 7d --grep 'Sentry POST failed'"
  expected_output: "JSONEachRow rows (if any POST failures occurred) or empty (clean) — proves the sink is queryable with NO ssh"
```

### Soak Follow-Through Enrollment

This plan's **primary deliverable IS the soak follow-through** (not a side
gate). Enrollment fields:

- **Script:** `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` — exit 0 when the soak holds (zero POST-failure rows + liveness), 1 on any POST-failure row (fail-loud), 2 on transient/no-liveness. Mirrors `chardevice-wedge-nonrecurrence-5934.sh` (Better Stack + liveness + fail-safe), not the Sentry-query `reconcile-ff-only-sentry-4977.sh` (D-6's signal never reaches Sentry).
- **Directive:** `<!-- soleur:followthrough script=scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh earliest=<merge+7d UTC> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` on #6475 + `follow-through` label.
- **New `secrets=` to wire into `scheduled-followthrough-sweeper.yml`:** none — `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` are already in the sweeper `env:` (added for #5934/#5110). Verified in Phase 0.3.

## Domain Review

**Domains relevant:** none

No cross-domain (product / marketing / sales / finance / legal / ops / support)
implications — infrastructure/tooling observability change. Engineering (CTO)
lens is the plan author's; no business-domain leader spawn warranted.

## Architecture Decision (ADR/C4)

**No ADR, no C4 change.** This applies an existing, ADR-documented pattern
(follow-through soak probe polling Better Stack Logs — ADR-096, "log-content
recurrence alarms are in-repo GH-cron pollers, not native Better Stack alerts")
to a new signal. C4 completeness enumeration (read against
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors:** none new (founder already the paging endpoint via existing edges).
- **External systems:** `betterstack` (system, `model.c4:266`) and `sentry` (`model.c4:273`) already modeled; the GitHub-Actions sweeper is the existing `github` system.
- **Containers / data stores:** none new (Better Stack Logs source 2457081 already modeled).
- **Access relationships:** the exact edge already exists — `github -> betterstack` "…the follow-through soak probes poll [Better Stack Logs] (ClickHouse SQL via betterstack-query.sh)" (`model.c4:429/433`); ci-deploy journald→Better Stack is `hetzner -> betterstack` (`model.c4:404`). This plan adds one *instance* of an already-modeled edge, not a new edge.

No element/edge/description is falsified by this change → no `.c4` edit.

## Test Scenarios

Covered by Phase 2 unit tests (exit-code matrix). Integration confidence comes
from AC8 (dry-run sweep parses + runs the probe) and AC9 (live betterstack-query
end-to-end). No prod-write, no synthetic users, read-only throughout.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Native Better Stack log-based alert (Terraform `betteruptime_*` on the log content) | Per ADR-096, Soleur deliberately uses in-repo GH-cron pollers for log-content recurrence alarms, not native Better Stack alerts. The issue explicitly names the follow-through mechanism. Deferring the native-alert option keeps scope minimal and consistent. |
| A second Sentry POST on failure (retry to a different DSN) | Pointless: the failure mode is Sentry being unreachable; a second Sentry POST fails identically. Better Stack is the independent second-source sink (`model.c4`: the redundancy is by design). |
| Make the on-host POST fail-*closed* (abort deploy) | Wrong. A deploy must not depend on Sentry availability; fail-open is deliberate. D-6 is about *observing* the failure, not blocking on it. |
| A standalone scheduled workflow (not a follow-through) | The follow-through substrate already exists, already wires the creds, and gives auto-close on clean soak + loud comment on failure for free. A bespoke workflow re-implements all of that. |
| Enroll a NEW tracker instead of #6475 | #6475's only remaining open item IS D-6 (Item 1 done via #6458); enrolling #6475 directly means the soak PASS closes it cleanly. |

## Sharp Edges

- **Query the sink the signal actually reaches.** A **failed** Sentry POST never
  arrives at Sentry — querying Sentry would PASS vacuously and auto-close #6475
  blind (the exact `#5934` trap in the convention). The probe MUST query Better
  Stack. Verify the `SYSLOG_IDENTIFIER` field spelling in a real `raw` row before
  freezing the LIKE clause.
- **Liveness gate is load-bearing.** Without requiring ≥1 `ci-deploy` liveness
  row, a dark Vector/journald or a deploy-free window reads as "zero POST
  failures" → false PASS + auto-close. Zero-liveness → TRANSIENT, never PASS.
- **No `: "${VAR:?}"` exit-gate.** Under the sweeper's non-interactive shell it
  aborts with status 1 (= FAIL = loud alarm on a green codebase). Use an explicit
  `if [[ -z … ]]; then exit 2; fi`.
- **`Ref #6475`, not `Closes #6475`.** `Closes` auto-closes at merge, *before* the
  soak runs — a false-resolved state. The sweeper closes it on soak PASS.
- **`betterstack-query.sh --grep` is OR-only.** For the AND of (`ci-deploy`) and
  (`Sentry POST failed`), use raw-SQL mode (mode-1) with two `LIKE`s, or `--grep`
  the marker + post-filter the JSONEachRow output for `ci-deploy` (as
  `chardevice`'s `denied_count()` does). A bare `--grep "Sentry POST failed"`
  could match another allowlisted tag (none known to emit it, but scope
  precisely).
- **Include the archive arm.** `remote($BS_TABLE)` alone is the ~40-min hot
  window; a 7d soak needs `UNION ALL s3Cluster(primary, $BS_TABLE_S3)` or it
  silently answers 7d with 40 minutes of rows.

## Risks & Mitigations

- **False PASS closing #6475 blind** → mitigated by the liveness gate + TRANSIENT-on-any-failure fail-safe (probe can only ever close on positive proof of a live, clean window).
- **Marker drift** (an emitter's message changes and the LIKE stops matching) → Phase 0.1 pins the marker; the 7 lines share `"Sentry POST failed"`. A drift-guard could assert the emitter count, but at 7 stable lines this is YAGNI; noted for deepen-plan to weigh.
- **`SYSLOG_IDENTIFIER` field spelling in `raw`** → resolved empirically in Phase 1 against one real Better Stack row before the LIKE is frozen (post-filter fallback if the field shape differs).
