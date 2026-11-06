---
title: Production-HOME census (counts only)
date: 2026-10-31
tracker: 10455
---

# Production-HOME census (counts only)

A counts-only, metadata-only, read-only census of the shared HOME in the web-platform container. Authorization: the controller's
comment 6546444433 on #10455. Legal method: the CLO ruling with conditions C1-C10 and the dissent-round rulings D1-D9, recorded in
`knowledge-base/project/specs/archive/20261031-224809-feat-one-shot-10455-prod-home-census/decision-challenges.md`. Building and merging the mechanism does
not run it. The purge of already-persisted shared data and the deploy-smoke promotion (PR 2) are not part of this runbook.

One real run, at most two; the second only after a recorded `young` result. If no mature window occurs before the sunset, the census
ends unrun at maturity. The census will run only when the CLO's conditions are met.

## What it is

`POST /api/internal/home-census` (Bearer `INNGEST_MANUAL_TRIGGER_SECRET`, header only). It uses `lstat` and `opendir`/`read` only, never
opens a file, never retains a name, and returns one bucketed-counts object. Buckets: `0`, `1-4`, `5-19`, `20-99`, `100-999`, `1000+`.
It writes the object to the HTTP caller, one Sentry event and one pino line at level `warn` (Vector ships only `level >= 40`).
The route returns 410 after `SUNSET_UTC` in `apps/web-platform/server/home-census.ts`.

Uptime is the age of the Node process. The HOME is the container's writable layer. It is wiped when the container is recreated (every
deploy; see the `docker stop` then `docker run` swap in `ci-deploy.sh`), not on a restart-policy restart, so process uptime can
understate the age of the counted layer. It errs toward `young`. A count is a count of this container's writable layer at the run,
never a statement about earlier containers or other hosts. A zero is never "clean".

## Fields (decode table)

- `evidence`: `young` under 24 h of process uptime, else `mature`. `uptime_bucket`: `lt_1h`, `lt_24h`, `lt_7d`, `ge_7d`.
- `class_result` per class: `counted` (entries seen; a lower bound when the class was cut off), `none_counted` (visited, nothing cut
  off, no errors, zero entries; for a trigger class this also needs the session-artifact witness), `inconclusive` (a zero in a trigger
  class without that witness), `unknown` (not visited, cut off, a link with nothing counted behind it, a symlinked `.claude`, or errors).
  A root that exists but cannot be listed (for example another user's home) is reported in `roots` and is not scanned.
- `activity_witness`: a session artifact was counted (`sessions_json` or `shell_snapshots` nonzero). `account_state` is not a witness:
  any CLI start writes it.
- `trigger_class_nonzero`: a routing label, never quoted. `true` if any of `history_jsonl`, `debug`, `todos`, `tasks` is counted; else
  `unknown` if any is `unknown`; else `inconclusive` if any is `inconclusive`; else `false` (every trigger class read `none_counted`).
  The only sentence that may be derived from `inconclusive` or `unknown` is: "Insufficient evidence, not a negative finding."
- `truncated` and `truncation_reason` (`entry_cap`, `time_cap`, `load_shed`, `class_budget`), `control` (`passed`/`failed`),
  `data_source` (`synthetic` for a dry_run, `container_home` for a real run), `roots`, `roots_distinct`, `roots_note`,
  `claude_config_dir_set`, `mode_bits_semantics` (file mode only, not reachability), `snapshot` (`non_atomic`).

## Before you run (tools and numbers)

The trigger script needs `doppler` (authenticated for `soleur`/`prd`, read only), `gh` (authenticated as the pinned account), `jq`,
`git` (a checkout of the repository with `origin`) and `curl`. `bash apps/web-platform/scripts/home-census-trigger.sh --self-check`
is offline and prints `HOME_CENSUS_TRIGGER_SELF_CHECK_OK`; it checks the trigger, not the signal.

`<N>` is the next unused `run_id`: above every `home-census run_id=N claim` comment on #10455, starting at 1.
Two real starts must be at least 3600 s apart (a server limiter per process); a real run inside that hour is refused with
`rate_limited` after its claim was written, so wait the hour. Run the script from the repository checkout (it refuses a copy).

## Steps (no SSH, no `docker exec`)

1. **Preflight (no scan).** `bash apps/web-platform/scripts/home-census-trigger.sh --mode dry_run --run-id <N>`. It scans a synthetic
   in-memory HOME, consumes no `run_id`, and reports the real `uptime_bucket`, `evidence`, `build_sha` and `sunset_utc`.
   A real run needs `evidence: "mature"` (container uptime of 24 h or more, condition C9).
2. **The real run** (only after C8 is recorded, see below):
   `bash apps/web-platform/scripts/home-census-trigger.sh --mode real --run-id <N> --discharged-sha <sha> --pr <PR>`.
   The script checks the pinned-author C8 comment, the CLO record of the served build, the bound paths, the two-run cap and the
   write-ahead claim, then posts the request and prints the body only if it validates against the allowlist schema.
   `--c9-fallback` skips the maturity check and sends `accept_young`; it is allowed only for the second run after a recorded `young`
   first result, and only with the controller's message naming it.
3. **Read the signal** (credentials required), not "exactly one row": every dry_run, including the preflight inside a real run, writes
   a result line too. Filter on `"data_source":"container_home"` and `"mode":"real"`:
   `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep "home-census result" --limit 20`.
   Refusals use a different message: `home-census refused` (Sentry search `message:"home-census refused"`, tag `error_class`; the same
   text in the log). Result events: Sentry search `message:"home-census result"`, tags `mode:real` and `data_source:container_home`.
   Zero rows for the real run means "pino line not shipped" or "not run": triage by log level, then the HTTP response, then retention.

Exit codes of the script: 0 ok, 2 usage, 3 secret, 4 unauthorized or not found, 5 forbidden, 6 server error (a real run: the scan may
have run, read Sentry and Better Stack and do not retry; a dry_run: safe to retry), 7 the real request did not complete (ambiguous; same
rule), 8 governance refusal, 9 build mismatch, 10 a 2xx body failed the allowlist schema (a real run: the scan ran), 11 refused by the
server (409, 410, 429, and a 503 whose body is the exact closed failure shape; the `error_class` is printed), 12 the preflight did not
complete (safe to retry), 78 shell tracing refused. A 503 without that shape (a proxy page) exits 6. The public `done` marker is posted for every outcome that reached the server except exit 6 and 7;
for those the executor posts `home-census run_id=N done` by hand after reading Sentry and Better Stack.

| Outcome | What it means | Next |
|---|---|---|
| 503 `control_failed` | the known-answer control or the canary failed; no scan ran and no slot was used | read Sentry `home-census refused`; a code fix voids C8 |
| `truncated: true` | a cap ended the scan; the result is final for that run (raising a cap voids C8) | report as incomplete; never "census complete" |
| `unknown` or `inconclusive` classes | not a negative finding | report with the sentence above; no public object |
| exit 6 / 7 | ambiguous | read Sentry and Better Stack first; search `trigger_class_nonzero:true` before any retry |

## Conditions before a real run

- **C8:** the CLO re-read the final bound diff and wrote a line consisting only of `DISCHARGED sha=<40-hex>` into
  `knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md`; only then does the controller post
  `home-census C8 DISCHARGED sha=<sha> pr=<PR>` on #10455. The script refuses a real run unless the CLO record of the served build
  carries the same line and the served build's bound paths equal the discharged commit. Bound paths: `server/home-census*`, the route
  directory, `lib/internal-auth.ts`, `server/sentry-scrub.ts`, `sentry.server.config.ts` and the trigger script (also compared to the
  working tree, which must be clean). Not bound: `infra/vector.toml` (it only drops lines) and `lib/routes.ts` (it only registers the
  path); the script prints their diff against the discharged commit and a new transform, enrichment, field or route prefix is a stop.
  `pino` and `@sentry/*` version bumps are an accepted residual.
- **Governance is self-attested.** The two-run cap, the write-ahead claim and the C8 DISCHARGED line are enforced by the trigger script
  against comments from the pinned GitHub account, which is also the account the executing session runs as. The server enforces only
  build match, uptime maturity, a per-process load limiter and an in-flight flag. The DISCHARGED comment is posted only after the CLO's
  re-read is written into the committed CLO record file. The script refuses a real run unless that record carries the same sha. A run
  made outside the script, or a DISCHARGED comment without that record, is out of policy and is reported to the controller and the CLO
  the same day. A comment counts only when its whole body is one governance line.
- **C9:** the preflight reports `evidence: "mature"`. At most two real runs in total.
- **C7 (sunset):** the fixed `SUNSET_UTC` is the operative hard-disable and must be at most merge date + 30 days. One extension of at
  most 15 days is allowed, from a PR that touches only that constant (a fresh CLO re-read and DISCHARGED follow, because the constant is
  in a bound file); it may not set the sunset later than the last claimed run + 30 days, is not allowed after a mature real run or after
  two claims exist, states the arithmetic in the PR body, records its reason on #10455, and keeps total standing time under 60 days.
  Dead code is deleted under #11714 within 30 days of the last real run, or at the sunset if none occurred, whichever is earlier.
  Removal checklist (everything the deletion PR removes): `git grep -ln home-census` outside `knowledge-base/`, plus the
  `PROMOTED_FILES` entries in `scripts/guard-vacuity-floor.test.sh`.

## Result handling

- **Owner:** the engineering session started on the tracker after the follow-through `earliest`. The full object goes only to the
  controller and the CLO, in the session, the same day.
- **Public tracker:** `home-census run_id=N done` for every outcome that reached the server, and the claim comments. The full object is
  never posted to GitHub and never written to the working tree, a commit or a PR text. Bucketed counts reach Sentry (per-class
  `n_entries` and `class_result` plus run-level tags) and Better Stack (one line with the full bucketed object) by design, under existing
  retention with no extension, readable by those tools' existing members. Publication rules (a)-(e) govern the public tracker only; they
  do not govern what Sentry and Better Stack hold.
- **When the object may be posted:** (a) The whole object may be posted immediately when `control` passed, the scan was not truncated,
  `errors` is `0`, `trigger_class_nonzero` is `false` (every trigger class read `none_counted`, so the witness was present), and
  `other_under_claude` is `0`. If any trigger class reads `inconclusive` or `unknown`, the full object goes only to the controller and the
  CLO in the session, and the public tracker gets only `done`. The executor says nothing about a delay. (b) With `trigger_class_nonzero`
  `false`, a nonzero in `shell_snapshots`, `account_state` or `sessions_*` may be posted immediately with the sentence "Entries (bucket)
  were counted in class C. No names or content were opened." (c) A nonzero in `projects` is held until the CLO has read it. (d) Any
  nonzero trigger class holds the whole object until the determination is recorded. (e) The object appears in the public repository
  only in or after the re-open addendum commit.
- **Wording.** Young zero, witness present: "At the run, a young container (process uptime bucket X) counted 0 in class C. Insufficient
  evidence, not a negative finding." Mature zero, witness present: "None counted in this container's writable layer at the run (process
  uptime bucket X). Earlier containers are not measured. This is a count at one time, not a statement about any time before or after the
  run." No witness, young or mature (session and record only, never with the object on the tracker): "At the run, no session-artifact
  entries were counted in this container (process uptime bucket X), so a zero in the other classes cannot be read as a negative result.
  Insufficient evidence, not a negative finding." Nonzero: "Entries (bucket) were counted in class C, which we presume from the CLI's
  writer behaviour to hold prompt text. No names or content were opened, and whether any sibling can read them is not established by
  the census."
  Never say: clean, no exposure, secure, isolated, protected, private, not readable, empty, no activity, nothing happened, negative
  result (other than the "not a negative" sentences above), "census complete" (when truncated or the control failed), no prompt text,
  found prompt text, leaked.
- **Support.** No ad-hoc replies about data on shared hosts. Inquiries go to the controller and the CLO. Holding line: "we are
  reviewing how session state is scoped on our hosts and will update you". Never "safe", "isolated", "no evidence of access" or
  "not a breach".

## Re-open procedure (any trigger class nonzero)

Trigger classes (presumptive by the CLI's writer behaviour; no content is read): `history_jsonl`, `debug`, `todos`, `tasks`. A zero
never triggers. `projects` is informational (used for sizing). `shell_snapshots`, `account_state` and `sessions_*` are already
conceded reachability classes; a nonzero in `other_under_claude` is a flag to the CLO.

0. **Freeze first:** every user statement about data isolation or safety and all public legal-document edits stop at once, before the
   steps below. To make the freeze executable, list what is live: scheduled or draft distribution items
   (`grep -L '^status: published' knowledge-base/marketing/distribution-content/*.md`), pages that make isolation claims
   (`grep -rli isolat plugins/soleur/docs/pages`), and the legal pages. The CLO names the items to hold. A CTO owner and a time-box for
   the relocation decision are named at the re-open, because the exposure continues until the container is next recreated.
1. Anchor = the Sentry event timestamp, cross-checked with the Better Stack row time and the HTTP `Date` header; record it as the
   fresh awareness anchor.
2. Append a dated re-open addendum to `knowledge-base/legal/audits/2026-10-31-clo-determination-10455-shared-home-sibling-read-art-4-12.md`
   and amend the provisional breach-register row in-cell, marking each superseded sentence. The Art. 33 clock starts only on
   second-limb evidence (a demonstrated sibling read).
3. Freeze as in step 0; support answers go through the CLO.
4. Run a G2-style repository test (synthetic tenants only) of whether the sibling's mount view reaches those classes.
5. No content snapshot or volume copy (it would create a second copy of prompt text). Deploys are not held for evidence and a
   security-critical deploy proceeds. A counts-only repeat needs a fresh typed message from the controller.
6. Engage external counsel with the audit record and the bucketed counts only.
7. Art. 33(2): a nonzero alone does not trigger processor-to-controller notice; it is owed without a risk threshold on evidence of a
   sibling read. Check the tenant DPA's own notification clause first (`knowledge-base/legal/data-processing-agreement-template.md`).
8. The CLO sizes the purge from the `n_entries` buckets. The purge is irreversible, needs a per-command go-ahead from the controller,
   and is not part of this runbook.
9. The ADR-075 relocation trigger "the census finding readable prompt text in the production HOME" is presumptively met; the CLO
   advises the CTO to relocate, because a purge without relocation recurs.

After a mature zero with the witness present no scheduled repeat is owed; repeat on a CLI version bump or when the class list changes.

## Not measured

`/workspaces`, `/tmp/.cs`, `CLAUDE_CONFIG_DIR`, the second web host, the canary container and outer-wrap cohorts are unmeasured. Adding any of them needs a fresh typed message from the controller. A hung filesystem call leaves the route answering 409
`busy` until the process restarts; that is deliberate.

## Retention

Existing and unchanged: Sentry plan-level retention, and Better Stack per `betterstack-log-query.md`. No extension.
