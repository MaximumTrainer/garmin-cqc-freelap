"""Ring 4b: the resource validation CI actually runs.

The point of these tests is the negative case. A validator that never fails
is a green tick that means nothing, so each test breaks one thing and asserts
the breakage is reported.
"""
import shutil

import pytest

from conftest import REPO_ROOT
from validate_resources import validate_tree


def repo_copy(tmp_path):
    """A copy of the parts of the repo the validator looks at."""
    dst = tmp_path / "repo"
    dst.mkdir()
    shutil.copy(REPO_ROOT / "manifest.xml", dst / "manifest.xml")
    shutil.copytree(REPO_ROOT / "resources", dst / "resources")
    return dst


def test_repo_as_committed_validates_clean():
    assert validate_tree(REPO_ROOT) == []


def test_malformed_strings_xml_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    (root / "resources" / "strings" / "strings.xml").write_text(
        '<strings><string id="AppName">Freelap</strings>'
    )

    errors = validate_tree(root)

    assert any("strings.xml" in e for e in errors), errors


def test_malformed_manifest_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    (root / "manifest.xml").write_text("<iq:manifest>")

    errors = validate_tree(root)

    assert any("manifest.xml" in e for e in errors), errors


def test_missing_manifest_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    (root / "manifest.xml").unlink()

    errors = validate_tree(root)

    assert any("manifest.xml" in e for e in errors), errors


def test_drawable_pointing_at_a_missing_file_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    (root / "resources" / "drawables" / "launcher_icon.png").unlink()

    errors = validate_tree(root)

    assert any("launcher_icon.png" in e for e in errors), errors


def test_string_resource_used_by_source_but_not_declared_is_reported(tmp_path):
    root = repo_copy(tmp_path)
    src = root / "source"
    src.mkdir()
    (src / "Thing.mc").write_text(
        "var a = WatchUi.loadResource(Rez.Strings.AppName);\n"
        "var b = WatchUi.loadResource(Rez.Strings.NoSuchString);\n"
    )

    errors = validate_tree(root)

    assert any("NoSuchString" in e for e in errors), errors
    assert not any("AppName" in e for e in errors), errors
