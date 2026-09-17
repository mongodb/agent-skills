#!/usr/bin/env python3
# /// script
# dependencies = [
#   "pymongo>=4.6.0",
# ]
# ///

# MongoDB Search Quickstart — Complete Script
# ─────────────────────────────────────────────────────────────
# Change these three values to use your own data:

CONNECTION_STRING = "your-connection-string-here"
DB_NAME = "sample_mflix"
COLLECTION_NAME = "movies"

# ─────────────────────────────────────────────────────────────

import time
from pymongo import MongoClient
from pymongo.operations import SearchIndexModel

client = MongoClient(CONNECTION_STRING)
db = client[DB_NAME]
collection = db[COLLECTION_NAME]

def wait_for_index(name, index_type="search"):
    print(f"  Waiting for index '{name}' to be ready...", end="", flush=True)
    while True:
        indexes = list(collection.list_search_indexes(name))
        if indexes and indexes[0].get("status") == "READY":
            print(" ready.")
            break
        print(".", end="", flush=True)
        time.sleep(5)

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

try:
    collection.create_search_index(
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
        )
    )
    wait_for_index("quickstart_semantic", "vectorSearch")
except Exception as e:
    if "already exists" in str(e):
        print("  Index already exists, skipping creation.")
    else:
        print(f"  Note: {e}")

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

try:
    collection.create_search_index(
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
        )
    )
    wait_for_index("quickstart_text")
except Exception as e:
    if "already exists" in str(e):
        print("  Index already exists, skipping creation.")
    else:
        print(f"  Note: {e}")

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
print("To use your own data, update CONNECTION_STRING, DB_NAME,")
print("and COLLECTION_NAME at the top of this file.")

client.close()
