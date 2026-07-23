---
name: operator-digest
description: "This skill should be used when generating the operator's weekly private comprehension digest: reading merged PRs, expenses, resolved incidents, and open action-required issues, then writing a plain-language digest.md without posting."
---

# Operator Weekly Comprehension Digest

Write a calm, plain-language weekly digest that tells the non-technical operator **what their
company actually did this week** — what got built, what it cost, what broke (and whether it is
fixed), and what now needs their attention. Autonomous loops ship features, move money, and resolve
incidents faster than a solo owner can track; this digest is the antidote to that comprehension debt.

This skill runs **headless inside `claude-code-action`** in the private `jikig-ai/operator-digest`
repo, with the **public** `jikig-ai/soleur` repo checked out at `$GITHUB_WORKSPACE`. It reads five
sources, synthesizes five sections of prose, and writes `$GITHUB_WORKSPACE/digest.md`. It then
**STOPS**. A deterministic workflow post-step scrubs that file (fail-closed) and is the only thing
that posts the issue — this skill itself must never post the digest (it writes the file and STOPS).

## Register (how to write)

Write as a trusted chief of staff briefing a busy owner — calm, candid, concrete. **Every line states
a business consequence or an action the owner can take, or it is cut.** No vanity metrics, no PR
numbers, no file paths, no jargon, no hype. Prefer "We made checkout faster" over "Merged #1234
refactoring the Stripe webhook handler." Money in plain figures. Incidents in plain "what broke / is
it fixed" terms.

## Date window

The digest covers the **last 7 days**. Anchor to the checkout root and compute the window once at the start:

```bash
cd "$GITHUB_WORKSPACE"   # the filesystem sources below (§2 git log, §3 ls) are relative to the soleur checkout
SINCE="$(date -u -d '7 days ago' +%Y-%m-%d)"
```

Use `$SINCE` for every source below.

## Read-failure handling (never render a failure as a quiet week)

Each source command can FAIL — a cross-repo auth denial, a missing checkout, a transient error —
returning a non-zero exit and/or empty output. **A failed read is NOT a quiet week.** This is the
most important comprehension guardrail: the operator must never read "Nothing shipped" and believe a
busy week was quiet because a `gh` call silently 403'd.

For each section: if its source command exits **non-zero**, do NOT emit the section's "Nothing …"
fallback. Instead emit a clearly-labelled warning line for that section:

> ⚠️ Could not read \<source\> this week — a read FAILED (this is NOT a quiet week). See the run log.

Only emit the "Nothing …" fallback when the command **succeeded** and genuinely returned no rows.

## Scope guardrails (load-bearing — do not weaken)

- **L1 — path scope.** Read ONLY the five named sources below. Any other file path is out of scope.
  Do not wander the repository.
- **L2 — summaries only (the named-PII + customer-email control).** A regex cannot catch "Jane Doe".
  - Incidents: build the section from each post-mortem's **frontmatter, title, and status ONLY —
    never the post-mortem body.** The body contains customer names, raw logs, and trace detail that
    must never reach the digest. If a **title or frontmatter** itself names a person, customer, or
    company, summarize it generically ("an incident affecting a customer") rather than echoing the
    name — title/frontmatter is author-controlled, so the named-PII control applies to it too.
  - Money: emit **amounts and vendor names only.** Never echo the ledger's Notes column (it carries
    contact emails, IPs, and account detail).
  - Never copy a raw record, email address, IP, token, or log line into the digest. Summarize.
- **L3 — velocity metrics are aggregate-only (the shipping-cadence and cost-trend metrics below).**
  Report **company-aggregate** figures only — one merge-pace band, one rounded run-rate figure. One
  operator plus autonomous agents means a per-contributor or per-author breakdown is meaningless noise,
  so **never add an `author` field to the §1 `gh pr list --json` list.** Both metrics suppress to a
  neutral hedge on any read doubt, and both are stated as a business consequence — never a raw count, a
  percentage, or an up/down arrow as the signal.

## The five sections

### 1. What your company built

Source: merged pull requests in the window.

```bash
# Use the List API (NOT --search): --search routes to GitHub's Search API, which returns
# EMPTY for a cross-repo query under the in-action App-installation token (#3403 class) — it
# would silently render "Nothing shipped" every week. The List API works cross-repo (same path
# as the action-required read below). Filter by mergedAt >= $SINCE in your synthesis.
gh pr list -R jikig-ai/soleur --state merged --limit 300 \
  --json title,labels,mergedAt,number,url
```

(`number,url` are used ONLY by §5's substantiation links — never surface a PR
number in §1's prose; still no `author` field per L3.)

Keep only PRs whose `mergedAt` is on or after `$SINCE`. Rewrite each meaningful change into its
**business consequence** in plain language. Group related work. Drop pure chores/dependency bumps
unless they matter to the owner. No PR numbers, no paths.

**Shipping cadence (aggregate, comparison-framed).** Alongside the summary, judge how much your
company shipped **this week** against **recent weeks (roughly the last month)** using the same
`mergedAt` data — count only the *meaningful* merges (the same set you kept above; still drop pure
chore/dependency bumps), a merge count and never a code-size measure. Fold one qualitative band into
the prose — *clearly quieter than usual* / *about as much as a normal week* / *clearly busier than
usual* — stated as a consequence ("Your company shipped about as much as a normal week."). **When in
doubt, say "about the same."** Judge the band; never pin an exact ratio, a percentage, or an up/down
arrow, and never use the words "velocity", "throughput", or "cadence" in the output.

Degrade gracefully, and never alarm off a bad read:

- With fewer than a few weeks of history, default to "about the same" (or a plain "still getting
  started" line) — never a confident band.
- If the §1 read FAILED (the ⚠️ warning above fired), OR the PR list hit the `--limit 300` cap across
  the comparison window (a truncated read undercounts the prior weeks), OR this week reads suspiciously
  empty, do **not** emit a definite band, and **never** emit the downward "quieter" band off a doubtful
  read — render "about the same" or a one-line hedge instead. A silent undercount must never surface as
  a confident "quieter than usual".

### 2. Money & vendors

Source: changes to the expense ledger in the window.

```bash
git log --since="$SINCE" -p -- knowledge-base/operations/expenses.md
```

Report **new costs, cost changes, and vendor changes** as amounts + vendor names only. "Sentry went
from $29 to ~$40/mo." "No new vendors this week." Never reproduce the Notes column.

**Cost trend (this week's direction + a coarse run-rate).** After the raw changes above, add framing:

- **Direction (the primary, always-honest signal)** from the `git log -p` diff window: the real added
  or changed *active* costs this week ("up ~$Y a month — added Resend Pro") or "no cost changes — spend
  is holding steady." A row merely **recorded** in the diff at a non-active status (`deferred`,
  `approved-not-billing`) is **not** a cost increase — do not report it as "cost up."
- **Coarse run-rate anchor (only when the ledger reads cleanly).** `Read` the current
  `knowledge-base/operations/expenses.md` and sum the **Recurring** table's Amount,
  counting **only** rows whose `status` is `active` (and `accruing` only when it carries a real
  actual). This is a **fail-safe allowlist, not a denylist** — the rule is the catch-all, not a list
  to maintain: any status that is not `active`/`accruing`-with-actual (`deferred` and
  `approved-not-billing` are the common ones, but a future/unknown status counts too) is invisible to
  the run-rate; an unrecognized status is excluded, never summed. Normalize known non-monthly rows (a
  2-year `.ai` registration, annual-billed rows) to a monthly figure. **Suppress the anchor entirely**
  if any counted row's billing cadence is ambiguous — a mis-read annual row is a 12–24× error, the
  exact false alarm this digest exists to prevent. When clean, hard-round to one coarse aggregate
  figure: "recurring spend is roughly $X a month, mostly hosting and tooling." Emit **one aggregate
  figure only** — never a per-row Notes value; read the **Recurring** table only (the One-Time table's
  registration and credit rows must never enter the run-rate).
- If the `Read` of `expenses.md` **errors** (distinct from an empty ledger), suppress the anchor behind
  the ⚠️ warning line — a failed read is NOT "spend holding steady."
- **First run:** an empty ledger read → "first reading — no cost trend yet," mirroring the
  first-digest continuity pattern.

### 3. What broke & whether it's fixed

Source: post-mortems (incident reports) dated in the window.

```bash
ls knowledge-base/engineering/operations/post-mortems/*.md
```

For each post-mortem whose **filename date** falls in the window, read **only its frontmatter +
title** (`title`, `date`, `status`). Emit one plain line per incident: what broke, and whether
`status` says it is `resolved`/`closed` or still open. **Never read or quote the post-mortem body.**

### 4. Action needed from you

Source: open issues labelled `action-required` — but **triaged and de-polluted**, not a flat dump.
A flat list makes a 131-day chore look identical to a P0, and buries the genuine asks under
informational noise (#6836). Fetch age + labels so both become signals:

```bash
gh issue list -R jikig-ai/soleur --label action-required --state open \
  --json number,title,url,createdAt,labels --limit 100
```

**Build the action list (de-pollute).** From the result, **EXCLUDE** any issue whose `labels`
include `decision-challenge` or `content-publisher` — these are informational or structurally-dead
per-piece chores that drown the genuine asks. **Do NOT exclude the bare `content` label** — a human
(or another workflow) can attach `content` to a genuine ops emergency (e.g. a content-*pipeline*
outage), and excluding it would hide that emergency from your only comprehension surface while the
SLA cron correctly keeps it open and escalates it (it classifies bare `content` as an ops ask, never
a dead chore). **KEEP** `content-starvation` (a real standing "distribution pipeline empty" signal).
The survivors are the true "only you can do this" asks (expiring tokens, saturating disks, TLS/cert
state, infra capacity, stale CLA).

**Sort and surface age.** Sort survivors by priority (`priority/p0-critical` > `priority/p1-high` >
`priority/p2-medium` > `priority/p3-low` > none), then oldest-first. Compute each issue's **age in
days** from `createdAt`. Lead with a bold "🔴 Open longest / needs your attention" line naming the
1–3 oldest survivors with their age (e.g. "#4375 — 58 days"). Then recap each remaining survivor as
a plain "what needs you to act" line with its age and link. **Cap the action list at 8**; if more
remain, end with "+N more open — see the `action-required` label." Read-only recap — do **not**
mutate, close, or comment on any issue.

**Decisions flagged for your awareness (separate block, not the action list).** SEPARATELY, list
open issues labelled `decision-challenge` under a distinct sub-heading **"Decisions flagged for
your awareness (informational, not blocking)"** — capped at 5 with "+N more" — so they stay visible
without diluting the action list above.

### 5. What got smarter this week

Source: the self-improvements Soleur's compounding loop **completed** in the window — the promotion
PRs it merged into how your agents work. **Reuse §1's already-fetched merged-PR list — do NOT run
another `gh` call, and NEVER `--search`** (the Search API returns empty cross-repo under the
in-action App token, exactly as noted in §1; a `--search` here would silently render "nothing got
smarter" every week). From §1's list, keep only PRs whose `labels` contains `self-healing/auto`
**and** whose `mergedAt` is on or after `$SINCE`. Production shape: title
`self-healing(auto): promote cluster <hash> <date>`, label `self-healing/auto`.

Render as a **platform-level outcome, framed for the operator** — the improvement is to the shared
Soleur harness (the rules and skills every workspace runs on), not to any one workspace's data:
"Soleur got sharper this week — N improvements shipped to the shared brain your agents run on."
Add a compact `Details:` line linking each kept PR (its `url`) as substantiation. Do **not** invent
a per-item description from the cluster-hash title — it carries no human summary, and reading a PR
body to synthesize one would violate L2 (summaries only). The count plus the links is the honest
claim; the link is the drill-in path.

**Never write "your workspace got smarter"** — that phrasing implies a per-tenant benefit the loop
does not produce (improvements are global harness edits). Because §5 reuses §1's read, a §1 read
FAILURE (the ⚠️ warning) suppresses §5 too — do not render a "nothing" line off a failed read.

## Deterministic fallback (never blank)

A quiet week is itself information. **Even an all-empty week still posts.** If a source yields nothing
in the window, write the section's labelled fallback line — **never leave a section blank**:

- Section 1 → "Nothing shipped this week."
- Section 2 → "No money or vendor changes this week."
- Section 3 → "Nothing broke this week."
- Section 4 → "Nothing needs your attention this week."
- Section 5 → "Nothing was promoted to the shared harness this week."

Every section must contain at least one full sentence. A blank or byte-for-byte command-dump section
is a failure.

## Prior-week continuity

Find the most recent prior digest issue and reference it so a skipped week is visible:

```bash
# List API, NOT --search (same Search-API-empty-under-App-token reason as section 1): list this
# repo's recent issues and pick the most recent whose title starts with "Digest:". A false-empty
# from --search would break the liveness loop — every week would falsely read "first digest".
gh issue list -R jikig-ai/operator-digest --state all \
  --json number,title --limit 20
```

From that list, take the highest-numbered issue whose title begins with `Digest:` (ignore the
withheld-notice issues) and add a final line to the digest: **"Last week: #N"**. If no prior digest
issue exists, write "Last week: (this is the first digest)." A missing prior-week back-reference is
the operator-visible signal that a week was skipped.

## Output

Write the assembled digest to `$GITHUB_WORKSPACE/digest.md`:

- A short title line: `# Weekly digest: <ISO week or date range>`.
- The five `##` sections above, in order, each with prose (or its fallback line).
- The final `Last week: #N` continuity line.

Then **STOP**. Do not open, post, or create any issue — the gated workflow post-step owns publishing.
Writing `digest.md` and stopping is the entire job of this skill.
