During peaks, I see error "the connection pool is in paused state for the server". Connections are ended and with connection count decreased by about 100. Then a peak of connections is received.

Config params:
- MaxConnectionPoolSize: 800
- MinConnectionPoolSize: 120
- MaxConnectionLifeTime: 5 hours
- MaxConnectionIdleTime: 32 hrs

Using 2 replicas, with 3 clusters each.