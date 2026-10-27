#!/usr/bin/env python3
"""Check a schema-only publication candidate without printing matched values.

Default: inspect this package's working files, excluding private/generated folders.
Use --staged to inspect Git's index (the exact proposed commit), --tracked for
tracked working files, or pass explicit files/directories relative to the package.
This is a conservative review aid, not proof that arbitrary SQL contains no secrets.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PUBLIC_DIRS = {"database", "docs", "scripts", "tests"}
PUBLIC_ROOT_FILES = {"README.md", "LICENSE", "LICENSE.txt", ".gitignore", "CHANGELOG.md"}
PUBLIC_SUFFIXES = {".sql", ".md", ".txt", ".py", ".sh", ".json"}
PRIVATE_PARTS = {".private", ".git", ".runtime", "node_modules", "__pycache__", "reports", "backups"}
FORBIDDEN_NAMES = {".env", ".pgpass", "pgpass.conf", "connection.json", "connection-details.txt"}

# The labels, paths, and line numbers are safe to print. Never print a match.
PATTERNS = {
    "literal SQL password": re.compile(r"\bPASSWORD\s+(?:E)?'[^']+'", re.I),
    "quoted credential assignment": re.compile(
        r'''\b(?:password|passwd|pwd|api[_-]?key|client[_-]?secret|access[_-]?token)\b["']?\s*[:=]\s*(["'])[^\r\n"']+\1''',
        re.I,
    ),
    "credential in connection URL": re.compile(r"\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|https?)://[^\s/:]+:[^\s/@]+@", re.I),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    "known access token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16}|sk-(?:proj-)?[A-Za-z0-9_-]{24,})\b"),
    "password hash": re.compile(r"(?:\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}|SCRAM-SHA-256\$\d+:|\bmd5[0-9a-f]{32}\b)", re.I),
    "table data COPY": re.compile(r"\bCOPY\s+[^;]+?\s+FROM\s+stdin\s*;", re.I),
    "pg_dump table data section": re.compile(r"^--.*\bType: TABLE DATA;", re.M),
}


def git(*args: str) -> bytes:
    result = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True)
    if result.returncode:
        raise ValueError("Git could not read the requested candidate files; use explicit paths outside a checkout.")
    return result.stdout


def permitted(path: Path) -> bool:
    parts = path.parts
    if not parts or any(part in PRIVATE_PARTS for part in parts):
        return False
    if path.name in FORBIDDEN_NAMES or path.name.startswith(".env.") and not path.name.endswith(".example"):
        return False
    if len(parts) == 1:
        return path.name in PUBLIC_ROOT_FILES
    return parts[0] in PUBLIC_DIRS and path.suffix.lower() in PUBLIC_SUFFIXES


def findings(data: str) -> list[tuple[int, str]]:
    found = []
    for label, pattern in PATTERNS.items():
        for match in pattern.finditer(data):
            found.append((data.count("\n", 0, match.start()) + 1, label))
    return sorted(set(found))


def working_files(directory: Path):
    """Prune private trees before traversal, including a disposable PG cluster."""
    for current, directories, files in os.walk(directory, followlinks=False):
        directories[:] = [name for name in directories if name not in PRIVATE_PARTS]
        for name in directories[:]:
            path = Path(current) / name
            if path.is_symlink():
                directories.remove(name)
                yield path
        for name in files:
            yield Path(current) / name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--staged", action="store_true", help="inspect index contents, including staged files now ignored")
    group.add_argument("--tracked", action="store_true", help="inspect tracked working files")
    parser.add_argument("paths", nargs="*", help="explicit files/directories relative to this package")
    args = parser.parse_args()
    if args.paths and (args.staged or args.tracked):
        parser.error("explicit paths cannot be combined with --staged/--tracked")

    try:
        if args.staged:
            names = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").decode().split("\0")
            candidates = {Path(name) for name in names if name}
        elif args.tracked:
            candidates = {Path(name) for name in git("ls-files", "-z").decode().split("\0") if name}
        else:
            candidates = set()
            inputs = [ROOT / name for name in args.paths] if args.paths else [ROOT]
            for item in inputs:
                if not item.exists():
                    raise ValueError("A requested candidate path does not exist.")
                for path in working_files(item) if item.is_dir() and not item.is_symlink() else [item]:
                    relative = path.relative_to(ROOT)
                    # Private folders are excluded from automatic traversal. An explicit
                    # private file, or any tracked/staged private file, fails the allowlist.
                    if item.is_dir() and any(part in PRIVATE_PARTS for part in relative.parts):
                        continue
                    if path.is_file() or path.is_symlink():
                        candidates.add(relative)

        failures = []
        inspected = 0
        for path in sorted(candidates):
            if not permitted(path) or (ROOT / path).is_symlink() or ".." in path.parts or path.is_absolute():
                failures.append(f"{path}: outside the publication allowlist")
                continue
            if args.staged:
                data = git("show", f":{path.as_posix()}")
            else:
                data = (ROOT / path).read_bytes()
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                failures.append(f"{path}: non-UTF-8 content needs separate review")
                continue
            inspected += 1
            failures.extend(f"{path}:{line}: {label}" for line, label in findings(text))

        if failures:
            print("Publication check failed:")
            print("\n".join(f"- {entry}" for entry in failures))
            return 1
        if not inspected:
            print("No candidate files found; nothing was verified.")
            return 1
        print(f"Publication check passed for {inspected} files. Review SQL bodies and comments before publishing.")
        return 0
    except (OSError, ValueError, UnicodeError) as error:
        print(f"Publication check could not complete: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
