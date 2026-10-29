# Learning: a legal determination inherits two kinds of evidence it never measured

## Problem

PR 11443 recorded the CLO determination for the gated-approval-tier bypass (issue 11303). Its first draft read cleanly and passed three legal lints, yet the review panel and the fix-round found the same defect class in about twenty places: a claim worded more strongly than the evidence behind it.

Two shapes recurred and both were inherited rather than measured:

1. **A serving claim with no host.** The post-merge comment on 11303 said production `/health` reported build `00f92f98` at 17:53Z. It did not say which host answered or when that build began serving. The memo, the breach-register row, the Art. 30 markers and both LIA addenda each restated it as "verified fixed on web-1" and "the gate operates on the verified host(s)". Five artifacts agreeing was one unverified sentence copied five times.
2. **A default state read as a signal.** The limb for workspace autonomy treated "4 of 20 workspaces have autonomy ON, 3 without a disclosure acknowledgement" as exposure evidence. Migration 099 sets the column default to ON with a NULL acknowledgement (the first-run hold), so that is the ordinary state of a new workspace. Migration 159 had also NULLed every earlier acknowledgement and moved the old value to a `superseded_at` column. The discriminating fact (all four `superseded_at` values NULL, so none had an acknowledgement reset) was one query away and absent from the draft.

Related telemetry traps, already in the memo but worth keeping together: `audit_github_token_use` has a writer that none of the gated GitHub tools reach, `messages.tool_calls` is never populated, and the Doppler audit log does not name secrets per entry. An empty read from any of these says nothing about the event.

## Solution

- Replaced every "web-1 verified" and "17:53Z post-merge check" claim with "production `/health` reported build `00f92f98` at the 17:53Z check (host not identified, serving start not dated)". The exposure end became "no later than 17:53Z for the host that answered `/health`; soleur-web-2 unconfirmed", and `mergedAt` was kept only as the time the fix entered `main`.
- Rewrote the autonomy limb from migrations 099 and 159: ON with a NULL acknowledgement is the default, none of the four had a reset, and the legacy runner applies neither the toggle nor the hold (`agent-runner.ts` builds `createCanUseTool` with none of the autonomy dependencies). A reset is recommended only for ON workspaces that pre-date 099, have no acknowledgement and no superseded stamp, and only after the owner confirms.
- Added the missing instruments (web-2 serving check, access counts for share links, deletion survivorship) and a time-box so an undecided limb lapses visibly rather than staying open under a SIGNED-OFF label.

## Key Insight

Before a determination quotes a value as evidence, ask two questions of it: which host or actor produced it, and what is the value when nobody did anything? A summary line that omits the host cannot support a per-host claim, and a column whose default equals the "suspicious" value cannot support an exposure claim without the migration history that explains it. Both checks cost one command each (`gh api` for the comment's context, `git log -S` on the migration), and neither appears in the lints that gate a legal PR.

## Session Errors

1. **A serving claim was restated across five artifacts without naming its host** — Recovery: fix-round replaced it everywhere with the measured wording. Prevention: when a determination cites a post-merge verification, copy the comment's exact scope (host, time, what was queried) and run `gh api repos/{o}/{r}/issues/<n>/comments` to confirm the comment names the surface before using a per-surface word like "verified".
2. **A column default was read as exposure evidence** — Recovery: re-derived from migrations 099 and 159 and a `superseded_at` query. Prevention: before treating a column value as a signal, grep the migrations for its default and for any later rewrite of it (`git grep -n "<column>" apps/*/supabase/migrations`).
3. **Guessed production column names (`beta_contacts.owner_id`, `beta_contact_stage_transitions.created_at`)** — Recovery: read `information_schema.columns` and re-ran. Prevention: query `information_schema.columns` for every table before the first aggregate, as was done for the other tables.
4. **`doppler activity -p` rejected** — Recovery: used `doppler configs logs -p … -c …`. Prevention: run `doppler <subcommand> --help` before passing project flags.
5. **A foreground `sleep` was blocked by a hook** — Recovery: stopped waiting on the background task and let its completion notification arrive. Prevention: wait on a background task through its notification, not a sleep.
6. **A turn ended on a first-person commitment and the stop hook refused it** — Recovery: ended on a single `Paused:` sentence naming the wait. Prevention: when waiting on background agents, state the wait and the fact, not a promise to act.

## Tags
category: security-issues
module: legal-determinations
