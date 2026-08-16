#!/usr/bin/env python3
"""Assert the Phase 3 alert drain from the committed lockfiles (ADR-191, #7084).

Deterministic and available at merge time -- the Dependabot alert count is a LAGGING
mirror of this same fact, so this is the assertion and the API re-query is corroboration.

Thresholds are keyed per MAJOR LINE, not per package. js-yaml and brace-expansion each
ship two supported majors with SEPARATE advisories (js-yaml 3.15.1 and 4.3.1;
brace-expansion 1.1.16 and 5.0.9), so a single per-package minimum would compare a
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
    ("web-platform", "brace-expansion", 5, "5.0.9"),
    ("web-platform", "@opentelemetry/propagator-jaeger", 2, "2.9.0"),
    ("root", "js-yaml", 3, "3.15.1"),
    ("root", "js-yaml", 4, "4.3.1"),
    ("root", "brace-expansion", 1, "1.1.16"),
    ("pencil-setup", "hono", 4, "4.12.34"),
    ("pencil-setup", "@hono/node-server", 1, "1.19.15"),
    ("pencil-setup", "ip-address", 10, "10.3.1"),
    ("pencil-setup", "fast-uri", 3, "3.1.5"),
]

# Deliberately left OPEN, never dismissed: `next` pins these nested copies and only a
# next 15.x -> 16.x major can move them. The top-level copies are already patched.
DEFERRED = [("web-platform", "postcss", "node_modules/next/node_modules/postcss"),
            ("web-platform", "sharp", "node_modules/next/node_modules/sharp")]


def ver(s):
    """Comparable version key. A prerelease sorts BELOW its release.

    `re.findall(r"\d+", "4.13.0-beta.1")[:3]` yields (4,13,0) -- identical to the release --
    so a prerelease below a patched floor would compare equal and read OK. The trailing
    flag makes the release sort strictly higher.
    """
    nums = tuple(int(x) for x in re.findall(r"\d+", s)[:3])
    nums = nums + (0,) * (3 - len(nums))
    is_release = 0 if re.search(r"[-+]", s) else 1
    return nums + (is_release,)


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
            if k.endswith("node_modules/" + pkg) and v.get("version")
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
    MIN_ROWS = 17
    if len(REQUIRED) < MIN_ROWS:
        failures.append(
            f"the reconciliation table has {len(REQUIRED)} rows, below the floor of {MIN_ROWS}. "
            f"Rows were deleted -- a clean result from this run means nothing.")
    # The floor that matters sits on rows that RESOLVED to a real installed version --
    # the only set that is non-empty in the passing state. `checked` and `len(REQUIRED)`
    # are both populated by construction and cannot detect a row that matches nothing.
    MIN_RESOLVED = 17
    if resolved < MIN_RESOLVED:
        failures.append(
            f"only {resolved} of {len(REQUIRED)} rows resolved to an installed version, "
            f"below the floor of {MIN_RESOLVED}. A row that matches nothing prints "
            f"'(absent)' and would otherwise pass -- check for a renamed or mistyped package.")
    if checked != len(REQUIRED):
        failures.append(f"evaluated {checked} of {len(REQUIRED)} rows -- the loop did not complete")

    # COMPLETENESS. Per-major keying is what lets a watched package carry an unwatched
    # major: a `brace-expansion@1.1.11` nested under a new dependency in web-platform sits
    # below the 1.x floor this table already declares for root, yet no row covers it. So
    # every major of every watched package that is PRESENT must have a row -- otherwise the
    # table's completeness is a coincidence of today's tree rather than an asserted property.
    watched = {pkg for _, pkg, _, _ in REQUIRED}
    covered = {(m, pkg, major) for m, pkg, major, _ in REQUIRED}
    for manifest, pkgs in packages.items():
        for key, meta in pkgs.items():
            version = meta.get("version")
            if not version:
                continue
            name = key.split("node_modules/")[-1]
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
