# Drain-guard ratchet: fixture parity + `.get()` vs fail-loud manifest checks

Two traps a `scripts/assert-dependabot-drain.py` ratchet hits that no gate warned about:

1. **Fixture parity.** `assert-dependabot-drain.test.sh` synthesizes a minimal lockfile
   tree; adding REQUIRED rows for packages the fixture lacks self-reds the CONTROL
   (resolved < MIN_RESOLVED). Every new watched package must also be added to each
   manifest's `pkgs()` entries at `<major>.999.999`, and the `MIN_ASSERTIONS` floor
   ratcheted to the new arm count in the same commit.
2. **`packages.get(manifest, {})` is correct ONLY where mass-absence is backstopped.**
   In the REQUIRED loop it is load-bearing (a deleted LOCKS entry must reach MIN_LOCKS,
   not KeyError). In MUST_STAY_ABSENT/ABSENT_PATH_ANCHOR a missing manifest means the
   absence assertion checks nothing — there `manifest not in packages` must fail
   explicitly, and needs its own mutate arm.

Also: a Tool-rejected exec (filing gate) refuses the WHOLE command — side effects
earlier in the same `&&` chain (a sed checkbox update) never ran; re-run them after
the refused part is fixed.
