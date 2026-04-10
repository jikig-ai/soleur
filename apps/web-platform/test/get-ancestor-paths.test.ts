import { describe, it, expect } from "vitest";
import { getAncestorPaths } from "@/components/kb/get-ancestor-paths";

describe("getAncestorPaths", () => {
  it("returns empty array for root-level file", () => {
    expect(getAncestorPaths("file.md")).toEqual([]);
  });

  it("returns parent directory for single-nested file", () => {
    expect(getAncestorPaths("engineering/file.md")).toEqual(["engineering"]);
  });

  it("returns all ancestor directories for deeply nested file", () => {
    expect(getAncestorPaths("engineering/specs/file.md")).toEqual([
      "engineering",
      "engineering/specs",
    ]);
  });

  it("returns three levels for triple-nested file", () => {
    expect(getAncestorPaths("a/b/c/file.md")).toEqual(["a", "a/b", "a/b/c"]);
  });

  it("returns empty array for empty string", () => {
    expect(getAncestorPaths("")).toEqual([]);
  });

  it("handles trailing slash (empty segment filtered, last dir treated as leaf)", () => {
    // "engineering/specs/" -> segments after filter: ["engineering", "specs"]
    // "specs" is the leaf, so only "engineering" is an ancestor
    expect(getAncestorPaths("engineering/specs/")).toEqual(["engineering"]);
  });

  it("handles URL-decoded paths with spaces", () => {
    expect(getAncestorPaths("my folder/sub dir/file.md")).toEqual([
      "my folder",
      "my folder/sub dir",
    ]);
  });
});
