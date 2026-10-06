---
title: "Sweep argv bearer tokens in tracked shell scripts to curl --config - (stdin)"
date: 2026-10-06
slug: sweep-argv-bearer-tokens-to-curl-config-stdin
branch: feat-one-shot-7843-argv-bearer-to-config-stdin
issue: 7843
closes: 7843
type: chore
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Overview

Tracked shell scripts still hand curl a bearer credential as an argument (the header flag
with an `Authorization: Bearer <token>` value). Whatever is on a command line is readable from the
process table and from `/proc/<pid>/cmdline`, and it is printed by `bash -x` when a traced parent
invokes the script. This plan moves the header onto curl's stdin config channel for every in-scope
script, keeps each script's existing xtrace self-refusal green, and shrinks the commit-time lint
baselines as scripts are converted. It is the prevention follow-through for the open incident
issue #7797, which stays open as the incident record.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (measured 2026-10-06 on this worktree) | Plan response |
|---|---|---|
| "61 scripts / 108 sites" (#7843, measured 2026-09-06) | Live count by logical-command census (backslash continuations joined, array/variable-held headers included): **64 files / 136 curl call sites** in tracked non-test `.sh`. The same grep the brief used (`Authorization: Bearer` string, any context) returns 79 non-test files; the `-H "Authorization: Bearer` same-line form alone returns 59. The inventory drifted by +3 files / +28 sites, mostly three seed scripts that hold the header in a variable (`header_auth`) and pass it 31 times. | Re-derived inventory is the work-list (see Research Insights). The issue's numbers are not used. |
| "87 tracked non-test .sh files still carry `-H "Authorization: Bearer`" (brief) | 87 does not reproduce for non-test files: 59 same-line, 79 any-context. 92 files appear only when the grep also matches already-converted stdin forms (`header = "Authorization: Bearer`, `--header @<(printf ...)`, `printf 'Authorization: Bearer %s' \|` ) and comment/emitter prose. Nine files already use a stdin form and are NOT work. | Census excludes already-safe forms; they are listed so nobody re-converts them. |
| "shrink its baseline as sites are converted" (brief) | The two existing baselines (`lint-shell-trace-credential-refusal.baseline.txt` = Rules A/B/C, `...-d.baseline.txt` = Rule D) list files lacking the xtrace refusal / transport confinement. **Neither lists argv-bearer sites**, so converting a site shrinks neither by itself. They shrink only because CI runs `--changed` (ci.yml:231), which bypasses baselines: every touched script must be fully A/B/C/D-clean. 19 of the 57 touched files are currently in a baseline; 24 baseline entries are already stale (17 of 67 in A/B/C, 7 of 31 in D: the repo-wide run reports 50 and 24 live offenders). | Phase 1 adds Rule E (argv-bearer) with its own enumerated baseline, so "baseline shrinks as sites convert" is literally true for the sweep; Phase 7 regenerates A/B/C and D baselines (they shrink by the touched files plus the stale entries). |
| "pattern in apps/web-platform/infra/inngest-boot-emitter.sh" (brief) | No such `.sh` exists on `origin/main`; only `inngest-boot-emitter.test.sh`. The proven in-repo shapes are `curl_auth()` in `cutover-verify.sh`, `-K -` in `rung2-rehearsal/seed-dirty-journal.sh`, `--config -` in `workspaces-luks-provision.sh` / `web2-rebirth.sh`, `--header @-` in `supabase-logs-query.sh`. | Canonical form is derived from those (Proposed Solution), not from the missing file. |
| "any PR that edits one of the listed callers must convert it" (#7843 trigger) | Not enforced by anything today; Rule D accepts argv bearer (measured: a compliant-D fixture with `-H "Authorization: Bearer ${TOK}"` exits 0). The `--changed` step at ci.yml:231 sits in the `lint-bot-statuses` job, which is NOT in `scripts/required-checks.txt` (advisory). The repo-wide run `scripts/lint-shell-trace-credential-refusal-repo` inside the required `test` context (test-all.sh:4213) IS blocking. | Rule E makes the trigger mechanical: new offenders are blocked by the required repo-wide run (baseline-gated); the touched-file drawdown (`--changed`) is advisory, and baseline E's equality rule makes a stale or grown list a blocking failure. |
| `cutover-verify.sh` is "already proven" | It converts the header but its `curl_auth()` omits `--disable`/`--noproxy '*'`, so Rule D fails it today (it is in the D baseline). | Exemplar is brought to the canonical form in Phase 1 so the pattern we point at is itself clean. |
| Host scripts are ordinary edit targets | 8 of the argv-bearer scripts under `apps/web-platform/infra/` are hashed into `terraform_data.*.triggers_replace` in `server.tf` and/or baked into the image (`host_script_files`, Dockerfile COPY); open tracker #7898 records that editing them re-runs prod-host provisioners on merge and belongs to a deployment window. | Deferred (Tier 2) to a residue tracker; Rule E baseline carries them. See Scope Check. |

## Research Insights

**Premise validation (Phase 0.6).** `gh issue view`: #7843 OPEN (no closing PR), #7797 OPEN,
#7842 OPEN (PreToolUse hook + CI `run:` form lint: not this scope), #7898 OPEN (Rule D drawdown:
host-script boundary, not this scope). The cited files exist on `origin/main` except
`inngest-boot-emitter.sh` (stale, see reconciliation). ADR corpus: ADR-202 (xtrace self-refusal)
records the argv correction ("argv hygiene is the only defense" for a traced parent) and does not
reject `--config -`; ADR-263 records the charset-before-config-stream discipline; ADR-198 records
stdin-header precedent. No ADR rejects the mechanism.

**Property List (Phase 0.6b).**

1. P1 — No bearer token appears in the argument list of any curl in a tracked, non-test shell script, so `ps`, `/proc/<pid>/cmdline` and a traced parent's `+ curl ...` line cannot render it.
2. P2 — Conversion never weakens an existing guard: each script keeps its xtrace self-refusal and each credentialed curl keeps `--disable` first and `--noproxy '*'` (Rules A/B/C/D stay green on every touched file).
3. P3 — Behaviour is unchanged for every defined input: same HTTP request, same exit/status/`-w` output under `set -e` / `set -o pipefail`. (An undefined token is the one difference: expansion now fails inside the process-substitution subshell, so each script keeps its existing non-empty guard BEFORE the call, and a battery row pins that an unset token never reaches PASS.)
4. P4 — The baselines shrink and regrowth is mechanically visible (a new argv bearer outside the enumerated baseline fails the required repo-wide lint run; touching a baselined script is flagged by the advisory `--changed` step).
5. P5 — A broken conversion cannot hide: a script that stops sending its credential must fail a test, because follow-through soak probes auto-close trackers on a healthy-looking result.

**Cut List (Phase 0.6b).**

- Shared sourced helper lib (`scripts/lib/curl-bearer.sh`) → buys one place for the charset guard. Cut: host-deployed and plugin-shipped scripts cannot source a repo-relative lib, so it would coexist with an inline form anyway; the guard is needed at 4 response-derived-token sites only. Inline per-site/per-file wrapper is the repo precedent (9 existing sites).
- `-H @-` as the canonical (vs `--config -`) → cut: the issue prescribes `--config -`, it works on every curl the fleet runs (stdin config has always existed; `-H @file` needs curl 7.55+), and 9 sites already use it. `--header @-` sites already in tree are left alone.
- Converting GitHub workflow YAML (14 files, ~32 sites) in this PR → cut: the lint cannot see YAML, `run:` blocks execute on runners where the process table is not an exposure surface the incident touched, and #7898 §3 records the YAML boundary. Tracked in the residue issue.
- Non-Bearer argv credentials (`-u`, `X-API-Key`, OAuth1 `Authorization:` in `x-community.sh`/`x-setup.sh`) → cut from the Bearer sweep except where a second credential header travels in the same curl call (`apikey:` with the same service-role key) and must move with it. Tracked in the residue issue.
- Host-deployed scripts (8 files) → cut (deployment window, see reconciliation).

**Mechanism measurements (this worktree, curl 8.22.0 / bash 5.3.15).**

- `printf 'header = "Authorization: Bearer %s"\n' "$t" | curl --disable --noproxy '*' -sS --config - URL` delivers the header; `/proc/<pid>/cmdline` of the curl shows `... --config - URL` with no token.
- **Config injection is real.** A token containing `"` + newline + `url = "..."` made curl issue a *second request* to the injected URL (two responses printed). Any token that comes from an API response (bsky `accessJwt`, LinkedIn `access_token`, OAuth exchanges) must be charset-guarded before it enters the config stream; env/Doppler tokens are fixed-format.
- **pipefail + SIGPIPE.** `printf ... | true` under `set -o pipefail` returned 141 on the first iteration of a 5-iteration loop and 141 for a 200 KB payload. Real curl reads the config first, so this bites a consumer that never reads stdin, which in practice means test stubs and shims (the plan rewrites those anyway); it is not asserted to be a production hazard. The process-substitution form (`curl ... --config - < <(printf ...)`) keeps curl as the only command whose status is observed and returned 0 in the same experiment. It is bash-only; the one `#!/bin/sh` script (`soleur-host-bootstrap.sh`) is in Tier 2.
- Rule D accepts the process-substitution form (fixture scored `OK: 1 scanned file(s)`), and also accepts the unconverted argv form: Rule D is orthogonal to this sweep.
- Repo-wide lint run takes 5.4 s; `c4-count-parity` passes (2.7 s) before the change.

**Existing in-repo shapes / learnings applied.**
`scripts/lint-shell-trace-credential-refusal.py` (Rules A–D, `--changed` baseline bypass, `--census`, `--write-baseline*`); ADR-202; post-mortem `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`; ADR-263 (charset sanitisation before a curl config stream); ADR-198 (`-K -` stdin header for ingest tokens); `tests/scripts/test-sentry-alert-live-fidelity.sh` (PATH-shim curl recording argv NUL-delimited plus stdin: the model for the battery); `knowledge-base/project/learnings/bug-fixes/2026-06-18-sibling-script-shares-byte-identical-argv-accumulation-defect.md` (enumerate sweep work-lists by grep, never by intuition); `plugins/soleur/test/fixture-relative-assert.baseline.txt` (row-by-row equality baseline that must be regenerated when a script edit moves its counts); followthrough lints (`scripts/lint-followthrough-varq-ban.sh`, `scripts/followthrough-exec-bit.test.sh`) constrain what a probe edit may contain.

**Open Code-Review Overlap check (Phase 1.7.5).** 87 open `code-review` issues queried; none names any file in `## Files to Edit` / `## Files to Create`. Recorded as `None` below.

## Problem Statement

A command line is world-readable on Linux (`/proc/<pid>/cmdline` is mode 0444, and `ps` shows it) for
the life of the process, and `bash -x` prints it after expansion. #7797 printed two live API tokens
into an agent transcript that way. ADR-202 added a self-refusal preamble to every credential-binding
script, but xtrace does not cross `exec` or a child invocation: a traced **parent** calling
`./child.sh "$TOK"` prints the token while the child's own preamble sees a clean `$-`. For that shape
argv hygiene is the only defense, so the sweep closes a real residual of the #7797 vector and not
only procfs hygiene. #7797's original statement that the sweep "buys zero trace-vector protection"
was wrong; ADR-202 §Named residual holes records the correction.

Limit of the claim: the sweep removes the token from curl's argument list and from the `+ curl ...`
trace line. A sourced library (`_cf-admin-token.sh` and the `tests/scripts/lib/*-gate.sh` files)
runs in its caller's shell with no preamble of its own, so under a traced parent the builtin
`printf` that feeds curl still expands the token into a `+` line. For those five files the
conversion buys procfs hygiene and a smaller trace surface, not trace immunity; the caller's
preamble remains the trace defense. The `printf` must stay the shell builtin (never `command
printf`, `env printf` or `/usr/bin/printf`), because an exec'd printf would put the token back on
argv.

## Proposed Solution

Move every bearer header off curl's argument list onto curl's stdin config channel, in the same shape
the tree already uses at nine sites, with two refinements measured above (process substitution, charset guard).

**Canonical form A — one call site (bash).** The token reaches curl as bytes on stdin; the only argv
text is `--config -`:

```bash
# before
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  -H "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}" "$url")"
# after
code="$(curl --disable --noproxy '*' -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  --config - "$url" \
  < <(printf 'header = "Authorization: Bearer %s"\n' "${SENTRY_ACTIONS_RO_TOKEN}"))"
```

Rules for the form: the format string is always a literal with `%s` (a token containing `%` must
never reach the format); `--disable` is the literal first argument and `--noproxy '*'` is present
(Rule D); the credential flag is removed from the argument list, not merely supplemented; curl keeps
its position as the only observed command (no `printf | curl` pipeline, see the SIGPIPE measurement).

**Canonical form B — a script with several calls.** One local wrapper owns the transport flags and the
header, so the property lives in one place per file and each call site loses its `-H` line:

```bash
sentry_curl() {
  curl --disable --noproxy '*' "$@" --config - \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$SENTRY_AUTH_TOKEN")
}
```

A header that travels with a second credential header in the same call (`apikey: <service-role key>`
beside `Authorization: Bearer <same key>`) moves into the same config stream as a second `header =`
line; leaving the `apikey:` header on argv would leave the identical secret on `ps`.

**Canonical form C — a token that came from an API response.** Allowlist the charset (not a denylist: an allowlist also refuses control bytes and any future
config-syntax surprise) before it enters the config stream, fail closed, never echo the value:

```bash
_bearer_ok() { case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
```

Required at exactly the response-derived sites: `bsky-community.sh`, `bsky-setup.sh`,
`linkedin-setup.sh`, and `linkedin-community.sh` if its token is not purely env-sourced (provenance
is resolved in Phase 0, not at conversion time).

**Canonical form D — text a script prints for a human to run.** `provision-cloudflare.sh`,
`provision-doppler.sh`, `trigger.sh`, `durable-reminder-prefer-inngest.sh` and
`registry-luks-recut-gate.sh` print or generate `curl -H "Authorization: Bearer ..."` command text.
That text is converted to the stdin form so a copy-paste does not reintroduce the argv exposure.
It is hand-converted and checked by an acceptance grep; Rule E scopes to executed curl commands and
does not parse printed text.

**Not converted (already safe).** `--header @-` / `-H @<(printf ...)` / `--config <(...)` / `-K -`
sites: `supabase-logs-query.sh`, `supabase-advisor-scan.sh`, `sentry-alert-live-fidelity.sh`,
`assert-byok-rules-exist.sh`, `postgrest-reload-schema.sh`, `audit-ruleset-bypass.sh`,
`cf-token-scope.sh`, `bin/snapshot-github-app.sh`, `rotate-supabase-db-credential.sh` (0600 config
file), `web2-rebirth.sh`, `resend-inbound-bootstrap.sh`, `web-probes-token-rotation-verify.sh`,
`rung2-rehearsal/seed-dirty-journal.sh`, the two bootstrap scripts under `knowledge-base/project/specs/`.
The conversion batteries do not touch them.

## Inventory (live, two derivations)

Derivation 1 (string grep): `git grep -l 'Authorization: Bearer' -- '*.sh'` minus `*.test.sh`,
`tests/`, `fixtures/` returns 79 files; the `-H "Authorization: Bearer` same-line subset is 59.
Derivation 2 (logical-command census, the one used): the executable procedure
`knowledge-base/project/specs/feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py`
joins backslash continuations, keeps commands whose argv carries a bearer header (`-H`/`--header`
not followed by `@`, not a a curl-config `header` line config line), adds variable-held (`-H "$header_auth"`) and
array-held (`curl_args+=(-H ...)`, `_auth=(-H ...)`) headers, and includes the sourced production
gate libs `tests/scripts/lib/*-gate.sh`. Run once at plan time: `TOTAL sites=136 files=64`, of which
**56 files / 128 sites are in scope (Tier 1)** and 8 files / 8 sites are deferred (Tier 2). Every
count in this plan comes from that run (or the lint's own `--census`), not from a hand tally. The
Phase 0 task re-runs it at work time and diffs it against this list; a mismatch is resolved before
any conversion. It is a one-time measurement (the lint's own `--census` is the standing detector); no test depends on it.

**Tier 1 — converted in this PR (file, site count).**

scripts/followthroughs (20 files / 22 sites): `ac10-workspace-reconcile-sentry-4246.sh` (1), `ac8-founder-ambiguous-soak-5673.sh` (1), `accounted-beacon-live-6462.sh` (1), `anthropic-admin-key-6297.sh` (1), `autovacuum-thrash-6168.sh` (1), `betterstack-roundtrip-latency-7855.sh` (1), `community-monitor-checkin-soak-5728.sh` (1), `concurrency-slot-wal-backoff.sh` (1), `cron-machinery-soak-9272.sh` (2), `cwv-field-rum-9178.sh` (1), `dashboard-cold-tiers-8978.sh` (1), `l3-probe-armed-6438.sh` (1), `phase3-ga-soak-5274.sh` (1), `reconcile-ff-only-sentry-4977.sh` (1), `send-failed-alert-probe-8097.sh` (1), `sentry-checkins-3859.sh` (1), `sync-health-residual-5689.sh` (2), `web2-standby-soak-6459.sh` (1), `workspaces-luks-soak-6604.sh` (1), `zot-soak-6122.sh` (1).

scripts (8 files / 15 sites): `arm-checkpoint.sh` (1), `betterstack-ingest-probe.sh` (1), `check-cloudflare-token-drift.sh` (1), `cutover-inngest.sh` (5), `provision-plausible-goals.sh` (2, array-held), `registry-heartbeat-poll.sh` (1), `sentry-issue.sh` (2), `weekly-analytics.sh` (2).

apps/web-platform/scripts + supabase/scripts (8 files / 53 sites): `audit-sentry-extra-text-references.sh` (4), `configure-sentry-alerts.sh` (5), `dsar-export-oversize.sh` (5, plus 5 co-travelling `apikey:`), `seed-dev-users.sh` (6, variable-held), `seed-live-verify-user.sh` (14, variable-held), `seed-qa-user.sh` (11, variable-held), `sentry-monitors-audit.sh` (6), `../supabase/scripts/configure-auth.sh` (2).

apps/cla-evidence/scripts (2 / 7): `_cf-admin-token.sh` (2, sourced), `gdpr-override.sh` (5).

apps/web-platform/infra, not host-deployed (4 / 7): `arm-heartbeats.sh` (2, run by CI), `scripts/fresh-host-boot-trail.sh` (2, run by CI), `scripts/verify-tunnel-ingress-origin.sh` (1), `zot-image-oci-archive.sh` (2, path-trigger on `zot-image-mirror.yml`; Phase 5 verifies the publish step is idempotent before converting and moves it to Tier 2 if it is not).

tests/scripts/lib production gates (4 / 5): `git-data-birth-readiness-gate.sh` (2, array-held with a stub seam), `preapply-entrypoint-gate.sh` (1), `stock-preflight-gate.sh` (1), `registry-luks-recut-gate.sh` (1, printed command text, form D).

plugins and hooks (10 / 19): `plugins/soleur/scripts/audit-flag-flip.sh` (1 + `apikey:`), `skills/community/scripts/{bsky-community,bsky-setup,linkedin-community,linkedin-setup}.sh` (6), `skills/provision-cloudflare/scripts/provision-cloudflare.sh` (2, text + live), `skills/provision-doppler/scripts/provision-doppler.sh` (6, text + live), `skills/trigger-cron/scripts/trigger.sh` (2), `skills/user-set-role/scripts/set-role.sh` (1 + `apikey:`), `.claude/hooks/durable-reminder-prefer-inngest.sh` (1, generated command text).

Exemplar fix (no argv site, Rule D only): `apps/web-platform/infra/cutover-verify.sh` `curl_auth()` gains `--disable` first and `--noproxy '*'`.

**Tier 2 — deferred to the residue tracker (host-deployed; edit re-runs prod provisioners on merge, per #7898):**
`apps/web-platform/infra/{container-restart-monitor,cron-egress-alarm,disk-monitor,resource-monitor,inngest-rearm-reminders,inngest-wiped-volume-verify,web-private-nic-guard}.sh` and `soleur-host-bootstrap.sh` (`#!/bin/sh`, so process substitution is unavailable: the form there is the pipe). They are listed in Rule E's baseline with the residue issue number.

**Tier 3 — also in the residue tracker:** `.github/workflows/*.yml` and composite actions (14 files, ~32 sites: `apply-web-platform-infra.yml` 8, `git-data-rung2-rehearsal.yml` 4, `scheduled-terraform-drift.yml` 3, others 1-2, `mint-infra-app-token/action.yml` 2), `cloud-init-*.yml`, and non-Bearer argv credentials (`-u user:token` in `web-zot-consumer-probe.sh` / `zot-entry-gate.sh`, OAuth1 `Authorization:` in `x-community.sh` / `x-setup.sh`, standalone `apikey:` in `seed-qa-user.sh:175` which carries only the anon key).

Measured conflicts to check at work time (all zero at plan time): a Tier 1 site that also uses curl's stdin for a body (`-d @-`, `--data-binary @-`, `-T -`, `--json @-`): 0 of 136; a site that already passes `-K`/`--config`: 0; `-u` sites among Tier 1: 0.

## Implementation Phases

Ordering (CTO and plan-review): the detector lands BEFORE the conversions, with a baseline that
lists every current offender, so each conversion batch literally shrinks baseline E (and the A/B/C
and D baselines) and a bisect separates lint-compliance, transport change and ratchet. Within a
batch, commit (a) compliance prerequisites (xtrace refusal, Rule D flags, destination pin) first,
then (b) the conversion. The residue tracker is filed (#9597) before Phase 0, so its number is
available to baseline E from the start.

### Phase 0 — Freeze, measure, and the RED battery

- 0.1 Re-run `census-argv-bearer.py` (a throwaway planning measurement, not a dependency of any test) and the grep in Acceptance Criteria; expected `TOTAL sites=136 files=64`.
- 0.2 Run the lint on explicit paths (baseline-bypassing) for the 19 baselined Tier 1 files and record per-file A/B/C/D findings, so each prerequisite commit is sized from data (Rule D has a destination-pin limb, not only flags).
- 0.3 Resolve token provenance for `linkedin-community.sh` (env-sourced or response-derived) and record which sites need the form C guard.
- 0.4 Write `tests/scripts/test-argv-bearer-sweep.sh` (Files to Create) before any conversion, scoped by the Guard 2 assembly: dynamic rows for the 20 followthrough probes and the form C sites; the shim lives here. Every other script is covered by Rule E (static) plus its existing owning test, extended in place where that test already stubs curl. A PATH shim `curl` records argv NUL-delimited and stdin per call and replays the REAL contract it stands in for (a fake written by the consumer's author encodes the consumer's reading): it reads stdin only when `--config -` / `-K -` is in argv, honours `-o <file>`, `-w '%{http_code}'` (including the `\nHTTP_STATUS:` suffix forms the probes use) and `-s/-S`, and exits 22 on a >= 400 answer when `-f`/`--fail`/`--fail-with-body` is present. Per row assert (i) at least one credentialed call recorded (zero fails the row, never skips), (ii) no recorded argv contains the fixture token, (iii) the fixture token is on stdin as `Authorization: Bearer <fixture>`, (iv) `--disable` is the first argv entry and `--noproxy` `*` is present. Negative rows, three only (one per probe family: Sentry, Better Stack, Supabase): shim answers 401, the probe's exit status is its TRANSIENT/FAIL status, never PASS; plus one unset-token row per form-A script family (no PASS). The four sourced gate libs (out of the lint's scope) get a fixed-list static assertion that none carries an argv bearer.
- 0.5 Run it against the unconverted tree: every dynamic row RED. A row green before conversion is vacuous and is fixed first.
- 0.6 Register the suite: add `run_suite "tests/scripts/argv-bearer-sweep" bash tests/scripts/test-argv-bearer-sweep.sh` to `scripts/test-all.sh` (it does not glob `tests/scripts/`) and run `bash scripts/lint-orphan-test-suites.sh`; place any owning EXIT trap before `source test-helpers.sh` (`lint-trap-tempfile-ownership`).

### Phase 1 — Rule E (detector first), exemplar, pilot

- 1.1 Write the Guard 1 fixtures and test rows first (matrix below), then Rule E in `scripts/lint-shell-trace-credential-refusal.py`: a `check_rule_e()` run from `check_file()` over every logical command assembled by `_curl_commands`, plus the `main()` plumbing (the `"e"` entry in `baselines_by_rule`, `load_baseline_e`, `--write-baseline-e`, an `offenders_e` census line, `OK:` output naming Rule E). An unregistered rule tag falls back to the A/B/C baseline file list and is silently suppressed, so the plumbing is part of the guard.
- 1.2 Wrapper awareness: after conversion form B hides call sites behind a file-local wrapper, so `CURL_INVOKE` (which requires the literal word `curl`) would stop classifying them and Rule D's destination-pin limb would go vacuous for every wrapper-converted script. Rules D and E therefore also treat a call whose first word is a function defined in the same file with a `curl` invocation in its body as a curl command. A fixture proves an env-settable `$URL` behind a wrapper is still flagged by Rule D.
- 1.3 Run Rule E on the unconverted tree and diff its offender set against the census (minus the four lint-excluded gate libs and the printed-text emitters); resolve every difference before baseline E is written. Generate `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` (header names #9597 and the shrink-only contract).
- 1.4 `cutover-verify.sh` `curl_auth()` gets `--disable` first and `--noproxy '*'` (not referenced by `server.tf` or the Dockerfile; Rule D only).
- 1.5 Pilot `scripts/arm-checkpoint.sh` (form A), `apps/web-platform/scripts/configure-sentry-alerts.sh` (form B, D-baselined), `scripts/provision-plausible-goals.sh` (array-held, A/B/C- and D-baselined). Prove: battery rows green, owning test green, lint green, baseline E regenerated with deletions only.

### Phase 2 — scripts/followthroughs (20 files)

- 2.1 Prerequisites for the four baselined probes (`autovacuum-thrash-6168`, `concurrency-slot-wal-backoff`, `l3-probe-armed-6438`, `web2-standby-soak-6459`).
- 2.2 Convert each probe to form A (curl invocation only; keep `2>/dev/null` and the `-w` status capture where they are, and keep `lint-followthrough-varq-ban.sh` compliance).
- 2.3 Gates: battery rows, `bash -n`, `lint-followthrough-varq-ban.sh`, `followthrough-exec-bit.test.sh`, `sweep-followthroughs.test.sh`, probe-owned tests (`anthropic-admin-key-6297`, `cwv-field-rum-9178`, `send-failed-alert-probe-8097`, `betterstack-roundtrip-latency-7855` via `tests/scripts/test-betterstack-roundtrip-latency.sh`); regenerate baseline E.

### Phase 3 — scripts/*.sh (8 files)

- 3.1 Prerequisites: `check-cloudflare-token-drift.sh`, `provision-plausible-goals.sh`, `weekly-analytics.sh`.
- 3.2 Convert. `cutover-inngest.sh` (5 sites, 3000+ lines, form B wrapper) gets its own commit with `apps/web-platform/infra/cutover-inngest-workflow.test.sh` and `inngest-cutover-flip.test.sh`; `betterstack-ingest-probe.sh` updates its stub in `tests/scripts/test-betterstack-ingest-probe.sh` (it asserts the Bearer text is in argv; it must read stdin and assert the token is absent from argv).

### Phase 4 — apps/web-platform/scripts and supabase/scripts (8 files)

- 4.1 Prerequisites: `dsar-export-oversize.sh`, `configure-auth.sh`, `seed-*`.
- 4.2 Convert with form B wrappers. The three `seed-*` scripts replace the `header_auth`/`header_api`/`header_json` plumbing with one `sb_curl` wrapper emitting both `Authorization: Bearer` and `apikey:` lines; `seed-live-verify-user.test.sh` is the pre-existing oracle. `dsar-export-oversize.sh` moves its five `apikey:` headers with the bearer.

### Phase 5 — cla-evidence, non-host infra, production gate libs

- 5.1 Prerequisites: `gdpr-override.sh`, `arm-heartbeats.sh`, `verify-tunnel-ingress-origin.sh`, `preapply-entrypoint-gate.sh`.
- 5.2 Evidence that the four infra files are not host-coupled: grep proving none appears in a `file(`/`filesha256(`/`triggers_replace`, `host_script_files`, or Dockerfile COPY. Editing any of them still fires `apply-web-platform-infra.yml` (path-triggered), whose plan has zero resource delta for a script-body edit with no `.tf` change; the PR body states that. `zot-image-oci-archive.sh`: verify `zot-image-mirror.yml`'s publish step is idempotent (reproducible tarball, same digest) before converting; if not, move it to Tier 2.
- 5.3 Convert incl. `_cf-admin-token.sh`, `fresh-host-boot-trail.sh`, the gate libs; update `arm-heartbeats.test.sh`, `tests/scripts/test-preapply-entrypoint-gate.sh`, `tests/scripts/test-stock-preflight-gate.sh` (T27 asserts a literal curl command in the lib's header text; text and assertion move together), `tests/scripts/test-git-data-birth-readiness-gate.sh` (the `SOLEUR_RUNG2_STUB_BEARER` seam keeps its meaning; only the header source changes).

### Phase 6 — plugins and hooks (10 files)

- 6.1 Convert. Form C guard at the response-derived sites, form D for printed command text. Owning tests: `plugins/soleur/test/audit-flag-flip.test.sh`, `operator-ack-guard.test.sh`, `cf-token-scope.test.sh`, `.claude/hooks/durable-reminder-prefer-inngest.test.sh`, `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`, `trigger-cron-allowlist-parity.test.ts`. These ship to installed users (observability layer 7): no repo-relative sourcing, no new dependency, bash-only constructs already used by the file.

### Phase 7 — Final baselines, ADR addendum, verification

- 7.1 Regenerate `lint-shell-trace-credential-refusal.baseline.txt` and `...-d.baseline.txt` with `--write-baseline` / `--write-baseline-d` (full tree, never scoped); diff is deletions only; baseline E ends as the 8 Tier 2 files.
- 7.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh`; if its row-by-row baseline moved, `--write-baseline` in the same commit.
- 7.3 ADR-202 dated addendum (short, see Architecture Decision).
- 7.4 Full gate: repo-wide lint, `--changed`, battery, every owning test, `c4-count-parity`, markdownlint on the plan/ADR.
- 7.5 PR body: `Ref #7797`; `Closes #7843` with the remaining scope stated as moved to #9597 (the issue's 61-script inventory is superseded by this plan's re-derivation, and the residue has its own tracker); list Tier 2/3. The next scheduled `scheduled-followthrough-sweeper.yml` run is the live signal for the converted probes; no acceptance criterion depends on it.

## Files to Edit

Tier 1 conversions: every path in the Tier 1 list above (56 files). Exemplar: `apps/web-platform/infra/cutover-verify.sh`.
Registration: `scripts/test-all.sh` (explicit `run_suite` line for the new battery; the repo-wide lint suite `scripts/lint-shell-trace-credential-refusal-repo` already exists at line 4213 and needs no change).
Lint and baselines: `scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-shell-trace-credential-refusal.test.sh`, `scripts/lint-shell-trace-credential-refusal.baseline.txt`, `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`.
Owning tests to update where a stub inspects argv for the header (confirmed by the Phase 0 battery run): `tests/scripts/test-betterstack-ingest-probe.sh`, `tests/scripts/test-betterstack-roundtrip-latency.sh`, `tests/scripts/test-stock-preflight-gate.sh`, `apps/web-platform/infra/arm-heartbeats.test.sh`, `apps/cla-evidence/scripts/gdpr-override.test.sh`, `plugins/soleur/test/audit-flag-flip.test.sh`, `plugins/soleur/test/cf-token-scope.test.sh`, `.claude/hooks/durable-reminder-prefer-inngest.test.sh`, `apps/web-platform/scripts/seed-live-verify-user.test.sh` (set is the Phase 0 output, not a guess).
Generated-baseline file that may move: `plugins/soleur/test/fixture-relative-assert.baseline.txt`.
ADR: `knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md`.

## Files to Create

- `tests/scripts/test-argv-bearer-sweep.sh` (manifest-driven shim battery; Guard 2)
- `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` (Rule E baseline: 8 Tier 2 files)
- `scripts/fixtures/shell-trace-refusal/violation-argv-bearer-literal.sh`, `violation-argv-bearer-second-member.sh`, `violation-argv-bearer-variable-held.sh`, `violation-argv-bearer-array-held.sh`, `violation-argv-bearer-wrapper.sh`, `compliant-wrapper-env-url.sh` (Rule D wrapper case), `compliant-stdin-bearer-procsub.sh`, `compliant-stdin-bearer-wrapper.sh`, `compliant-stdin-bearer-header-at-stdin.sh` (Rule E fixtures; synthesized tokens only, per `cq-test-fixtures-synthesized-only`)
- `knowledge-base/project/specs/feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py` (the executable inventory procedure; already written at plan time) and `decision-challenges.md` (the single-PR vs split User-Challenge)
- `knowledge-base/project/specs/feat-one-shot-7843-argv-bearer-to-config-stdin/tasks.md` (Save Tasks step)

## Open Code-Review Overlap

None. 87 open `code-review` issues were queried (`gh issue list --label code-review --state open --json number,title,body`) and matched with `jq --arg path` against every file in the Tier 1 list plus the lint, its test and `cutover-verify.sh`: zero matches.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-202 with a short dated addendum (about 10 lines; no new ordinal, so no collision exposure) in this PR: (1) the argv correction recorded in §Named residual holes is now implemented for Tier 1 and ratcheted by Rule E, (2) sourced libraries get procfs hygiene but not trace immunity, (3) Tier 2/3 are deferred to #9597. Canonical forms A-D, the SIGPIPE measurement and the config-injection finding live in Rule E's header comment in the lint, not in the ADR. Reason it is a deliverable of this plan: plan Phase 2.10 (an extension of an accepted ADR's enforcement belongs to the plan that creates it).

### C4 views

No C4 impact. Checked against `model.c4`, `views.c4` and `spec.c4` by enumerating: external human actors (none added; the operators and CI that run these scripts are already modeled), external systems touched by the converted calls (Sentry 24 mentions, Better Stack 21, Supabase 20, Hetzner 42, Cloudflare 22, Resend 12, Doppler 35, Plausible 3: all modeled; LinkedIn, Bluesky and X are community-plugin integrations on users' machines and are not modeled before or after), data stores (none touched), actor-to-surface access relationships (unchanged: this changes how a header is transported on existing edges, and `model.c4` already documents "Bearer-on-stdin transport per supabase-logs-query.sh" on the `github -> supabase` edge). `plugins/soleur/test/c4-count-parity.test.sh` passes before the change (re-run in Phase 7).

### Sequencing

Single PR; the ADR addendum describes the shipped state.

## User-Brand Impact

- **If this lands broken, the user experiences:** a converted operational script silently sends no credential (or the wrong one) and its soak probe or gate reports a healthy result: a follow-through tracker is auto-closed while the underlying signal is unverified, or a DSAR/GDPR tooling run fails closed with an auth error instead of completing. No end-user-facing page changes.
- **If this leaks, the user's data is exposed via:** the argv/process-table vector this sweep removes (`/proc/<pid>/cmdline`, a traced parent's `+ curl` line) carrying Supabase service-role keys, Sentry/Better Stack/Hetzner/Cloudflare/Doppler tokens; the conversion introduces no new file or log sink for the token (stdin only) and one new injection surface (token content into curl config) closed by the charset guard.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the sweep reduces an existing exposure and no single script's failure leaks user data, but a repeated silent-auth-break pattern across the probe fleet would erode trust in the soak/gate machinery, so it is not `none`; it is not `single-user incident` because every failure mode is fail-closed or detected by the battery before merge.

Artifact/vector pairs for review: (1) probe false-green after a broken header, via a swallowed 401 -> battery negative-path rows; (2) token visible in argv after a partial conversion -> Rule E + battery row (ii); (3) config injection from a response-derived token -> form C guard + battery fixture with a newline/quote token.

## Observability

```yaml
liveness_signal:
  what: "the required-context suite 'scripts/lint-shell-trace-credential-refusal-repo' (Rule E, repo-wide) and 'tests/scripts/argv-bearer-sweep' (the battery), both run by scripts/test-all.sh; the advisory --changed step at ci.yml:231 flags touched baselined scripts"
  cadence: "every pull request and every merge-queue run"
  alert_target: "PR check status: the test context is required, the --changed step (lint-bot-statuses job) is advisory"
  configured_in: "scripts/test-all.sh, .github/workflows/ci.yml, scripts/lint-shell-trace-credential-refusal.py (Rule E), tests/scripts/test-argv-bearer-sweep.sh"
error_reporting:
  destination: "GitHub Actions job log (stderr of the lint and the battery) and check annotations"
  fail_loud: "lint exits 1 with '<file>:<line>: bearer token on curl argv'; the battery prints the failing manifest row and exits non-zero"
failure_modes:
  - mode: "a converted script stops sending its credential and a probe reads the 401 as healthy"
    detection: "battery rows (ii)(iii) for every probe and form C site, three negative rows (401 must not reach PASS), unset-token row"
    alert_route: "required test context red on the PR"
  - mode: "an argv bearer is reintroduced in a tracked script outside baseline E"
    detection: "Rule E in the repo-wide run (blocking); baseline E must equal the live offender set exactly"
    alert_route: "required test context red; merge queue ejects"
  - mode: "a response-derived token with a newline or quote injects a curl config directive"
    detection: "battery fixture token containing a quote and newline must be refused by the form C allowlist guard (non-zero exit, zero curl calls recorded)"
    alert_route: "required test context red"
logs:
  where: "GitHub Actions run logs for ci.yml"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py
  expected_output: "OK:"
```

## Guard Contract

### Guard 1 — Rule E: argv-bearer ratchet

**Property.** No executed curl command in a tracked, non-test shell script carries a bearer token in its own argument list unless the file is enumerated in the Rule E baseline.

**Assembly.** The chokepoint is `_curl_commands()` in `scripts/lint-shell-trace-credential-refusal.py` (it joins continuations, the pipeline above a call, inlines `"${arr[@]}"` bodies and `--config` writer blocks) feeding a new `check_rule_e()` called from `check_file()`, registered in `main()`'s rule-to-baseline map; Rule E must run on every logical command in the file, not the first. Members the property quantifies over: the short `-H` and long `--header` flags; double- and single-quoted values; a header held in a variable (`h="Authorization: Bearer $T"`, `-H "$h"`); a header held in an array (`curl_args+=(-H ...)`, `_auth=(-H ...)`); a call through a file-local wrapper function whose body invokes curl (the wrapper's own `curl` line AND its call sites, so a bearer passed to `api_curl -H ...` is seen); a second credential header (`apikey:`) in the same call. Safe forms (`-H @-`, `--header @<(...)`, `--config -`, `-K -`, `--config <(...)`) are not flagged. Out of scope by construction: printed command text (converted by hand, checked by an acceptance grep), YAML, and the sourced `tests/scripts/lib/*-gate.sh` libs (covered by Guard 2's fixed-list assertion). Scope is `excluded_for_rule_d()`; baseline E is enumerated paths, bypassed by `--changed` and by explicit paths.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | In `compliant-stdin-bearer-procsub.sh`, replace the `--config -` call with `-H "Authorization: Bearer ${TOK}"` | RED (violation reported, rc 1) |
| 2 | Delete the `check_rule_e` call from `check_file()`, or remove the fixture loop from the suite (the guard's own dispatch) | RED: the suite asserts a floor on executed Rule E fixtures (violation and compliant) and `--census` must report `offenders_e` equal to baseline E's length, so a dead dispatch reads RED, never "0 checked" |
| 3 | `violation-argv-bearer-second-member.sh`: a compliant stdin call followed by a second call with `-H "Authorization: Bearer ${TOK}"` | RED (the check must not stop at the first compliant member) |
| 4 | `violation-argv-bearer-variable-held.sh`: `h="Authorization: Bearer $T"; curl -H "$h" "$u"` | RED |
| 5 | `violation-argv-bearer-array-held.sh`: `args+=(-H "Authorization: Bearer ${T}"); curl "${args[@]}" "$u"` | RED |
| 6 | `violation-argv-bearer-wrapper.sh`: `api_curl() { curl --disable --noproxy '*' "$@"; }` then `api_curl -H "Authorization: Bearer ${T}" "$u"` | RED (call sites of a wrapper are seen) |
| 7 | Rule D: `compliant-wrapper-env-url.sh`: a wrapper called with an env-settable `"$URL"` that is never pinned | RED from Rule D (the wrapper does not blind the destination-pin limb) |
| 8 | Drop the `"e"` entry from `baselines_by_rule` in `main()` (it falls back to the A/B/C list) | RED (a Rule E offender listed only in baseline E is reported) |
| 9 | Add a converted (clean) file to baseline E, or remove a still-violating Tier 2 file from it | RED: baseline E must equal the live Rule E offender set exactly |
| 10 | Harness must-PASS (not the canonical): `compliant-stdin-bearer-header-at-stdin.sh` (`-H @-` fed by `printf`) and `compliant-stdin-bearer-wrapper.sh` (local wrapper with `--config -`) | GREEN (rc 0): a guard that rejects everything cannot pass these |

**Anchor.** The stored value is baseline E. The suite requires baseline E == the live offender set (equality, not a count floor), so a weakening needs the file edited in the same diff as the code it excuses; its header ties every entry to #9597; the repo-wide run (required context) reports any offender missing from the list, so growth cannot ride a green run.

### Guard 2 — Conversion battery (`tests/scripts/test-argv-bearer-sweep.sh`)

**Property.** For every script it covers, a run that reaches the credentialed curl records the bearer token on curl's stdin and never in curl's argument list, and an unusable credential never produces the script's PASS outcome.

**Assembly.** The chokepoint is the PATH-shim `curl` every row runs the script under; it records every call (argv NUL-delimited, stdin) and assertions quantify over ALL recorded calls that carry a credential, not the first. Covered population: the 20 followthrough probes, the form C sites, and a fixed list of the four sourced gate libs (static assertion). Everything else is Rule E's population. Coverage of the rest of Tier 1 is delegated, by decision, to Rule E (static) and each script's owning test (extended in place), not re-modelled here.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert one converted probe to `-H "Authorization: Bearer ${TOK}"` | RED (token found in recorded argv) |
| 2 | Make a covered script exit before its curl (the guard's own dispatch: zero calls recorded) | RED: zero recorded calls fails the row; it must never read as a pass |
| 3 | A script with two curls, the first converted and the second left on argv | RED (assertion covers all recorded calls) |
| 4 | Harness: change the shim to stop recording stdin | RED (token-on-stdin assertion fails for every row) |
| 5 | Harness must-PASS (not the canonical): a script using `-H @-` fed by `printf`, and one using a wrapper function | GREEN |
| 6 | Negative path: shim answers 401 for a Sentry, a Better Stack and a Supabase probe | the probe's exit status is its TRANSIENT or FAIL status, never PASS; a probe that exits PASS is RED |
| 7 | Form C: token fixture containing a quote and a newline | RED unless refused with zero curl calls recorded |

**Anchor.** Nothing is stored that a diff could weaken silently: the covered population is the followthrough directory glob plus the fixed gate-lib list, and the 20-probe count is asserted against the directory listing at test time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "sweep the remaining argv bearer tokens (`-H "Authorization: Bearer ..."` on curl argv) in tracked shell scripts to `curl --config -` with the header on stdin" [brief] | Phases 1-6, Canonical forms A-D, Files to Edit | mapped (Tier 1); Tier 2/3 descoped — justification: host-deployed edits re-run prod provisioners on merge (#7898), YAML is outside the lint's reach; both tracked in the residue issue |
| 2 | "so `bash -x` / `ps` / /proc/<pid>/cmdline cannot render them" [brief] | Property P1, battery rows (ii)(iii), Rule E | mapped |
| 3 | "Read `gh issue view 7843` for the scoped inventory (61 scripts / 108 sites)" [brief] | Research Reconciliation, Inventory, Phase 0.1 | mapped (inventory re-derived; 64 files / 136 sites) |
| 4 | "existing in-repo patterns (e.g. apps/web-platform/infra/cutover-verify.sh, apps/web-platform/infra/inngest-boot-emitter.sh, scripts/fixtures/shell-trace-refusal/)" [brief] | Canonical forms, Phase 1.1, Rule E fixtures | mapped (`inngest-boot-emitter.sh` does not exist; recorded in reconciliation) |
| 5 | "use `Ref #7797`, not Closes — it stays open as the incident record" [brief] | Phase 7.5 | mapped |
| 6 | "Do not touch or print any token values" [brief] | Test Scenarios (synthesized fixtures only; no step runs a probe with a real credential) | mapped |
| 7 | "keep each script's xtrace self-refusal and the commit-time lint (scripts/lint-shell-trace-credential-refusal.py) green" [brief] | Phases 2-6 step (a), Property P2 | mapped |
| 8 | "shrink its baseline as sites are converted" [brief] | Phase 1.3 (baseline E), per-phase regeneration, Phase 7.1 | mapped |
| 9 | "re-derive the live inventory yourself (git grep, two ways)" [brief] | Inventory, Phase 0.1 | mapped |
| 10 | "any PR that edits one of the 61 listed callers must convert that caller" [issue #7843] | Rule E (`--changed` bypass) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Canonical forms A, B | "sweep ... to `curl --config -` with the header on stdin" | asked |
| Canonical form D (printed command text) | — | inferred — justification: a copied printed command reintroduces the argv exposure for whoever runs it; hand-converted, outside Rule E |
| Form C charset guard | — | inferred — justification: measured config-injection (a newline plus `url =` made curl issue a second request); without it the new stdin channel introduces a vulnerability the argv form did not have |
| Process substitution instead of `printf \| curl` | — | inferred — justification: measured SIGPIPE 141 under `set -o pipefail` with a non-reading consumer would turn the sweep into intermittent failures in every scripted stub |
| Tier 2/3 deferral | — | inferred — justification: #7898 records that editing the host-hashed scripts re-runs prod provisioners on merge; a sweep PR must not take a deployment window it did not plan for |
| Phase 0 battery (Guard 2), scoped to the 20 probes and form C sites | "Do not touch or print any token values" | inferred — justification: follow-through probes auto-close trackers on a healthy-looking result, so a silently broken header is a false-green; the shim proves delivery without a real token; scoped narrowly because Rule E and the owning tests cover the rest |
| Rule E + baseline E | "shrink its baseline as sites are converted" | asked |
| ADR-202 addendum | — | inferred — justification: plan Phase 2.10; the plan extends an accepted ADR's enforcement and ADR-202 records the argv residual this sweep closes |
| Residue tracker #9597 | — | inferred — justification: `wg-when-deferring-a-capability-create-a`; Tier 2/3 deferrals without an issue are invisible (filed at plan time) |
| `cutover-verify.sh` exemplar fix | — | inferred — justification: the brief points at this file as the pattern to copy, and it fails Rule D today; a two-flag edit keeps the pointed-at exemplar clean (not host-coupled: no `.tf` or Dockerfile reference) |

### Split Assessment

- Subsystems touched: 7 — `apps/cla-evidence`, `apps/web-platform`, `plugins/soleur`, `.claude`, `scripts`, `tests`, `knowledge-base`
- Planned files: ~85 (57 scripts, ~10 owning tests, lint + 4 baselines/fixtures + ~8 new files, ADR, plan/tasks) | Estimated changed lines: ~1,600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split. Three plan reviewers and the CTO recommended splitting; the thresholds are all exceeded. Proposed boundary: (a) Phases 0-3 (battery, Rule E + baseline, `scripts/**`, followthroughs) and (b) Phases 4-6 (`apps/**`, `plugins/**`, hooks, gate libs) + Phase 7. **Decision: single PR with the phase-ordered commits above, split boundary (a)/(b) kept as the pre-agreed fallback** — justification: the pipeline produces one PR per invocation; the edits are uniform and mechanical; and, with Rule E and baseline E landing first (Phase 1), each phase shrinks the baseline, so "one PR rewrites the baseline twice" no longer applies and a later split costs nothing structural. Recorded as a User-Challenge in `knowledge-base/project/specs/feat-one-shot-7843-argv-bearer-to-config-stdin/decision-challenges.md` for the operator.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 knowledge-base/project/specs/feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py` was re-run at work time before Phase 1 and matched `TOTAL sites=136 files=64` (or the difference is explained in the PR body); after Phase 6 the same command lists exactly the 8 Tier 2 files.
- [ ] `git grep -nE -- '(-H|--header)[[:space:]]+\\?["'"'"']?Authorization:[[:space:]]*Bearer' -- '*.sh' ':!*.test.sh' ':!tests/**' ':!**/fixtures/**' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | cut -d: -f1 | sort -u` returned 58 files at plan time (all in Tier 1 or Tier 2) and returns exactly the 8 Tier 2 files after Phase 6. Printed command text is covered by the same grep (form D lines contain `-H`), so a non-zero residue outside Tier 2 fails this criterion.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py` exits 0 and prints `OK:`; `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0 with every touched file un-baselined.
- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py --census` shows `offenders_e` equal to the baseline-E line count (8), and `offenders`/`offenders_d` strictly smaller than the pre-change 50/24.
- [ ] The A/B/C, D and E baseline diffs contain deletions only versus their Phase 1 state (`git diff -U0 -- scripts/lint-shell-trace-credential-refusal*.baseline.txt | grep '^+[^+]'` prints nothing, E measured against its first commit); no Tier 1 file remains in any baseline.
- [ ] `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0; its dynamic rows were observed RED against the unconverted tree in Phase 0 (recorded in the PR body); the suite is registered in `scripts/test-all.sh` and `bash scripts/lint-orphan-test-suites.sh` reports no orphan.
- [ ] `bash scripts/lint-shell-trace-credential-refusal.test.sh` exits 0 including the new Rule E rows (each of mutation rows 1-9 observed to fail the suite when applied, row 10 observed green).
- [ ] The four non-host infra files carry no reference in `file(`, `filesha256(`, `triggers_replace`, `host_script_files` or the Dockerfile (grep output in the PR body), and the PR body states that the path-triggered infra apply has zero resource delta for them.
- [ ] Every owning test listed in Files to Edit passes; `scripts/lint-followthrough-varq-ban.sh`, `scripts/followthrough-exec-bit.test.sh`, `scripts/sweep-followthroughs.test.sh`, `plugins/soleur/test/fixture-relative-assert.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] No fixture, test or log in the PR contains a real token; fixtures use synthesized values (`cq-test-fixtures-synthesized-only`).
- [ ] ADR-202 carries the dated addendum; #9597 is referenced from baseline E's header comment and the PR body; PR body has `Ref #7797` and `Closes #7843` with the moved scope stated.
- [ ] `bash -n` passes on every touched script; every converted curl keeps `--disable` as its first argument and carries `--noproxy '*'`; `printf` feeding curl is the shell builtin.

## Test Scenarios

- Given a converted followthrough probe and a shim that records argv and stdin, when the probe runs with fixture token `fixture-token-<name>`, then no recorded argv entry contains the token and stdin carries `header = "Authorization: Bearer fixture-token-<name>"`.
- Given the same probe and a shim answering HTTP 401, then the probe exits with its TRANSIENT/FAIL status, never PASS.
- Given a wrapper-based script (`seed-qa-user.sh`) whose calls pipe curl output into `python3`, when run against the shim, then every call carries both `Authorization` and `apikey` on stdin and none on argv.
- Given a response-derived token `a"\nurl = "http://x/y`, when `bsky-community.sh` builds its header, then the form C guard refuses and the shim records zero calls.
- Given an unset or empty token (the script's existing guard fires first), then no curl call is recorded and the exit status is never the PASS status.
- Given `set -o pipefail` and a shim that never reads stdin, when a converted script runs, then its exit status is unaffected by the unread config (process-substitution form).
- Given `compliant-stdin-bearer-header-at-stdin.sh` and `compliant-stdin-bearer-wrapper.sh`, Rule E reports nothing; given each `violation-argv-bearer-*.sh`, Rule E reports exactly one finding per offending call site.
- Given a touched file that is in baseline E, `--changed` reports it (baseline bypass) until it is converted.

## Domain Review

**Domains relevant:** Engineering (security hardening of operator, CI and plugin tooling). No product, marketing, finance, legal, sales, operations-vendor or support surface changes.

### Engineering

**Status:** reviewed
**Assessment:** CTO assessment (spawned at plan time): direction sound; boundary at host-deployed scripts is right (server.tf hashes them into `triggers_replace`); main risk is silent auth break turning follow-through probes false-green, mitigated by the battery's negative-path rows and the post-merge sweeper comparison; recommended strictly ordered commits (compliance, conversion, Rule E), shrink-only baselines with issue links, an explicit stdin-conflict/`-K`/`-u` census, and a split into three PRs (single-PR decision and fallback boundary recorded in Scope Check). Applied: negative-path rows, commit ordering, baseline equality row, census results, post-merge comparison. Plan-review (DHH, Kieran, code-simplicity) applied: detector-first ordering with per-phase baseline shrink, wrapper-aware Rule D/E, `main()` plumbing row, allowlist charset guard, battery scoped to probes and form C sites, ADR addendum trimmed, post-merge comparison dropped, residue tracker filed early, sourced-library trace limit stated. Not applied: live dry-run of converted probes against real APIs (requires reading real tokens; the brief forbids touching token values). GDPR gate: not invoked; the change moves a transport channel for existing credentials and introduces no new processing, store, schema or lawful-basis question (`dsar-export-oversize.sh` and `gdpr-override.sh` change only how their existing auth header is carried).

## Dependencies & Risks

- **Silent auth break (highest).** A conversion that drops the header turns a 200 into a 401; probes that read "no data" as healthy would false-green. Mitigation: battery rows (v), per-site review that status capture (`-w`) and `2>/dev/null` placement are untouched, post-merge sweeper comparison.
- **`--config -` consumes stdin.** Measured zero Tier 1 conflicts; any site added later that needs stdin for a body must use `--data-binary @file`. Rule E does not police this, the battery row (iii) would catch it as a missing header.
- **Test stubs asserting argv.** Stubs that assert `Authorization: Bearer` in argv (e.g. `test-betterstack-ingest-probe.sh:64`) will go red by design; they are updated to read stdin and to assert absence from argv, in the same commit as the script.
- **Baseline interaction.** `--changed` makes 19 baselined files fully A/B/C/D-clean in this PR; the prerequisite commits are separate and small.
- **Plugin-shipped scripts** run on users' machines: bash-only constructs already present in each file, no new dependency.
- **Tier 2 re-introduction window.** Until #9597 lands, the 8 host scripts keep argv bearers; baseline E names them so growth elsewhere cannot hide.
- **`--changed` is advisory.** ci.yml:231 runs in the non-required `lint-bot-statuses` job; the blocking enforcement is the repo-wide run inside the required `test` context. The touched-file drawdown trigger therefore surfaces in review, and growth is blocked.
- **Large PR.** Split fallback at the Scope Check boundary.

## References & Research

#7843, #7797, #7842, #7898; ADR-202, ADR-263, ADR-198; `scripts/lint-shell-trace-credential-refusal.py`; `tests/scripts/test-sentry-alert-live-fidelity.sh`; `apps/web-platform/infra/cutover-verify.sh`; `scripts/supabase-logs-query.sh`; post-mortem `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`.

Spec lacks valid `lane:` (no `spec.md` exists for this branch): defaulted to `cross-domain` (fail-closed).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- `--changed` (what CI runs) bypasses every baseline, so touching ANY script in a baseline makes it fully Rule A/B/C/D-clean in the same PR. That is why Phases 2-6 carry a prerequisite commit per group and why 19 files cost more than their conversion alone.
- The new battery must be registered in `scripts/test-all.sh` by hand and verified with `lint-orphan-test-suites.sh`; an unregistered suite reads as coverage and never runs.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` is a row-by-row equality baseline with per-file counts for several Tier 1 scripts (`dsar-export-oversize.sh`, `weekly-analytics.sh`, `sentry-monitors-audit.sh`, ...). A script edit that moves a count turns that suite red; regenerate in the same commit, never loosen it.
- Followthrough probes are constrained by `lint-followthrough-varq-ban.sh` (no `: "${VAR:?}"`), `trusted-verdict.sh` routing and the exec bit; a conversion edits only the curl invocation.
- `#!/bin/sh` and process substitution do not mix: the only such script (`soleur-host-bootstrap.sh`) is Tier 2 and will take the pipe form there, where pipefail does not exist in dash.
- Tests that stub curl and assert the bearer text in argv (`test-betterstack-ingest-probe.sh:64`) go red BY DESIGN when the script converts; update the stub to read stdin and assert the token is absent from argv, never loosen it to accept either.
- Co-travelling credential headers (`apikey:`) must move with the bearer in the same config stream; converting only the `Authorization` line leaves the identical key on `ps`.
- A response-derived token needs the form C guard BEFORE it is formatted into the config stream; the format string stays a literal `%s` template.
- Rule E's baseline equals the live offender set exactly (growth and shrink both need a regeneration commit); do not hand-edit it to excuse a script.
- No step runs a converted probe with a real credential (the brief forbids touching token values); the next scheduled sweeper run is the live signal and no criterion depends on it.
