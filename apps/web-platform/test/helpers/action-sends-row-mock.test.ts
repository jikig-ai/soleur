/**
 * Negative controls for the shared stateful store (#10543): a fake that cannot reject cannot prove
 * the route's filters or column list, so pin that it narrows on `.eq`, projects only what was asked,
 * applies updates by filter, and REJECTS an unknown column or table.
 */

import { describe, test, expect } from "vitest";

import {
  createActionSendsStore,
  pendingActionSendRow,
} from "./action-sends-row-mock";

const U = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const M1 = "11111111-1111-4111-aaaa-111111111111";
const M2 = "22222222-2222-4222-aaaa-222222222222";

function store() {
  return createActionSendsStore({
    message: {
      id: M1,
      user_id: U,
      action_class: "engineering.pr_review_pending",
      status: "draft",
      draft_preview: "d",
      owning_domain: "engineering",
      template_id: "default_legacy",
      source_ref: "pr-acme:repo:7",
    },
    actionSends: [
      pendingActionSendRow({ id: "r1", message_id: M2, user_id: U }),
      pendingActionSendRow({ id: "r2", message_id: M1, user_id: U }),
    ],
  });
}

describe("action-sends-row-mock", () => {
  test(".eq narrows: filtering on message_id picks the right row even when another row for the same user is first", async () => {
    const s = store();
    const q = (s.from("action_sends") as any)
      .select("id")
      .eq("message_id", M1)
      .eq("user_id", U);
    expect((await q.maybeSingle()).data).toEqual({ id: "r2" });
  });

  test("a dropped filter is observable: without message_id the FIRST row wins", async () => {
    const s = store();
    const q = (s.from("action_sends") as any).select("id").eq("user_id", U);
    expect((await q.maybeSingle()).data).toEqual({ id: "r1" });
  });

  test("projection returns only the requested columns", async () => {
    const s = store();
    const q = (s.from("action_sends") as any)
      .select("id, tier_at_send")
      .eq("message_id", M1);
    expect(Object.keys((await q.maybeSingle()).data).sort()).toEqual([
      "id",
      "tier_at_send",
    ]);
  });

  test("an UNKNOWN column rejects (the real client would answer 42703)", async () => {
    const s = store();
    const q = (s.from("action_sends") as any)
      .select("id, not_a_column")
      .eq("message_id", M1);
    await expect(q.maybeSingle()).rejects.toThrow("unknown column");
  });

  test("an unknown table rejects", () => {
    expect(() => store().from("scope_grants")).toThrow("unexpected table");
  });

  test("update applies only to rows matching ALL filters and records them", async () => {
    const s = store();
    await (s.from("messages") as any)
      .update({ status: "archived" })
      .eq("id", M1)
      .eq("user_id", U)
      .eq("status", "draft");
    expect(s.messageStatus()).toBe("archived");
    expect(s.archiveFilters[0]).toContainEqual(["status", "draft"]);

    // a second archive with the status filter now matches nothing and changes nothing
    await (s.from("messages") as any)
      .update({ status: "x" })
      .eq("id", M1)
      .eq("status", "draft");
    expect(s.messageStatus()).toBe("archived");
  });
});
