# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-fix-lint-infra-workflow-filename-false-positive-plan.md
- Status: complete

### Errors
- The `iac-plan-write-guard` PreToolUse hook blocked the initial Write and one Edit, because the plan legitimately quotes a human-run terraform invocation as a **test fixture**. Resolved by adding the documented `iac-routing-ack: plan-phase-2-8-reviewed` opt-out (Phase 2.8 reviewed; the plan introduces no infrastructure). The literal phrasing is deliberately paraphrased here: quoting it verbatim in a scanned dir trips the very sentinel this PR repairs.
- The plan tripped the very linter it repairs, four separate times, as fixture prose was added. Each was resolved by wrapping the quoting region in an ignore region with rationale — including one caused by the meta-trap of documenting the marker itself.
- Background review agents' final reports did not surface through the notification channel on the first two attempts; recovered by parsing the agent transcripts directly and then re-requesting via SendMessage. Both reports were ultimately received in full.

### Decisions
- **Land both fix options**, with option 2 (tool-anchored `-target`) as primary and option 1 (filename neutralization) as a supplementary, explicitly-argued addition — diverging from the issue's stated preference order on measured evidence (option 2 removes 45 latent false positives and frees 8 carve-out regions; option 1 removes 8 and frees 2).
- **Neutralize filenames once per line in `scan_text`**, feeding both the actor and imperative halves, behind a fast path testing both `.yml` and `.yaml`. Naive per-predicate substitution was measured at 2.3x the full-scan cost.
- **Substitute `_`, never the empty string** — deleting a span can bring fragments into adjacency and *create* matches. Guarded by a dedicated fixture.
- **Sweep 7 carve-out regions inline, retain 1**, and verify every removal in-context rather than by body-isolation (one region scans clean in isolation but still flags in context). The other ~52 regions are measured as unrelated to this defect, so no follow-up issue is filed.
- **Express acceptance criteria as relative deltas, not absolute counts or wall-clock seconds** — the corpus drifts and baselines vary 32-73 s across hosts.

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:deepen-plan`
- `Agent: soleur:engineering:review:kieran-rails-reviewer` (correctness panel)
- `Agent: soleur:engineering:review:code-simplicity-reviewer` (simplicity panel)
- Deepen-plan gates 4.4 (precedent diff), 4.5 (network-outage, recorded non-applicable), 4.6 (user-brand impact), 4.7 (observability), 4.8 (PAT-shaped variable), 4.9 (UI wireframe)
- `gh issue view`, `git grep`, and a purpose-built scratchpad harness for the four-arm corpus measurement
