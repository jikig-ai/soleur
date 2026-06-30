# Learning: a new guard test that mirrors an existing round-trip should first check what the round-trip already enforces

## Problem

Planning the #5703 registry-completeness test, the first draft specified three
invariants for a new `registry-completeness.test.sh`: INV1 (registry→source integrity:
source_file exists, markers present, projected_prompt_path exists, marker↔id
consistency), INV2 (source→registry parity), INV3 (no duplicate block_id) — plus
"verify-the-verifier" machinery (parameterize each invariant on injectable
registry-path/scan-root, drive synthetic tmp fixtures). The second deliverable was a
refactor of the EXISTING `extract-block.test.sh` to be registry-driven.

## Solution

The 3-agent plan-review panel (DHH / Kieran / code-simplicity) collapsed it to roughly
one assertion:

- **INV1 was ~90% redundant with the OTHER deliverable.** Once `extract-block.test.sh`
  loops over registry entries, its round-trip calls `gen-skill-prompt.cjs
  generateFromDisk()`, which `readFileSync(source_file)` (throws if missing/renamed) →
  `extractBlock(... registry markers)` (throws if markers absent) → returns
  `projected_prompt_path` (round-trip `diff` fails if missing/stale). So every INV1 case
  was already caught by the registry-driven round-trip. The redundancy was invisible
  because it spanned two files.
- **INV2 (parity) collapses to one set-equality** of source-scanned block-ids vs registry
  block_ids — which ALSO catches marker↔id inconsistency (a registry block_id disagreeing
  with the source marker surfaces as a scanned-id ≠ registry-id mismatch). The
  injectable-parameter + synthetic-registry machinery was testing that `diff` works; the
  cited git-log-union-trap learning (a genuinely tricky verifier) did not transfer.
- **Kieran caught two real residuals the simplification didn't:** (a) `sort -u` hides the
  *same* block_id duplicated across source markers (registry maps a block_id to ONE
  source_file → the second occurrence is silently never projected) → added a per-id
  count==1 DEDUP guard before `sort -u`; (b) `git grep` is **tracked-only** and cannot
  see an untracked `/tmp` fixture, so a file-based negative test would exercise a
  different backend than production and false-pass → keep the negative purely in-memory
  (append a fake id to the scanned list).

## Key Insight

- When a plan adds a new guard/parity test ALONGSIDE a refactor of an existing
  round-trip/regeneration test, enumerate what the round-trip already enforces (it
  regenerates from source, so it implicitly validates source existence + markers +
  projection) BEFORE adding integrity invariants. The net-new value is usually only the
  direction the round-trip does NOT iterate (here: source→registry completeness).
- A negative test for a `git grep`-backed verifier must be in-memory, not a file fixture
  — `git grep` ignores untracked files, so a tmp fixture silently tests nothing.
- "Verify the verifier" is warranted for a tricky verifier (range/union/intersection
  semantics), not for a `diff` of two sorted lists.

## Tags
category: workflow-patterns
module: soleur:plan, eval-harness, plan-review
issue: 5703
