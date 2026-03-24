# mongodb-query-optimizer — Eval Cases

## Eval 1: Find with ESR / $in threshold nuance

**Prompt:**

How do I optimize this query? db.orders.find({ status: 'open', tags: { $in: \['urgent', 'priority', 'escalated'\] } }).sort({ createdAt: \-1 }).limit(50). The tags field usually has 3-5 values per document but the $in list could grow to much larger from a user filter.

**Expected output:** Recommends index { status: 1, tags: 1, createdAt: \-1 }, notes that $in with many elements is treated as a range scan rather than equality.

**Expectations:**

- Recommends a compound index covering status, tags, and createdAt  
- Mentions ESR ordering or explains equality-before-sort-before-range  
- Suggests that if the $in list stays small, { status: 1, tags: 1, createdAt: \-1 } works, but if it grows large the performance is likely to degrade

---

## Eval 2: Aggregation pipeline ($lookup \+ top-N sort)

**Prompt:**

This aggregation is slow. It joins orders to products and sums revenue per category. db.orders.aggregate(\[ { $match: { date: { $gte: ISODate('2025-01-01') } } }, { $lookup: { from: 'products', localField: 'productId', foreignField: 'sku', as: 'product' } }, { $unwind: '$product' }, { $group: { \_id: '$product.category', totalRevenue: { $sum: { $multiply: \['$quantity', '$unitPrice'\] } } } }, { $sort: { totalRevenue: \-1 } }, { $limit: 10 } \])

**Expected output:** Identifies that the $lookup foreignField 'sku' needs an index on the products collection. Notes that $sort \+ $limit together enable a top-N optimization. Suggests an index on orders.date for the initial $match.

**Expectations:**

- Identifies that products.sku needs an index for the $lookup to avoid collection scans on every joined document  
- Suggests an index on orders.date for the $match stage  
- Notes that $sort immediately followed by $limit enables top-N sort optimization (only tracks top N values rather than sorting full dataset)  
- Does not suggest adding a $project before $group to 'reduce fields' since MongoDB's optimizer handles field pruning automatically

---

## Eval 3: Update — replaceOne oplog optimization

**Prompt:**

We have a background job that syncs documents from an external system. It does db.coll.replaceOne({ \_id: doc.\_id }, doc) for each document. Most fields don’t change but we don’t know which fields do change. With 50K updates per hour things are getting slower. Any optimization ideas?

**Expected output:** Identifies that replaceOne writes the full document to the oplog. Recommends switching to updateOne with aggregation pipeline syntax ($replaceWith \+ $literal) to generate smaller oplog deltas when only a few fields change.

**Expectations:**

- Identifies that replaceOne generates large oplog entries because it writes the full document  
- Recommends updateOne with aggregation pipeline syntax using $replaceWith and $literal as the alternative  
- Explains that the update rather than replace lets MongoDB compute deltas, resulting in smaller oplog entries

---

## Eval 4: Covered query — missing \_id: 0 gotcha

**Prompt:**

I need a covered query for this access pattern: db.users.find({ status: 'active', plan: 'premium' }, { email: 1 }).sort({ email: 1 }). I created index { status: 1, plan: 1, email: 1 } but explain still shows totalDocsExamined \> 0\. What am I doing wrong?

**Expected output:** Identifies that the projection implicitly includes \_id (which is not in the index), so MongoDB must fetch documents. Fix is to add \_id: 0 to the projection.

**Expectations:**

- Identifies that \_id is included by default in projections and is not in the index  
- Recommends adding \_id: 0 to the projection to achieve a covered query  
- Notes that a covered query requires all returned fields to be in the index, and \_id is returned unless explicitly excluded

---

## Eval 5: Negative test — routine query writing (should NOT trigger skill)

**Prompt:**

Write me a MongoDB query to find all users with role 'admin' and return their name and email.

**Expected output:** The optimizer skill should NOT be invoked. This is routine query writing with no optimization or performance ask.

**Expectations:**

- The mongodb-query-optimizer skill is NOT invoked for this prompt  
- The response is a straightforward find query without unsolicited optimization advice