// Script to load test fixtures into MongoDB for skill evaluation

import { MongoClient, ObjectId } from 'mongodb';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const FIXTURES_DIR = path.join(__dirname, 'fixtures');

// Import fixture files (we'll need to parse them since they're TypeScript)

// Helper to convert fixture format to MongoDB documents
function parseFixture(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  // Remove the export default and extract the array
  const jsonStr = content
    .replace(/export default\s+/, '')
    .replace(/\$oid:\s*'([^']+)'/g, '"$1"') // Convert $oid format
    .replace(/ObjectId\(/g, '')
    .replace(/\)/g, '')
    .replace(/,\s*\]/g, ']') // Remove trailing commas
    .replace(/,\s*\}/g, '}');

  try {
    const docs = eval('(' + jsonStr + ')');
    // Convert _id fields with $oid to ObjectId
    return docs.map(doc => {
      if (doc._id && typeof doc._id === 'object' && doc._id.$oid) {
        doc._id = new ObjectId(doc._id.$oid);
      }
      return doc;
    });
  } catch (e) {
    console.error(`Error parsing ${filePath}:`, e.message);
    return [];
  }
}

async function loadFixtures(connectionString) {
  const client = new MongoClient(connectionString);

  try {
    await client.connect();
    console.log('Connected to MongoDB');

    const fixtures = [
      { namespace: 'netflix.movies', file: 'netflix.movies.ts' },
      { namespace: 'netflix.comments', file: 'netflix.comments.ts' },
      { namespace: 'airbnb.listingsAndReviews', file: 'airbnb.listingsAndReviews.ts' },
      { namespace: 'berlin.cocktailbars', file: 'berlin.cocktailbars.ts' },
      { namespace: 'nyc.parking', file: 'nyc.parking.ts' },
    ];

    for (const { namespace, file } of fixtures) {
      const [dbName, collName] = namespace.split('.');
      const filePath = path.join(FIXTURES_DIR, file);

      console.log(`Loading ${namespace}...`);

      const docs = parseFixture(filePath);
      if (docs.length === 0) {
        console.log(`  No documents found in ${file}`);
        continue;
      }

      const db = client.db(dbName);
      const collection = db.collection(collName);

      // Drop existing collection
      try {
        await collection.drop();
      } catch (e) {
        // Collection might not exist
      }

      // Insert documents
      await collection.insertMany(docs);
      console.log(`  Inserted ${docs.length} documents into ${namespace}`);
    }

    console.log('All fixtures loaded successfully!');
  } catch (error) {
    console.error('Error loading fixtures:', error);
    throw error;
  } finally {
    await client.close();
  }
}

// Get connection string from command line or use default
const connectionString = process.argv[2] || 'mongodb://localhost:27017';
loadFixtures(connectionString);
