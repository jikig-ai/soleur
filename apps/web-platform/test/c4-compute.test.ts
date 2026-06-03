import { describe, it, expect } from "vitest";

import { computeC4Model } from "@/server/c4-compute";

const VALID = `
specification {
  element system
  element actor { style { shape person } }
}
model {
  user = actor "User"
  app = system "App"
  user -> app "uses"
}
views {
  view index {
    include *
  }
}
`;

const INVALID = `
specification {
  element system
}
model {
  app = system "App"
  app -> ghost "broken reference"
}
views {
  view index { include * }
}
`;

describe("computeC4Model", () => {
  it("returns a layouted dump and view ids for valid source", async () => {
    const { dump, viewIds, diagnostics } = await computeC4Model(VALID);
    expect(diagnostics).toEqual([]);
    expect(dump).not.toBeNull();
    expect(viewIds).toContain("index");
  });

  it("returns diagnostics and a null dump for invalid source", async () => {
    const { dump, diagnostics } = await computeC4Model(INVALID);
    expect(dump).toBeNull();
    expect(diagnostics.length).toBeGreaterThan(0);
    expect(diagnostics[0]).toHaveProperty("message");
    expect(diagnostics[0]).toHaveProperty("line");
  });
});
