import { describe, expect, it } from "vitest";
import { KB_MAX_FILE_SIZE } from "@/lib/kb-constants";

describe("kb-constants", () => {
  it("exports KB_MAX_FILE_SIZE as 1MB", () => {
    expect(KB_MAX_FILE_SIZE).toBe(1024 * 1024);
  });
});
