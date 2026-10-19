# Learning: git C-quotes `"`, `\` and control bytes regardless of core.quotePath=false — extension-anchored ls-files filters must carry a quoted-name arm

## Problem

`_th_root_corpus` filtered `git ls-files` output for dir-less corpus members
with `$`-anchored extension regexes (`/\.test\.sh$/`, `/\.sh$/`). The
structural-enumeration review seat found the evasion class: a dir-less file
whose NAME carries `"`, `\`, or a control byte (`x<TAB>y.test.sh`) is
C-quoted by git's `quote_path` REGARDLESS of `-c core.quotePath=false` —
`core.quotePath` governs only bytes ≥0x80. The emitted line is
`"x\ty.test.sh"`, the trailing `"` defeats the `$` anchor, and the member
silently escaped the coverage census — a silent hole in exactly the guard
whose job is catching unrepresentable names.

## Solution

Two additional disjoint arms mirror the plain ones: `NF<2 &&
/^".*\.test\.sh"$/` and `NF<2 && /^".*\.sh"$/ && !/\.test\.sh"$/`. The
`NF<2` stays correct inside quotes because a real `/` can never appear
escaped inside a filename (a quoted line with `/` is genuinely dir-ful).
Each arm is independently mutation-killable: fixture `x<TAB>y.test.sh`
(arm 3) and a `_th_fn_mut` deaden row for arm 4 keep every arm load-bearing.

The same class recurs anywhere a consumer anchors on emitted bytes rather
than the underlying names — `_TH_ROOTS`' `awk -F/ 'NF>1{print $1}'` mints a
phantom root token `"x\ty` for a control-byte dir name (recorded as a
comment; the verdict stays correct because the diff lines are equally
unmatchable — fail-loud direction).

## Key Insight

`git ls-files` (and `diff`/`status` path channels) do not promise unquoted
output under `core.quotePath=false` — they promise high-byte passthrough.
Any grep/awk filter anchored at line-end (`\.sh$`, extension suffixes) has a
blind spot at `"…<ext>"` and must either normalize first or carry the quoted
arm. A guard whose detection domain is derived bytes must enumerate the
producer's actual emission grammar, not the logical filenames.

## Tags
category: test-failures
module: affected-suite-selection
