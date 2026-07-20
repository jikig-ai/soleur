# Full-repo census — tempfile-cleanup ownership (#6734, AC4)

Derived by committed command, not transcribed. Re-run any time:

```bash
git ls-files '*.sh' | wc -l                                    # files scanned
python3 scripts/lint-trap-tempfile-ownership.py --census        # class-b population
python3 scripts/lint-trap-tempfile-ownership.py                 # violations (rule a + c)
```

## Result at merge time

| Measure | Count |
|---|---|
| Tracked `*.sh` files scanned | **641** |
| Files allocating via `mktemp` (command position) | **289** |
| Class-b: allocates, no owning `EXIT`/`RETURN` trap | **102** |
| Rule (a) + rule (c) violations on this branch | **0** |

The high-water ratchet is pinned at 102 in
`scripts/lint-trap-tempfile-ownership.highwater`. CI asserts the live count never
exceeds it, so the accepted population can only shrink.

## Why these numbers differ from the plan's

The plan quoted 282 files / 121 class-b / 16 multi-trap. Every figure moved, and the
movement is the point — this is why the plan says to commit the derivation command rather
than the number:

- **282 → 289 allocating files.** `main` advanced during the work, and this PR adds test
  files that allocate.
- **121 → 102 class-b.** Two corrections, in opposite directions. Recognising
  `trap … RETURN` as ownership moved ~20 files OUT (they were never untrapped — the rule
  could not see their cleanup). Fixing `content-publisher.sh` and
  `skill-freshness-aggregate.sh`, and adding owning traps to this PR's own new harnesses,
  moved several more out.
- **Multi-trap count is no longer tracked.** It existed to size rule (b), which was
  rejected as incoherent (ADR-129 § Alternatives Considered).

## What the census does NOT cover

Rule (c) is a *file-level* question: does this file register any owning trap? It cannot
see an allocation that is untrapped **within** a file that traps something else. That is
rule (b) territory, deliberately not implemented. One real instance of exactly that shape
was found by hand during this work and filed as **#6760** (`run-scan.sh` leaks one runtime
directory per invocation; 7,603 observed). It is a retention-policy problem rather than a
missing trap, so no lint rule here would have been the right place to catch it.
