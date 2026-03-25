/**
 * Inserts test data into an Atlas replica set cluster and runs queries that
 * produce COLLSCANs and in-memory sorts. The goal is to populate the Atlas
 * slow query log and trigger Performance Advisor index suggestions.
 *
 * Usage:
 *   npm run setup <connection-string>
 *   npm run setup mongodb+srv://user:pass@cluster.mongodb.net/
 */

import { MongoClient, ObjectId } from "mongodb";

const CONNECTION_STRING =
  process.argv[2] || process.env.MONGODB_URI || "";

if (!CONNECTION_STRING) {
  console.error(
    "Usage: npm run setup <atlas-connection-string>\n" +
      "  e.g. npm run setup mongodb+srv://user:pass@cluster0.abc12.mongodb.net/"
  );
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const REGIONS = ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"];
const STATUSES = ["pending", "processing", "shipped", "delivered", "cancelled"];
const CATEGORIES = ["electronics", "clothing", "home", "books", "sports", "toys"];
const FIRST_NAMES = [
  "Alice", "Bob", "Carol", "David", "Eva", "Frank", "Grace", "Hector",
  "Iris", "Jack", "Karen", "Leo", "Mia", "Noah", "Olivia", "Paul",
];
const LAST_NAMES = [
  "Chen", "Garcia", "Kim", "Müller", "Patel", "Rossi", "Smith", "Tanaka",
  "Williams", "Zhang", "Johnson", "Brown", "Wilson", "Taylor", "Davis", "Lee",
];

let _seed = 42;
function rand(): number {
  // Simple LCG — deterministic so re-runs produce the same data.
  _seed = (_seed * 1664525 + 1013904223) & 0x7fffffff;
  return _seed / 0x7fffffff;
}
function pick<T>(arr: T[]): T {
  return arr[Math.floor(rand() * arr.length)];
}
function randInt(min: number, max: number): number {
  return Math.floor(rand() * (max - min + 1)) + min;
}
function randomDate(startYear: number, endYear: number): Date {
  const start = new Date(startYear, 0, 1).getTime();
  const end = new Date(endYear, 11, 31).getTime();
  return new Date(start + rand() * (end - start));
}
function randomEmail(first: string, last: string): string {
  return `${first.toLowerCase()}.${last.toLowerCase()}${randInt(1, 999)}@example.com`;
}

// ---------------------------------------------------------------------------
// Data generation
// ---------------------------------------------------------------------------

interface Customer {
  _id: ObjectId;
  firstName: string;
  lastName: string;
  email: string;
  region: string;
  signupDate: Date;
  tier: string;
}

interface OrderItem {
  sku: string;
  category: string;
  name: string;
  quantity: number;
  unitPrice: number;
}

interface Order {
  customerId: ObjectId;
  status: string;
  region: string;
  createdAt: Date;
  updatedAt: Date;
  total: number;
  items: OrderItem[];
  shippingAddress: {
    street: string;
    city: string;
    zip: string;
    country: string;
  };
}

function generateCustomers(count: number): Customer[] {
  const customers: Customer[] = [];
  for (let i = 0; i < count; i++) {
    const first = pick(FIRST_NAMES);
    const last = pick(LAST_NAMES);
    customers.push({
      _id: new ObjectId(),
      firstName: first,
      lastName: last,
      email: randomEmail(first, last),
      region: pick(REGIONS),
      signupDate: randomDate(2020, 2025),
      tier: pick(["free", "standard", "premium"]),
    });
  }
  return customers;
}

function generateOrders(customers: Customer[], count: number): Order[] {
  const orders: Order[] = [];
  for (let i = 0; i < count; i++) {
    const customer = pick(customers);
    const numItems = randInt(1, 5);
    const items: OrderItem[] = [];
    let total = 0;
    for (let j = 0; j < numItems; j++) {
      const qty = randInt(1, 4);
      const price = randInt(5, 200);
      total += qty * price;
      items.push({
        sku: `SKU-${randInt(1000, 9999)}`,
        category: pick(CATEGORIES),
        name: `Product ${randInt(1, 500)}`,
        quantity: qty,
        unitPrice: price,
      });
    }
    const created = randomDate(2024, 2026);
    orders.push({
      customerId: customer._id,
      status: pick(STATUSES),
      region: customer.region,
      createdAt: created,
      updatedAt: new Date(created.getTime() + randInt(0, 7 * 86400000)),
      total,
      items,
      shippingAddress: {
        street: `${randInt(1, 9999)} ${pick(["Main", "Oak", "Pine", "Elm", "Cedar"])} St`,
        city: pick(["New York", "London", "Berlin", "Tokyo", "Sydney"]),
        zip: `${randInt(10000, 99999)}`,
        country: pick(["US", "UK", "DE", "JP", "AU"]),
      },
    });
  }
  return orders;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const client = new MongoClient(CONNECTION_STRING);
  try {
    await client.connect();
    console.log("Connected to Atlas cluster");

    const db = client.db("perftest");

    // ------------------------------------------------------------------
    // 1. Drop existing collections
    // ------------------------------------------------------------------
    for (const name of ["orders", "customers"]) {
      try {
        await db.collection(name).drop();
        console.log(`  Dropped perftest.${name}`);
      } catch {
        // collection may not exist
      }
    }

    // ------------------------------------------------------------------
    // 2. Insert test data (NO indexes — everything will COLLSCAN)
    // ------------------------------------------------------------------
    const NUM_CUSTOMERS = 50_000;
    const NUM_ORDERS = 500_000;

    console.log(`\nGenerating ${NUM_CUSTOMERS} customers...`);
    const customers = generateCustomers(NUM_CUSTOMERS);
    await db.collection("customers").insertMany(customers);
    console.log(`  Inserted ${customers.length} customers`);

    console.log(`Generating ${NUM_ORDERS} orders...`);
    const orders = generateOrders(customers, NUM_ORDERS);
    // Insert in batches of 2000
    for (let i = 0; i < orders.length; i += 2000) {
      await db.collection("orders").insertMany(orders.slice(i, i + 2000));
    }
    console.log(`  Inserted ${orders.length} orders`);

    // ------------------------------------------------------------------
    // 3. Run slow queries for ~30 seconds
    //    These are deliberately unindexed to produce COLLSCANs.
    // ------------------------------------------------------------------
    console.log("\nRunning slow queries for ~30 seconds...");
    console.log("  (These are intentionally unindexed to generate COLLSCAN entries)");

    const coll = db.collection("orders");
    const startTime = Date.now();
    const durationMs = 30_000;
    let queryCount = 0;

    while (Date.now() - startTime < durationMs) {
      // Query 1: Filter on status + region with sort on createdAt (COLLSCAN + in-memory sort)
      // Should trigger index suggestion: { status: 1, region: 1, createdAt: -1 }
      const status = pick(STATUSES);
      const region = pick(REGIONS);
      await coll
        .find({ status, region })
        .sort({ createdAt: -1 })
        .limit(20)
        .toArray();
      queryCount++;

      // Query 2: Filter on customerId (COLLSCAN)
      // Should trigger index suggestion: { customerId: 1 }
      const customer = pick(customers);
      await coll.find({ customerId: customer._id }).toArray();
      queryCount++;

      // Query 3: $facet aggregation that sends ALL docs through every branch
      // This is slow because $facet funnels the entire collection into each branch,
      // even though the "recentHighValue" branch only needs a tiny subset.
      // Skill should recommend replacing $facet with $unionWith so each branch
      // can optimize independently (and use indexes).
      await coll
        .aggregate([
          {
            $facet: {
              recentHighValue: [
                {
                  $match: {
                    total: { $gte: 500 },
                    createdAt: { $gte: new Date("2025-06-01") },
                  },
                },
                { $sort: { total: -1 } },
                { $limit: 10 },
              ],
              statusBreakdown: [
                {
                  $group: {
                    _id: "$status",
                    count: { $sum: 1 },
                    avgTotal: { $avg: "$total" },
                  },
                },
                { $sort: { count: -1 } },
              ],
              categoryRevenue: [
                { $unwind: "$items" },
                {
                  $group: {
                    _id: "$items.category",
                    totalRevenue: {
                      $sum: { $multiply: ["$items.quantity", "$items.unitPrice"] },
                    },
                    orderCount: { $sum: 1 },
                  },
                },
                { $sort: { totalRevenue: -1 } },
              ],
            },
          },
        ])
        .toArray();
      queryCount++;

      // Brief pause to avoid overwhelming the cluster
      await new Promise((r) => setTimeout(r, 100));
    }

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`  Executed ${queryCount} slow queries in ${elapsed}s`);

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    console.log("\n--- Setup complete ---");
    console.log("Database:    perftest");
    console.log(`Collections: orders (${NUM_ORDERS} docs), customers (${NUM_CUSTOMERS} docs)`);
    console.log("Indexes:     _id only (no secondary indexes)");
    console.log("\nExpected slow query patterns:");
    console.log("  1. find({ status, region }).sort({ createdAt: -1 })  →  COLLSCAN + in-memory SORT");
    console.log("  2. find({ customerId })                              →  COLLSCAN");
    console.log("  3. aggregate([$facet: { recentHighValue, statusBreakdown }])  →  full collection funneled into every branch");
    console.log("\nExpected Performance Advisor suggestions (after a few minutes):");
    console.log("  - { status: 1, region: 1, createdAt: -1 }  on perftest.orders");
    console.log("  - { customerId: 1 }                        on perftest.orders");
    console.log("  - $facet aggregation: replace with $unionWith so branches optimize independently");
    console.log("\nNote: Performance Advisor suggestions may take 5-15 minutes to appear in Atlas.");
  } finally {
    await client.close();
  }
}

main().catch((err) => {
  console.error("Setup failed:", err);
  process.exit(1);
});
