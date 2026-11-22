"""Write a schema slice into the canvas template.

    python3 -I fill.py <canvas.html> <schema.json> <out.html>

schema.json is introspect.sql's output, with title, source and any change marks added.
"""
import html
import json
import sys
from typing import NoReturn

Json = dict[str, "Json"] | list["Json"] | str | int | float | bool | None


def fail(message: str) -> NoReturn:
    sys.exit(f"fill.py: {message}")


def entries(owner: Json, key: str, where: str, required: tuple[str, ...]) -> list[dict[str, Json]]:
    """owner[key] as a list of objects, each holding the required strings; a missing key is an empty list."""
    value = owner.get(key) if isinstance(owner, dict) else None
    if value is None:
        return []
    if not isinstance(value, list):
        fail(f"{where}: {key} must be a list")
    found: list[dict[str, Json]] = []
    for i, item in enumerate(value):
        if not isinstance(item, dict):
            fail(f"{where}: {key}[{i}] must be an object")
        for field in required:
            if not isinstance(item.get(field), str):
                fail(f"{where}: {key}[{i}] has no {field}")
        found.append(item)
    return found


def check(data: Json, path: str) -> int:
    """Stop on anything the canvas cannot draw; return how many tables there are."""
    if not isinstance(data, dict):
        fail(f"{path}: expected an object with tables, found {type(data).__name__}")
    tables = entries(data, "tables", path, ("id", "schema", "name"))
    if not tables:
        fail(f"{path}: no tables; check the schemas and tables given to introspect.sql")
    for table in tables:
        where = f"{path}: {table['id']}"
        for column in entries(table, "columns", where, ("name", "type")):
            entries(column, "fk", f"{where}.{column['name']}", ("table", "column"))
    for enum in entries(data, "enums", path, ("id", "name")):
        values = enum.get("values")
        if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
            fail(f"{path}: {enum['id']}: values must be a list of strings")
    title = data.get("title")
    if title is not None and not isinstance(title, str):
        fail(f"{path}: title must be a string")
    return len(tables)


def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError) as e:
        fail(f"{path}: {e}")


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit("usage: fill.py <canvas.html> <schema.json> <out.html>")
    template_path, data_path, out_path = sys.argv[1:]
    page = read(template_path)
    try:
        data: Json = json.loads(read(data_path))
    except json.JSONDecodeError as e:
        fail(f"{data_path}: not JSON: {e}")
    count = check(data, data_path)
    for marker in ("__SCHEMA_TITLE__", "__SCHEMA_JSON__"):
        if page.count(marker) != 1:
            fail(f"{template_path}: expected one {marker}, found {page.count(marker)}")

    # Inside a <script>, "</" ends the block and "<!--" changes how the rest is parsed, so no "<" is left.
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    title = data.get("title") if isinstance(data, dict) else None
    page = page.replace("__SCHEMA_TITLE__", html.escape(title if isinstance(title, str) and title else "Schema"))
    page = page.replace("__SCHEMA_JSON__", payload)
    try:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(page)
    except OSError as e:
        fail(f"{out_path}: {e}")
    print(f"{out_path}: {count} tables, {len(page) // 1024} KB")


main()
