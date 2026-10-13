#!/usr/bin/env python3
# ================================================================
#  seala.py
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Seala (Irish: seal)
#  Role: Header stamper for Python and shell files
#  Runs: On demand
#  Created: 2026-10-08
#  Last Modified: 2026-10-12 21:50 CDT
#  Changelog (newest first):
#    2026-10-12 21:50 CDT - v1.1.1: lint fixes for current ruff defaults (DTZ notes, executable bit); no behaviour change
#    2026-10-12 17:30 CDT - v1.1: owner from SEALA_OWNER, git user.name or the login name (no longer hard-coded); lint pass
#    2026-10-08 16:07 CDT - Initial version (v1.0), twin of Seala PowerShell module v1.2.0
# ================================================================

"""Seala - applies or updates the standard header block on Python and shell files.

Python/shell twin of the Seala PowerShell module: same fields, same rolling
changelog, written as '#' line comments. The owner on the IP line comes from
SEALA_OWNER, else git user.name, else the login name.

  No header        : inserts the header (below the shebang and any Python
                     encoding line, above the module docstring).
  Seala header     : refreshes the IP lines and file name, bumps Last Modified,
                     prepends a changelog entry, trims to --max-changelog.
  Old-style header : (the #==== block with 'Key : Value' lines) is absorbed:
                     fields carry over, its Last Modified becomes a changelog
                     line, the old block is removed. Also un-stacks a Seala
                     header sitting on top of an old one.

Created is set once, then preserved. Source order: --created, existing header,
old-style header, the file's first git commit, file birth time, modified time.

Handles .py .pyw .sh .bash .zsh, plus extensionless files with a python/sh
shebang when named directly. Encoding, BOM, line endings and file mode are
preserved; every write is verified on disk. Standard library only.
"""

import argparse
import getpass
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime

RULE = "=" * 64
EXTS = {".py", ".pyw", ".sh", ".bash", ".zsh"}
CANON = ("Company", "Suite", "Role", "Runs")

RX_RULE = re.compile(r"^#\s*=+\s*$")
RX_IP = re.compile(r"^#{2,}\s*Intellectual Property of")
RX_BANNER = re.compile(r"^#{2,}.*#{2,}\s*$")
RX_FIELD = re.compile(r"^#\s+([^:]+?):\s*(.*?)\s*$")
RX_CHANGELOG = re.compile(r"^#\s+Changelog\b")
RX_ENTRY = re.compile(r"^#\s{3,}(\S.*?)\s*$")
RX_FILELINE = re.compile(r"^#\s+\S+ for ")
RX_LEGACY_KV = re.compile(r"^#\s*([A-Za-z][\w ]*?)\s*:\s*(.*?)\s*$")
RX_EMPTY = re.compile(r"^#\s*$")
RX_CODING = re.compile(r"^[ \t\f]*#.*?coding[:=][ \t]*[-\w.]+")
RX_SHEBANG_OK = re.compile(r"^#!.*\b(python[\d.]*|sh|bash|zsh|dash|ksh)\b")


def resolve_owner():
    """Name for the IP line: SEALA_OWNER, else git user.name, else the login name."""
    owner = os.environ.get("SEALA_OWNER", "").strip()
    if not owner and shutil.which("git"):
        try:
            owner = subprocess.run(["git", "config", "--get", "user.name"], capture_output=True,
                                   text=True, timeout=5, check=False).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            owner = ""
    return owner or getpass.getuser()


OWNER = resolve_owner()


def now_stamp():
    """2026-10-08 16:05 CDT. Windows gives long zone names, so abbreviate them."""
    now = datetime.now().astimezone()
    name = now.tzname() or ""
    if name in ("UTC", "Coordinated Universal Time"):
        abbr = "UTC"
    elif " " in name:
        abbr = "".join(word[0] for word in name.split())
    else:
        abbr = name
    return f"{now:%Y-%m-%d %H:%M} {abbr.upper()}".rstrip()


def iso_date(value):
    """08/06/2026 -> 2026-08-06. Unrecognised text is returned unchanged."""
    v = (value or "").strip()
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d", "%m/%d/%Y %H:%M",
                "%Y-%m-%d %H:%M", "%m/%d/%Y %I:%M %p"):
        try:
            return datetime.strptime(v, fmt).strftime("%Y-%m-%d")  # noqa: DTZ007 - date-only reformat, no timezone involved
        except ValueError:
            pass
    return v


def created_fallback(path):
    """First git commit date if tracked, else birth time, else modified time."""
    try:
        out = subprocess.run(
            ["git", "log", "--follow", "--diff-filter=A", "--format=%as", "--", os.path.basename(path)],
            cwd=os.path.dirname(os.path.abspath(path)) or ".",
            capture_output=True, text=True, timeout=10, check=False,
        )
        dates = out.stdout.split()
        if out.returncode == 0 and dates:
            return dates[-1]
    except (OSError, subprocess.SubprocessError):
        pass
    st = os.stat(path)
    ts = getattr(st, "st_birthtime", None)
    if ts is None:
        ts = st.st_ctime if os.name == "nt" else st.st_mtime
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")  # noqa: DTZ006 - the local calendar date is intended


def read_text(path):
    """Returns (text, bom). Raises UnicodeDecodeError on non-UTF-8 files."""
    with open(path, "rb") as fh:
        raw = fh.read()
    bom = raw.startswith(b"\xef\xbb\xbf")
    return raw[3:].decode("utf-8") if bom else raw.decode("utf-8"), bom


def write_text(path, text, bom):
    with open(path, "wb") as fh:  # in-place write keeps the file mode (+x)
        fh.write((b"\xef\xbb\xbf" if bom else b"") + text.encode("utf-8"))


def skip_blank(lines, i):
    while i < len(lines) and not lines[i].strip():
        i += 1
    return i


def parse_seala(lines, start):
    """Seala header at lines[start:]? -> (fields, log, index after header) or None."""
    i = skip_blank(lines, start)
    if i + 2 >= len(lines) or not RX_RULE.match(lines[i]) or not RX_IP.match(lines[i + 1]):
        return None
    i += 2
    while i < len(lines) and RX_BANNER.match(lines[i]):
        i += 1
    if i >= len(lines) or RX_RULE.match(lines[i]):
        return None  # rule straight after the banners = old-style header
    fields, log, in_log = {}, [], False
    while i < len(lines):
        line = lines[i]
        if RX_RULE.match(line):
            return (fields, log, i + 1) if "Last Modified" in fields else None
        if not line.startswith("#"):
            return None
        if RX_FILELINE.match(line):
            pass
        elif RX_CHANGELOG.match(line):
            in_log = True
        elif in_log and RX_ENTRY.match(line):
            log.append(RX_ENTRY.match(line).group(1))
        else:
            m = RX_FIELD.match(line)
            if m:
                in_log = False
                fields[m.group(1)] = m.group(2)
        i += 1
    return None


def parse_legacy(lines, start):
    """Old-style header at lines[start:]? -> (fields, index after header) or None."""
    i = skip_blank(lines, start)
    if i + 1 >= len(lines) or not RX_RULE.match(lines[i]) or not RX_IP.match(lines[i + 1]):
        return None
    i += 2
    while i < len(lines) and RX_BANNER.match(lines[i]):
        i += 1
    if i >= len(lines) or not RX_RULE.match(lines[i]):
        return None
    end = i
    i += 1
    fields = {}
    while i < len(lines):
        line = lines[i].rstrip()
        m = RX_LEGACY_KV.match(line)
        if m:
            fields[m.group(1).strip()] = m.group(2)
            end = i
        elif RX_EMPTY.match(line):
            if fields:
                end = i
        elif not line:
            if fields:
                break  # blank line after the fields ends the header
        elif RX_RULE.match(line):
            if fields:
                end = i  # closing rule directly under the fields
            break
        else:
            break
        i += 1
    return fields, end + 1


def build_header(name, fields, log, stamp):
    out = [
        "# " + RULE,
        f"####   Intellectual Property of {OWNER} ####",
        "#####           Do Not Copy without Consent      #####",
        f"#  {name} for {OWNER}",
    ]
    for key in list(CANON) + [k for k in fields if k not in CANON]:
        if key in fields and key not in ("Created", "Last Modified"):
            out.append(f"#  {key}: {fields[key]}".rstrip())
    out.append("#  Created: {}".format(fields.get("Created", "")).rstrip())
    out.append("#  Last Modified: " + stamp)
    out.append("#  Changelog (newest first):")
    out.extend("#    " + entry for entry in log)
    out.append("# " + RULE)
    return out


def stamp_file(path, args):
    """Returns (action, stamp)."""
    try:
        text, bom = read_text(path)
    except UnicodeDecodeError:
        print("WARNING: skipped (not UTF-8, re-save as UTF-8): " + path, file=sys.stderr)
        return "Skipped", ""

    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()

    # Lines that must stay on top: shebang, then a Python encoding line (line 1 or 2).
    keep = 0
    if lines and lines[0].startswith("#!"):
        keep = 1
    if keep < len(lines) and keep < 2 and RX_CODING.match(lines[keep]):
        keep += 1
    prelude, body = lines[:keep], lines[keep:]

    stamp = now_stamp()
    found = parse_seala(body, 0)
    if found:
        fields, log, pos = found
        action, entry = "Updated", "Modified"
    else:
        fields, log, pos = {"Company": ""}, [], 0
        action, entry = "Added", "Header added"

    legacy_created = ""
    legacy = parse_legacy(body, pos)
    if legacy:
        legacy_fields, pos = legacy
        for key, value in legacy_fields.items():
            if key in ("Script Name", "Author"):
                continue
            if key == "Created":
                legacy_created = iso_date(value)
            elif key == "Last Modified":
                line = f"{iso_date(value)} - Last modified per previous header"
                if value.strip() and line not in log:
                    log.append(line)
            elif not fields.get(key, "").strip():
                fields[key] = value
        if action == "Added":
            action, entry = "Migrated", "Header migrated from previous format"
        else:
            action, entry = "Merged", "Merged previous header"

    rest = body[skip_blank(body, pos):]

    fields.setdefault("Company", "")
    for key in CANON:
        given = getattr(args, key.lower())
        if given is not None:
            fields[key] = given

    if args.created is not None:
        fields["Created"] = iso_date(args.created)
    elif not fields.get("Created", "").strip():
        fields["Created"] = legacy_created or created_fallback(path)

    log.insert(0, f"{stamp} - {args.note or entry}")
    header = build_header(os.path.basename(path), fields, log[: args.max_changelog], stamp)

    new_lines = prelude + header + ([""] + rest if rest else [])
    new_text = nl.join(new_lines) + nl

    if args.dry_run:
        return "Preview:" + action, ""
    try:
        if args.backup:
            shutil.copy2(path, path + ".bak")
        write_text(path, new_text, bom)
        if read_text(path)[0] != new_text:
            raise OSError("file on disk does not match what was written")
    except OSError as err:
        print(f"WARNING: NOT written: {path} ({err})", file=sys.stderr)
        return "FAILED", ""
    return action, stamp


def has_script_shebang(path):
    try:
        with open(path, "rb") as fh:
            first = fh.readline(200).decode("utf-8", "replace")
    except OSError:
        return False
    return bool(RX_SHEBANG_OK.match(first))


def collect(paths, recurse):
    for item in paths:
        if os.path.isdir(item):
            if recurse:
                for root, dirs, files in os.walk(item):
                    dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "__pycache__")
                    for name in sorted(files):
                        if os.path.splitext(name)[1].lower() in EXTS:
                            yield os.path.join(root, name)
            else:
                for name in sorted(os.listdir(item)):
                    full = os.path.join(item, name)
                    if os.path.isfile(full) and os.path.splitext(name)[1].lower() in EXTS:
                        yield full
        elif os.path.isfile(item):
            ext = os.path.splitext(item)[1].lower()
            if ext in EXTS or (not ext and has_script_shebang(item)):
                yield item
        else:
            print("WARNING: not found: " + item, file=sys.stderr)


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="seala",
        description="Apply or update the standard header block on Python and shell files.",
        epilog=(
            "examples:\n"
            "  seala sweep.py --role 'Lab sweep' --note 'Initial version'\n"
            "  seala sweep.py -n 'Fixed timeout handling'\n"
            "  seala ~/scripts -r --dry-run\n"
            "  seala backup.sh --created 8/6/2026\n"
            "  git diff --name-only | seala -n 'What changed'\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("paths", nargs="*", help="files or folders; with none, paths are read from stdin")
    ap.add_argument("-n", "--note", help="changelog entry text (default: 'Header added' / 'Modified')")
    ap.add_argument("--company", help="Company line; blank by default, kept from the existing header")
    ap.add_argument("--suite", help="tool set this file belongs to")
    ap.add_argument("--role", help="one line on what this file does")
    ap.add_argument("--runs", help="how or when it runs, e.g. 'cron daily 21:00'")
    ap.add_argument("--created", help="creation date, any common format; overrides the header's value")
    ap.add_argument("--max-changelog", type=int, default=10, metavar="N", help="changelog entries to keep (default 10)")
    ap.add_argument("-r", "--recurse", action="store_true", help="include subfolders")
    ap.add_argument("--backup", action="store_true", help="write <file>.bak before changing a file")
    ap.add_argument("--dry-run", "--whatif", action="store_true", help="show what would happen, write nothing")
    args = ap.parse_args(argv)
    if args.max_changelog < 1:
        ap.error("--max-changelog must be at least 1")

    paths = args.paths
    if not paths:
        if sys.stdin.isatty():
            ap.error("give at least one file or folder")
        paths = [line.strip() for line in sys.stdin if line.strip()]

    failed = False
    for path in collect(paths, args.recurse):
        action, stamp = stamp_file(path, args)
        failed = failed or action == "FAILED"
        print(f"{action:<17} {stamp:<21} {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
