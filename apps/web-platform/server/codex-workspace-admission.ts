/** Observations only: a later workspace switch still needs a durable fence. */
export async function verifyCodexWorkspace(input: {
  conversationWorkspaceId: string;
  bindingWorkspaceId: string;
  conversationRepoUrl: string | null | undefined;
  readWorkspace: () => Promise<string | null>;
  readRepo: (workspaceId: string) => Promise<{ url: string | null; degraded: boolean }>;
  assertCurrent: () => void;
}): Promise<void> {
  const refuse: () => never = () => { throw new Error("Codex conversation not found in the current workspace"); };
  const first = await input.readWorkspace();
  input.assertCurrent();
  if (!first || first !== input.conversationWorkspaceId || first !== input.bindingWorkspaceId) refuse();
  const repo = await input.readRepo(first);
  input.assertCurrent();
  if (repo.degraded || !repo.url || repo.url !== input.conversationRepoUrl) refuse();
  const last = await input.readWorkspace();
  input.assertCurrent();
  if (last !== first) refuse();
}
