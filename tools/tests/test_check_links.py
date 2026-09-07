"""The link checker (issue #31).

Its whole job is to fail, so every test here breaks one thing on purpose. A
link checker with no red case is a green tick that means nothing — the same
argument as `test_validate_resources.py`.
"""
import shutil

from conftest import REPO_ROOT
from check_links import check_tree


def repo_copy(tmp_path):
    """The parts of the repo the checker looks at."""
    dst = tmp_path / "repo"
    (dst / "site").mkdir(parents=True)
    (dst / "docs" / "screenshots").mkdir(parents=True)
    shutil.copy(REPO_ROOT / "site" / "index.html", dst / "site" / "index.html")
    shutil.copy(REPO_ROOT / "site" / "style.css", dst / "site" / "style.css")
    for png in (REPO_ROOT / "docs" / "screenshots").glob("*.png"):
        shutil.copy(png, dst / "docs" / "screenshots" / png.name)
    return dst


def test_the_repo_as_committed_has_no_broken_links():
    assert check_tree(REPO_ROOT) == []


def test_a_missing_screenshot_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    (root / "docs" / "screenshots" / "fr265.png").unlink()

    errors = check_tree(root)

    # The page says screenshots/fr265.png; the file it comes from is gone, so
    # the live site would show a broken image.
    assert any("fr265.png" in e for e in errors), errors


def test_a_missing_stylesheet_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    (root / "site" / "style.css").unlink()

    assert any("style.css" in e for e in errors_of(root)), errors_of(root)


def errors_of(root):
    return check_tree(root)


def test_a_link_out_of_the_site_into_the_repo_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    page = root / "site" / "index.html"
    page.write_text(page.read_text(encoding="utf-8").replace(
        '<link rel="stylesheet" href="style.css">',
        '<link rel="stylesheet" href="style.css">\n<a href="../docs/DESIGN.md">design</a>'),
        encoding="utf-8")

    errors = check_tree(root)

    # docs/ is deliberately not published, so this looks fine in an editor and
    # 404s for every visitor. That is the failure mode worth catching.
    assert any("outside the published site" in e for e in errors), errors


def test_an_absolute_path_in_the_site_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    page = root / "site" / "index.html"
    page.write_text(page.read_text(encoding="utf-8").replace(
        'href="style.css"', 'href="/style.css"'), encoding="utf-8")

    # The site is served from /garmin-freelap/, not the domain root, so a
    # leading slash points at somebody else's page.
    assert any("outside the published site" in e for e in check_tree(root)), check_tree(root)


def test_a_broken_markdown_link_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    (root / "docs" / "NOTES.md").write_text("See [the design](DESIGN-typo.md).\n",
                                            encoding="utf-8")

    assert any("DESIGN-typo.md" in e for e in check_tree(root)), check_tree(root)


def test_external_links_are_left_alone(tmp_path):
    root = repo_copy(tmp_path)
    (root / "docs" / "NOTES.md").write_text(
        "[github](https://github.com/x/y) [mail](mailto:a@b.c) [anchor](#section)\n",
        encoding="utf-8")

    # Reaching out to the network would make the check slow and flaky, and
    # would fail on a plane. Only what is on disk is verified.
    assert check_tree(root) == []


def test_a_link_with_an_anchor_still_resolves(tmp_path):
    root = repo_copy(tmp_path)
    (root / "docs" / "DESIGN.md").write_text("# design\n", encoding="utf-8")
    (root / "docs" / "NOTES.md").write_text("[section](DESIGN.md#5-fit-layout)\n",
                                            encoding="utf-8")

    assert check_tree(root) == []
