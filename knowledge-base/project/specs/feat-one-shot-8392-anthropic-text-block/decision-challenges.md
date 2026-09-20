# Decision Challenges — feat-one-shot-8392-anthropic-text-block

Persisted headless per `soleur:plan` Step 4.5 (ADR-083/ADR-084). `ship` renders these into the PR body and files an `action-required` issue.

## DC1 — advisor proposed `filter(text).join("")` instead of `find(text)` (decision class: user-challenge)

**Operator's stated direction (#8392, the default):** `data.content?.find(b => b.type === "text")?.text ?? ""` — take the FIRST text block.

**Challenge (ADR-083 advisor consult, 2026-09-19):** `filter(b => b.type === "text").map(b => b.text).join("")` is a "cheap hedge, same test surface" — it would not silently drop a later text block in an interleaved thinking/text/thinking/text sequence.

**Plan's disposition — kept the operator's direction.** Three reasons: (1) both live callers pass `output_config.format: {type: "json_schema"}`, which yields exactly one text block, so the hedge protects a shape neither caller can receive; (2) `domain-router.ts` already reads first-text, so `find` keeps the two copies of this parse identical, which is what its own NOTE comment asks for; (3) concatenation is a behavior change with no property behind it and was recorded in the plan's Cut List at Phase 0.6b before the consult ran.

**What would reverse it:** a caller that drops `output_config` (free-form text response), or an observed response carrying two text blocks. Either makes the hedge load-bearing rather than speculative.

## DC2 — plan-review widened the scope beyond the issue's stated inventory (decision class: user-challenge)

**Operator's stated scope (#8392):** fix `postAnthropicMessage`, verify the weekly digest is covered, decide on `domain-router.ts`.

**Challenge (Kieran correctness review + CTO devex review, plan-review panel, 2026-09-19):** the issue's blast-radius section under-counts the class. A repo-wide census found two more readers of the same shape outside `apps/`: `scripts/compound-promote.sh:231` (pinned `claude-sonnet-5` at `:218`, **live-broken**, hard-`exit 1` on empty) and `scripts/learning-retrieval-bench.sh:360` (latent Haiku twin). Separately, `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` prints `thinking-API shape: … no-op` — true of the request side, irrelevant to the response side, and contradicting that skill's own SKILL.md row 3. That line is why ten consecutive per-model-release audits reported this axis clear.

**Plan's disposition — scope widened, four extra edits folded in.** Each is one expression or one line: two `jq` picks, one `echo` block, one SKILL.md table cell. The shell sibling is the same feature's own manual arm and is worse off than the `domain-router.ts` line the issue already asks about, so fixing one and not the other would be arbitrary. The audit fix is compelled by `wg-when-a-workflow-gap-causes-a-mistake-fix`.

**Scope delta the operator should see:** `+scripts/compound-promote.sh`, `+scripts/learning-retrieval-bench.sh`, `+scripts/compound-promote.test.sh`, `+plugins/soleur/skills/model-launch-review/{scripts/audit-models.sh,SKILL.md}`. Say the word and the two `model-launch-review` edits split into a follow-up issue; the two shell picks should not, since leaving a live-broken sibling behind would make "Deferred items: none" false.

## DC3 — the simplification panel would cut the post-deploy production arm entirely (decision class: user-challenge)

**Operator's stated direction:** after merge + deploy, fire the compound-promote manual trigger once on prd and read `SOLEUR_COMPOUND_PROMOTE_OUTCOME`; record the row on #8281.

**Challenge (DHH review, P0):** firing a billed Sonnet run against prd to confirm that `Array.prototype.find` works is ceremony. The unit tests prove the parser; the scheduled Sunday 00:00Z run proves prod; `scripts/followthroughs/compound-promote-outcome-8281.sh` already watches for the row — and the plan itself concedes the manual fire cannot close #8281 (the probe requires `trigger == "cron"`), so the expensive step is explicitly non-closing.

**Plan's disposition — kept, per the operator's direction and the CTO's counter-argument.** The probe cannot report until the first Sunday after merge, which is up to 8 days of an unverified fix in production; the manual fire is the only same-day evidence that the deployed build actually parses a real Sonnet 5 response. The compromise applied: AC10 is now a *falsifiable* predicate (no `Empty Anthropic response` event on a run whose `SOLEUR_CLAUDE_COST` shows output tokens) rather than the original "clusters > 0 OR a named status", which admitted every outcome and could never fail; and posting the row to #8281 was demoted out of the acceptance criteria to a Phase 7 step, so this PR's done-ness no longer depends on another issue's bookkeeping.
