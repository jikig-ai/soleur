---
title: Production-HOME census (counts only)
date: 2026-10-31
tracker: 10455
---

# Production-HOME census (counts only)

A counts-only, metadata-only, read-only census of the shared HOME in the web-platform container. Authorization: the controller's
comment 6546444433 on #10455. Legal method: the CLO ruling with conditions C1-C10, recorded in
`knowledge-base/project/specs/feat-one-shot-10455-prod-home-census/decision-challenges.md`. Building and merging the mechanism does
not run it. The purge of already-persisted shared data and the deploy-smoke promotion (PR 2) are not part of this runbook.

## What it is

`POST /api/internal/home-census` (Bearer `INNGEST_MANUAL_TRIGGER_SECRET`, header only). It uses `lstat` and `opendir`/`read` only, never
opens a file, never retains a name, and returns one bucketed-counts object. Buckets: `0`, `1-4`, `5-19`, `20-99`, `100-999`, `1000+`.
It writes the object to the HTTP caller, one Sentry event and one pino line at level `warn` (Vector ships only `level >= 40`).
The route returns 410 after `SUNSET_UTC` in `apps/web-platform/server/home-census.ts`.

**Uptime means since the last container start.** The HOME is the container's writable layer and is wiped at every start. A count is
"counted in this container since its last start", never a statement about earlier windows or other hosts. A zero is never "clean".

## Steps (no SSH, no `docker exec`)

1. **Preflight (no scan).** `bash apps/web-platform/scripts/home-census-trigger.sh --mode dry_run --run-id <N>`. It scans a synthetic
   in-memory HOME, consumes no `run_id`, and reports the real `uptime_bucket`, `evidence`, `build_sha` and `sunset_utc`.
   A real run needs `evidence: "mature"` (container uptime of 24 h or more, condition C9).
2. **The real run** (only after C8 is recorded, see below):
   `bash apps/web-platform/scripts/home-census-trigger.sh --mode real --run-id <N> --discharged-sha <sha> --pr <PR>`.
   The script checks the pinned-author C8 comment, the served build against the discharged commit, the two-run cap and the
   write-ahead claim, then posts the request and prints the body only if it validates against the allowlist schema.
3. **Read the signal** (credentials required):
   `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep "home-census result" --limit 5` and expect
   exactly one row. Sentry: Issues search `message:"home-census result"`. Zero rows means "pino line not shipped" or "not run": triage
   by log level, then the HTTP response, then retention.

Exit codes of the script: 0 ok, 2 usage, 3 secret, 4 unauthorized, 5 forbidden, 6 server error, 7 timeout after the scan (ambiguous;
read Sentry and Better Stack first and do not retry), 8 governance refusal, 9 build mismatch, 10 body failed the allowlist schema,
11 refused by the server (409, 410, 429, 503), 78 shell tracing refused.

## Conditions before a real run

- **C8:** the CLO re-read the final scanner and emitter diff and a comment `home-census C8 DISCHARGED sha=<sha> pr=<PR>` from a pinned
  author is on #10455; the same sha is in `knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md`. The script
  refuses a real run if the served build's census paths differ from the discharged commit.
- **C9:** the preflight reports `evidence: "mature"`. At most two real runs in total; the second only after a recorded `young` result.
  The default terminal state is "unmeasured at maturity" if no mature window exists before the sunset.
- **C7:** inside the sunset. One extension of at most 15 days is allowed, from a PR that touches only the constant, reason recorded
  on #10455. Total standing time stays under 60 days from the merge deploy. Dead code is deleted under #11714.

## Result handling

- **Owner:** the engineering session started on the tracker after the follow-through `earliest`. The full object goes only to the
  controller and the CLO, in the session, the same day.
- **Public tracker:** only `home-census run_id=N done` for every terminal outcome. The object is never written to the working tree, a
  commit, a PR text or Sentry.
- **When the object may be posted:** (a) whole and immediately when `control` passed, not truncated, `errors` `0`, all four trigger
  classes `0` and `other_under_claude` `0`; (b) with the four trigger classes `0`, a nonzero in `shell_snapshots`, `account_state` or
  `sessions_*` immediately with the sentence "Entries (bucket) were counted in class C. No names or content were opened."; (c) a
  nonzero in `projects` is held until the CLO has read it; (d) any nonzero trigger class holds the whole object until the
  determination is recorded; (e) the object appears in the public repository only in or after the re-open addendum commit.
- **Wording.** Young zero: "At the run, a young container (uptime bucket X) counted 0 in class C. Insufficient evidence, not a
  negative finding." Mature zero: "None counted in this container since its start. Earlier containers no longer exist and are not
  measured." Nonzero: "Entries (bucket) were counted in class C, which we presume from the CLI's writer behaviour to hold prompt
  text. No names or content were opened, and whether any sibling can read them is not established by the census."
  Never say: clean, no exposure, secure, isolated, protected, private, not readable, empty, "census complete" (when truncated or the
  control failed), no prompt text, found prompt text, leaked.
- **Support.** No ad-hoc replies about data on shared hosts. Inquiries go to the controller and the CLO. Holding line: "we are
  reviewing how session state is scoped on our hosts and will update you". Never "safe", "isolated", "no evidence of access" or
  "not a breach".

## Re-open procedure (any trigger class nonzero)

Trigger classes (presumptive by the CLI's writer behaviour; no content is read): `history_jsonl`, `debug`, `todos`, `tasks`. A zero
never triggers. `projects` is informational (used for sizing). `shell_snapshots`, `account_state` and `sessions_*` are already
conceded reachability classes; a nonzero in `other_under_claude` is a flag to the CLO.

0. **Freeze first:** every user statement about data isolation or safety and all public legal-document edits stop at once, before the
   steps below. The inventory of published or scheduled isolation claims (docs site, legal pages, the distribution queue) is listed
   here so the freeze is executable: the docs site, the legal pages and the distribution queue under
   `knowledge-base/marketing/distribution-content/`. A CTO owner and a time-box for the relocation decision are named at the re-open,
   because the exposure continues until the next container start wipes the HOME.
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

After a mature zero no scheduled repeat is owed; repeat on a CLI version bump or when the class list changes.

## Not measured

`/workspaces`, `/tmp/.cs`, `CLAUDE_CONFIG_DIR`, the second web host, the canary container and outer-wrap cohorts are unmeasured, not
safe. Adding any of them needs a fresh typed message from the controller.

## Retention

Existing and unchanged: Sentry plan-level retention, and Better Stack per `betterstack-log-query.md`. No extension.
