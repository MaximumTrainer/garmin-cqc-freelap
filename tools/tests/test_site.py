"""The published page (issue #31).

The acceptance criteria on that issue are mostly statements about what the page
says and does not say, and every one of them is the sort of thing that quietly
stops being true. The status notice is the important one: it is what stops the
page reading as a product page for something that cannot yet talk to a chip.
"""
import re

import pytest

from conftest import REPO_ROOT

SITE = REPO_ROOT / "site"
PAGE = SITE / "index.html"
CSS = SITE / "style.css"
LISTING = REPO_ROOT / "docs" / "store" / "LISTING.md"


@pytest.fixture(scope="module")
def html():
    return PAGE.read_text(encoding="utf-8")


def visible_text(html):
    """Roughly what a reader sees: tags and comments stripped."""
    text = re.sub(r"<!--.*?-->", " ", html, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", text)


# ---------------------------------------------------------------------------
# The status notice
# ---------------------------------------------------------------------------

def test_the_page_says_it_has_never_been_run_against_a_real_chip(html):
    text = visible_text(html).lower()

    assert "never been run against a real" in text
    assert "in development" in text


def test_the_status_notice_comes_before_any_other_section(html):
    status = html.index('class="status"')
    first_section = html.index("<h2")

    # Issue #31 asks for it on screen without scrolling at 360px. Being the
    # first thing after the tagline is how that is arranged; if a section ever
    # gets inserted above it, this is what says so.
    assert status < first_section


def test_the_status_notice_links_to_the_issues_that_would_change_it(html):
    status = html[html.index('class="status"'):html.index("<h2")]

    # When #60 and #25 are answered, this notice is what has to be rewritten.
    # Linking them makes that findable rather than folklore.
    #
    # It was #7 and #25 while the protocol was unknown. #7's decoder is built
    # and the specification arrived, so the honest blocker moved: what is
    # unresolved now is whether a watch can read the scan response at all,
    # which decides whether this records splits or only rep totals.
    assert "/issues/60" in status
    assert "/issues/25" in status


# ---------------------------------------------------------------------------
# Screenshots
# ---------------------------------------------------------------------------

def figures(html):
    """Each <figure>, whitespace-normalised — the assertions below are about
    what a reader sees, and source line wrapping is not part of that."""
    return [re.sub(r"\s+", " ", f)
            for f in re.findall(r"<figure>(.*?)</figure>", html, flags=re.S)]


def test_every_image_has_meaningful_alt_text(html):
    for tag in re.findall(r"<img\b[^>]*>", html):
        match = re.search(r'alt="([^"]*)"', tag)
        assert match, f"no alt attribute: {tag}"
        # An empty alt is correct for decoration and wrong for a screenshot,
        # which carries the only description of the app a screen reader gets.
        assert len(match.group(1).split()) >= 5, f"alt text too thin: {tag}"


def test_every_screenshot_says_it_came_from_the_simulator(html):
    found = figures(html)
    assert found, "no figures on the page"

    for figure in found:
        assert "simulator capture" in figure.lower(), figure[:120]


def test_the_recording_screenshot_says_its_numbers_were_injected(html):
    recording = [f for f in figures(html) if "fr265-recording" in f]
    assert recording, "the recording screenshot is not on the page"

    # The values on it were produced by injecting a synthetic rep, because
    # there is no chip. Presenting them as a recording would be the website
    # version of what docs/store/README.md already refuses to do.
    caption = recording[0].lower()
    assert "injected" in caption
    assert "not recorded" in caption


# ---------------------------------------------------------------------------
# Required content
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("needle,what", [
    ("cannot sense", "that the watch cannot sense the transmitters itself"),
    ("FxChip BLE", "the hardware needed"),
    ("MIT", "the licence"),
    ("garmin-freelap/issues", "a link to the issue tracker"),
    ("#build", "a link to the build instructions rather than a copy of them"),
])
def test_the_page_carries(html, needle, what):
    assert needle in html, f"missing: {what}"


def test_the_trademark_note_is_present_and_unambiguous(html):
    text = visible_text(html)

    assert "Freelap is a trademark of Freelap SA" in text
    assert "not made by, endorsed by, or affiliated with Freelap SA" in text
    assert "Garmin Ltd" in text


def test_the_privacy_statement_matches_the_store_listing():
    listing = LISTING.read_text(encoding="utf-8")
    page = visible_text(PAGE.read_text(encoding="utf-8"))

    # #30 and #31 make the same promise to different audiences. Keeping one
    # copy would mean the listing pointing at a web page it predates, so
    # instead both carry it and this fails if they drift.
    for claim in [
        "Nothing leaves your watch",
        "no network permission",
        "No analytics, no accounts, no third-party services",
    ]:
        assert claim in listing, f"not in the store listing: {claim}"
        assert claim in page, f"not on the website: {claim}"


# ---------------------------------------------------------------------------
# No duplicated prose (the criterion that stops the page rotting)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("doc", ["README.md", "docs/DESIGN.md", "docs/EXPORT.md"])
def test_no_long_sentence_is_copied_from_the_repository_docs(html, doc):
    source = (REPO_ROOT / doc).read_text(encoding="utf-8")
    page = visible_text(html)

    for sentence in re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", source)):
        words = sentence.split()
        if len(words) < 12:
            continue
        cleaned = sentence.strip("*_`#-| ")
        assert cleaned not in page, (
            f"copied from {doc}, link to it instead: {cleaned[:90]}...")


# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------

def asset_list():
    lines = (SITE / "assets.txt").read_text(encoding="utf-8").splitlines()
    return [l.strip() for l in lines if l.strip() and not l.startswith("#")]


def test_every_screenshot_the_page_uses_is_in_the_asset_list(html):
    used = set(re.findall(r'src="screenshots/([^"]+)"', html))

    # An image the page references but the deploy workflow does not copy is a
    # broken image on the live site, and nothing else here would catch it.
    assert used, "the page uses no screenshots"
    assert used <= set(asset_list()), f"not copied at deploy: {sorted(used - set(asset_list()))}"


def test_the_asset_list_has_nothing_spare(html):
    used = set(re.findall(r'src="screenshots/([^"]+)"', html))

    assert set(asset_list()) == used, "assets.txt lists images the page does not use"


def test_every_listed_asset_exists():
    for name in asset_list():
        assert (REPO_ROOT / "docs" / "screenshots" / name).exists(), name


# ---------------------------------------------------------------------------
# Layout and contrast
# ---------------------------------------------------------------------------

def test_the_page_declares_a_mobile_viewport(html):
    assert 'name="viewport"' in html
    assert "width=device-width" in html


def test_nothing_is_laid_out_at_a_fixed_width():
    css = CSS.read_text(encoding="utf-8")

    # A fixed width is how a page ends up scrolling sideways on a 360px phone.
    for match in re.finditer(r"(?<!max-)(?<!min-)width\s*:\s*([^;]+);", css):
        value = match.group(1).strip()
        assert not re.match(r"^\d+(\.\d+)?(px|rem|em)$", value), \
            f"fixed width in style.css: {match.group(0)}"


def test_both_colour_schemes_are_defined():
    css = CSS.read_text(encoding="utf-8")

    # The criterion asks for AA contrast in light *and* dark. A stylesheet with
    # only one scheme gets whatever the browser inverts it to.
    assert "prefers-color-scheme: dark" in css
    assert "color-scheme: light dark" in css


def test_every_colour_pairing_records_its_measured_contrast():
    css = CSS.read_text(encoding="utf-8")

    # Each foreground token carries its measured ratio in a comment, so the
    # next person to change a colour has to recompute rather than guess.
    for token in ["--fg:", "--muted:", "--link:", "--warn-fg:"]:
        for line in css.splitlines():
            if token in line:
                assert re.search(r"\d+\.\d+:1", line), f"no measured ratio on: {line.strip()}"
