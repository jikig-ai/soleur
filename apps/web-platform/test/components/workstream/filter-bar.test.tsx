import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import {
  deriveFilterOptions,
  emptyFilters,
  type WorkstreamFilters,
} from "@/lib/workstream";
import { FilterBar } from "@/components/workstream/filter-bar";

function opts(
  over: Partial<ReturnType<typeof deriveFilterOptions>> = {},
): ReturnType<typeof deriveFilterOptions> {
  return { ...baseOpts(), ...over };
}
function baseOpts(): ReturnType<typeof deriveFilterOptions> {
  return {
    priorities: ["urgent", "high", "low"],
    roles: ["cto", "cmo"],
    users: ["alice"],
    hasUnassigned: true,
    domains: ["domain/engineering", "domain/product"],
    creators: ["Soleur", "octocat"],
  };
}

afterEach(() => cleanup());

describe("FilterBar", () => {
  it("renders Priority/Status/Assignee/Domain when options exist", () => {
    render(
      <FilterBar options={opts()} filters={emptyFilters()} onChange={() => {}} />,
    );
    expect(screen.getByRole("button", { name: /priority/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /status/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /assignee/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /domain/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /created by/i })).toBeTruthy();
  });

  it("toggling a Created by checkbox calls onChange with that creator added", () => {
    const onChange = vi.fn();
    render(
      <FilterBar options={opts()} filters={emptyFilters()} onChange={onChange} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /created by/i }));
    fireEvent.click(screen.getByRole("checkbox", { name: /octocat/i }));
    const next = onChange.mock.calls[0][0] as WorkstreamFilters;
    expect(next.creators.has("octocat")).toBe(true);
  });

  it("hides the Created by dimension when no creators are present", () => {
    render(
      <FilterBar
        options={opts({ creators: [] })}
        filters={emptyFilters()}
        onChange={() => {}}
      />,
    );
    expect(screen.queryByRole("button", { name: /created by/i })).toBeNull();
  });

  it("hides a dimension whose option list is empty (Domain); Status always shows", () => {
    render(
      <FilterBar
        options={opts({ domains: [] })}
        filters={emptyFilters()}
        onChange={() => {}}
      />,
    );
    expect(screen.queryByRole("button", { name: /domain/i })).toBeNull();
    expect(screen.getByRole("button", { name: /status/i })).toBeTruthy();
  });

  it("toggling a priority checkbox calls onChange with that priority added", () => {
    const onChange = vi.fn();
    render(
      <FilterBar options={opts()} filters={emptyFilters()} onChange={onChange} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /priority/i }));
    const urgent = screen.getByRole("checkbox", { name: /urgent/i });
    fireEvent.click(urgent);
    expect(onChange).toHaveBeenCalledTimes(1);
    const next = onChange.mock.calls[0][0] as WorkstreamFilters;
    expect(next.priorities.has("urgent")).toBe(true);
  });

  it("Status is a 3-option radio; selecting Open calls onChange with status=open", () => {
    const onChange = vi.fn();
    render(
      <FilterBar options={opts()} filters={emptyFilters()} onChange={onChange} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /status/i }));
    fireEvent.click(screen.getByRole("radio", { name: /^open$/i }));
    const next = onChange.mock.calls[0][0] as WorkstreamFilters;
    expect(next.status).toBe("open");
  });

  it("shows an active-count badge reflecting the selection", () => {
    const filters: WorkstreamFilters = {
      ...emptyFilters(),
      priorities: new Set(["urgent", "high"]),
    };
    render(<FilterBar options={opts()} filters={filters} onChange={() => {}} />);
    const priorityBtn = screen.getByRole("button", { name: /priority/i });
    expect(within(priorityBtn).getByText("2")).toBeTruthy();
  });

  it("assignee menu includes an Unassigned option when hasUnassigned", () => {
    render(
      <FilterBar options={opts()} filters={emptyFilters()} onChange={() => {}} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /assignee/i }));
    expect(screen.getByRole("checkbox", { name: /unassigned/i })).toBeTruthy();
  });
});
