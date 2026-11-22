---
name: schema
description: Draw a slice of a database schema as a private claude.ai Artifact - tables as cards you drag, pan and zoom, joined by their foreign keys, with a proposed change marked - read from the structure only, never the rows. Use when asked to show, map, diagram or visualise some tables, a schema or how tables relate, or to picture a migration before writing it.
argument-hint: "<tables, a schema, a feature area, or ABC-123>"
---

# Draw a slice of the schema

The output is one Artifact that shows the chosen tables the way a database's own visualiser does, which the user can rearrange.
It reads the schema's structure, never its rows, writes nothing in the repository and changes no git state.

The three files beside this one do the work, in this skill's directory (installed at `~/.keel/claude/skills/schema/`):

- `introspect.sql` reads a slice from Postgres's catalog as the JSON the canvas draws.
- `canvas.html` is the page: cards, plain lines along the foreign keys, pan, zoom, drag, fold, tidy, and a key. What a foreign key points at, its cardinality and its delete rule are written on its own row.
- `fill.py` writes the JSON and title into a copy of the page.

Never edit `canvas.html` for one drawing.
Something the canvas cannot show is a change to the template, made in keel.

## 1. Pick the slice

- The slice is the argument: table names, a schema, a feature area such as "billing", or an issue ID.
- An issue's slice is the tables the issue and its `/audit-issue` write-up touch.
- A feature area becomes table names by searching the schema for its terms. Say which tables you took.
- Tables one foreign key away come along as neighbours, drawn dashed and folded to their keys, so no line ends in the air. Do not add them to the slice yourself.
- Keep it under about 25 tables. Ask to narrow a bigger slice rather than draw a wall of cards.

## 2. Read the structure

Take the first source that exists, and name it in `source`:

1. **A running local or dev database.** For Supabase, `supabase status -o env` gives `DB_URL`; otherwise use the URL the repository's local setup uses. Never point it at production.

   ```sh
   psql "$DB_URL" -X -q -A -t -v schemas=public -v tables=invoices,customers \
     -f ~/.keel/claude/skills/schema/introspect.sql > "$CLAUDE_JOB_DIR/tmp/schema.json"
   ```

   `schemas` is the comma-separated schemas to look in, and `tables` the slice, by name or `schema.name`; leave `tables` empty for every table in those schemas.
   Neighbours in other schemas, such as `auth.users`, come back on their own.
2. **A database the repository starts.** When none is up, start it the way the repository does, `keel stack up` where it has one, and read it as above.
3. **The schema files.** When no database can run, write the JSON by hand in the shape below, from the declarative source (`supabase/schemas/*.sql`, `schema.prisma`, Drizzle tables), or else from the migrations read in order.
   Set `source` to say it was read from files, since a hand reading can miss what the database would report.

Read no rows.
Defaults and comments are published with the page, so drop any that hold a credential or a customer's data.

## 3. Shape the data

Add to the JSON before filling:

- `title`: the slice's name, two to four words, such as `Invoicing`. It names the Artifact too.
- `source`: where it came from, such as `local Supabase · main @ 55097e2`.
- For a change not yet applied, from an issue or a migration being written, draw the schema after it and mark what moves:
  `"change": "added"`, `"changed"` or `"removed"` on a table or column, and `"was": "<old type>"` on a changed column.
  A removed table or column stays in the JSON so the user sees it go.
- Optional: `note` on a table for one line of context, `collapsed: true` to fold a focus table, and `x`, `y` on every table to fix a layout.

What `introspect.sql` returns, for writing it by hand:

```json
{
  "tables": [{
    "id": "public.invoices", "schema": "public", "name": "invoices", "kind": "table",
    "focus": true, "rls": true, "policies": [{"name": "members read", "cmd": "SELECT"}], "comment": null,
    "columns": [
      {"name": "id", "type": "bigint", "nullable": false, "pk": true, "identity": true},
      {"name": "customer_id", "type": "bigint", "nullable": false,
       "fk": [{"table": "public.customers", "column": "id", "onDelete": "restrict", "one": false, "optional": false}]},
      {"name": "status", "type": "invoice_status", "nullable": false, "default": "'draft'::invoice_status",
       "enum": "public.invoice_status"}
    ]
  }],
  "enums": [{"id": "public.invoice_status", "schema": "public", "name": "invoice_status", "values": ["draft", "open", "paid"]}]
}
```

`one` on a foreign key is true when its columns are unique together, and `optional` when any of them is nullable.
`focus: false` marks a neighbour; `unique`, `generated` and `comment` are optional on a column.

## 4. Build it

Start with the Artifact tool's `action: "quickstart"`, `intent: "other"`, as every new Artifact does.
No listed type draws a schema, so the page is this template, published as a plain page:

```sh
python3 -I ~/.keel/claude/skills/schema/fill.py ~/.keel/claude/skills/schema/canvas.html \
  "$CLAUDE_JOB_DIR/tmp/schema.json" "$CLAUDE_JOB_DIR/tmp/<slug>.html"
```

It stops with the reason when the JSON is not one the canvas can draw, such as a misspelt table leaving no tables at all.

Publish that file with `icon: "database"` and a one-sentence `description` naming the slice.
Keep the JSON and the page out of the repository.

## 5. Revise it in place

Republish the same file path, so the link stays, for each change the user asks for.

- The layout a user drags lives only in their browser.
  **Copy layout** puts it on their clipboard; when they paste it to you, copy each `x`, `y` into the JSON and republish.
  Anyone who already moved tables on that page keeps their own layout until they press **Reset**.
- A different slice of the same schema is a new Artifact, with its own file path.
- When the slice came from an issue, offer to add the link to it with `keel linear comment`; do not add it unasked.

## 6. Report

The link, the tables in the slice and its neighbours, and the source.
Say what you inferred: the tables a feature area or issue meant, and each change you marked.
When the schema came from files rather than a database, say so.
