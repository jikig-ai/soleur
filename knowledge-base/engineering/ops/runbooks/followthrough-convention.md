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

## Security guarantees

- Verification scripts are code-reviewed at PR time and live committed in the repo. Issue body editors cannot inline-execute code, only reference an existing path.
- The sweeper exports a narrow allowlist of secrets (declared per-script), not the full workflow env.
- Issue body content reaches the sweeper via `awk` on stdin (no shell interpolation). Directive values are passed to the verification script as environment values and command-line args, never via shell-evaluated strings.
- The sweeper uses `gh` CLI for issue close/comment, not raw token interpolation.

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
