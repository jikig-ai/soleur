import { describe, it, expect } from "vitest";
import {
  GITHUB_EVENT_STRATEGIES,
  resolveOwningDomain,
  isKnownGitHubActionClass,
} from "@/server/inngest/functions/github-event-strategies";

describe("github-event-strategies", () => {
  describe("strategy table shape", () => {
    it("has exactly 4 entries (the 4 event classes)", () => {
      expect(Object.keys(GITHUB_EVENT_STRATEGIES).sort()).toEqual([
        "engineering.ci_failed",
        "engineering.pr_review_pending",
        "security.cve_alert",
        "triage.p0p1_issue",
      ]);
    });

    it("each strategy declares sourceRefPrefix + urgency + redactSource", () => {
      for (const [name, strategy] of Object.entries(GITHUB_EVENT_STRATEGIES)) {
        expect(strategy.sourceRefPrefix, `${name}.sourceRefPrefix`).toBeTruthy();
        expect(strategy.urgency, `${name}.urgency`).toBeTruthy();
        expect(strategy.redactSource, `${name}.redactSource`).toBeTruthy();
      }
    });
  });

  describe("resolveOwningDomain (label routing)", () => {
    it("pr_review_pending → engineering (static)", () => {
      expect(resolveOwningDomain("engineering.pr_review_pending", {})).toBe("engineering");
    });

    it("ci_failed → engineering (static)", () => {
      expect(resolveOwningDomain("engineering.ci_failed", {})).toBe("engineering");
    });

    it("cve_alert → security (static)", () => {
      expect(resolveOwningDomain("security.cve_alert", {})).toBe("security");
    });

    it("p0p1_issue with type/feature label → product", () => {
      const body = { issue: { labels: [{ name: "type/feature" }] } };
      expect(resolveOwningDomain("triage.p0p1_issue", body)).toBe("product");
    });

    it("p0p1_issue without type/feature label → engineering", () => {
      const body = { issue: { labels: [{ name: "type/bug" }] } };
      expect(resolveOwningDomain("triage.p0p1_issue", body)).toBe("engineering");
    });

    it("p0p1_issue with malformed body → engineering (fail-closed)", () => {
      expect(resolveOwningDomain("triage.p0p1_issue", null)).toBe("engineering");
      expect(resolveOwningDomain("triage.p0p1_issue", { issue: null })).toBe("engineering");
      expect(resolveOwningDomain("triage.p0p1_issue", { issue: { labels: "not-an-array" } })).toBe(
        "engineering",
      );
    });
  });

  describe("redactSource correctness", () => {
    it("pr_review_pending uses pr_title", () => {
      expect(GITHUB_EVENT_STRATEGIES["engineering.pr_review_pending"].redactSource).toBe(
        "pr_title",
      );
    });

    it("p0p1_issue uses issue_body", () => {
      expect(GITHUB_EVENT_STRATEGIES["triage.p0p1_issue"].redactSource).toBe("issue_body");
    });

    it("cve_alert uses cve_description", () => {
      expect(GITHUB_EVENT_STRATEGIES["security.cve_alert"].redactSource).toBe("cve_description");
    });
  });

  describe("isKnownGitHubActionClass type-guard", () => {
    it("returns true for each registered class", () => {
      expect(isKnownGitHubActionClass("engineering.pr_review_pending")).toBe(true);
      expect(isKnownGitHubActionClass("security.cve_alert")).toBe(true);
    });

    it("returns false for unknown strings (including stripe + kb-drift)", () => {
      expect(isKnownGitHubActionClass("finance.payment_failed")).toBe(false);
      expect(isKnownGitHubActionClass("knowledge.kb_drift")).toBe(false);
      expect(isKnownGitHubActionClass("")).toBe(false);
    });
  });
});
