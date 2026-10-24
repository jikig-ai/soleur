# Alert-Channel Sweep — postmerge Phase 3.9

A green deploy verdict says production serves the merge; it says nothing about what the alert
channels reported while it landed. On 2026-10-22 the two inngest heartbeat monitors paged
correctly into an unwatched email inbox — detection was timely, notice was late (epic #10390,
ADR-297). This phase reads the two watched alert surfaces once, after the deploy verdict — the
same advisory idiom as the Phase-3.5 inngest-down read: report, never hard-block. The always-on
arm is `scheduled-betterstack-incident-mirror.yml`; this phase is the merge-time point read, and
`scripts/followthroughs/post-deploy-incident-soak.sh` is the enrollable time-windowed
complement.

**(a) `ci/` GitHub issues opened since the merge commit.** Every watchdog and standing alarm
files under a `ci/*` label (`ci/inngest-down`, `ci/betterstack-incident`, `ci/zot-restart-loop`,
… — the whole family, not only `ci/inngest-*`). Two Bash calls (no command substitution): first
the merge commit's timestamp, then the windowed list filtered to the `ci/` label family:

```bash
gh api repos/{owner}/{repo}/commits/<full-merge-sha> --jq '.commit.committer.date'
```

```bash
gh issue list --state all --search "created:>=<committer-date-from-above>" --limit 100 \
  --json number,title,createdAt,labels \
  --jq '[.[] | select([.labels[].name | startswith("ci/")] | any)] | .[] | "#\(.number) [\(.labels | map(.name) | join(","))] \(.title) (opened \(.createdAt))"'
```

**(b) Better Stack open incidents.** `BETTERSTACK_API_TOKEN_READONLY` from Doppler
`prd_terraform`; project each incident to `{id,name,started_at}` — the raw objects carry
`acknowledged_by` and screenshot URLs, and the Phase-6 comment republishes printed lines
(public-comment discipline; `scripts/betterstack-query.sh` is the Logs path, not this one —
incidents live on the uptime API):

```bash
BS_TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform --plain 2>/dev/null)
# argv shows in /proc/<pid>/cmdline, so the token rides curl's stdin config. Bash only; `bash -x` would print the token.
# Advisory phase: a missing or malformed token SKIPS (exit 0), it never fails the run.
if ! (LC_ALL=C; case "$BS_TOKEN" in ''|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac); then
  echo "WARNING: BETTERSTACK_API_TOKEN_READONLY (Doppler prd_terraform) unset or not [A-Za-z0-9._~+/=-] (refused, not sent). Better Stack incidents: SKIPPED."
else
  curl --disable --noproxy '*' -g --proto '=https' --max-redirs 0 -m 30 -fsS --config - \
    "https://uptime.betterstack.com/api/v2/incidents?resolved=false&per_page=50" \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$BS_TOKEN") \
    | jq '[.data[] | {id, name: .attributes.name, started_at: .attributes.started_at}]'
fi
```

- Both reads empty → `Alert-channel sweep: clean`.
- Any rows → `Alert-channel sweep: <verbatim rows>` — a `ci/` filing or an open vendor incident
  in the report is a real page to name, never a merge blocker; the filing watchdog owns its own
  remediation. An incident that predates the merge still counts: `resolved=false` is a point
  read of what is open NOW, not a window read — the deploy-window caveat applies to the `ci/`
  half only.
- Token/Doppler unavailable, or the API unreadable → `Alert-channel sweep: SKIPPED (<cause>)` —
  the mirror workflow is the always-on arm, so a skipped point read loses nothing continuous.
  The `ci/` half needs no token and always runs.

**Graceful degradation:** advisory end to end — a Better Stack API failure or absent token does
not block the pipeline (see [graceful-degradation.md](./graceful-degradation.md)).
**Advisory only — never hard-block the turn.**
