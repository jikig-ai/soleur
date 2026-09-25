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
   - **Exit 78 = refused to run under shell tracing** (`EX_CONFIG`, #7797). It lands in the TRANSIENT bucket above, which is the fail-safe direction — never a false PASS — but it is a *configuration* signal, not a network one: the probe declined because tracing was on while a live credential was in scope. Re-run with the credential unset to trace safely. A probe stuck reporting 78 every sweep is a caller enabling `-x`, not a flaky dependency.
   - The script may print human-readable output to stdout/stderr; the sweeper captures the last 4 KB and posts it as a comment.
   - **A registered sub-vocabulary inside the TRANSIENT bucket, for NOTIFY-ONLY probes.** Some
     trackers must never be closed by a probe — a legal record whose close is an operator's
     judgement, say. Such a probe can take neither 0 (the close verb) nor 1 (which comments
     "still exits 1" and reads as a regression), so *every* verdict it has lands in the bucket
     above and the sweeper's heading renders them identically. Three codes are reserved so the
     heading distinguishes them: **2 = NOT YET** (measured, nothing qualifies yet — the normal
     daily state), **3 = CANNOT ESTABLISH** (the probe could not measure, and says why), and
     **5 = ACTION REQUIRED** (the condition fired; a human must act). `sweep-followthroughs.sh`
     maps these to words in the comment heading; anything else still reads TRANSIENT. First use:
     `scripts/followthroughs/ccla-representative-icla-7922.sh`. A notify-only probe should say
     so in its header and assert the never-0/never-1 invariant in its own suite — an exit-code
     contract nothing drives is a comment.
   - **State the probe's CREDENTIAL POSTURE in its header, and be exact about what "none" covers.**
     A probe declaring no `secrets=` holds no credential *in its environment*. That is not the same
     as running unauthenticated: `actions/checkout` persists a token into `.git/config`, so any
     `git fetch` the probe makes uses it whether or not the probe knows. If the probe's reads are
     genuinely anonymous, set `persist-credentials: false` on the workflow's checkout and measure
     the anonymous read once — do not infer it.
   - **A probe that will one day be RETIRED needs its retirement written down where the probe is.**
     When the tracker closes, the probe file usually goes with it — and anything else that
     references it (a parity arm in another suite, a back-pointer comment in a third file, a
     runbook section) is left dangling, discovered by whoever next reddens that suite. List those
     references in the probe's header under a `RETIREMENT:` line, so the deletion is one grep.
     Enumerate generated-registry rows (a `suite-shard-legs.tsv` manifest row, an index entry)
     and mid-document mentions, not just the file's own siblings — the issue-8006 probe's
     RETIREMENT listed 3 sites and the true footprint was 5. Treat the header as a seed: at
     retirement time, re-census `git grep <unnumbered-stem>` over live-code dirs and disposition
     every hit in the plan.
   - The script must be deterministic in its exit semantics: do not exit 0 on partial success.
   - **Never name the retired Sentry credential.** The sweeper's Sentry read is `SENTRY_ACTIONS_RO_TOKEN` (the org-level read-only `actions-read-prd` integration, ADR-031, repo secret only). The canonical vendor env-var name it replaced is banned anywhere under `scripts/followthroughs/` — any file at any depth, executable line or comment (one recursive literal grep; a superstring counts) — because a workstation `doppler run -c prd_terraform` binds a *personal*, human-account-scoped token under it (#7797, #7946). Enforced as **rule 2** of `scripts/lint-followthrough-varq-ban.sh` (the executable form of this census); rotation: `sentry-actions-ro-token-rotation.md`.
   - **Never gate the exit code on `: "${VAR:?msg}"`.** Under a non-interactive shell that word-expansion aborts with status **1** (= FAIL in this contract), so a trailing `|| { echo TRANSIENT; exit 2; }` is dead code and an unprovisioned/empty secret reports FAIL instead of TRANSIENT. Use `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi`. **Enforced mechanically by `scripts/lint-followthrough-varq-ban.sh`** (registered in `scripts/test-all.sh`, merge-blocking `test-scripts` shard; #6757) — a banned form on any executable probe line reddens CI. Accept both `200` AND `201` from the Supabase Management query endpoint (`/database/query` returns 201). Verified in `scripts/followthroughs/autovacuum-thrash-6168.sh` (PR #6164) — see `knowledge-base/project/learnings/best-practices/2026-07-07-followthrough-and-shape-gate-silent-falseness.md`.
   - **Query a sink the signal is ACTUALLY written to, and fail-safe when the signal path is unproven.** A soak that greps a sink the target signal never reaches PASSes vacuously and auto-closes the tracker blind (#5934: queried Sentry for an in-sandbox line that this host's `vector.toml` never mirrors to Sentry — only Better Stack). Verify the emit→sink wiring before trusting a zero-count; require a positive liveness marker (proof the producer ran) before treating "zero bad events" as PASS, and exit **TRANSIENT** (not PASS) on any auth/query failure or missing-liveness — so the gate can never false-close.
3. **Declare needed secrets** via the directive's `secrets=` clause. Only the named secrets get exported into the script's environment. Add the secret to `.github/workflows/scheduled-followthrough-sweeper.yml` `env:` block if it isn't already wired.
4. **Add the directive** to the issue body:

   ```html
   <!-- soleur:followthrough
     script=scripts/followthroughs/sentry-checkins-3859.sh
     earliest=2026-05-17T18:00:00Z
     secrets=SENTRY_ACTIONS_RO_TOKEN
   -->
   ```

   **Paste it UNFENCED, at column 0.** The example above is fenced only so it renders in this
   document; the sweeper SKIPS fenced blocks by design (#4200 Gap 3 — a fenced directive is an
   example, not an enrolment) and anchors the opener at column 0. A fenced or indented
   directive is visibly present in the issue body and enrols nothing, which is the hardest
   version of this failure to notice: six of 56 open trackers were dead that way, the oldest
   silent since 2026-06 (#7490). Both the `gh issue create` hook and the sweeper now name the
   fence as the cause instead of reporting a missing directive.

   Place it inline anywhere in the body. Multiple directives in one body: only the first is honored.

5. **Open a PR** that lands the script + (optionally) any new secrets in the workflow env. CI on the PR includes the workflow file's syntax check.

**Before shipping a change to a probe, dry-run the REAL sweeper on the branch.** A fixture suite
certifies the probe's logic. It cannot see whether the host can still answer the query at today's
data volume, and an open-topped window's volume grows daily. Run
`gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`. It is
read-only and posts nothing. Then read the tracker's `exit=` line and output tail in the run log.
**Why:** #6178/PR #8835. A 144/0 suite shipped pins for a probe whose heaviest slice timed out on
the host's page 8 every time, and only the dry run showed it
([learning](../../../project/learnings/2026-09-25-a-fixture-suite-cannot-see-that-the-probe-can-no-longer-take-its-reading.md)).

## Directive fields

| Field | Required | Notes |
|---|---|---|
| `script` | yes | Path MUST start with `scripts/followthroughs/`. Other paths are refused (defense against tampered issue bodies pointing at arbitrary files). |
| `earliest` | yes | ISO-8601 UTC timestamp. The sweeper skips the issue until `now >= earliest`. |
| `secrets` | optional | Comma-separated GitHub secret names. Only these are exported into the script's environment. Omit if the script needs no secrets. |
| **Placement** | yes | The `<!--` opener MUST be at **column 0 and outside any code fence**. Fenced blocks are skipped wholesale and the anchor is column-0, so an indented or fenced directive parses as no directive at all. This is a field of the directive in every sense that matters — get it wrong and the other three are never read. |

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
| **Soak** — `<signal> stays at ~0 for N days post-deploy` (often gating an ADR `adopting → accepted` flip) | `<deploy>+Nd` (UTC; gates the first check to after the soak window) | `SENTRY_ACTIONS_RO_TOKEN` (Sentry-rate soaks; the org-level read-only `actions-read-prd` integration, ADR-031) | rate==0 over a window pinned strictly after deploy ? `exit 0` : `exit 1` — mirror [`reconcile-ff-only-sentry-4977.sh`](../../../../scripts/followthroughs/reconcile-ff-only-sentry-4977.sh) / [`ac8-founder-ambiguous-soak-5673.sh`](../../../../scripts/followthroughs/ac8-founder-ambiguous-soak-5673.sh) (`start=` pins the window past deploy so pre-deploy events don't contaminate the verdict). Enforced at ship time by the **Soak-Gated Follow-Through Enrollment Gate** (ship/SKILL.md Phase 5.5) — a soak declared in PR/plan prose blocks PR-ready until its tracker is enrolled here. |

**`secrets=GH_TOKEN` is MANDATORY for any gh-using probe.** The sweeper runs
verification scripts under `env -i` (PATH + HOME + directive-declared `secrets=`
ONLY). On the CI runner `gh` authenticates from `GH_TOKEN`, not `~/.config/gh`,
so a gh-using script with NO `secrets=GH_TOKEN` is unauthenticated → `gh` fails →
the probe returns exit 2 (transient) on every sweep and the issue **never closes**
(a silent never-close, not a loud failure). The date shape is the only one that
needs no `secrets=` (its body never calls `gh`). This is the same opt-in
mechanism `sentry-checkins-3859.sh` uses (`secrets=SENTRY_ACTIONS_RO_TOKEN`).

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

**Enrolling on a PRE-EXISTING issue** (the auto-wire only fires on issue
create): manually add the `follow-through` label — the sweeper enumerates by
label and never parses bodies, so an unlabeled directive is invisible; verify
no prior directive; directive at column 0; canonical
`script=scripts/followthroughs/<name>.sh` (a bare name fails path
canonicalization **silently** — stderr-only, zero comments, every run);
post-merge, verify the sweeper run log shows the script actually ran — "it
didn't comment" is indistinguishable from "it worked". And note: the sweeper
comments on EVERY non-0/1 verdict with no dedup, so an indefinite-horizon
"watch for upstream" directive spams the tracker (~30 comments/month) — use a
dedicated `scheduled-*-drift.yml` workflow + `Ref #N` for that shape instead.

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

- **An operator-confirmed probe filters verdicts through `scripts/lib/trusted-verdict.sh`, never an
  inline `authorAssociation` select.** `jikig-ai/soleur` is public with issues open, so an
  unfiltered `.comments[].body` accepts a verdict from any authenticated GitHub user (#7448). The
  filter that closed that hole introduced a quieter one: **`authorAssociation` is computed against
  the READING token's visibility**, so a member whose org membership is PRIVATE renders as
  `CONTRIBUTOR` under the sweeper's `GITHUB_TOKEN` and their verdict is dropped silently.

  Measured 2026-09-19 on the same comment, two tokens, in the same hour:

  | Token | `authorAssociation` for `deruelle` | Old filter's verdict |
  |---|---|---|
  | operator PAT | `MEMBER` | honoured |
  | sweeper `GITHUB_TOKEN` | `CONTRIBUTOR` | **dropped** |

  That is why #6617 reported FAIL every night for two months against an issue whose
  `RESULT: PASS` had been recorded on 2026-07-20 (sweeper run 35470503032 prints the
  `CONTRIBUTOR` reading next to `would close with verdict=PASS`, i.e. the reading AND the fix in
  one log). `GET /repos/{owner}/{repo}/collaborators/{login}/permission` resolves EFFECTIVE
  permission, does not depend on membership visibility, and answers 200 under `GITHUB_TOKEN`
  (measured in that same run, so the CODEOWNERS fallback the plan held in reserve was not needed).
  The lib honours `admin`/`maintain`/`write` only.

  Two arms of it are easy to get wrong and both have fixtures: a permission read that FAILS
  (403, network) is `TRANSIENT`, never "untrusted" — absence of evidence is not evidence; but an
  HTTP **404** (`"<login> is not a user"`) is DEFINITIVE and drops just that author. `github-actions`
  comments on nearly every tracker and answers 404, so collapsing the two makes every such thread
  permanently unresolvable — the same permanent red, reached from the other side.

  `scripts/lint-followthrough-varq-ban.sh` rule 4 enforces the POSITIVE OBLIGATION, not a ban on
  one wrong spelling: a probe under `scripts/followthroughs/` that reads issue comments AND
  branches on a `RESULT:` verdict must route that decision through the lib. An inline
  `authorAssociation` select is subsumed — it reads comments, branches on a verdict and does not
  call `trusted_verdict_bodies`, so it fires without needing a rule of its own.

  The difference is load-bearing and was measured. While the rule banned the wrong MECHANISM, a
  live probe read `.comments[].body` with **no author filter at all** — strictly worse than what
  was banned, and invisible to it: the lint ran rc 0 over the verbatim #7448 forgery shape. A rule
  green over the exact hole it advertises protection from is worse than the doc, because it
  converts "we wrote this down" into "we gated it".

  What the rule does and does not see. It reads comments through `gh issue view --json comments`,
  `--comments`, `.comments[]` or the `gh api .../issues/N/comments` REST route; it treats any
  `RESULT:` on an executable line as a verdict branch, so extracting the verdict and comparing it
  later is still branching on it; and **calling the lib does not exempt a raw read beside it** —
  a compliant probe has no direct comment read at all, because it takes its bodies from the lib.
  It is comment-stripped, so a comment explaining any of this is still writable. Its own floor is
  keyed on comment-reading probes by ANY route (direct or via the lib), so migrating a probe onto
  the lib moves it within the corpus instead of out of it.

  **Three further requirements follow from the same public-repo fact, and the lib does not cover
  any of them — they are the consuming probe's job.** All three were measured on real probes (#7448):

  1. **Anchor the verdict with `\b`.** A bare `^RESULT: PASS` matched `RESULT: PASSing on this for
     now` — prose that is not a verdict, read as one.
  2. **Never echo the matched line unredacted.** The sweeper posts a probe's stdout back as an
     issue comment, and the next run re-reads that comment as input: a probe that echoes the
     verdict it matched re-seeds it, latching the issue unclosable.
  3. **Hardcode the tracker number; never self-locate by searching issues for the probe's own
     filename.** GitHub's issue search matches COMMENT bodies as well as issue bodies and is
     relevance-ordered, so taking the first hit can point the probe at one issue while the sweeper
     closes another.

## Sharp edges for Better Stack log-content probes

- **A PASS built from "positive evidence exists AND a violation is absent" is only as wide as its NARROWEST absence query — and the test stub must filter on every dimension the real reader does.** Write the scope of each positive predicate (a LIVE heartbeat, an owner row, a stamp) and of each absence query (drift, refusal, pre-boundary rows) along shape, host, clock (`dt` vs the host's `start_ts`), machine and page completeness. Anywhere the positive side is wider is a false PASS. A stub that shape-checks `--since`/`--until` but does not filter on them leaves every time bound in the probe deletable at green. **Why:** #7761/PR #8690 — seven reproduced false-PASS paths on a green 223-assertion suite. See `knowledge-base/project/learnings/2026-09-24-my-probe-accepted-more-evidence-than-its-absence-queries-could-see.md`.
- **Discriminate on the journald SYSLOG_IDENTIFIER FIELD, never a bare payload substring, and model fixtures on the REAL escaped JSONEachRow shape.** The Vector source is shared: inngest ships GitHub-webhook logs (SYSLOG_IDENTIFIER=doppler etc.) that embed branch names, issue/PR bodies, and quoted marker strings — so any marker a human types into GitHub appears in *another* producer's rows, and a bare-substring probe self-contaminates (the tracker's own body quotes the marker → false-FAIL → sweeper re-seeds it). Isolate the field in both byte-forms: server `--grep 'SYSLOG_IDENTIFIER":"<tag>'` (LIKE, unescaped column) + client `grep -F 'SYSLOG_IDENTIFIER\":\"<tag>\"'` (escaped stdout). Fixtures must reproduce the escaped JSON `raw`, not bare syslog. **Run the live discoverability query at /work, not post-merge** — it is the only check that surfaces the escaping and the contamination before merge. See `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` (#6475).

- **A probe that reads a resource's ARMED/enabled/unpaused state has a hidden dependency on the per-member wiring that arms it — and that wiring does NOT fan out with `for_each`.** When a soak asserts a new host/tenant's Better Stack heartbeat is `up`, trace the ENABLE path (the apply arm-gate's `arm_one` calls, the `systemctl enable`, the `paused=false` flip) and confirm it was extended to the new member, exactly like the roster-coupled parity guards. A `for_each`-created monitor is born in its declared state (`paused=true` + `ignore_changes=[paused]`), so it reads `paused`, **never `ABSENT`** — a probe's "not-provisioned ⇒ ABSENT ⇒ TRANSIENT" contract silently does not hold for the born-but-not-yet-armed window, and the probe **false-FAILs a healthy target** (paused ≠ up → DARK) with the tracker never closing. Route `paused`/`pending` to TRANSIENT, distinct from ABSENT and a genuinely-down status. See `knowledge-base/project/learnings/2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md` (#6459).
- **A probe that proves a ONE-TIME event through a `--since` window stops proving it once the window slides past the event, and on a CLOSED tracker the resulting exit 1 REOPENS it.** When the tracker closes, retire its directive in the same step, or key the verdict on a recurring terminal-state row instead of the transition row. **Why:** #8296 — `inngest-luks-cutover-6894.sh` read `--since 48h --grep cutover-complete`; the only such row was 2026-09-20 15:29Z, so every sweep from 2026-09-23 (its `earliest`) would have exited 1 and falsely reopened the operator-closed #8295.

- **In a NOTIFY-ONLY probe, put the xtrace refusal first and the rc-remapping EXIT trap directly after it, with nothing in between.** `lint-shell-trace-credential-refusal.py` requires the refusal in the prologue, and the refusal can only exit 78, so no 0/1 path opens before the trap. Assert the ordering, exactly one `trap`, and no `exec`/`kill` in the probe's suite: `exec true` and `trap - EXIT` both bypass the remap. Also pin BOTH `.host` and `.host_name` on the rows: every host writes into one Logs source. **Why:** #8296 PR-2 review — the structural seat found all three open in a green 91-case suite (`inngest-luks-property-8296.sh`).

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

## The positive control must be impossible for the OLD artifact (#7220, 2026-08-04)

A soak probe proves a NEW thing is live. Its liveness control must therefore be a signal the
**pre-change** artifact cannot produce. A signal both versions emit cannot discriminate
"deployed and healthy" from "never deployed" — and on a delivery channel, "never deployed" is
usually the failure being verified.

Measured: #7220's first probe counted the handler's `starting:`/`writing:`/`wrote:`/`complete:`
journald rows. The pre-fix handler emits all four. Run against production it returned **PASS on
40 such rows while the host was dying at `daemon-reload`** — and `sweep-followthroughs.sh` closes
the issue on exit 0, so it would have closed the incident while the incident was happening.

Valid controls are things the old version structurally cannot emit: a marker string introduced by
the change, or a KEY the new writer adds unconditionally (so its ABSENCE proves the old artifact
even on a healthy run).

**And when the probe cannot resolve the ambiguity, exit TRANSIENT.** `PASS` is an auto-close;
spending it on "I could not tell" converts an unverified channel into a closed issue. Ask of every
PASS branch: *what would this report if the change were never deployed?*
