// Shared fixtures for the deleteAccount -> git-data erasure ledger tests
// (account-delete-git-data-ledger*.test.ts). `vi.mock` calls must stay in each test file (hoisting),
// so this exports only the id, the RPC name and the happy-path wiring of the supabase fakes.
import { vi, type Mock } from "vitest";

export const UID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
export const LEDGER_RPC = "record_git_data_erasure_pending";

export interface AccountDeleteFakes {
  mockFrom: Mock;
  mockRpc: Mock;
  mockAuth: { admin: { getUserById: Mock; deleteUser: Mock } };
  mockStorageFrom: Mock;
}

/** Wire the supabase fakes so deleteAccount(UID, ...) runs its whole cascade successfully. */
export function setupAccountDeleteFakes({ mockFrom, mockRpc, mockAuth, mockStorageFrom }: AccountDeleteFakes): void {
  mockAuth.admin.getUserById.mockResolvedValue({ data: { user: { id: UID, email: "t@example.test" } }, error: null });
  mockAuth.admin.deleteUser.mockResolvedValue({ data: {}, error: null });
  mockStorageFrom.mockReturnValue({
    list: vi.fn().mockResolvedValue({ data: [], error: null }),
    remove: vi.fn().mockResolvedValue({ data: [], error: null }),
  });
  mockFrom.mockImplementation(() => ({
    update: () => ({ eq: () => ({ in: () => Promise.resolve({ error: null }) }) }),
    delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
    select: () => ({ eq: () => Promise.resolve({ count: 1, data: [], error: null }) }),
  }));
  mockRpc.mockResolvedValue({ data: 0, error: null });
}
