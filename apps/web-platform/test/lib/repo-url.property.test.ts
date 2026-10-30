import { describe, expect, it } from "vitest";
import fc from "fast-check";
import { normalizeRepoUrl } from "@/lib/repo-url";

// Property-based suite (fast-check) — idempotency + output-contract classes
// over normalizeRepoUrl (its docstring states the contract: "Idempotent").
// Convention: on failure, shrink and pin the counterexample as a permanent
// it() labelled `// regression fixture: fast-check seed <seed> path <path>`.
// See apps/web-platform/test/README.md "Property-based tests".

// Non-URL-shaped inputs plus URL-shaped inputs with the suffix classes the
// normaliser owns: trailing "/", ".git" (any case, repeated), and the
// whitespace-reexposure corners a strip can open ("foo .git", "x /").
const suffixArb = fc.constantFrom(
  "",
  ".git",
  ".GIT",
  "/",
  ".git/",
  ".git.git",
  ".git.git/",
  "///",
  " .git",
  " /",
  // dot-segment exposure: a strip leaves `/.` or `/..`, which the next
  // call's URL parse resolves (also in percent-encoded form).
  "/..git",
  "/..git.git",
  "/%2e.git",
);
const urlishArb = fc.tuple(fc.webUrl(), suffixArb).map(([u, s]) => u + s);
const paddedArb = fc
  .tuple(fc.constantFrom(" ", "\t", "\n", "  "), urlishArb)
  .map(([pad, u]) => pad + u);
const inputArb = fc.oneof(fc.string(), urlishArb, paddedArb);

describe("normalizeRepoUrl — idempotency (property)", () => {
  // Pinned counterexamples: the `.git` strip can expose a trailing dot-segment
  // (`a/..git` → `a/..`) that URL parsing then collapses — #10716, surfaced by
  // fast-check seeds -590792931 and -1488952269.
  it.each(["http://a.aa/..git.git", " http://a.aa/..git.git/", "https://x.io/a/..git"])(
    "pinned #10716: %j is a fixpoint",
    (x) => {
      const once = normalizeRepoUrl(x);
      expect(normalizeRepoUrl(once)).toBe(once);
    },
  );

  it("normalize(normalize(x)) === normalize(x) over arbitrary + URL-ish inputs", () => {
    fc.assert(
      fc.property(inputArb, (x) => {
        const once = normalizeRepoUrl(x);
        expect(normalizeRepoUrl(once)).toBe(once);
      }),
    );
  });
});

describe("normalizeRepoUrl — flake counterexample pins (#10732, #10713)", () => {
  // regression fixture: counterexample from CI run 39506606768 (#10732), fast-check seed not recorded
  // regression fixture: counterexample from CI run 39462075257 (#10713), fast-check seed not recorded
  // Four of these fail on the pre-fixpoint code (commit 91594324ef): `.git` strip exposes a
  // dot-segment or an unparseable first pass keeps case the next pass lowers. The two
  // issue-named values (`http://a.aa/.` and `a://A`) are non-discriminating: they pass there
  // in isolation, because their failing contexts depended on the shrink path.
  it.each<[input: string, expected: string, discriminating: boolean]>([
    ["http://a.aa/.", "http://a.aa", false],
    ["http://a.aa/..git", "http://a.aa", true],
    ["a://A", "a://a", false],
    [" a://A .git", "a://a", true],
    ["a://A /", "a://a", true],
    [" a://A/..git", "a://a", true],
  ])("pinned: %j -> %j is a fixpoint (discriminating: %s)", (input, expected) => {
    const once = normalizeRepoUrl(input);
    expect(once).toBe(expected);
    expect(normalizeRepoUrl(once)).toBe(once);
  });
});

describe("normalizeRepoUrl — output contract (property)", () => {
  it("output is trim-stable and carries no stripped suffix residue", () => {
    fc.assert(
      fc.property(inputArb, (x) => {
        const out = normalizeRepoUrl(x);
        expect(out).toBe(out.trim());
        if (out.length > 0) {
          expect(out).not.toMatch(/\/+$/);
          expect(out).not.toMatch(/(\.git)+$/i);
        }
      }),
    );
  });

  it("URL-parseable inputs: scheme+host lowercased, path case preserved", () => {
    const schemeArb = fc.constantFrom("https", "HTTPS", "HtTpS");
    const hostArb = fc.constantFrom(
      "GitHub.com",
      "EXAMPLE.ORG",
      "gitlab.com",
    );
    // Paths end in an alphanumeric so the only thing the normaliser strips
    // is the generated suffix — keeps the expected value derivable.
    const pathArb = fc.constantFrom("/Foo/Bar", "/owner/repo", "/A/b/C");
    const cleanSuffixArb = fc.constantFrom(
      "",
      ".git",
      ".GIT",
      "/",
      ".git/",
      ".git.git",
    );
    fc.assert(
      fc.property(
        schemeArb,
        hostArb,
        pathArb,
        cleanSuffixArb,
        (scheme, host, path, suffix) => {
          const input = `${scheme}://${host}${path}${suffix}`;
          const expected = `${scheme.toLowerCase()}://${host.toLowerCase()}${path}`;
          expect(normalizeRepoUrl(input)).toBe(expected);
        },
      ),
    );
  });
});

// Regression fixtures: counterexamples found by this suite, pinned per the
// property-harness convention (shrink → permanent named case, never a
// pinned seed).
describe("normalizeRepoUrl — regression fixtures", () => {
  // regression fixture: fast-check seed -1467736381 path 11:0:0:0:0:0
  // Space inside the authority makes URL parsing throw; the string-only
  // `.git` strip then exposed a trailing space — output was not trim-stable
  // and the documented idempotence contract failed. SUT fix: re-trim after
  // the suffix strips.
  it("space before a stripped .git suffix leaves no trailing whitespace", () => {
    expect(normalizeRepoUrl("http://a.aa .git")).toBe("http://a.aa");
  });

  // regression fixture: fast-check seed -2133206446 path 17:0:0:0:0:0
  it("space before a stripped slash suffix leaves no trailing whitespace", () => {
    expect(normalizeRepoUrl("http://a.aa /")).toBe("http://a.aa");
  });
});

describe("normalizeRepoUrl — dot-segment exposure regression", () => {
  // regression fixture: fast-check seed 1186074284 path 59:0:0:0:0:1:0
  // Counterexample " http://a.aa/..git.git": the `.git` strip left `/.`, a
  // dot-segment the NEXT call's URL parse resolves to `/` — so one pass was
  // not a fixpoint (f(f(x)) !== f(x)). SUT fix: iterate the pipeline to a
  // fixpoint.
  it("a suffix strip that exposes a dot-segment is still idempotent", () => {
    const once = normalizeRepoUrl(" http://a.aa/..git.git");
    expect(normalizeRepoUrl(once)).toBe(once);
    expect(once).toBe("http://a.aa");
  });

  it.each([
    ["http://a.aa/..git.git", "http://a.aa"],
    ["https://h.io/o/..git", "https://h.io/o"],
    ["https://h.io/o/r/..git.git/", "https://h.io/o/r"],
    ["http://a.aa/...git", "http://a.aa"],
    // `%2e` is a dot-segment under the WHATWG URL rules: a regex patch that
    // only strips a literal `/.` or `/..` stays non-idempotent here.
    ["http://a.aa/x/%2e.git", "http://a.aa/x"],
  ])("dot-segment exposure %s is idempotent", (x, expected) => {
    const once = normalizeRepoUrl(x);
    expect(once).toBe(expected);
    expect(normalizeRepoUrl(once)).toBe(once);
  });

  it("many trailing /.git segments still converge (no fixed pass cap)", () => {
    const x = "https://github.com/o/r" + "/.git".repeat(50);
    const once = normalizeRepoUrl(x);
    expect(once).toBe("https://github.com/o/r");
    expect(normalizeRepoUrl(once)).toBe(once);
  });

  it("a long run followed by a non-matching character stays linear-time", () => {
    // The former /\/+$/ and /(\.git)+$/i were quadratic here (seconds at 40k).
    const x = "http://a/x" + "/".repeat(100_000) + "x";
    const started = performance.now();
    normalizeRepoUrl(x);
    expect(performance.now() - started).toBeLessThan(2000);
  });
});

// Negative control (anti-vacuity, AC6): the harness must be able to fail.
describe("repo-url property suite — negative control", () => {
  it("a deliberately-false property throws", () => {
    expect(() =>
      fc.assert(fc.property(fc.string(), () => false)),
    ).toThrow();
  });
});
