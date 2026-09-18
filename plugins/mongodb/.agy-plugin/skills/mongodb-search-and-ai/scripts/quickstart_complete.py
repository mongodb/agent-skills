#!/usr/bin/env python3
# /// script
# dependencies = [
#   "pymongo>=4.6.0",
# ]
# ///

# MongoDB Search Quickstart — Complete Script
# ─────────────────────────────────────────────────────────────
# Written for the Atlas `sample_mflix.movies` sample collection. The
# schema is hard-coded throughout: the `plot`, `genres`, and `title`
# fields, the index definitions, and the sample query text.
#
# To run against your own data, change the three values below AND
# update the index definitions, `$project` stages, and query strings
# to match your own field names.

CONNECTION_STRING = "your-connection-string-here"
DB_NAME = "sample_mflix"
COLLECTION_NAME = "movies"

INDEX_WAIT_TIMEOUT_SECONDS = 600

# ─────────────────────────────────────────────────────────────

import time
from pymongo import MongoClient
from pymongo.operations import SearchIndexModel

client = MongoClient(CONNECTION_STRING)
db = client[DB_NAME]
collection = db[COLLECTION_NAME]

def fail(message):
    print(f"\n  ERROR: {message}")
    client.close()
    raise SystemExit(1)

def wait_for_index(name):
    print(f"  Waiting for index '{name}' to be ready...", end="", flush=True)
    deadline = time.monotonic() + INDEX_WAIT_TIMEOUT_SECONDS
    while True:
        indexes = list(collection.list_search_indexes(name))
        if not indexes:
            fail(f"Index '{name}' does not exist.")
        status = indexes[0].get("status")
        if status == "READY":
            print(" ready.")
            return
        if status == "STALE":
            print(" stale — queryable, but embedding sync is paused."
                  " Free disk space on the cluster to resume it.")
            return
        if status == "FAILED":
            fail(f"Index '{name}' failed to build. Check the tier index cap"
                 " (3 on Free, 10 on Flex) and the index definition.")
        if time.monotonic() > deadline:
            fail(f"Index '{name}' is still '{status}' after"
                 f" {INDEX_WAIT_TIMEOUT_SECONDS}s. Check its status in Atlas,"
                 " then rerun.")
        print(".", end="", flush=True)
        time.sleep(5)

def ensure_index(model, name):
    try:
        collection.create_search_index(model)
    except Exception as e:
        if "already exists" not in str(e):
            fail(f"Could not create index '{name}': {e}")
        print("  Index already exists.")
    wait_for_index(name)

def print_results(results, fields=["title", "plot"]):
    for i, doc in enumerate(results, 1):
        print(f"\n  {i}. {doc.get('title', 'N/A')}")
        if "score" in doc:
            print(f"     Score: {round(doc['score'], 3)}")
        if "plot" in fields and doc.get("plot"):
            print(f"     Plot:  {doc['plot'][:120]}...")
        if "genres" in doc:
            print(f"     Genres: {doc.get('genres', [])}")

# ─────────────────────────────────────────────────────────────
# 1. CREATE AUTO EMBEDDING INDEX (Semantic Search)
# ─────────────────────────────────────────────────────────────
print("\n── SEMANTIC SEARCH (Auto Embedding) ──────────────────")
print("Creating autoEmbed index on 'plot' field...")

ensure_index(
    SearchIndexModel(
        definition={
            "fields": [
                {
                    "type": "autoEmbed",
                    "modality": "text",
                    "path": "plot",
                    "model": "voyage-4"
                },
                {
                    "type": "filter",
                    "path": "genres"
                }
            ]
        },
        name="quickstart_semantic",
        type="vectorSearch"
    ),
    "quickstart_semantic"
)

# Run semantic query
print("\nQuery: 'a story about growing up'")
results = list(collection.aggregate([
    {
        "$vectorSearch": {
            "index": "quickstart_semantic",
            "path": "plot",
            "query": "a story about growing up",
            "numCandidates": 100,
            "limit": 3
        }
    },
    {
        "$project": {
            "_id": 0,
            "title": 1,
            "plot": 1,
            "score": { "$meta": "vectorSearchScore" }
        }
    }
]))
print_results(results)

# Run filtered semantic query
print("\nFiltered query: 'a story about growing up' + Drama only")
results = list(collection.aggregate([
    {
        "$vectorSearch": {
            "index": "quickstart_semantic",
            "path": "plot",
            "query": "a story about growing up",
            "filter": { "genres": { "$eq": "Drama" } },
            "numCandidates": 150,
            "limit": 3
        }
    },
    {
        "$project": {
            "_id": 0,
            "title": 1,
            "genres": 1,
            "score": { "$meta": "vectorSearchScore" }
        }
    }
]))
print_results(results, fields=["title", "genres"])

# ─────────────────────────────────────────────────────────────
# 2. CREATE TEXT SEARCH INDEX (Keyword Search)
# ─────────────────────────────────────────────────────────────
print("\n── KEYWORD SEARCH (Atlas Search) ─────────────────────")
print("Creating text search index on 'title', 'plot', 'genres'...")

ensure_index(
    SearchIndexModel(
        definition={
            "mappings": {
                "dynamic": False,
                "fields": {
                    "title": [
                        { "type": "string" },
                        { "type": "autocomplete", "tokenization": "edgeGram" }
                    ],
                    "plot": { "type": "string" },
                    "genres": { "type": "token" }
                }
            }
        },
        name="quickstart_text"
    ),
    "quickstart_text"
)

# Run keyword query
print("\nKeyword query: 'space adventure'")
results = list(collection.aggregate([
    {
        "$search": {
            "index": "quickstart_text",
            "text": {
                "query": "space adventure",
                "path": ["title", "plot"]
            }
        }
    },
    {
        "$project": {
            "_id": 0,
            "title": 1,
            "plot": 1,
            "score": { "$meta": "searchScore" }
        }
    },
    { "$limit": 3 }
]))
print_results(results)

# Run fuzzy query
print("\nFuzzy query: 'sapce adventre' (intentional typos)")
results = list(collection.aggregate([
    {
        "$search": {
            "index": "quickstart_text",
            "text": {
                "query": "sapce adventre",
                "path": ["title", "plot"],
                "fuzzy": { "maxEdits": 1 }
            }
        }
    },
    {
        "$project": {
            "_id": 0,
            "title": 1,
            "score": { "$meta": "searchScore" }
        }
    },
    { "$limit": 3 }
]))
print_results(results, fields=["title"])

# Run autocomplete
print("\nAutocomplete query: 'inc'")
results = list(collection.aggregate([
    {
        "$search": {
            "index": "quickstart_text",
            "autocomplete": { "query": "inc", "path": "title" }
        }
    },
    { "$project": { "_id": 0, "title": 1 } },
    { "$limit": 5 }
]))
for doc in results:
    print(f"  - {doc['title']}")

# ─────────────────────────────────────────────────────────────
# 3. HYBRID SEARCH ($rankFusion)
# ─────────────────────────────────────────────────────────────
print("\n── HYBRID SEARCH ($rankFusion) ───────────────────────")
print("Query: 'a story about growing up' (semantic 70% + keyword 30%)")

try:
    results = list(collection.aggregate([
        {
            "$rankFusion": {
                "input": {
                    "pipelines": {
                        "semanticPipeline": [
                            {
                                "$vectorSearch": {
                                    "index": "quickstart_semantic",
                                    "path": "plot",
                                    "query": "a story about growing up",
                                    "numCandidates": 100,
                                    "limit": 20
                                }
                            }
                        ],
                        "keywordPipeline": [
                            {
                                "$search": {
                                    "index": "quickstart_text",
                                    "text": {
                                        "query": "coming of age",
                                        "path": "plot"
                                    }
                                }
                            },
                            { "$limit": 20 }
                        ]
                    }
                },
                "combination": {
                    "weights": {
                        "semanticPipeline": 0.7,
                        "keywordPipeline": 0.3
                    }
                }
            }
        },
        { "$project": { "_id": 0, "title": 1, "plot": 1 } },
        { "$limit": 5 }
    ]))
    print_results(results)
except Exception as e:
    print(f"  Hybrid search requires MongoDB 8.0+. Error: {e}")

print("\n── Done! ─────────────────────────────────────────────")
print("This script targets the sample_mflix.movies schema. To use your")
print("own data, update CONNECTION_STRING, DB_NAME, and COLLECTION_NAME")
print("at the top, then adjust the index definitions, $project stages,")
print("and query strings to match your own field names.")

client.close()
