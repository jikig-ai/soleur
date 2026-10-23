# Learning: a "counting wrapper" that subclasses the type it wraps leaks every C-level fast path — build a delegating plain object instead

## Problem

#10724's fix wrapped `index.paths`/`index.tracked` in counting probes so a mutation-battery mutant could not hide
O(paths) work inside C calls. `_SeqProbe` (plain object, counting `__iter__`/`__getitem__`) was sound; `_SetProbe` was
written as a `set` subclass — and a subclass inherits the C-level fast paths that never consult `__iter__`:
`.copy()`, `set(p)`, `frozenset(p)`, `p | s`, `.union()/.intersection()/.difference()` all returned hits=0. A one-edit
spelling (`"\n".join(index.tracked.copy())`) silently materialized the collection and fell back to the flaky CPU bound —
the exact survivor class the PR existed to kill. Four independent review seats verified the hole by execution; the
original CTO ruling's "`.copy()` crashes loudly" was true only for `_SeqProbe` (which has no `copy`).

## Fix

Make the wrapper a plain object that delegates: `__len__`, `__contains__` (O(1) membership stays uncounted — that is the
correct boundary), and a counting `__iter__`. Then `set(x)`/`frozenset(x)`/`sorted(x)`/`join(x)` all dispatch to the
counted `__iter__`, `.copy()` → `AttributeError` (loud crash), `x | s` → `TypeError` (loud). Also count EVERY
`__getitem__` on the sequence probe (drop slice-only): otherwise `reversed(x)` and an int-index genexpr escape via
uncounted C-level indexing.

## Rules of thumb

- A counting/instrumenting wrapper on a builtin container must NOT subclass the builtin: every C-level fast path of the
  base type is an uncounted escape. Delegate over `self._d` instead.
- Enumerate the escape family by level: Python-level (`__iter__`, `__getitem__`), C-level fast paths of the base type
  (`copy`, constructors, operators), and object-model internals (`__dict__`, `_d`, `copy.copy`). The first two classes
  must be closed by construction; the last is an honest residual only when it needs insider knowledge or a second edit.
- A "`X` crashes loudly" claim is per-probe — verify it against EACH wrapped type, not the design's flagship one.
