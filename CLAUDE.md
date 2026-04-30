# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`initool` is a small CLI for reading, writing, and deleting key/value pairs in INI files. The same program is implemented in **four parallel languages** — C++, Python, Lua, and Zig — kept behaviorally identical. There is no shared core; each file is a standalone reimplementation. When you change behavior, change it in all four.

The CLI surface (identical across implementations):

```
initool -g | --get  <file> <section> <key>
initool -s | --set  <file> <section> <key> <value>
initool -d | --del  <file> <section> <key>
```

Section/key comparisons are case-insensitive. `--get` writes the value to stdout with no trailing newline; `--set`/`--del` print a confirmation line.

## Files

- `initool.cpp` — primary C++20 implementation, built by `make` and `cmake`.
- `initool.py` — Python 3 implementation. `initool.sh` is a shim that execs it.
- `initool.lua` — Lua implementation.
- `initool.zig` — Zig implementation, built via `make zig`.
- `sample.ini` — fixture used by `make test`.

## Build & test

```
make              # builds C++ release into Darwin_objn/initool (or Linux_objn/)
make DEBUG=1      # debug build into Darwin_objd/initool
make zig          # builds initool_zig via `zig build-exe`
make test         # runs four --get smoke tests against sample.ini
make clean        # removes build dirs and binaries
make install      # copies the built binary to ~/bin (Mac)

bin/build         # CMake release build into ./build/
bin/build -d      # CMake debug build into ./build-debug/
bin/clean         # removes all build artifacts
```

`makefile` and `CMakeLists.txt` only build the C++ source. The Python/Lua scripts run directly; the Zig source is built only via `make zig`.

There is no automated test suite — `make test` is just four `--get` invocations. To exercise `--set`/`--del`, run them manually against a copy of `sample.ini` and inspect the result; the file is rewritten in place.

## Shared design (applies to all four implementations)

All four files implement the same data model and algorithm. If you read one, you understand the others.

- **Round-trip preservation.** Loading the file stores every original line verbatim in a `lines` array. `--set` and `--del` mutate this array and write it back, so comments, blank lines, and unparseable lines are preserved.
- **Three indexes built during load**, all keyed by lowercased names:
  - `section_lines[sec] -> line index` of the `[section]` header.
  - `key_lines[sec][key] -> line index` of the `key = value` line.
  - `data[sec][key] -> unquoted value` (used only by `--get`).
- **`--set` insertion rules:**
  - Key exists → rewrite that line as `<original-cased-lhs> = <quote_if_needed(value)>`.
  - Section exists, key doesn't → walk forward from the section header until the next `[` or EOF; insert before it, stepping back one if the prior line is blank (so the blank stays as a separator).
  - Section doesn't exist → append a blank line (if needed), then `[section]`, then the key line.
  - After insertion or deletion, every stored line index in `section_lines` and `key_lines` greater than the affected line is shifted by ±1.
- **Quoting.** Values are unquoted on read if surrounded by `"…"`. On write, `quote_if_needed` adds quotes only if the value contains a space or `=`.
- **Parsing tolerance.** Inside a section, lines without `=` are skipped silently (see the "random junk" line in `sample.ini`). Lines starting with `;` are comments. A section header must be `[…]` of length ≥ 3.
- **Errors** are thrown/raised with messages like `"Error: key not found"` and caught in `main`, which prints to stderr and exits 1.

When fixing a bug or changing behavior in one implementation, replicate the change in the other three and re-run `make test` (and ad-hoc `--set`/`--del` checks) against each.
