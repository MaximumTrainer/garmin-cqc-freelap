#!/usr/bin/env python3
"""Backlog tooling.

    issues.py render            -> writes docs/BACKLOG.md from .github/issues.json
    issues.py create [--repo O/R] [--dry-run]
                                -> creates labels, milestones and issues on GitHub via `gh`
                                   (idempotent: skips labels/milestones/issues whose
                                   name/title already exists)

Requires `gh` authenticated with push access to the repo.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, ".github", "issues.json")
OUT = os.path.join(ROOT, "docs", "BACKLOG.md")


def load():
    with open(DATA) as f:
        return json.load(f)


def body(issue):
    lines = ["## Requirement", "", issue["requirement"], "", "## Acceptance criteria", ""]
    lines += [f"- [ ] {a}" for a in issue["acceptance"]]
    if issue.get("notes"):
        lines += ["", "## Notes", "", issue["notes"]]
    lines += ["", "_Generated from `.github/issues.json`; see docs/DESIGN.md for context._"]
    return "\n".join(lines)


def render():
    d = load()
    out = ["# Backlog", "",
           "Mirror of `.github/issues.json` (regenerate with `python3 tools/issues.py render`). "
           "Each item has a requirement and testable acceptance criteria; milestones are ordered "
           "so that each one is usable on its own.", ""]
    for i, m in enumerate(d["milestones"]):
        out += [f"## {m['title']}", "", m["description"], ""]
        for n, issue in enumerate([x for x in d["issues"] if x["milestone"] == m["title"]], 1):
            labels = " ".join(f"`{l}`" for l in issue["labels"])
            out += [f"### {issue['title']}", "", labels, "", "**Requirement.** " + issue["requirement"], "",
                    "**Acceptance criteria**", ""]
            out += [f"- [ ] {a}" for a in issue["acceptance"]]
            if issue.get("notes"):
                out += ["", f"_Notes: {issue['notes']}_"]
            out.append("")
    with open(OUT, "w") as f:
        f.write("\n".join(out))
    print("wrote", OUT)


def gh(*args, check=True, capture=True):
    r = subprocess.run(["gh", *args], text=True, capture_output=capture)
    if check and r.returncode != 0:
        raise SystemExit(f"gh {' '.join(args)} failed:\n{r.stderr}")
    return r.stdout.strip()


def create(repo, dry):
    d = load()
    existing_labels = {x["name"] for x in json.loads(
        gh("label", "list", "-R", repo, "--json", "name", "-L", "200") or "[]")}
    for l in d["labels"]:
        if l["name"] in existing_labels:
            continue
        print("label", l["name"])
        if not dry:
            gh("label", "create", l["name"], "-R", repo, "-c", l["color"], "-d", l["description"])

    ms = json.loads(gh("api", f"repos/{repo}/milestones?state=all&per_page=100") or "[]")
    ms_by_title = {m["title"]: m["number"] for m in ms}
    for m in d["milestones"]:
        if m["title"] in ms_by_title:
            continue
        print("milestone", m["title"])
        if not dry:
            r = json.loads(gh("api", f"repos/{repo}/milestones", "-f", f"title={m['title']}",
                              "-f", f"description={m['description']}"))
            ms_by_title[m["title"]] = r["number"]

    existing = {x["title"] for x in json.loads(
        gh("issue", "list", "-R", repo, "--state", "all", "--json", "title", "-L", "500") or "[]")}
    for issue in d["issues"]:
        if issue["title"] in existing:
            print("skip (exists)", issue["title"])
            continue
        print("issue", issue["title"])
        if dry:
            continue
        gh("issue", "create", "-R", repo, "-t", issue["title"], "-b", body(issue),
           "-m", issue["milestone"], *sum((["-l", l] for l in issue["labels"]), []))


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("render", "create"):
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "render":
        render()
    else:
        repo = None
        dry = "--dry-run" in sys.argv
        if "--repo" in sys.argv:
            repo = sys.argv[sys.argv.index("--repo") + 1]
        if repo is None:
            repo = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
        create(repo, dry)
