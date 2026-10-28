---
title: "Your Alarm Passed Every Rehearsal. In Real Life It Never Rings."
seoTitle: "Your Error Alerts Can Pass Every Test and Never Fire"
date: 2026-12-03
description: "Your alarms can pass every practice run and still stay silent when something real goes wrong. Here is how we caught ours, and the one question to ask."
ogImage: "blog/og-alarm-passed-every-rehearsal-never-rings.png"
pillar: billion-dollar-solo-founder
tags:
  - methodology
  - ai-trust
  - solo-founder
  - build-in-public
---

Somewhere in your business there is an alarm you were told works. Maybe it pings you when a nightly job breaks. Maybe it is the notice that fires if a secret key leaks. Someone you trust, a contractor or an AI agent, said the words you wanted to hear: "we tested it." And it passed.

Here is the question nobody asks at that moment: could the test have failed?

For parts of our own alarm system, the honest answer was no. They passed every rehearsal we ran, and in real life they would never have rung. This post is about how that happens, what it would have cost us, and the one question that tells you whether your alarms have the same flaw.

## Why a rehearsal that cannot fail feels exactly like a rehearsal that passed

Picture a note passed down a line of workers. Each worker does a job, then hands the note to the next. If something goes wrong, the note says so, and the right person is supposed to react: stay quiet, retry, or sound the alarm.

In real life, that hand-off goes through a coordinator that writes the note out again from scratch. The new note keeps the words of the complaint, the trail of what happened, and a short line about the cause. It drops the stamp: what kind of problem this was, and the numeric code that says why a request was refused. Think of a translator who keeps your sentences and strips the letterhead.

Plenty of alarm logic reads that stamp. If the stamp says "a release is in progress", stay quiet and try again later. If it says "a secret was detected", sound the loud alarm. In real life the stamp is gone, so those instructions never match and the note falls through to the boring default.

In a rehearsal, none of this happens. The practice stage hands the original note straight over, stamp intact. Every instruction matches. Every test goes green. The tests were never wrong about the instructions. They were testing a hand-off that does not exist in real life.

That is the whole trap. A green result from a practice stage that skips the real hand-off proves nothing about the alarm, and it feels like proof because nothing looks broken.

## What it would have cost us

We found this in three separate places. They are different pieces of the system, and each shows a different way the silence hurts. We did not have a whole fleet of dead alarms. We had three specific defects.

**A false alarm, every time a release overlapped.** Nine scheduled jobs that run on their own are built to notice when a new version of the product is being rolled out and to wait politely instead of failing. That signal travels as exactly the sort of stamp that gets stripped. When a release outlasted the one retry the job allows, the job did not recognize it. It reported a failed setup and sent a failed "I'm alive" signal, the very false alarm the waiting rule exists to prevent. This one was noisy rather than damaging, and no data was lost. But a founder who gets enough false alarms learns to stop reading alerts, which is the more expensive outcome.

**A serious alert dressed as a boring one.** A separate guard watches for leaked credentials. When it found one, the instruction was to take the leak path: loud, urgent, human. But the leak signal was a stamp too. After the hand-off it arrived looking like an ordinary "the guard itself is broken" failure. The most serious message in the system showed up wearing the costume of the most routine one. Our rehearsal showed the guard doing exactly the right thing.

**A refusal read as a slow reply.** A third piece of the product talks to an outside AI service. When that service refused a request outright, for example because the request was malformed and could never succeed, the reason for the refusal was a numeric code. The code was lost at the hand-off, so the program read every refusal as "it timed out", and the response to a timeout is to try again. A request that could never succeed would be sent three more times. The rehearsal never saw it, because the practice stage kept the code.

Three places, one shape. In each, the green checkmark was telling the truth about something other than what we cared about.

## Why we counted instead of fixing them one by one

The obvious move was to fix the places we knew about and move on. We did fix them. But finding them one at a time is how the next one slips in. The first two were found by a reviewer who happened to be reading carefully that day. A system that depends on someone happening to notice will eventually miss one.

So we counted instead. We wrote a lint, which is an automatic checker that reads the code and stops a change from shipping when it finds a pattern we have banned. This one works as a census, a full count of every place in the code that catches an error and then reads something about it.

The checker sorts every one of those places into one of two piles.

**The error already crossed the hand-off.** The code is reading the stamp on a note that has been rewritten. This is always wrong, because the stamp is gone. The checker flags it, every time, with no exceptions. There is no way to excuse a place in this pile.

**The error is still live inside the task.** Here the note has not been passed on yet, so the original is in hand, stamp and all. Reading the stamp is fine, and it is in fact the right place to do it: check the label while you still have it, then pass the verdict along as a plain result. But the checker only allows this in a short, written list of places. Adding a place to that list is a visible, deliberate act. The addition shows up in the change for a reviewer to see and challenge.

It watches for three kinds of label reading: asking what kind of problem this is, asking what it is named, and asking for its numeric code. If any of those turns up on the wrong side of the hand-off, the change is stopped. Today the count comes back clean.

The old way, a careful person had to notice. The new way, nobody has to. The bad pattern cannot come back silently, because coming back means failing a check in plain sight or adding a name to a list in plain sight.

## The other half: a rehearsal that can finally fail

A counter alone is not enough. The rehearsal was the other half of the lie, so we rebuilt the practice stage too.

The old rehearsal handed errors over directly. The new one hands them over the way the real system does, rebuilding the error with the real system's own rebuilding code instead of a hand-made imitation. The stamp is stripped in rehearsal the same way it is in life. Now an alarm that depends on a stamp that will not be there fails its test, in the practice room, where failing is cheap.

The two halves do different jobs. The counter finds every place that reads a label. The honest rehearsal checks that an alarm behaves when the label is gone.

This is one repair of seven in [the story of making green mean something]({{ site.url }}/blog/first-we-made-green-mean-something/), zoomed in.

## What this does not prove

We would rather tell you the edges than let you round them up.

The counter knows one tool's hand-off by name. It only looks at the folder of jobs built on that tool, and it recognizes the hand-off by its literal call. It reads code by pattern, matching shapes of text rather than meaning. It checks three kinds of label reading and nothing else; an alarm that finds some fourth way to be wrong would sail past it.

And what it proves is narrow. It proves that one particular lie cannot return silently. It does not prove that every alarm is correct. A clean count means that no code reads a stripped stamp. It says nothing about whether the response to a stamp is a good one.

The trap itself is not unique to our tool. The same trap shows up in other tools in different forms. In some, the label is dropped. In others, the original arrives intact but tucked underneath a wrapper, so the code that catches the error sees the wrapper first and has to know to look inside. In both, code that expects the original kind of problem can be wrong without any test noticing. We are not saying any tool is broken, or that details are always stripped. We are saying the question is the same wherever work changes hands: queues (lists of waiting work), workflow engines (software that runs a chain of tasks) and calls between services (one program asking another).

The idea transfers, even if the implementation does not. List every place that catches an error. Sort each one into "the error already crossed a hand-off" or "it is still live". Make the second pile a short list that people have to argue to join. Your builders' version will look different from ours.

## What you do with this

You do not need to read any code to use it. Ask whoever builds your systems one question:

**"Was this alarm ever tested against the real hand-off, and has anyone counted every place an error can be swallowed?"**

A good answer names the hand-off, says what survives it, and shows the practice stage rebuilt to match. A weak answer is "yes, it's tested" with nothing about how. An alarm only ever rehearsed on the practice stage is untested for the one case that matters.

For the technical write-up, see [how we built the check and moved the tests onto an honest rehearsal](https://github.com/jikig-ai/soleur/pull/11278).

And if you are the one person running the whole company, with no time to audit every alarm yourself, that is the problem Soleur exists for. Your AI team checks its own work, writes down what it learns, and gets better at telling a real pass from a rehearsal. [Join the waitlist](https://soleur.ai/pricing/#waitlist).

## Frequently Asked Questions

### Can an alert pass every test and still never fire?

Yes. If the test practices on a stage that skips the real hand-off between workers, the error keeps its label in the test and loses it in real life. The alert reads a label that is no longer there, so it stays silent or fires the wrong message. The green result was true about the rehearsal and false about the real thing.

### What does it mean for an error to cross a hand-off?

Work in software is often split into small tasks passed from one worker to the next. When a task fails, the error is usually rewritten before the next worker sees it. The message survives, but details such as the kind of problem and its numeric code may not. An error that has crossed the hand-off is the rewritten one, and code that reads the original details from it is reading something that is gone.

### Does this problem only affect one tool?

No, although it looks different in different tools. In some, the label is dropped. In others, the original error arrives intact but wrapped, so the code that catches it sees the wrapper first. The common thread is that wherever work changes hands, the code that catches an error may not be looking at the original, and a test that skips the hand-off will not show it.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Can an alert pass every test and still never fire?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. If the test practices on a stage that skips the real hand-off between workers, the error keeps its label in the test and loses it in real life. The alert reads a label that is no longer there, so it stays silent or fires the wrong message. The green result was true about the rehearsal and false about the real thing."
      }
    },
    {
      "@type": "Question",
      "name": "What does it mean for an error to cross a hand-off?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Work in software is often split into small tasks passed from one worker to the next. When a task fails, the error is usually rewritten before the next worker sees it. The message survives, but details such as the kind of problem and its numeric code may not. An error that has crossed the hand-off is the rewritten one, and code that reads the original details from it is reading something that is gone."
      }
    },
    {
      "@type": "Question",
      "name": "Does this problem only affect one tool?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No, although it looks different in different tools. In some, the label is dropped. In others, the original error arrives intact but wrapped, so the code that catches it sees the wrapper first. The common thread is that wherever work changes hands, the code that catches an error may not be looking at the original, and a test that skips the hand-off will not show it."
      }
    }
  ]
}
</script>
