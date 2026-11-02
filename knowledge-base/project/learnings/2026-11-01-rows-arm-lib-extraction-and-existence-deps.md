# --rows lib extraction + affected-index existence-deps (dispatch #11647)

Machinery lessons from shipping the `--rows` arm-debt bundle (est tier,
rows-range.sh, exit-2 parity, per-block floors, ADR-313).

## Direction-2 census matches DECLARED_TOTAL= inside subshells, not just
## line-start bare decls

`_DECL_COUNT_RE` (`scripts-shard-totality.test.sh`) matches `export DECLARED_TOTAL=`
with optional keyword prefix anywhere at line-start — a subshell-scoped
`( export DECLARED_TOTAL=N; … )` inside a lib test file still counts. The
sanctioned dodge is quote-splicing the var name (`DECLARED_TOTA''L=N`):
runtime concatenates back to the same name, the regex sees `DECLARED_TOTA''L`
which never matches. Same for Direction-1: `--rows "2-3"` quoted literals evade
`--rows[[:space:]]+[0-9]+-[0-9]+`; document WHY in the file header or a future
"unquote the literals" cleanup reds the census silently.

## Accept-vs-edge: existence-deps are edges, not accepts

The affected-index accept/edge doctrine isn't "reads the file" vs "names it" —
it's "does the suite's verdict change on this path's diff." A classification-table
row (`IN|path`/`EXCLUDED|path`) or an imported file a suite's checker resolves
is delete-sensitive: `TABLE-STALE`/`UNRESOLVED-IMPORT` red the suite on a
delete-only diff. `test-affected-paths.sh:906-908` already declared
existsSync-checked files as edges for exactly this reason — same shape, same
disposition. ~25 fixture-string accepts had to be converted to edge members.

Cost of conversion: each edge file joins the suite's read closure → every
comment/mention inside it mints new (suite,path) pairs → ~187 transitive pairs
to reconcile (mostly name-only accepts). Budget a reconciliation cycle per
edge expansion; the ratchet's flag display caps refs at 3 per pair — grep the
closure or use `audit --all-refs` to enumerate the full boundary set.

## Exit-code doctrine pitfalls that survive static review

- `declare -p X | grep -q` is a producer-pipe shape the SIGPIPE sweep asserts
  zero of — use `[[ "$(declare -p X)" == "declare -a "* ]]`.
- `[0-9]+`-validated values still need `10#` normalization before arithmetic:
  `08`/`09` arithmetic-error inside `(( ))` → the `if` goes false → gate
  silently skipped (the dangerous direction, not a crash).
- `ROWS_BLOCK_CASES[$i]` without `:-` on a sparse-but-count-matching array
  aborts rc 1 under `set -u` — a shape error exiting like a verdict, off the
  exit-2 doctrine.

## Floor maps under-declare silently

`>=` floors never false-fire — the failure direction is a floor below the
block's real straight-line `cases+=` count (a hollow to the floor stays
green). Count sites per block before shipping the map; loop-driven blocks
get structural minimums, straight-line blocks get the exact count. Two of 38
values were under-declared and survived until a seat counted sites
per-block.

## bash lazy-reads running suite files

Editing a `*.test.sh` while a `--rows` arm of it is executing corrupts the
run mid-file (bash re-reads at byte offsets) — bogus FAILs that look like
suite regressions. Never edit a battery file while an arm of it runs;
re-run arms on the committed tree after the last edit.
