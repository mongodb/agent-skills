// Seed fixture: `seeded_sample` — authors/books/logins/orders (functional cases 38–40).
// Applied per-sample by solvers/seed_db.py, selected by a case's `seed: seeded_sample`.
// Each collection carries a definitive trap so a naive query returns WRONG data.
const sample = db.getSiblingDB('sample')

// Case 38: zero-preserving join. Cara has no books → naive group-by-author drops her.
sample.authors.drop()
sample.authors.insertMany([{ name: 'Ada' }, { name: 'Ben' }, { name: 'Cara' }])
sample.books.drop()
sample.books.insertMany([
  { title: 'B1', author: 'Ada' },
  { title: 'B2', author: 'Ada' },
  { title: 'B3', author: 'Ben' },
])

// Case 39: case-insensitive grouping. Naive group by raw `user` splits Alice/alice/ALICE.
sample.logins.drop()
sample.logins.insertMany([
  { user: 'Alice' },
  { user: 'alice' },
  { user: 'ALICE' },
  { user: 'Bob' },
  { user: 'bob' },
])

// Case 40: distinct customers, not order count. c1 orders books twice.
sample.orders.drop()
sample.orders.insertMany([
  { category: 'books', customer: 'c1' },
  { category: 'books', customer: 'c1' },
  { category: 'books', customer: 'c2' },
  { category: 'toys', customer: 'c3' },
])

print(
  'seeded authors=' +
    sample.authors.countDocuments() +
    ' books=' +
    sample.books.countDocuments() +
    ' logins=' +
    sample.logins.countDocuments() +
    ' orders=' +
    sample.orders.countDocuments(),
)
