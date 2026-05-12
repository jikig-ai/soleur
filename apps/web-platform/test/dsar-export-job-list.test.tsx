import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
}));

import {
  DsarExportJobList,
  type DsarExportJobRow,
} from "@/components/settings/dsar-export-job-list";

// Phase 8 UI tests for the DSAR job list.
//
// Plan rev-2 FR6 + AC24 + AC31.

const baseRow: DsarExportJobRow = {
  id: "job-1",
  status: "pending",
  requested_at: "2026-05-12T10:00:00Z",
  signed_url_expires_at: null,
  failure_reason: null,
  bundle_size_bytes: null,
};

describe("DsarExportJobList", () => {
  beforeEach(() => cleanup());
  afterEach(() => cleanup());

  it("shows empty-state copy when there are no jobs", () => {
    render(<DsarExportJobList initialJobs={[]} />);
    expect(
      screen.getByText(/haven't requested any data exports yet/i),
    ).toBeInTheDocument();
  });

  it("disables the 'Download my data' trigger when an active job exists (AC31)", () => {
    render(<DsarExportJobList initialJobs={[{ ...baseRow, status: "running" }]} />);
    const btn = screen.getByRole("button", { name: /download my data/i });
    expect(btn).toBeDisabled();
  });

  it("a `completed` row exposes a Download link", () => {
    render(
      <DsarExportJobList
        initialJobs={[
          {
            ...baseRow,
            id: "job-completed",
            status: "completed",
            signed_url_expires_at: "2026-05-19T10:00:00Z",
            bundle_size_bytes: 1024 * 1024 * 5,
          },
        ]}
      />,
    );
    const link = screen.getByRole("link", { name: /download/i });
    expect(link).toHaveAttribute(
      "href",
      "/api/account/export/job-completed/download",
    );
  });

  it("an `expired` row exposes a 'Re-request' button (AC24)", () => {
    render(
      <DsarExportJobList
        initialJobs={[{ ...baseRow, id: "job-expired", status: "expired" }]}
      />,
    );
    expect(screen.getByRole("button", { name: /re-request/i })).toBeInTheDocument();
  });

  it("a `failed` row surfaces the failure_reason inline", () => {
    render(
      <DsarExportJobList
        initialJobs={[
          {
            ...baseRow,
            id: "job-failed",
            status: "failed",
            failure_reason: "job_timeout",
          },
        ]}
      />,
    );
    expect(screen.getByText(/reason: job_timeout/i)).toBeInTheDocument();
  });

  it("renders status label per spec FR6 (pending/running/delivered/expired)", () => {
    const jobs: DsarExportJobRow[] = [
      { ...baseRow, id: "j1", status: "pending" },
      { ...baseRow, id: "j2", status: "running" },
      { ...baseRow, id: "j3", status: "delivered" },
      { ...baseRow, id: "j4", status: "expired" },
    ];
    render(<DsarExportJobList initialJobs={jobs} />);
    expect(screen.getByTestId("job-status-j1")).toHaveTextContent("Queued");
    expect(screen.getByTestId("job-status-j2")).toHaveTextContent(
      /preparing your bundle/i,
    );
    expect(screen.getByTestId("job-status-j3")).toHaveTextContent("Downloaded");
    expect(screen.getByTestId("job-status-j4")).toHaveTextContent("Expired");
  });
});
