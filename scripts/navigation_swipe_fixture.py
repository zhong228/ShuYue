#!/usr/bin/env python3
"""Prepare/serve/clean the deterministic sources for DetailReaderBackSwipeUITests.

Two books on one server: "Navigation Swipe Fixture" (text) and "Navigation Manga
Fixture" (image pages, opened in the fixed-page reader).

The app must be installed on the selected, booted simulator. Stop the app before
prepare/clean. Only records belonging to these fixture source UUIDs are changed.
"""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import struct
import subprocess
import zlib

SOURCE_ID = "C5DED179-61D0-49C4-BDB7-93A7B3DAD8F4"
MANGA_SOURCE_ID = "42017D70-DAD6-4EDE-845E-C5DBAC606CA4"
SOURCE_IDS = {SOURCE_ID, MANGA_SOURCE_ID}
ROOT = Path("/tmp/yuedu-back-swipe-fixture")
BASE = "http://localhost:18765"
MANGA_BASE = BASE + "/manga"
# One colour per page. Chapter 1 has three pages and chapter 2 two, so the reader's
# page indicator also tells the chapters apart.
MANGA_PAGES = [[(214, 69, 65), (65, 131, 215), (38, 166, 91)], [(244, 179, 80), (142, 68, 173)]]


def support(simulator):
    container = subprocess.check_output([
        "xcrun", "simctl", "get_app_container", simulator,
        "com.zhong228.shuyue", "data",
    ], text=True).strip()
    return Path(container) / "Library/Application Support"


def update_records(path, keep, additions=()):
    records = json.loads(path.read_text()) if path.exists() else []
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([r for r in records if keep(r)] + list(additions)))


def png(width, height, rgb):
    """A solid-colour RGB PNG, written without an imaging library."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = (b"\x00" + bytes(rgb) * width) * height
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def write_book(directory, base, title, intro, chapters):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "catalog.html").write_text(
        f'<div class="book"><h2>{title}</h2>'
        f'<a href="{base}/book.html">Read</a><span class="author">Regression</span></div>')
    (directory / "book.html").write_text(
        f'<h1>{title}</h1><div class="author">Regression</div>'
        f'<div class="intro">{intro}</div><a class="toc" href="{base}/toc.html">Contents</a>')
    (directory / "toc.html").write_text(''.join(
        f'<a class="chapter" href="{base}/chapter{i}.html">Chapter {i+1}</a>' for i in range(len(chapters))))
    for i, content in enumerate(chapters):
        (directory / f"chapter{i}.html").write_text(f'<div id="content">{content}</div>')


def source(source_id, name, base, category, **fields):
    book_list = {"bookList": ".book", "name": "h2@text", "author": ".author@text", "bookUrl": "a@href"}
    return {
        "id": source_id, "bookSourceName": name, "bookSourceUrl": base,
        "enabled": True, "enabledExplore": True,
        "searchUrl": base + "/catalog.html?key={{key}}",
        "exploreUrl": json.dumps([{"title": category, "url": base + "/catalog.html"}]),
        "ruleSearch": book_list,
        "ruleExplore": book_list,
        "ruleBookInfo": {"name": "h1@text", "author": ".author@text", "intro": ".intro@text", "tocUrl": ".toc@href"},
        "ruleToc": {"chapterList": "a.chapter", "chapterName": "text", "chapterUrl": "href"},
        "ruleContent": {"content": "#content@html"},
        **fields,
    }


def prepare(simulator):
    write_book(ROOT, BASE, "Navigation Swipe Fixture", "Edge swipe regression", [''.join(
        f'<p>Chapter {i+1} paragraph {j}. Reserved edge navigation must return to the original detail. '
        'Regular page turning remains available inside the reading surface.</p>' for j in range(60)) for i in range(3)])
    # MangaChapterParser reads the pages from the chapter's <img> tags.
    write_book(ROOT / "manga", MANGA_BASE, "Navigation Manga Fixture", "Image pages opened from a book detail", [''.join(
        f'<img src="{MANGA_BASE}/chapter{i}-page{j}.png">' for j in range(len(pages))) for i, pages in enumerate(MANGA_PAGES)])
    for i, pages in enumerate(MANGA_PAGES):
        for j, colour in enumerate(pages):
            (ROOT / "manga" / f"chapter{i}-page{j}.png").write_bytes(png(400, 600, colour))
    sources = [
        source(SOURCE_ID, "Navigation Swipe Fixture", BASE, "Navigation Test"),
        # bookSourceType 2 (image) is what BookStore.addOnlineBook reads as manga
        # (OnlineBookContentInference), so the detail opens FixedPageReaderView.
        source(MANGA_SOURCE_ID, "Navigation Manga Fixture", MANGA_BASE, "Manga Test", bookSourceType=2),
    ]
    update_records(support(simulator) / "book_sources.json", lambda r: r.get("id") not in SOURCE_IDS, sources)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "serve", "clean"])
    parser.add_argument("--simulator", help="Live simulator UDID from scripts/sim.sh")
    args = parser.parse_args()
    if args.action == "serve":
        ThreadingHTTPServer(("127.0.0.1", 18765), partial(SimpleHTTPRequestHandler, directory=str(ROOT))).serve_forever()
    elif not args.simulator:
        parser.error("prepare/clean require --simulator")
    elif args.action == "prepare":
        prepare(args.simulator)
    else:
        directory = support(args.simulator)
        update_records(directory / "book_sources.json", lambda r: r.get("id") not in SOURCE_IDS)
        update_records(directory / "books_meta.json", lambda r: r.get("bookSourceId") not in SOURCE_IDS)


if __name__ == "__main__":
    main()
