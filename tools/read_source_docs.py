#!/usr/bin/env python3
"""Dump the text of the user's source material (design PDF / Godot EPUB) to disk.

Neither file lives in the repo, so this is how a fresh session gets the text
back instead of asking the user to re-export it.

    pip install pypdf                       # not stdlib, only needed for PDF
    python3 tools/read_source_docs.py ~/sasti.pdf          -> sasti.txt
    python3 tools/read_source_docs.py ~/GodotEngine.epub   -> GodotEngine.txt

EPUB is a zip of XHTML, so it needs nothing extra. PDF text extraction needs
pypdf; if pip is blocked, use the venv form:

    python3 -m venv /tmp/rd && /tmp/rd/bin/pip install pypdf
    /tmp/rd/bin/python tools/read_source_docs.py ~/sasti.pdf
"""

import html
import re
import sys
import zipfile


def epub_text(path):
    out = []
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if n.lower().endswith((".xhtml", ".html", ".htm"))]
        for n in sorted(names):
            raw = z.read(n).decode("utf-8", "ignore")
            raw = re.sub(r"(?is)<(script|style).*?</\1>", " ", raw)
            raw = re.sub(r"(?i)</(p|div|h[1-6]|li|pre|tr)>", "\n", raw)
            text = html.unescape(re.sub(r"<[^>]+>", " ", raw))
            text = re.sub(r"[ \t]+", " ", text)
            text = re.sub(r"\n\s*\n+", "\n\n", text).strip()
            if text:
                out.append("\n\n===== %s =====\n%s" % (n, text))
    return "\n".join(out)


def pdf_text(path):
    try:
        from pypdf import PdfReader
    except ImportError:
        sys.exit("pypdf is missing: python3 -m venv /tmp/rd && /tmp/rd/bin/pip install pypdf")
    reader = PdfReader(path)
    pages = []
    for i, p in enumerate(reader.pages):
        try:
            pages.append("\n\n===== page %d =====\n%s" % (i + 1, p.extract_text() or ""))
        except Exception as exc:  # a broken page must not lose the other 471
            pages.append("\n\n===== page %d (unreadable: %s) =====" % (i + 1, exc))
    return "\n".join(pages)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    text = epub_text(src) if src.lower().endswith(".epub") else pdf_text(src)
    dst = sys.argv[2] if len(sys.argv) > 2 else re.sub(r"\.(pdf|epub)$", "", src) + ".txt"
    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)
    print("%s -> %s (%d chars)" % (src, dst, len(text)))


if __name__ == "__main__":
    main()
