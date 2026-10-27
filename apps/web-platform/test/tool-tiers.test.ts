/**
 * Tool Tier Classification Tests (Phase 1, #1926)
 *
 * Tests the tiered permission model for platform MCP tools:
 * - auto-approve: read-only tools pass through without review gate
 * - gated: write tools require founder confirmation via review gate
 * - blocked: destructive patterns rejected unconditionally
 *
 * Extracted to a standalone module (following tool-path-checker.ts pattern)
 * for unit testability without SDK/Supabase dependencies.
 */
import { describe, test, expect } from "vitest";
import {
  getToolTier,
  buildGateMessage,
  buildGateCard,
  buildOfflineGateMessage,
  CC_ROUTER_TIER3_DENYLIST,
  TOOL_TIER_MAP,
  isPreApprovable,
  pluginWildcard,
  parsePluginWildcard,
} from "../server/tool-tiers";
import { EXPECTED_GATED } from "./helpers/expected-tool-tiers";

describe("getToolTier", () => {
  test("returns auto-approve for github_read_ci_status", () => {
    expect(getToolTier("mcp__soleur_platform__github_read_ci_status")).toBe(
      "auto-approve",
    );
  });

  test("returns auto-approve for github_read_workflow_logs", () => {
    expect(getToolTier("mcp__soleur_platform__github_read_workflow_logs")).toBe(
      "auto-approve",
    );
  });

  test("returns auto-approve for edit_c4_diagram (scope-guarded write)", () => {
    expect(getToolTier("mcp__soleur_platform__edit_c4_diagram")).toBe(
      "auto-approve",
    );
  });

  test("returns gated for github_trigger_workflow", () => {
    expect(getToolTier("mcp__soleur_platform__github_trigger_workflow")).toBe(
      "gated",
    );
  });

  test("returns gated for github_push_branch", () => {
    expect(getToolTier("mcp__soleur_platform__github_push_branch")).toBe(
      "gated",
    );
  });

  test("returns gated for create_pull_request", () => {
    expect(getToolTier("mcp__soleur_platform__create_pull_request")).toBe(
      "gated",
    );
  });

  test("returns gated for create_issue", () => {
    expect(getToolTier("mcp__soleur_platform__create_issue")).toBe(
      "gated",
    );
  });

  test("returns gated for unregistered platform tools (fail-closed default)", () => {
    // Platform tools not in the tier map default to gated
    // so new tools require explicit tier assignment before auto-approve
    expect(getToolTier("mcp__soleur_platform__unknown_future_tool")).toBe(
      "gated",
    );
  });

});

describe("workstream edit-fields tool tiers (agent-user parity)", () => {
  test("workstream_issue_update_fields is gated (real GitHub write)", () => {
    expect(
      getToolTier("mcp__soleur_platform__workstream_issue_update_fields"),
    ).toBe("gated");
  });

  test("workstream_issue_options is auto-approve (read-only discovery)", () => {
    expect(
      getToolTier("mcp__soleur_platform__workstream_issue_options"),
    ).toBe("auto-approve");
  });

  test("update_fields gate message names the edited fields", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__workstream_issue_update_fields",
      { number: 7, labels: ["bug"], milestone: null, assignees: ["harry"] },
    );
    expect(msg).toContain("#7");
    expect(msg).toContain("bug");
    expect(msg).toContain("harry");
    expect(msg).toMatch(/milestone/i);
  });
});

describe("buildGateMessage", () => {
  test("trigger workflow message includes workflow_id and ref", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__github_trigger_workflow",
      { workflow_id: 42, ref: "main" },
    );
    expect(msg).toContain("42");
    expect(msg).toContain("main");
    expect(msg).toMatch(/trigger workflow/i);
  });

  test("push branch message includes branch name", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__github_push_branch",
      { branch: "feat-new-feature" },
    );
    expect(msg).toContain("feat-new-feature");
    expect(msg).toMatch(/push/i);
  });

  test("create PR message includes title and branches", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__create_pull_request",
      { title: "My PR", base: "main", head: "feat-x" },
    );
    expect(msg).toContain("My PR");
    expect(msg).toContain("main");
    expect(msg).toContain("feat-x");
    expect(msg).toMatch(/open PR/i);
  });

  test("create issue message includes title", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__create_issue",
      { title: "Login is broken" },
    );
    expect(msg).toContain("Login is broken");
    expect(msg).toMatch(/file an issue/i);
  });

  test("unknown tool uses short tool name", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__some_new_tool",
      {},
    );
    expect(msg).toContain("some_new_tool");
  });

  // #5325 — the operator MUST see recipient + body before approving an
  // outbound send; a content-free "Allow?" would make the gate decorative.
  test("email_send gate shows the recipient, subject, and body", () => {
    const msg = buildGateMessage("mcp__soleur_platform__email_send", {
      to: "journalist@example.com",
      subject: "Your listicle",
      body: "Hi — I built something relevant to your piece.",
    });
    expect(msg).toContain("journalist@example.com");
    expect(msg).toContain("Your listicle");
    expect(msg).toContain("I built something relevant");
    expect(msg).not.toMatch(/^Agent wants to use/); // not the default
  });

  test("email_reply gate names the inbound item + shows the body (recipient is server-derived)", () => {
    const msg = buildGateMessage("mcp__soleur_platform__email_reply", {
      messageId: "abc-123",
      subject: "Re: hello",
      body: "Thanks for your note.",
    });
    expect(msg).toContain("abc-123");
    expect(msg).toContain("Thanks for your note");
  });

  test("email_suppress gate names the recipient + flags permanence", () => {
    const msg = buildGateMessage("mcp__soleur_platform__email_suppress", {
      recipient: "person@example.com",
      reason: "decline",
    });
    expect(msg).toContain("person@example.com");
    expect(msg).toMatch(/permanent/i);
  });
});

describe("CC_ROUTER_TIER3_DENYLIST (#2909)", () => {
  test("contains exactly 3 entries", () => {
    expect(CC_ROUTER_TIER3_DENYLIST.size).toBe(3);
  });

  test("contains all three Plausible tool FQNs", () => {
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__plausible_create_site"),
    ).toBe(true);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__plausible_add_goal"),
    ).toBe(true);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__plausible_get_stats"),
    ).toBe(true);
  });

  test("does not contain non-Plausible tools (no Tier 3 creep)", () => {
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__kb_share_create"),
    ).toBe(false);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__github_push_branch"),
    ).toBe(false);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__conversations_lookup"),
    ).toBe(false);
  });
});

// #11303 — once the gate is reachable (gated names leave SDK allowedTools), the card is the ONLY control, so the tier map
// must say "decided" rather than "defaulted" for every platform tool, and the card text must be informed and tamper-proof.
const P = "mcp__soleur_platform__";
const GATED_KEYS = Object.entries(TOOL_TIER_MAP)
  .filter(([, tier]) => tier === "gated")
  .map(([name]) => name);

describe("explicit tier entries (#11303)", () => {
  test.each(["plausible_create_site", "plausible_add_goal", "plausible_get_stats", "account_export_enqueue", "account_delete_initiate"])(
    "%s has an explicit gated entry (decided, not defaulted)",
    (n) => {
      expect(Object.hasOwn(TOOL_TIER_MAP, `${P}${n}`)).toBe(true);
      expect(getToolTier(`${P}${n}`)).toBe("gated");
    },
  );

  test("conversations_lookup is an explicit auto-approve entry (its handler is read-only: SELECTs through the tenant client)", () => {
    expect(Object.hasOwn(TOOL_TIER_MAP, `${P}conversations_lookup`)).toBe(true);
    expect(getToolTier(`${P}conversations_lookup`)).toBe("auto-approve");
  });

  test("the registered-but-not-allowlisted conversations siblings stay unclassified (denied by canUseTool's deny-default)", () => {
    for (const n of ["conversations_list", "conversation_archive", "conversation_unarchive"]) {
      expect(Object.hasOwn(TOOL_TIER_MAP, `${P}${n}`)).toBe(false);
    }
  });

  test("prototype keys never resolve to a tier object (fail-closed)", () => {
    for (const k of ["__proto__", "constructor", "toString", "hasOwnProperty"]) expect(getToolTier(k)).toBe("gated");
  });
});

describe("gate messages for tools that become reachable (#11303)", () => {
  test("no gated tool's card is the generic default", () => {
    // the universe is the hand-written gated list, not a floor derived from the map under test
    expect([...GATED_KEYS].sort()).toEqual(EXPECTED_GATED.map((n) => `${P}${n}`).sort());
    for (const key of GATED_KEYS) {
      const short = key.replace(P, "");
      expect(buildGateMessage(key, {})).not.toBe(`Agent wants to use **${short}**. Allow?`);
    }
  });

  test("workspace_set_autonomous states ON vs OFF and what ON permits", () => {
    const on = buildGateMessage(`${P}workspace_set_autonomous`, { value: true });
    const off = buildGateMessage(`${P}workspace_set_autonomous`, { value: false });
    expect(on).toMatch(/\bON\b/);
    expect(on).toMatch(/shell commands/i);
    expect(on).toMatch(/without (asking|approval)/i);
    expect(off).toMatch(/\bOFF\b/);
    expect(on).not.toBe(off);
  });

  test("account_delete_initiate names permanent deletion and does not echo the confirmation email", () => {
    const msg = buildGateMessage(`${P}account_delete_initiate`, { ack: "DELETE MY ACCOUNT", confirmEmail: "me@example.invalid" });
    expect(msg).toMatch(/permanent/i);
    expect(msg).toMatch(/account/i);
    expect(msg).not.toContain("me@example.invalid");
    expect(msg).not.toContain("DELETE MY ACCOUNT");
  });

  test("account_export_enqueue names a full data export", () => {
    expect(buildGateMessage(`${P}account_export_enqueue`, {})).toMatch(/export/i);
  });

  test("plausible cards name the site domain, goal type and value, or the stats read", () => {
    expect(buildGateMessage(`${P}plausible_create_site`, { domain: "example.com", timezone: "UTC" })).toContain("example.com");
    const goal = buildGateMessage(`${P}plausible_add_goal`, { site_id: "example.com", goal_type: "event", value: "signup" });
    expect(goal).toContain("example.com");
    expect(goal).toContain("event");
    expect(goal).toContain("signup");
    const stats = buildGateMessage(`${P}plausible_get_stats`, { site_id: "example.com", period: "7d" });
    expect(stats).toContain("example.com");
    expect(stats).toContain("7d"); // not the "30d" fallback, so the assertion can tell the input from the default
  });
});

// A hostile tool input: every field the model controls carries markdown, a link, a newline, bidi/zero-width characters
// and a huge payload. The card must stay bounded and must not let the value restyle or restructure itself.
const HOSTILE = `evil**bold**\n\n[click here](https://evil.invalid)\u202Egpj.exe\u200B\`code\`<img src=x>${"X".repeat(5000)}`;
const inputOf = (v: unknown) => new Proxy({}, { get: () => v }) as Record<string, unknown>;
const countOf = (s: string, ch: string) => s.split(ch).length - 1;
// eslint-disable-next-line no-control-regex -- asserting the absence of control characters is the point
const CONTROL_OR_BIDI = /[\u0000-\u0009\u000B-\u001F\u007F-\u009F\u00AD\u061C\u200B-\u200F\u2028-\u202E\u2060-\u2069\uFEFF\u{E0000}-\u{E007F}]/u;

// The email cards are not neutralised by deletion: they show the whole send, make hidden characters visible, and DENY what
// they cannot show in full. They have their own hardening block below.
const EMAIL_CARD_KEYS = [`${P}email_send`, `${P}email_reply`, `${P}email_suppress`];
const PLAIN_CARD_KEYS = GATED_KEYS.filter((k) => !EMAIL_CARD_KEYS.includes(k));

describe("card text hardening (#11303)", () => {
  test.each(PLAIN_CARD_KEYS)("%s: bounded, no restructuring, no control or bidi characters under hostile input", (key) => {
    const hostile = buildGateMessage(key, inputOf(HOSTILE));
    const benign = buildGateMessage(key, inputOf("ok"));
    expect(hostile.length).toBeLessThan(1600);
    expect(CONTROL_OR_BIDI.test(hostile)).toBe(false);
    // The hostile value must add no newline and no markdown/link/html control character beyond the fixed template's own.
    for (const ch of ["\n", "*", "`", "[", "]", "<", ">"]) expect(countOf(hostile, ch)).toBe(countOf(benign, ch));
  });

  test.each(GATED_KEYS)("%s: a non-string field is rendered as the word unknown, never an object", (key) => {
    const msg = buildGateMessage(key, inputOf({ nested: "object" }));
    expect(msg).not.toContain("[object Object]");
    // the workflow card lists the NAMES of the dispatch inputs (values are never printed), so a key may appear there
    if (key !== `${P}github_trigger_workflow`) expect(msg).not.toContain("nested");
  });

  test("ordinary values still render readably (branch, title, path)", () => {
    expect(buildGateMessage(`${P}github_push_branch`, { branch: "feat/my_branch-1" })).toContain("feat/my_branch-1");
    expect(buildGateMessage(`${P}create_issue`, { title: "Login is broken" })).toContain("Login is broken");
    expect(buildGateMessage(`${P}kb_share_create`, { documentPath: "product/roadmap.md" })).toContain("product/roadmap.md");
  });
});

describe("offline gate message is content-free for every gated tool (#11303, privacy notice scope #8532)", () => {
  const CANARY = "CANARY-9f3a-tool-input";

  test.each(GATED_KEYS)("%s: no tool-input value reaches the push / email text", (key) => {
    const msg = buildOfflineGateMessage(key, inputOf(CANARY));
    expect(msg).not.toContain(CANARY);
    expect(msg).toMatch(/waiting for your approval/i);
    // identical for any input: the text depends on the tool only
    expect(buildOfflineGateMessage(key, inputOf("another value"))).toBe(msg);
  });

  test("outbound email keeps its existing wording", () => {
    expect(buildOfflineGateMessage(`${P}email_send`, { to: "a@example.invalid", body: "b" })).toBe(
      "An agent is waiting for your approval on an outbound email action. Open the conversation to review it.",
    );
  });

  test("an unknown future gated tool falls back to a generic, still content-free sentence", () => {
    const msg = buildOfflineGateMessage(`${P}some_future_tool`, inputOf(CANARY));
    expect(msg).not.toContain(CANARY);
    expect(msg).toMatch(/waiting for your approval/i);
  });
});

describe("outbound email cards: the whole send is shown, or the tool is denied (#11303)", () => {
  const SEND = `${P}email_send`;
  const REPLY = `${P}email_reply`;
  const DENY_RECIPIENT =
    "The recipient could not be shown in full for review, so the email was not sent. Fix the recipient and try again.";
  const DENY_BODY = "Shorten the body to 4,000 characters or fewer and try again.";
  const base = { to: "jo@example.invalid", subject: "Hello", body: "Hi Jo" };

  test("the recipient is the full parsed address with its angle brackets, the display name separately", () => {
    const r = buildGateCard(SEND, { ...base, to: "Jo Doe <jo@example.invalid>" });
    expect(r).toHaveProperty("card");
    const card = (r as { card: string }).card;
    expect(card).toContain("To: <jo@example.invalid> (display name: \"Jo Doe\")");
    expect(card).toContain("Subject: \"Hello\"");
    expect(card).toContain("Hi Jo");
  });

  test("a bare address is shown in angle brackets with no display name", () => {
    expect(buildGateMessage(SEND, base)).toContain("To: <jo@example.invalid>\n");
  });

  test("a long display name is capped with a visible ellipsis and the address is still shown in full", () => {
    const msg = buildGateMessage(SEND, { ...base, to: `${"N".repeat(150)} <jo@example.invalid>` });
    expect(msg).toContain("<jo@example.invalid>");
    expect(msg).toContain(`${"N".repeat(60)}…`);
    expect(msg).not.toContain("N".repeat(61));
  });

  test("a display name carrying an address-like or list separator is refused", () => {
    for (const to of ["ceo@bank.invalid <evil@example.invalid>", "Doe, Jo <jo@example.invalid>", "Jo; Al <jo@example.invalid>"]) {
      expect(buildGateCard(SEND, { ...base, to })).toEqual({ deny: DENY_RECIPIENT });
    }
  });

  test.each([
    ["a recipient list", "a@example.invalid, b@example.invalid"],
    ["two angle addresses", "A <a@example.invalid> B <b@example.invalid>"],
    ["an unclosed angle bracket", "Jo <jo@example.invalid"],
    ["an empty address", "Jo <>"],
    ["not an address", "just a name"],
    ["a raw value over 320 characters", `${"x".repeat(321)}@example.invalid`],
    ["an address over 254 characters", `${"x".repeat(250)}@example.invalid`],
    ["an address with a bidi override inside", "jo\u202E@example.invalid"],
    ["an address with a zero-width space", "jo\u200B@example.invalid"],
    ["an address with a markdown character", "j*o@example.invalid"],
    ["a non-string", 42],
  ])("fails closed on %s: a static deny, never a card", (_n, to) => {
    expect(buildGateCard(SEND, { ...base, to })).toEqual({ deny: DENY_RECIPIENT });
  });

  test("reply-to is shown on its own line, parsed the same way", () => {
    const msg = buildGateMessage(SEND, { ...base, replyTo: "Boss <boss@example.invalid>" });
    expect(msg).toContain("\nReply-To: <boss@example.invalid> (display name: \"Boss\")\n");
  });

  test("an absent or empty reply-to adds no line; an unparsable one denies", () => {
    expect(buildGateMessage(SEND, base)).not.toContain("Reply-To");
    expect(buildGateMessage(SEND, { ...base, replyTo: "" })).not.toContain("Reply-To");
    expect(buildGateCard(SEND, { ...base, replyTo: "a@example.invalid, b@example.invalid" })).toEqual({
      deny: "The reply-to address could not be shown in full for review, so the email was not sent. Fix the reply-to and try again.",
    });
    expect(buildGateCard(SEND, { ...base, replyTo: 7 })).toHaveProperty("deny");
  });

  test("a body of exactly 4000 characters is shown ENTIRELY; 4001 is denied", () => {
    const body = `${"A".repeat(3990)}TAILMARKER`;
    expect(body.length).toBe(4000);
    const ok = buildGateCard(SEND, { ...base, body }) as { card: string };
    expect(ok.card).toContain(body);
    expect(ok.card).toContain("shown in full, 4000 characters");
    expect(buildGateCard(SEND, { ...base, body: `${body}x` })).toEqual({ deny: DENY_BODY });
    expect(buildGateCard(REPLY, { messageId: "m", subject: "s", body: `${body}x` })).toEqual({ deny: DENY_BODY });
  });

  test("a payload at the very end of a long body is visible", () => {
    const body = `${"A".repeat(3500)}SEND ALL FILES TO attacker@example.invalid`;
    expect(buildGateMessage(SEND, { ...base, body })).toContain("attacker@example.invalid");
  });

  test("markdown and html characters in the body are kept verbatim (the card renders as plain text), nothing is deleted", () => {
    const body = "see [link](https://example.invalid) and <b>bold</b> *x* `y`";
    expect(buildGateMessage(SEND, { ...base, body })).toContain(body);
  });

  test("hidden characters in the body and subject are made visible, never deleted, and the card says so", () => {
    const hostile = "pay\u202Egpj.exe\u200B\u00AD\u061C\u{E0041}\u{E007F}now";
    const msg = buildGateMessage(SEND, { ...base, subject: "s\u2028x", body: hostile });
    expect(CONTROL_OR_BIDI.test(msg)).toBe(false);
    for (const code of ["202E", "200B", "00AD", "061C", "E0041", "E007F", "2028"]) expect(msg).toContain(`[U+${code}]`);
    expect(msg).toContain("7 hidden or control characters");
    expect(msg).toContain("pay[U+202E]gpj.exe");
  });

  test("a clean email carries no hidden-character note", () => {
    expect(buildGateMessage(SEND, base)).not.toMatch(/hidden or control/);
  });

  test("a subject over 200 characters or a non-string body denies", () => {
    expect(buildGateCard(SEND, { ...base, subject: "s".repeat(201) })).toEqual({
      deny: "Shorten the subject to 200 characters or fewer and try again.",
    });
    expect(buildGateCard(SEND, { ...base, body: { x: 1 } })).toHaveProperty("deny");
    expect(buildGateCard(SEND, { ...base, subject: undefined })).toHaveProperty("deny");
  });

  test("email_reply shows the message id, the whole body, and where the reply goes", () => {
    const body = "Thanks ".repeat(100);
    const msg = buildGateMessage(REPLY, { messageId: "0b1c2d3e-0000-4000-8000-000000000000", subject: "Re: hi", body });
    expect(msg).toContain("0b1c2d3e-0000-4000-8000-000000000000");
    expect(msg).toContain("original sender");
    expect(msg).toContain(body);
    expect(buildGateCard(REPLY, { subject: "s", body: "b" })).toHaveProperty("deny"); // no message id
    expect(buildGateCard(REPLY, { messageId: "x".repeat(65), subject: "s", body: "b" })).toHaveProperty("deny");
  });

  test("email_suppress shows the parsed address in full and fails closed on an unparsable one", () => {
    expect(buildGateMessage(`${P}email_suppress`, { recipient: "Jo <jo@example.invalid>", reason: "decline" })).toContain("<jo@example.invalid>");
    expect(buildGateCard(`${P}email_suppress`, { recipient: "a@example.invalid, b@example.invalid", reason: "decline" })).toEqual({
      deny: "The recipient could not be shown in full for review, so the suppression was not applied. Fix the recipient and try again.",
    });
  });

  test("hostile input never yields a card with hidden characters (deny or visible escape)", () => {
    for (const key of EMAIL_CARD_KEYS) {
      const r = buildGateCard(key, inputOf(HOSTILE));
      expect("deny" in r ? r.deny : r.card).not.toMatch(CONTROL_OR_BIDI);
    }
  });

  test("the card names the not-shown inputs of the other gated writes (generalised omission fix)", () => {
    expect(buildGateMessage(`${P}create_pull_request`, { title: "t", head: "h", body: "x".repeat(50) })).toContain("description of 50 characters is not shown here");
    expect(buildGateMessage(`${P}create_issue`, { title: "t", body: "xx", labels: ["bug"] })).toMatch(/labels \[bug\].*description of 2 characters is not shown/);
    expect(buildGateMessage(`${P}github_trigger_workflow`, { workflow_id: 1, ref: "main", inputs: { env: "prod" } })).toMatch(/inputs \[env\].*values are not shown/);
    expect(buildGateMessage(`${P}github_push_branch`, { branch: "b", force: true })).toMatch(/force-push was requested/);
    expect(buildGateMessage(`${P}plausible_create_site`, { domain: "example.com", timezone: "Europe/Paris" })).toContain("Europe/Paris");
    expect(buildGateMessage(`${P}workstream_issue_create`, { title: "t", body: "xx" })).toContain("description of 2 characters is not shown");
  });
});

describe("list and field truncation is never silent (#11303)", () => {
  test("a list past ten entries says how many more", () => {
    const labels = Array.from({ length: 13 }, (_, i) => `l${i}`);
    const msg = buildGateMessage(`${P}workstream_issue_update_fields`, { number: 1, labels });
    expect(msg).toContain("l9");
    expect(msg).not.toContain("l10");
    expect(msg).toContain("+3 more");
  });

  test("a long scalar ends with a visible ellipsis, and a huge one is clipped before cleaning", () => {
    const msg = buildGateMessage(`${P}create_issue`, { title: "T".repeat(5_000_000) });
    expect(msg).toContain(`${"T".repeat(120)}…`);
    expect(msg.length).toBeLessThan(400);
  });

  test("tag characters, the soft hyphen and the Arabic letter mark are stripped from plain cards", () => {
    const msg = buildGateMessage(`${P}create_issue`, { title: "a\u00ADb\u061Cc\u{E0041}d" });
    expect(msg).toContain("abcd");
    expect(CONTROL_OR_BIDI.test(msg)).toBe(false);
  });
});

describe("shared pre-approval keep-rule (#11303)", () => {
  test("isPreApprovable is true only for auto-approve tools", () => {
    expect(isPreApprovable(`${P}kb_share_list`)).toBe(true);
    expect(isPreApprovable(`${P}email_send`)).toBe(false);
    expect(isPreApprovable(`${P}never_registered`)).toBe(false);
    expect(isPreApprovable("constructor")).toBe(false);
  });

  test("pluginWildcard and parsePluginWildcard round-trip, and only the exact shape parses", () => {
    expect(pluginWildcard("my-server")).toBe("mcp__plugin_soleur_my-server__*");
    expect(parsePluginWildcard(pluginWildcard("my-server"))).toBe("my-server");
    for (const bad of ["mcp__plugin_soleur_My__*", "mcp__plugin_soleur___*", "mcp__plugin_soleur_a__b", "mcp__plugin_soleur_a__* ", "mcp__*"]) {
      expect(parsePluginWildcard(bad)).toBeNull();
    }
  });
});
