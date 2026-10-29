/**
 * #4672 task 3.2 / AC14: the copy deck is a set of constants a string test can hold to the wireframe rules.
 *   - no OUTCOME word (sent, ran, executed, delivered) anywhere a card, thread line, notification or agent message reads;
 *   - "Released to your agent" is present;
 *   - push and email copy is CONTENT-FREE for every gated tool: no action type, recipient, repo, branch, document, subject
 *     or agent text. Only {first_name}, {workspace_name} and the expiry date-time may be interpolated, and only in the email;
 *   - the workspace-autonomy card wording is marked PROVISIONAL until CPO and CLO sign it off.
 */
import { describe, expect, it } from "vitest";
import {
  APPROVAL_COPY,
  APPROVAL_LANDING_COPY,
  APPROVAL_NOTIFY_COPY,
  APPROVAL_STATE_COPY,
  AUTONOMOUS_CARD_COPY_PROVISIONAL,
  approvalEmailFootnote,
  approvalEmailLines,
  formatExpiry,
  formatExpiryDateTimeTz,
} from "@/lib/approval-copy";
import { AGENT_WAIT_MINUTES } from "@/lib/approval-card-state";
import { DEFAULT_WAIT_MS } from "@/server/approval/waiters";
import { renderApprovalInboxTitle } from "@/server/approval/render";
import { canonicalizeAction } from "@/server/approval/canonical";
import { SAMPLES, TOOLS } from "./fixtures";

const OUTCOME_WORDS = /\b(sent|ran|executed|delivered)\b/i;

/** Every string reachable from a constant, calling the function-valued entries with representative arguments. */
function collect(v: unknown, out: string[] = []): string[] {
  if (typeof v === "string") out.push(v);
  else if (typeof v === "function") {
    for (const args of [[5], [3], ["Priya", "Owner"], ["email"]] as unknown[][]) {
      try {
        const r = (v as (...a: unknown[]) => unknown)(...args);
        if (typeof r === "string") out.push(r);
      } catch {
        /* wrong arity for this probe */
      }
    }
  } else if (v && typeof v === "object") Object.values(v).forEach((x) => collect(x, out));
  return out;
}

describe("copy deck: no outcome claim (AC14)", () => {
  const all = [
    ...collect(APPROVAL_COPY),
    ...collect(APPROVAL_STATE_COPY),
    ...collect(APPROVAL_LANDING_COPY),
    ...collect(APPROVAL_NOTIFY_COPY),
    ...collect(AUTONOMOUS_CARD_COPY_PROVISIONAL),
    ...approvalEmailLines("requested", { firstName: "Dana", workspaceName: "Jikigai", expiresAt: "2026-10-29T10:42:00Z" }),
    ...approvalEmailLines("expired", { firstName: "Dana", workspaceName: "Jikigai" }),
    approvalEmailFootnote("Jikigai"),
  ];

  it("walks a non-trivial set of strings (the check is not vacuous)", () => {
    expect(all.length).toBeGreaterThan(60);
  });

  it("contains none of the outcome words sent, ran, executed, delivered", () => {
    for (const s of all) expect(s, s).not.toMatch(OUTCOME_WORDS);
  });

  it("the guard itself bites: a planted outcome word is caught", () => {
    expect("The email was sent.").toMatch(OUTCOME_WORDS);
    expect("Your consent matters").not.toMatch(OUTCOME_WORDS);
  });

  it("carries 'Released to your agent' and the approved two-state split", () => {
    expect(APPROVAL_COPY.releasedBadge).toBe("Released to your agent");
    expect(APPROVAL_COPY.releasedTitle).toBe("Released, your agent is continuing");
    expect(APPROVAL_COPY.approvedLate).toBe("Approved. Ask your agent again.");
  });

  it("the inbox row text never claims an outcome either, for every state of every tool", () => {
    for (const tool of Object.keys(SAMPLES)) {
      const s = SAMPLES[tool];
      const action = canonicalizeAction(tool, s.input, s.server);
      for (const st of ["pending", "approved", "rejected", "consumed", "expired", "expired_after_approval"] as const) {
        const t = renderApprovalInboxTitle(action, st, "static");
        // The bound VALUES are the agent's own text (a subject can say anything); the framing words are ours.
        const framing = t.replace(/(to|for|address|commit|branch|in|pull request|into|workflow|on) [^,.]*/g, "");
        expect(framing, t).not.toMatch(OUTCOME_WORDS);
      }
    }
  });
});

describe("notification copy is content-free for every gated tool (privacy notice scope #8532)", () => {
  const ACTION_WORDS = /\b(email|e-mail|reply|commit|commits|branch|repository|repo|pull request|workflow|share link|document|autonomous|setting|recipient|subject|push(ed)? code|github)\b/i;

  it("push title and body name no action", () => {
    for (const k of ["requested", "expired"] as const) {
      expect(APPROVAL_NOTIFY_COPY[k].pushTitle).not.toMatch(ACTION_WORDS);
      expect(APPROVAL_NOTIFY_COPY[k].pushBody).not.toMatch(ACTION_WORDS);
    }
  });

  it("email subject, heading and body lines name no action (the footnote's 'this email' is the medium)", () => {
    for (const k of ["requested", "expired"] as const) {
      expect(APPROVAL_NOTIFY_COPY[k].emailSubject).not.toMatch(ACTION_WORDS);
      expect(APPROVAL_NOTIFY_COPY[k].emailHeading).not.toMatch(ACTION_WORDS);
      for (const l of approvalEmailLines(k, { firstName: "Dana", workspaceName: "Jikigai", expiresAt: "2026-10-29T10:42:00Z" })) {
        expect(l, l).not.toMatch(ACTION_WORDS);
      }
    }
  });

  it("the ONLY interpolations are first name, workspace name and the expiry; nothing else can vary", () => {
    const base = approvalEmailLines("requested", {});
    const withAll = approvalEmailLines("requested", { firstName: "ZZFIRST", workspaceName: "ZZWS", expiresAt: "2026-10-29T10:42:00Z" });
    const joined = withAll.join("\n");
    expect(joined).toContain("ZZFIRST");
    expect(joined).toContain("ZZWS");
    expect(joined).toContain("Thu 29 Oct, 10:42 UTC");
    // Removing exactly those three values yields the no-value text: no other variable part exists.
    expect(joined.replace("ZZFIRST", "").replace("ZZWS", "your workspace").replace(" on Thu 29 Oct, 10:42 UTC", "").replace("Hi ,", "Hi,")).toBe(base.join("\n"));
  });

  it("formats the expiry as an unambiguous UTC date-time and tolerates a bad value", () => {
    expect(formatExpiryDateTimeTz("2026-10-29T10:42:00Z")).toBe("Thu 29 Oct, 10:42 UTC");
    expect(formatExpiryDateTimeTz("nonsense")).toBe("");
    expect(formatExpiryDateTimeTz(null)).toBe("");
  });
});

describe("the autonomous-mode card wording is PROVISIONAL (CPO and CLO sign-off pending)", () => {
  it("is flagged provisional with empty sign-off fields", () => {
    expect(AUTONOMOUS_CARD_COPY_PROVISIONAL.PROVISIONAL).toBe(true);
    expect(AUTONOMOUS_CARD_COPY_PROVISIONAL.signOff).toEqual({ cpo: null, clo: null });
  });
});

describe("shared timing and countdown", () => {
  it("the card's wait minutes equal the server's wait (lockstep)", () => {
    expect(AGENT_WAIT_MINUTES * 60_000).toBe(DEFAULT_WAIT_MS);
  });

  it("formats the expiry chip: hours and minutes, amber under an hour, Expired past it", () => {
    const now = Date.parse("2026-10-28T10:00:00Z");
    expect(formatExpiry("2026-10-29T09:41:00Z", now)).toEqual({ text: "Expires in 23h 41m", urgent: false, past: false });
    expect(formatExpiry("2026-10-28T10:38:00Z", now)).toEqual({ text: "Expires in 38m", urgent: true, past: false });
    expect(formatExpiry("2026-10-28T09:59:00Z", now)).toEqual({ text: "Expired", urgent: true, past: true });
    expect(formatExpiry("bad", now).text).toBe("");
  });
});
