#!/usr/bin/env bash
# Checks that every string-literal localization key used in the app sources exists in
# FlatlyApp/Resources/Localizable.xcstrings and has a Polish ("pl") translation.
#
# Extracted call sites: Text("…"), Label("…", Button("…", TextField("…", Picker("…",
# Toggle("…", ProgressView("…", LabeledContent("…", ContentUnavailableView("…",
# .navigationTitle("…"), .alert("…", .confirmationDialog("…" and String(localized: "…").
# Interpolations (\(…)) match any format specifier in the catalog key (%lld, %@, %1$lld, …).
# Text(verbatim:) and non-literal arguments are ignored. Exits 1 if any key is missing, or if a
# catalog key or Swift literal uses automatic grammar agreement (^[…](inflect: true)), which
# confirmationDialog titles and accessibility values show raw: use plural variations instead.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, pathlib, re, sys

CATALOG = pathlib.Path("FlatlyApp/Resources/Localizable.xcstrings")

# Literals the extractor finds that are intentionally NOT catalog keys.
# Format: "key as written in Swift (interpolations as \x00)": "why it is allowed".
ALLOW = {
    # (empty) — add entries here with a comment explaining why the literal is not user-facing.
}

CALL = re.compile(
    r'(?:(?<![\w.])(?:Text|Label|Button|TextField|Picker|Toggle|ProgressView|LabeledContent|ContentUnavailableView)'
    r'|\.(?:navigationTitle|alert|confirmationDialog))\(\s*"'
    r'|String\(localized:\s*"'
)
SPEC = re.compile(r'%(?:\d+\$)?(?:lld|ld|lu|d|u|@|(?:\.\d+)?f)')
HOLE = "\x00"

def read_literal(src, i):
    """Parses a Swift string literal whose opening quote is at src[i-1]. Returns the key with
    interpolations replaced by HOLE, or None for multi-line literals."""
    if src.startswith('""', i):
        return None
    out = []
    while i < len(src):
        c = src[i]
        if c == '"':
            return "".join(out)
        if c == "\\":
            n = src[i + 1]
            if n == "(":
                depth, i = 1, i + 2
                while depth:
                    ch = src[i]
                    if ch == '"':          # nested string inside the interpolation
                        i += 1
                        while src[i] != '"':
                            i += 2 if src[i] == "\\" else 1
                    elif ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                    i += 1
                out.append(HOLE)
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return None

catalog = json.loads(CATALOG.read_text())["strings"]
known = {}
untranslated = []
for key, entry in catalog.items():
    known[SPEC.sub(HOLE, key).replace("%%", "%")] = key
    if "pl" not in entry.get("localizations", {}):
        untranslated.append(key)

INFLECT = "](inflect:"
INFLECT_ERROR = ("automatic grammar agreement markup ^[…](inflect: true) is not resolved in dialog titles "
                 "or accessibility values; use plural variations in the catalog")
inflected = [f"catalog key {key!r}" for key in catalog if INFLECT in key]

missing = []
for path in sorted(pathlib.Path("FlatlyApp").rglob("*.swift")):
    src = path.read_text()
    # Blank out line comments so commented-out code is not checked.
    src = re.sub(r'(?m)^\s*//.*$', "", src)
    for m in CALL.finditer(src):
        key = read_literal(src, m.end())
        if key and INFLECT in key:
            line = src.count("\n", 0, m.start()) + 1
            inflected.append(f"{path}:{line}: {key.replace(HOLE, '%…')!r}")
        if key is None or key == "" or key in ALLOW or key in known:
            continue
        line = src.count("\n", 0, m.start()) + 1
        missing.append(f"{path}:{line}: {key.replace(HOLE, '%…')!r}")

for key in untranslated:
    print(f"error: catalog key without a Polish translation: {key!r}")
for item in missing:
    print(f"error: key missing from {CATALOG}: {item}")
for item in inflected:
    print(f"error: {INFLECT_ERROR}: {item}")
if missing or untranslated or inflected:
    sys.exit(1)
print(f"✓ Localization check passed ({len(catalog)} catalog keys)")
PY
