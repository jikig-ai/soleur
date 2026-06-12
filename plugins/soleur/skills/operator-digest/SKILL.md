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
repo, with the **public** `jikig-ai/soleur` repo checked out at `$GITHUB_WORKSPACE`. It reads four
sources, synthesizes four sections of prose, and writes `$GITHUB_WORKSPACE/digest.md`. It then
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

- **L1 — path scope.** Read ONLY the four named sources below. Any other file path is out of scope.
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

## The four sections

### 1. What your company built

Source: merged pull requests in the window.

```bash
gh pr list -R jikig-ai/soleur --state merged --search "merged:>=$SINCE" --limit 100 \
  --json title,labels,body
```

Rewrite each meaningful change into its **business consequence** in plain language. Group related
work. Drop pure chores/dependency bumps unless they matter to the owner. No PR numbers, no paths.

### 2. Money & vendors

Source: changes to the expense ledger in the window.

```bash
git log --since="$SINCE" -p -- knowledge-base/operations/expenses.md
```

Report **new costs, cost changes, and vendor changes** as amounts + vendor names only. "Sentry went
from $29 to ~$40/mo." "No new vendors this week." Never reproduce the Notes column.

### 3. What broke & whether it's fixed

Source: post-mortems (incident reports) dated in the window.

```bash
ls knowledge-base/engineering/operations/post-mortems/*.md
```

For each post-mortem whose **filename date** falls in the window, read **only its frontmatter +
title** (`title`, `date`, `status`). Emit one plain line per incident: what broke, and whether
`status` says it is `resolved`/`closed` or still open. **Never read or quote the post-mortem body.**

### 4. Action needed from you

Source: open issues labelled `action-required`.

```bash
gh issue list -R jikig-ai/soleur --label action-required --state open \
  --json title,url --limit 100
```

These are genuine owner-action signals (expiring tokens, saturating disks, TLS/cert state, overdue
content, stale CLA). Recap each as a plain "what needs you to act" line with its link. This is a
read-only recap — do **not** mutate, close, or comment on any issue.

## Deterministic fallback (never blank)

A quiet week is itself information. **Even an all-empty week still posts.** If a source yields nothing
in the window, write the section's labelled fallback line — **never leave a section blank**:

- Section 1 → "Nothing shipped this week."
- Section 2 → "No money or vendor changes this week."
- Section 3 → "Nothing broke this week."
- Section 4 → "Nothing needs your attention this week."

Every section must contain at least one full sentence. A blank or byte-for-byte command-dump section
is a failure.

## Prior-week continuity

Find the most recent prior digest issue and reference it so a skipped week is visible:

```bash
gh issue list -R jikig-ai/operator-digest --state all --search "Digest in:title" \
  --json number,title --limit 1
```

Add a final line to the digest: **"Last week: #N"** (the prior week's issue number). If no prior
digest exists, write "Last week: (this is the first digest)." A missing prior-week back-reference is
the operator-visible signal that a week was skipped.

## Output

Write the assembled digest to `$GITHUB_WORKSPACE/digest.md`:

- A short title line: `# Weekly digest: <ISO week or date range>`.
- The four `##` sections above, in order, each with prose (or its fallback line).
- The final `Last week: #N` continuity line.

Then **STOP**. Do not open, post, or create any issue — the gated workflow post-step owns publishing.
Writing `digest.md` and stopping is the entire job of this skill.
