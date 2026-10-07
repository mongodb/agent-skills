**N:** 3000000
**numUnindexed:** 2
**numIndexed:** 7
**numEntries:** 9

== FIELD VALUES ===============================================================

**ssn**
**Query Type:** equality
**v:** 11
**T:** 1
**Document Storage (bytes):** 490.8

**name**
**Query Type:** prefix and suffix
**lb_prefix:** 2
**ub_prefix:** 10
**lb_suffix:** 2
**ub_suffix:** 10
**v:** 20
**T formula:** T = 1 + (ub_prefix - lb_prefix + 1) + (ub_suffix - lb_suffix + 1)
**T calculation:** T = 1 + (10 - 2 + 1) + (10 - 2 + 1)
**T:** 19
**Document Storage (bytes):** 5998.8

**username**
**Query Type:** prefix
**lb:** 3
**ub:** 6
**v:** 10
**T formula:** T = 1 + (ub - lb + 1)
**T calculation:** T = 1 + (6 - 3 + 1)
**T:** 5
**Document Storage (bytes):** 1695.6

**bio**
**Query Type:** substring
**mlen:** 50
**lb:** 3
**ub:** 6
**v:** 200
**T formula:** T = 1 + (ub - lb + 1) * (2 * mlen + 2 - ub - lb) / 2
**T calculation:** T = 1 + (6 - 3 + 1) * (2 * 50 + 2 - 6 - 3) / 2
**T:** 187
**Document Storage (bytes):** 57618

**userId**
**Query Type:** equality
**v:** 8
**T:** 1
**Document Storage (bytes):** 471.6

**balance**
**Query Type:** range
**T:** 0
**Document Storage (bytes):** 0

**birthdate**
**Query Type:** range
**T:** 0
**Document Storage (bytes):** 0

**profile**
**v:** 500
**T:** 0
**Document Storage (bytes):** 583

**idScan**
**v:** 20000
**T:** 0
**Document Storage (bytes):** 20087

== COLLECTION-LEVEL TOTALS ====================================================
**N:** 3000000
**T_Total:** 213
**Index Storage (bytes):** 17893.2
**Total Disk Storage (bytes):** 314514000000
**Memory (bytes):** 33279000000
