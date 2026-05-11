---
name: schema-visualization
description: Visualize MongoDB database schemas as diagrams. Use this skill when users want to see their database structure visually, generate ER diagrams, view collection relationships, or export schema diagrams. Triggers on "visualize schema", "schema diagram", "ER diagram", "show me the database structure", "draw the collections", "database diagram", "visualize collections", "show relationships between collections", "generate a diagram of my database". Also use when users ask to "see" or "view" their schema in a graphical or diagrammatic form, even if they don't use the word "visualize" explicitly. Requires MongoDB MCP server.
license: Apache-2.0
---

# Schema Visualization

Generate visual diagrams of MongoDB database schemas using the `database-schema` MCP tool. The approach depends on the user's environment.

## Step 1: Determine the Environment

Detect which environment the user is running in:

- **CLI** (terminal-only, no GUI rendering): Claude Code CLI without an IDE, or any terminal-based session
- **IDE / Desktop** (VS Code, Cursor, Claude Code Desktop app): environments that can render or preview Mermaid diagrams

Use context clues: if you're running inside VS Code or Cursor, you're in an IDE environment. If you're in a plain terminal session, you're in CLI mode. If uncertain, ask the user.

## Step 2a: CLI Environment

When in a terminal-only environment:

1. **Check that Graphviz is installed.** Run `dot -V` to verify. If it's not installed, tell the user how to install it:
   - macOS: `brew install graphviz`
   - Ubuntu/Debian: `sudo apt-get install graphviz`
   - Fedora: `sudo dnf install graphviz`

2. **Get the database schema in DOT format.** Call the `database-schema` tool with `exportFormat: "dot"` and optionally `inferRelationships: true` if the user wants to see relationships. Save the DOT output to a temporary file (e.g., `/tmp/schema.dot`).

3. **Render an ASCII diagram.** Use Graphviz to produce a text-based representation the user can see directly in their terminal:
   ```bash
   dot -Tplain /tmp/schema.dot
   ```
   Parse the plain-text output and present a readable summary of collections and their fields in the terminal. Alternatively, if the `graph-easy` tool is available (`which graph-easy`), use it for better ASCII rendering:
   ```bash
   dot -Tcanon /tmp/schema.dot | graph-easy --from=dot --as=ascii
   ```

4. **Offer to save in other formats.** After displaying the ASCII version, ask the user if they'd like to export the diagram as PNG, SVG, or PDF:
   - PNG: `dot -Tpng /tmp/schema.dot -o schema.png`
   - SVG: `dot -Tsvg /tmp/schema.dot -o schema.svg`
   - PDF: `dot -Tpdf /tmp/schema.dot -o schema.pdf`

   Let the user choose the output path and filename.

## Step 2b: IDE / Desktop Environment (VS Code, Cursor, Claude Code Desktop)

When in an environment that supports file preview or Mermaid rendering:

1. **Get the database schema in Mermaid format.** Call the `database-schema` tool with `exportFormat: "mmd"` and optionally `inferRelationships: true`.

2. **Try to display the Mermaid diagram directly.** If the environment supports rendering Mermaid inline (e.g., a markdown preview panel), write the output to a `.mmd` or `.md` file and open it for preview.

3. **If direct rendering isn't possible**, save the Mermaid content to a file (e.g., `schema.mmd` in the project root or a location the user specifies) and give the user instructions:

   **For VS Code / Cursor:**
   - Install the "Markdown Preview Mermaid Support" extension (or "Mermaid Preview")
   - Open the `.mmd` file, or wrap the content in a markdown code fence:
     ````
     ```mermaid
     <diagram content>
     ```
     ````
   - Use the Markdown preview (Cmd+Shift+V / Ctrl+Shift+V) to see the rendered diagram

   **For Claude Code Desktop:**
   - Save as a `.md` file with a mermaid code fence and open in any markdown viewer

## Before Running

Tell the user that schema generation may take a moment, since it samples documents from every collection in the database to infer field types. If `inferRelationships` is enabled, it takes significantly longer because it runs additional queries against each collection to validate potential foreign key relationships.

Also inform the user about size limits: the `database-schema` tool operates within a response byte limit (default ~1MB). For databases with many collections or very wide schemas, the output may be truncated or some collections may have incomplete field lists. If the user has a large database, suggest focusing on specific collections of interest or keeping `sampleSize` low.

## Tips

- Always ask the user which database to visualize if multiple are available.
- Suggest `inferRelationships: true` when the user wants to understand how collections relate to each other — mention that it requires additional queries to validate relationships.
- For large databases (many collections), warn the user that the diagram may be complex and offer to filter to specific collections if the tool supports it.
