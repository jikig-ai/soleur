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

  // regression fixture: fast-check seed -1029694662 path 68:0:0:0:0:0:1:0:0
  // Counterexample " http://a.aa/..git/" (merge_group run 39400877769): the
  // `.git` strip leaves a `.` dot-segment (`http://a.aa/.`) which the NEXT
  // call's URL parse resolves away (`http://a.aa`), so one pass was not a
  // fixpoint. SUT fix: run the pass until the output stops changing.
  it("a .git strip that exposes a dot-segment is idempotent", () => {
    const once = normalizeRepoUrl(" http://a.aa/..git/");
    expect(once).toBe("http://a.aa");
    expect(normalizeRepoUrl(once)).toBe(once);
  });

  // pinned example (scratch fuzz 2026-10-20, no fast-check seed): shapes the
  // same convergence loop must reach; each needs more than 3 passes or a
  // different mechanism, so a too-small fixed pass cap fails them.
  it("a deep chain of dot-segment-exposing strips converges", () => {
    const once = normalizeRepoUrl("http://a.aa/" + "..git/".repeat(5));
    expect(once).toBe("http://a.aa");
    expect(normalizeRepoUrl(once)).toBe(once);
  });

  // pinned example (scratch fuzz 2026-10-20, no fast-check seed): an
  // opaque-path scheme gains an authority on re-parse (`xx:B` -> `xx://b`).
  it("an opaque-path input converges to its re-parsed form", () => {
    const once = normalizeRepoUrl("xx:B");
    expect(once).toBe("xx://b");
    expect(normalizeRepoUrl(once)).toBe(once);
  });

  // pinned example (scratch fuzz 2026-10-20, no fast-check seed): each
  // strip exposes one more whitespace-shielded `/`, so peeling is linear in
  // the input length.
  it("a long whitespace/slash peel chain converges", () => {
    const once = normalizeRepoUrl("x" + " /".repeat(8));
    expect(once).toBe("x");
    expect(normalizeRepoUrl(once)).toBe(once);
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
