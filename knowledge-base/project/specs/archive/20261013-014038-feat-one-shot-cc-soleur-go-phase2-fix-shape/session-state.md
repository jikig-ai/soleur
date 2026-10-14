# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-cc-soleur-go-phase2-fix-shape/knowledge-base/project/plans/2026-05-05-fix-cc-pdf-poppler-cascade-phase2-positional-and-exclusion-list-plan.md
- Status: complete

### Errors
None. All gates passed:
- Phase 4.6 User-Brand Impact halt: PASS (heading present, threshold = `single-user incident`, body concrete and non-placeholder, requires_cpo_signoff: true carry-forward from PR #3288).
- Phase 4.5 Network-Outage gate: did not trigger (no SSH/firewall/timeout/handshake keywords in prompt-engineering plan).
- Branch safety: feat-one-shot-cc-soleur-go-phase2-fix-shape (not main).
- Code-Review Overlap check: 3 acknowledged issues (#2955, #3219, #3242) — same disposition as PR #3288, no fold-ins.

### Decisions
- **Sentry breadcrumb data ruled the fix shape.** Pulled 6 cold-Query construction breadcrumbs from production Sentry (conversationId 73a6ede4, 2026-05-05 18:50:43–18:51:21Z). All 6 showed `hasContextPath: true`, `documentKindResolved: "pdf"`, `hasActiveCcQuery: false`. Per the Phase 1 plan's gating logic this rules out **all four sub-hypotheses A.1–A.4 (client / resolver / Map-leak)** and **confirms hypothesis B (positional weakness)** plus co-confirms **hypothesis C (wording below override threshold)**.
- **Phase 2A (client-side rebind) is dropped from scope.** The original parent plan's gating logic prescribed exactly this branch; this plan implements 2B+2C only.
- **Phase 2B = positional reorder so artifact frame leads when present.** Concierge-side: `[artifactBlock, ...baseline, ...remainingExtras]` when `args.artifactPath` is non-empty. Leader-side has different semantics (identity opener must remain first); leader prepends the artifact directive between identity-opener and the rest of the baseline. Both achieve "frame establishes the tool before router scaffolding establishes the dispatch protocol".
- **Phase 2C = named-tool exclusion list extending the gated PDF directive only.** 5 measured binaries (`pdftotext`, `pdfplumber`, `pdf-parse`, `PyPDF2`, `PyMuPDF`/`fitz`) plus 2 install verbs (`apt-get`, `pip3 install`) plus generalized "shell-installation commands". Lives in the GATED inline branch at `soleur-go-runner.ts:519` and `agent-runner.ts:616`, NOT in the `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` baseline constant — preserving the anti-priming-guard at `read-tool-pdf-capability.test.ts` Scenario 2.
- **PR will close #3292 and #3293 (the two follow-through issues created by /ship Phase 7 Step 3.5 on PR #3288), NOT re-Closes #3287.** #3287 is already CLOSED via PR #3288.
- **No SDK upgrade needed.** Installed `@anthropic-ai/claude-agent-sdk@0.2.85` already supports PDF-native Read.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- gh issue view, gh pr view 3288
- Sentry HTTP API via doppler-resolved SENTRY_API_TOKEN
- mcp__plugin_soleur_context7__resolve-library-id + query-docs
- bash (grep, find, wc)
- Read (ws-handler.ts, soleur-go-runner.ts, agent-runner.ts, read-tool-pdf-capability.test.ts, agent-runner-system-prompt.test.ts, baseline-prompt-must-declare-capabilities learning, parent plan)
- Write (plan file)
- Edit (4 deepen-pass enhancements)
