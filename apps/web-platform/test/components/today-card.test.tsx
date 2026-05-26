import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { TodayCard } from "@/components/dashboard/today-card";

// PR-H (#3244) Phase 6 — source-aware TodayCard variants.
// AC5 matrix: 3 sources × N owning_domain affordance correctness.
// AC6: CVE / secret-scan cards render ID + severity only (no draft body).

const baseProps = {
  id: "msg-1",
  draftPreview: "Hello founder",
  urgency: "normal",
};

describe("TodayCard — source variants (AC5)", () => {
  it("renders stripe/cfo with Send/Edit/Discard buttons", () => {
    render(
      <TodayCard
        {...baseProps}
        source="stripe"
        sourceRef={null}
        owningDomain="cfo"
      />,
    );
    expect(screen.getByLabelText(/Send draft/)).toBeInTheDocument();
    expect(screen.getByLabelText(/Edit draft/)).toBeInTheDocument();
    expect(screen.getByLabelText(/Discard draft/)).toBeInTheDocument();
  });

  it("renders github/engineering pr_review with 'Spawn review agent' button", () => {
    render(
      <TodayCard
        {...baseProps}
        source="github"
        sourceRef="pr-jikig-ai-soleur-4066"
        owningDomain="engineering"
        draftPreview="fix: leak in foo path (https://github.com/x/y/pull/4066)"
      />,
    );
    expect(screen.getByLabelText(/Let CTO spawn a PR-review agent/)).toBeInTheDocument();
  });

  it("renders github/engineering ci_failed with 'Spawn fix agent' button", () => {
    render(
      <TodayCard
        {...baseProps}
        source="github"
        sourceRef="ci-88991"
        owningDomain="engineering"
        draftPreview="CI failed: build"
      />,
    );
    expect(screen.getByLabelText(/Let CTO spawn a CI-fix agent/)).toBeInTheDocument();
  });

  it("renders github/triage issue with 'Spawn triage agent' button", () => {
    render(
      <TodayCard
        {...baseProps}
        source="github"
        sourceRef="issue-jikig-ai-soleur-999"
        owningDomain="triage"
        draftPreview="Add SSO"
      />,
    );
    expect(screen.getByLabelText(/Let CTO spawn an issue-triage agent/)).toBeInTheDocument();
  });

  it("renders kb-drift/knowledge with 'Fix link' button (direct-action, no leader)", () => {
    render(
      <TodayCard
        {...baseProps}
        source="kb-drift"
        sourceRef="link-deadbeef00000000"
        owningDomain="knowledge"
        draftPreview="Broken link in foo.md → missing.md"
      />,
    );
    expect(screen.getByLabelText(/^Fix link$/)).toBeInTheDocument();
    // No leader-delegation buttons on KB-drift cards.
    expect(screen.queryByLabelText(/Let CTO/)).not.toBeInTheDocument();
  });

  it("renders kb-drift/knowledge with 'Update anchor' button when source_ref is anchor-*", () => {
    render(
      <TodayCard
        {...baseProps}
        source="kb-drift"
        sourceRef="anchor-cafef00d00000000"
        owningDomain="knowledge"
        draftPreview="Broken anchor in foo.md → bar.ts:100"
      />,
    );
    expect(screen.getByLabelText(/^Update anchor$/)).toBeInTheDocument();
  });
});

describe("TodayCard — CVE / secret-scan render (AC6)", () => {
  it("renders CVE card with ID + severity badge but NOT the body", () => {
    render(
      <TodayCard
        {...baseProps}
        source="github"
        sourceRef="cve-GHSA-abcd-1234-efgh"
        owningDomain="security"
        urgency="critical"
        draftPreview="GHSA-abcd-1234-efgh (critical): Remote code execution at 198.51.100.42"
      />,
    );
    const cveContainer = screen.getByTestId("today-card-cve");
    expect(cveContainer).toBeInTheDocument();
    expect(screen.getByTestId("cve-id")).toHaveTextContent("GHSA-abcd-1234-efgh");
    expect(screen.getByTestId("severity-badge")).toHaveTextContent(/critical/);
    // AC6: draft-preview-body MUST NOT be in the DOM for CVE cards.
    expect(screen.queryByTestId("draft-preview-body")).not.toBeInTheDocument();
  });

  it("renders secret-scan card with ID + severity only", () => {
    render(
      <TodayCard
        {...baseProps}
        source="github"
        sourceRef="secret-scan-42"
        owningDomain="security"
        urgency="critical"
        draftPreview="alert-42 (high): leaked API token detected in commit"
      />,
    );
    expect(screen.getByTestId("today-card-cve")).toBeInTheDocument();
    expect(screen.queryByTestId("draft-preview-body")).not.toBeInTheDocument();
  });
});

describe("TodayCard — render-time redaction (Art. 14 gate)", () => {
  it("redacts an email in a github/pr draft body before render", () => {
    render(
      <TodayCard
        {...baseProps}
        source="github"
        sourceRef="pr-jikig-ai-soleur-4066"
        owningDomain="engineering"
        draftPreview="reach me at alice@example.com on this PR"
      />,
    );
    const body = screen.getByTestId("draft-preview-body");
    expect(body.textContent).toContain("[redacted-email]");
    expect(body.textContent).not.toContain("alice@example.com");
  });

  it("does NOT redact stripe drafts (CFO path untouched — R2 mitigation)", () => {
    render(
      <TodayCard
        {...baseProps}
        source="stripe"
        sourceRef={null}
        owningDomain="cfo"
        draftPreview="Reach me at alice@example.com to fix payment"
      />,
    );
    const body = screen.getByTestId("draft-preview-body");
    // Stripe path renders raw — CFO drafts are LLM-output, not third-party text.
    expect(body.textContent).toContain("alice@example.com");
  });
});
