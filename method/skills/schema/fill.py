"""Write a schema slice into the canvas template.

    python3 -I fill.py <canvas.html> <schema.json> <out.html>

schema.json is introspect.sql's output, with title, source and any change marks added.
"""
import html
import json
import sys

template_path, data_path, out_path = sys.argv[1:4]
with open(template_path, encoding="utf-8") as f:
    page = f.read()
with open(data_path, encoding="utf-8") as f:
    data = json.load(f)

for marker in ("__SCHEMA_TITLE__", "__SCHEMA_JSON__"):
    if page.count(marker) != 1:
        sys.exit(f"{template_path}: expected one {marker}, found {page.count(marker)}")

# "</" would end the <script> block early, so it is escaped; JSON reads "<\/" back as "</".
payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
page = page.replace("__SCHEMA_TITLE__", html.escape(data.get("title") or "Schema"), 1)
page = page.replace("__SCHEMA_JSON__", payload, 1)

with open(out_path, "w", encoding="utf-8") as f:
    f.write(page)
print(f"{out_path}: {len(data.get('tables', []))} tables, {len(page) // 1024} KB")
