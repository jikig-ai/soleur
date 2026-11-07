# Pattern-Recognition Review — PR #11603 (feat-one-shot-11600-job-log-step-attribution)

**Seat:** soleur:engineering:review:pattern-recognition-specialist
**Scope:** `git diff origin/main...HEAD` in worktree `feat-one-shot-11600-job-log-step-attribution` — `scripts/followthroughs/web-first-deploy-10585.sh` (+94/-20), `scripts/followthroughs/web-first-deploy-10585.test.sh` (+143/-6), `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (+16), spec docs.
**Baseline corpus:** `git-data-boot-poll-8178.sh` (the copied technique), the sibling followthrough-probe population, repo conventions (fixture-dir-operand-assert drift suite, emitter-parity guards, never-quiet-on-unmeasured doctrine).

**Verdict: APPROVE WITH COMMENTS** — 0 P1, 2 P2, 6 P3. No correctness defect changes a verdict on any real log shape; the suite is green (69 passed, 0 failed; verified locally) and covers the recovery matrix well. The P2s are consistency/drift exposures introduced or surfaced by the diff, both fixable in ~5 lines.

## Pattern Usage Report

- **`emit_rows` chokepoint (web-first-deploy-10585.sh:217-227, consumed at :296 and :314)** — textbook extract-shared-filter refactor. The #9905 emitted-vs-echoed rule now lives in exactly one awk consumed by both the named-step anchor and the UNKNOWN STEP recovery, so the filter cannot drift between copies. The new split (`print $3` → `emit_rows`) is behaviorally equivalent to the old inline awk on every edge checked: missing `$3` emits the same empty `\t` row as before, ANSI-first-byte and ts-extraction logic identical. Good.
- **Region-slice idiom (web-first-deploy-10585.sh:307-310)** — byte-verbatim port of `git-data-boot-poll-8178.sh:205-208` modulo the `ps=` variable, as advertised by the comment. BOM/CR strip pair at :290-291 likewise mirrors 8178:202-203. The port is faithful — see P2-1 for the pin gap.
- **Recovery cause-chain (`recovery_cause` at :304-328)** — a clean enumerated-variant pattern threaded into the existing tripwire printf (:334); each branch names a distinct failure mode. Reset per-loop-iteration; correctly unreachable when the named path yields a trail.
- **Fixture DSL (test.sh:145-184)** — `ul`/`usrc`/`ulog` mirror the `l`/`src` named-attribution builders with a consistent `u` prefix; `ulog` faithfully reproduces the measured real shape (bare `Set up job` head, BOM'd prelude stamped before `started_at`, BOM'd trail header AT `started_at`, payload, BOM'd bounding header). The multi-BOM document is what pins the `//` global-strip mutation — the comment at :150-152 correctly identifies that a lone-BOM fixture cannot. `ULOG_NO_BOUND`/`ULOG_EARLY_HDR` knobs are documented at the builder.
- **Never-quiet-on-unmeasured doctrine** — recovery preserves it end-to-end: every failure arm funnels into the same `zero parseable` tripwire on success jobs, and the exit-vocabulary property sweep covers the 8 new cases. Anti-vacuity floor raised 30→69 to the exact new pass count — appropriately brittle-by-design.

## Findings

### P2-1 — Verbatim region-slice derivation now lives in two probes with no parity pin

`web-first-deploy-10585.sh:307-310` is a byte-identical copy of `git-data-boot-poll-8178.sh:205-208` (the header-gate regex `^[0-9][0-9TZ:.-]* ##\[group\]Run `, the two-tab-field strip, `substr(line,1,19)` ts compare, `started`/`exit`/`next` state machine), and the BOM/CR normalization pair is duplicated at `10585:290-291` ↔ `8178:202-203`. This is a subtle derivation — 8178 carries ~20 lines of measured justification for why the BOM strip must be global and why it sits in bash rather than awk, precisely because the shape is easy to "simplify" wrong.

The probe comment asserts "8178's region derivation verbatim" — a coupling nothing enforces. The repo already has the convention for this situation: `plugins/soleur/test/fixture-dir-operand-assert.test.sh` drift-checks every tracked copy of `assert_fixture_dir` (cited by the header comment at test.sh:27-28), and plugin AGENTS.md's workflow-script guidance states a presence grep is insufficient — the copy that runs must match the copy that is tested. If 8178's regex or ts-compare is ever tightened (e.g., the documented `::group::` "Run " residual, or a gh timestamp-format change), 10585 silently diverges.

**Recommendation:** add a cross-file parity pin — either a normalized-logic drift guard in one of the two `.test.sh` files asserting the awk block text matches its sibling, or register the snippet pair with the fixture-dir-operand-assert suite. A shared sourceable lib is *not* recommended: followthrough probes are deliberately self-contained (per-probe `FT*_GH`/`*_FX` seams, no shared lib dir exists in `scripts/followthroughs/`).

### P2-2 — The trail-pattern invariant is enforced asymmetrically: recovery arm strict, named arm retains the quiet drift hole

The recovery path adds a second strictness level the named path lacks. At :317, a recovered region whose emitted rows contain **no** pointer-or-ready line is forced back to `trail=""` with cause "recovered region emitted no trail-pattern lines" — correctly, per the comment's own reasoning that "a success job's trail step always emits the pointer — a region with output but no trail-pattern line is a degraded channel."

That reasoning applies identically to the named path, which still only checks `-z "$trail"`. A named-attribution success job whose trail step emits lines but none matching the trail patterns (pointer literal drift, step emitting warnings only) currently flows: non-empty `trail` → tripwire skipped → `ready_ts` empty → no pointer keys → **quiet 2 NOT YET** — the exact silent-under-coverage class the tripwire exists to kill, and the class this diff just closed for the recovery arm. Two arms now encode different strictness for one documented invariant — a drift vector and a residual hole.

**Recommendation:** hoist the pattern check to the post-source `$trail` — i.e. the success-job tripwire becomes "trail empty OR trail carries no trail-pattern line," evaluated once regardless of which arm produced it. Behavior on failure jobs is unchanged either way (empty → skip, patternless → no keys → nothing owed). This also collapses the two `recovery_cause` branch texts for the patternless arm into the shared diagnostic.

### P3-1 — `recovery_cause` misdiagnoses the empty-region arm, and the `ULOG_EARLY_HDR` fixture exercises a different arm than it claims

At :311-312, `-z "$region"` produces "; no ##[group]Run header at or after ${jstart:0:19} in an attribution-expired log". But `$region` is empty in TWO distinguishable cases: (a) no header ever satisfied `ts >= ps`, and (b) a header DID open the region (the last `##[group]Run` in the log) but zero output lines followed it. Case (b) gets case (a)'s diagnosis — an operator chasing the CANNOT ESTABLISH is told no header matched when one did.

Concretely visible in the suite's own fixture: `ULOG_EARLY_HDR=1` (test.sh:587-589) stamps the trail header *before* `started_at`, but `ulog` still emits the `Post job cleanup` header at `post` — which satisfies `ts >= ps`, opens an empty region, and exits at EOF. The test passes via arm (b) while its comment claims arm (a) ("a log with no ##[group]Run header at/after started_at"). The verdict and substring are identical so coverage of the rc is real, but the genuinely-headerless shape is never exercised — constructing it needs `ULOG_EARLY_HDR=1 ULOG_NO_BOUND=1` together. Fix options: have the awk print a sentinel when a header opens (`found=1`) so cause (b) can read "region opened but carried no lines", and/or add the combined-knob fixture row.

### P3-2 — Dead fixture helper: `usrc` is defined but never invoked

test.sh:157 defines `usrc()` (ANSI-echoed UNKNOWN STEP line builder) as the `src()` analog, and tasks.md 1.2 lists it as planned — but no call site exists. Case 18 builds its ANSI-echoed ready line as a raw positional arg to `ulog` instead. Either wire it into a fixture (e.g., a `usrc`-produced echoed line inside `ulog`'s payload loop, which would also make 18's construction symmetric with case 7's use of `src`) or delete it — a defined-but-unused builder is the fixture DSL's version of dead code.

### P3-3 — Header comment over-claims the "latent named-path edge" the BOM strip fixes

web-first-deploy-10585.sh:288-289 says the global BOM strip "fixes the latent named-path edge where a section's first line carries a BOM-prefixed timestamp into ts_to_epoch." On real `gh run view --log` shapes the BOM lands only on each section's first line — always that section's `##[group]Run` header, which can never match the `fresh-host boot reached`/`Sentry pointer` patterns, so a BOM'd ts could never actually reach `ready_ts`/`ts_to_epoch`. The normalization is still correct and necessary (the recovery path's `^[0-9]` header gate and `substr(line,1,19)` ts-compare genuinely depend on it — 8178's measured comment shows exactly how it fails otherwise); only the *justification* is overstated. Suggest rewording to name the recovery path as the true consumer ("fixes the BOM'd header the region gate would otherwise miss") rather than a named-path edge that cannot fire.

### P3-4 — Recovery gate encodes an all-or-nothing attribution-expiry assumption (unstated residual)

Recovery fires only on `-z "$trail"` (:305) — correct for GitHub's observed all-or-nothing per-log expiry, but a partially-attributed trail (pointer attributed, ready UNKNOWN, hypothetically) would take the named path with an incomplete row set and silently derive no obligation. This is speculative — no evidence partial expiry occurs — but it is the same *class* of unstated assumption the header's RESIDUALS section exists to record, and one sentence there ("recovery requires the trail step's lines to be wholly unattributed; partial expiry is unobserved and would read as a thinner trail, not a recovery trigger") would close the documentation gap.

### P3-5 — `--jq` expression duplicates the step-selection predicate twice

web-first-deploy-10585.sh:268 repeats `[.steps[]? | select(.name | startswith("Surface fresh-host Sentry breadcrumb trail")) | .X] | .[0] // "-"` for both `.conclusion` and `.started_at`. Two copies of a literal-bearing predicate is a small drift surface (a rename must hit both). Collapsible to `([.steps[]? | select(.name | startswith("..."))] | .[0]) as $s | "\($s.conclusion // "absent")\t\($s.started_at // "-")"`. Also note `.name` unguarded (`select(.name | startswith(...))` errors on a null name) — pre-existing, but a `(.name // "")` guard rides the same line.

### P3-6 — Naming/docs nitpicks (batch)

- test.sh `ulog` (line 170) declares `local ... l` and iterates `for l in "$@"` — shadowing the global `l()` fixture builder in the same file. Harmless (no call inside), but a `line`/`ln` local keeps the DSL free of self-shadowing.
- `job()` writes `"completed_at":%s` equal to `started_at` (test.sh:138-139) — a step that starts and ends at the same instant is a fixture-unrealistic shape; harmless since nothing reads `completed_at`, but a `+600` offset would age better if a future consumer appears.
- Runbook (followthrough-convention.md, new section): "`git-data-boot-poll-8178.sh` and adapted in `web-first-deploy-10585.sh` (#8262)" — the `(#8262)` sits after the 10585 name but is 8178's precedent issue; a reader may misattribute which probe #8262 fixed. Suggest "(#8262; adapted here under #11600)".

## Anti-Pattern Scan

- No TODO/FIXME/HACK/XXX introduced in the diff.
- No new god-function: the recovery block adds ~25 lines inside the existing per-job loop, all single-purpose; `emit_rows` extracted rather than inlined.
- No layering violation: the change stays inside the probe's existing gh-log → awk → trail pipeline; the jobs API gains one field on the same call rather than a new transport.
- Code duplication is the scan's headline finding — see P2-1 (cross-file) and P3-5 (intra-expression); the `ul`/`ulog` UNKNOWN STEP fixture builders also parallel 8178's test idioms and inherit the same unpinned-copy exposure.

## Naming Consistency

- `jstart` continues the `jid`/`jcon`/`jstep` TSV-field convention; `recovery_cause`, `emit_rows`, `GH_LOG_BOM`, `ul`/`ulog`/`usrc`, `ULOG_NO_BOUND`/`ULOG_EARLY_HDR` are all self-describing and consistent with the file's fixture-DSL style. Only nit: `l` local shadow (P3-6).

## Verification

- `bash scripts/followthroughs/web-first-deploy-10585.test.sh` → **69 passed, 0 failed** (45 probe runs, all exits in {5,2,3,78}).
- Byte-level diff of the two region-slice awk blocks confirms verbatim-copy claim (only `ps=` binding differs).
- No worktree writes; scratch not needed beyond the test suite's own `mktemp`.
