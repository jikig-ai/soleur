"use client";
import { ErrorBoundaryView } from "@/components/error-boundary-view";

export default function Error(props: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return <ErrorBoundaryView {...props} feature="root-error-boundary" />;
}
