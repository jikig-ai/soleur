# Measurements — #9763 continuation (2026-10-09)

Host caveat: ALL wall-clock numbers below were taken on a CONTENDED host
(load ~34 on 16 cores, tmpfs /tmp ~51% full, plus a 9h `yes|grep` orphan and
several concurrent agent sessions). Use them for relative attribution, not as
idle-machine absolutes. The #9763 idle baselines (4.40 min docs arm) stand.

## A. The affected pre-pass is the dominant fast-tier fixed cost

`bash scripts/test-all.sh --print-selection --paths=README.md` (the same
pre-pass a real `--affected` run executes — `_PRINT_AFFECTED` is a different
flag; print-selection pays the full derive):

- Total: **2m31s** wall (contended)
- Nested `--enumerate-commands` child walk: **0.85s** — negligible
- The `_affected_classify` loop over 585 records: ~**150s**, i.e. ~256ms/record

Instrumented run (`EPOCHREALTIME` around classify per record; instrumentation
roughly doubles cost, so read proportions not absolutes):

| class | share of classify time |
|---|---|
| `edge:derived` | ~60% (172s of 285s instrumented) |
| `edge:declared` (union derive — `_PRINT_AFFECTED==0` arm) | ~40% (113s) |
| `always_on` early-return | ~0.3s total |
| `_diff_touches` per record | ~0 (memoized string compares) |

Worst single derives (instrumented): `render-c4-model` ~16s,
`community-argv` ~10s, `argv-bearer-sweep` ~6.4s — a long tail, not one bad
suite.

**Implication.** On the 4.40 min docs-only arm, ~2.5 min is selection overhead
and only ~1.9 min is suite execution. The pre-pass — not the suites — is now
the largest single component of the local fast tier.

The classify phase is **diff-independent**: `_affected_classify` computes
class + edge set from suite argv, file contents, and path existence only;
`_diff_touches` applies the diff afterward. The derive is a pure function of
enumerable inputs (files actually read + paths probed-and-missing) — which is
what makes a derive cache structurally different from the twice-rejected
suite-result memo (see F).

## B. kb-diff arm: 7 edge-selected suites, ~331 committed s

`--print-selection --paths=knowledge-base/project/specs/foo.md`:
`selected=118 of=585 (always_on=111, edge=7)`.

| suite | committed ms | why it selects |
|---|---:|---|
| test-affected-kb-consumers | 68,386 | honest `^knowledge-base/` — the ratchet reads the kb tree for consumers |
| operator-ack-guard | 109,036 | `^knowledge-base/` — `find . -name '*.sh'` walker; generated scripts ship under kb/specs/ |
| operator-script | 98,487 | same `*.sh`-walker scope |
| operator-agent-runnable | 15,761 | same `*.sh`-walker scope |
| lint-trap-tempfile-ownership | 20,587 | same `*.sh`-walker scope |
| lint-shell-capture-exit-live | 11,192 | same `*.sh`-walker scope |
| lint-shell-trace-credential-refusal | 8,494 | same `*.sh`-walker scope (committed weight; #9763 measured 185s LOCAL) |

Six of the seven are `*.sh` corpus walkers whose declared `^knowledge-base/`
edge is honest at prefix granularity but over-broad in practice: a
`*.md`-only kb diff can never change their verdict, yet selects ~331
committed seconds (realistically ~430s+ locally). File-level enumeration is
unsound (a NEW `.sh` under kb/ would be a coverage hole), so the fix is an
extension-aware edge kind in `_affected_classify`/`_diff_edge_hit`
(e.g. `knowledge-base/**/*.sh`) — a mechanism change, tracked as a new issue.
`test-affected-kb-consumers` keeps `^knowledge-base/` — any kb file can be a
consumer.

## C. Local-vs-committed weight drift — real, large, unmonitored

Spot-check of heaviest always-on suites, run standalone (CONTENDED — ratios
inflate, but the direction is consistent with the #9763 learning):

| suite | committed ms | local ms (contended) | ratio |
|---|---:|---:|---:|
| lint-workflow-errexit-capture | 7,265 | 43,343 | 6.0x |
| lint-shell-capture-exit | 6,054 | 46,028 | 7.6x |
| lint-legal-registers-unit | 8,647 | 24,284 | 2.8x |
| lint-legal-mirror-drift-baseline-unit | 7,735 | 16,176 | 2.1x |
| lint-legal-scope-block-placement-unit | 7,381 | 14,438 | 2.0x |

Even at a conservative 2x idle discount, several always-on suites plausibly
exceed the 10s committed cap in local reality. `TEST_TIMING_LOG` already
produces per-suite elapsed rows; nothing compares them to the committed
manifest. The drift detector (new issue) closes this loop.

## D. webplat/bun legs — already edge-gated, zero share off-app

On the README.md arm, `apps/web-platform [repo-wide+component]`,
`apps/web-platform [unit]` and all 4 bun registrations classify `edge:*` and
decline (sel=0). They cost ~0 on docs/kb/scripts-only diffs; on app diffs the
full projects run (~80s repo-wide+component + ~82s unit + bun legs; no
suite-durations.tsv rows — the manifest's population is the scripts leg).
Remaining lever is intra-suite narrowing (`vitest related`), tracked as a new
issue.

## E. Fast-tier shape audit (pyramid check)

All 111 always-on registrations are `bash`/`python3` invocations of
lint-live scanners, hook batteries and runner-SUT suites (96 bash / 15
python). No argv carries server/browser/network shapes. The tier is
unit/integration-shaped as labelled.

## F. Deferred mechanisms — evaluated against fresh evidence

- **Suite-result caching (P2, #7454 item 2):** rejection stands. #7454 records
  the structural defect — untracked producer/consumer pairs (`_site/`) defeat
  both tracked-only and untracked-inclusive keys. No new evidence.
- **Suite parallelism (#8231, #7454 item 1):** parked on #7376's measured
  interference signature (3 distinct suites failing across 2 of 6 parallel
  executions) and a green-baseline precondition; #8098/#8163 are live
  instances of the fixture/env contention class. Also: with the pre-pass at
  ~2.5 min and the fast tier's suites at ~1.9 min, intra-run parallelism would
  not touch the dominant cost even if safe.
- **Lock → admission control (#7454 item 3):** deferred with a hard evidence
  bar (TOCTOU + non-monotonic ENOSPC degradation). Stands.
- **Derive cache (NEW lever):** distinct from every rejected mechanism —
  caches selection metadata, not verdicts; inputs enumerable per record
  (files read = `_FE_FILES` memo set; missing probes recordable at
  `_affected_buf_add`'s `-e` check); no ambient/machine state enters the
  derive. Estimated saving ~2.4 min/run on warm cache — ~55% of the docs arm.
  `scripts/affected-prepass-bench.sh` is the selection-identity gate for any
  such change.
- **#9323 (CI-side path gating):** sibling extension, still the right shape;
  prepass caching does not transfer to ephemeral CI runners (cold cache each
  leg) unless restored via actions/cache — noted on the issue.
