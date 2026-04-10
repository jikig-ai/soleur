import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

// Mock next/navigation
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

// Supabase query builder mock — thenable like the real client
function createQueryBuilder(data: unknown) {
  const result = { data, error: null };
  const builder = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    gt: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    single: vi.fn().mockReturnThis(),
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
  };
  return builder;
}

const mockConversationsWithCost = [
  {
    id: "conv-1",
    domain_leader: "cto",
    total_cost_usd: 0.0042,
    created_at: new Date(Date.now() - 3600000).toISOString(),
  },
  {
    id: "conv-2",
    domain_leader: "cmo",
    total_cost_usd: 0.0018,
    created_at: new Date(Date.now() - 7200000).toISOString(),
  },
];

let usersBuilder: ReturnType<typeof createQueryBuilder>;
let conversationsBuilder: ReturnType<typeof createQueryBuilder>;

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === "users") return usersBuilder;
      if (table === "conversations") return conversationsBuilder;
      return createQueryBuilder(null);
    },
  }),
}));

// Mock domain-leaders for server-side import
vi.mock("@/server/domain-leaders", () => ({
  DOMAIN_LEADERS: [
    { id: "cto", name: "CTO", title: "Chief Technology Officer" },
    { id: "cmo", name: "CMO", title: "Chief Marketing Officer" },
    { id: "cfo", name: "CFO", title: "Chief Financial Officer" },
  ],
}));

describe("BillingPage cost list", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    usersBuilder = createQueryBuilder({ subscription_status: "active" });
    conversationsBuilder = createQueryBuilder(mockConversationsWithCost);
  });

  it("renders conversation cost list with domain and cost", async () => {
    const { default: BillingPage } = await import(
      "@/app/(dashboard)/dashboard/billing/page"
    );
    render(<BillingPage />);

    await waitFor(() => {
      expect(screen.getByText(/api usage/i)).toBeInTheDocument();
    });

    // Verify cost figures are displayed with estimated label
    expect(screen.getByText(/\$0\.0042/)).toBeInTheDocument();
    expect(screen.getByText(/\$0\.0018/)).toBeInTheDocument();
  });

  it("shows empty state when no conversations have cost data", async () => {
    conversationsBuilder = createQueryBuilder([]);

    const { default: BillingPage } = await import(
      "@/app/(dashboard)/dashboard/billing/page"
    );
    render(<BillingPage />);

    await waitFor(() => {
      expect(screen.getByText(/no api usage yet/i)).toBeInTheDocument();
    });
  });
});
