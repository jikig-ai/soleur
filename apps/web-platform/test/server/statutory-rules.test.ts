import { describe, it, expect } from "vitest";

// Phase 2 contract tests for the statutory-rules registry (operator-inbox-
// delegation). Pure module — no I/O, no mocks needed. All fixtures are
// synthesized (cq-test-fixtures-synthesized-only): invented senders/domains
// like dsar-requester@example-person.test, never real mail.
//
// References:
// - Plan: knowledge-base/project/plans/2026-06-10-feat-operator-inbox-delegation-plan.md
//   (rows for statutory-rules.ts / statutory-rules.test.ts; AC3e/AC3f)
// - Catalog anchors target knowledge-base/legal/statutory-response-catalog.md
//   (created in a later phase).

import {
  STATUTORY_RULES,
  PROBE_MARKER_PREFIX,
  matchProbeToken,
  matchStatutoryMetadata,
  matchStatutoryBody,
  isThinBody,
  normalizeEmailHtml,
  computeDueDate,
  formatDueDate,
  type StatutoryRule,
} from "@/lib/email-triage/statutory-rules";

const PLAIN_SENDER = "correspondent@example-person.test";
const PROBE_UUID = "3f2a9c1e-7b4d-4e2a-9f10-6c8d2e5a7b3c";

function ruleByClass(statutoryClass: StatutoryRule["statutoryClass"]): StatutoryRule {
  const rule = STATUTORY_RULES.find((r) => r.statutoryClass === statutoryClass);
  if (!rule) throw new Error(`no rule for class ${statutoryClass}`);
  return rule;
}

describe("STATUTORY_RULES registry invariants", () => {
  it("evaluates in pinned priority order: breach > service-of-process > dsar > regulator", () => {
    expect(STATUTORY_RULES.map((r) => r.statutoryClass)).toEqual([
      "breach",
      "service-of-process",
      "dsar",
      "regulator",
    ]);
  });

  it("has unique ruleIds and no probe class", () => {
    const ids = STATUTORY_RULES.map((r) => r.ruleId);
    expect(new Set(ids).size).toBe(ids.length);
    expect(STATUTORY_RULES.some((r) => (r.statutoryClass as string) === "probe")).toBe(false);
  });

  it("anchors every rule into the statutory response catalog with an excerpt", () => {
    expect(ruleByClass("dsar").catalogAnchor).toBe("statutory-response-catalog.md#dsar");
    expect(ruleByClass("breach").catalogAnchor).toBe("statutory-response-catalog.md#breach");
    expect(ruleByClass("service-of-process").catalogAnchor).toBe(
      "statutory-response-catalog.md#service-of-process",
    );
    expect(ruleByClass("regulator").catalogAnchor).toBe("statutory-response-catalog.md#regulator");
    for (const rule of STATUTORY_RULES) {
      expect(rule.catalogExcerpt.length).toBeGreaterThan(20);
    }
  });

  it("wires the statutory periods: DSAR calendar-month, breach 72h, SoP/regulator verify-instrument", () => {
    expect(ruleByClass("dsar").dueRule.kind).toBe("calendar-month");
    expect(ruleByClass("breach").dueRule).toMatchObject({ kind: "hours", hours: 72 });
    expect(ruleByClass("service-of-process").dueRule).toMatchObject({
      kind: "calendar-month",
      label: "verify the instrument's own deadline",
    });
    expect(ruleByClass("regulator").dueRule).toMatchObject({
      kind: "calendar-month",
      label: "verify the instrument's own deadline",
    });
  });
});

describe("matchStatutoryMetadata — subject-only positives per class", () => {
  it("matches a breach notification subject", () => {
    const rule = matchStatutoryMetadata({
      subject: "Notification of a personal data breach affecting your account",
      sender: "security-team@example-vendor.test",
    });
    expect(rule?.statutoryClass).toBe("breach");
  });

  it("matches a service-of-process subject", () => {
    const rule = matchStatutoryMetadata({
      subject: "Subpoena duces tecum — Case No. 2026-CV-1234",
      sender: "clerk@example-court.test",
    });
    expect(rule?.statutoryClass).toBe("service-of-process");
  });

  it("matches a DSAR subject", () => {
    const rule = matchStatutoryMetadata({
      subject: "Subject access request under GDPR",
      sender: "dsar-requester@example-person.test",
    });
    expect(rule?.statutoryClass).toBe("dsar");
  });

  it("matches a French DSAR subject", () => {
    const rule = matchStatutoryMetadata({
      subject: "Demande d'accès à mes données personnelles",
      sender: "demandeur@example-personne.test",
    });
    expect(rule?.statutoryClass).toBe("dsar");
  });

  it("matches a regulator subject", () => {
    const rule = matchStatutoryMetadata({
      subject: "Inquiry from your supervisory authority regarding processing records",
      sender: "case-officer@example-authority.test",
    });
    expect(rule?.statutoryClass).toBe("regulator");
  });

  it("matches a regulator by sender domain alone", () => {
    const rule = matchStatutoryMetadata({
      subject: "Courrier de suivi",
      sender: "agent-controle@cnil.fr",
    });
    expect(rule?.statutoryClass).toBe("regulator");
  });
});

describe("matchStatutoryBody", () => {
  it("matches a body-only DSAR (subject is vague)", () => {
    const rule = matchStatutoryBody(
      "Hello, I am writing to make a data subject access request for all information you hold about me.",
    );
    expect(rule?.statutoryClass).toBe("dsar");
  });

  it("matches a French DSAR body", () => {
    const rule = matchStatutoryBody(
      "Bonjour, je vous adresse une demande d'accès à mes données personnelles " +
        "conformément au RGPD. Merci de me répondre dans le délai légal.",
    );
    expect(rule?.statutoryClass).toBe("dsar");
  });

  it("never returns a probe rule for a probe-marker body", () => {
    expect(matchStatutoryBody(`automated check ${PROBE_MARKER_PREFIX}${PROBE_UUID}`)).toBeNull();
  });
});

describe("normalizeEmailHtml — HTML-only body positive", () => {
  // Keyword "data subject access request" split by an inline tag, a <wbr>,
  // an &nbsp; entity, and a soft hyphen — only normalization makes it match.
  const rawHtml =
    "<html><head><style>p { color: red; }</style></head><body>" +
    "<script>var tracker = 1;</script>" +
    "<p>Dear team,</p>" +
    "<p>I would like to make a <span>data&nbsp;subject</span> ac<wbr>cess&shy; request " +
    "for everything you hold about me.</p>" +
    "</body></html>";

  it("does NOT match on the raw HTML (entities/tags split the keyword)", () => {
    expect(matchStatutoryBody(rawHtml)).toBeNull();
  });

  it("matches after normalizeEmailHtml strips tags, decodes entities, removes soft hyphens", () => {
    const text = normalizeEmailHtml(rawHtml);
    expect(text).toContain("data subject access request");
    expect(matchStatutoryBody(text)?.statutoryClass).toBe("dsar");
  });

  it("strips script/style content, decodes common entities, removes zero-width chars", () => {
    const text = normalizeEmailHtml(
      "<style>body{}</style><script>alert(1)</script>" +
        "<p>Tom &amp; Co &lt;legal&gt; said &quot;hi&quot; &#39;there&#39;&nbsp;" +
        "zero\u200Bwidth\u200Cjoin\u200Ders and so\u00ADft hyphens</p>",
    );
    expect(text).not.toContain("alert");
    expect(text).not.toContain("color");
    // Entity-decoded angle-bracket content (`&lt;legal&gt;`) is stripped by the
    // post-decode tag pass — text extraction for keyword matching never renders
    // HTML, so no `<...>` survives (CodeQL js/incomplete-multi-char-sanitization).
    expect(text).toContain("Tom & Co");
    expect(text).toContain('said "hi" \'there\'');
    expect(text).not.toContain("<legal>");
    expect(text).toContain("zerowidthjoiners");
    expect(text).toContain("soft hyphens");
  });

  it("strips script blocks with malformed closing tags and nested partials (CodeQL js/bad-tag-filter + incomplete-multi-char-sanitization)", () => {
    // Closing tag with junk after the name (browsers tolerate `</script foo>`).
    const malformedClose = normalizeEmailHtml(
      "<p>before</p><script>evil()</script\t\n bar><p>data subject access request</p>",
    );
    expect(malformedClose).not.toContain("evil");
    expect(malformedClose).not.toContain("<script");
    expect(matchStatutoryBody(malformedClose)?.statutoryClass).toBe("dsar");

    // Nested/partial tag that defeats a single-pass strip: the inner removal
    // reveals an outer <script>...</script> the loop must catch.
    const nested = normalizeEmailHtml("<scr<script>nope</script>ipt>alert(1)</script><p>ok</p>");
    expect(nested).not.toContain("<script");
    expect(nested).not.toContain("nope");
  });
});

describe("matchStatutoryMetadata — attachment filename pass", () => {
  it("matches a DSAR from an attachment filename with a vague subject", () => {
    const rule = matchStatutoryMetadata({
      subject: "Documents for you",
      sender: "dsar-requester@example-person.test",
      attachmentFilenames: ["DSAR_request.pdf"],
    });
    expect(rule?.statutoryClass).toBe("dsar");
  });

  it("does not match ICO from a favicon.ico filename (case-sensitive acronym)", () => {
    const rule = matchStatutoryMetadata({
      subject: "New site assets",
      sender: "designer@example-vendor.test",
      attachmentFilenames: ["favicon.ico"],
    });
    expect(rule).toBeNull();
  });
});

describe("isThinBody — stub/short body heuristic", () => {
  it("treats stub bodies as thin", () => {
    expect(isThinBody("see attached")).toBe(true);
    expect(isThinBody("Please find attached.")).toBe(true);
    expect(isThinBody("")).toBe(true);
    expect(isThinBody("   \n  ")).toBe(true);
    expect(isThinBody(null)).toBe(true);
  });

  it("treats a normal mail body as not thin", () => {
    expect(
      isThinBody(
        "Hi Jean, thanks for the call earlier today. As discussed, here is the summary of the " +
          "onboarding steps we agreed on, plus the timeline for the next two sprints. Let me know " +
          "if anything is missing and we can adjust before Friday.",
      ),
    ).toBe(false);
  });
});

describe("priority — adjacent pairwise fixtures (first match wins)", () => {
  it("breach + service-of-process → breach", () => {
    const rule = matchStatutoryMetadata({
      subject: "Subpoena relating to a personal data breach investigation",
      sender: "clerk@example-court.test",
    });
    expect(rule?.statutoryClass).toBe("breach");
  });

  it("service-of-process + DSAR → service-of-process", () => {
    const rule = matchStatutoryMetadata({
      subject: "Summons concerning your handling of a subject access request",
      sender: "clerk@example-court.test",
    });
    expect(rule?.statutoryClass).toBe("service-of-process");
  });

  it("DSAR + regulator → dsar", () => {
    const rule = matchStatutoryMetadata({
      subject: "DSAR escalated to the supervisory authority",
      sender: "dsar-requester@example-person.test",
    });
    expect(rule?.statutoryClass).toBe("dsar");
  });

  it("regulator + probe marker → regulator from metadata, token still extracted separately", () => {
    const subject = `CNIL correspondence ${PROBE_MARKER_PREFIX}${PROBE_UUID}`;
    const rule = matchStatutoryMetadata({ subject, sender: PLAIN_SENDER });
    expect(rule?.statutoryClass).toBe("regulator");
    expect(matchProbeToken(subject)).toBe(PROBE_UUID);
  });
});

describe("vendor-mail negatives", () => {
  it.each([
    ["invoice", "Your invoice #4821 is ready", "billing@example-vendor.test"],
    [
      "newsletter with marketing data phrasing",
      "Weekly newsletter: how we are processing your data responsibly",
      "news@example-vendor.test",
    ],
    ["password reset", "Reset your password", "no-reply@example-vendor.test"],
    ["shipping update", "Your order has shipped", "orders@example-vendor.test"],
  ])("%s does not match any statutory rule", (_label, subject, sender) => {
    expect(matchStatutoryMetadata({ subject, sender })).toBeNull();
  });

  it("marketing body with 'processing your data' does not match DSAR", () => {
    expect(
      matchStatutoryBody(
        "Thanks for subscribing! We care deeply about processing your data securely and " +
          "responsibly. You can unsubscribe at any time from your account settings page.",
      ),
    ).toBeNull();
  });

  it("acronyms do not match inside longer words (DSAR/RGPD/CNIL word boundaries)", () => {
    expect(
      matchStatutoryMetadata({ subject: "ARGPDB conference agenda", sender: PLAIN_SENDER }),
    ).toBeNull();
    expect(
      matchStatutoryMetadata({ subject: "MYDSARB project kickoff", sender: PLAIN_SENDER }),
    ).toBeNull();
    expect(
      matchStatutoryMetadata({ subject: "ACNILB partnership notes", sender: PLAIN_SENDER }),
    ).toBeNull();
    expect(
      matchStatutoryMetadata({ subject: "ICONS and logos refresh", sender: PLAIN_SENDER }),
    ).toBeNull();
  });
});

describe("matchProbeToken", () => {
  it("exports the pinned probe marker prefix", () => {
    expect(PROBE_MARKER_PREFIX).toBe("SOLEUR-PROBE-");
  });

  it("extracts the uuid token from a probe subject", () => {
    expect(matchProbeToken(`Synthetic probe ${PROBE_MARKER_PREFIX}${PROBE_UUID} please ignore`)).toBe(
      PROBE_UUID,
    );
  });

  it("returns null for the marker shape without a token", () => {
    expect(matchProbeToken("SOLEUR-PROBE")).toBeNull();
    expect(matchProbeToken("SOLEUR-PROBE-")).toBeNull();
    expect(matchProbeToken("SOLEUR-PROBE-not-a-uuid")).toBeNull();
  });

  it("returns null for arbitrary subjects", () => {
    expect(matchProbeToken("Quarterly planning notes")).toBeNull();
  });

  it("probe-only subjects are NOT statutory", () => {
    expect(
      matchStatutoryMetadata({
        subject: `${PROBE_MARKER_PREFIX}${PROBE_UUID}`,
        sender: "probe-sender@example-monitor.test",
      }),
    ).toBeNull();
  });
});

describe("computeDueDate — calendar-month vs naive +30d discriminators", () => {
  const calendarMonth = ruleByClass("dsar").dueRule;
  const breach72h = ruleByClass("breach").dueRule;

  it("received 2026-01-31 → due 2026-02-28 (month-end clamp, non-leap)", () => {
    const due = computeDueDate("2026-01-31T09:00:00.000Z", calendarMonth);
    expect(due.toISOString()).toBe("2026-02-28T09:00:00.000Z");
  });

  it("received 2024-01-31 → due 2024-02-29 (leap year clamp)", () => {
    const due = computeDueDate("2024-01-31T09:00:00.000Z", calendarMonth);
    expect(due.toISOString()).toBe("2024-02-29T09:00:00.000Z");
  });

  it("received 2026-01-30 → due 2026-02-28 (clamp, not just the 31st)", () => {
    const due = computeDueDate("2026-01-30T09:00:00.000Z", calendarMonth);
    expect(due.toISOString()).toBe("2026-02-28T09:00:00.000Z");
  });

  it("received 2026-03-15 → due 2026-04-15 (same day next month, no clamp)", () => {
    const due = computeDueDate("2026-03-15T17:45:00.000Z", calendarMonth);
    expect(due.toISOString()).toBe("2026-04-15T17:45:00.000Z");
  });

  it("received 2026-12-31 → due 2027-01-31 (year rollover)", () => {
    const due = computeDueDate("2026-12-31T09:00:00.000Z", calendarMonth);
    expect(due.toISOString()).toBe("2027-01-31T09:00:00.000Z");
  });

  it("breach 72h rule is exactly +72 hours", () => {
    const due = computeDueDate("2026-06-01T08:30:00.000Z", breach72h);
    expect(due.toISOString()).toBe("2026-06-04T08:30:00.000Z");
  });
});

describe("formatDueDate", () => {
  it("formats a calendar-month due date as 'due <date> — <label>'", () => {
    const dsar = ruleByClass("dsar");
    const formatted = formatDueDate("2026-01-31T09:00:00.000Z", dsar.dueRule);
    expect(formatted.startsWith("due 28 Feb 2026")).toBe(true);
    expect(formatted).toContain("—");
    expect(formatted).toContain(dsar.dueRule.label);
  });

  it("formats an hours due date with the deadline time in UTC", () => {
    const breach = ruleByClass("breach");
    const formatted = formatDueDate("2026-06-01T08:30:00.000Z", breach.dueRule);
    expect(formatted.startsWith("due 4 Jun 2026, 08:30 UTC")).toBe(true);
    expect(formatted).toContain(breach.dueRule.label);
  });
});
