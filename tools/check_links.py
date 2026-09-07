#!/usr/bin/env python3
"""Internal links and images, in the site and in the Markdown around it.

A broken link in a repository is an annoyance. On a published page it is the
first thing a visitor sees, and nothing else in this project would notice: the
site has no tests of its own and its images come from a folder that other work
is free to reorganise.

Three things are checked, and the third is the one specific to this repo:

  * every relative `href`/`src` in `site/` resolves in the site as it will be
    **assembled** — which is not the same as the repo layout, because
    `screenshots/x.png` on the page comes from `docs/screenshots/x.png`;
  * every relative Markdown link and image in the tracked `.md` files resolves
    to a file that exists;
  * nothing in `site/` links to a repository path that the published site will
    not contain. `docs/` is deliberately not published (issue #31), so a link
    to `../docs/DESIGN.md` would 404 for every visitor while looking perfectly
    fine in an editor.

Usage: check_links.py [repo-root]   (exit 0 clean, 1 with findings)
"""
import os
import re
import sys

# site path prefix -> where the file actually lives in the repo. Must match the
# copy step in .github/workflows/pages.yml.
SITE_ASSET_SOURCES = {
    "screenshots/": "docs/screenshots/",
}

SKIP_DIRS = {".git", "bin", "gen", "__pycache__", ".vscode", "_site", ".pytest_cache"}

# href/src in the site, and Markdown [text](target) / ![alt](target).
HTML_REF = re.compile(r"""(?:href|src)\s*=\s*["']([^"']+)["']""")
MD_REF = re.compile(r"!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'][^\"']*[\"'])?\s*\)")

# Anything we are not being asked to resolve on disk.
EXTERNAL = ("http://", "https://", "mailto:", "tel:", "#", "data:")


def _is_external(target):
    return target.startswith(EXTERNAL)


def _strip_fragment(target):
    return target.split("#", 1)[0].split("?", 1)[0]


def site_target_path(root, target):
    """Where a relative site reference resolves in the repo, or None."""
    for prefix, source in SITE_ASSET_SOURCES.items():
        if target.startswith(prefix):
            return os.path.join(root, source, target[len(prefix):])
    return os.path.join(root, "site", target)


def check_site(root, errors):
    site = os.path.join(root, "site")
    if not os.path.isdir(site):
        errors.append("site/: missing")
        return

    for name in sorted(os.listdir(site)):
        if not name.endswith((".html", ".css")):
            continue
        path = os.path.join(site, name)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()

        for target in HTML_REF.findall(text):
            if _is_external(target):
                continue
            clean = _strip_fragment(target)
            if not clean:
                continue

            # A link out of the site into the repo will 404 once published.
            if clean.startswith("../") or clean.startswith("/"):
                errors.append(
                    f"site/{name}: '{target}' points outside the published site. "
                    "Link to the file on github.com instead."
                )
                continue

            resolved = site_target_path(root, clean)
            if not os.path.exists(resolved):
                errors.append(f"site/{name}: '{target}' -> {resolved} does not exist")


def check_markdown(root, errors):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            with open(path, encoding="utf-8") as handle:
                text = handle.read()

            for target in MD_REF.findall(text):
                if _is_external(target):
                    continue
                clean = _strip_fragment(target)
                if not clean:
                    continue
                resolved = os.path.normpath(os.path.join(dirpath, clean))
                if not os.path.exists(resolved):
                    errors.append(f"{rel}: '{target}' -> {resolved} does not exist")


def check_tree(root):
    """Return a list of human-readable findings; empty means clean."""
    root = str(root)
    errors = []
    check_site(root, errors)
    check_markdown(root, errors)
    return errors


def main(argv):
    root = argv[1] if len(argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    errors = check_tree(root)
    for error in errors:
        print(error)
    print(f"{len(errors)} broken link(s) in {root}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
