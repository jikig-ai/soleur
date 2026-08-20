#!/usr/bin/env python3
"""Assert the Phase 3 alert drain from the committed lockfiles (ADR-191, #7084).

Deterministic and available at merge time -- the Dependabot alert count is a LAGGING
mirror of this same fact, so this is the assertion and the API re-query is corroboration.

Thresholds are keyed per MAJOR LINE, not per package. js-yaml and brace-expansion each
ship two supported majors with SEPARATE advisories (js-yaml 3.15.1 and 4.3.1;
brace-expansion 1.1.18, 2.1.4 and 5.0.9), so a single per-package minimum would compare a
correctly-patched 3.x copy against a 4.x threshold and report a false vulnerability.
"""
import json, re, sys

LOCKS = {
    "web-platform": "apps/web-platform/package-lock.json",
    "root": "package-lock.json",
    "pencil-setup": "plugins/soleur/skills/pencil-setup/scripts/package-lock.json",
    # The FOURTH tracked lockfile. Its omission made this script disagree with
    # lint-dual-lockfile.sh, whose MIN_PACKAGE_LOCK_DIRS=4 floor names spike explicitly --
    # so one guard asserted four directories exist while this one asserted three were clean,
    # and a vulnerable copy here was asserted clear by nobody.
    "spike": "spike/package-lock.json",
}

# Deleting an entry from LOCKS exits 0. `packages[manifest]` is only reached for rows
# that NAME the manifest, so dropping "spike" -- which no row names, because its tree is
# covered by the completeness sweep rather than by the table -- removed a whole lockfile
# from the scan in silence. That is the precise regression the comment above says was
# fixed; repointing a path IS caught, deletion was not. Mirrors lint-dual-lockfile.sh's
# MIN_PACKAGE_LOCK_DIRS=4.
MIN_LOCKS = 4

# Every package this table is responsible for. Declared, not derived: substituting one
# row's package name for another REAL package left len(REQUIRED) at 19 and both count
# floors satisfied while silently dropping the original from the watched set. A mistyped
# name deflates `resolved` and IS caught; a substitution was not.
WATCHED_PACKAGES = {
    "@hono/node-server",
    "@opentelemetry/propagator-jaeger",
    "brace-expansion",
    "fast-uri",
    "hono",
    "ip-address",
    "js-yaml",
    "nanoid",
    "undici",
}

# (manifest, package, major-line, minimum patched) -- the Phase 3 reconciliation table.
REQUIRED = [
    ("web-platform", "nanoid", 3, "3.3.18"),
    ("web-platform", "js-yaml", 3, "3.15.1"),
    ("web-platform", "js-yaml", 4, "4.3.1"),
    ("web-platform", "hono", 4, "4.12.34"),
    ("web-platform", "@hono/node-server", 1, "1.19.15"),
    ("web-platform", "ip-address", 10, "10.3.1"),
    ("web-platform", "fast-uri", 3, "3.1.5"),
    ("web-platform", "undici", 7, "7.29.0"),
    # Three rows, not one: #1327 removed the blanket `brace-expansion` override, so
    # web-platform legitimately resolves this package on major lines 1, 2 and 5 again
    # (minimatch@3 needs ^1, rimraf's minimatch@9 needs ^2, minimatch@10 needs ^5).
    # Floors are the UNION of all SEVEN published advisories, not GHSA-v6h2-p8h4-qcjw
    # (LOW) alone: GHSA-rgw5-rvv9-x895 (HIGH) makes <1.1.18 and <2.1.4 vulnerable.
    # FOUR of the seven are HIGH -- 3jxr, 832h, mh99, rgw5. An earlier version of this
    # comment said six advisories and three HIGH; it omitted GHSA-832h-xg76-4gv6
    # (HIGH, <1.1.7). Re-derived 2026-08-20 from
    # `gh api "/advisories?ecosystem=npm&affects=brace-expansion"`.
    # No 3.x or 4.x release clears all seven, so neither line is encodable here.
    # That is deliberately weaker than "no patched 3.x exists": GHSA-rgw5 names 3.0.6
    # as its own first_patched and npm ships it under dist-tag maintenance-v3, but
    # GHSA-3jxr's `>=3.0.0 <5.0.7` range swallows it. The mirror of this table in
    # apps/web-platform/test/eslint-config.test.ts carries the same seven advisories;
    # they must move together.
    ("web-platform", "brace-expansion", 1, "1.1.18"),
    ("web-platform", "brace-expansion", 2, "2.1.4"),
    ("web-platform", "brace-expansion", 5, "5.0.9"),
    ("web-platform", "@opentelemetry/propagator-jaeger", 2, "2.9.0"),
    ("root", "js-yaml", 3, "3.15.1"),
    ("root", "js-yaml", 4, "4.3.1"),
    ("root", "brace-expansion", 1, "1.1.18"),  # was 1.1.16: GHSA-rgw5-rvv9-x895 covers <1.1.18
    ("pencil-setup", "hono", 4, "4.12.34"),
    ("pencil-setup", "@hono/node-server", 1, "1.19.15"),
    ("pencil-setup", "ip-address", 10, "10.3.1"),
    ("pencil-setup", "fast-uri", 3, "3.1.5"),
]

# THE FLOOR UNDER THE FLOOR. The structural check in main() asserts a row's minimum sits
# on the major line it declares and is above the bare X.0.0 -- which kills "0.0.0" and
# "7.0.0", and nothing else. It does NOT kill "X.0.1", nor a revert to a REAL but stale
# first_patched_version, and those are the drifts that actually happen: rewriting every
# threshold to <major>.0.1 exited 0 with a clean summary, and reverting the two
# brace-expansion rows to 1.1.16 -- the value #1327 itself replaced, so the highest-
# probability drift on this file -- silently re-admitted 1.1.17, which GHSA-rgw5-rvv9-x895
# (HIGH) covers.
#
# So the security-critical lines carry an explicit anchor. This is a mirror and it is
# supposed to be: lowering a floor now requires editing two places that disagree loudly,
# and scripts/assert-dependabot-drain.test.sh source-greps these values so lowering BOTH
# is a three-file edit. Add an anchor whenever an advisory forces a floor up.
FLOOR_ANCHORS = {
    ("brace-expansion", 1): "1.1.18",   # GHSA-rgw5-rvv9-x895 (HIGH)
    ("brace-expansion", 2): "2.1.4",    # GHSA-rgw5-rvv9-x895 (HIGH)
    ("brace-expansion", 5): "5.0.9",    # GHSA-rgw5-rvv9-x895 (HIGH)
    ("js-yaml", 3): "3.15.1",
    ("js-yaml", 4): "4.3.1",
    ("undici", 7): "7.29.0",
    ("nanoid", 3): "3.3.18",
    ("ip-address", 10): "10.3.1",
    ("fast-uri", 3): "3.1.5",
    ("hono", 4): "4.12.34",
    ("@hono/node-server", 1): "1.19.15",
    ("@opentelemetry/propagator-jaeger", 2): "2.9.0",
}

# Deliberately left OPEN, never dismissed: `next` pins these nested copies and only a
# next 15.x -> 16.x major can move them. The top-level copies are already patched.
DEFERRED = [("web-platform", "postcss", "node_modules/next/node_modules/postcss"),
            ("web-platform", "sharp", "node_modules/next/node_modules/sharp")]


def ver(s):
    r"""Comparable version key. A prerelease sorts BELOW its release.

    `re.findall(r"\d+", "4.13.0-beta.1")[:3]` yields (4,13,0) -- identical to the release --
    so a prerelease below a patched floor would compare equal and read OK. The trailing
    flag makes the release sort strictly higher.
    """
    nums = tuple(int(x) for x in re.findall(r"\d+", s)[:3])
    nums = nums + (0,) * (3 - len(nums))
    is_release = 0 if re.search(r"[-+]", s) else 1
    return nums + (is_release,)


def entry_name(key, meta):
    """The package a lock entry actually installs.

    npm aliases put a DIFFERENT name at a path: this very lockfile carries
    node_modules/string-width-cjs whose `name` is string-width. Keying on the path alone
    -- which all three matchers used to do -- means an aliased copy is invisible to every
    guard here. A node_modules/brace-expansion-cjs pinned at 1.1.11 matched nothing and
    was reported clean. npm itself resolves the `name` field first; so does this.
    """
    return meta.get("name") or key.split("node_modules/")[-1]


def read_packages(path):
    # Context-managed rather than `json.load(open(path))`: the bare form leaves four
    # lockfile handles open until the interpreter's refcount happens to drop them, which
    # is CPython-specific behaviour rather than a guarantee. Flagged by github-code-quality
    # on this PR.
    with open(path) as fh:
        return json.load(fh)["packages"]


def main():
    packages = {name: read_packages(path) for name, path in LOCKS.items()}
    failures = []
    checked = 0
    resolved = 0
    print(f"{'manifest':14s} {'package':34s} {'line':>5s} {'required':>10s}  found")
    for manifest, pkg, major, minimum in REQUIRED:
        found = sorted({
            v["version"] for k, v in packages[manifest].items()
            if "node_modules/" in k and entry_name(k, v) == pkg and v.get("version")
            and ver(v["version"])[0] == major
        }, key=ver)
        checked += 1
        if not found:
            # Absent is fine on its own: the major line simply is not installed here.
            # But it must not count toward the floor -- a mistyped package name produces
            # exactly this output, so a floor on `checked` is satisfied by rows that
            # resolved to nothing. Renaming all 17 rows to nonexistent packages exited 0
            # reporting "17 rows clear" before `resolved` existed.
            print(f"{manifest:14s} {pkg:34s} {major:5d} {'>=' + minimum:>10s}  (absent)")
            continue
        resolved += 1
        worst = found[0]
        ok = ver(worst) >= ver(minimum)
        if not ok:
            failures.append(f"{manifest}: {pkg}@{worst} < {minimum}")
        print(f"{manifest:14s} {pkg:34s} {major:5d} {'>=' + minimum:>10s}  {found} "
              f"{'OK' if ok else '*** VULNERABLE ***'}")

    # Anti-vacuity. The floor is an ABSOLUTE constant, not len(REQUIRED): comparing the
    # evaluated count against the table's own length is a tautology that cannot fail, so
    # deleting the table would report "0 rows clear" and exit 0. (Measured -- that mutation
    # survived the first version of this check.)
    MIN_ROWS = 19  # main's 17 + the two brace-expansion major lines #1327 restored
    if len(REQUIRED) < MIN_ROWS:
        failures.append(
            f"the reconciliation table has {len(REQUIRED)} rows, below the TABLE-SIZE floor of {MIN_ROWS}. "
            f"Rows were deleted -- a clean result from this run means nothing.")
    # The floor that matters sits on rows that RESOLVED to a real installed version --
    # the only set that is non-empty in the passing state. `checked` and `len(REQUIRED)`
    # are both populated by construction and cannot detect a row that matches nothing.
    MIN_RESOLVED = 19  # main's 17 + the same two rows, both of which resolve
    if resolved < MIN_RESOLVED:
        failures.append(
            f"only {resolved} of {len(REQUIRED)} rows resolved to an installed version, "
            f"below the RESOLVED-ROW floor of {MIN_RESOLVED}. A row that matches nothing prints "
            f"'(absent)' and would otherwise pass -- check for a renamed or mistyped package.")
    # `checked != len(REQUIRED)` used to sit here. It was the exact tautology the MIN_ROWS
    # comment fourteen lines above mocks: `checked` is incremented unconditionally once per
    # iteration over REQUIRED and nothing breaks out of the loop, so it could not fail.
    # MIN_ROWS and MIN_RESOLVED carry the real load.
    for pkg_major, anchor in sorted(FLOOR_ANCHORS.items()):
        pkg, major = pkg_major
        rows = [m for m in REQUIRED if m[1] == pkg and m[2] == major]
        if not rows:
            failures.append(
                f"FLOOR_ANCHORS pins {pkg} line {major} at >={anchor}, but no row covers it. "
                f"The row was deleted or retargeted -- restore it, or drop the anchor "
                f"deliberately and say why.")
            continue
        for manifest, _, _, minimum in rows:
            if ver(minimum) < ver(anchor):
                failures.append(
                    f"{manifest}: the {pkg} line-{major} floor was LOWERED to {minimum!r}, "
                    f"below the anchored {anchor!r}. A floor moves DOWN only when an advisory "
                    f"is withdrawn -- re-derive from the advisory feed and move the anchor in "
                    f"the same commit, or this is a silent re-admission of a patched CVE.")
    if len(LOCKS) < MIN_LOCKS:
        failures.append(
            f"only {len(LOCKS)} lockfiles are read, below the MANIFEST floor of {MIN_LOCKS}. A manifest "
            f"was dropped from LOCKS -- its tree is now asserted clear by nobody, which is the "
            f"regression the 'spike' entry was added to close.")

    # THE THRESHOLD, not the count. MIN_ROWS and MIN_RESOLVED both floor how MANY rows
    # exist and resolve; nothing floored the fourth tuple element, which is the only
    # thing the table exists to enforce. Setting all 19 thresholds to "0.0.0" printed a
    # confident clean summary and exited 0. This check is structural rather than a second
    # copy of the table: a row's minimum must sit ON the major line the row declares, so
    # "0.0.0" fails every row whose major is not 0, and a correct table cannot false-fail.
    # It must also be a real patch level -- "7.0.0" on the undici row would clear the
    # major check while admitting every vulnerable 7.x. If a package's true
    # first_patched_version is ever exactly X.0.0, relax this deliberately and say why.
    for manifest, pkg, major, minimum in REQUIRED:
        m = ver(minimum)
        if m[0] != major:
            failures.append(
                f"{manifest}: the {pkg} row declares major line {major} but its minimum "
                f"{minimum!r} is on line {m[0]}. A threshold was zeroed or retargeted -- "
                f"a clean result from this run means nothing.")
        elif m[:3] <= (major, 0, 0):
            failures.append(
                f"{manifest}: the {pkg} row's minimum {minimum!r} is the bare {major}.0.0 "
                f"floor, which admits every vulnerable {major}.x. Encode the advisory's "
                f"first_patched_version.")

    declared = {pkg for _, pkg, _, _ in REQUIRED}
    if declared != WATCHED_PACKAGES:
        failures.append(
            f"the table's package set drifted from WATCHED_PACKAGES: "
            f"missing {sorted(WATCHED_PACKAGES - declared)}, "
            f"unexpected {sorted(declared - WATCHED_PACKAGES)}. A row's package name was "
            f"substituted -- the count floors cannot see that, because a substitution keeps "
            f"the count.")

    # COMPLETENESS. Per-major keying is what lets a watched package carry an unwatched
    # major: a `brace-expansion@1.1.11` nested under a new dependency in web-platform sits
    # below the 1.x floor this table already declares for root, yet no row covers it. So
    # every major of every watched package that is PRESENT must have a row -- otherwise the
    # table's completeness is a coincidence of today's tree rather than an asserted property.
    # WATCHED_PACKAGES rather than a second derivation of the same set: the two were
    # identical by construction, so the recomputation asserted nothing, and the equality
    # check above now pins them together.
    watched = WATCHED_PACKAGES
    covered = {(m, pkg, major) for m, pkg, major, _ in REQUIRED}
    for manifest, pkgs in packages.items():
        for key, meta in pkgs.items():
            version = meta.get("version")
            if not version or "node_modules/" not in key:
                continue
            name = entry_name(key, meta)
            if name not in watched:
                continue
            major = ver(version)[0]
            if (manifest, name, major) not in covered:
                failures.append(
                    f"{manifest}: {name}@{version} is present on major line {major}, which no "
                    f"row covers. Add ({manifest!r}, {name!r}, {major}, '<patched>') to the "
                    f"table or confirm the major is not affected.")
    for manifest, pkg, path in DEFERRED:
        if path not in packages[manifest]:
            failures.append(
                f"{manifest}: {path} is gone. The deferral of the {pkg} advisory rests on it "
                f"being a next-pinned nested copy; re-derive the deferral rather than assuming it.")

    print()
    if failures:
        print("DRAIN ASSERTION FAILED:")
        for f in failures:
            print("  -", f)
        return 1
    print(f"drain assertion: {checked} rows evaluated, {resolved} resolved to an installed "
          f"version (floor {MIN_RESOLVED}), across {len(LOCKS)} manifests; "
          f"{len(DEFERRED)} deferred advisories still present as next-pinned nested copies (expected).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
