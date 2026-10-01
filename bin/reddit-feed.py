#!/usr/bin/env python3
"""Read-only Reddit access through logged-out Atom feeds. Emits JSON lines.

  reddit-feed.py search <sub> <query> [--sort top|new|relevance|comments] [--t hour|day|week|month|year|all] [--limit N] [--since YYYY-MM-DD]
  reddit-feed.py listing <sub> [--sort top|new|hot] [--t ...] [--limit N] [--since YYYY-MM-DD]
  reddit-feed.py thread <post-url>

Why feeds: `.json` and old.reddit.com return 403 to plain HTTP clients; `.rss` answers.
The feed has no scores, and a thread feed may not hold every comment — treat results as leads.
Pacing: Reddit allows roughly one request per window (see x-ratelimit-* headers). The next
allowed time is kept in a state file, so separate invocations share one budget and the script
sleeps (stderr notice) instead of tripping a 429.
"""
import argparse, html, json, os, re, sys, tempfile, time
import urllib.error, urllib.parse, urllib.request
import xml.etree.ElementTree as ET

UA = os.environ.get("REDDIT_FEED_UA", "oskr-research/0.1 (personal read-only; logged-out feeds)")
NS = {"a": "http://www.w3.org/2005/Atom"}
STATE = os.path.join(tempfile.gettempdir(), "oskr-reddit-feed-next-ok")
GH_REF = re.compile(r"https?://github\.com/[\w.-]+/[\w.-]+/(?:issues|pull|discussions)/\d+")


def read_state():
    try:
        return float(open(STATE).read())
    except (OSError, ValueError):
        return 0.0


def write_state(t):
    try:
        open(STATE, "w").write(str(t))
    except OSError:
        pass


def fetch(url, retries=4):
    for _ in range(retries):
        wait = read_state() - time.time()
        if wait > 0:
            print(f"[pace] sleeping {wait:.0f}s", file=sys.stderr)
            time.sleep(wait)
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                if float(r.headers.get("x-ratelimit-remaining", 1)) < 1:
                    write_state(time.time() + float(r.headers.get("x-ratelimit-reset", 30)) + 1)
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 429:
                write_state(time.time() + float(e.headers.get("x-ratelimit-reset", 60)) + 2)
                continue
            if e.code == 403:
                sys.exit(f"403 from Reddit for {url} (blocked; try a different UA via REDDIT_FEED_UA)")
            raise
    sys.exit("still rate limited after retries: " + url)


def node(e, path):
    n = e.find(path, NS)
    return n.text if n is not None else None


def clean(raw):
    t = re.sub(r"<(br|/p|/li)\s*/?>", "\n", raw or "")
    t = re.sub(r"<[^>]+>", " ", t)
    t = html.unescape(t)
    t = re.sub(r"\[link\]|\[comments\]|submitted by\s+/u/\S+", " ", t)
    return re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n", t)).strip()


def entries(xml):
    for e in ET.fromstring(xml).findall("a:entry", NS):
        link = e.find("a:link", NS)
        raw = node(e, "a:content") or ""
        eid = node(e, "a:id") or ""
        cat = e.find("a:category", NS)
        yield {
            "kind": {"t3": "post", "t1": "comment"}.get(eid.split("_")[0], "other"),
            "id": eid,
            "title": node(e, "a:title"),
            "author": node(e, "a:author/a:name"),
            "subreddit": cat.get("term") if cat is not None else None,
            "date": (node(e, "a:updated") or node(e, "a:published") or "")[:10],
            "url": link.get("href") if link is not None else None,
            "text": clean(raw),
            "github_refs": sorted(set(GH_REF.findall(html.unescape(raw)))),
        }


def build_url(a):
    base = "https://www.reddit.com"
    if a.cmd == "search":
        q = {"q": a.query, "restrict_sr": "on", "sort": a.sort, "t": a.t, "limit": a.limit}
        return f"{base}/r/{a.sub}/search.rss?{urllib.parse.urlencode(q)}"
    if a.cmd == "listing":
        q = {"t": a.t, "limit": a.limit}
        return f"{base}/r/{a.sub}/{a.sort}.rss?{urllib.parse.urlencode(q)}"
    m = re.search(r"/comments/([a-z0-9]+)", a.url)
    if not m:
        sys.exit("thread: could not find /comments/<id> in the URL")
    clean_url = a.url.split("?")[0].rstrip("/")
    return f"{clean_url}/.rss?limit=500"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    for name in ("search", "listing"):
        s = sp.add_parser(name)
        s.add_argument("sub")
        if name == "search":
            s.add_argument("query")
        s.add_argument("--sort", default="top" if name == "listing" else "relevance")
        s.add_argument("--t", default="year")
        s.add_argument("--limit", type=int, default=10)
        s.add_argument("--since", default="")
    sp.add_parser("thread").add_argument("url")
    a = p.parse_args()
    for e in entries(fetch(build_url(a))):
        if getattr(a, "since", "") and e["date"] < a.since:
            continue
        print(json.dumps(e, ensure_ascii=False))


if __name__ == "__main__":
    main()
