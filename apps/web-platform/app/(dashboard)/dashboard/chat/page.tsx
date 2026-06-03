import { redirect } from "next/navigation";

// Redirect stub — NOT a rendered surface (UX tier stays advisory).
//
// The chat segment is `chat/layout.tsx` + `chat/[conversationId]/page.tsx`;
// there is no page at the bare `/dashboard/chat` slot, so App Router renders the
// global 404 ("This page could not be found") for any navigation that lands
// there. The NoApiKeyBanner "Accept access" (pending-delegation) CTA links to
// bare `/dashboard/chat` (no-api-key-banner.tsx), so a granted-but-keyless
// member hits that 404. Land them in the new-conversation composer instead,
// inside the chat layout where the DelegationBanner's accept action renders.
export default function ChatIndexPage() {
  redirect("/dashboard/chat/new");
}
