# Structural enumeration — every path a baseline file (or equivalent state) can reach the ratchet's adoption/acceptance decision

Seat: structural-enumeration (PR #12127, branch `feat-one-shot-10861-pr5z-strict-zero`, HEAD `79db88e18b`).
Scope: `scripts/ci-pr-affected-replay.py` (`ratchet` subcommand), its merge-base helper `plugins/soleur/scripts/lint-ratchet.py`, the CI invocation in `.github/workflows/ci.yml`, and the adjacent baseline consumers (`scripts/followthroughs/ratchet-observation-window-10865.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, `.gitattributes`).
This is a map, not a findings list: coverage noted where observed, nothing ranked except the P1 candidates at the end. Probes were run in `/tmp/soleur-seat.vPxG` (a scratch fixture, not the worktree).

## 0. The decision core (one place)

All verdict computation lives in `ratchet_run` (replay.py:1994-2105). The adoption/state decision consumes exactly two values:

- `head_text = ratchet_read(root, rel)` — replay.py:2015. Working-tree bytes of the baseline, `None` only on `FileNotFoundError` (replay.py:1903-1911).
- `base_text = ratchet_base(root, a.base or "HEAD^1", rel)[1]` — replay.py:2037. The baseline's text in the resolved base commit's TREE via the merge-base copy of `baseline_at` (lint-ratchet.py:528-538): `None` only when `git ls-tree --name-only <sha> -- <rel>` prints nothing.

The new arm (replay.py:2058-2060):

```python
if head_text is not None and base_text is None:
    findings.append(("baseline-reintroduced", ...))
```

then `code = 1 if findings else 0` (replay.py:2101) and `return code` (2105). The append is unconditional inside the `if`; no later code removes entries from `findings`. Exit-2 conditions (floors, unreadable inputs, unresolved base, helper load failure) all raise BEFORE this point or return via `ratchet_infra` — stricter, never weaker.

Findings order (matters only for the marker string `findings[0][0]`, never for the exit code): `unaudited` → `star-row` → `stale-accept` → **`baseline-reintroduced`** → `baseline-deleted`/`new-pair` → `stale-line` → `baseline-dup` → `baseline-order` → `grown`.

## The map

### (a) `--baseline <path>` override invocations

- Anchor: `rel = a.baseline or RATCHET_BASELINE` (replay.py:1996); flag at replay.py:2520 (`--baseline`, default `""`). `--baseline ""` collapses to the default path; there is no env var, no second path.
- Covered: every state read (`ratchet_read`, `ratchet_base`, `baseline_split`, the arm, `grown`, `stale-line`, `dups`, `order`, the oracle list `RATCHET_ORACLE + (rel,)` at replay.py:1900) goes through `rel`, so an override file is judged identically. `--baseline` naming a path outside the tree → `read_bytes` confinement → `baseline-unreadable` exit 2. `--baseline` naming a directory → not a regular file → exit 2 (pinned by `row_rt_baseline_dir`).
- Members inside the arm's reach but decided by OTHER arms: a path that is a directory/gitlink/symlink AT BASE — `baseline_at` runs `git ls-tree` (non-empty listing) then `git show` (returns the tree listing / "Subproject commit" line / link target text) → `base_text` non-`None` → present-at-both → `grown`/`stale-line`/equality arms (probe P8: dir-at-base + file-at-HEAD → `exit=1 reason=grown`). Still refused, never adopted — but the verdict name is `grown`, not `baseline-reintroduced`.
- One-line edit adding a member outside the arm's reach: any second baseline consulted under a different state pair, e.g. `head_lines += baseline_split(ratchet_read(root, EXTRA_BASELINE))[0]` — folds a second file's lines into the compare set with no `head/base` check on it. Also `rel = os.environ.get("CI_BASELINE") or a.baseline or RATCHET_BASELINE` would make the judged path env-settable (today it is flag-or-constant only).

### (b) `--base <ref>` resolving to a tree where the file is absent while HEAD has it

- Anchor: `sha, base_text = ratchet_base(root, a.base or "HEAD^1", rel)` (replay.py:2037); flag at replay.py:2522; resolution at replay.py:1873-1883 (`ref.startswith("-")` refused; `git rev-parse --verify --end-of-options <ref>^{commit}`; unresolvable → `base-unresolved` exit 2 — never an adoption, per the docstring at 1869).
- Covered: the default `HEAD^1` (a merge commit's first parent = target tip under the PR/merge_group refs; `fetch-depth: 2` in ci.yml:428) and any explicit ref whose tree lacks the file → `baseline_at` → `ls-tree` empty → `None` → arm fires (probe P3, and P1 on the default).
- NOT covered, by construction: an explicit `--base` naming a commit whose tree HAS the file → `base_text` non-`None` → the arm is unreachable → present-at-both semantics; when head equals base's copy and covers live the run **passes** (probe P2: `--base HEAD` → `exit=0 reason=pass`). The flag is a local escape hatch — legitimate for the drain/`--print-baseline` workflow — but it means the property "absent at base" is defined by whatever the run resolves, and CI safety rests on the invocation at ci.yml:444 never passing `--base`. A base ref pointing at a commit carrying a WEAKENED `baseline_at` (see (j)) is the same hole one level down.
- One-line edit adding a member outside reach: `ratchet_base(root, a.base or "HEAD", rel)` — the base always carries the file; or `sha, base_text = ..., rel) ; base_text = base_text or ""` — `None` can never occur.

### (c) `ratchet_read` returning `''` vs `None` for empty/trailing-newline files

- Anchor: replay.py:1903-1911 — `None` iff the caught `ReadError`'s `__context__` is `FileNotFoundError`; otherwise the decoded text (`errors="replace"`); every other read failure propagates to `baseline-unreadable` exit 2.
- Covered: empty file → `""` → `is not None` → arm fires (pinned by `row_rt_reintroduced` on `bl-empty.tsv`; the `ratchet-reintroduced-content-weakened` mutant `if head_text and base_text is None:` is killed by exactly this case). `"\n"`-only, whitespace-only, UTF-8-damaged → non-`None` → fires. Oversized (`>MAX_READ`), device, dir, out-of-tree symlink → exit 2.
- NOT covered by the arm (inert): a committed **dangling symlink** at the path — `os.open` fails ENOENT → `None` → reads as HEAD-absent → `elif new:` → `new-pair` when live is non-empty, **pass** when live is empty (probe P4). It is "present at HEAD" in git terms but carries zero baseline lines, so nothing is adopted; a later commit making the link resolvable flips it to non-`None` and the arm fires then.
- One-line edit adding a member outside reach: `except ReadError as e: return None` (drop the `isinstance(e.__context__, FileNotFoundError)` gate) — every unreadable file collapses to "absent", skipping both the arm AND `baseline-unreadable`.

### (d) `baseline_split` callers

- Callers: replay.py:2016 (`head_lines, final_nl`), replay.py:2042 (`base_set`), replay.py:2022 (`keep` in `--print-baseline` reuses `head_lines`). `baseline_split(None)` → `([], True)`; `baseline_split("")` → `([], True)`; `baseline_split("x\n\n")` keeps a trailing `""` line (only one trailing empty segment is popped).
- Covered: the arm keys on `*_text is None` (presence), never on the split output (content), so no split behavior can launder the state. `""` and `None` split identically but are distinguished where it matters — the arm's predicate.
- One-line edit adding a member outside reach: none at `baseline_split` itself — it is content-level. The adjacent edit `head_lines, final_nl = baseline_split(head_text if head_text else None)` is how a content-weakening could creep in (equivalent to the pinned `ratchet-reintroduced-content-weakened` mutant).

### (e) The `head_text is None and base_text is not None` (baseline-deleted) sibling arm

- Anchor: replay.py:2061-2063 — `if new and head_text is None and base_text is not None:` … `elif new:` (2064).
- Behavior: fires only when `new` (live minus head baseline) is non-empty; with head absent `head_set` is `∅` so `new = live` — i.e. fires iff anything is live. Live-empty + baseline deleted → pass (the strict-zero end state, `row_rt_deleted_end`). Outside the new arm's reach BY DESIGN — it is the opposite state-row; mutants pin both directions (`ratchet-deleted-baseline-tolerated`, `ratchet-deleted-baseline-always-refused`).
- Under the new arm's state (head present, base absent) the `elif new:` branch fires too, printing each uncovered live pair as `new-pair` detail beneath the reintroduced marker — deliberate co-firing (pinned by `row_rt_reintroduced_newpair`; CTO ruling in `decision-challenges.md` row 3).
- One-line edit adding a member outside reach: `if head_text is None and base_text:` — `base_text=""` (empty file at base) falls through to `new-pair` (still exit 1, wrong name); or swapping `elif new:` to `else:` would make order findings unreachable.

### (f) RATCHET_ORACLE / `oracle-inputs-changed` paths

- Anchors: `RATCHET_ORACLE` tuple replay.py:1755-1758 (includes `RATCHET_BASELINE` — kept post-deletion per spec row 15); `ratchet_oracle(touched, rel)` replay.py:1898-1900 (appends `rel`, so a `--baseline` override file is also announced); computed at 2039 (and best-effort at 2024-2029 under `--print-baseline`); printed at 2098-2100.
- Verdict reach: NONE — `oracle` is appended to `out`/`rep`, never to `findings`; it cannot produce or suppress an exit 1. `touched` comes from `git diff --name-status -z --no-renames <sha> HEAD` (replay.py:1886-1895) — a committed-diff view only: an UNTRACKED baseline file at `rel` fires the arm but is NOT named in the notice (probe P6: `baseline-reintroduced` fired, no `oracle-inputs-changed` line).
- One-line edit adding a member outside reach: `ratchet_oracle(touched, RATCHET_BASELINE)` (drop `+ (rel,)`) — a `--baseline` override path stops being announced; cosmetic, not adoption.

### (g) The `accept.tsv` `path-untracked` stale mechanism (the 42 deleted rows)

- Anchors: `judge_rules` replay.py:1603-1604 — `elif path not in tracked: stale_entries(..., "path-untracked")` → `c.stale` → `stale-accept` finding at replay.py:2052-2056 (exit 1); `load_accept` replay.py:1487-1531; default-path wiring `apath = a.accept or (default_accept if os.path.lexists(default_accept) else "")` at replay.py:2000 (`lexists` so a dangling symlink takes the accept branch, then `os.path.exists` inside `load_accept` yields "no exemptions").
- The 42 rows exempted `scripts/ci-pr-affected-audit.baseline.tsv` as a mere-name path for `ci-pr-affected-replay-{a,b,c}`; deleting the file makes every one of them `path-untracked` → `stale-accept` → exit 1 — hence the same-commit removal (correct coupling, spec row 9).
- Verdict reach of accept rows on the arm: NONE. Accept rows only shrink `miss`/`live` (exempt pairs); the reintroduced arm never consults `live`. A `--accept` file covering every pair cannot launder a re-added baseline; and a leftover row FOR the baseline path is itself `stale-accept` — both directions refuse.
- One-line edit adding a member outside reach: `elif path not in tracked: continue` — accept rows on absent files go silent (still cannot touch baseline state, but the orphan-row alarm the 42-row deletion relied on would die).

### (h) `--print-baseline` (the write-side drain tool)

- Anchor: replay.py:2019-2036 — runs BEFORE the verdict block; exits 0 (or 2 `census-degraded` on unaudited/stale/malformed-accept). `keep = live if head_text is None else sorted(set(head_lines) & set(live))` — under the reintroduced state it prints `head ∩ live`, never more (probe P5: `exit=0`, printed the baseline line). Writes nothing; stdout is pure baseline bytes.
- Verdict reach: none — it is a byte-printer, and anything an operator redirects into the path is refused by the next verdict run (state is path-presence, not content). It is however the only exit-0 path that runs under the reintroduced state, so a CI invocation mutated to add `--print-baseline` would turn the job green while emitting candidate bytes — flag-level member, see (i).
- One-line edit adding a member outside reach: `open(os.path.join(root, rel), "w").write(...)` — the exact `ratchet-print-baseline-writes-the-file` mutant (pinned, killed by `row_rt_pb_prune`); or `keep = live` (`ratchet-print-baseline-grows`, also pinned).

### (i) The CI invocation and the advisory surface

- Anchor: `.github/workflows/ci.yml:444` — `python3 -I scripts/ci-pr-affected-replay.py ratchet --report "$full"`; no `--baseline`/`--base`/`--accept`/`--print-baseline`. `fetch-depth: 2` (428) is the documented minimum for `HEAD^1`. `continue-on-error: true` (420) — the verdict is exit 1 but does not gate merge (advisory by design; PR3b #10859).
- Members outside the arm's reach: the flag surface itself. Any future diff adding `--base <file-carrying ref>` (see (b)) or `--print-baseline` (see (h)) to this line changes which code path runs. ci.yml is in `RATCHET_ORACLE`, so the diff prints `oracle-inputs-changed` — advisory notice only.
- One-line edit adding a member outside reach: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base "$(git merge-base HEAD^1 HEAD^2 || echo HEAD)" > "$out"` — resolves to a carrying tree on a re-add PR.

### (j) The merge-base helper (`baseline_at`, `resolve_base`, `InfraError`)

- Anchors: `ratchet_load` replay.py:1848-1865 — loads `lint-ratchet.py` from the BASE commit (`git show <sha>:<path>`), requiring exactly `baseline_at` + `InfraError` (1862); a base without the file or with an uncompilable one → `internal` exit 2. `baseline_at` lint-ratchet.py:528-538 — `None` iff `ls-tree` prints nothing; `git show` text otherwise (empty blob → `""`, symlink → target text, gitlink → "Subproject commit", tree → listing).
- Covered: the PR tree's helper never runs (pinned by `rt_p_weak`/`row_rt_helper_pr_tree_ignored` — the appended `baseline_at → None` and `resolve_base → "HEAD"` are ignored). `resolve_base` (lint-ratchet.py:453) is NOT called by `ratchet_base` (own `rev-parse` at replay.py:1875 — pinned by mutant `ratchet-base-is-merge-base-with-origin-main`); a PR editing `resolve_base` reaches nothing here.
- NOT covered: a base whose OWN helper is weakened — the two-step escape the oracle notice exists for (weaken `baseline_at` on main in PR-1 [oracle names lint-ratchet.py], re-add the baseline in PR-2 [helper returns non-`None` → present-at-both → equality could pass]). The helper is the arm's eyes for "absent".
- One-line edit adding a member outside reach: `if not listed.stdout.strip(): return ""` inside `baseline_at` (on a future main-side helper change) — `base_text` can never be `None`, the arm can never fire.

### (k) `ratchet_changed` / `added` / `touched`

- Anchor: replay.py:1886-1895, consumed at 2038-2039 and by `ratchet_new_entry` (1929-1947). `added` feeds only the cause sentence of a `new-pair` entry; `touched` feeds only `ratchet_oracle`. No verdict reach — they name, never decide.
- One-line edit adding a member outside reach: `--diff-filter=A` dropped from the status parse would mislabel cause text only.

### (l) The census side (`live`): `--list`, `--accept`, `audit_census`, floors

- Anchors: `load_rows` replay.py:1732-1745 (`--list FILE` else `run_selector`, which honors the `PR_AFFECTED_REPLAY_TEST_ALL` seam at 355); `audit_census` 1635; `ratchet_floors` 1813-1845 (summary grammar, fallback=none, short/bad rows, rows-vs-of, faults, non-zero census) → all exit 2 before any baseline read.
- Verdict reach on the arm: NONE — `live` enters `new`/`gone`/`stale-line`/`grown`, never the state predicate. A forged `--list` shrinking live to empty can erase `new-pair` detail but not `baseline-reintroduced` (fires regardless; probe of the code path is trivial — the arm has no `live` term).
- One-line edit adding a member outside reach: `pairs = {}` — kills `live` entirely (kills new-pair/stale-line with it; reintroduced survives — the arm is the only live-independent verdict besides the file-format checks).

### (m) Marker / report / cap plumbing

- Anchors: `ratchet_marker` 1950, `ratchet_report` 1954-1963, `RATCHET_CAP` 1754/2083-2086, `names & {...}` remedy tail 2089-2097, `code = 1 if findings else 0` 2101. Marker reason = `findings[0][0]` — an earlier co-firing class (`unaudited`, `star-row`, `stale-accept`) changes the marker string, never the exit code (matches the documented ORDER at replay.py:148-150). ci.yml's sed pattern `reason=\([a-z0-9-]*\)` and the probe's `MARKER_RE` both accept `baseline-reintroduced`.
- One-line edit adding a member outside reach: `code = 1 if findings else 0` → `code = 0` — global, not arm-specific.

### (n) Adjacent consumers of baseline state (outside `ratchet` entirely)

- `scripts/followthroughs/ratchet-observation-window-10865.sh:477-510` — reads the baseline via the contents API at the PR3a merge commit and at main tip, set-compares lines; "absent at the tip is the end state" (498). A re-added baseline that is a SUBSET of the merge-commit baseline yields `added=""` → `grew=0` → NOT flagged — the probe catches growth, not re-addition (its (h) is a different surface; the ratchet arm is the only strict-zero guard).
- `scripts/ci-pr-affected-audit.accept.tsv` — the 42 `path-untracked` rows removed in-diff (see (g)); the header comment still names the ratchet.
- `.gitattributes` — the `text eol=lf linguist-generated=true` line for the baseline path is removed; a re-add gets platform EOL → CRLF lines would additionally fail `stale-line`/`baseline-order` — still refused, reintroduced fires first. Consistent.
- `lint-ratchet.py`'s own user-scope baseline machinery (`USER_BASELINE`, `classify_user` ~1294-1349) — a different file, different check, no shared state.

## Assembly verdict (one sentence)

Within the CI invocation (no flags) the assembly equals the named property — `head_text is not None and base_text is None` is "readable bytes present in the checkout" × "no tree entry of any type at the resolved base" and it exits 1 unconditionally, empty files included — but the guard's reach is narrower than the property's letter on two named edges: `--base` can resolve to a file-carrying tree and exit 0 (probe P2), and a committed dangling symlink reads as absent rather than present (probe P4).

## Uncovered / boundary paths — P1 candidates

1. **P1 — `--base` escape hatch is the only code-level adoption path left open.** `ratchet --base <any commit carrying the file>` bypasses the arm entirely and can exit 0 (probe P2: `exit=0 reason=pass` with the baseline equal to live). Today only an operator/local run or a ci.yml edit can reach it (ci.yml is an oracle input but the job is `continue-on-error`). If the intended property is "a re-added baseline can never pass ANYWHERE", the flag needs a second invariant — e.g. the arm could also consult `git diff`-membership (`rel ∈ touched` ∧ `ls-tree` empty at HEAD^1 ignores `--base`) — or accept the flag as documented escape hatch.
2. **P1 — two-step helper weakening.** The arm's `base_text is None` inherits whatever `baseline_at` the resolved BASE commit carries (replay.py:1879-1881); a weakened helper landed on main first turns every future re-add into present-at-both equality. Mitigation exists (helper-from-base + oracle notice + review) but it is procedural, not structural — `ratchet_load` checks only name-presence (`baseline_at`, `InfraError`), not semantics.
3. **P1(adjacent) — the observation-window probe does not see a subset re-add.** `ratchet-observation-window-10865.sh` (h) compares tip vs merge-commit as a set and treats "absent at tip" as the end state; a re-added baseline ⊆ the PR3a-merge baseline registers `baseline_grown=0`. Fine while the ratchet job itself is the guard, worth noting if the probe's window is ever read as "no baseline activity since merge".

Boundary members verified but judged inert (not P1): committed dangling symlink at the path → `None` → `new-pair`/pass but carries no lines (P4); dir/gitlink/symlink/empty-blob at base → `grown` or equality arms, still exit 1 (P7/P8); untracked working-tree file → fires the arm (P6, stricter than git-presence); `--print-baseline` under the state → exit 0 byte-printer, prune-only, non-verdict (P5).
