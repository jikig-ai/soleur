// #12600 (CTO rulings R2, R16): `classifyPushError` reads git's stderr only and keys the protected-branch fallback on the
// line-anchored `^remote: error: GH006:` GitHub prints. A ref name in git's own status line, or text in `err.message`
// (which embeds argv), cannot steer it. GH013 (rulesets) stays `other` (follow-up #12734). Synthesized stderr shapes.
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

  test("a GH006 line with CRLF endings still matches", () => {
    expect(classifyPushError(err("remote: error: GH006: Protected branch update failed.\r\n"))).toBe("protected_branch");
  });

  test("GH006 only inside a ref name on git's status line -> other", () => {
    expect(
      classifyPushError(err(" ! [rejected] abc -> remote:-error:-GH006:-x (non-fast-forward)\nerror: failed to push some refs")),
    ).toBe("other");
  });

  test("GH006 only in err.message (argv) -> other", () => {
    expect(classifyPushError(err("fatal: unable to access", "Command failed: git push remote: error: GH006: x"))).toBe("other");
  });

  test("the require-PR tail without the GH006 line no longer routes to the fallback -> other", () => {
    expect(classifyPushError(err("remote: error: Changes must be made through a pull request."))).toBe("other");
  });

  test("GH013 (rulesets) stays other (#12734)", () => {
    expect(
      classifyPushError(err("remote: error: GH013: Repository rule violations found for refs/heads/main.\nremote: - Changes must be made through a pull request.")),
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
