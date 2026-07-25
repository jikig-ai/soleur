# Decision Challenges — plan-review panel (Phase 0.9)

Recorded per ADR-084 (headless persist). The 8-agent panel (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer + named cpo/cmo/cto; cpo terminated on a vendor
rate-limit, its lens covered by spec-flow + cmo) produced strong cross-panel convergence. The
**mechanical** findings were applied directly to the plan deltas (see `tasks.md` §"Plan Review
Resolution"). The items below are **Taste / User-Challenge / scope** decisions that argue against
the operator's stated direction or add capability beyond the six issues — surfaced, not
auto-applied. `ship` Phase 6 renders this file into the PR body and files the `action-required`
issue the operator sees.

---

## C1 — Push-body statutory copy: zero disclaimer (Taste, user-legible)

**Panel:** cmo (×2), spec-flow P2-8, code-simplicity #1.

**Challenge.** The plan (D1) puts a short "not legal advice" caveat in the push body and the full
framing in the email. The panel argues the push should carry **no** disclaimer at all — a push is a
lock-screen pointer whose one job is to drive the tap; a legal hedge riding alongside the urgency
signal reads as the product covering itself and trains the founder to skim. cmo's reframing: the
disclaimer's home is the destination (email/detail view), and the "not legal advice" stance should
read as a confident handoff ("We track the deadline so you don't miss it; confirm specifics with
your counsel") rather than a liability shield.

**Disposition (default kept, guidance forwarded).** The exact wording is already gated behind the
**blocking `soleur:legal:clo` review at Phase 1.4** — this is precisely the reliance-vs-urgency
question the CLO owns. The panel's guidance (push = imperative + state-accurate, **zero** disclaimer
text; all not-legal-advice + clock framing in the email only) is forwarded into the CLO review
inputs as the **recommended** placement. The CLO adjudicates; the copy is not frozen here beyond
that recommendation. cmo's note that the CLO covers legal sufficiency but not brand-voice is
honored by the Phase 1.4 task explicitly asking for both a reliance verdict and a voice pass.

---

## C3 — Founder-facing surface for un-pinged statutory items (User-Challenge / new scope)

**Panel:** spec-flow P1-1, P1-2, P1-4 (all P1); cmo-adjacent.

**Challenge.** Three flow gaps the six issues do not close, all on a legal clock for a
non-technical solo founder who does not read dashboards:

1. **No `resolved` state.** `email_triage_items.status` is a one-way `new → acknowledged`
   (terminal) matrix (`102_email_triage_items.sql` §`set_email_triage_status`). The founder can
   never tell the system "I answered this." Combined with D3b's re-anchor, an item handled on day 1
   keeps generating daily overdue pings for up to ~60 days after acknowledgement.
2. **`status='new'` statutory items get exactly ONE notification, ever.** The repin scan is
   `.eq("status","acknowledged")`. A founder who never opens the inbox receives total silence on a
   running Art. 12(3) clock while every counter reads healthy.
3. **The `excluded` cliff is a telemetry counter, not a human artifact.** An item acknowledged
   >60 days ago is silently dropped and only counted in a Sentry/Better Stack payload the founder
   never sees.

**Disposition (out of this PR; consolidated follow-up filed).** #6801 explicitly scoped this PR to
closing the *acknowledged-window cliff* + making the residue observable, and permits "accept the
cliff in writing." A `resolved` state transition, scanning `new` items, and a founder-facing weekly
digest are **new capabilities**, each with its own design surface (RPC + inbox affordance; scan
predicate change; a new notification channel). Building them inside a six-issue delivery-path PR is
exactly the batching the panel warns against (C4). **One consolidated tracker issue** is filed
("statutory-notify flow gaps: resolved-state transition, new-item reminder scan, abandoned-item
founder digest") rather than three separate ones (net-issue-flow discipline). The `excluded`
residual is recorded in writing in the ADR-037 amendment per #6801's own acceptance.

---

## C4 — Split #6800 and #6813 into their own PRs (User-Challenge, against stated batch)

**Panel:** DHH P1, code-simplicity #6, cto P2.

**Challenge.** The four notification issues (#6798/#6799/#6801/#6802) genuinely interlock — D2's
band change destroys D3's `suppressed` detector, D4's rollback interacts with the marker — so they
must be reviewed and reverted as a unit. But #6800 (delete `adr:` from ~57 files) and #6813 (a
ship-skill regex, zero `apps/` code) are independent, touch different subsystems, and dilute the
load-bearing delivery-path diff. More sharply: a post-merge notification regression cannot be
`git revert`ed without also reverting the 57-file ADR corpus sweep and the ship gate.

**Disposition (batch kept, per operator instruction; reviewability mitigated).** The operator
invoked `/soleur:go #6798–#6802 and #6813` as a single batch, and one-shot is architected as one
worktree → one PR. Splitting mid-pipeline into three PRs is a workflow the operator did not request.
The batch is kept, with two mitigations that address the panel's actual concern: (a) **per-issue
commits** with the issue number in each subject, so review and `git bisect` operate at issue grain
even under a squash; (b) #6800/#6813 touch **zero** `apps/` code and are trivially skippable in
review. **The operator may reaffirm or split** — if a clean revert boundary is judged more valuable
than a single dispatch, re-run with the notification cluster alone.

---

## C5 — Comment-only migration 136 to correct the live DB's stale contract docs (surface)

**Panel:** architecture-strategist P2.

**Challenge.** `135_statutory_repin_send.sql`'s `COMMENT ON TABLE` / `COMMENT ON FUNCTION` describe
`headsup` as "a constant, one-shot" and warn of a "dead zone on days 6..3" — both made false by D2's
band. The plan freezes mig 135 (D6.5/AC29), so after merge the live database's own `\d+` / function
comments contradict the shipped code on a `single-user incident`-threshold contract. The ADR-037
"Historical citations" note does not reach anyone reading the DB directly.

**Disposition (follow-up filed; PR stays migration-free).** A comment-only migration 136
(`COMMENT ON` statements only — no DDL, no lock, a *new* file so no `content_sha` drift trip) is the
correct home for the corrected invariant at the contract's own surface. It is **deferred to a
follow-up** to preserve this PR's deliberate migration-free property (adding it would pull migration
apply + verify + Doppler-pooler operations into an otherwise code-only pipeline). Meanwhile the
corrected invariant lands in-repo via the ADR-037/ADR-134 amendments **and** a code comment at the
cron loop, so no in-repo reader is misled; only the live-DB `COMMENT` strings lag until 136 ships.
Filed on the consolidated tracker from C3.
