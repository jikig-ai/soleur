import Link from "next/link";

export function CtaBanner() {
  return (
    <div className="fixed bottom-0 left-0 right-0 z-40 border-t border-neutral-800 bg-neutral-900/95 px-4 py-3 backdrop-blur-sm">
      <div className="mx-auto flex max-w-3xl items-center justify-between gap-4">
        <p className="text-sm text-neutral-300">
          This document was created with{" "}
          <span className="font-medium text-amber-400">Soleur</span> — AI
          agents for every department of your startup.
        </p>
        <Link
          href="/signup"
          className="shrink-0 rounded-lg bg-amber-500 px-4 py-2 text-sm font-medium text-black transition-colors hover:bg-amber-400"
        >
          Create your account
        </Link>
      </div>
    </div>
  );
}
