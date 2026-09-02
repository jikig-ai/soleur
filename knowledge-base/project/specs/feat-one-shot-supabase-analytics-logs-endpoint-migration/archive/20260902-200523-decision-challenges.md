# Decision challenges — feat-one-shot-supabase-analytics-logs-endpoint-migration

Recorded 2026-08-26 by `soleur:plan` + `soleur:plan-review` (headless). Each item below
changes the **operator's stated direction** and is surfaced rather than applied silently.
The operator's direction is the default; these are challenges to it, not decisions taken.

---

## UC-1 — The brief asked for one migration; the plan ships three PRs

**Stated direction.** "Migrate off the deprecated endpoint" — implicitly one change.

**Challenge.** Measurement found the endpoint has **no committed caller**, so the migration
proper is one markdown addendum and one script. What the work actually surfaced is three
independent things with different blast radii, different reviewers and different deadlines:
a legal-corpus defect (live now, depends on nothing), the deadline work (2026-09-23), and a
recurrence poller (no deadline). Four of seven reviewers independently reached the same
split.

**Why it matters.** Bundled, a **Critical** compliance defect that is live today would wait
behind a shell-script CI cycle, and a 379 KB statutory register would be edited by
engineering-shaped reviewers — with two other branches (`feat-one-shot-7624-legal-corpus-third-country-transfer`,
`feat-web-active-active-iac-phase2.2-4-backup`) already holding open diffs against it.

**Plan's position.** Split into PR-A (legal, first), PR-B (deadline), PR-C (poller).

**If you disagree:** say so and the plan collapses back to one PR; the ACs are unchanged,
only the delivery boundary moves.

---

## UC-2 — Scope grew well beyond the endpoint swap

**Stated direction.** Six numbered scope items, all endpoint-focused.

**Challenge.** The plan now also adds: a Management-API call-site guard, a GATE G-ESCALATE
runbook promotion, `triggers:` frontmatter activating a dormant incident-routing surface,
edits to three agent-facing skill bodies, an ADR, an Art. 30 transcription, and six tracking
issues.

Most of this is a **response to measurement, not creep** — but two items are genuinely
opportunistic and are flagged as such:
- the **Art. 30 cross-reference defect** (the determination claims a register cross-reference
  that does not exist; `grep -c` returns 0) — real, Critical, and unrelated to Supabase;
- the **GATE G-ESCALATE promotion** — the procedure the helper serves exists only as a
  blockquote in a June plan, referenced by zero skills.

**Plan's position.** Both are kept, because the helper without the procedure is a tool with
no documented use, and the register defect was found by this work and should not be dropped
on the floor. The Art. 30 fix is isolated into PR-A precisely so it can be dropped or
resequenced without touching the deadline.

---

## UC-3 — The CI guard is ADVISORY, not blocking

**Stated direction.** Scope item 5: *"Add a guard so the dead endpoint cannot come back — a
repo-wide grep assertion in CI that fails on any new occurrence."*

**Challenge.** The natural home (`lint-bot-statuses`) is documented in `ci.yml:120-121` as
**advisory — a PR can merge with it red**. Making it genuinely blocking is four coupled
steps, one of which is a trap: `scripts/required-checks.txt` carries an ⚠ AUTO-FABRICATION
GUARD (#6049) under which adding a *content-scoped* gate name causes the bot-PR composite
action to post a **fabricated green** for it. Promotion therefore requires reproducing the
gate in the composite action's preflight, plus the ruleset, plus re-deriving the ADR-139
`ALLOWED_PATHS ∩ SCAN_DIRS` test.

**Plan's position.** Ship advisory, **say so plainly everywhere** (the Observability block no
longer claims a required-check route), and file promotion as a tracked issue with the four
steps enumerated. Rationale: shipping a fifth gate that *claims* teeth it lacks — three
commits after `924994b2f fix(gates): close four fail-open gates that reported success while
doing nothing` — is a worse outcome than an honest advisory gate.

**This is a genuine reduction against the brief.** If a blocking gate is required for the
deadline, the promotion work must be scoped in and the deadline re-checked.

---

## UC-4 — Two deferrals the brief did not contemplate

- **`advisors/*` callers are not migrated.** The same spec marks them deprecated and they
  have live callers — but **the spec contains no replacement path**, so migration is not
  currently possible. The tracking issue is therefore *"monitor for a successor or an
  announced removal date"*, not *"migrate"*. The waiver expiry routes to the poller, never to
  a red CI check, so it cannot break unrelated PRs on 2026-11-01.
- **The C4 `supabaseMgmtApi` element is deferred.** The gap is real and predates this plan,
  but it serves none of the plan's six properties, and
  `wg-architecture-decision-is-a-plan-deliverable` is satisfied by ADR-197 alone.

---

## UC-5 — An unclosed item the brief asked about directly

Scope item 6 asked whether a **Doppler-stored PAT used by a non-repo cron** is a second
caller. The honest answer is **unknown, not clean** — a repo grep cannot exclude it, and the
spec-diff poller diffs the *spec*, not traffic.

**Recommended before 2026-09-23:** pull Supabase's own Management API request log for
`logs.all` over the last 30 days and attribute the traffic, or record it as accepted-unknown
with the blast radius named. This is the only open item that can actually bite on the
deadline date, and no deliverable in the plan currently detects it.
