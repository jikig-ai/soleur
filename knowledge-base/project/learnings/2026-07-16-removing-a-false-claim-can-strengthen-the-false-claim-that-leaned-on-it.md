---
title: "Removing a false claim can strengthen the false claim that leaned on it"
date: 2026-07-16
category: security-issues
module: legal-docs
tags: [legal-docs, gdpr, art-32, prose-claims, sweep, anchoring, review]
issues: [6538, 6463, 6588, 6584, 6585]
pr: 6568
---

# Removing a false claim can strengthen the false claim that leaned on it

## Problem

PR A of #6538 restated the hosting locative in the public legal docs from "Helsinki,
Finland only" to EU-level. Same sentences also named a **dedicated per-workspace
git-data host**, which I verified against the live Hetzner API had **never been
provisioned** (5 servers, no `soleur-git-data`, no git-data volume). So I removed it —
correctly, on the facts.

That sentence continues:

> …a second web host (web-2) plus **a dedicated per-workspace git-data host**. Stored
> workspace git data sits on a **LUKS-encrypted (encryption-at-rest)** volume; traffic
> between the hosts is **encrypted in transit with TLS**; … re-verified when a session
> is served across hosts.

Removing the host left the LUKS clause **dangling**. And the LUKS clause is itself false:

| Evidence | Result |
|---|---|
| `hcloud_volume.workspaces` — the volume holding user worktrees | `format = "ext4"` — **no encryption** |
| the web host's `cloud-init.yml` | **0** × `cryptsetup` / `luksFormat` / `luksOpen` |
| `git-data-luks.tf` — the LUKS volume that *does* exist | attached to `hcloud_server.git_data`, never born |

So user source code is stored **unencrypted at rest** while the published privacy policy
says it is LUKS-encrypted.

## Key insight

**A false claim's blast radius changes when you delete its subject.**

Bound to the named phantom host, the LUKS clause read as a claim *about that host* — false,
but scoped to a thing a careful reader could see didn't exist. Unbound, it reads as a claim
about **live workspace storage**. Same bytes, strictly worse claim. A correction made a
false Article 32 security claim more dangerous than leaving it alone.

The generalizable rule:

> When deleting an entity from an enumeration in prose, grep the **same sentence, cell, or
> bullet** for clauses whose *subject* was that entity. A claim family is removed **whole
> or not at all** — never just its head.

Litmus: after removing X from "…A, B, and X. X does P, Q, R." — ask *what does "does P" now
attach to?* If the answer changed, you rewrote a claim you didn't intend to touch.

This is the prose sibling of `cq-ref-removal-sweep-cleanup-closures` (removing a ref leaves
closures reading a dangling binding) — same shape, different substrate.

## Solution

PR A narrowed to **purely the locative fix**. The whole #5274-Phase-3 claim family
(git-data host + LUKS + cross-host clauses) is left exactly as on `main` — neither
corrected nor exacerbated. Verified mechanically, not by eye: LUKS-clause counts are
byte-identical to `main` across all 6 files, and no clause is left without its antecedent.

Only **1 of the 4** clauses can ever be made true — verified live rather than assumed:

- *"a dedicated per-workspace git-data host"* — **unachievable**: `cax11` orderable in
  **0 of 3** EU DCs (Hetzner API 2026-07-16: `nbg1-dc3`, `hel1-dc2`, `fsn1-dc14` all
  `false`). Blocked on #6570.
- *"traffic between the hosts … TLS"* / *"session served across hosts"* — **unachievable**:
  no load balancer exists, `app.soleur.ai` is a hard-pinned singleton to web-1, and PR B
  destroys web-2.
- *"LUKS-encrypted volume"* — **achievable**, by encrypting `hcloud_volume.workspaces` (a
  *different* substrate than the sentence was written about). → **#6588** (P1), CTO-routed:
  `hcloud_volume.format` is ForceNew, so a naive apply destroys live user code.

Operator decided to keep the claim published and make it true by encrypting, rather than
retract or temporally qualify. Recorded with evidence + a 2026-07-23 re-raise trigger at
`knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` DC-1.

## The design rule that should have prevented the original claim

`architecture-strategist` articulated it better than the plan did:

> **Disclosure specificity should equal enforcement specificity.**

`variables.tf` validation-pins every host to `contains(["nbg1","fsn1","hel1"], …)` — an
**EU set**. *No invariant pins any host to `hel1`.* So "Helsinki" was a public claim with
**nothing behind it**; it was always going to drift, and #6393 merely collected. EU-level
is exactly the enforced invariant — which is why it survives PR B, #6459 and #6570 without
a further edit. Under-specified enforcement is the tell that a disclosure will rot.

## Prevention

- **Claim-family sweep.** Deleting an entity from prose → grep the same sentence/cell for
  its dependent clauses. Route: `work/SKILL.md`.
- **Sweep the semantic quantity, not its formatting.** See Session Errors #2.
- **Threshold follows the surface, not the file type.** A "docs-only" PR that edits the
  **public privacy policy** has a user surface. Keeping `single-user incident` is what
  fired `user-impact-reviewer`, which found this P1.

## Session Errors

1. **Removed a false claim's antecedent, leaving a dependent false claim dangling and
   stronger.** The finding above. 4 review agents converged (`user-impact-reviewer`,
   `security-sentinel`, `code-quality-analyst`, `pattern-recognition-specialist`); my own
   edit cycle never saw it. **Recovery:** unwound; PR A narrowed to the locative fix.
   **Prevention:** claim-family sweep rule (routed to `work/SKILL.md`).

2. **Stale-figure sweep anchored on exact decimals missed the same figures in rounded
   prose.** I swept `176\.11|595\.82|92\.81|75\.68`, reported clean. §6 "Pricing Gate #4
   Status" carried `~$176/mo`, `4 paying users`, `~76%`, `~93%` — the one section written
   for **external citation**, asserting the exact "93%" framing §5 retires one screen
   above. **Recovery:** corrected to `~$200` / `5` / `~75%` / `~92%`. **Prevention:** sweep
   on the *semantic quantity* (every figure derived from the subtotal), not on its
   formatted representation — enumerate derived figures, then grep each. Same root as
   `cq-assert-anchor-not-bare-token` / "narrowing is not anchoring". Routed to
   `work/SKILL.md`.

3. **Offered the operator an option a CLO-signed rubric forbids.** I asked "repin SHA, no
   TC_VERSION bump?" before reading `knowledge-base/legal/tc-version-bump-policy.md`, which
   makes Tier 3 (no bump) *typos/whitespace/markdown only*, Tier 2 clarifying **BUMP
   REQUIRED**, with an explicit tie-break: *"if unsure, treat as clarifying — over-bumping
   is recoverable, under-bumping leaks demonstrability gaps."* No-bump was never available
   for a non-cosmetic T&C edit. **Recovery:** re-put the question; the operator's real
   intent (don't force re-acceptance) was served by **not editing the T&C at all** — its
   claim is true as written, since web-2 never served the platform. **Prevention:** before
   offering options on a governed surface, read the governing rubric — an option the rubric
   forbids is not a choice, it's a trap. Routed to `work/SKILL.md`.

4. **Mirror-sync script silently dropped the `Previous:` label** in all 3 mirrors,
   orphaning the July 5 changelog entry on soleur.ai. My `new_prefix` was built as
   `canon[i:j] + "July 5, 2026 …"` where `j` indexed *at* `"Previous: "`, excluding it.
   **Recovery:** restored; asserted count==1 per file. **Prevention:** when a script
   reconstructs a string by slicing around an anchor, assert the output contains the anchor.
   One-off (script deleted).

5. **Two changelog cross-references pointed at the wrong sections** — privacy "Section 6" is
   *Legal Basis for Processing* (transfers are §10); DPD "Section 2.2" is *User's
   Responsibilities* (the processor table is §4.2). `code-quality-analyst` marked these PASS;
   `architecture-strategist` caught them. **Recovery:** corrected against actual headings.
   **Prevention:** verify a cross-ref against the target file's real heading list, never from
   memory of the doc's shape. Also: when two agents disagree, resolve by reading — don't
   count votes.

6. **My own review note claimed the sweep found "two more" untabled rows.** It found two of
   **three** — `Cloudflare R2 (cla-evidence)` was missed because it is worth **$0.00** and
   the sweep was implicitly hunting dollars. **Recovery:** tabled in the not-counted list,
   whose scope had to widen from "free-tier or test-mode" to admit metered-sub-cent; note
   corrected to say three and to say the sweep missed one. **Prevention:** a completeness
   claim about a sweep is itself a claim — re-derive it before writing it down.

7. **Bash tool CWD persists across calls.** A `cd docs/legal` in one call made later
   relative-path greps fail with *"No such file or directory"*. **Recovery:** absolute paths.
   **Prevention:** already documented in `work/SKILL.md` ("prefer absolute paths"); the
   failure was loud here but would be **silent** for a grep that merely returns 0 hits —
   which is exactly how a sweep false-passes.

8. **`npx @11ty/eleventy` resolved a cached wrong version**, then failed again on CWD (the
   Eleventy config lives at the repo root, not in `plugins/soleur/docs/`). **Recovery:** used
   the pinned `node_modules/.bin/eleventy` from the repo root. **Prevention:** the pinned-
   binary rule already covers `npx vitest` / `npx tsc`; Eleventy is the same class. Note the
   first failure looked like *my markdown broke the build* — it didn't.

9. **Background task-completion notification reporting "exit code 0" is the *trailing*
   command's exit, not the runner's.** Hit twice (`bash test-all.sh > log 2>&1; echo
   "EXIT=$?"; tail`). Caught both times only because the rule is documented. **Recovery:**
   read the captured `EXIT=` and the runner's own `178/178 suites passed` line.
   **Prevention:** already documented; the recurrence suggests the safer shape is to drop the
   redirect entirely so the bg output file captures the runner directly.

10. **Plan's AC-A1 expected `fsn1` count == 4; the as-written register has 6.** The annex row
    and PA-8(e) were added after the AC was drafted. **Recovery:** corrected the AC to 6 with
    the command published beside it. **Prevention:** the plan's own rule ("derive counts from
    the as-written artifact") — reproduced by the plan itself. One-off.

11. **Route-to-definition edit aimed at the main checkout instead of the worktree** — the
    `guardrails:block-main-repo-write` hook denied it (*"Writing to main repo checkout while
    worktrees exist"*). This is the exact failure `compound/SKILL.md` warns about ("always
    use worktree-absolute paths… verify with `git status --short`"), and the hook caught it
    where prose had not. **Recovery:** re-applied at the worktree path; verified `M` in
    `git status`. **Prevention:** already hook-enforced — working as designed. Worth noting
    the prose rule alone did **not** prevent it; the hook did, which is the project's
    standing evidence for hooks-over-prose.

12. **AGENTS.md always-loaded payload is 22,973 bytes — over the 22,000 CRITICAL
    threshold** (index 6,072 + core 16,901; 202 rules, longest 600 B). Pre-existing, not
    introduced here: this session's three rules were routed to `work/SKILL.md` per the
    placement gate (domain-scoped — they fire only inside a `/work` edit cycle, never on an
    arbitrary turn). **Prevention:** the shrink is a `wg-*`-demotion exercise
    (`AGENTS.core.md` → `AGENTS.rest.md`, never `hr-*`), gated on loader-class fit.
    **Already tracked — did NOT file a duplicate:** #6138 (same finding, 23068 B) and #6461
    (the compound rubric's own threshold is stale: it prints `critical > 22000` while the
    authoritative `lint-agents-rule-budget.py` REJECTs at **23000**, so 22,973 is a warning,
    not a block). Net-flow discipline: re-filing a tracked finding is backlog growth, not
    diligence.

## Related

- `2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md` — publish the command next to the number
- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md` — same root as Session Error #2
- `2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration.md` — the direct ancestor: legal prose hallucinated against the implementing artifact. This learning is its **removal-side** twin.
- `2026-05-25-pr1-of-sequenced-legal-disclosures-needs-temporal-qualifiers.md` — the Art. 13(3) precedent (PR #4455) the operator declined here
