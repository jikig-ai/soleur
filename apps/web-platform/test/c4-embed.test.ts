import { describe, it, expect } from "vitest";
import { parseLikeC4Embed } from "@/lib/c4-embed";

describe("parseLikeC4Embed", () => {
  it("returns null when there is no embed", () => {
    expect(parseLikeC4Embed("# Title\n\nSome prose.")).toBeNull();
    expect(parseLikeC4Embed("")).toBeNull();
  });

  it("extracts the view id from a likec4-view block", () => {
    const md = "# Container\n\n```likec4-view\ncontainers\n```\n\n## Notes\n- a";
    const embed = parseLikeC4Embed(md);
    expect(embed?.viewId).toBe("containers");
  });

  it("strips the block from the notes and keeps surrounding prose", () => {
    const md = "intro\n\n```likec4-view\ncontext\n```\n\n## Notes\n- one\n- two";
    const embed = parseLikeC4Embed(md);
    expect(embed?.notes).toContain("intro");
    expect(embed?.notes).toContain("## Notes");
    expect(embed?.notes).not.toContain("likec4-view");
    expect(embed?.notes).not.toContain("```");
  });

  it("tolerates trailing whitespace on the fence and view-id lines", () => {
    const md = "```likec4-view  \n  components of platform.plugin  \n```";
    const embed = parseLikeC4Embed(md);
    expect(embed?.viewId).toBe("components of platform.plugin");
  });

  it("uses the first block when several are present", () => {
    const md = "```likec4-view\nfirst\n```\n\n```likec4-view\nsecond\n```";
    expect(parseLikeC4Embed(md)?.viewId).toBe("first");
  });

  it("returns null when the block body is empty", () => {
    const md = "```likec4-view\n\n```";
    expect(parseLikeC4Embed(md)).toBeNull();
  });
});
