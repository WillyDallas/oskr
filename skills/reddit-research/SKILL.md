---
name: reddit-research
description: Read Reddit as research leads — reach for it when `deep-research` needs practitioner experience (upgrade breakage, "does X work with Y", what people run) that docs and trackers don't carry.
allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/reddit-feed.py"*) Read
---

Reddit is a **lead generator**, never evidence: a post tells you where to look and what to test, and the claim only counts once a primary source backs it (changelog, issue, docs, code).

`WebFetch` and plain `curl` get 403 on `.json` and `old.reddit.com`; logged-out `.rss` answers. `"${CLAUDE_PLUGIN_ROOT}/bin/reddit-feed.py"` wraps it and prints JSON lines (`kind`, `title`, `author`, `date`, `url`, `text`, `github_refs`):

    reddit-feed.py search <sub> "<query>" [--sort new|top|relevance|comments] [--t month|year|all] [--limit N] [--since YYYY-MM-DD]
    reddit-feed.py listing <sub> [--sort top|new|hot] [--t week] [--limit N]
    reddit-feed.py thread <post-url>

## Limits that shape the plan

- **Budget is requests, and each costs up to a minute.** The script sleeps to honour Reddit's rate limit, shared across runs, so ten requests is roughly ten minutes. Spend them on queries that matter; fold the rest into `deep-research`'s tier ceiling.
- **Search is fuzzy.** Reddit's own relevance sorting returns loosely related posts, so several sharper phrasings beat one long one. Use `--sort new --since` for recency on volatile topics.
- **No scores, and a thread feed may omit comments.** "Top" is an order, not popularity, and a short thread feed is not proof nobody replied.

## Steps

1. **Pick subreddits and phrasings** from the question's concept table (symptom wording, product names, version numbers). *Done when* each request names the gap it fills.
2. **Search, then read the few threads that matter.** Fetch a thread only when its title or text bears on a named gap. *Done when* every thread read is logged with its date.
3. **Extract claims as leads.** For each: the claim, poster's version if stated, post date, thread URL. Follow every `github_refs` entry and any release or doc link to its primary source and verify it there. *Done when* each lead is either backed by a primary source or listed unconfirmed.
4. **Date-stamp against the version.** A fix or breakage reported against an older major version is stale for a newer one; drop or downgrade it.
5. **Report limits**: subreddits and queries that returned nothing relevant belong in `not found`, not omitted.
