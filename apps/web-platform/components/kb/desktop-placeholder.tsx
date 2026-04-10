export function DesktopPlaceholder() {
  return (
    <div className="hidden h-full items-center justify-center md:flex">
      <div className="text-center">
        <svg
          width="48"
          height="48"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1"
          className="mx-auto mb-3 text-neutral-600"
        >
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <p className="text-sm text-neutral-500">Select a file to view</p>
        <p className="mt-1 text-xs text-neutral-600">
          Choose a file from the sidebar to preview its contents
        </p>
      </div>
    </div>
  );
}
