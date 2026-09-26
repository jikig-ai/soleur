# Alpha setup — about 10 minutes, and the fiddly part is on the call

Welcome to the Soleur alpha. This page is everything you need before (or during) your guided
setup session. If anything here doesn't match what you see, just bring it to the call —
that's what it's for.

## 1. Create your account

1. Open your invite link.
2. Sign up — **Google sign-in is the fastest path**. If you use email instead, you'll get a
   one-time code: **check your spam folder** if it doesn't arrive within a minute.
3. Accept the terms and name your workspace anything you like.

That's it — you can stop here and let the rest happen on the call.

## 2. Get an Anthropic API key (we'll do this together)

Soleur runs on your own Anthropic key, so usage bills to your Anthropic account and your
data stays yours. If you already have a `sk-ant-…` key, you're done with this section.

Otherwise:

1. Go to [console.anthropic.com](https://console.anthropic.com) and sign in (or create an
   account).
2. Add a payment method under **Plans & Billing** — API usage is billed per token, and a
   few dollars covers a two-week alpha comfortably.
3. Open **API Keys** → **Create Key**, give it a name like `soleur-alpha`, and copy the
   `sk-ant-…` key it shows. It's shown only once — keep it handy until the call.

On the call you'll paste it into Soleur's `/setup-key` step, which stores it encrypted for
your workspace only.

## 3. Connect GitHub — optional, and skippable

Connecting a repository lets Soleur's agents work directly against your code. If you're
ready: connect it on the call and we'll do it together. **If this step stalls or you're not
sure which repo to pick — skip it.** "Connect later with help" is a completely supported
path; nothing else depends on it.

## 4. Things worth trying first

Once you're set up, these three prompts are a good first session — use your real business,
not a demo:

1. *"Look at my repository and tell me what the codebase is doing — like a senior hire's
   first-week summary."*
2. *"I need to decide <a real decision you're weighing>. Help me think it through and
   produce a short write-up I can share."*
3. *"Find the riskiest thing in my current plan and tell me what you'd check first."*

The point of the first session is to walk out with **one real artifact** — something you'd
actually use. Don't aim for coverage; aim for useful.

## 5. Where to get unstuck

Your private Slack channel is the fastest way to reach me: [Slack link — Jean will send
this with your invite]. Post anything — errors, "is this supposed to…", screenshots. There
are no scripted check-ins; I answer when you write.

## Notes

- **Local decision log:** on your machine the plugin appends one metadata-only line per
  routing decision to `.soleur/decisions.jsonl` in the project (event names, skill/agent
  labels, timestamps — never prompt text, args, or file paths; the directory self-ignores
  in git). Nothing leaves your machine unless you choose to paste the aggregate at a
  checkpoint (`bash plugins/soleur/scripts/alpha-metrics.sh`). Disable it entirely with
  `SOLEUR_DISABLE_DECISION_LOG=1`.
- You can stop at any point, for any reason — just say so.
- The terms you accepted on signup apply to your use of Soleur on any surface.
