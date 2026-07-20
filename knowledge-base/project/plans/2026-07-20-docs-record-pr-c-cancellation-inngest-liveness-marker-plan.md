---
title: "Record the operator's cancellation of PR C (Inngest liveness-marker discriminators)"
date: 2026-07-20
type: docs
lane: cross-domain
issues: []
refs: ["#6617", "#6748", "#6780", "#6781", "#6608", "#6348", "#6295", "#6488"]
adrs: ["ADR-100"]
brand_survival_threshold: none
revision: v1
---

# Record the cancellation of PR C

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). This branch has no
> `spec.md`; the artifacts being edited belong to a *different* feature's spec directory.

## Enhancement Summary

**Deepened on:** 2026-07-20
**Panel:** code-simplicity-reviewer (scope + AC discipline), git-history-analyzer (attribution
verification). Deliberately *not* a full fan-out — a 5-file markdown decision record does not
warrant 40 agents, and the simplicity pass explicitly flagged AC ceremony as the failure mode here.

### Key improvements

1. **Closed the Sharp-Edge-1 hole.** Every AC originally referenced a bare `<tasks.md>` placeholder
   that resolves equally well against the *wrong* spec directory — the plan named path-confusion as
   the top failure mode and then failed to check for it. AC4 (exact seven-path changed-file set) now
   catches it, and subsumes the former ADR-100 and outside-`knowledge-base/` ACs.
2. **Found a second stale claim.** `tasks.md` B4.3 ends *"the doublefire verdict remains unrecorded
   pending B4.2.b"* — falsified by the same run that closes B4.2.b. Now Phase 1.5.
3. **Corrected the merge shape.** PR A and PR B did **not** merge as two PRs; both landed in #6748
   (commit `1d4208f44`), which also carried a third piece the brief omits.
4. **Strengthened the doublefire evidence.** Run `29748606817` was dispatched from `main` *after*
   #6748 merged — against the shipped `build_request_body` fix, not the branch copy. That is exactly
   what made B4.2.b answerable, and it was not in the brief.
5. **AC block cut from 13 to 10** (9 pre-merge + 1 post-merge): dropped a redundant verbatim-text
   grep already implied by a zero-deletion diff, and merged the duplicated closing-keyword checks.

### Gate determinations

4.5 network-outage — not triggered (only self-referential hits quoting the trigger list).
4.6 user-brand impact — PASS (section present, threshold `none` valid, no sensitive-path match).
4.7 observability — skipped, pure-docs (all Files-to-Edit under `knowledge-base/`).
4.8 PAT-shaped variable — PASS (no match). 4.9 UI wireframe — skipped (no UI surface).
4.55 downtime/cutover — not triggered; this plan *cancels* a replace, it performs none.

---

## Overview

The operator has **cancelled PR C** of `feat-one-shot-6617-inngest-liveness-marker-registry-probe`.
PR C (phases C0–C6: `sdk_url` / `backend_is_prod` / `registry_count` marker discriminators, plus
`apply_target=inngest-host-replace` delivery) was previously **HELD** by the operator ruling dated
2026-07-20. It is now cancelled outright.

This change is **documentation only**. No code, workflow, script, or Terraform is touched. It
records a decision the operator has already made; the agent's job is to transcribe it accurately,
not to re-litigate it.

**The deliverable is the accuracy of the recorded rationale**, not the mechanics of the edit. The
edit itself is four small `.md` changes.

---

## Research Reconciliation — Brief vs. Repo

Every premise cited in the task brief was verified against the repo and GitHub before planning.

| Claim in the brief | Verified reality | Plan response |
|---|---|---|
| ADR-100 references `sdk_url` / `backend_is_prod` / `registry_count` as forthcoming | **False.** `grep` for all three field names in ADR-100 returns **zero**. A second sweep for forward-looking language (`will emit`, `forthcoming`, `planned`, `discriminator`, `#6617`) returns only unrelated hits (`host_name` create-time-render caveat, #6396/#6616). | **No change to ADR-100.** Per the brief: "If it does not, change nothing there." Recorded as **AC4** (the exact changed-file set must not contain ADR-100). |
| #6780 open (C5.8 root debt) | OPEN — "dedicated Inngest host has no in-place redelivery channel … (deferred C5.8)" | Reference only. Do not re-file. |
| #6781 open (C6.7 / T-4) | OPEN — "cron send-path has no idempotency guard … (deferred C6.7 / T-4)" | Reference only. Do not re-file. |
| #6608 open (was C6.6) | OPEN — "inngest-host nftables allowlist keeps 10.0.1.11 after web-2 retires" | Reference only; note it is being re-homed in a separate session. |
| #6348 draft + MERGEABLE (stranding risk) | OPEN, `MERGEABLE`, titled `[HOLD — merge at cutover flip-step 2.4]` | Record that cancelling PR C **dissolves** the stranding risk. |
| #6617 is the tracking issue | OPEN | Must **remain** open. `Ref #6617`, never a closing keyword. |
| "PR A and PR B were implemented and **merged**" | **True in substance, misleading in shape.** They did not merge as two PRs — both landed in **one** PR, **#6748**, commit `1d4208f44`, merged 2026-07-20T13:22:59Z. That PR also carried a **third** piece the brief omits: making `op=verify`'s exactly-once check capable of a verdict. #6295 is CLOSED (by #6748). | Write "PR A + PR B merged together as #6748" — never "PR A and PR B were merged", which sends a future reader hunting for two merge commits that do not exist. Note the third piece. |
| Run `29748606817` = doublefire, ZERO runs | **CONFIRMED**, with a detail that strengthens it: dispatched from **`main`** (sha `898de92e4`) *after* #6748 merged — i.e. against the shipped fix, not the branch. Run `29729509511` (registry) was dispatched pre-merge from the feature branch (sha `883a70e54`). | Record the verbatim annotation and the fact the doublefire read was taken against merged `main`. See Phase 2.2. |
| doublefire probe returned ZERO runs (run 29748606817) | **Supersedes three places in the artifacts.** `tasks.md` B4.2.b is `[ ]` "blocked until post-merge delivery"; `tasks.md` B4.3 ends "the doublefire verdict **remains unrecorded** pending B4.2.b"; `session-state.md` § Outstanding says the reading "is **not yet taken**". | **Scope addition (required for coherence).** Close out B4.2.b, reconcile B4.3, supersede the Outstanding block. See "Why B4.2.b is in scope" below. |
| PR C is HELD | The plan file (`…-registry-probe-op-plan.md`, at the `# Post-C contract` comment) asserts `PR C is HELD … promote it into the block above **when C ships**`. | **Fifth target.** Two surgical status corrections. See "Scope note: the plan file is a fifth target". |

### Why B4.2.b is in scope

The cancellation rationale rests on four measures, one of which is the doublefire reading from run
`29748606817`. But `session-state.md` currently states that reading was never taken, `tasks.md`
B4.2.b marks it blocked, and `tasks.md` B4.3 asserts the verdict "remains unrecorded."
**Appending a closing entry that cites a reading the same artifacts say does not exist produces a
self-contradicting record** — precisely the defect this change exists to remove.

This is not scope creep. It is the minimum required for the cancellation record to be internally
coherent. The brief supplies the run ID for exactly this purpose.

There is a second reason this matters. `session-state.md` carries an explicit, deliberate caveat:

> **Do not read the registry result alone as "no double-scheduler."** An empty registry means
> nothing has registered *now*; it is not proof that nothing executed earlier.

That caveat was written when the doublefire probe had not yet run. It is now **discharged** by run
`29748606817`, not ignored. The closing entry must say so explicitly — otherwise a future reader
sees a live caveat sitting above a conclusion that appears to have bypassed it.

### Scope note: the plan file is a fifth target

The brief enumerates four targets and does not include the plan file. It is added because the plan
file makes a **live status assertion the cancellation falsifies**: the `# Post-C contract` comment reads *"PR C is HELD …
promote it into the block above **when C ships**"* — an instruction to a future reader to do
something that will now never happen.

Two surgical corrections only (a status line at the `# PR C` heading, and the `# Post-C contract` comment). PR
C's design body is **not** rewritten or deleted. This corrects a false status; it does not
re-document the feature.

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no user-facing surface changes.
The failure mode is *internal and indirect*: a future agent or the operator reads `tasks.md` Phase
C0–C6 as live work and dispatches `apply_target=inngest-host-replace`, force-replacing the sole
production Inngest scheduler. That is the exact action the cancellation exists to prevent. A
weaker failure: someone reads the stale `session-state.md` Outstanding block and re-dispatches a
probe whose answer is already in hand.

**If this leaks, the user's data is exposed via:** the rationale references the dedicated host's
`INNGEST_POSTGRES_URI` and the prod project ref. **Naming the variable is fine; rendering its value
is not.** The `backend_is_prod=false` verdict was reached by evaluating the `soleur-inngest/prd`
Doppler config **without ever rendering the URI** (AC-NOBODY). The written record must preserve that
property — state the verdict, never the connection string or the project ref. Enforced by **AC7**.

**Brand-survival threshold:** `none`.
Reason: docs-only edits to internal spec artifacts under `knowledge-base/project/specs/`. No
user-facing surface, no regulated data, no code path. The diff touches no sensitive path per the
preflight Check 6 regex. The indirect risk above is a *documentation-accuracy* risk, mitigated by
the ACs, not a user-incident class.

---

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` and matched issue
bodies against both `feat-one-shot-6617-inngest-liveness-marker-registry-probe` and `ADR-100`. Zero
matches for either path.

---

## Domain Review

**Domains relevant:** none (Engineering — informational only).

No cross-domain implications. This is an infrastructure-documentation change recording an operator
decision already taken. No technical choice is made by this plan.

**Product/UX Gate:** skipped. The mechanical UI-surface override does not fire — `Files to Edit`
contains only `.md` files under `knowledge-base/`; no path matches `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx`.

**Engineering (informational, not a blocking review):** the consequence the operator is accepting
should be recorded honestly in the artifacts — after cancellation the dedicated Inngest host has
**no continuous liveness discriminators**. Its observability posture is on-demand only, via the two
standalone ops PR B shipped (`op=registry-probe`, `op=doublefire-probe`). This is what makes #6780
(no in-place redelivery channel) the live root debt rather than a filed-and-forgotten follow-up.

---

## Gate determinations (recorded so a reviewer can see the checks ran)

- **§1.4 Network-outage checklist:** not triggered. No `SSH`, `connection reset`, `kex`, `firewall`,
  `unreachable`, `timeout`, `502/503/504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` in the brief.
- **§2.7 GDPR gate:** skipped. No regulated-data surface; canonical regex does not match. Triggers
  (a)–(d) do not fire: no LLM processing of operator data, threshold is `none`, no new cron reading
  `learnings/` or `specs/`, and the PR body carries no new artifact-distribution surface.
- **§2.8 IaC routing:** **no-op.** The plan introduces no infrastructure and prescribes no
  provisioning. `Files to Edit` is `.md`-only. The subject matter is infra-adjacent, hence this
  explicit note rather than a silent skip.
- **§2.9 Observability:** skipped — pure-docs; no `Files to Edit` under `apps/*/server/`,
  `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`.
- **§2.9.1 Soak follow-through:** not triggered. No time-gated close criterion is introduced. (The
  tracking issue's closure is handled by its existing follow-through sweeper — untouched here.)
- **§2.10 ADR / C4 gate:** **skip — no architectural decision is made.** Cancelling unbuilt work
  does not change the recorded architecture: the discriminators never existed, so ADR-100 remains
  accurate as written. Phase C4.1 (an ADR-100 `## Amendment` for the delivery invariant) is itself
  cancelled and was never written, so no amendment is orphaned.
  **C4 completeness enumeration** (checked against all three of `model.c4`, `views.c4`, `spec.c4`):
  this change adds/removes no external human actor, no external system or vendor, no container or
  data store, and no actor↔surface access relationship. Nothing ships; no runtime edge changes. The
  test — "would a competent engineer reading only the existing ADRs + C4 be misled about the system
  after this plan ships?" — resolves **no**.

---

## Files to Edit

All paths are relative to the repo root. **Zero files outside `knowledge-base/` may be touched.**

| File | Change |
|---|---|
| `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/tasks.md` | Cancellation banner at `## PR C`; `— CANCELLED (2026-07-20)` on each of the seven `### Phase C0–C6` headings; close out `B4.2` / `B4.2.b` with run `29748606817` |
| `…/feat-one-shot-6617-inngest-liveness-marker-registry-probe/session-state.md` | Append a closing entry; add a supersede pointer to the `### Outstanding` block |
| `…/feat-one-shot-6617-inngest-liveness-marker-registry-probe/decision-challenges.md` | **Append** a follow-on ruling under the existing `## Operator Ruling — 2026-07-20`. Do not rewrite the original |
| `knowledge-base/project/plans/2026-07-20-feat-inngest-liveness-marker-discriminators-and-registry-probe-op-plan.md` | Two surgical status corrections — the `# PR C` heading and the stale `when C ships` text in the `# Post-C contract` comment |
| `knowledge-base/engineering/architecture/decisions/ADR-100-…md` | **NO CHANGE.** Verified: does not reference the three fields. AC7 asserts an empty diff |

**Not to be touched:** `apps/web-platform/infra/**`, `.github/workflows/**`, any `*.tf`, and the
open/closed state of any GitHub issue.

---

## The rationale to record (this is the substance — get it right)

PR C's purpose was **diagnostic**: to distinguish states of a dark dedicated Inngest host. That
question is now answered on **four independent measures**, none of which required the host replace.

| # | Measure | Reading | Source |
|---|---|---|---|
| 1 | doublefire probe | **ZERO runs** on the dedicated host | workflow run `29748606817`, 2026-07-20T13:58:56Z, dispatched from **`main`** (sha `898de92e4`) after #6748 merged — i.e. against the shipped fix |
| 2 | registry probe | `registry_empty=true`, `function_count=0` | run `29729509511` |
| 3 | `backend_is_prod` | **FALSE** — the dedicated host's `INNGEST_POSTGRES_URI` does not contain the prod project ref | evaluated against the `soleur-inngest/prd` Doppler config **without ever rendering the URI** (AC-NOBODY preserved) |
| 4 | start-blocked | `INNGEST_CUTOVER_FLIP` is **absent** from `soleur-inngest/prd`, so the flip guard refuses any prod-URI start | corroborates #6488 (2026-07-15) |

Phase C6.3's escalation branch fires on `backend_is_prod=yes` **OR** a non-empty doublefire result.
**Neither limb is met.**

### Why CANCEL rather than continue to HOLD

This is the decisive argument and must be recorded in full:

> PR C's discriminators exist to distinguish states of a **dark** host. After the cutover the
> dedicated host becomes the live scheduler and that question is no longer asked. The instrument's
> useful life is therefore **bounded by the pre-cutover window** — and it cannot be delivered inside
> that window at acceptable risk, because its delivery force-replaces the sole production Inngest
> scheduler days before the cutover it was built to instrument.
>
> **An instrument that cannot be delivered while it still matters is cancelled, not parked.**

The reason delivery costs a full host replace is #6780 — the dedicated host has no in-place
redelivery channel. That root debt is what makes "park it and deliver later" not actually
recoverable, and it is why #6780 is the carry-forward that matters most.

### The `sdk_url` note

`sdk_url` was the **one discriminator with no off-host channel**. It is read from the unit's
ExecStart argv (via `systemctl show -p ExecStart`), which reads configuration and therefore works
while the host is dark — that is what made it viable as a marker, and also what makes it the field
that dies with the cancellation.

It is **not decision-relevant while `backend_is_prod` is false**: a host that is not wired to prod
Postgres cannot corrupt prod state regardless of which SDK URL it would poll.

### Carry-forward items — reference, do NOT re-file

All four are already filed and verified OPEN. **No new issues may be created by this change.**

- **#6780** — C5.8 root debt: the dedicated host has no in-place redelivery channel.
- **#6781** — C6.7 / T-4: the cron send-path has no idempotency guard.
- **#6608** — was C6.6 ("rides along, closed post-replace"); being re-homed in a separate session.
- **#6348** — the draft `INNGEST_BASE_URL` repoint PR. The operator ruling recorded a standing risk
  that if it merged before PR C was delivered, PR C would be stranded merged-but-undelivered.
  **Cancelling PR C dissolves that risk** — record this explicitly.

### Single-source discipline

Do **not** triplicate the rationale. Each artifact has one job:

- `decision-challenges.md` → the **ruling** (authoritative; appended to the existing ruling section).
- `session-state.md` → the **closing entry** (session narrative: what was measured, what was
  decided, what carries forward, what caveat is discharged).
- `tasks.md` → a **short banner** (decision, date, who, pointer). Not the full argument.
- plan file → a **status line**. Not the full argument.

---

## Implementation Phases

### Phase 0 — Preconditions (measure; do not bake literals)

- [ ] 0.1 Confirm CWD is the worktree and branch is `feat-one-shot-record-pr-c-cancellation-6617`
      (**not** `main`).
- [ ] 0.2 **Read all three target files before editing** (`hr-always-read-a-file-before-editing-it`).
- [ ] 0.3 The **pre-edit checkbox count** under `## PR C` in `tasks.md` is **46**, measured at plan
      time with `sed -n '/^## PR C/,$p' `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/tasks.md` | grep -cE '^\s*- \[[ x~]\]'`.
      Re-measure before editing and confirm it is still 46; if it differs, the file changed under
      the plan — stop and reconcile. AC3 asserts the post-edit count is unchanged.
- [ ] 0.4 Re-confirm #6617 is OPEN and must stay OPEN.
- [ ] 0.5 Re-confirm ADR-100 contains none of the three field names (AC7's premise).

### Phase 1 — `tasks.md`

- [ ] 1.1 Insert a cancellation banner **immediately after** the `## PR C` heading. It must contain
      the literal tokens `CANCELLED`, `2026-07-20`, and `operator`, state that the decision was the
      operator's, and point to `decision-challenges.md` for the ruling. Keep it short.
      **The banner must contain no checkbox** (`- [ ]`) — AC3 counts checkboxes from `## PR C` to
      EOF, so a checkbox in the banner fails that AC spuriously.
- [ ] 1.2 Append `— CANCELLED (2026-07-20)` to **each of the seven** headings
      `### Phase C0:` … `### Phase C6:`.
      *Rationale: a reader who scrolls directly to `### Phase C3` must see it is cancelled without
      scrolling up. The banner alone does not survive out-of-context reading.*
- [ ] 1.3 **Do not delete or reword any phase body.** The bodies are the record of what was designed.
- [ ] 1.4 Close out the doublefire reading: flip `B4.2` and `B4.2.b` to `[x]` and record that
      `op=doublefire-probe` returned **ZERO runs** on the dedicated host in run `29748606817`.
      *Note: this file uses `[~]` for "partial" (see `B4.2`). Do not reuse `[~]` to mean cancelled —
      that is why C0–C6 are marked at the heading, not the checkbox.*
- [ ] 1.5 **Reconcile `B4.3` in the same edit.** Its body currently ends *"The doublefire verdict
      remains unrecorded pending B4.2.b."* — which B4.2.b's close-out falsifies. Append the
      resolution: the verdict is now recorded, backed by run `29748606817`, and B4.3's discipline
      (never record a verdict ahead of the read) was **honoured** — the read came first.
      *This is the same defect class the whole change exists to remove: leaving a superseded claim
      standing three lines below its own correction.*

### Phase 2 — `session-state.md`

- [ ] 2.1 Append a closing entry recording: the cancellation, the operator as its author, the date,
      the four measures table, the CANCEL-vs-HOLD argument, the `sdk_url` note, and the four
      carry-forwards.
- [ ] 2.2 State explicitly that the **registry-alone caveat is discharged** by run `29748606817` —
      the doublefire probe (the instrument that proves the harm) has now run and returned empty.
      Record the **verbatim** annotation rather than a paraphrase:
      ```
      doublefire-probe: 0 run(s) in window; bucketing by (functionID, floor(startedAt / 3600s))
      doublefire-probe: ZERO runs on the dedicated host — its scheduler has executed nothing in the window.
      ```
      Note that this read was taken from **`main`** (sha `898de92e4`) after #6748 merged, so it
      exercised the shipped `build_request_body` fix — not the branch copy. This is what makes it a
      valid answer to B4.2.b, whose blocker was precisely that the host ran the unfixed deployed copy.
- [ ] 2.2b Refer to the merged work as **"PR A + PR B, merged together as #6748"** (commit
      `1d4208f44`, 2026-07-20). Do **not** write "PR A and PR B were merged" — they were one PR, and
      the plural sends a future reader hunting for a second merge commit that does not exist. #6748
      also carried a third piece: making `op=verify`'s exactly-once check capable of a verdict.
- [ ] 2.3 Add a one-line supersede pointer under the `### Outstanding` heading directing the reader
      to the closing entry. **Insert only — delete nothing.**
- [ ] 2.4 Record that cancelling PR C dissolves the #6348 stranding risk.
- [ ] 2.5 Use the `apply_target=inngest-host-replace` form (matches `tasks.md` C5.3). The existing
      `session-state.md:50` says `apply_target=inngest-host`; that is a pre-existing inconsistency —
      **do not rewrite it**, just do not propagate it.

### Phase 3 — `decision-challenges.md`

- [ ] 3.1 **Append** a follow-on ruling under the existing `## Operator Ruling — 2026-07-20`.
- [ ] 3.2 **Do not rewrite, reword, or reorder the original ruling.** The diff for this file must be
      pure-append (AC4: zero deleted lines).
- [ ] 3.3 State the reversal plainly: the original ruling said *"PR C: HELD, not cancelled."* The
      follow-on ruling supersedes that to **CANCELLED**, and says why the earlier condition (read
      PR B's probe output first) has now been satisfied.
- [ ] 3.4 Record that the standing #6348 risk carried by the original ruling is **dissolved**.

### Phase 4 — plan file (the fifth target)

- [ ] 4.1 Add a one-line status note under `# PR C — marker discriminators + delivery` (`:331`)
      marking it CANCELLED (2026-07-20, operator) with a pointer to `decision-challenges.md`.
- [ ] 4.2 Correct the stale `# Post-C contract` comment — it is a **three-line** YAML comment, not one
      line (verified; the file is 803 lines):
      ```
      # Post-C contract (PR C is HELD per the 2026-07-20 operator ruling — retained
      # verbatim so C does not have to re-derive it; promote it into the block above
      # when C ships and the marker fields actually emit).
      ```
      Rewrite so it no longer implies PR C will ship. The `discoverability_test_after_c` block below
      it may stay as a record of the contract that was designed — but it must no longer read as a
      pending instruction.
- [ ] 4.3 Do not otherwise modify PR C's design body in the plan.

### Phase 5 — Verification

- [ ] 5.1 Run every AC below.
- [ ] 5.2 `git diff --name-only` and confirm the changed set is `.md`-only under `knowledge-base/`.
- [ ] 5.3 Confirm no GitHub issue state was modified and no new issue was filed.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `tasks.md`: the banner region strictly *between* `## PR C` and `### Phase C0` contains
  `CANCELLED`, `2026-07-20`, and `operator`. Use the **flag-based** awk form, which excludes both
  the start and end lines:
  ```sh
  awk '/^## PR C/{f=1;next} /^### Phase C0/{f=0} f' `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/tasks.md` > /tmp/prc-banner.txt
  grep -c 'CANCELLED' /tmp/prc-banner.txt   # >= 1
  grep -c '2026-07-20' /tmp/prc-banner.txt  # >= 1
  grep -ci 'operator' /tmp/prc-banner.txt   # >= 1
  ```
  **Do not** use `sed -n '/^## PR C/,/^### Phase C0/p'`: that range *includes* the `### Phase C0`
  line, which AC2 requires to contain `CANCELLED` and `2026-07-20` — so a `grep -c` over it returns
  ≥ 1 **even when the banner is entirely missing**. `operator` is the one token that appears only in
  the banner, which is why it is asserted separately.
- **AC2** — All seven phase headings carry the marker.
  `grep -cE '^### Phase C[0-6]:.*CANCELLED' `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/tasks.md`` **== 7**.
- **AC3** — No PR C phase body was deleted. The checkbox count under `## PR C` still equals the
  Phase-0.3 baseline:
  `sed -n '/^## PR C/,$p' `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/tasks.md` | grep -cE '^\s*- \[[ x~]\]'` **== 46**.
- **AC4** — **The changed-file set is exactly these seven paths.** `git diff --name-only main...HEAD | sort`
  must equal, verbatim:
  ```
  knowledge-base/project/plans/2026-07-20-docs-record-pr-c-cancellation-inngest-liveness-marker-plan.md
  knowledge-base/project/plans/2026-07-20-feat-inngest-liveness-marker-discriminators-and-registry-probe-op-plan.md
  knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/decision-challenges.md
  knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/session-state.md
  knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/tasks.md
  knowledge-base/project/specs/feat-one-shot-record-pr-c-cancellation-6617/session-state.md
  knowledge-base/project/specs/feat-one-shot-record-pr-c-cancellation-6617/tasks.md
  ```

  **SUPERSEDED at /compound (2026-07-21) — replaced by AC4' below.** The exact-file-census form
  was run twice and drifted twice: first at /work (the orchestrator writes a `session-state.md`
  the planning subagent cannot know about), then at /compound (a learning file + a routed
  `review/SKILL.md` bullet). Both additions were legitimate. A census assertion is structurally
  incompatible with a pipeline whose later phases add files by design, so it fails for reasons
  unrelated to the property it guards — and an AC that must be edited every phase teaches the
  reader to edit it rather than to heed it. The historical amendment note is retained below.

  **Amended at /work (2026-07-20), from six paths to seven.** The plan was authored by the
  planning subagent, which writes only `tasks.md` into this branch's own spec dir; the parent
  one-shot pipeline additionally writes `session-state.md` there (one-shot Steps 1–2, "write the
  parsed content to `knowledge-base/project/specs/<exact-branch-name>/session-state.md`"). That
  file therefore could not exist when the plan was written. Recorded as an amendment rather than
  silently relaxing the assertion, because AC4 is the load-bearing path-confusion check and a
  weakened AC4 is worse than a wrong one.
  Two derived assertions, both of which must hold:
  - `git diff --name-only main...HEAD | grep -c 'ADR-100'` **== 0** (ADR-100 untouched).
  - `git diff --name-only main...HEAD | grep -cvE '^knowledge-base/'` **== 0** (nothing outside
    `knowledge-base/`).

- **AC4' (replaces AC4)** — **The cancellation content landed in the RIGHT spec directory.**
  This tests the failure mode directly instead of proxying it through a file census:
  ```sh
  # 0 — no cancellation banner may land in THIS branch's own spec dir (the confusion case)
  git diff --name-only origin/main...HEAD \
    | grep 'feat-one-shot-record-pr-c-cancellation-6617/' \
    | xargs -r grep -l 'CANCELLED — 2026-07-20, by operator decision' | wc -l   # == 0
  # >=1 — the banner IS present in the target spec dir
  git diff --name-only origin/main...HEAD \
    | grep 'feat-one-shot-6617-inngest-liveness-marker-registry-probe/' \
    | xargs -r grep -l 'CANCELLED — 2026-07-20, by operator decision' | wc -l   # >= 1
  # ADR-100 untouched; nothing outside the two permitted roots
  git diff --name-only origin/main...HEAD | grep -c 'ADR-100'                    # == 0
  git diff --name-only origin/main...HEAD \
    | grep -cvE '^(knowledge-base/|plugins/soleur/skills/review/SKILL\.md$)'      # == 0
  ```
  **This is stronger than the census it replaces, not weaker.** The census could pass while the
  banner sat in the wrong directory (it only counted paths, never content); AC4' asserts the
  banner's presence in the target dir AND its absence from the decoy dir, which is the actual
  Sharp-Edge-1 failure. It is also stable under legitimate later-phase additions. The `-r` on
  `xargs` is load-bearing: without it an empty path list makes `grep` read stdin and hang, and a
  hung check is not a passing one.

  **This is the load-bearing AC.** Note that exactly two of the seven paths carry the
  `feat-one-shot-record-pr-c-cancellation-6617/` segment (this branch's own tasks.md and
  session-state.md); the three spec files being *edited* all carry
  `feat-one-shot-6617-inngest-liveness-marker-registry-probe/`.
  **That asymmetry is the check.** If the edits land in the wrong spec directory, this AC fails and
  every other AC still passes green (Sharp Edge 1).
- **AC5** — **Pure-append on the two narrative files.** `git diff --numstat` reports **0 deletions**
  for both `decision-challenges.md` and `session-state.md`. Additionally `session-state.md` cites
  run `29748606817` and its `### Outstanding` block carries a supersede pointer.
  *(A zero-deletion diff already proves the original ruling survives verbatim — no separate grep for
  its text is needed, and hardcoding that 46-character literal would break on any reflow.)*
- **AC6** — `tasks.md`: `B4.2.b` is `[x]`, the file contains `29748606817`, and `B4.3` no longer
  asserts the doublefire verdict is unrecorded:
  `grep -c 'remains unrecorded pending B4.2.b' `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/tasks.md`` **== 0**.
- **AC7** — **AC-NOBODY preserved.** No rendered connection string **and no bare project ref**
  anywhere in the diff. *(Naming the variable `INNGEST_POSTGRES_URI` is permitted; rendering its
  value is not.)* Three limbs, all **== 0**:
  ```sh
  # Patterns are built by CONCATENATION so this file does not match its own checks.
  # (a) DSN / vendor-host forms
  PAT_A='postgres''(ql)?://|\.''supabase''\.co'
  git diff origin/main...HEAD | grep -ciE "$PAT_A"
  # (b) credential shape: userinfo, colon, secret, at-sign, host
  #     (a bare scheme-separator check over-matches credential-less endpoint URLs)
  PAT_B='[A-Za-z0-9._%+-]+'':''[^[:space:]"@/]+''@''[A-Za-z0-9.-]+'
  git diff origin/main...HEAD | grep -cE "$PAT_B"
  # (c) the BARE prod ref, sourced from the flip-guard so the literal never enters this doc
  MARKER=$(grep -oE 'INNGEST_PROD_URI_MARKER:-[a-z]+' \
    apps/web-platform/infra/inngest-server-flip-guard.sh | head -1 | cut -d- -f2- | tr -d ':')
  test -n "$MARKER" || { echo "AC7(c) EXTRACTION FAILED — treat as RED, not clean"; exit 1; }
  git diff origin/main...HEAD | grep -cF "$MARKER"
  ```
  **Self-match note (caught at /compound, 2026-07-21).** AC7 limb (a) went from 0 to 1 purely
  because this explanatory prose originally spelled out the vendor-host suffix while explaining
  why limb (a) is insufficient — **the document describing the rule tripped the rule**. It was not
  a leak. The fix is to reword the prose so the forbidden literal appears only inside the pattern
  itself, NOT to add a path exemption: an exemption would blind the check on the one file most
  likely to quote a real credential shape while discussing credentials. Any AC of this kind should
  be run once on its own PR before being trusted — a self-matching pattern reads as a finding.

  **The `test -n` guard is not boilerplate — the first draft of limb (c) was vacuous.** It used
  `sed -n 's/.*PROD_MARKER:-\([a-z]*\)}.*/\1/p'`, whose unescaped `}` after `*` made the
  expression fail to match; the extraction returned the empty string, and `grep -cF ""` matches
  every line. Caught only by printing the extracted length before trusting the result. Assert the
  extraction landed; treat an empty marker as RED, never as clean.

  **Limb (c) is the one that matters and the one the original AC7 missed.** `PROD_MARKER` is
  matched in `inngest-server-flip-guard.sh` as a **bare substring** — no scheme, no
  vendor-host suffix (spelled out in limb (a)'s pattern, deliberately not repeated in this prose —
  see the self-match note below) — so the ref can be disclosed in a form that passes limb (a). The
  AC would then report clean on precisely the disclosure its own prose forbids: the assertion's
  scope was narrower than the property claimed (the repo's prefix-scoped-purity-test defect
  class). The `test -n "$MARKER"` guard is load-bearing — a failed `sed` yields an empty pattern,
  and `grep -cF ""` matches every line, so an unguarded limb (c) fails loudly rather than
  vacuously passing. Sourcing the marker from the script rather than hardcoding it is also
  required: writing the literal into this plan would itself violate AC-NOBODY.
  Note all three limbs use `origin/main...HEAD`, not `main...HEAD` — a stale local `main` silently
  narrows the compared range, and this check's green result is load-bearing for a security
  property.
  *(Found by security-sentinel at review; fixed inline per the cost-of-filing gate.)*
- **AC8** — **No closing keyword bound to #6617** in commit messages **or** the PR body:
  `git log main..HEAD --format=%B | grep -ciE '(clos(e|es|ed)|fix(e[sd])?|resolv(e|es|ed))[[:space:]]+#6617'`
  **== 0**, and the same regex over the PR body **== 0** before marking ready. `Ref #6617` **is**
  present, so the linkage exists without closing. The PR body must also not quote `Closes #6295`
  verbatim from `tasks.md` — that would fire a closing keyword at an already-closed issue.
- **AC9** — All four carry-forwards are cited by number in the closing entry: `grep -c` for each of
  `#6780`, `#6781`, `#6608`, `#6348` ≥ 1.

### Post-merge (automated — not an operator step)

- **AC10** — `gh issue view 6617 --json state` reports **OPEN**. The tracking issue's
  follow-through sweeper owns its closure; this change must not have altered it.
  *Automation: `gh` CLI via Bash.*

---

## Sharp Edges

1. **Two spec directories differ only by suffix, and both end in `6617`.** This is the single most
   likely way to get this change wrong.
   - **EDIT TARGET:** `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/`
   - **THIS BRANCH's own spec dir:** `knowledge-base/project/specs/feat-one-shot-record-pr-c-cancellation-6617/` (does not exist yet; `/work` will create it)

   Writing the cancellation banner into this branch's own `tasks.md` would silently produce a
   correct-looking diff that records nothing. Re-read the full path before every edit.
   **AC4 is the only AC that catches this** — every AC naming a bare `tasks.md` passes green
   against the wrong directory. Do not weaken AC4 into a per-file check.

2. **`[~]` already means "partial" in the target `tasks.md`** (see `B4.2`). Do not overload it to
   mean "cancelled." That is why C0–C6 are marked at the **heading**, not the checkbox.

3. **A PreToolUse IaC hook blocked the previous plan write on this feature.** Per
   `session-state.md`, an acceptance criterion quoted a forbidden literal (a Doppler secret-write
   command) *in order to prohibit it*, and the hook is blind to intent. When writing the artifacts,
   describe prohibited operations rather than quoting their literal command form.

4. **`git diff --numstat` deletion counts are the load-bearing check for "append-only."** A reviewer
   eyeballing the rendered markdown cannot tell an append from a rewrite-with-similar-text. AC4 and
   AC5 must be run as commands, not judged by reading.

5. **Do not re-file the carry-forwards, and do not file anything new.** All four issues already
   exist (#6780, #6781, #6608, #6348). The Step-6 deferral-tracking checklist would ordinarily
   require filing an issue per deferred item; here that would create four duplicates. **This change
   files zero GitHub issues and alters zero issue states.** AC9 asserts citation, not creation.

6. **Attribute the decision to the operator, never to the agent.** The agent transcribes; it does not
   decide. Phrasing such as "we determined" or "the analysis concluded" is wrong in all four files.

7. **The closing entry must not silently step over the registry-alone caveat.** `session-state.md`
   explicitly warns that an empty registry is not proof of "no double-scheduler." The entry must
   state that run `29748606817` **discharges** that caveat — not omit it and hope the reader does
   not notice the tension.
