---
title: "What Your MVP Is Missing Before Real Users Show Up: A Findings List, Not a Verdict"
seoTitle: "What Your MVP Is Missing Before Real Users Show Up"
date: 2026-11-04
description: "Your product works for you. Before strangers use it, get one plain list of what is missing in security, testing, upkeep and uptime, ranked by what matters most."
ogImage: "blog/og-what-your-mvp-is-missing.png"
ogImageAlt: "A short ranked list of launch gaps, drawn as gold bars of falling length"
tags:
  - launch-readiness
  - solo-founder
---

Your product works. You have clicked through it a hundred times, and it does what you built it to do. Now someone who is not you is about to sign up, with their email address and maybe their card, and a quiet question shows up: what haven't I checked?

You can't answer it by clicking around more. The things that hurt a young product are rarely on the screen. A password saved in your code where anyone with access can read it. No test that tells you a change broke sign-up. No alert when the site goes down at 3 a.m. No written way to undo a bad release. You only find out about these when a user does.

## What a founder actually needs: a list, not a grade

Many readiness tools hand you a score or a certificate. A score invites the wrong question ("am I a 72?"). A certificate promises something no automated check can promise.

What you need is shorter and more useful: a plain list of the gaps, in the order they matter, so you can pick the next three things to fix and ignore the rest for now.

That is what Soleur's launch readiness check produces. You run it on a project you already have, and it writes one report with the gaps it found. It is a findings list, and every report opens with a notice saying it is not a security review or an attestation of any standard.

## What the list covers: security, testing, upkeep and uptime

The report groups what it finds into four areas a founder worries about:

- **Security and secrets.** Signs of passwords or keys saved in your project, and whether your project locks its outside software to known versions and has automatic updates set up.
- **Tests and deployment.** Signs that something checks your work automatically before it reaches users, and that there is a release path set up or written down.
- **Tech debt and architecture.** Whether the big decisions about how your product is put together are written down anywhere, so you (or whoever you hire next) can find them.
- **Reliability and operations.** Signs that you would hear about a failure (such as error reporting being set up), that the site has a page that reports whether it is up, and that your files mention how backups and restores work.

These are automatic look-for-signs checks, not proof. A tick means the check found the sign it looks for, not that the thing works.

Each gap comes with a severity and a plain description of what to do about it. It also looks at which of Soleur's own working practices your project is missing, such as automatic checks that stop a secret from being saved by accident, so the report tells you what to add as well as what is wrong.

## Your report never contains your secrets

A check that finds a password in your project is the one most worth getting right. So when the report finds a secret, it tells you how many it found, never what they are or where they are. If you want the locations, you run the scan yourself in a separate terminal window, and they appear on your own screen only, never in the report.

Two limits to know about. The secret scan looks at the version of your project you last saved to its history, not at the whole history (the record of every earlier version). A secret you deleted last month can still be live in that history, so if the report mentions any, change them. And the AI review described below reads files from your project, so a secret written directly into one of those files is part of what goes to your AI provider.

## The check runs from your own computer

The scan runs on your computer, and Soleur's servers receive nothing. Today you run the check from your own computer, set up through the [getting started guide](https://soleur.ai/getting-started/). It needs one free secret-scanning program installed first, and it stops with a clear message if that is missing.

The check also has the AI you already use read files from your project, except the ones made to hold passwords and keys, to judge things a scan can't, such as how people sign in. That content goes to your AI provider. If you accept the offer to file the gaps as tasks, the check reads from and then writes to GitHub with your own login. The report is a file in your project, and because it lists weaknesses you have not fixed yet, you should keep that project private.

## Turn the gaps into a to-do list, only if you approve it

A list is only useful if the gaps become tasks. After the report is written, the check can offer to file them in your own GitHub project: one parent item, and one item per gap, ranked by how much it matters and labelled by area. Run it again later and it will not file a gap it already filed, even if you closed the item, as long as you leave the item's label in place.

That step is optional, and it is built so that you are asked first. The check shows you the full list of what it would file, then asks about your project, whether it is public, private or internal, how many items it will create and which labels it will add if they are missing. If your project is public, internal or of unknown visibility, it asks a second, separate question, because filing unfixed gaps there would publish them for everyone who can see the project.

The command that does the filing cannot tell whether you agreed, so if you ever run it directly, you are the one deciding. It never closes or deletes anything, and it refuses to file when it detects that it is running unattended. If you change your mind, closing the items removes them from your list, though notifications already sent to people watching your project cannot be recalled.

You can also accept a finding on purpose. If a gap does not apply to your product, say why, and the report moves it to an "accepted" list instead of nagging you.

## What a clean report does not tell you

- It does not promise that a clean report means you are safe. A gap it doesn't list was not found in the files it read, which is different from not being there.
- Its checks can be wrong. Treat each line as a prompt to look, not a ruling.
- Some checks apply only to products built with JavaScript or TypeScript (two common web languages). For other products the report says coverage is partial and lists the checks it could not run, rather than showing them as fine.
- The secret scan cannot see files you have not saved to your project's history. The other checks read the files in your project folder as they are on disk, including changes and new files you have not yet saved to your project's history, and skip new files your project is set to ignore.

## Frequently Asked Questions

<div class="faq-list">
  <details class="faq-item">
    <summary class="faq-question">Does a clean report mean my product is ready for customers?</summary>
    <p class="faq-answer">No. The report lists gaps it found in the files it read. A gap that is not listed was not found, which is not the same as not being there. It is a findings list, not a score or a certification.</p>
  </details>
  <details class="faq-item">
    <summary class="faq-question">Will my passwords or keys appear in the report?</summary>
    <p class="faq-answer">No. When the check finds a secret it reports how many, never what they are or where they are. The secret scan looks at the version of your project you last saved to its history, so a secret you deleted earlier can still be live there and should be changed.</p>
  </details>
  <details class="faq-item">
    <summary class="faq-question">Does anything leave my computer?</summary>
    <p class="faq-answer">The scan runs on your computer and Soleur's servers receive nothing. The AI you already use reads files from your project, except files made to hold passwords and keys, so that content goes to your AI provider. If you accept the offer to file the gaps as tasks, the check reads from and then writes to GitHub with your own login.</p>
  </details>
  <details class="faq-item">
    <summary class="faq-question">Is this a security audit?</summary>
    <p class="faq-answer">No. It is a findings list, and every report opens with a notice that it is not a security review or an attestation of any standard.</p>
  </details>
  <details class="faq-item">
    <summary class="faq-question">Will it create tasks in my GitHub project without asking?</summary>
    <p class="faq-answer">It is built to ask first. It shows you the full list of what it would create and asks, naming your project, whether it is public, private or internal, and how many items it will file. A project that is public, internal or of unknown visibility gets a second, separate question, and a run it detects as unattended is refused.</p>
  </details>
</div>

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Does a clean report mean my product is ready for customers?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. The report lists gaps it found in the files it read. A gap that is not listed was not found, which is not the same as not being there. It is a findings list, not a score or a certification."
      }
    },
    {
      "@type": "Question",
      "name": "Will my passwords or keys appear in the report?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. When the check finds a secret it reports how many, never what they are or where they are. The secret scan looks at the version of your project you last saved to its history, so a secret you deleted earlier can still be live there and should be changed."
      }
    },
    {
      "@type": "Question",
      "name": "Does anything leave my computer?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The scan runs on your computer and Soleur's servers receive nothing. The AI you already use reads files from your project, except files made to hold passwords and keys, so that content goes to your AI provider. If you accept the offer to file the gaps as tasks, the check reads from and then writes to GitHub with your own login."
      }
    },
    {
      "@type": "Question",
      "name": "Is this a security audit?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. It is a findings list, and every report opens with a notice that it is not a security review or an attestation of any standard."
      }
    },
    {
      "@type": "Question",
      "name": "Will it create tasks in my GitHub project without asking?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "It is built to ask first. It shows you the full list of what it would create and asks, naming your project, whether it is public, private or internal, and how many items it will file. A project that is public, internal or of unknown visibility gets a second, separate question, and a run it detects as unattended is refused."
      }
    }
  ]
}
</script>

## Your next step

Want an AI team that works through the list while you make the calls? [{{ site.primaryCta.label }}]({{ site.primaryCta.url }})

For the technical write-up, see [how the check was designed](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/architecture/decisions/ADR-314-launch-check-baseline-manifest-and-finding-contract.md).
