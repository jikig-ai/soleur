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

describe("normalizeRepoUrl — fixpoint fixtures", () => {
  // regression fixture: fast-check seed -1029694662 (merge_group run 39400877769)
  // A trailing `.git` strip exposed a `.` segment; the next call's URL parse
  // collapsed it. One pass was not a fixpoint.
  it.each([
    " http://a.aa/..git/",
    "b.git/.",
    "?q/\t/..",
    "http://a.aa#h@u.GIT/..///",
    "http://a.aa/../%2E%2e/.git/.git",
  ])("%j is a fixpoint after one call", (x) => {
    const once = normalizeRepoUrl(x);
    expect(normalizeRepoUrl(once)).toBe(once);
  });

  // Review finding on #10779: each pass peels one "/..git" segment, so a deep
  // chain outruns the pass bound. The result must still be a fixpoint.
  it.each([8, 15, 16, 17, 5000])("a chain of %i '/..git' segments is a fixpoint", (k) => {
    const once = normalizeRepoUrl("https://github.com/o/r" + "/..git".repeat(k));
    expect(normalizeRepoUrl(once)).toBe(once);
  });

  it("a chain within the pass bound still normalizes to the repository", () => {
    expect(normalizeRepoUrl("https://github.com/o/r" + "/..git".repeat(3))).toBe(
      "https://github.com/o/r",
    );
  });

  it("the counterexample normalizes to the bare origin", () => {
    expect(normalizeRepoUrl(" http://a.aa/..git/")).toBe("http://a.aa");
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
