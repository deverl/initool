#!/usr/bin/env python3

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path


def trim(s: str) -> str:
    return s.strip(" \t\r\n")


def to_lower(s: str) -> str:
    return s.lower()


def starts_with(s: str, c: str) -> bool:
    return bool(s) and s[0] == c


def is_section_header(s: str) -> bool:
    return len(s) >= 3 and s[0] == "[" and s[-1] == "]"


def unquote(s: str) -> str:
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1]
    return s


def quote_if_needed(s: str) -> str:
    if any(ch in s for ch in (" ", "=")):
        return f'"{s}"'
    return s


@dataclass
class IniFile:
    path: Path
    lines: list[str] = field(default_factory=list)
    section_lines: dict[str, int] = field(default_factory=dict)
    key_lines: dict[str, dict[str, int]] = field(default_factory=dict)
    data: dict[str, dict[str, str]] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.load()

    def get(self, section: str, key: str) -> str:
        sec = to_lower(section)
        k = to_lower(key)
        if sec in self.data and k in self.data[sec]:
            return self.data[sec][k]
        raise RuntimeError("Error: key not found")

    def set(self, section: str, key: str, value: str) -> None:
        sec_lower = to_lower(section)
        key_lower = to_lower(key)
        val = value

        if sec_lower not in self.section_lines:
            if self.lines and trim(self.lines[-1]) != "":
                self.lines.append("")
            self.lines.append(f"[{section}]")
            self.lines.append(f"{key} = {quote_if_needed(val)}")
            self.write()
            return

        section_line = self.section_lines[sec_lower]
        keys = self.key_lines.setdefault(sec_lower, {})

        if key_lower in keys:
            line_no = keys[key_lower]
            line = self.lines[line_no]
            pos = line.find("=")
            lhs = trim(line[:pos]) if pos != -1 else trim(line)
            self.lines[line_no] = f"{lhs} = {quote_if_needed(val)}"
            self.write()
            return

        insert_at = section_line + 1
        while insert_at < len(self.lines):
            t = trim(self.lines[insert_at])
            if starts_with(t, "["):
                if insert_at > section_line + 1 and trim(self.lines[insert_at - 1]) == "":
                    insert_at -= 1
                break
            insert_at += 1

        self.lines.insert(insert_at, f"{key} = {quote_if_needed(val)}")
        self.write()

    def delete(self, section: str, key: str) -> None:
        sec_lower = to_lower(section)
        key_lower = to_lower(key)

        if sec_lower not in self.key_lines:
            raise RuntimeError("Error: section not found")

        keys = self.key_lines[sec_lower]
        if key_lower not in keys:
            raise RuntimeError("Error: key not found")

        line_no = keys[key_lower]
        del self.lines[line_no]

        if sec_lower in self.data:
            self.data[sec_lower].pop(key_lower, None)
        keys.pop(key_lower, None)

        for _sec, _keys in self.key_lines.items():
            for _k, _lineno in list(_keys.items()):
                if _lineno > line_no:
                    _keys[_k] = _lineno - 1

        for _sec, _lineno in list(self.section_lines.items()):
            if _lineno > line_no:
                self.section_lines[_sec] = _lineno - 1

        self.write()

    def load(self) -> None:
        try:
            with self.path.open("r", encoding="utf-8") as f:
                raw_lines = f.read().splitlines()
        except OSError:
            raise RuntimeError(f"Error: cannot open file {self.path}") from None

        self.lines = list(raw_lines)
        self.section_lines.clear()
        self.key_lines.clear()
        self.data.clear()

        current_section = ""
        for lineno, line in enumerate(self.lines):
            t = trim(line)
            if t == "" or starts_with(t, ";"):
                continue

            if is_section_header(t):
                current_section = to_lower(trim(t[1:-1]))
                self.section_lines[current_section] = lineno
                continue

            if current_section:
                pos = t.find("=")
                if pos != -1:
                    k = to_lower(trim(t[:pos]))
                    v = unquote(trim(t[pos + 1 :]))
                    self.data.setdefault(current_section, {})[k] = v
                    self.key_lines.setdefault(current_section, {})[k] = lineno

    def write(self) -> None:
        try:
            with self.path.open("w", encoding="utf-8", newline="\n") as f:
                for line in self.lines:
                    f.write(line)
                    f.write("\n")
        except OSError:
            raise RuntimeError(f"Error: cannot write file {self.path}") from None


def usage(argv0: str) -> None:
    sys.stderr.write(
        "\nUsage:\n"
        f"  {argv0} -g, --get <file> <section> <key>\n"
        f"  {argv0} -s, --set <file> <section> <key> <value>\n"
        f"  {argv0} -d, --del <file> <section> <key>\n\n"
    )


def main(argv: list[str]) -> int:
    try:
        if len(argv) < 2:
            usage(argv[0])
            return 1

        command = argv[1]
        if command in ("--get", "-g"):
            if len(argv) != 5:
                sys.stderr.write(f"Usage: {argv[0]} --get <file> <section> <key>\n")
                return 1
            ini = IniFile(Path(argv[2]))
            sys.stdout.write(ini.get(argv[3], argv[4]))
            return 0

        if command in ("--set", "-s"):
            if len(argv) != 6:
                sys.stderr.write(f"Usage: {argv[0]} --set <file> <section> <key> <value>\n")
                return 1
            ini = IniFile(Path(argv[2]))
            ini.set(argv[3], argv[4], argv[5])
            sys.stdout.write(f"Updated [{argv[3]}] {argv[4]} = {argv[5]}\n")
            return 0

        if command in ("--del", "-d"):
            if len(argv) != 5:
                sys.stderr.write(f"Usage: {argv[0]} --del <file> <section> <key>\n")
                return 1
            ini = IniFile(Path(argv[2]))
            ini.delete(argv[3], argv[4])
            sys.stdout.write(f"Deleted [{argv[3]}] {argv[4]}\n")
            return 0

        sys.stderr.write(f"Unknown command: {command}\n")
        return 1
    except Exception as e:
        sys.stderr.write(str(e) + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

