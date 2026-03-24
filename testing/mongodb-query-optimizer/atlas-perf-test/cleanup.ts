/**
 * Drops the perftest database created by setup-slow-queries.ts.
 *
 * Usage:
 *   npm run cleanup <connection-string>
 */

import { MongoClient } from "mongodb";

const CONNECTION_STRING =
  process.argv[2] || process.env.MONGODB_URI || "";

if (!CONNECTION_STRING) {
  console.error("Usage: npm run cleanup <atlas-connection-string>");
  process.exit(1);
}

async function main() {
  const client = new MongoClient(CONNECTION_STRING);
  try {
    await client.connect();
    await client.db("perftest").dropDatabase();
    console.log("Dropped perftest database");
  } finally {
    await client.close();
  }
}

main().catch((err) => {
  console.error("Cleanup failed:", err);
  process.exit(1);
});
