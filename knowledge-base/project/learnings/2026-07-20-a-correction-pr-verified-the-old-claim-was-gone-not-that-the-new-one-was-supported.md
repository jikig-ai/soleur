---
title: "A correction PR verified the old claim was gone, not that the new one was supported"
date: 2026-07-20
category: best-practices
module: marketing-copy, review, acceptance-criteria
issue: 6768
pr_branch: feat-one-shot-6768-polsia-figure-unverified
tags:
  - acceptance-criteria
  - review
  - aeo
  - json-ld
  - claim-verification
---

# A correction PR verified the old claim was gone, not that the new one was supported

## Problem

Two published, indexed comparison pages asserted a competitor's vendor-reported ARR and customer count as settled fact, in rendered copy **and** inside a `FAQPage` JSON-LD `acceptedAnswer` — the string answer engines lift verbatim with no page context. The fix was to lead with the verifiable funding round and attribute all revenue/customer figures.

The plan was thorough: 11 acceptance criteria, a 7-agent review panel, a deepen pass that falsified three of its own v1 claims. Every AC passed. The full suite ran 204/204. The site gates exited 0.

Multi-agent review then found **four defects in the replacement copy**, three of which reproduced the exact defect class the PR existed to fix.

## Root cause

Every sweep AC was an **absence** assertion:

```bash
grep -cE '1\.5M|2,000\+' _site/blog/*/index.html   # → 0
```

Absence assertions verify that the old claim is gone. **Nothing asserted presence-with-provenance** — that each claim the diff *added* traced to a named line in the cited source of truth. That gap is where all four defects lived.

### The four defects

**1. Provenance inversion + metric swap.** Source of truth says a *February 2026 founder interview* **implied** a **~$689K run-rate**. The new copy said *"third-party reports cite figures ranging from roughly $689K to $10M in annual recurring revenue."* Two errors compounded: a founder's own statement was attributed to third parties, and a run-rate was relabelled as ARR — inside the machine-quotable `acceptedAnswer`. This is the PR's own defect class, pointed a different direction.

**2. Dependent-clause re-pointing** — the additive direction of the documented #6538 class. The original read *"Polsia's **growth** validates that solo founders will pay."* Attached to customer revenue, that clause was sound. The head was swapped to a **funding round** and the clause survived verbatim, becoming a non-sequitur: a round is evidence that *investors expect* founders to pay, not that they *do*. The documented rule warns about deletion leaving dangling clauses; this is the same failure when the head is **replaced** rather than removed.

**3. An AC that named a sub-region but was tested against the whole artifact.** AC4 required the figure tokens to appear in the rendered **answer**. The check grepped the whole rendered **page**, where the tokens appeared in the *question heading*. It reported PASS over an answer with dangling deixis — "that calibre", "that valuation" — whose antecedents lived only in the heading above. The AC was not wrong; its scope did not equal the noun it named.

**4. Half-swept sibling.** The published Paperclip page was corrected to the verified star count, but the `seo-refresh-queue.md` rows that **feed regeneration** still said `30,000+` / `53k+` and still carried the instruction *"Confirm canonical repo before publishing"* — an instruction this PR had discharged. That is the same mechanism that produced the original staleness: correct the artifact, leave the upstream row that regenerates it.

## Solution

Add a **presence-with-provenance** AC to any correction PR, as the inverse of the absence sweep:

> Every third-party claim the diff ADDS traces to a named line in the cited source of truth.

Concretely, the claim-by-claim table a reviewer should be able to fill:

| Claim | Where asserted | Source-of-truth line | Metric matches? | Verdict |
|---|---|---|---|---|

And scope every AC command to the noun the AC names:

```bash
# Wrong — passes on tokens in the question heading
grep -c '\$30M' _site/blog/<slug>/index.html

# Right — isolate the answer paragraph first
python3 - <<'PY'
m = re.search(re.escape("**Q: "+qn+"**") + r"\s*\n\s*\n(.+?)(?:\n\s*\n)", md, re.S)
assert tok in m.group(1)   # the ANSWER, not the page
PY
```

## Key insight

**An absence assertion and a presence assertion are not the same claim, and a correction PR needs both.** Verifying the old text is gone tells you nothing about whether the new text is true. The replacement copy is fresh, unreviewed prose written under the confidence of "we're fixing the unverified-claim bug" — which is precisely the state in which a new unverified claim gets written.

The generalisation of defect 3: **ask of every AC whether the command's scope equals the noun the AC names.** "In the answer" tested against the page, "in the block" tested against the file, "in the changed lines" tested against the diff — each passes vacuously on a superset.

## Session Errors

1. **Plan v1 grep baseline stated 24 lines/14 files; actual was 54/16.** Recovery: deepen-plan re-derived it. Prevention: already covered — plan-quoted numbers are documented as preconditions to re-measure, and the plan-review panel caught it.
2. **Plan v1 classified `seo-refresh-queue.md:208` as a historical record; it is a live P1 input to `cron-content-generator`.** Recovery: moved LEAVE → FIX, sequenced first. Prevention: block-date headings and `_Updated:` footers are human supersession cues with **no machine semantics** — check what the consumer actually selects on.
3. **Plan v1 described `business-validation.md:124` as already hedged; it is a bare assertion.** Recovery: re-classified with an honest reason. Prevention: read the line, don't paraphrase it.
4. **Plan v1's citation-fallback rule would have degraded a good citation** (403 is bot-gating, not dead). Recovery: rule amended to fall back only on 404/410/DNS. Prevention: an auth/bot-gated status (401/403/405/429) means *reachable*, not *dead* — only 404/410/DNS failure justifies dropping a citation, and the status code belongs in the PR body as evidence.
5. **Plan v1's parity AC was structurally vacuous** — the JSON-LD literal lives inside the same `.md`, so the assertion could never fail. Recovery: rewritten to extract `**Q:**` lines and assert bidirectional set equality. Prevention: for any parity AC, name the mutation that would satisfy the assertion while violating the property; if none exists, the AC pins nothing.
6. **Ran eleventy from `plugins/soleur/docs/` instead of the repo root**, where the config lives → `filter not found: dateToShort`, which looked like a real build break. Also used `npx` rather than the pinned `./node_modules/.bin/eleventy`. Recovery: rebuilt from root with the pinned binary. Prevention: both rules already exist in `work/SKILL.md`; the tell for a config-not-loaded failure is a *missing filter*, not a content error.
7. **`scripts/test-all.sh` was SIGTERM'd at the Bash tool's 10-minute ceiling** (exit 143) despite a requested 900s timeout — the tool caps at 600s. Recovery: killed surviving children, relaunched detached with an rc file plus a Monitor. Prevention: tracked on #6789; the mandated full-suite exit gate does not fit the foreground ceiling.
8. **`pkill -f 'scripts/test-all.sh'` also killed my own waiter loop**, whose command string contained the pattern → a spurious "background task failed, exit 144" notification. Recovery: none needed, it had already served its purpose. Prevention: pattern-match on something the killer itself cannot contain.
9. **The AC10 LEAVE-path grep was too loose** and matched this branch's *own* `decision-challenges.md` — which AC10 explicitly permits — reporting a false violation. Recovery: re-ran with a pattern scoped to the sibling branch's path. Prevention: a guard for "no LEAVE path in the diff" must exclude the allowed set explicitly, or it flags itself.
10. **AC8 harness first attempt failed on `import.meta.url` relative resolution.** Recovery: `resolve(process.cwd(), ...)`. Prevention: a throwaway AC harness dropped into an app's `test/` dir resolves against the vitest root, not the file — anchor on `process.cwd()` and delete the harness after the run rather than committing a one-shot acceptance check as a regression test.
11. **Reported AC4 as PASS when it was not** — see defect 3 above. Recovery: two review agents caught the dangling deixis; the AC is now answer-scoped and passes genuinely. Prevention: the scope-equals-the-noun check, now routed to `review/SKILL.md`.
12. **Paraphrase drift in my own replacement copy** (defects 1 and 2). Recovery: fixed inline. Prevention: the presence-with-provenance AC above.
13. **Dependent-clause re-pointing in my own copy** (defect 2 above) — "solo founders will pay" survived a head-swap from customer revenue to a funding round. Recovery: rewritten to match its new head. Prevention: `work/SKILL.md` already documents the *deletion* direction of this class (#6538); this session found the *replacement* direction behaves identically, now recorded in `review/SKILL.md`.
14. **Half-swept sibling** (defect 4 above) — corrected the published Paperclip page but left the `seo-refresh-queue.md` rows that feed regeneration stale, including a "confirm canonical repo before publishing" instruction this PR had already discharged. Recovery: all four queue rows plus the `competitive-intelligence.md` tracking item updated. Prevention: when a PR discharges an instruction written into a queue/tracking row, close the row in the same commit — leaving it re-creates the staleness on the next regeneration.
15. **Sibling-worktree `test-all.sh` contention** cost ~10 minutes of idle waiting. Prevention: filed #6789.

## Prevention

- Correction PRs get a **presence-with-provenance AC**, not just an absence sweep.
- Scope every AC command to the noun the AC names.
- When replacing a claim, read each rewritten sentence **against its new subject** — the surviving clauses were written for the old one.
- Sweep the **upstream row that regenerates** the artifact, not only the artifact.

## Related

- [[2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it]] — the deletion direction of defect 2
- [[2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim]] — claim-indexed vs file-indexed sweeps
- [[2026-04-15-multi-agent-review-catches-bugs-tests-miss]] — the pattern catalogue this routes into
