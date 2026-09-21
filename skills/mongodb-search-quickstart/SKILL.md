---
name: mongodb-search-quickstart
description: |
  Runs a guided, hands-on tour of MongoDB Search and Vector Search against the `sample_mflix` sample dataset. Use this skill when a user is new to MongoDB search, asks for a guided tour, walkthrough, demo, or tutorial, or has no specific use case yet and wants to see semantic search (Automated Embedding), keyword search, and hybrid search working end to end. Requires Atlas cloud or Atlas Local, because the tour depends on the sample dataset and Automated Embedding. To build search on the user's own data, or on a generic self-managed deployment, use the mongodb-search-and-ai skill instead.
license: Apache-2.0
metadata:
  version: "1.0.0"
---

# MongoDB Search Quickstart

This skill runs one prescribed walkthrough: a guided tour that builds semantic, keyword, and hybrid search against the `sample_mflix` sample dataset, explaining each result as it goes.

It is for users who want to *see* MongoDB search work before designing anything. The user is following, not driving.

## When to use this skill

Use it when the user is new to MongoDB search, asks for a tour, walkthrough, demo, or tutorial, or has no specific use case yet.

Do not use it when the user has their own data and a concrete search requirement. That is the `mongodb-search-and-ai` skill, which covers index design, query construction, and optimization for real workloads.

## Prerequisites

- The MongoDB MCP server is connected.
- The deployment is Atlas cloud or Atlas Local. Both provide `sample_mflix` and support Automated Embedding. On Atlas Local that means the preview image and a Voyage AI key; the walkthrough's Scope section gives the one-command setup. A generic self-managed deployment cannot complete the prescribed sequence, and Step 0 routes it to `mongodb-search-and-ai`.

## How to run it

Follow `references/quick-start.md` exactly. It prescribes the interaction sequence, the index names, and the queries. Do not improvise a substitute sequence or skip its Step 0 deployment check.

The walkthrough ends by offering the user a standalone script, `scripts/quickstart_complete.py`, that reproduces everything it just did.

## Handing off

When the user finishes the tour and wants to apply any of it to their own data, hand off to the `mongodb-search-and-ai` skill. That skill holds the reference material for Automated Embedding, manual vector search, lexical indexing and querying, and hybrid search.
