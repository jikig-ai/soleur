---
title: "security(git-data): delete the app's unpinned host-key fallback arm (#5914, host-key step 6), gated on the step-5 Art. 17 discharge record"
date: 2026-09-28
slug: feat-git-data-delete-unpinned-fallback-arm-5914
branch: feat-one-shot-8211-hostkey-step5-6
issue: 5914
closes: 5914
type: security
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# security(git-data): delete the app's unpinned host-key fallback arm (#5914, host-key step 6)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this
branch; the one-shot pipeline entered planning directly.)

## Enhancement Summary

**Deepened on:** 2026-09-28 (after a six-seat plan review and a strong-model consult)
**Gates:** User-Brand Impact (4.6) pass; Observability (4.7) pass, with the suite-shape match argued
down; PAT-shape (4.8) none; UI wireframe (4.9) and Downtime (4.55) not triggered; Encryption Posture
(4.10) present; Guard Contract (4.11) `lint-guard-contract.py` green, 2 entries.
**Agents used:** soleur:engineering:review:security-sentinel,
soleur:engineering:review:user-impact-reviewer, soleur:engineering:review:test-design-reviewer,
soleur:engineering:review:observability-coverage-reviewer, and a mechanical verify-negatives and
citations pass (43 of about 45 checks confirmed, 0 contradictions). The fan-out was scoped to the
reviewers relevant to a small security change on the Art. 17 path, not the full agent roster; the
plan-review panel had already covered simplicity, conventions, architecture and flows.

### Key improvements

1. **Paging really reaches someone.** Open issue #8629: an Error-path `reportSilentFallback` loses its
   `feature`/`op` tags to the pino mirror's pre-capture, so `art17_erasure_incomplete` cannot match
   the erasure report today. The erasure report and both startup ops move to the message path
   (AC5c), and G1 plus the post-merge reads require no unresolved `erasure_outcome:unconfigured`
   issue, because the rule pages only on first-seen, reappeared or regression.
2. **The runtime guard is as strict as the resolver** (it reuses the exported
   `GIT_DATA_HOST_KEY_PIN_RE`), and its tests match the guard's exact text, so a `TypeError` cannot
   pass for the guard.
3. **Part A cannot leak ids.** The runbook's own step-3 block prints ids and must not be run as
   written. The sweep uses the `.context` field path, runs with `jq` stderr suppressed, and uses a
   positive control that exercises the tag query itself.
4. **G1 and G2 read the invariant.** G1 re-sweeps from the record's own window end and matches the
   author by login. G2 adds a count-only shape check of the Doppler pin against the app's pattern.
5. **The records state the residuals.** These are: a Doppler `prd` writer swapping the pin, the
   post-flip limit of "discharge as in step 5", and the Art. 12(3) clock on a refused erasure.

### New considerations discovered

- #8629 is a fleet-wide defect. This PR fixes only the emitters it relies on and comments on #8629.
- The no-TOFU mutation harness runs in about 44 s (34 assertions), and the guard itself in 1.1 s.

## Overview

This branch continues the #8211 git-data cutover along the runbook's **host-key pinning post-merge
sequence** (`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`,
§"Host-key pinning post-merge sequence (#7226, #5914)"), re-read from `origin/main` at `fff36b6172`.

Two runbook steps are in play, and only one of them is a PR:

- **Host-key step 5 — an operation plus an issue record, not a PR.** Discharge the Art. 17 erasures
  left pending by the pin window, by reads only, and post the step-5 discharge record on #5914.
  Section [Part A](#part-a--host-key-step-5-the-operation-this-pr-is-gated-on) states exactly what the
  runbook requires, where each read comes from, and which parts need operator authorization. This
  plan does not execute it.
- **Host-key step 6 — this branch's PR.** Delete the app's transitional unpinned fallback arm
  (`TOFU_FALLBACK_OPTS` and the `null`-pin path) from `apps/web-platform/server/git-auth.ts` and
  `resolveGitDataHostKeyPin`, remove `git-auth.ts` from the no-TOFU guard's allow-list, record the
  change in the runbook, ADR-237, the C4 model, the encryption-posture ledger and (CLO-drafted) the
  Art. 30 register, and close #5914. After merge, the flag precheck reads `TOFU_ARM absent` on any
  dispatch from `main`. See [Part B](#part-b--host-key-step-6-this-branchs-pr).

**Is step 6 unblocked?** Per the runbook it needs two things, and nothing else:

1. **Step 5 first.** Step 5 runs "after the pin is fixed (step 3 GO) and before step 6 or any flag
   flip". The PR can be written, reviewed and CI-green now; it must not **merge** until the step-5
   discharge record is on #5914 (gate G1).
2. **The positive step-3 startup line.** "Gate it on the positive step-3 startup line
   (`git_data_pin=present` on the current deploy), not on the absence of Sentry events." Evidence it
   held on 2026-09-25 exists (#5914 issuecomment-5830287903: `git_data_pin=present
   fp=SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs` from replace run 36118115758); the gate is
   re-read on the current deploy immediately before merge (gate G2).

Nothing in the runbook makes step 6 wait on #8572, #8209, #8101 or the rest of #8211: those are
flag-flip and real-cutover preconditions, and step 6 is itself one of the flag-flip preconditions.
So step 6 is the first unblocked PR item, and #8572 is **not** the fallback.

## Research Reconciliation — brief vs. runbook vs. codebase

| Brief / earlier claim | Reality (origin/main `fff36b6172`) | Plan response |
|---|---|---|
| Step 6 is "gated on step 5's discharge record being posted first". | The runbook adds a second gate: the positive `git_data_pin=present` startup line **on the current deploy**. | Both are merge gates (G1, G2). Neither blocks writing or CI. |
| "The flag precheck must then read `TOFU_ARM absent`." | The precheck line is read from the **dispatched source tree** (`GIT_AUTH_TS_PATH` defaults to `<infra>/../server/git-auth.ts`), so it reads `absent` only on a dispatch from a ref that contains this PR. It is a reminder, not a control. | Pre-merge: a new precheck test row runs the real script against the real `git-auth.ts` and must read `TOFU_ARM absent`. Post-merge: the next authorized proof dispatch from `main` must read it; that dispatch belongs to the #8211 PR2 remainder (proof before freeze) and is recorded there, not triggered by this PR. |
| #5914 comment 2026-09-23 says the arm's deletion "is PR2's work under #8211". | The runbook (newer, and the source of truth) names it "the #5914 follow-up PR" (step 6). | Ship it as its own PR that closes #5914; reference #8211. |
| Repo research suggested deleting ADR-237's Residual and Addendum text about the arm. | ADRs here are amended by dated addenda; accepted records are append-only. | Add a new dated addendum to ADR-237; do not delete earlier text. |
| Repo research suggested rewriting the precheck test's K6–K11 and mutation rows 12–15 to expect `absent`. | Those rows run the script against **synthetic fixtures** (`$T/git-auth-tofu.ts`, a mirrored tree), not the real file, and stay valid: the probe must still detect a re-introduced arm. | Keep the precheck suite unchanged (K6–K11, rows 12–15). A K12 real-file case was planned, then cut at plan review: Guard 1 already forces the real file to zero accept-new hits; AC7 runs the probe's predicate once. |
| Encryption ledger / Art. 30 register were not in the brief. | `scripts/encryption-posture-ledger.json` `connections[9]` carries `cert_verification: off` with an exception tracking #5914; the counsel review `2026-09-counsel-review-7226.md` re-evaluation trigger (2): "#5914 merges and deletes TOFU_FALLBACK_OPTS. Residual (b) of (g)(14) and the ledger exception then close, and both must be rewritten in place with Superseded markers." | In scope. Ledger row flips to `cert_verification: on` with the exception removed. The register's PA-36 (g)(14) marker is CLO-drafted wording, pasted verbatim. |
| C4 was not in the brief. | `model.c4` edge `claude -> gitDataStore` says "a transitional unpinned fallback applies only while no pin is published and the store flag is off (#5914)". This PR falsifies that sentence. | Edit the edge description and regenerate `model.likec4.json` (lefthook `c4-model-regenerate`). |
| Optional catch-up: tick host-key steps 1–3. | Step 1 requires every push-triggered `apply-web-platform-infra.yml` run to be `success`; runs 36150370048, 36186259051 and 36249105103 (2026-09-25/26) are `failure`. Step 2's evidence merged in #8655. Step 3's GO evidence is on #5914 (comment above). | Tick step 2 and step 3 (citing evidence); leave step 1 unticked with no edit. Tick step 5 (citing the record) and step 6 (this PR). |

## Research Insights

### Premise Validation (Phase 0.6)

- #5914 is OPEN (`Pin git-data host key: replace accept-new TOFU on private-net git SSH`). #8211,
  #8572, #8209, #8101, #8634 and #9066 are OPEN. PR #9096 is this branch's draft, content empty. No
  other open PR references #5914.
- `TOFU_FALLBACK_OPTS` exists at `apps/web-platform/server/git-auth.ts` (`const TOFU_FALLBACK_OPTS:
  readonly string[] = ["-o", "StrictHostKeyChecking=accept-new"];`), selected by
  `gitDataHostKeyTrust` on `hostKeyPin === null`. `resolveGitDataHostKeyPin()` in
  `apps/web-platform/server/git-data-replication.ts` returns `null` only when the pin is absent
  **and** `isGitDataStoreEnabled()` is false.
- Proof run 36339208990: `workflow_dispatch`, `main`, head `ab4a07e5e0` (an ancestor of
  `origin/main`), `success`, created 2026-09-27T18:03:15Z. PR #9048 (the #8211 PR2 proof half) merged
  2026-09-27T17:25:03Z as `59745cf049ab24279e1fc26fcc0a579705276972`, an ancestor of the proof's
  head. The proof's `cutover` job waited on environment approval and ran 21:01:53Z–21:02:28Z. The
  release runs listed on 2026-09-28 show none spanning that interval (the nearest ended 20:33:00Z and
  started 21:14:39Z); Part A re-reads this with `deploy-arm.sh find` on the full SHA rather than
  relying on this note.
- Doppler `dev` carries none of `GIT_REMOVE_SSH_PRIVATE_KEY`, `GIT_PROVISION_SSH_PRIVATE_KEY`,
  `GIT_TRANSPORT_SSH_PRIVATE_KEY`, `GIT_DATA_*` (names-only read), so dev account deletion returns
  `skipped` before the pin is resolved; deleting the fallback cannot change dev behaviour.
- No Sentry alert keys on `pin_absent_store_disabled` or `pin_absent_store_enabled`:
  `sentry_alert.art17_erasure_incomplete` (`apps/web-platform/infra/sentry/issue-alerts.tf`) filters
  on `feature=account-delete` and `op=git-data-bare-repo-erasure` only.
- `doppler_secret.git_data_ssh_host_key` (`apps/web-platform/infra/git-data.tf`) is Terraform-owned,
  so a deletion outside Terraform shows in `scheduled-terraform-drift.yml`.

### Property List (Phase 0.6b)

- **P1.** No code path in the web app dials the git-data host without a host-key pin: an absent pin
  refuses, whatever `GIT_DATA_STORE_ENABLED` says.
- **P2.** A refused erasure caused by a pin fault is reported as `unconfigured` with a fixed reason
  word, never as `unreachable`, and pages through the existing `art17_erasure_incomplete` route.
- **P3.** The repo's text guard fails if any tracked file re-introduces an `accept-new` (or
  equivalent) SSH option, `git-auth.ts` included.
- **P4.** The cutover workflow's flag precheck reads `TOFU_ARM absent` on the real tree.
- **P5.** The recorded architecture and compliance records (runbook, ADR-237, C4, encryption ledger,
  Art. 30 register) stop describing the fallback as live, in the same PR.
- **P6.** The PR does not merge before the step-5 record exists and the startup line
  `git_data_pin=present` is read on the current deploy.
- **P7.** A web container that starts armed for git-data but without a pin produces a Sentry event at
  boot, before any user's erasure is refused.

### Cut List (Phase 0.6b)

- ~~A startup Sentry event for an absent pin~~ — **reinstated at domain review (2026-09-28).** First
  cut as covered by Terraform drift. The CPO's sign-off condition C2 and the CTO both noted that
  deleting `pin_absent_store_disabled` removes the only proactive absent-pin signal, and drift sees
  only a deleted secret, not a container that started without one (a fresh birth, a redeploy that
  raced the publish). It buys **P7** and costs one branch in an existing function: mirror
  `pin_invalid_at_startup` as `pin_absent_at_startup`, emitted only when git-data is armed in this
  process (`GIT_REMOVE_SSH_PRIVATE_KEY`, `GIT_PROVISION_SSH_PRIVATE_KEY` or `GIT_DATA_SSH_HOST`
  set — the same sibling-input predicate `removeGitDataRepo` uses for `remove_key_absent`), so dev,
  which carries none of them, stays silent. Paging on it is added to #8572's rule scope by a comment
  (that issue owns `issue-alerts.tf` changes), not by this PR.
- **A committed step-5 sweep script** → would buy repeatable Sentry pagination → the runbook's
  documented `curl` + `jq` reads cover a one-off discharge; the future re-drive path belongs to #8211
  (per-id re-erasure). Cut.
- **Paging on replication-push pin faults** → #8572's scope, a separate PR. Not folded in.
- **Cut at plan review (2026-09-28), each a duplicate of a surviving owner:** precheck K12/K12b and
  the `FLOOR` bump (→ Guard 1 plus K6–K11); a vitest source scan for accept-new literals (→ Guard 1);
  a module-wide pass-through `vi.mock("fs")` write spy (→ the guard sits above every write, asserted
  by "rejects with the guard's message and `execFile` never runs"); a `@ts-expect-error` null line
  (→ `tsc` plus the runtime guard); a shared "armed" helper (→ inline; the two predicates differ);
  a duplicate post-merge comment on #5914 (→ the #8211 comment).
- **A per-flag reason word** (`pin_absent_store_enabled` vs `pin_absent_store_disabled`) → the flag
  state no longer changes the outcome, so one word (`pin_absent`) carries the fault; the message text
  still names the flag state. Kept to one word.

### Relevant files (anchors are content, not line numbers)

- `apps/web-platform/server/git-auth.ts` — `TOFU_FALLBACK_OPTS`, `gitDataHostKeyTrust`,
  `gitWithPrivateKeyAuth(args, privateKey, hostKeyPin: string | null, …)`,
  `sshWithPrivateKeyAuth(host, remoteCommand, privateKey, hostKeyPin: string | null, …)`, and the
  section comment "git-data host-key trust (#7226 / #5914, ADR-237)".
- `apps/web-platform/server/git-data-replication.ts` — `resolveGitDataHostKeyPin(): string | null`,
  `let pinAbsentReported`, the `pin_absent_store_disabled` report, `provisionGitDataRepo(workspaceId,
  preResolvedHostKeyPin?: string | null)`, `removeGitDataRepo`'s guarded resolution (reason words
  `pin_invalid` | `pin_absent_store_enabled`), the `unconfigured` doc comment, and
  `replicateToGitData`'s pin resolution.
- `apps/web-platform/server/git-data-client.ts` — `fetchFromGitData`'s `resolveGitDataHostKeyPin()`
  guard comment.
- `apps/web-platform/server/account-delete.ts` — the `unconfigured` comment block listing
  `pin_invalid | pin_absent_store_enabled`.
- Tests: `apps/web-platform/test/git-auth.test.ts`, `apps/web-platform/test/git-data-host-key-pin.test.ts`,
  `apps/web-platform/test/git-data-replication.test.ts` (reason-word comment),
  `apps/web-platform/test/helpers/ssh-host-key-fixture.ts` (`TOFU_OPT`, comment "Guard 1 counts it in
  exactly one tracked place").
- Guards: `tests/scripts/test-no-tofu-ssh.sh` (ALLOWLIST line for `git-auth.ts`),
  `tests/scripts/test-no-tofu-ssh-mutation.sh` (rows 2, 5, 5b),
  `apps/web-platform/infra/git-data-flag-precheck.test.sh` (read, not edited; `FLOOR=76`, `MUTANT_FLOOR=17`).
  `apps/web-platform/infra/git-data-flag-precheck.sh` is **not** edited.
- Records: the runbook (Preconditions checklist; step 5 (a) "the flag precheck's `TOFU_ARM present`
  warning is expected until step 6"; step 6; "Deploy-day go/no-go" bullet "The first rotation cannot
  produce `host_key_mismatch`"; "Between merge and step 3"; verdict-map row "The app, an Art. 17
  erasure, pin fault"), `ADR-237-ssh-host-keys-are-pinned.md` (Residuals "The transitional app arm
  (#5914)"), `knowledge-base/engineering/architecture/diagrams/model.c4` (edge `claude ->
  gitDataStore`), `model.likec4.json` (generated), `scripts/encryption-posture-ledger.json`
  `connections[9]`, `knowledge-base/legal/article-30-register.md` PA-36 (g)(14).
- Not edited (dated, append-only): `knowledge-base/legal/audits/2026-09-counsel-review-7226.md`,
  ADR-220's amendment log, earlier #5914 records.

### Institutional learnings applied

- `best-practices/2026-04-18-drift-guard-self-silent-failures.md` — a test asserting the arm is gone
  must pin the exact token, and must have a must-RED twin; a bare `not.toContain` passes vacuously
  when the fixture changes.
- `best-practices/2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md`
  — after the `model.c4` edit, run the C4 syntax/render suites, not only the regenerate hook.
- `best-practices/2026-04-22-verification-claims-in-plans-decay-silently.md` — gates G1/G2 are
  re-read at merge time; this plan's evidence dates are not the gate.
- `best-practices/2026-04-18-compliance-runbook-authoring-gotchas.md` — run each step-5 `jq`/`curl`
  in isolation before trusting a zero; a zero from a broken query is indistinguishable from a real
  zero, so every sweep pairs with a positive-control query.

### Conventions

- Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test git commit …`; rely on CI for the full
  battery. Required checks must pass by name on the exact head SHA.
- This PR touches no `.github/workflows/` file, so it is not UNTRUSTED-CI; it may merge by the normal
  route after the gates.
- Legal forks go to the CLO agent; architecture forks go to the CTO agent. Production writes and
  prod dispatches need explicit per-step operator authorization (`hr-menu-option-ack-not-prod-write-auth`).

### External research

None. The change removes an arm inside an existing, reviewed mechanism (ADR-237); strong local
context. Functional-overlap discovery: 3/3 registries queried, nothing relevant.

## Part A — Host-key step 5: the operation this PR is gated on

Not implemented by this PR and not executed during planning. It is the precondition for gate G1. All
references are to the runbook's step 5 text on `origin/main`.

### What step 5 requires

1. **5.1 Collect the ids (Sentry, read-only).** Every `op:git-data-bare-repo-erasure` event since the
   PR #8511 merge (`2026-09-22T12:07:01Z`), via the "Store not empty" step-3 query with its period
   widened to cover the merge. No `erasure_outcome` filter (the `removeGitDataRepo threw` arm has
   none). Follow the `Link: …; rel="next"; results="true|false"` cursor on every list call until
   `results="false"`. Run it a second time immediately before writing the record; the window ends at
   that second read. **Ids never leave Sentry**: not on an issue, PR, commit, workflow input, log, or
   this session's terminal output, and no hash of them. The record carries counts and Sentry issue
   ids only.
2. **5.2 The proof run.** A `git-data-cutover.yml` run from `main`, dispatched after the #8211 PR2
   proof-half merge and its release deploy concluded, ending `verdict=clear`. Then four recorded
   items:
   - **(a) served LUKS store** — `gh run view <id> --json headBranch,headSha,event,conclusion` reads
     `main`, `workflow_dispatch`, `success`; `git merge-base --is-ancestor <headSha> origin/main`;
     the nine notice annotations, including `probe=store-empty verdict=ok`; the `flag=` precheck line
     from `gh run view <id> --log`.
   - **(b) retained plaintext volume** — the current instance's `boot_complete` line from Better
     Stack reads `plaintext_volume=present plaintext_empty=yes served_repos=0`; the server's
     `created` time falls inside replace run 36118115758; no later `apply-web-platform-infra.yml`
     dispatch ran a `git_data_host_replace` or `git_data_host_create` job to `success`.
   - **(c) flag never on** — page `doppler configs logs` for `prd` back past the `created` time of the
     older of `soleur-git-data-store` and `soleur-git-data-luks-store` (Hetzner volumes, GET only),
     reading the logs **after** the proof run completed; none names `GIT_DATA_STORE_ENABLED`.
   - **(d) no lock file for the collected ids** — classify every event per id into *host not
     reached* / *refused before the lock* / *lock may exist*; an id is discharged only if every event
     is in the first two classes.
3. **5.3** Any verdict other than `clear` follows its verdict-map row; one re-dispatch; a repeat opens
   an incident.
4. **The record** on #5914, using the runbook's template verbatim, with "no repository held; nothing
   to erase" (never "erased", never "no data held").

### Data sources and the read-only queries

| Item | Source | Read (all GET / read-only) |
|---|---|---|
| 5.1 sweep | Sentry org `jikigai-eu` | Write the sweep as an **uncommitted** script in the session scratchpad that can print **only counts and Sentry issue ids**, and run it as `doppler run -p soleur -c prd -- bash <scratch>/sweep.sh` so the token never enters argv or the caller's shell (take the host `https://jikigai-eu.sentry.io` and the `SENTRY_ISSUE_RO_TOKEN` choice from `scripts/sentry-issue.sh`, whose header documents both). Issues: `GET /api/0/organizations/jikigai-eu/issues/?query=feature%3Aaccount-delete%20op%3Agit-data-bare-repo-erasure&start=2026-09-22T12:07:01Z&end=<now>`, capturing headers (`curl -D <file>`) and following `rel="next"` while `results="true"`. Events per issue: `GET …/issues/<id>/events/?full=true`, same pagination, filtered in `jq` to `dateCreated` inside the window. Run the positive control first; if the sweep returns 0 while the control returns rows, do **not** debug by printing events — add count-only diagnostics. **Never run the runbook's "Store not empty" step-3 block as written**: its final `jq -r … @tsv` prints one id per line. The script runs with `set +x`, sends `jq`/`awk` stderr to `/dev/null` (a `jq` error echoes the value it failed on) and checks exit codes through `PIPESTATUS`; response bodies are streamed, and the only file written is the `-D` header file. |
| 5.1 positive control | Sentry | Two controls. (1) The same token and host list at least one org issue over the last 24 h (the token and host work). (2) The same two tag keys (`feature:account-delete op:git-data-bare-repo-erasure`) over `statsPeriod=90d`, the tag query itself, which the 2026-09-25 sweep cross-checked. When any events exist, at least one must resolve a repository id (as a count), which proves the field path. |
| (a) | GitHub Actions | `gh run view 36339208990 --json headBranch,headSha,event,conclusion`; `gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations`; `gh run view 36339208990 --log \| grep -E 'flag=\|TOFU_ARM'`. |
| (a) eligibility of the existing run | GitHub | The runbook's reason for waiting is "keeps the dry run off a host mid-redeploy", which is about when the **job ran** (21:01:53Z–21:02:28Z per `gh run view 36339208990 --json jobs`), not when it was dispatched. Three reads: (1) `git merge-base --is-ancestor 59745cf049ab24279e1fc26fcc0a579705276972 ab4a07e5e0ab26a84a4b08b61cbe02a99e410acb` succeeds (the proof-half code ran; checked 2026-09-28); (2) `bash plugins/soleur/scripts/deploy-arm.sh find 59745cf049ab24279e1fc26fcc0a579705276972` (full 40-hex SHA — a short one matches nothing, #8135) prints `DEPLOY=success`, and that `ARM=<id>` run's `updatedAt` (`gh run view <id> --json updatedAt`) precedes the job's `startedAt`; (3) list `web-platform-release.yml` runs and confirm none ran across 21:01:53Z–21:02:28Z (`gh run list --workflow web-platform-release.yml -L 40 --json databaseId,createdAt,updatedAt,conclusion`). If a deploy did overlap, record why it cannot yield a false `clear`: the probes read git-data host state through the web-1 jump, so a web-1 redeploy can only fail the run, and (c) is read after the run. `deploy-arm.sh served` answers what production serves **now** and is not evidence about 2026-09-27; it is not used here. |
| (b) | Better Stack (git-data source `t520508_soleur_git_data_prd_logs`), Hetzner API, GitHub | The runbook's `betterstack-query.sh` SQL with anchor `A` from replace run 36118115758's `boot-trail anchor` line (1790328235, per #8211 issuecomment-5860128868); `GET /v1/servers?name=soleur-git-data` → `.servers[0].created`; `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --created '>=2026-09-25T09:23:01Z'` then per run the job-name filter. |
| (c) | Doppler, Hetzner | `doppler configs logs -p soleur -c prd --number 100 --page N` (flags verified with `doppler configs logs --help` on 2026-09-28) until an entry older than the older volume's `created`; open each diff with `doppler configs logs get`. `GET /v1/volumes?name=soleur-git-data-store` and `?name=soleur-git-data-luks-store` → `.volumes[0].created`. |
| (d) | Sentry (events from 5.1) | `jq` over the events emitting `<id>\t<class>`, where the id path is the runbook's `.context.gitDataRepoId // .extra.gitDataRepoId` (the events API returns extra data under `.context`), straight into `awk`, which aggregates per id to its worst class and prints **only** the counts. An event with no `gitDataRepoId` is the `deleteAccount` outer-catch arm (`removeGitDataRepo threw`), which only receives throws raised before any dial: the pin resolver's errors are caught inside `removeGitDataRepo`, so the outer catch sees exactly `git-data: refusing unsafe workspace_id` (`assertSafeWorkspaceId`) and `GIT_DATA_SSH_HOST is unset in production` (`resolveGitDataSshHost`). Match those two message prefixes as the `jq` set (never print the message: the first embeds the id). Per the runbook's (d) such events are *host not reached*; record them as a fourth count, "no repository id, host not reached", discharged on the empty-store proof plus that class (CLO, 2026-09-28). An id-less event matching neither prefix is unrecognised and takes the "If an item cannot be read" path. |

The evidence in hand suggests the likely outcome: the 2026-09-25 sweep found 0 issues for
`op:git-data-bare-repo-erasure` over 90 days, and (b) was read on 2026-09-27 as
`plaintext_volume=present plaintext_empty=yes served_repos=0` on server 167392038. That is a
prediction, not the record; the record reads everything again.

### What needs operator authorization

- **Nothing in 5.1, (b), (c) or (d) writes anything.** They are reads of Sentry, Better Stack, the
  Hetzner API (GET), Doppler (secret read and audit-log read) and GitHub. They need no production
  authorization. Reading `SENTRY_ISSUE_RO_TOKEN` and `HCLOUD_TOKEN` from Doppler is a read.
- **The proof run.** If run 36339208990 qualifies (reads (1) and (2) of the eligibility row above; the
  CTO agent ruled reuse sound on 2026-09-28 provided those hold), step 5 reuses it and dispatches
  nothing. If (1) or (2) fails, a fresh `git-data-cutover.yml` dispatch from `main` is a prod
  dispatch: it waits on the `web-platform-infra-apply` environment approval, which hands the job
  `DOPPLER_TOKEN_PRD` and the git-data root key. That needs the operator's explicit in-session
  consent for that run, the runbook's identity check on the run (`path`, `event`, `headBranch`,
  `headSha`, `actor`) before approving, and cancelling the run if it is still unapproved at session
  end (it holds the `git-data-state` group). Architecture question if the eligibility read is
  ambiguous (for example the deploy arm resolves to a descendant and concluded during the proof's
  approval wait): route to the CTO agent, not the operator.
- **Posting the #5914 record** is a GitHub comment on a public repo (not a production write), made by
  the step-5 session. It carries counts and Sentry issue ids only.
- **If any item cannot be read, or any id is in "lock may exist"**: the runbook's escalation posts an
  `outcome: NOT DISCHARGED — …` record, opens a `clo-attestation` issue routed through `soleur:go` to
  the CLO, and retries by reads only. A host replace to produce a fresh `boot_complete` is a separate,
  CTO-decided, separately authorized prod write; it is never part of step 5.
- **If step 5 cannot complete at all** (the existing proof run fails eligibility and the operator does
  not consent to a fresh dispatch, or two non-`clear` verdicts open an incident): G1 never passes and
  this PR waits. Any collected ids keep their Art. 12(3) clock; the runbook's rule applies (the CLO
  rules no later than 7 days before the earliest deadline). The 2026-09-25 sweep set no deadline (0
  ids); a sweep that finds ids sets one, and that date goes into the record and the
  `clo-attestation` issue title.

## Part B — Host-key step 6: this branch's PR

### Merge gates (read immediately before merge; none is a write)

- **G1 — the step-5 record is on #5914, and nothing is pending after it.** Read the comments with
  `gh api --paginate repos/jikig-ai/soleur/issues/5914/comments` and keep only those whose body
  **contains** `git-data store Art. 17 discharge (#5914, host-key step 5)` (the runbook's template
  sits in a fenced block, so a pasted record starts with the fence, not the title) **and** whose
  author is an expected login: the repository owner's account or the session's own `gh api user`
  login (not `author_association`, which reads `NONE` for a GitHub App bot; this is a public repo).
  The **newest** such record governs: parse its `proof run:` id, its `outcome:` line and the end
  time on its `Sentry sweep: … to <time>` line. Then re-run the 5.1 sweep, counts only, from **that
  end time** (the runbook's window ends at the second read, before posting) to now: it must be 0. Any
  event after the record is a new pending erasure under the runbook's "Requests after the window",
  and needs a new step-5 record before this merge. Finally, the Sentry issues list for
  `feature:account-delete op:git-data-bare-repo-erasure erasure_outcome:unconfigured
  is:unresolved` is empty, so the first post-merge refusal would page (the rule fires on
  first-seen, reappeared or regression only). If the governing record's `outcome:` reads `NOT DISCHARGED` for some
  ids, step 6 may still merge (CLO, 2026-09-28: deleting the arm destroys no evidence, leaves the
  reads-only retry untouched, and with the pin present strictly improves the safeguard) provided the
  `clo-attestation` issue it names is open with the earliest Art. 12(3) deadline in its title, and
  neither the PR body nor the register marker says step 5 discharged everything. The legal question
  goes to the CLO; only the sequencing question (the runbook orders step 5 before step 6) goes to the
  CTO.
- **G2 — the pin the merge will load, and the pin production runs, are the host's key.** Three
  reads; any mismatch, `absent` or `invalid` is NO-GO, because this PR would then fail every
  production erasure closed.
  1. **Expected fingerprint** — from the newest `apply-web-platform-infra.yml` run whose
     `git_data_host_replace` or `git_data_host_create` job ended `success` (today replace run
     36118115758): `gh run view <id> --log | grep 'git-data host key fingerprint'`
     (`SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs` as of 2026-09-28). A later replace moves
     this value; the gate follows the newest run, so a legitimate rotation is not a false NO-GO.
  2. **The pin the merged container will load** — the fingerprint of Doppler `prd`'s
     `GIT_DATA_SSH_HOST_KEY` (a public key), computed without echoing it:
     `doppler secrets get GIT_DATA_SSH_HOST_KEY -p soleur -c prd --plain | ssh-keygen -lf - | awk '{print $2}'`
     (the runbook's own read). It must equal (1). `ssh-keygen -lf -` also accepts a trailing
     comment, key options or a private key, so add a count-only shape check against the app's own
     pattern: `doppler secrets get GIT_DATA_SSH_HOST_KEY -p soleur -c prd --plain | grep -cE
     '^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$'` prints `1`. (1) and (2) share
     Terraform as their source; the evidence that the **host** presents this key is the proof run's
     pinned `role=git-data-auth verdict=ok`.
  3. **The pin production runs** — anchor on the build production serves:
     `bash plugins/soleur/scripts/deploy-arm.sh served "$(git rev-parse origin/main)"` prints
     `BUILD_SHA=<sha>`; `deploy-arm.sh find <that full sha>` prints `ARM=<id> … DEPLOY=success`
     (if `find` returns `ARM=none`, walk back `git log --format=%H origin/main` to the newest SHA
     whose `find` reads `DEPLOY=success`); take that run's `createdAt`; then
     `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since '<createdAt>' --grep git_data_pin=`
     and reduce with `jq` to the newest line per host. Expected hosts: every host that emitted a
     `git_data_pin=` line in the 24 h before the anchor; a host missing after the anchor is NO-GO.
     Each newest line reads `git_data_pin=present fp=<(1)>`.
- **G3 — CI.** Every required check passes by name on the exact head SHA.

### Implementation Phases

#### Phase 1 — RED: tests that describe the pinned-only behaviour (write first)

1. `apps/web-platform/test/git-data-host-key-pin.test.ts`
   - Replace "absent + store disabled returns null and reports pin_absent_store_disabled ONCE per
     process" with: absent + store disabled **throws** a message naming `GIT_DATA_SSH_HOST_KEY` and the
     flag state, and emits no `git_data_host_key_pin` report.
   - Replace "store disabled + no pin, run twice: ssh uses the fallback (null)…" with: store
     disabled, no pin and remove key set → `removeGitDataRepo` returns `{ status: "unconfigured" }` whose
     `detail` matches `/^pin_absent: /`, and `sshTransport` is never called; run twice, still never
     dials.
   - "store ENABLED + absent pin returns `unconfigured`": expect `/^pin_absent: /` (was
     `pin_absent_store_enabled`).
   - "no remove key and no sibling inputs stays `skipped` without consulting the pin" stays as is (the
     dev path).
   - Add: `provisionGitDataRepo` / `replicateToGitData` / `fetchFromGitData` with store enabled + no
     pin still throw before any exec (unchanged behaviour; keep the existing cases).
   - Update the file header comment: the module-state note about `pin_absent_store_disabled` goes.
   - "does not fire the pin_absent Sentry report (startup evidence is the log line, not an event)"
     splits in two (P7): absent + **unarmed** (none of `GIT_REMOVE_SSH_PRIVATE_KEY`,
     `GIT_PROVISION_SSH_PRIVATE_KEY`, `GIT_DATA_SSH_HOST` set) logs `git_data_pin=absent` at warn and
     emits no event; absent + **armed** (each of the three set alone, one row per input — a check that
     stops at the first input is the defect) logs the same line and emits exactly one
     `feature=git_data_host_key_pin op=pin_absent_at_startup` event whose payload carries no key
     material.
2. `apps/web-platform/test/git-auth.test.ts`
   - Every call that passes `null` becomes a pinned call with a pin from `makeEd25519Pin()`, keeping
     its key-delivery and cleanup assertions. There are **five** (`tsc --noEmit` enumerates them once
     the parameter is `string`): the two transport tests ("delivers the key via GIT_SSH_COMMAND -i …
     with the Phase-2 TOFU options", "invokes ssh with -i keyfile … TOFU opts …"), the two
     "cleans up on failure" cases (`gitWithPrivateKeyAuth(["ls-remote", "git-data"], KEY, null)`,
     `sshWithPrivateKeyAuth("10.0.1.20", "ws-uuid-123", KEY, null)`) — under the guard these would
     otherwise reject with the guard's message rather than the mocked transport error — and the one
     inside "null pin: the fallback arm writes an EMPTY known_hosts and carries no alias", which is
     deleted outright.
   - Add one runtime-guard case per helper: `null as unknown as string` rejects with the guard's
     message and the `execFile` mock is never called. (Types stop a TypeScript caller; this stops a
     JS or `as any` caller. The existing `""`/whitespace/CR-LF refusals stay as they are.)
   - Delete "git-auth.ts carries the unpinned TOFU literal exactly once (Guard 1 allow-list count)".
     Guard 1 (`test-no-tofu-ssh.sh`) is the one owner of "no accept-new literal in git-auth.ts" once
     the allow-list entry is gone; a second vitest source scan would duplicate it (plan review).
3. `apps/web-platform/test/helpers/ssh-host-key-fixture.ts` — keep `TOFU_OPT` (the pinned tests use
   it in `not.toContain`), update its comment: git-auth.ts now carries zero such literals.
4. `apps/web-platform/test/git-data-replication.test.ts` — update the reason-word comment
   (`pin_invalid / pin_absent`).
5. `apps/web-platform/infra/git-data-flag-precheck.test.sh` — **unchanged** (plan review cut K12/K12b):
   its K6–K11 already prove the `TOFU_ARM` probe detects an arm, and Guard 1's `P_STRICT` pattern is a
   superset of the probe's `StrictHostKeyChecking=accept-new` match, so with `git-auth.ts` off the
   allow-list the real file cannot carry what the probe looks for. The brief's "the flag precheck
   must then read `TOFU_ARM absent`" is verified pre-merge by running the probe's own predicate on the
   real file (AC7) and post-merge on the next authorized proof dispatch.
6. `tests/scripts/test-no-tofu-ssh-mutation.sh`
   - **Row 5** becomes "a TOFU literal re-added to git-auth.ts (no allow-list entry) → RED naming
     `apps/web-platform/server/git-auth.ts`". The needle changes from `expects 1 hit(s) and has 2` to
     the guard's non-allow-listed failure text for that path,
     `apps/web-platform/server/git-auth.ts: 1 unpinned SSH host-key hit(s)`.
   - **Row 5b** (per-MATCH counting on an allow-listed line) is retargeted to
     `apps/web-platform/infra/git-data-ownership.test.sh`, whose allow-listed line (the `ssh -q -o
     StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null …` line) carries 2 hits. The `sed`
     anchors on that line's `UserKnownHostsFile=/dev/null` token (spelled by concatenation, as the
     harness does) and inserts a third literal there; the needle becomes `expects 2 hit(s) and has 3`.
     Its precondition becomes positional, not just "the file changed": the line count is unchanged,
     exactly one line of `git-data-ownership.test.sh` matches the guard's patterns, and `grep -o`
     finds 3 matches on it (a literal landing on a new line would leave per-line counting at 3 too).
   - **Row 2** (empty enumeration) still needs a `expects 1 hit(s) and has 0` line; after the edit,
     `infra-config-gate.test.sh|1|…` supplies it. Keep the needle; confirm it still fires.
   - Update the header matrix table text for rows 5 and 5b.

Run the two shell suites and the two vitest files: every new or changed case is RED against the
current code (the helpers still accept `null`, the allow-list still names `git-auth.ts`, the real file
still carries the literal), except rows that describe unchanged behaviour.

#### Phase 2 — GREEN: delete the arm

**One commit.** Items 1 and 5 below land together: the moment `TOFU_FALLBACK_OPTS` leaves
`git-auth.ts`, `test-no-tofu-ssh.sh` reds on its stale `git-auth.ts|1` allow-list entry, so a split
leaves a commit lefthook and CI reject and invites "temporarily relax the guard".

1. `apps/web-platform/server/git-auth.ts`
   - Delete `TOFU_FALLBACK_OPTS` and its comment block ("The ONE unpinned host-key option in this
     file…").
   - `gitDataHostKeyTrust(hostKeyPin: string)`: first statement is a runtime guard — `if (typeof
     hostKeyPin !== "string" || !GIT_DATA_HOST_KEY_PIN_RE.test(hostKeyPin)) throw new
     Error("git-data: refusing to dial without a valid host-key pin …")` — then the pinned return.
     Export `GIT_DATA_HOST_KEY_PIN_RE` from `git-data-replication.ts` (it already carries a
     `# twin:` note; add `git-auth.ts` to it) so the guard is exactly as strict as the resolver, not
     just "non-empty, single line".
     It runs before any temp file is written (it already sits above the `try`).
   - `gitWithPrivateKeyAuth(…, hostKeyPin: string, …)` and `sshWithPrivateKeyAuth(…, hostKeyPin:
     string, …)`; rewrite their JSDoc (`@param hostKeyPin` no longer mentions `null`; the "A `null`
     pin takes the transitional fallback arm" sentence goes).
   - Rewrite the section comment: the pin is required; an absent or malformed pin refuses before any
     dial (ADR-237, #5914 closed by this PR).
2. `apps/web-platform/server/git-data-replication.ts`
   - `resolveGitDataHostKeyPin(): string`. Absent → throw `git-data: GIT_DATA_SSH_HOST_KEY is unset
     (GIT_DATA_STORE_ENABLED=<true|unset/false>) — refusing unpinned SSH to the git-data host. The
     replace job publishes it to Doppler prd.` Delete `pinAbsentReported` and the
     `pin_absent_store_disabled` report. Rewrite the JSDoc (no `null` arm; the flag-flip
     precondition sentence becomes history: "deleted by #5914").
   - `provisionGitDataRepo(workspaceId, preResolvedHostKeyPin?: string)`.
   - `logGitDataHostKeyPinAtStartup`: after the log line, when `s.state === "absent"` and git-data is
     armed (any of `GIT_REMOVE_SSH_PRIVATE_KEY`, `GIT_PROVISION_SSH_PRIVATE_KEY`, `GIT_DATA_SSH_HOST`
     non-empty after trim), `reportSilentFallback(null, { feature: "git_data_host_key_pin", op:
     "pin_absent_at_startup", message: "git-data host-key pin absent at startup" })` — the **message
     path**, because an Error-path report loses its tags to the pino mirror's pre-capture (#8629).
     Move the existing `pin_invalid_at_startup` report to the same path. Still never throws. The three-input check is written
     inline (plan review cut a shared helper: `removeGitDataRepo`'s `remove_key_absent` test is
     "remove key absent AND provision key or host set", a different predicate).
   - `removeGitDataRepo`: `let hostKeyPin: string`; reason word `inspect… === "invalid" ? "pin_invalid"
     : "pin_absent"`; update the comment ("a FIXED reason word … `pin_invalid` | `pin_absent`") and
     the `unconfigured` doc comment on the outcome type. The resolver guard already sits outside the
     ssh `try`, so an absent pin is `unconfigured`; the git-auth runtime guard is a second layer that
     only a caller bypassing the resolver can reach, and in `removeGitDataRepo` it would throw inside
     the `try` and classify as `unreachable` (no numeric `code`). That path is unreachable by
     construction today; say so in the comment rather than adding a mapping.
3. `apps/web-platform/server/git-data-client.ts` — update the guard comment ("an absent or malformed
   pin throws here, whatever the flag").
4. `apps/web-platform/server/account-delete.ts` — update the comment block: `pin_invalid |
   pin_absent — GIT_DATA_SSH_HOST_KEY is malformed or unset (#7226, #5914)`; and move the erasure
   report (today `reportSilentFallback(new Error(...), ...)` with the message "git-data erasure
   STATUS") to the message path (`reportSilentFallback(null, { ..., message })`, same message text).
   This PR makes `unconfigured` `pin_absent:` the outcome of every deletion when the pin is missing, and
   the only page for it is `art17_erasure_incomplete`, which filters on `feature`/`op` tags that the
   Error path loses (#8629, deepen-plan observability review). The fleet-wide fix stays #8629's;
   comment there that this emitter moved. The outer `catch (err)` report keeps the Error path (a real
   thrown error), and is noted on #8629 as still affected.
5. `tests/scripts/test-no-tofu-ssh.sh` — delete the ALLOWLIST line
   `apps/web-platform/server/git-auth.ts|1|TOFU_FALLBACK_OPTS: …`. Nothing else in the guard changes.
6. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; every TS2345 it reports on a
   `null` pin before the fix is a call site to convert (`hr-type-widening-cross-consumer-grep`: this
   is a narrowing, so the risk is a caller still passing `null`, and the compiler enumerates them).

#### Phase 3 — Records (same PR)

1. **Runbook** `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
   - Preconditions checklist: tick **Step 2** (evidence: rung-2 rehearsal 35914294265 and evidence PR
     #8655, per #5914 issuecomment-5803357950), **Step 3** (G3 replace run 36118115758; startup line
     `git_data_pin=present fp=SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs` at
     2026-09-25T09:39:39Z, per #5914 issuecomment-5830287903, re-read under G2), **Step 5** (cite the
     step-5 record's comment URL from G1), **Step 6** (this PR). Leave **Step 1** unticked and
     unedited (push-triggered applies 36150370048, 36186259051, 36249105103 failed).
   - Flag-flip precondition paragraph: `TOFU_ARM absent` is now what `main` reads; the reminder is
     satisfied from this merge on. Also correct its sentence "The enforcing control is the app's pin
     resolver, which throws on an absent pin while the store flag is on": after this PR it throws on
     an absent pin whatever the flag says. The other two conditions (pin present in `prd`, #8572
     paging) stand.
   - Step 5 (a): one dated line under "the flag precheck's `TOFU_ARM present` warning is expected
     until step 6": since PR #9096 a dispatch from `main` reads `TOFU_ARM absent`, and a `present`
     warning there is a finding.
   - Step 5.2: record the reuse rule the CTO ruled on 2026-09-28 — an existing `clear` run qualifies
     when its head descends from the proof-half merge and that merge's deploy arm ended `success`
     before the **job** started (the wait exists to keep the job off a host mid-redeploy, so dispatch
     time is the wrong comparison).
   - Step 6: append "**Done:** PR #9096 …" under the step, as step 4 does (keyed by PR number, not a
     date: the merge waits on step 5, whose end date is unknown).
   - Step 6: record the CLO's 2026-09-28 ruling that a `NOT DISCHARGED` step-5 record does not block
     step 6 when its `clo-attestation` issue is open and nothing claims full discharge.
   - "Deploy-day go/no-go (step 3)", bullet "The first rotation cannot produce `host_key_mismatch`":
     one dated line — since PR #9096 there is no fallback arm; a container without a pin refuses
     (`unconfigured` `pin_absent:`) and emits `pin_absent_at_startup`; a rotation's stale-pin window
     is unchanged (`host_key_mismatch` until the pin-redeploy follower loads the new pin).
   - "Between merge and step 3": one dated line — historical since step 3 (2026-09-25); the
     `pin_absent_store_disabled` event no longer exists after PR #9096.
   - Verdict-map row "The app, an Art. 17 erasure, pin fault": `detail` starting `pin_invalid:` or
     `pin_absent:` — match with the colon, because `pin_absent` is a prefix of the old word (events
   before this PR read `pin_absent_store_enabled:`; keep that word in the row as history). The row's
   existing remedy ("fix the pin …, then discharge the ids as in host-key step 5") is the sweep path
   that keeps the login page's "will be completed" promise after the pin is restored (CPO C3); make
   the row say so for `pin_absent:` explicitly; count the Art. 12(3) one-month deadline from the first
   `pin_absent:` event and route such events to a `clo-attestation` issue with that deadline in its
   title; and state its limit: "discharge as in step 5" works
   only while `GIT_DATA_STORE_ENABLED` has never been on; after the first flip it depends on #8211's
   per-id re-erasure path.
2. **ADR-237** — append `## Addendum — PR #9096 (#5914): the transitional app arm is deleted`:
   what was deleted, that the Residual "The transitional app arm (#5914)" is closed, the new refusal
   semantics (absent pin → `unconfigured` `pin_absent`, whatever the flag), the new proactive signal
   (`pin_absent_at_startup` when armed, replacing the deleted `pin_absent_store_disabled`; paging for
   it is #8572's), and that a rotation's stale-pin window is unchanged (`host_key_mismatch` until the
   pin-redeploy follower loads the new pin), and the residual that remains: a writer of Doppler `prd`
   who swaps `GIT_DATA_SSH_HOST_KEY` and holds a private-network position is pinned by the app, and
   only `scheduled-terraform-drift.yml` sees it, after the fact. Earlier text is not edited.
2b. **ADR-220** — one line appended to its amendment log (append-only), keyed by PR #9096: the
   flag-flip precondition "#5914 closed" is met by this PR, and the app's pin resolver now refuses an
   absent pin whatever the flag. No earlier line is edited.
3. **C4** — `knowledge-base/engineering/architecture/diagrams/model.c4`:
   - edge `claude -> gitDataStore`: replace "a transitional unpinned fallback applies only while no
     pin is published and the store flag is off (#5914)" with "an absent or malformed pin refuses the
     dial (#5914)".
   - **new edge** `api -> gitDataStore` (plan review, architecture): the Art. 17 erasure dial
     (`removeGitDataRepo`, reached from `app/api/account/delete/route.ts` → `account-delete.ts`) is the
     one path this PR changes, it is **not** flag-gated, and no edge models it today. Prose: "Art. 17
     erasure of the user's bare repo over the REMOVE key's forced command, not gated on
     GIT_DATA_STORE_ENABLED; host key pinned (ADR-237); an absent or malformed pin returns
     `unconfigured` without dialing (#5914)", `technology "SSH over private net"`. Both elements are
     already in the container view, so no `views.c4` change; confirm the edge renders.
   Regenerate `model.likec4.json` (`bash scripts/regenerate-c4-model.sh`, which lefthook's
   `c4-model-regenerate` also runs). Run `apps/web-platform/test/c4-code-syntax.test.ts`,
   `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.
4. **Encryption-posture ledger** — `scripts/encryption-posture-ledger.json` `connections[9]`:
   select the row by its `connection` name (`web-1 app container -> git-data sshd …`), not by index.
   `cert_verification: "on"`; delete the `exception` block; rewrite `tls` as "SSH-2 over the Hetzner
   private network; git-data authenticated by its Terraform-minted ED25519 host key
   (GIT_DATA_SSH_HOST_KEY), pinned on every dial; an absent or malformed pin refuses. Unpinned
   fallback arm deleted by PR #9096, #5914; ADR-237 Addendum" (the dated pointer follows the
   ledger's existing "superseded on web-1 by …" prose); rewrite `does_not_defend` to exactly the
   four clauses in this plan's Encryption Posture block. `enforced_at` stays. No schema change and
   no `supersedes_note` field (CLO, 2026-09-28: the flip, the ADR-237 addendum and a register marker
   naming this row's flip together satisfy the counsel review's "rewritten in place with Superseded
   markers"). Run `python3 scripts/lint-encryption-posture.py` and
   `bash scripts/lint-encryption-posture.test.sh`.
5. **Art. 30 register** — `knowledge-base/legal/article-30-register.md`. Spawn the
   `soleur:legal:clo` agent with the counsel review's triggers (1) and (2), the cell texts below, this
   PR's diff summary and the G1/G2 evidence, and ask for the exact marker wording for **four**
   markers (CLO scope ruling, 2026-09-28):
   - PA-36 (g)(14) **activation** — past fact, dated 2026-09-25, evidence #5914
     issuecomment-5830287903 re-read under G2. Its status label still reads "DRAFTED /
     NOT-YET-ACTIVE" and its last sentence ("Until activation, the erasure path … runs over that
     arm") is out of date; closing residual (b) without this would make the cell contradict itself.
   - PA-36 (g)(14) **residual (b) closure** — conditioned on this PR's merge ("fires on the merge of
     PR #9096 …"), never past tense, and naming the ledger row's flip.
   - The sibling markers at **PA-1 (g)(14)** and **PA-2 (g)(18)**, which repeat "until #5914 deletes
     it, the SSH helpers keep a transitional unpinned arm"; each gets its own Superseded marker.

   Paste the CLO's wording verbatim; the operator neither drafts nor signs it. #8634 (ADR-239 /
   row D5 of the 8189 review) stays separate. The counsel review `2026-09-counsel-review-7226.md` is
   not edited: at ship Phase 5.5 the CLO writes a new re-attestation record under
   `knowledge-base/legal/audits/` discharging triggers (1) and (2). No published `docs/legal/**`
   page mentions the arm, so the #7387 public-claim gates do not fire.

#### Phase 4 — Ship

- PR #9096 title `security(git-data): delete the unpinned host-key fallback arm (#5914 host-key step 6)`;
  body `Closes #5914`, `Ref #8211`, `Ref #7226`; the G1/G2 evidence; the post-merge line below.
- Mark ready only after G1 and G2 read GO; merge after G3.
- **After merge (reads only, by the shipping session):** wait for the merge's deploy with
  `deploy-arm.sh find --wait 90 <merge-sha>` run under Monitor (explicit poll count;
  `hr-monitor-not-run-in-background-for-polling`) → `DEPLOY=success`; `deploy-arm.sh served
  <merge-sha>` → `CONTAINS`; G2 read 3 again from that deploy's `createdAt` (every expected host's
  newest line `present` with the expected fingerprint); Sentry, via the searchable tags only (`extra`
  is not indexed): `feature:account-delete op:git-data-bare-repo-erasure erasure_outcome:unconfigured`
  and `feature:git_data_host_key_pin op:pin_absent_at_startup` / `op:pin_invalid_at_startup` since
  the deploy, each 0, and no **unresolved** issue for the first query (open any hit with
  `scripts/sentry-issue.sh`). The startup line is the primary
  evidence; a zero erasure count may only mean nobody deleted an account.
- **If a post-merge read fails** (`absent`/`invalid`, a missing host, or a pin-fault event): do
  **not** revert — a revert restores the unpinned arm. Republish the pin (dispatch
  `git-data-host-replace` only with the operator's per-step authorization, or re-run
  `git-data-pin-redeploy.yml` if the secret is present but not loaded), then sweep the refused
  erasures through the runbook's pin-fault row.
- Post one comment on #8211 (the result, and that the next authorized proof dispatch must read
  `TOFU_ARM absent`) and one on #8572 (the new reason word `pin_absent`, that `detail` is in
  unindexed `extra` so its rule must key on `op`/tags, and that `pin_absent_at_startup` /
  `pin_invalid_at_startup` want routing). Read #8572 back after commenting.
- **Deferred, not an operator checklist:** the next authorized `git-data-cutover.yml` dispatch from
  `main` must read `TOFU_ARM absent`. That dispatch is already required by the #8211 PR2 remainder
  (the proof run before the freeze), and the #8211 comment above records it. No new issue.

## Files to Edit

- `apps/web-platform/server/git-auth.ts`
- `apps/web-platform/server/git-data-replication.ts`
- `apps/web-platform/server/git-data-client.ts` (comment only)
- `apps/web-platform/server/account-delete.ts` (comment; erasure report moved to the message path)
- `apps/web-platform/test/account-delete.test.ts` (the report's first argument is `null` and its tags are intact)
- `apps/web-platform/test/git-auth.test.ts`
- `apps/web-platform/test/git-data-host-key-pin.test.ts`
- `apps/web-platform/test/git-data-replication.test.ts` (comment only)
- `apps/web-platform/test/helpers/ssh-host-key-fixture.ts` (comment only)
- `tests/scripts/test-no-tofu-ssh.sh`
- `tests/scripts/test-no-tofu-ssh-mutation.sh`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md` (one amendment-log line)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (generated)
- `scripts/encryption-posture-ledger.json`
- `knowledge-base/legal/article-30-register.md` (the four CLO-drafted markers only)

## Files to Create

- `knowledge-base/legal/audits/<date>-counsel-reattestation-5914.md` (name chosen by the CLO) — the
  CLO's re-attestation record for counsel-review-7226 triggers (1) and (2), written by the
  `soleur:legal:clo` agent at ship Phase 5.5, not by the implementer.

## Open Code-Review Overlap

None. Checked 2026-09-28 against the 86 open `code-review` issues, by full path for every file in
Files to Edit and by basename (`git-auth.ts`, `git-data-replication.ts`, `test-no-tofu`,
`encryption-posture-ledger`, `git-data-flag-precheck`): no match.

## User-Brand Impact

- **If this lands broken, the user experiences:** a deleted user whose account deletion reaches the
  git-data erasure step is shown, on the login page after deletion, that an outstanding erasure "will
  be completed", because `removeGitDataRepo` returns `unconfigured` `pin_absent:` for every
  deletion. That happens if production ever runs this code without a loaded pin (G2 guards the
  merge; a later pin loss is drift). Today the store holds no repository, so no data is left behind,
  but every such deleted user sees the notice. **Paging is per Sentry issue, not per deletion**
  (deepen-plan, user-impact review): `art17_erasure_incomplete` fires on `first_seen`, `reappeared`
  or `regression`, and every refusal shares the message `git-data erasure unconfigured`, so only the
  first refusal pages, and none does while that issue sits unresolved. G1 and the post-merge reads
  therefore also require **no unresolved** Sentry issue for
  `feature:account-delete op:git-data-bare-repo-erasure erasure_outcome:unconfigured`, so the next
  refusal pages.
- **After the first `GIT_DATA_STORE_ENABLED` flip** a `pin_absent` refusal leaves a real repository on
  the host, and "discharge as in step 5" no longer works (emptiness stops being evidence); re-erasure
  then depends on #8211's per-id path. This is a flag-flip limit, already one of #8211's own
  preconditions ("the flip must not happen until a per-id re-erasure path exists"); the runbook's
  pin-fault row states it.
- **Art. 12(3) clock on a refused erasure:** before this PR an absent pin still erased (unpinned);
  now the erasure waits for the pin to be restored and the sweep to run. The runbook's pin-fault row
  counts the one-month deadline from the first `pin_absent:` event and routes any such event to a
  `clo-attestation` issue carrying that deadline in its title, as step 5 does for `NOT DISCHARGED`.
- **If this leaks, the user's data is exposed via:** nothing new. The change removes an exposure: an
  impersonator of `10.0.1.20` on the private network could previously be accepted on first contact
  during an Art. 17 erasure call whenever the pin was absent and the flag off. Remaining vectors are
  unchanged and recorded elsewhere: a reader of main-root Terraform state with a network position
  (#8209), and a rooted web-1.
- **Brand-survival threshold:** `single-user incident`. The Art. 17 erasure path answers one data
  subject at a time; a wrong outcome is a per-user compliance incident. `requires_cpo_signoff: true`;
  `soleur:engineering:review:user-impact-reviewer` runs at review.
- **Detection gap until #8572 ships:** the new `pin_absent_at_startup` boot event is logged to Sentry
  but pages no one until #8572's rule routes it; until then an absent pin is caught by G2 before
  merge, by the post-merge reads, by Terraform drift (a deleted secret), and otherwise by the first
  refused erasure's `art17_erasure_incomplete` page.

## Observability

```yaml
liveness_signal:
  what: the app's startup line `git_data_pin=present fp=SHA256:<fp>` (warn level, shipped to Better Stack by Vector's app_container_warn_filter)
  cadence: once per web container start (every deploy)
  alert_target: none by itself; read at deploy (G2 and the post-merge read). Pin removal from Doppler prd is caught by scheduled-terraform-drift.yml (doppler_secret.git_data_ssh_host_key is Terraform-owned)
  configured_in: apps/web-platform/server/git-data-replication.ts (logGitDataHostKeyPinAtStartup), apps/web-platform/server/index.ts, apps/web-platform/infra/vector.toml

error_reporting:
  destination: Sentry project web-platform (org jikigai-eu), via reportSilentFallback in apps/web-platform/server/account-delete.ts
  fail_loud: an erasure refused for a pin fault emits feature=account-delete op=git-data-bare-repo-erasure with tag erasure_outcome=unconfigured and extra.detail starting `pin_absent:` or `pin_invalid:`; replication and fetch (flag-gated, off) throw into their existing failure reports

failure_modes:
  - mode: GIT_DATA_SSH_HOST_KEY absent in the running container (deleted outside Terraform, or a container started before a pin loaded)
    detection: at boot, Sentry event feature=git_data_host_key_pin op=pin_absent_at_startup (armed processes only) plus the startup line `git_data_pin=absent`; every erasure returns unconfigured `pin_absent:`; Terraform drift shows a create of doppler_secret.git_data_ssh_host_key
    alert_route: sentry_alert.art17_erasure_incomplete (email, issue owners -> active members) per refused erasure; scheduled-terraform-drift.yml failure for the secret; the boot event is discoverable in Sentry now and is routed to a page by #8572's rule
  - mode: pin malformed
    detection: startup Sentry event op=pin_invalid_at_startup; erasures return unconfigured `pin_invalid:`
    alert_route: sentry_alert.art17_erasure_incomplete
  - mode: pin stale after a host replace (key rotated, redeploy not yet loaded)
    detection: erasure returns host_key_mismatch (SSH 255 + host-key stderr)
    alert_route: sentry_alert.art17_erasure_incomplete; runbook H4 triage
  - mode: a TypeScript or JS caller passes a null/empty pin to a git-auth helper
    detection: tsc --noEmit fails at build; at runtime gitDataHostKeyTrust throws before any temp file or exec. Every production caller resolves the pin first, so this is unreachable by construction; a bypassing caller inside removeGitDataRepo's ssh try would classify as unreachable (no numeric code), which the code comment states
    alert_route: CI required checks; sentry_alert.art17_erasure_incomplete at runtime

logs:
  where: Better Stack app source (warn+ lines from web containers), queried with scripts/betterstack-query.sh; Sentry issue stream for events
  retention: Better Stack per source plan (hot table plus the s3 archive the query unions); Sentry per org retention

discoverability_test:
  command: bash tests/scripts/test-no-tofu-ssh.sh
  expected_output: "all allow-listed at exact counts"
```

`discoverability_test.command` note: Guard 1 is the observable property this PR establishes at the
source level (no unpinned SSH option anywhere outside the three reviewed exemptions). Its final line
reads `test-no-tofu-ssh: PASS (<n> files scanned, 3 file(s) with hits, all allow-listed at exact
counts)` after this PR (4 before it). Measured on `origin/main` 2026-09-28: 1.1 s, inside preflight
Check 10's 15 s cap; no credentials, no network, no ssh, and no shell-active characters in the
command. The runtime signal (the startup line and Sentry ops) needs prd credentials and is read by
G2 and the post-merge reads instead.

Deepen-plan Phase 4.7 note: the suite-shape detector matches this command (`tests/`), a deliberate
over-inclusive proxy. Argued down: `test-no-tofu-ssh.sh` is a single guard scan (one `git ls-files`
plus six `git grep` arms), not a suite; measured 1.1 s, well inside the 15 s cap. Its mutation
harness, which is suite-shaped, is not the probe. `probe-verb-gate.sh` accepts the verb (rc 0).

## Encryption Posture

```yaml
at_rest: []   # no store is added or changed
in_transit:
  - connection: web-1 app container -> git-data sshd (Hetzner private network, 10.0.1.20:22)
    enforced_at: apps/web-platform/server/git-auth.ts gitDataHostKeyTrust (gitWithPrivateKeyAuth, sshWithPrivateKeyAuth); apps/web-platform/server/git-data-replication.ts resolveGitDataHostKeyPin
    tls: SSH-2 over the Hetzner private network; the git-data host is authenticated by its Terraform-minted ED25519 host key (GIT_DATA_SSH_HOST_KEY) on every dial, StrictHostKeyChecking=yes under the alias git-data with -F /dev/null and GlobalKnownHostsFile=/dev/null
    cert_verification: on
    does_not_defend: a reader of main-root Terraform state (the host private key lives there and in user_data) who also holds a private-network position (#8209); a writer of Doppler prd who replaces GIT_DATA_SSH_HOST_KEY with their own key and holds a private-network position (the app then pins the impersonator; detected only after the fact by scheduled-terraform-drift.yml); a rooted web-1, which holds the transport, provision and remove keys; a rooted git-data answering falsely under its own key
    disclosed_as: not-publicly-claimed
# exception: removed — cert_verification is on after this PR
```

## Architecture Decision (ADR/C4)

Detection fires: this PR completes a residual an accepted ADR recorded (ADR-237 "The transitional
app arm (#5914)") and changes a trust boundary's fail mode (absent pin: dial unpinned → refuse).

### ADR

Amend **ADR-237** by a new addendum keyed by PR number (`## Addendum — PR #9096 (#5914): the transitional app
arm is deleted`), not a new ADR: the decision (pin both hops; the app pins git-data) is unchanged, and
this is the residual it named closing. Content per Phase 3 item 2. No ordinal is claimed, so the
ADR-ordinal collision gate does not apply.

### C4 views

Read on 2026-09-28: `model.c4` (the `gitDataStore` element and every edge touching it: `hetzner ->
gitDataStore` probe, `github -> gitDataStore` root auth, `gitDataStore -> sentry`, `gitDataStore ->
betterstack`, `gitDataStore -> doppler`, `claude -> gitDataStore`), `views.c4` (the container view
includes `platform.infra.gitDataStore`) and `spec.c4` (element kinds only). Enumeration:

- **External human actors:** none added or changed. The deleted user is not a C4 actor on this path
  and the notice surface is unchanged.
- **External systems / vendors:** Doppler (pin source, already modeled via deploy-time env and
  `gitDataStore -> doppler`), Sentry (new boot op on the existing app → Sentry path), Better Stack
  (existing warn-line shipping). All modeled; no new vendor.
- **Containers / stores:** `claude` (Agent Runtime, the flag-gated replication and fetch),
  `api` (API Routes, which run account deletion and so the unflagged Art. 17 erasure dial) and
  `gitDataStore`; all three modeled.
- **Access relationships:** two changes. (1) `claude -> gitDataStore` states "a transitional unpinned
  fallback applies only while no pin is published and the store flag is off (#5914)", which this PR
  falsifies; replace with "an absent or malformed pin refuses the dial (#5914)". (2) The erasure dial
  from `api` to the git-data host has **no edge** today, and it is the one path whose fail mode this
  PR changes; add `api -> gitDataStore` (prose in Phase 3 item 3). No element, tag or view `include`
  changes; both endpoints are already in the container view.

Regenerate `model.likec4.json` and run `apps/web-platform/test/c4-code-syntax.test.ts`,
`apps/web-platform/test/c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (the
edit changes no cardinality in edge prose, which the parity suite confirms).

### Sequencing

Lands in this PR. Nothing is soak-gated; the addendum describes the state at merge.

## Guard Contract

### Guard 1 — no-TOFU text guard (`tests/scripts/test-no-tofu-ssh.sh`) after the allow-list shrinks

**Property.** No tracked file outside the three remaining allow-list entries configures an SSH client
to accept an unknown host key, and `apps/web-platform/server/git-auth.ts` carries zero such literals.

**Assembly.** The universe is `git ls-files --cached --others --exclude-standard` minus
`knowledge-base/**`; every file flows through the one `_grep` chokepoint and the `HITS` map; the
ALLOWLIST heredoc is the only exemption source. After this PR the heredoc holds
`git-data-ownership.test.sh|2`, `infra-config-gate.test.sh|1`, `tests/scripts/test-no-tofu-ssh.sh|5`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `const X = ["-o", "StrictHostKeyChecking=accept-new"]` to `git-auth.ts` (row 5, retargeted) | RED, `apps/web-platform/server/git-auth.ts: 1 unpinned SSH host-key hit(s)` |
| 2 | Empty enumeration (row 2): 0 files scanned | RED (floor + a zero-hit allow-list entry) |
| 3 | A third literal appended to `git-data-ownership.test.sh`'s allow-listed line, after its compliant two (row 5b, retargeted) | RED, `expects 2 hit(s) and has 3` |
| 4 | Re-add the deleted `git-auth.ts|1|…` allow-list line with the arm still deleted | RED, zero-hit stale exemption — covered by existing harness row 6, which plants a zero-hit entry through the same code path; no new row |
| 5 | Guard verdict stubbed to `exit 0` (H-a) | the harness itself goes RED |

**Harness rows.** H-a above; must-PASS H-b (`SHKC=yes` + `UKHF=/tmp/kh`) and the unmutated baseline,
which now includes the real `git-auth.ts` with zero hits.

**Anchor.** The allow-list lives in the guard file, reviewed under CODEOWNERS; the zero-hit rule
makes a stale re-added exemption RED, so weakening needs both a code change and a reviewed allow-list
edit in the same diff.

A precheck guard (K12/K12b) was planned and cut at plan review. The precheck K12/K12b cases were cut: Guard 1's `P_STRICT` pattern is a superset of the precheck
probe's match, so Guard 1 owns "the real `git-auth.ts` carries no accept-new literal", and K6–K11
already prove the probe detects an arm. AC7 runs the probe's own predicate on the real file.

### Guard 2 — pinned-only transport (vitest + tsc)

**Property.** Neither git-auth helper dials, or writes a temp key, without a non-empty single-line pin.

**Assembly.** Two exported helpers (`gitWithPrivateKeyAuth`, `sshWithPrivateKeyAuth`) both call the
one chokepoint `gitDataHostKeyTrust` before their `try`; four resolution sites feed them
(`provisionGitDataRepo`, `removeGitDataRepo`, `replicateToGitData`, `fetchFromGitData`), all via
`resolveGitDataHostKeyPin`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `if (hostKeyPin === null) return {knownHosts:"", sshOpts:[…accept-new]}` | runtime-guard tests RED; Guard 1 RED |
| 2 | `resolveGitDataHostKeyPin` returns `""` instead of throwing when absent | "absent + store disabled throws" RED; `removeGitDataRepo` never-dials test RED |
| 3 | Only `sshWithPrivateKeyAuth` guarded (second helper skips the check) | the `gitWithPrivateKeyAuth` runtime-guard test RED |
| 4 | Reason word reverted to `pin_absent_store_enabled` | `/^pin_absent: /` assertions RED |
| 5 | The startup arming predicate reads only `GIT_REMOVE_SSH_PRIVATE_KEY` (the second and third inputs dropped) | the provision-key-only and host-only AC5b rows RED |
| 6 | The startup event fires whenever the pin is absent (arming check removed) | the unarmed AC5b row RED |
| 7b | The runtime guard reverted to CR/LF-and-empty only | a new AC5 case with a valid key plus a trailing comment RED |
| 7 | The runtime guard's `typeof` clause dropped (a `null` then dies in `.trim()` with a `TypeError`) | AC5 RED, because it matches the guard's exact text |
| 8 | A startup op or the erasure report reverts to the Error path (`new Error(…)` as first argument) | AC5b / AC5c RED |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `rg -n "TOFU_FALLBACK_OPTS|accept-new" apps/web-platform/server/` prints nothing.
- [ ] **AC2** `gitWithPrivateKeyAuth` and `sshWithPrivateKeyAuth` declare `hostKeyPin: string`;
  `resolveGitDataHostKeyPin` returns `string`; `tsc --noEmit` passes for `apps/web-platform`.
- [ ] **AC3** With `GIT_DATA_SSH_HOST_KEY` unset and the flag off, `resolveGitDataHostKeyPin()` throws,
  and `removeGitDataRepo` (remove key set) returns `unconfigured` with `detail` matching the regex
  `/^pin_absent: /` and never calls the ssh transport, even when run twice, with `pinReports()` still
  empty afterwards; the resolver's message names the flag state (`GIT_DATA_STORE_ENABLED=unset/false`
  here, `=true` in the enabled twin) (vitest, `git-data-host-key-pin.test.ts`).
- [ ] **AC4** No code path emits `op: "pin_absent_store_disabled"`:
  `rg -n "pin_absent_store_disabled" apps/web-platform/server` prints nothing.
- [ ] **AC5** Each helper, called with `null`, `undefined` and `123` (each `as unknown as string`)
  and with a valid pin followed by a trailing comment (which the resolver's pattern rejects),
  rejects with exactly the new guard text `/refusing to dial without a valid host-key pin/` — not the
  looser existing `/host-key pin/i`, which a `TypeError` from `null.trim()` would also satisfy — and
  the `execFile` mock is never called (vitest, `git-auth.test.ts`). The five former `null` call sites
  pass a `makeEd25519Pin()` pin and keep their original assertions.
- [ ] **AC5b** The file's `beforeEach` also stubs `GIT_DATA_SSH_HOST` to `""` (today it leaks the
  shell's value). At startup with no pin, each row sets all three arming inputs explicitly with
  distinctive synthetic values (unused ones `""`): none set, with `GIT_TRANSPORT_SSH_PRIVATE_KEY` still
  set → no `git_data_host_key_pin` event; all three whitespace-only → no event; each one set alone →
  exactly one report whose options `toEqual({ feature: "git_data_host_key_pin", op:
  "pin_absent_at_startup", message: "git-data host-key pin absent at startup" })` on the **message
  path** (`err` is `null`), and `JSON.stringify(reportSilentFallback.mock.calls)` contains none of the
  synthetic values (vitest, `git-data-host-key-pin.test.ts`). The existing "absent: `git_data_pin=absent`
  at warn" case is armed by that `beforeEach` and now also emits the event; its comment says so.
- [ ] **AC5c** The Art. 17 erasure report in `account-delete.ts` and both startup ops
  (`pin_absent_at_startup`, `pin_invalid_at_startup`) use the message path
  (`reportSilentFallback(null, { …, message })`), so their `feature`/`op`/`erasure_outcome` tags reach
  Sentry (#8629: an Error-path report is pre-captured by the pino mirror with only
  `feature=pino-mirror`, and the tagged capture is dropped). Tests assert the reporter received
  `null` as its first argument with the tags. The parameterised account-delete test that asserts
  `toHaveBeenCalledWith(expect.any(Error), …erasure_outcome…)` changes its first matcher to `null` and
  adds `message: "git-data erasure <status>"`; the outer-catch test keeps `expect.any(Error)`.
- [ ] **AC6** `tests/scripts/test-no-tofu-ssh.sh` passes with no `git-auth.ts` allow-list entry, and
  `tests/scripts/test-no-tofu-ssh-mutation.sh` passes with rows 5 and 5b retargeted (both RED for the
  stated reason).
- [ ] **AC7** The flag precheck's own `TOFU_ARM` predicate reads absent on the real file:
  `grep -ciF 'StrictHostKeyChecking=accept-new' apps/web-platform/server/git-auth.ts || true` prints
  `0` (a copy of the probe's `grep -qiF` line, not a run of the probe; `grep -c` exits 1 on zero), and
  `apps/web-platform/infra/git-data-flag-precheck.test.sh` still passes unchanged (`76 passed`).
- [ ] **AC8** In `scripts/encryption-posture-ledger.json`, the row selected by name —
  `jq '.connections[] | select(.connection | startswith("web-1 app container -> git-data sshd"))'` —
  has `in_transit.cert_verification == "on"` and no `in_transit.exception`, and exactly one row
  matches; `python3 scripts/lint-encryption-posture.py` and `bash scripts/lint-encryption-posture.test.sh`
  pass.
- [ ] **AC9** `model.c4`'s `claude -> gitDataStore` description no longer says "transitional unpinned
  fallback"; a new `api -> gitDataStore` edge models the unflagged Art. 17 erasure dial;
  `model.likec4.json` is regenerated; the C4 syntax, render and count-parity suites pass.
- [ ] **AC10** ADR-237 has a new addendum keyed by PR #9096 and ADR-220 one new amendment-log line;
  neither loses a line: `git diff --numstat origin/main...HEAD -- <ADR-237 path> <ADR-220 path>`
  prints `0` in the deletions column for both.
- [ ] **AC11** The runbook ticks steps 2, 3, 5 and 6 with evidence links, leaves step 1 unticked, the
  verdict-map pin-fault row names `pin_absent:` with its post-flip limit, the flag-flip sentence says
  the resolver refuses an absent pin whatever the flag, and steps 5.2 and 6 record the CTO and CLO
  rulings this plan relies on.
- [ ] **AC12** The register carries the four CLO-drafted markers (PA-36 (g)(14) activation and
  residual (b) closure, PA-1 (g)(14), PA-2 (g)(18)) exactly as the CLO agent drafted them, and a CLO
  re-attestation record exists under `knowledge-base/legal/audits/` citing triggers (1) and (2).
- [ ] **AC13** G1: the step-5 record URL is in the PR body and in the runbook's step-5 tick. If its
  `outcome:` is `NOT DISCHARGED` for any ids, the named `clo-attestation` issue is open with its
  Art. 12(3) deadline, and no text in the PR body or register says step 5 discharged everything.
- [ ] **AC14** G2: the PR body records the expected fingerprint and its source run, the Doppler `prd`
  pin's fingerprint (equal to it), and the newest `git_data_pin=present fp=…` line per expected host
  since the served build's deploy arm started, each with its timestamp.
- [ ] **AC15** The PR body contains `Closes #5914` (body, not title) and references #8211 and #7226.
- [ ] **AC16** Every required check passes by name on the exact head SHA before merge.

### Post-merge (automated reads by the shipping session; no operator step)

- [ ] **AC17** The merge's deploy is `DEPLOY=success` and served (`CONTAINS`); after it, every
  expected host's newest startup line reads `present` with the expected fingerprint; the three
  Sentry tag queries in Phase 4 return 0; the #8211 comment records that the next authorized proof
  dispatch must read `TOFU_ARM absent`, and the #8572 comment is posted and read back.

## Test Scenarios

- Given no `GIT_DATA_SSH_HOST_KEY` and the store flag off, when an account deletion runs
  `removeGitDataRepo` with a remove key set, then the outcome is `unconfigured` `pin_absent: …`,
  nothing is dialed, and the account-delete path reports `erasure_outcome=unconfigured`.
- Given a valid pin, when either helper runs, then its ssh options carry `StrictHostKeyChecking=yes`,
  `HostKeyAlias=git-data`, `-F /dev/null`, `GlobalKnownHostsFile=/dev/null`, and the per-call
  known_hosts holds exactly `git-data <pin>`.
- Given a pin of `null`/`undefined`/`123` passed by an untyped caller, when a helper runs, then it
  throws the guard's refusal before any exec (the guard sits above the temp-file writes by code
  order; the test asserts only "before any exec").
- Given the real tree, when the precheck's `TOFU_ARM` predicate is applied to the real `git-auth.ts`,
  then it matches nothing (AC7).
- Given a re-introduced accept-new literal in `git-auth.ts`, when the no-TOFU guard runs, then it
  fails naming that file.
- Regression: given store enabled and a valid pin, replication, provision and fetch still pass the pin
  (existing cases, unchanged).

## Domain Review

**Domains relevant:** Engineering, Legal, Product (plan-time sign-off at the `single-user incident`
threshold)

### Engineering

**Status:** reviewed (soleur:engineering:cto, 2026-09-28)
**Assessment:** Sound; four plan defects fixed in place. (1) One reason word `pin_absent`, matched
with the colon everywhere because it prefixes the old word; `detail` lives in Sentry `extra`, which no
rule indexes. (2) Reuse of proof run 36339208990 is sound, but the eligibility test was wrong:
`deploy-arm.sh` needs the full 40-hex SHA and prints no conclusion time, `served` is about now, and
the runbook's wait is about when the **job** ran; replaced by the ancestor check, the arm's
`DEPLOY=success` preceding the job's `startedAt`, and a no-overlap read. (3) No new risk for the
ADR-220 D6 replace; the Dependencies bullet claiming a changed rotation window was wrong and was
rewritten. (4) Guard 2's row 3 proved the opposite of its claim and row 1 mutated the real file;
later cut with K12 at plan review. AC8 selects the ledger row by name; G2 anchors on
`deploy-arm.sh served` and then `find` of the served build.

### Legal

**Status:** reviewed (soleur:legal:clo, 2026-09-28)
**Assessment:** Step 6 may proceed. The register edit covers four markers (PA-36 (g)(14) activation,
its residual (b) closure conditioned on merge, and the PA-1 (g)(14) / PA-2 (g)(18) siblings), all
CLO-drafted; the ledger needs no schema field, only a dated pointer in `tls`; a `NOT DISCHARGED`
step-5 record does not block merge if its `clo-attestation` issue is open and nothing claims full
discharge; id-less erasure events are *host not reached*, not unidentifiable; the CLO writes a new
re-attestation record at ship Phase 5.5. `soleur:gdpr-gate` required (see below).

### GDPR gate (plan Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` +
`soleur:legal:legal-compliance-auditor` before merging.**

Path scan: `apps/web-platform/server/git-auth.ts` matches the canonical regex
(`apps/web-platform/server/.*auth.*\.(ts|tsx|js)`); no migration, no `.sql`, no API route.
`GDPR-Art-6`, `GDPR-Art-5e`, `GDPR-Art-17` (FK), `GDPR-Art-17-caller`, `GDPR-Chapter-V` and
`GDPR-Art-9`: no match (no schema, column, FK, RPC or vendor change). One `Suggestion`-level note on
Art. 17 behaviour: an absent pin now turns an erasure into `unconfigured` instead of an unpinned
dial, which is a fail-closed change on the erasure path; its user-facing effect and sweep path are
covered by User-Brand Impact, the runbook's pin-fault row and the CLO's review. No `Critical`
finding; no `compliance-posture.md` write. Re-run at work Phase 2 exit, scoped to the diff.

### Product/UX Gate

**Tier:** none (no UI surface in Files to Edit or Files to Create; the login-page notice is unchanged)
**Decision:** reviewed — plan-time CPO sign-off: **yes, with conditions** (soleur:product:cpo,
2026-09-28)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO conditions and where each is met: C1, G1/G2 read fresh at merge with `absent`/`invalid` as NO-GO
(Merge gates, AC13/AC14); C2, a proactive absent-pin signal before any user is affected
(`pin_absent_at_startup`, P7, AC5b; paging routed to #8572); C3, a sweep path for `unconfigured
pin_*` outcomes after the pin is restored (the runbook's pin-fault row, Phase 3 item 1); C4,
CLO-drafted register wording only (Phase 3 item 5, AC12).

## Dependencies & Risks

- **Step 5 not yet done.** The PR can be complete and green while G1 is open; it simply waits.
- **Pin loss after merge fails erasures closed.** Accepted and intended (ADR-237 Alternatives A6
  rejected fail-closed *before* the first replace; that condition is gone). Detection is the art17
  route and Terraform drift.
- **ADR-220 D6 fresh replace.** No new risk (CTO, 2026-09-28). Since step 3 the pin is present, so a
  rotation already yields `host_key_mismatch` until the pin-redeploy follower loads the new pin; the
  deleted arm only ever ran with the pin absent. This PR changes only the absent-pin case (a fresh
  create, or the secret deleted outside Terraform), which now fails closed. Recorded in the runbook's
  go/no-go note and the ADR-237 addendum.
- **CLO turnaround** on the (g)(14) marker. If the CLO wording is not available, the PR waits; the
  register is not edited with engineer-drafted text.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- **Never print an erasure id.** The step-5 sweep's `jq` must pipe ids straight into an aggregating
  `awk`/`sort -u | wc -l`; do not `echo`, `tee` or `head` the events. The session transcript is a log.
- **A Sentry event with no `gitDataRepoId`** is the `removeGitDataRepo threw` arm, which only catches
  pre-dial throws, so it is *host not reached* under the runbook's (d). Count it as "no repository
  id, host not reached", not as unidentifiable. Only an id-less event whose error is not a
  recognised pre-dial throw takes the "If an item cannot be read" path.
- **Do not "fix" K6–K11 or precheck mutation rows 12–15.** They test synthetic fixtures and must keep
  reading `present` for a re-introduced arm; the precheck suite is not edited by this PR.
- **Row 2 of the no-TOFU mutation harness** needs some allow-list entry with count 1; after this PR it
  is `infra-config-gate.test.sh`. If that entry is ever removed, row 2's needle must move.
- **`pin_absent_store_enabled` is not renamed in dated records** (the counsel review's D8 row, earlier
  #5914 comments). Only live code, tests, the runbook's verdict-map row and comments change.
