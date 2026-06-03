import { describe, it, expect } from "vitest";

import { isC4DiagramPath, C4_DIAGRAMS_DIR } from "@/lib/c4-constants";

// The C4 write scope guard is the single security-critical boundary shared by
// the UI editor route and the Concierge MCP tool. It must accept ONLY direct
// .c4/.md children of the diagrams dir and reject everything else.
describe("isC4DiagramPath", () => {
  it("accepts .c4 sources directly under the diagrams dir", () => {
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/model.c4`)).toBe(true);
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/spec.c4`)).toBe(true);
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/views.c4`)).toBe(true);
  });

  it("accepts the .md view-embed pages in the diagrams dir", () => {
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/system-context.md`)).toBe(true);
  });

  it("rejects paths outside the diagrams dir", () => {
    expect(isC4DiagramPath("engineering/architecture/decisions/ADR-001.md")).toBe(false);
    expect(isC4DiagramPath("project/plans/secret.c4")).toBe(false);
    expect(isC4DiagramPath("model.c4")).toBe(false);
  });

  it("rejects nested subdirectories under the diagrams dir", () => {
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/sub/model.c4`)).toBe(false);
  });

  it("rejects path traversal and null bytes", () => {
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/../../../etc/passwd`)).toBe(false);
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/..%2fmodel.c4`)).toBe(false);
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/model.c4\0.txt`)).toBe(false);
    expect(isC4DiagramPath("")).toBe(false);
  });

  it("rejects non-diagram extensions inside the dir", () => {
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/model.txt`)).toBe(false);
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/model.json`)).toBe(false);
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/notes.yaml`)).toBe(false);
  });

  it("rejects a directory-like path equal to the prefix", () => {
    expect(isC4DiagramPath(C4_DIAGRAMS_DIR)).toBe(false);
    expect(isC4DiagramPath(`${C4_DIAGRAMS_DIR}/`)).toBe(false);
  });
});
