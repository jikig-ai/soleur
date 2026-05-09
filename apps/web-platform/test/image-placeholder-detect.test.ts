import { describe, it, expect } from "vitest";
import {
  IMAGE_PLACEHOLDER_REGEX,
  detectImagePlaceholders,
} from "@/lib/image-placeholder-detect";

describe("image-placeholder-detect", () => {
  describe("zero-match cases", () => {
    it("returns count 0 and unchanged text when no placeholders are present", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "what is this code doing?",
      );
      expect(count).toBe(0);
      expect(cleaned).toBe("what is this code doing?");
    });

    it("returns count 0 for empty string", () => {
      const { count, cleaned } = detectImagePlaceholders("");
      expect(count).toBe(0);
      expect(cleaned).toBe("");
    });

    it("does NOT match lowercase [image #1] (SDK marker is fixed-case)", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "see [image #1] for context",
      );
      expect(count).toBe(0);
      expect(cleaned).toBe("see [image #1] for context");
    });

    it("does NOT match no-space variant [Image#1] (SDK requires the space)", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "see [Image#1] for context",
      );
      expect(count).toBe(0);
      expect(cleaned).toBe("see [Image#1] for context");
    });
  });

  describe("single-match cases", () => {
    it("strips a single placeholder at start of message", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "[Image #1] what is this?",
      );
      expect(count).toBe(1);
      expect(cleaned).toBe("what is this?");
    });

    it("strips a single placeholder at end of message", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "what is this? [Image #1]",
      );
      expect(count).toBe(1);
      expect(cleaned).toBe("what is this?");
    });

    it("strips a single placeholder in the middle of message", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "what is [Image #1] doing?",
      );
      expect(count).toBe(1);
      expect(cleaned).toBe("what is doing?");
    });
  });

  describe("multi-match cases", () => {
    it("strips three placeholders in a row (no whitespace between)", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "[Image #1][Image #2][Image #3]",
      );
      expect(count).toBe(3);
      expect(cleaned).toBe("");
    });

    it("strips three space-separated placeholders", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "[Image #1] [Image #2] [Image #3]",
      );
      expect(count).toBe(3);
      expect(cleaned).toBe("");
    });

    it("strips placeholders interleaved with prose", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "[Image #1] hello [Image #2] world [Image #3]",
      );
      expect(count).toBe(3);
      expect(cleaned).toBe("hello world");
    });
  });

  describe("multi-digit cases", () => {
    it("matches multi-digit placeholders like [Image #99]", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "see [Image #99] please",
      );
      expect(count).toBe(1);
      expect(cleaned).toBe("see please");
    });

    it("matches a mixed single- and multi-digit run", () => {
      const { count, cleaned } = detectImagePlaceholders(
        "[Image #1] [Image #42]",
      );
      expect(count).toBe(2);
      expect(cleaned).toBe("");
    });
  });

  describe("regex export", () => {
    it("exports a global-flag regex", () => {
      expect(IMAGE_PLACEHOLDER_REGEX.flags).toContain("g");
    });

    it("regex matches exactly the expected literal shape", () => {
      // Reset lastIndex defensively before .test() (the implementation
      // uses .replace which is unaffected, but exporters of the regex
      // must reset before using .test() with /g).
      IMAGE_PLACEHOLDER_REGEX.lastIndex = 0;
      expect(IMAGE_PLACEHOLDER_REGEX.test("[Image #1]")).toBe(true);
      IMAGE_PLACEHOLDER_REGEX.lastIndex = 0;
      expect(IMAGE_PLACEHOLDER_REGEX.test("[image #1]")).toBe(false);
      IMAGE_PLACEHOLDER_REGEX.lastIndex = 0;
      expect(IMAGE_PLACEHOLDER_REGEX.test("[Image#1]")).toBe(false);
    });
  });
});
