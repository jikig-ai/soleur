# Follow-Through Convention

A `follow-through` is a tracker issue whose closure depends on wall-clock
time passing AND a verifiable condition being true (e.g. "wait 48 hours
then check that Sentry monitors received check-ins"). The
follow-through sweeper closes them automatically when both gates pass.

## Why

Without automation, the engineer who filed the tracker has to remember
to come back and check. Sessions close, calendar reminders get lost,
and the issue rots open. With the sweeper, the issue closes the day the
verification passes — no human revisit required.

## Author workflow

1. **File the tracker** with label `follow-through` and a clear close-criteria description in the body.
2. **Write the verification script** under `scripts/followthroughs/<short-name>-<issue-num>.sh`. Conventions:
   - Exit 0 = PASS (close-criteria met → sweeper closes the issue)
   - Exit 1 = FAIL (criteria not met → sweeper comments, leaves open)
   - Any other exit = TRANSIENT (network failure, timeout → sweeper retries next sweep)
   - The script may print human-readable output to stdout/stderr; the sweeper captures the last 4 KB and posts it as a comment.
   - The script must be deterministic in its exit semantics: do not exit 0 on partial success.
   - **Never gate the exit code on `: "${VAR:?msg}"`.** Under a non-interactive shell that word-expansion aborts with status **1** (= FAIL in this contract), so a trailing `|| { echo TRANSIENT; exit 2; }` is dead code and an unprovisioned/empty secret reports FAIL instead of TRANSIENT. Use `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi`. **Enforced mechanically by `scripts/lint-followthrough-varq-ban.sh`** (registered in `scripts/test-all.sh`, merge-blocking `test-scripts` shard; #6757) — a banned form on any executable probe line reddens CI. Accept both `200` AND `201` from the Supabase Management query endpoint (`/database/query` returns 201). Verified in `scripts/followthroughs/autovacuum-thrash-6168.sh` (PR #6164) — see `knowledge-base/project/learnings/best-practices/2026-07-07-followthrough-and-shape-gate-silent-falseness.md`.
   - **Query a sink the signal is ACTUALLY written to, and fail-safe when the signal path is unproven.** A soak that greps a sink the target signal never reaches PASSes vacuously and auto-closes the tracker blind (#5934: queried Sentry for an in-sandbox line that this host's `vector.toml` never mirrors to Sentry — only Better Stack). Verify the emit→sink wiring before trusting a zero-count; require a positive liveness marker (proof the producer ran) before treating "zero bad events" as PASS, and exit **TRANSIENT** (not PASS) on any auth/query failure or missing-liveness — so the gate can never false-close.
3. **Declare needed secrets** via the directive's `secrets=` clause. Only the named secrets get exported into the script's environment. Add the secret to `.github/workflows/scheduled-followthrough-sweeper.yml` `env:` block if it isn't already wired.
4. **Add the directive** to the issue body:

   ```html
   <!-- soleur:followthrough
     script=scripts/followthroughs/sentry-checkins-3859.sh
     earliest=2026-05-17T18:00:00Z
     secrets=SENTRY_AUTH_TOKEN
   -->
   ```

   Place it inline anywhere in the body. Multiple directives in one body: only the first is honored.

5. **Open a PR** that lands the script + (optionally) any new secrets in the workflow env. CI on the PR includes the workflow file's syntax check.

## Directive fields

| Field | Required | Notes |
|---|---|---|
| `script` | yes | Path MUST start with `scripts/followthroughs/`. Other paths are refused (defense against tampered issue bodies pointing at arbitrary files). |
| `earliest` | yes | ISO-8601 UTC timestamp. The sweeper skips the issue until `now >= earliest`. |
| `secrets` | optional | Comma-separated GitHub secret names. Only these are exported into the script's environment. Omit if the script needs no secrets. |

## Trigger → verification mapping

Deferred-scope-out issues (filed by `/soleur:review` §5) carry a **re-evaluation
trigger** in one of four concrete shapes. The review skill auto-wires each into
this substrate: it adds the `follow-through` label, scaffolds a verification
script (from [`../../../../plugins/soleur/skills/ship/references/followthrough-stub-template.sh`](../../../../plugins/soleur/skills/ship/references/followthrough-stub-template.sh)),
and embeds the directive — so the issue auto-closes the moment its trigger fires
instead of rotting open. Each trigger shape maps 1:1 to an exit-code probe:

| Trigger shape | `earliest=` | `secrets=` | Verification script body (fill into the stub) |
|---|---|---|---|
| **Date** — `Re-evaluate by YYYY-MM-DD` | `<date>T00:00:00Z` | none | trivial `exit 0` (a real `exit 0` script file is still required — the gate rejects an empty/absent `script=`); the `earliest` wall-clock gate alone defers closure until the date |
| **Dependency** — `Re-evaluate when #N lands` | filing date | `GH_TOKEN` | `[[ "$(gh issue view N --json state --jq .state)" == CLOSED ]] && exit 0 \|\| exit 2` |
| **Event-grep** — `Re-evaluate when <pattern> matches in <corpus>` | filing date | `GH_TOKEN` (gh corpus) | corpus probe nonempty ? `exit 0` : `exit 2` — e.g. `gh run list --workflow X --status success --created ">=<cutoff>" --json conclusion \| jq -e 'length >= 1' >/dev/null && exit 0 \|\| exit 2` |
| **Counter** — `Re-evaluate when <counter> exceeds <threshold>` | filing date | `GH_TOKEN` (gh/API counter) | `[[ "$count" -ge "$threshold" ]] && exit 0 \|\| exit 2` where `$count` comes from `gh`/SQL/grep |
| **Soak** — `<signal> stays at ~0 for N days post-deploy` (often gating an ADR `adopting → accepted` flip) | `<deploy>+Nd` (UTC; gates the first check to after the soak window) | `SENTRY_AUTH_TOKEN` (Sentry-rate soaks) | rate==0 over a window pinned strictly after deploy ? `exit 0` : `exit 1` — mirror [`reconcile-ff-only-sentry-4977.sh`](../../../../scripts/followthroughs/reconcile-ff-only-sentry-4977.sh) / [`ac8-founder-ambiguous-soak-5673.sh`](../../../../scripts/followthroughs/ac8-founder-ambiguous-soak-5673.sh) (`start=` pins the window past deploy so pre-deploy events don't contaminate the verdict). Enforced at ship time by the **Soak-Gated Follow-Through Enrollment Gate** (ship/SKILL.md Phase 5.5) — a soak declared in PR/plan prose blocks PR-ready until its tracker is enrolled here. |

**`secrets=GH_TOKEN` is MANDATORY for any gh-using probe.** The sweeper runs
verification scripts under `env -i` (PATH + HOME + directive-declared `secrets=`
ONLY). On the CI runner `gh` authenticates from `GH_TOKEN`, not `~/.config/gh`,
so a gh-using script with NO `secrets=GH_TOKEN` is unauthenticated → `gh` fails →
the probe returns exit 2 (transient) on every sweep and the issue **never closes**
(a silent never-close, not a loud failure). The date shape is the only one that
needs no `secrets=` (its body never calls `gh`). This is the same opt-in
mechanism `sentry-checkins-3859.sh` uses (`secrets=SENTRY_AUTH_TOKEN`).

**Exit contract** (same as Author workflow): `0` = PASS → sweeper closes;
`1` = FAIL → sweeper comments + leaves open (reserve for a genuine "this should
NOT close" regression, not a not-yet condition); any other exit = TRANSIENT →
retry next sweep (use `exit 2` for "the trigger has not fired yet").

**`earliest=` semantics.** It is a hard wall-clock gate evaluated BEFORE the
script runs (`scripts/sweep-followthroughs.sh` skips the issue until
`now >= earliest`). For the **date** shape it IS the verification. For
dependency / event-grep / counter shapes the *script* self-gates via its
transient exit, so set `earliest=` to the filing date — do NOT set a far-future
`earliest=` (that double-gates and delays verification).

**Scaffolding contract.** `cp` the stub template → replace the TODO body with the
probe for the trigger shape → `chmod +x` → embed the directive (include
`secrets=GH_TOKEN` for any gh-using shape — dependency / event-grep / counter).
The script must exist + be executable on disk BEFORE `gh issue create --label
follow-through` runs — `.claude/hooks/follow-through-directive-gate.sh` (and the
sweeper) reject a missing/non-executable `script=` path. For review-time filings
the script lands in the review PR's branch.

**First deferred-scope-out instance**: #3950 (review: cla-evidence scripts
hardening bundle) — `scripts/followthroughs/cla-evidence-hardening-3950.sh` is the
worked event-grep example (asserts the 4 hardening markers are intact, then
probes for a post-PR-#4784-merge green `cla-evidence.yml` run; `earliest=` is the
merge timestamp; its directive declares `secrets=GH_TOKEN`).

## Security guarantees

- Verification scripts are code-reviewed at PR time and live committed in the repo. Issue body editors cannot inline-execute code, only reference an existing path.
- The sweeper exports a narrow allowlist of secrets (declared per-script), not the full workflow env.
- Issue body content reaches the sweeper via `awk` on stdin (no shell interpolation). Directive values are passed to the verification script as environment values and command-line args, never via shell-evaluated strings.
- The sweeper uses `gh` CLI for issue close/comment, not raw token interpolation.

## Sharp edges for Better Stack log-content probes

- **Discriminate on the journald SYSLOG_IDENTIFIER FIELD, never a bare payload substring, and model fixtures on the REAL escaped JSONEachRow shape.** The Vector source is shared: inngest ships GitHub-webhook logs (SYSLOG_IDENTIFIER=doppler etc.) that embed branch names, issue/PR bodies, and quoted marker strings — so any marker a human types into GitHub appears in *another* producer's rows, and a bare-substring probe self-contaminates (the tracker's own body quotes the marker → false-FAIL → sweeper re-seeds it). Isolate the field in both byte-forms: server `--grep 'SYSLOG_IDENTIFIER":"<tag>'` (LIKE, unescaped column) + client `grep -F 'SYSLOG_IDENTIFIER\":\"<tag>\"'` (escaped stdout). Fixtures must reproduce the escaped JSON `raw`, not bare syslog. **Run the live discoverability query at /work, not post-merge** — it is the only check that surfaces the escaping and the contamination before merge. See `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` (#6475).

## What the sweeper does NOT cover

- **One-shot scheduling**: every sweep checks every open follow-through. If you want a script to run exactly once at a specific timestamp, that's a regular scheduled workflow, not a follow-through.
- **Inline scripts**: scripts must be committed. We considered allowing inline shell in directives and rejected it for security.
- **Multi-step verification**: each script is one binary pass/fail. For verifications that span multiple days with different criteria, file multiple follow-through issues that block each other.

## Operator reference

- **Workflow**: `.github/workflows/scheduled-followthrough-sweeper.yml`
- **Driver script**: `scripts/sweep-followthroughs.sh`
- **Manual run**: `gh workflow run scheduled-followthrough-sweeper.yml`
- **Dry run**: `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true`
- **First user**: #3859 (Sentry cron monitor check-in receipts after #3849 rotation)
