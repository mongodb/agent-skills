// TypeScript script to load test fixtures into MongoDB

import { MongoClient, ObjectId } from 'mongodb';
import airbnbListings from './fixtures/airbnb.listingsAndReviews';
import berlinBars from './fixtures/berlin.cocktailbars';
import netflixMovies from './fixtures/netflix.movies';
import netflixComments from './fixtures/netflix.comments';
import nycParking from './fixtures/nyc.parking';

async function loadFixtures(connectionString: string) {
  const client = new MongoClient(connectionString);

  try {
    await client.connect();
    console.log('Connected to MongoDB');

    const fixtures = [
      { namespace: 'netflix.movies', data: netflixMovies },
      { namespace: 'netflix.comments', data: netflixComments },
      { namespace: 'airbnb.listingsAndReviews', data: airbnbListings },
      { namespace: 'berlin.cocktailbars', data: berlinBars },
      { namespace: 'nyc.parking', data: nycParking },
    ];

    for (const { namespace, data } of fixtures) {
      const [dbName, collName] = namespace.split('.');

      console.log(`Loading ${namespace}...`);

      // Convert _id fields with $oid to ObjectId
      const docs = data.map((doc: any) => {
        if (doc._id && typeof doc._id === 'object' && doc._id.$oid) {
          return { ...doc, _id: new ObjectId(doc._id.$oid) };
        }
        return doc;
      });

      const db = client.db(dbName);
      const collection = db.collection(collName);

      // Drop existing collection
      try {
        await collection.drop();
        console.log(`  Dropped existing ${namespace}`);
      } catch (e) {
        // Collection might not exist
      }

      // Insert documents
      if (docs.length > 0) {
        await collection.insertMany(docs);
        console.log(`  Inserted ${docs.length} documents into ${namespace}`);
      }
    }

    console.log('\\nAll fixtures loaded successfully!');
    console.log('\\nTest databases created:');
    console.log('  - netflix (movies, comments)');
    console.log('  - airbnb (listingsAndReviews)');
    console.log('  - berlin (cocktailbars)');
    console.log('  - nyc (parking)');
  } catch (error) {
    console.error('Error loading fixtures:', error);
    throw error;
  } finally {
    await client.close();
  }
}

// Get connection string from command line or environment variable
const connectionString = process.argv[2] || process.env.MONGODB_URI || 'mongodb://localhost:27017';
loadFixtures(connectionString);
