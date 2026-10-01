# Phase 0 — open design questions, resolved with measurements

Closed before RED work per `tasks.md` Phase 0.2/0.3. Each records what was measured, not asserted.

## Population re-measurement (supersedes plan C4 partially)

| Quantity | Command | Measured |
|---|---|---|
| Shipped marker blocks | `grep -rl 'soleur-cloud-mode:start' plugins/soleur/ \| wc -l` minus the guard file | **67** (68 files match; `plugins/soleur/test/devin-cloud-mode.test.ts` is the 68th and quotes the marker literal only) |
| Derived cache-path population | `grep -rlE '/opt/\.devin/plugins\|devin/cli/plugins/cache' plugins/soleur/ \| wc -l` | **71** — confirms consolidation C4 over the plan body's 69 |
| Derived MINUS marked | `comm -23` | `AGENTS.md`, `commands/go.md`, `devin/INSTRUCTIONS.md`, `test/go-session-gates.test.sh` |
| Marked MINUS derived | `comm -13` | `test/devin-cloud-mode.test.ts` — it carries the marker but **no cache path today** |

Consequence for the guard's self-match problem: it does **not** exist in the current tree. It would
be created by commit 1 if the detector quoted its own literal. The adopted simplification (assemble
the pattern from fragments) avoids creating it, so no allowlist ships and nothing asserts the
allowlist's size. 71 = 67 + 4.

## 0.2.1 — `/opt/.devin/plugins` containment under test (consolidation X1)

**Decision: add a single override, `SOLEUR_DEVIN_CACHE_OPT`, on the `/opt` arm only.**

```sh
for d in "$HOME/.local/share/devin/cli/plugins/cache" "${SOLEUR_DEVIN_CACHE_OPT:-/opt/.devin/plugins}"; do
```

Why this shape rather than the alternatives the panel named:

- **Only the `/opt` arm needs one.** `run_gate` already passes `HOME="$home"` on scratch in every
  row, so the `$HOME` cache arm is contained today. Adding a second override for it would be
  surface with no containment value.
- **One quoted scalar with a `:-` default is POSIX-safe.** The resolver's own header forbids
  non-POSIX constructs; a space-separated `SOLEUR_DEVIN_CACHE_ROOTS` list would need unquoted
  word-splitting, which breaks on a path containing a space. Two arms, two quoted words, no split.
- **It adds no new trust class.** Arm 2 (`GROK_PLUGIN_ROOT`) is already a fully env-directed root
  subject to the same `name=soleur` identity preflight, and ADR-179 A11 records that preflight as a
  shape check a planted directory passes. An env-directed search *root* is therefore strictly
  within the existing model, not an extension of it.
- **The rejected option was "add an AC naming the dependency".** Rejected because the plan's own
  X1 text forbids the outcome it produces: *"Do not ship a MUST-PASS suite whose verdict is a
  property of the machine."* The affected rows (R4, R6, R6c) change verdict with no diff change on
  exactly a Devin CLI host — the audience #8401 exists for — so the suite would be weakest on the
  hosts it is for.

`run_gate` sets `SOLEUR_DEVIN_CACHE_OPT` to a scratch path that does not exist, so the `[ -d ]`
guard skips that arm deterministically on every host. Recorded in the ADR-179 A16 amendment.

## 0.2.2 — fleet block: full recipe vs pointer (consolidation "Recorded, not adopted")

**Decision: full recipe, in compact single-paragraph prose form.** Measured before deciding, as the
panel required — changing this after the 67-file sweep is the rework.

| Measure | Value |
|---|---|
| Current block | 915 bytes |
| Proposed block | 1393 bytes |
| Delta per body | **+478 bytes ≈ +119 tokens** (1.52×, not the feared ~8×) |
| Fleet-wide on disk | +32 KB across 67 files |

The ~8× estimate assumed pasting a multi-line `bash` fence. A prose form of the same recipe is
1.52×. Per-body cost is what matters (one skill body loads at a time), and ~119 tokens is below the
noise floor of a skill body.

**The measurement is not the decisive argument, and the decisive one points the same way.** The
panel recorded it itself: a pointer cannot carry a root-resolution recipe, because reading
`devin/INSTRUCTIONS.md` requires the root the recipe resolves. That bootstrap circularity makes the
pointer non-functional for this block, not merely larger. It gets one sentence in the ADR so it is
not re-proposed.

`plugins/soleur/AGENTS.md` still takes the **pointer** treatment — a different constraint (a
one-line rule body in a customer-shipped always-loaded file), not an inconsistency.

## 0.3 — RESOLVE echo placement and the nomatch source value (spec-flow A3)

**Decision: exactly one `SOLEUR_PLUGIN_ROOT_RESOLVE` line per gate, emitted after verification.**
Moving the cache arms inside the resolver anchors moves the arm's own interim `echo` with them, so
that interim emit is deleted and the single post-verify emit is the only one. A Guard 2 row asserts
the **count** is exactly 1 per gate (`grep -c`), not presence — a `grep -F` presence check cannot
see a duplicate.

**Decision: add `source=devin-cache-nomatch`.** `none` and "a cache directory exists but carries no
Soleur manifest" have two different remedies and collapsed into one value. New semantics:

| `source=` | Means | Remedy |
|---|---|---|
| `devin-cache` | a cache dir existed and yielded a `name=soleur` manifest | — |
| `devin-cache-nomatch` | at least one cache dir existed and was searched; no Soleur manifest in it | reinstall/update the plugin in that cache |
| `none` | no arm produced a root and no cache dir existed to search | set `CLAUDE_PLUGIN_ROOT` per the harness's INSTRUCTIONS |

`go.md`'s operator marker-interpretation list gains the `devin-cache-nomatch` row alongside the
`reaper-capability-unverified` row CPO-C1 requires, and the existing `source=none` bullet is
corrected — Phase 2 falsifies it for read-from-disk harnesses (spec-flow A4).
