#!/usr/bin/env python3
"""Everything about this project CI can check without the Connect IQ SDK.

The SDK needs a Garmin login, so `monkeyc` cannot run on a GitHub-hosted
runner (see .github/workflows/lint.yml). What is left is still worth
checking, because each of these breaks the build in a way that is only
discovered on a developer's machine minutes later:

  * any XML in the tree is well-formed (manifest, settings, strings, drawables)
  * manifest.xml exists, parses, and declares an id, an entry point and
    at least one product
  * every <bitmap filename="..."> points at a file that exists
  * every Rez.Strings.X the source refers to is declared in strings.xml
  * every @Properties.X a setting binds to is declared in properties.xml

Usage: validate_resources.py [repo-root]   (exit 0 clean, 1 with findings)
"""
import os
import re
import sys
import xml.dom.minidom
import xml.parsers.expat

SKIP_DIRS = {".git", "bin", "gen", "__pycache__", ".vscode"}


def _xml_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(filenames):
            if name.endswith(".xml"):
                yield os.path.join(dirpath, name)


def _rel(root, path):
    return os.path.relpath(path, root).replace(os.sep, "/")


def _parse(root, path, errors):
    try:
        return xml.dom.minidom.parse(path)
    except (xml.parsers.expat.ExpatError, OSError) as exc:
        errors.append(f"{_rel(root, path)}: not well-formed XML: {exc}")
        return None


def check_xml_well_formed(root, errors):
    docs = {}
    for path in _xml_files(root):
        doc = _parse(root, path, errors)
        if doc is not None:
            docs[_rel(root, path)] = doc
    return docs


def check_manifest(root, docs, errors):
    manifest = os.path.join(root, "manifest.xml")
    if not os.path.exists(manifest):
        errors.append("manifest.xml: missing")
        return
    doc = docs.get("manifest.xml")
    if doc is None:
        return  # already reported as malformed
    apps = doc.getElementsByTagName("iq:application")
    if not apps:
        errors.append("manifest.xml: no <iq:application> element")
        return
    app = apps[0]
    for attr in ("id", "entry", "minApiLevel"):
        if not app.getAttribute(attr):
            errors.append(f"manifest.xml: <iq:application> has no {attr}")
    if not doc.getElementsByTagName("iq:product"):
        errors.append("manifest.xml: no <iq:product> declared")


def check_drawables(root, docs, errors):
    for rel, doc in docs.items():
        if "drawables" not in rel:
            continue
        base = os.path.dirname(os.path.join(root, rel))
        for bitmap in doc.getElementsByTagName("bitmap"):
            filename = bitmap.getAttribute("filename")
            if filename and not os.path.exists(os.path.join(base, filename)):
                errors.append(f"{rel}: bitmap '{filename}' does not exist")


def _declared_ids(docs, rel_fragment, tag):
    ids = set()
    for rel, doc in docs.items():
        if rel_fragment in rel:
            for node in doc.getElementsByTagName(tag):
                ids.add(node.getAttribute("id"))
    return ids


def check_string_references(root, docs, errors):
    declared = _declared_ids(docs, "strings", "string")
    if not declared:
        return
    pattern = re.compile(r"Rez\.Strings\.(\w+)")
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(filenames):
            if not name.endswith(".mc"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as handle:
                for lineno, line in enumerate(handle, 1):
                    for used in pattern.findall(line):
                        if used not in declared:
                            errors.append(
                                f"{_rel(root, path)}:{lineno}: Rez.Strings.{used} "
                                "is not declared in strings.xml"
                            )


def check_property_references(root, docs, errors):
    declared = _declared_ids(docs, "properties", "property")
    if not declared:
        return
    for rel, doc in docs.items():
        if "settings" not in rel or "properties" in rel:
            continue
        for setting in doc.getElementsByTagName("setting"):
            key = setting.getAttribute("propertyKey")
            if key.startswith("@Properties."):
                name = key[len("@Properties."):]
                if name not in declared:
                    errors.append(
                        f"{rel}: setting binds @Properties.{name}, "
                        "which properties.xml does not declare"
                    )


def validate_tree(root):
    """Return a list of human-readable findings; empty means clean."""
    root = str(root)
    errors = []
    docs = check_xml_well_formed(root, errors)
    check_manifest(root, docs, errors)
    check_drawables(root, docs, errors)
    check_string_references(root, docs, errors)
    check_property_references(root, docs, errors)
    return errors


def main(argv):
    root = argv[1] if len(argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    errors = validate_tree(root)
    for error in errors:
        print(error)
    print(f"{len(errors)} problem(s) in {root}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
