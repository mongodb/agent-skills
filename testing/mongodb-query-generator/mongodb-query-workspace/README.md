# MongoDB Query Skill Testing Workspace

This workspace contains test fixtures, evaluation cases, and scripts for testing the mongodb-query skill.

## Directory Structure

```
mongodb-query-generator/mongodb-query-workspace/
├── fixtures/              # Test data fixtures (copied from Compass)
│   ├── airbnb.listingsAndReviews.ts
│   ├── berlin.cocktailbars.ts
│   ├── netflix.comments.ts
│   ├── netflix.movies.ts
│   └── nyc.parking.ts
├── iteration-1/           # Test results for iteration 1
│   ├── simple-find/
│   ├── find-with-filter-projection-sort-limit/
│   └── ...
├── load-fixtures.ts       # Script to load fixtures into MongoDB
└── README.md             # This file
```

## Setup

### 1. Install Dependencies

```bash
npm install
```

This installs:
- `mongodb` - MongoDB Node.js driver
- `bson` - BSON library for ObjectId handling
- `tsx` - TypeScript executor
- `@types/node` - Node.js type definitions

### 2. Load Test Fixtures

The test fixtures need to be loaded into your MongoDB instance before running tests.

**Quick start (using your Atlas cluster):**

```bash
npm run load-fixtures mongodb+srv://<username>:<password>@<cluster>.mongodb.net/
```

**Using a local MongoDB instance:**

```bash
# Start MongoDB locally (if not already running)
mongod --dbpath /path/to/data

# Load fixtures
npm run load-fixtures mongodb://localhost:27017
```

**Using Atlas Local (Docker):**

```bash
# Ensure Docker is running
# Create Atlas Local deployment
npx mongodb-mcp-server@latest atlas-local-create-deployment --deploymentName skill-tests

# Load fixtures
npm run load-fixtures mongodb://localhost:27017
```

### 3. Configure MCP Server

The mongodb-query skill requires the MongoDB MCP server to be configured. Update your `.mcp.json`:

```json
{
  "mcpServers": {
    "mongodb": {
      "command": "npx",
      "args": ["-y", "mongodb-mcp-server@latest"],
      "env": {
        "MDB_MCP_CONNECTION_STRING": "your-connection-string-here"
      }
    }
  }
}
```

## Test Data

The fixtures contain sample documents for testing various query scenarios:

- **netflix.movies** (9 docs) - Movie data with title, year fields
- **netflix.comments** (multiple docs) - Comments with movie_id references
- **airbnb.listingsAndReviews** - Listing data with geolocation, amenities, pricing
- **berlin.cocktailbars** - Bar data with geolocation
- **nyc.parking** - Parking violation data

## Running Tests

Tests are organized by iteration. Each test case has:
- `eval_metadata.json` - Test description and assertions
- `with_skill/outputs/` - Results when using the skill
- `without_skill/outputs/` - Baseline results without the skill

### Evaluation Cases

1. **simple-find** - Basic filter query
2. **find-with-filter-projection-sort-limit** - Complex find with text search
3. **geo-based-find** - Geospatial query
4. **find-translates-to-agg-mode-count** - Aggregation for mode calculation
5. **relative-date-find-last-year** - Relative date handling
6. **find-with-non-english** - Non-English prompt (Spanish)
7. **agg-complex-regex-split** - Complex text processing
8. **agg-join-lookup** - Collection joins with $lookup

## Cleaning Up

To remove test databases after testing:

```bash
# Connect to your MongoDB instance
mongosh "your-connection-string"

# Drop test databases
use netflix
db.dropDatabase()

use airbnb
db.dropDatabase()

use berlin
db.dropDatabase()

use nyc
db.dropDatabase()
```

## Notes

- The fixture files are in TypeScript format and are imported directly by `load-fixtures.ts`
- ObjectId fields are automatically converted during loading
- Test data is intentionally small to keep tests fast
- Fixtures are copied from the Compass repository for portability
