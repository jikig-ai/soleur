/**
 * Redirect mappings from old /pages/*.html URLs to new clean URLs.
 * Used by page-redirects.njk to generate meta-refresh redirect pages
 * so that existing Google index entries and external links still work.
 */
export default function () {
  return [
    { from: "pages/agents.html", to: "/agents/" },
    { from: "pages/skills.html", to: "/skills/" },
    { from: "pages/vision.html", to: "/vision/" },
    { from: "pages/community.html", to: "/community/" },
    { from: "pages/getting-started.html", to: "/getting-started/" },
    { from: "pages/legal.html", to: "/legal/" },
    { from: "pages/pricing.html", to: "/pricing/" },
    { from: "pages/changelog.html", to: "/changelog/" },
    { from: "pages/legal/privacy-policy.html", to: "/legal/privacy-policy/" },
    { from: "pages/legal/terms-and-conditions.html", to: "/legal/terms-and-conditions/" },
    { from: "pages/legal/cookie-policy.html", to: "/legal/cookie-policy/" },
    { from: "pages/legal/gdpr-policy.html", to: "/legal/gdpr-policy/" },
    { from: "pages/legal/acceptable-use-policy.html", to: "/legal/acceptable-use-policy/" },
    { from: "pages/legal/data-protection-disclosure.html", to: "/legal/data-protection-disclosure/" },
    { from: "pages/legal/individual-cla.html", to: "/legal/individual-cla/" },
    { from: "pages/legal/corporate-cla.html", to: "/legal/corporate-cla/" },
    { from: "pages/legal/disclaimer.html", to: "/legal/disclaimer/" },
    { from: "blog/what-is-company-as-a-service/index.html", to: "/company-as-a-service/" },
  ];
};
