import type { User } from "@supabase/supabase-js";

/**
 * Resolve a user's GitHub login from their Supabase auth metadata.
 *
 * Mirrors the existing detect-installation/route.ts behavior exactly: the login
 * comes from the OAuth session metadata (`user_name` / `preferred_username`),
 * NOT from a `users` table column. Extracted so detect-installation and repos
 * routes resolve the login identically.
 */
export function resolveGithubLogin(user: User): string | null {
  return (
    (user.user_metadata?.user_name as string | undefined) ??
    (user.user_metadata?.preferred_username as string | undefined) ??
    null
  );
}
