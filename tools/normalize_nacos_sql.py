#!/usr/bin/env python3

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

csv.field_size_limit(sys.maxsize)

INSERT_RE = re.compile(r"^\s*(INSERT|REPLACE) INTO `([^`]+)` VALUES \((.*)\);\s*$", re.S)


def parse_insert_fields(line: str) -> list[str]:
    match = INSERT_RE.match(line)
    if not match:
        raise ValueError("unsupported insert line")
    values = match.group(3)
    return next(csv.reader([values], delimiter=",", quotechar="'", escapechar="\\"))


def replace_insert_prefix(line: str) -> str:
    stripped = line.lstrip()
    indent = line[: len(line) - len(stripped)]
    if stripped.startswith("REPLACE INTO "):
        return line
    return indent + "REPLACE INTO " + stripped[len("INSERT INTO ") :]


def config_sort_key(fields: list[str]) -> tuple[str, str, int]:
    gmt_create = fields[5]
    gmt_modified = fields[6]
    row_id = int(fields[0] or "0")
    return (gmt_modified, gmt_create, row_id)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: normalize_nacos_sql.py <input.sql> <output.sql>", file=sys.stderr)
        return 1

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    lines = input_path.read_text(encoding="utf-8").splitlines(keepends=True)

    latest_config_rows: dict[tuple[str, str, str], tuple[tuple[str, str, int], str]] = {}
    rendered_lines: list[str] = []
    config_inserted = False

    for line in lines:
        stripped = line.lstrip()

        if stripped.startswith("DROP TABLE IF EXISTS"):
            rendered_lines.append("-- " + stripped)
            continue

        if stripped.startswith("CREATE TABLE `"):
            rendered_lines.append(line.replace("CREATE TABLE `", "CREATE TABLE IF NOT EXISTS `", 1))
            continue

        match = INSERT_RE.match(line)
        if match:
            table = match.group(2)
            if table == "config_info":
                fields = parse_insert_fields(line)
                if fields[1] == "cmict-share.yaml":
                    continue
                key = (fields[1], fields[2], fields[10] or "")
                candidate = (config_sort_key(fields), replace_insert_prefix(line))
                current = latest_config_rows.get(key)
                if current is None or candidate[0] >= current[0]:
                    latest_config_rows[key] = candidate
                continue

            if table == "his_config_info":
                continue

            rendered_lines.append(replace_insert_prefix(line))
            continue

        rendered_lines.append(line)
        if stripped.startswith("-- Records of config_info") and not config_inserted:
            for _key, (_sort_key, row_line) in sorted(latest_config_rows.items()):
                rendered_lines.append(row_line if row_line.endswith("\n") else row_line + "\n")
            config_inserted = True

    if not config_inserted and latest_config_rows:
        rendered_lines.append("\n-- Records of config_info\n")
        for _key, (_sort_key, row_line) in sorted(latest_config_rows.items()):
            rendered_lines.append(row_line if row_line.endswith("\n") else row_line + "\n")

    output_path.write_text("".join(rendered_lines), encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
