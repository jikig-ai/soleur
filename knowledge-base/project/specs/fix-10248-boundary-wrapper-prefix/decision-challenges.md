# Decision Challenges — fix-10248-boundary-wrapper-prefix

Headless pipeline record per ADR-084 + technical-ruling-delegation. No Agent tool was available in the
planning subagent, so technical rows carry `pending - assumed:` rulings — a CTO consult may override at
review time.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Shared fragment home — `plugins/soleur/scripts/lib/wrapper-boundary.sh` (new) vs the issue's suggested `.claude/hooks/lib/` constant / `lib/incidents.sh` helper | technical | pending - assumed: plugin-scripts lib. `precommit-guard.sh` is self-contained BY DESIGN and runs from the plugin install cache where `.claude/` does not exist; the plugin lib is the only home reachable from BOTH consumer trees (cache-safe `SCRIPT_DIR` resolution for precommit; `incidents.sh` nested source for the 11 hook files). Satisfies the issue's shared-fragment intent without reintroducing a second restatement. |
| `rtk run -c '…'` / `rtk summary --shell '…'` opaque string-payload escalation to `unparsed-wrapper` ask verdicts at boundary sites | technical | pending - assumed: out of scope — joins the declared `bash -c '…'` lexical-limit class every boundary gate already carries; the fragment deliberately excludes `-c\|--command\|--shell` atoms. New verdict machinery is beyond the issue's fix requirements. |
| Launcher arg-grammars (`sudo -u root`, `env -C dir`, `timeout 5`, `nice -n N`) in the shared fragment | technical | pending - assumed: out of scope — pre-existing gap predating `rtk`, named in the plan's Attack Surface Enumeration; atom shape admits them later. Candidate follow-up issue if untracked. |
| TSV machine-readable flag rows (`flag-global`, `flag-string` classes) so globals/string-flags get parity extraction, not just exec-subs | technical | pending - assumed: adopt — additive rows only; all six existing extraction arms key on `class == "exec"` and are unaffected. |
| pkill `PFX` consolidation into the shared fragment | technical | pending - assumed: rejected — `PFX` admits arg-words after the wrapper (correct for `ps`, wrong for gated-command adjacency); different atom grammar; widening into the parent's just-landed code doubles the regression surface. |
| `brand_survival_threshold: aggregate pattern` (vs `none` vs `single-user incident`) | taste | pending - assumed: aggregate pattern — systemic integrity of the repo's guard substrate; no per-incident blast radius that would justify single-user-incident escalation, but `none` understates a security-evidence surface. |
| Census guard as `plugins/soleur/test/*.test.sh` vs new `scripts/lint-*.py` | technical | pending - assumed: test suite — auto-discovered by `scripts/test-all.sh`, matches the parity suite's idiom; no new lint surface. |
