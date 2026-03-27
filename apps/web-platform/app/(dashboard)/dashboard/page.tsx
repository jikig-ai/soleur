import Link from "next/link";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import { createClient } from "@/lib/supabase/server";

export default async function DashboardPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className="mx-auto max-w-5xl px-6 py-10">
      {/* Command Center header */}
      <div className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-white">
            Command Center
          </h1>
          <p className="mt-1 text-sm text-neutral-500">
            One command center, {DOMAIN_LEADERS.length} departments
          </p>
        </div>
        {user?.email && (
          <span className="text-sm text-neutral-500">{user.email}</span>
        )}
      </div>

      {/* Primary: Start a conversation (auto-routed) */}
      <div className="mb-10">
        <Link
          href="/dashboard/chat/new"
          className="flex w-full items-center justify-center rounded-xl border border-neutral-700 bg-neutral-900 px-6 py-5 text-sm text-neutral-400 transition-colors hover:border-neutral-500 hover:text-white"
        >
          Start a conversation &mdash; the right experts will show up
        </Link>
      </div>

      {/* Secondary: Domain leader discovery */}
      <div className="mb-4">
        <h2 className="text-sm font-medium text-neutral-500">
          Or talk to a specific leader
        </h2>
      </div>
      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        {DOMAIN_LEADERS.map((leader) => (
          <Link
            key={leader.id}
            href={`/dashboard/chat/new?leader=${leader.id}`}
            className="group rounded-lg border border-neutral-800 bg-neutral-900/50 p-4 transition-colors hover:border-neutral-600"
          >
            <div className="mb-1 flex items-center gap-3">
              <span className="text-sm font-semibold text-white">
                {leader.name}
              </span>
              <span className="text-xs text-neutral-500">{leader.title}</span>
            </div>
            <p className="text-xs leading-relaxed text-neutral-500">
              {leader.description}
            </p>
          </Link>
        ))}
      </div>
    </div>
  );
}
