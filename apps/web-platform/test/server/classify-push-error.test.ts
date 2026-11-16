// #12600 (CTO rulings R2, R16, re-ruled by D9): `classifyPushError` reads git's stderr only and routes to the protected-branch
// fallback on a line-anchored `remote: error: GH006:` OR a `remote:` line carrying GitHub's require-PR text (the #5426 tail,
// which also covers a GH013 ruleset that requires a PR). A ref name in git's own status line, a mid-line occurrence, or text in
// `err.message` (which embeds argv) cannot steer it. GH013 without the require-PR text (secret push protection) stays `other`.
// Line endings: CRLF and a lone CR both end a line. Synthesized stderr shapes.
import { describe, expect, test } from "vitest";
import { classifyPushError } from "../../server/kb-sync-publish";

const err = (stderr: string, message = "Command failed: git push"): Error => Object.assign(new Error(message), { stderr });

describe("classifyPushError (#12600)", () => {
  test("GitHub's GH006 line -> protected_branch", () => {
    expect(
      classifyPushError(
        err(
          [
            "remote: error: GH006: Protected branch update failed for refs/heads/main.",
            "remote: error: Changes must be made through a pull request.",
            "To https://github.com/acme/widget.git",
            " ! [remote rejected] abc -> main (protected branch hook declined)",
          ].join("\n"),
        ),
      ),
    ).toBe("protected_branch");
  });

  test("a GH006 line after a CRLF-ended line still matches (the anchor needs the CR gone)", () => {
    expect(classifyPushError(err("Enumerating objects: 3, done.\r\nremote: error: GH006: Protected branch update failed.\r\n"))).toBe(
      "protected_branch",
    );
  });

  test("a GH006 line after a CR-only separator (progress output) still matches", () => {
    expect(classifyPushError(err("Writing objects: 100% (3/3)\rremote: error: GH006: Protected branch update failed."))).toBe(
      "protected_branch",
    );
  });

  test("GH006 mid-line (inside git's own status line, not at the start of a remote: line) -> other", () => {
    expect(classifyPushError(err(" ! [remote rejected] main -> main (remote: error: GH006: x)\nerror: failed to push some refs"))).toBe(
      "other",
    );
  });

  test("the require-PR text mid-line (not on a remote: line) -> other", () => {
    expect(
      classifyPushError(err(" ! [remote rejected] main -> main (remote: Changes must be made through a pull request)\nerror: x")),
    ).toBe("other");
  });

  test("a ref name cannot steer it: git ref names cannot hold spaces, so the require-PR text never fits in one", () => {
    expect(
      classifyPushError(
        err(" ! [rejected] abc -> Changes-must-be-made-through-a-pull-request (non-fast-forward)\nremote:-Changes-must-be-made-through-a-pull-request"),
      ),
    ).toBe("other");
  });

  test("GH006 only in err.message (argv) -> other", () => {
    expect(classifyPushError(err("fatal: unable to access", "Command failed: git push remote: error: GH006: x"))).toBe("other");
  });

  test("the require-PR tail without the GH006 line routes to the fallback (#5426) -> protected_branch", () => {
    expect(classifyPushError(err("remote: error: Changes must be made through a pull request."))).toBe("protected_branch");
  });

  test("GH013 (a ruleset requiring a PR) -> protected_branch", () => {
    expect(
      classifyPushError(err("remote: error: GH013: Repository rule violations found for refs/heads/main.\nremote: - Changes must be made through a pull request.")),
    ).toBe("protected_branch");
  });

  test("GH013 with CRLF line endings (a ruleset requiring a PR) -> protected_branch", () => {
    expect(
      classifyPushError(
        err("remote: error: GH013: Repository rule violations found for refs/heads/main.\r\nremote: \r\nremote: - Changes must be made through a pull request.\r\n"),
      ),
    ).toBe("protected_branch");
  });

  test("GH013 secret push protection (no require-PR text) stays other", () => {
    expect(
      classifyPushError(
        err(
          [
            "remote: error: GH013: Repository rule violations found for refs/heads/main.",
            "remote: - GITHUB PUSH PROTECTION",
            "remote:   Push cannot contain secrets",
            "remote:     - commit: 0123456789abcdef0123456789abcdef01234567",
          ].join("\n"),
        ),
      ),
    ).toBe("other");
  });

  test("shallow update not allowed in stderr -> persistent_other", () => {
    expect(classifyPushError(err(" ! [remote rejected] abc -> main (shallow update not allowed)"))).toBe("persistent_other");
  });

  test("auth / network / non-Error input -> other", () => {
    expect(classifyPushError(err("fatal: Authentication failed for 'https://github.com/acme/widget.git/'"))).toBe("other");
    expect(classifyPushError(err("fatal: unable to access: Could not resolve host: github.com"))).toBe("other");
    expect(classifyPushError("remote: error: GH006: string input")).toBe("other");
    expect(classifyPushError(null)).toBe("other");
  });
});
