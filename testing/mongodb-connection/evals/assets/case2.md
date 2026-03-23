Experiencing intermittent connection issues.

```log
MongoNetworkError: Client network socket disconnected before secure TLS connection was established
  ...
  cause: Error: Client network socket disconnected before secure TLS connection was established
    code: 'ECONNRESET',
  ...
```

- there are spikes of connection counts multiple times
- the connection counts stops at 3000 (server's connection limit)
- using a connection per Lambda instance. As long as the Lambda function is alive, it will reuse the established DB connection
- maximum of 60 Lambda instances active at a time

Environment:

    - Node.js
    - AWS Lambda 
    - M20, 3-member replica set

Connection logic used (extract):

```js
mongoose.Promise = global.Promise;
let isConnected;

export const connectToDatabase = () => {
  if (isConnected) {
    return Promise.resolve();
  }

  mongoose.set("strictQuery", true);
  return mongoose
    .connect(MONGO_URI, { maxIdleTimeMS: 60000 })
    .then((db) => {
      isConnected = db.connections[0].readyState;
    })
};
```