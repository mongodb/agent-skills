// OpenCode server plugin for the MongoDB community plugin: registers the
// self-managed MongoDB MCP Server (stdio, via npx) and the plugin's bundled
// agent skills. Mirrors plugins/mongodb/mcp.json for the other harnesses.
//
// The OpenCode package root is this plugin's root (plugins/mongodb): the same
// folder every other harness installs, with package.json as the manifest and
// this folder holding the OpenCode-specific entry code. Users install with:
//   opencode plugin add opencode-plugin-mongodb        (npm, primary)
//   opencode plugin add github:mongodb/agent-skills#v<release-tag>::path:plugins/mongodb
//                                                      (git spec, tag-pinned fallback)

import { Plugin, Skill } from "@opencode/plugin";
import { join } from "node:path";
import { loadBundledSkills } from "./skills.ts";

export default Plugin.define({
  id: "mongodb",
  async setup(ctx) {
    // The package root is the parent of this .opencode-plugin/ directory.
    const packageDir = join(import.meta.dirname, "..");

    // MCP: same server as plugins/mongodb/mcp.json
    // ({"mcpServers":{"mongodb":{"command":"npx","args":["-y","mongodb-mcp-server@<4"]}}}),
    // in OpenCode's local-server shape (a single `command` array).
    await ctx.mcp.transform((editor) => {
      editor.set("mongodb", {
        type: "local",
        command: ["npx", "-y", "mongodb-mcp-server@<4"],
      });
    });

    // Skills: the plugin's skills/ copy (the same one every other harness
    // installs), registered with the same IDs the other harnesses use (the
    // skill's directory name, e.g. "mongodb-schema-design").
    const skills = loadBundledSkills(packageDir);
    await ctx.skill.transform((editor) => {
      for (const skill of skills) {
        editor.add({
          id: Skill.ID.make(skill.id),
          name: Skill.Name.make(skill.name),
          description: skill.description,
          path: Skill.Info.fields.path.make(skill.path),
          content: skill.content,
        });
      }
    });
  },
});
