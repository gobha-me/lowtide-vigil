#!/usr/bin/env python3
"""Check only tracked presentation text, never engine tokens or code comments."""

import fnmatch
import html
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import sys

FORBIDDEN = re.compile(
    r"\b(?:lanternwake|boons?|trials?|springs?|kindling|gravebell)\b", re.I
)
OWN = {"tools/term-gate.sh", "tools/term_gate.py", "tools/term-gate.allow"}
LICENCE = re.compile(
    r"(?:OFL|LICENSE|LICENCE|COPYING|NOTICE|ATTRIBUTION|THIRD_PARTY)(?:\.(?:txt|md))?",
    re.I,
)


def strings(source, language):
    """Yield literal contents, offset and end; exclude comments and identifiers."""
    index = 0
    while index < len(source):
        if language in {"gd", "data"} and source[index] in ("#" if language == "gd" else "#;"):
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
        elif language == "js" and source.startswith("//", index):
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
        elif language == "js" and source.startswith("/*", index):
            end = source.find("*/", index + 2)
            index = len(source) if end < 0 else end + 2
        elif source[index] in "\"'" or (language == "js" and source[index] == "`"):
            quote = source[index]
            if language == "gd" and source.startswith(quote * 3, index):
                quote *= 3
            start = index + len(quote)
            index = start
            while index < len(source) and not source.startswith(quote, index):
                index += 2 if source[index] == "\\" else 1
            yield source[start:index], start, index + len(quote)
            index += len(quote)
        else:
            index += 1


def decoded(value):
    # One pass preserves escaped backslashes and ordinary UTF-8. Callers split
    # physical source lines first, so rendered newlines do not shift diagnostics.
    escapes = {
        "a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r",
        "t": "\t", "v": "\v", "0": "\0", "\\": "\\", '"': '"', "'": "'", "/": "/",
    }
    value = re.sub(
        r"\\(?:u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2})|([abfnrtv0\\\"'/]))",
        lambda match: chr(int(match[1] or match[2], 16))
        if match[1] or match[2] else escapes[match[3]],
        value,
    )
    return html.unescape(value)


def literal_parts(source, language):
    for value, start, _end in strings(source, language):
        yield value, source.count("\n", 0, start) + 1


class WebText(HTMLParser):
    """HTML prose/accessibility text and script literals sent to UI sinks.

    This includes canvas drawing calls, DOM text setters, banners, card data
    and the reward-sign map used by the reference game. CSS, resource paths,
    selectors, internal enum values and JS identifiers are outside the scope.
    """

    SINK = re.compile(
        r"\b(?:fillText|strokeText|fillTextWrap|text|ftext|banner|offerCards|"
        r"drawText|ptxt|add|mk_|showMessage|alert|confirm|prompt)\s*\("
        r"|\.(?:textContent|innerText|innerHTML|outerHTML|title|ariaLabel|value)\s*="
        r"|\.(?:setAttribute|insertAdjacentHTML|insertAdjacentText|createTextNode)\s*\("
        r"|\b(?:name|short|title|desc|description|label|caption|message|text)\s*[:=]"
        r"|\b(?:SIGNNAME|SIGN_NAMES|UI_TEXT|RARN)\s*=",
        re.I,
    )
    # Maintained presentation-data scope: drawHUD's touch/keyboard tutorial
    # arrays in web/lowtide-vigil.html. The following lines.forEach callback
    # renders each element via ptxt. Inspect only literals in this declaration,
    # not every variable named lines, nor identifiers, CSS or other JS tokens.
    PRESENTATION_DATA = re.compile(r"\bconst\s+lines\s*=\s*TOUCH\.on\s*\?")

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.hidden = []
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style"}:
            self.hidden.append(tag)
        for key, value in attrs:
            if value and key in {"title", "alt", "aria-label", "placeholder"}:
                self.parts.append((value, self.getpos()[0]))
            elif value and key == "value" and tag in {"button", "input", "option"}:
                self.parts.append((value, self.getpos()[0]))

    def handle_endtag(self, tag):
        if self.hidden and self.hidden[-1] == tag:
            self.hidden.pop()

    def handle_data(self, data):
        base = self.getpos()[0]
        if not self.hidden:
            self.parts.append((data, base))
        elif self.hidden[-1] == "script":
            # Work by statement/line context so procedural canvas UI is checked
            # without interpreting arbitrary JavaScript or scanning code tokens.
            for value, start, end in strings(data, "js"):
                left = max(data.rfind(";", 0, start), data.rfind("}", 0, start)) + 1
                right = data.find("\n", end)
                right = len(data) if right < 0 else right
                context = data[left:right]
                if (
                    self.SINK.search(context)
                    or self.PRESENTATION_DATA.search(context)
                    or "<" in value
                ):
                    self.parts.append((value, base + data.count("\n", 0, start)))


def read_allowlist(files):
    patterns = []
    errors = []
    for line, entry in enumerate(Path("tools/term-gate.allow").read_text().splitlines(), 1):
        path, separator, reason = entry.partition("#")
        path = path.strip()
        if not separator or not reason.strip() or not path:
            errors.append(f"tools/term-gate.allow:{line}: every entry needs a path and reason")
            continue
        matches = [file for file in files if fnmatch.fnmatchcase(file, path)]
        if not matches or any(
            file not in OWN and not LICENCE.fullmatch(Path(file).name) for file in matches
        ):
            errors.append(
                f"tools/term-gate.allow:{line}: only tracked licence/attribution or gate files allowed"
            )
            continue
        patterns.append(path)
    return patterns, errors


def main():
    files = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
    files = [file for file in files if file]
    patterns, errors = read_allowlist(files)
    for file in files:
        if any(fnmatch.fnmatchcase(file, pattern) for pattern in patterns):
            continue
        path = Path(file)
        is_doc = file == "README.md" or (file.startswith("docs/") and path.suffix == ".md")
        is_web = file.startswith("web/") and path.suffix in {".html", ".htm", ".js"}
        if not (is_doc or is_web or path.suffix in {".gd", ".tscn", ".tres", ".json"}):
            continue
        source = path.read_text(encoding="utf-8")
        if is_doc:
            parts = [(source, 1)]
        elif is_web and path.suffix != ".js":
            parser = WebText()
            parser.feed(source)
            parts = parser.parts
        elif is_web:
            parser = WebText()
            parser.feed("<script>" + source + "</script>")
            parts = parser.parts
        else:
            language = "gd" if path.suffix == ".gd" else "data"
            parts = literal_parts(source, language)
        for value, line in parts:
            for offset, text in enumerate(value.splitlines()):
                for hit in FORBIDDEN.finditer(decoded(text)):
                    errors.append(f"{file}:{line + offset}: forbidden player-facing term: {hit[0]}")
    if errors:
        print("\n".join(dict.fromkeys(errors)))
        return 1
    print("term-gate: tracked player-facing content is clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
