# Decision challenges — feat-one-shot-6752-7004-10167-tmp-gate-residuals

Headless/pipeline planning run inside a Task-free subagent context (Devin
CLI). No agent-spawn capability: technical rulings are recorded
`pending - assumed` per the technical-ruling-delegation contract; `ship`
renders this table into the PR body and files `action-required` issues.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #6752's ask ("three remaining tempfile-ownership sites") is stale — the merged #10017 census (`mktemp-census.md`, Mandatory rows) verified all three sites already-clean. Plan delivers verify-and-close with evidence, not the trap additions the issue describes. | technical | pending - assumed: close #6752 with census + fresh re-verification evidence; no speculative trap edits — the issue itself names the speculative-fix blast radius (session-state.sh fd-locks, workspaces-cutover LUKS rollback) |
| #7004's reclamation machinery already shipped in PR #8738; the brief's "treat the deferred work as in-scope" reads against a stale title ("reclamation deferred"). Plan bounds the residual to the two measured-but-unadopted producers (cloud-init-inngest-bootstrap.test.sh, harness-discovery-smoke.ts) and defers the Tier-3 `env -i` sweep (~91 files), absolute `/tmp` literals, and day-7 soak probe to a tracking issue filed at work time. | operator (scope) | pending - assumed: bounded adoption in this PR + deferred-tail tracking issue — the recorded safety rationale (~25+ env -i judgement calls do not belong in the same review sitting) still holds; operator may widen scope at review |
| #7004 is referenced (`Refs`), never `Closes`, in the PR body — the issue's own comment record fixes its close-condition to the #8786 operator-run drain evidence, which a code PR cannot produce (production-mutating purge on the operator host). | operator (scope) | pending - assumed: Refs only; issue stays open until #8786 evidence lands per its recorded close-condition |
| #10167 fix form: two-arm presence check (non-empty same-line value OR following indented block) vs the issue's simplest suggested `^${f}:` alone. | technical | pending - assumed: two-arm check — `^f:` alone accepts `findings_json:` declared-but-empty (YAML null, schema-invalid); the awk pass costs one read and preserves rejection |
| Scoped advisor consult (Step 4.5), plan-review agent panel, domain leaders, and research subagents could not run — no Task-spawn capability in this context. Research and review executed inline (premise validation, mechanism-minimality, overlap check, guard-contract lint all ran mechanically). | technical | pending - assumed: inline review per the prior Devin-CLI headless precedent (feat-one-shot-6760 decision-challenges); the multi-seat soleur:review panel at PR stage is the next real review layer |
| `lane: cross-domain` retained though the semantic sweep finds zero cross-domain surface — `security` token in `skill-security-scan` trips the fail-closed trigger; no domain leaders could be spawned regardless. | technical | pending - assumed: keep the conservative lane; cheaper than a false single-domain ruling |

## Not Yet Specified

- Whether `harness-discovery-smoke.ts` should import `plugins/soleur/test/lib/scratch-session.ts` (test-lib import from `scripts/`) or write `.soleur-owned` markers directly via the tmp-classify contract — implementation detail resolved at work time; both satisfy the same marker format (`tc_marker_owner_pid` is the one parser).
