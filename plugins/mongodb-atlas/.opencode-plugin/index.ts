// OpenCode server plugin for the MongoDB Atlas plugin: registers the
// MongoDB-hosted MCP server (https://mcp.mongodb.com/) and the plugin's
// bundled agent skills.
//
// The OpenCode package root is this plugin's root (plugins/mongodb-atlas):
// package.json is the manifest, this folder holds the entry code, and the
// skills come from the plugin's existing skills/ copy. Users install with:
//   opencode plugin add opencode-plugin-mongodb-atlas      (npm, primary)
//   opencode plugin add github:mongodb/agent-skills#v<release-tag>::path:plugins/mongodb-atlas
//                                                          (git spec fallback)
//
// OAuth: OpenCode resolves a client as pre-registered client_id -> CIMD -> DCR.
// Atlas only accepts clients seeded in atlas-iam (see CONTRIBUTING.md,
// "atlas-iam OAuth client seed"), and OpenCode is seeded with the static
// client_id "opencode" — its CIMD URL is NOT seeded. Atlas advertises CIMD, so
// without an explicit client_id OpenCode would send its unseeded CIMD URL and
// be rejected. The pre-registered client_id below takes priority over CIMD.
// redirect_uri is left at OpenCode's default loopback callback, which must
// match a seeded path (/mcp/oauth/callback or /callback; any port).

import { Plugin, Skill } from "@opencode/plugin";
import { join } from "node:path";
import { loadBundledSkills } from "./skills.ts";

export default Plugin.define({
  id: "mongodb-atlas",
  async setup(ctx) {
    // The package root is the parent of this .opencode-plugin/ directory.
    const packageDir = join(import.meta.dirname, "..");

    // MCP: the hosted Atlas server, authenticated as the seeded "opencode"
    // client (see the header comment).
    await ctx.mcp.transform((editor) => {
      editor.set("mongodb-atlas", {
        type: "remote",
        url: "https://mcp.mongodb.com/",
        oauth: { client_id: "opencode" },
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
