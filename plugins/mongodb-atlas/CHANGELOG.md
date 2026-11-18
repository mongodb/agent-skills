# Changelog

All notable changes to the `mongodb-atlas` plugin are documented in this file.
This project follows [Semantic Versioning](https://semver.org/). More detailed
entries are available on [GitHub releases](https://github.com/mongodb/agent-skills/releases),
including repository tooling and CI.

The `mongodb-atlas` plugin was introduced in 1.2.1. Earlier versions shipped the
same skills in the single `mongodb` plugin.

## [Unreleased]

### Added

- Gemini plugin manifest (`.gemini-plugin/plugin.json`) with the Atlas MCP
  server and the Gemini OAuth client.
- `mongodb-qe-size-estimation` skill for estimating the storage and memory
  impact of Queryable Encryption
  ([#71](https://github.com/mongodb/agent-skills/pull/71)).
- Automated Embedding guidance in `mongodb-search-and-ai`
  ([#57](https://github.com/mongodb/agent-skills/pull/57)) and a guided
  quickstart walkthrough ([#66](https://github.com/mongodb/agent-skills/pull/66)).
- Antigravity logo and suggested prompts
  ([#84](https://github.com/mongodb/agent-skills/pull/84)).

### Changed

- Antigravity packaging moved to the `.antigravity-plugin/` layout
  ([#80](https://github.com/mongodb/agent-skills/pull/80)).

### Fixed

- `mongodb-atlas-stream-processing` accepts `$$ROOT` in pipelines
  ([#83](https://github.com/mongodb/agent-skills/pull/83)).

## [1.2.1] - 2026-11-10

### Added

- `mongodb-atlas` plugin, which connects to the MongoDB-hosted Atlas MCP
  Server over OAuth ([#49](https://github.com/mongodb/agent-skills/pull/49)),
  pointed at the production endpoint `https://mcp.mongodb.com/`
  ([#53](https://github.com/mongodb/agent-skills/pull/53)).
- Codex plugin support ([#38](https://github.com/mongodb/agent-skills/pull/38),
  [#39](https://github.com/mongodb/agent-skills/pull/39)).
- Plugin READMEs ([#56](https://github.com/mongodb/agent-skills/pull/56)).
- Access pattern analysis in `mongodb-schema-design`
  ([#37](https://github.com/mongodb/agent-skills/pull/37)).
- Skill metadata ([#45](https://github.com/mongodb/agent-skills/pull/45)).

### Changed

- `mongodb-natural-language-querying` has fewer Compass-specific instructions
  and a smaller context size
  ([#35](https://github.com/mongodb/agent-skills/pull/35)).

### Fixed

- Atlas service account navigation steps
  ([#43](https://github.com/mongodb/agent-skills/pull/43)).
- File fixes found during eval testing
  ([#44](https://github.com/mongodb/agent-skills/pull/44)).
- Missing `version` field in the Antigravity manifests
  ([#59](https://github.com/mongodb/agent-skills/pull/59)).

## [1.1.0] - 2026-03-25

### Added

- `mongodb-atlas-stream-processing` skill
  ([#10](https://github.com/mongodb/agent-skills/pull/10)).
- `mongodb-query-optimizer` skill
  ([#6](https://github.com/mongodb/agent-skills/pull/6)).
- `mongodb-connection` skill
  ([#5](https://github.com/mongodb/agent-skills/pull/5)).
- `mongodb-search-and-ai` skill
  ([#9](https://github.com/mongodb/agent-skills/pull/9)).

## [1.0.0] - 2026-03-22

### Added

- `mongodb-natural-language-querying` skill
  ([#2](https://github.com/mongodb/agent-skills/pull/2)).
- `mongodb-schema-design` skill
  ([#7](https://github.com/mongodb/agent-skills/pull/7)).

## [0.5.0] - 2026-03-12

### Added

- Initial release of the MongoDB Agent Skills plugin, with MongoDB MCP Server
  configuration.

[Unreleased]: https://github.com/mongodb/agent-skills/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/mongodb/agent-skills/releases/tag/v1.2.1
[1.1.0]: https://github.com/mongodb/agent-skills/releases/tag/v1.1.0
[1.0.0]: https://github.com/mongodb/agent-skills/releases/tag/v1.0.0
[0.5.0]: https://github.com/mongodb/agent-skills/releases/tag/v0.5.0
