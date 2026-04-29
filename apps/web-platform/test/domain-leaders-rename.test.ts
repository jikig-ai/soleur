import { describe, test, expect } from "vitest";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";

// Plan 2026-04-29 (H4): rename the `cc_router` domain-leader entry from
// "Router · Command Center Router" to "Soleur Concierge". The internal
// `id: "cc_router"` MUST stay the same — it discriminates router-narration
// turns from system-process turns in the chat-state-machine and tool-use
// chip render path. Only `name`, `title`, and `description` are user-visible.
//
// See ADR-022 §"2026-04-29 follow-up" and the plan's H4 / AC10.

describe("domain-leaders: cc_router rename to Soleur Concierge", () => {
  const router = DOMAIN_LEADERS.find((l) => l.id === "cc_router");

  test("entry exists under the unchanged internal id", () => {
    expect(router).toBeDefined();
  });

  test("title renders as 'Soleur Concierge'", () => {
    expect(router?.title).toBe("Soleur Concierge");
  });

  test("name renders as 'Concierge' (not 'Router')", () => {
    expect(router?.name).toBe("Concierge");
  });

  test("description does not contain legacy 'Command Center Router' label", () => {
    expect(router?.description).toBeDefined();
    expect(router?.description).not.toContain("Command Center Router");
  });
});
