# Source routing

Pick the class by **who can observe the fact**, then the entry point. The researcher is shell-free, so every route below is a `WebSearch` or `WebFetch`. Rows marked *untested* come from vendor docs or search snippets and haven't been exercised from this harness — confirm they respond before building a plan on them.

| Question | Source class | Entry point |
|---|---|---|
| What does library/API X do, in which version? | Official docs, changelog, release notes | The docs site (`/llms.txt` or a `.md` version first); the repo's `CHANGELOG`/releases page |
| Is this a known bug, or did it break in version N? | Issue tracker | The repo's issues page; quote the exact error string; filter by label/date in the query |
| What does the code actually do? | Source | The repo file at a pinned tag; GitHub code search supports `repo:`, `path:`, `language:`, `symbol:`, quoted strings and `/regex/` (web UI needs a login — *untested* unauthenticated) |
| Is it published / what versions exist? | Package registry | npm, PyPI, crates.io project pages |
| What do practitioners report? | Community — **leads only** | HN via Algolia: `hn.algolia.com/api/v1/search?query=…&tags=story` (`search_by_date` for newest first) — *untested*. Reddit: `oskr:reddit-research` |
| What does the research say? | Papers | arXiv API (`export.arxiv.org/api/query?search_query=all:…`, prefixes `ti:` `abs:` `cat:`, ≥3 s between calls) — *untested* |
| What happened recently? | News / current web | `WebSearch` with the month and year in the query; check the page date |
| Unknown unknowns | General web search | Short broad query first, then narrow with the vocabulary you find |

## Reddit

Use `oskr:reddit-research` — `WebFetch` and plain `curl` get 403 on `.json` and `old.reddit.com`, and the skill's wrapper (logged-out RSS, paced to the rate limit) is the supported route. Results are leads only.

## Engine notes

- Semantic/neural engines suit discovery ("a page that compares X and Y"); keyword engines suit exact names, error strings, and spellings. Prefer soft constraints (domain or year in the query) over hard domain filters unless off-domain results are unusable.
- Search to find URLs, then read the page: search → rerank → fetch for load-bearing facts.
- Don't search for stable knowledge; search for what changes (versions, prices, status, recent reports).
- No authoritative agent-targeted routing guidance was found for Stack Overflow, Semantic Scholar, or Kagi — treat any rule here for them as unsourced.
