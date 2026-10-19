#!/usr/bin/env python3
"""Generates booklist/Resources/IconCatalog.json for the folder icon picker.

  * SF Symbols — read from the macOS system catalogue (CoreGlyphs.bundle): every symbol
    available on the app's deployment target, in Apple's order and categories (the same
    ones the SF Symbols app shows), plus Apple's search keywords.
  * Emoji — from the official Unicode emoji-test.txt: fully-qualified emoji grouped like
    the system picker, with names for search. Skin-tone variants are skipped.

Re-run after a macOS / Xcode update to pick up new symbols:
    python3 scripts/generate_icon_catalog.py
"""
import json
import pathlib
import re
import subprocess
import urllib.request

DEPLOYMENT_TARGET = (26, 4)      # keep in sync with MACOSX_DEPLOYMENT_TARGET
EMOJI_VERSION = "16.0"           # newest Unicode emoji release fully supported by macOS 26

GLYPHS = pathlib.Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")
OUTPUT = pathlib.Path(__file__).resolve().parent.parent / "booklist" / "Resources" / "IconCatalog.json"

# Apple's category keys → display names. Meta categories (all, whatsnew, draw, variable,
# multicolor) describe rendering features, not subjects, so they're skipped.
CATEGORY_LABELS = {
    "communication": "Communication", "weather": "Weather", "maps": "Maps",
    "objectsandtools": "Objects & Tools", "devices": "Devices",
    "cameraandphotos": "Camera & Photos", "gaming": "Gaming", "connectivity": "Connectivity",
    "transportation": "Transportation", "automotive": "Automotive",
    "accessibility": "Accessibility", "privacyandsecurity": "Privacy & Security",
    "human": "Human", "home": "Home", "fitness": "Fitness", "nature": "Nature",
    "editing": "Editing", "textformatting": "Text Formatting", "media": "Media",
    "keyboard": "Keyboard", "commerce": "Commerce", "time": "Time", "health": "Health",
    "shapes": "Shapes", "arrows": "Arrows", "indices": "Indices", "math": "Math",
}

# Script/locale-specific duplicates of a base symbol (e.g. "0.circle.ar", "text.rtl").
LOCALIZED_SUFFIXES = {
    "ar", "hi", "rtl", "he", "ja", "th", "zh", "bn", "gu", "kn", "ko", "ml", "mni", "mr",
    "or", "pa", "sat", "te", "si", "ta", "el", "ru", "km", "my", "traditional",
}


def load_plist(name):
    return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(GLYPHS / name)]))


def version_tuple(text):
    return tuple(int(part) for part in text.split("."))


def build_symbols():
    order = load_plist("symbol_order.plist")
    categories = load_plist("symbol_categories.plist")
    availability = load_plist("name_availability.plist")
    keywords = load_plist("symbol_search.plist")
    releases = availability["year_to_release"]

    names = set(order)

    def is_localized(name):
        base, _, last = name.rpartition(".")
        return bool(base) and last in LOCALIZED_SUFFIXES and base in names

    def available(name):
        year = availability["symbols"].get(name)
        mac = releases.get(year, {}).get("macOS") if year else None
        return mac is not None and version_tuple(mac) <= DEPLOYMENT_TARGET

    usable = [n for n in order if available(n) and not is_localized(n)]

    sections = {key: [] for key in CATEGORY_LABELS}
    other = []
    for name in usable:
        # dict.fromkeys de-duplicates while keeping order — Apple's data occasionally lists a
        # category twice for one symbol (e.g. camera.filters → editing, editing).
        keys = [k for k in dict.fromkeys(categories.get(name, [])) if k in CATEGORY_LABELS]
        for key in keys:
            sections[key].append(name)
        if not keys:
            other.append(name)

    result = [{"title": CATEGORY_LABELS[k], "items": v} for k, v in sections.items() if v]
    if other:
        result.append({"title": "Other", "items": other})
    usable_set = set(usable)
    search = {n: kws for n, kws in keywords.items() if n in usable_set}
    # Renamed symbols (e.g. "doc" → "document"): old names still render, and folders saved
    # with them should still match their symbol in the picker and in search.
    aliases = {old: new for old, new in load_plist("name_aliases.strings").items() if new in usable_set}
    return result, search, aliases, len(usable)


def build_emoji():
    url = f"https://unicode.org/Public/emoji/{EMOJI_VERSION}/emoji-test.txt"
    text = urllib.request.urlopen(url, timeout=30).read().decode("utf-8")
    groups, current = [], None
    line_re = re.compile(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$")
    for line in text.splitlines():
        if line.startswith("# group:"):
            title = line.split(":", 1)[1].strip()
            current = None if title == "Component" else {"title": title, "items": []}
            if current:
                groups.append(current)
            continue
        match = line_re.match(line)
        if current is None or not match:
            continue
        emoji, name = match.groups()
        if "skin tone" in name:
            continue
        current["items"].append({"emoji": emoji, "name": name})
    return [g for g in groups if g["items"]]


def main():
    symbols, keywords, aliases, symbol_count = build_symbols()
    emoji = build_emoji()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(
        {"symbolSections": symbols, "symbolKeywords": keywords, "symbolAliases": aliases,
         "emojiSections": emoji},
        ensure_ascii=False, separators=(",", ":"),
    ))
    emoji_count = sum(len(g["items"]) for g in emoji)
    print(f"Wrote {OUTPUT} — {symbol_count} symbols in {len(symbols)} categories, "
          f"{emoji_count} emoji in {len(emoji)} groups")


if __name__ == "__main__":
    main()
