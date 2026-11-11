**N:** 3000000

**numUnindexed:** 1
**numIndexed:** 2
**numEntries:** 3

== FIELD VALUES ===============================================================

**SSN**
**v:** 11
**T:** 0
**Document Storage (bytes):** 103

**lastname**
**Query Type:** substring
**mlen:** 30
**lb:** 3
**ub:** 6
**v:** 20
**T formula:** T = 1 + (ub - lb + 1) * (2 * mlen + 2 - ub - lb) / 2
**T calculation:** T = 1 + (6 - 3 + 1) * (2 * 30 + 2 - 6 - 3) / 2
**T:** 107
**Document Storage (bytes):** 32926.8

**username**
**Query Type:** prefix and suffix
**lb_prefix:** 2
**ub_prefix:** 4
**lb_suffix:** 2
**ub_suffix:** 4
**v:** 10
**T formula:** T = 1 + (ub_prefix - lb_prefix + 1) + (ub_suffix - lb_suffix + 1)
**T calculation:** T = 1 + (4 - 2 + 1) + (4 - 2 + 1)
**T:** 7
**Document Storage (bytes):** 2307.6

== COLLECTION-LEVEL TOTALS ====================================================
**N:** 3000000
**T_Total:** 114
**Index Storage (bytes):** 9933.6
**Total Disk Storage (bytes):** 135813000000
**Memory (bytes):** 17835000000
