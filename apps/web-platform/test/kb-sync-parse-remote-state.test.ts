// `parseRemoteState` unit rows (#12600, CTO rulings R2, R17; D13 / test-design seat W16, W17): the `ls-remote --symref`
// parse the whole KB sync keys on. Exactly one `ref: refs/heads/<D>\tHEAD`, one `<sha>\tHEAD`, at most one exact
// `refs/heads/soleur/kb-sync`; other refs the tail-matching patterns return are ignored; anything duplicated or malformed
// throws `remote_state_invalid`. Synthesized shas only.
import { describe, expect, test } from "vitest";
import { KbRemoteError, parseRemoteState } from "../server/kb-sync-remote";

const A = "a".repeat(40);
const B = "b".repeat(40);
const C = "c".repeat(40);
const lines = (...l: string[]): string => `${l.join("\n")}\n`;
const invalid = (out: string): void => {
  let caught: unknown;
  try {
    parseRemoteState(out);
  } catch (err) {
    caught = err;
  }
  expect(caught).toBeInstanceOf(KbRemoteError);
  expect((caught as KbRemoteError).reason).toBe("remote_state_invalid");
};

describe("parseRemoteState (#12600)", () => {
  test("default branch, tip and side tip", () => {
    expect(parseRemoteState(lines("ref: refs/heads/main\tHEAD", `${A}\tHEAD`, `${B}\trefs/heads/soleur/kb-sync`))).toEqual({
      defaultBranch: "main",
      tip: A,
      sideTip: B,
    });
  });

  test("no side branch -> sideTip null; a non-main default branch is read from the symref", () => {
    expect(parseRemoteState(lines("ref: refs/heads/trunk\tHEAD", `${A}\tHEAD`))).toEqual({ defaultBranch: "trunk", tip: A, sideTip: null });
  });

  test("other refs the patterns tail-match (refs/x/HEAD, a nested kb-sync name) are ignored", () => {
    expect(
      parseRemoteState(
        lines("ref: refs/heads/main\tHEAD", `${A}\tHEAD`, `${C}\trefs/x/HEAD`, "ref: refs/heads/evil\trefs/x/HEAD", `${C}\trefs/heads/x/soleur/kb-sync`),
      ),
    ).toEqual({ defaultBranch: "main", tip: A, sideTip: null });
  });

  test("no resolvable HEAD (empty output, or a symref with no sha line) -> null (remote_branch_absent)", () => {
    expect(parseRemoteState("")).toBeNull();
    expect(parseRemoteState(lines("ref: refs/heads/main\tHEAD"))).toBeNull();
    expect(parseRemoteState(lines(`${A}\tHEAD`))).toBeNull();
  });

  test("a duplicated HEAD symref line throws (W16)", () => {
    invalid(lines("ref: refs/heads/main\tHEAD", "ref: refs/heads/other\tHEAD", `${A}\tHEAD`));
  });

  test("a duplicated HEAD sha line throws", () => {
    invalid(lines("ref: refs/heads/main\tHEAD", `${A}\tHEAD`, `${B}\tHEAD`));
  });

  test("a duplicated side line throws", () => {
    invalid(lines("ref: refs/heads/main\tHEAD", `${A}\tHEAD`, `${B}\trefs/heads/soleur/kb-sync`, `${C}\trefs/heads/soleur/kb-sync`));
  });

  test("a default branch name git refuses throws (W17)", () => {
    invalid(lines("ref: refs/heads/bad..name\tHEAD", `${A}\tHEAD`));
    invalid(lines("ref: refs/heads/a b\tHEAD", `${A}\tHEAD`));
  });

  test("a HEAD symref outside refs/heads throws", () => {
    invalid(lines("ref: refs/tags/v1\tHEAD", `${A}\tHEAD`));
  });

  test("a line with no tab, or a non-40-hex sha, throws", () => {
    invalid(lines("ref: refs/heads/main HEAD", `${A}\tHEAD`));
    invalid(lines("ref: refs/heads/main\tHEAD", `${A.toUpperCase()}\tHEAD`));
    invalid(lines("ref: refs/heads/main\tHEAD", `${"a".repeat(64)}\tHEAD`));
  });
});
