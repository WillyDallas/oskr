# Source routing

Pick the class by **who can observe the fact**, then the entry point. The researcher is shell-free, so every route below is a `WebSearch` or `WebFetch`. Rows marked *untested* come from vendor docs or search snippets and haven't been exercised from this harness — confirm they respond before building a plan on them.

| Question | Source class | Entry point |
|---|---|---|
| What does library/API X do, in which version? | Official docs, changelog, release notes | The docs site (`/llms.txt` or a `.md` version first); the repo's `CHANGELOG`/releases page |
| Is this a known bug, or did it break in version N? | Issue tracker | The repo's issues page; quote the exact error string; filter by label/date in the query |
| What does the code actually do? | Source | The repo file at a pinned tag; GitHub code search supports `repo:`, `path:`, `language:`, `symbol:`, quoted strings and `/regex/` (web UI needs a login — *untested* unauthenticated) |
| Is it published / what versions exist? | Package registry | npm, PyPI, crates.io project pages |
| What do practitioners report? | Community — **leads only** | HN via Algolia: `hn.algolia.com/api/v1/search?query=…&tags=story` (`search_by_date` for newest first) — *untested*. Reddit: see below |
| What does the research say? | Papers | arXiv API (`export.arxiv.org/api/query?search_query=all:…`, prefixes `ti:` `abs:` `cat:`, ≥3 s between calls) — *untested* |
| What happened recently? | News / current web | `WebSearch` with the month and year in the query; check the page date |
| Unknown unknowns | General web search | Short broad query first, then narrow with the vocabulary you find |

## Reddit

- `.json` and `old.reddit.com` return **403** to plain HTTP clients (tested 2026-10-01). Logged-out **RSS** works: `/r/<sub>/search.rss?q=…&restrict_sr=on&sort=top|new&t=year`, `/r/<sub>/top.rss`, and a thread's `.rss`.
- Rate limit is tight — about one request per 30–60 s; honour the `x-ratelimit-reset` header. A thread feed returned few entries; don't assume it is the whole thread.
- The feed carries no scores, so "top" is an order, not a popularity signal.
- Whether `WebFetch` can reach these feeds is *untested*; if it can't, a research run that needs Reddit needs a shell-capable helper, not a workaround in the prompt.

## Engine notes

- Semantic/neural engines suit discovery ("a page that compares X and Y"); keyword engines suit exact names, error strings, and spellings. Prefer soft constraints (domain or year in the query) over hard domain filters unless off-domain results are unusable.
- Search to find URLs, then read the page: search → rerank → fetch for load-bearing facts.
- Don't search for stable knowledge; search for what changes (versions, prices, status, recent reports).
- No authoritative agent-targeted routing guidance was found for Stack Overflow, Semantic Scholar, or Kagi — treat any rule here for them as unsourced.
