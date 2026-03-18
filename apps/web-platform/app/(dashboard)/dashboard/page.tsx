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
      {/* Header */}
      <div className="mb-8 flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-white">
          Choose a domain leader
        </h1>
        {user?.email && (
          <span className="text-sm text-neutral-500">{user.email}</span>
        )}
      </div>

      {/* Leader grid */}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        {DOMAIN_LEADERS.map((leader) => (
          <Link
            key={leader.id}
            href={`/dashboard/chat/new?leader=${leader.id}`}
            className="group rounded-xl border border-neutral-800 bg-neutral-900 p-5 transition-colors hover:border-neutral-600"
          >
            <div className="mb-1 flex items-center gap-3">
              <span className="text-base font-semibold text-white">
                {leader.name}
              </span>
              <span className="text-sm text-neutral-500">{leader.title}</span>
            </div>
            <p className="text-sm leading-relaxed text-neutral-400">
              {leader.description}
            </p>
          </Link>
        ))}
      </div>
    </div>
  );
}
