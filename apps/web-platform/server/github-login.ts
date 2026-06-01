import logger from "@/server/logger";

/**
 * Minimal structural type for the service client's GoTrue admin surface.
 * Only `auth.admin.getUserById` is needed.
 */
interface AdminClientLike {
  auth: {
    admin: {
      getUserById: (id: string) => Promise<{
        data: {
          user: {
            identities?:
              | {
                  provider: string;
                  identity_data?: Record<string, unknown> | null;
                }[]
              | null;
          } | null;
        } | null;
        error: unknown;
      }>;
    };
  };
}

/**
 * Resolve a user's GitHub login (account name) for installation discovery.
 *
 * Mirrors the existing detect-installation/install route behavior exactly:
 *   1. Prefer the provider-controlled GitHub identity from the GoTrue admin API
 *      (`auth.admin.getUserById` → identities → provider === "github" →
 *      identity_data.user_name). `user.identities` from `getUser()` can be null
 *      for email-first users who later linked GitHub, and `user_metadata` is
 *      user-mutable, so neither is trusted here.
 *   2. Fall back to the stored `users.github_username` for email-only users
 *      (the caller passes it in, having already read the `users` row).
 *
 * Returns null when no login can be resolved.
 */
export async function resolveGithubLogin(
  service: AdminClientLike,
  userId: string,
  storedGithubUsername?: string | null,
): Promise<string | null> {
  let githubLogin: string | undefined;
  try {
    const { data: adminUser, error: adminError } =
      await service.auth.admin.getUserById(userId);
    if (adminError) {
      logger.error(
        { err: adminError, userId },
        "auth.admin.getUserById failed during login resolution",
      );
    }
    const githubIdentity = adminUser?.user?.identities?.find(
      (i) => i.provider === "github",
    );
    githubLogin = githubIdentity?.identity_data?.user_name as
      | string
      | undefined;
  } catch (err) {
    logger.error(
      { err, userId },
      "Failed to resolve GitHub identity for login resolution",
    );
  }

  // Fallback: stored github_username for email-only users.
  if (!githubLogin) {
    githubLogin = storedGithubUsername ?? undefined;
  }

  return githubLogin ?? null;
}
