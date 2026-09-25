**N:** 3000000
**numUnindexed:** 1
**numIndexed:** 3
**numEntries:** 4

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
**T calculation:** 1 + (6 - 3 + 1) * (2 * 30 + 2 - 6 - 3) / 2 = 1 + 4 * 53 / 2 = 107
**T:** 107
**Document Storage (bytes):** 32912.40

**username**
**Query Type:** prefix
**lb:** 2
**ub:** 4
**v:** 10
**T formula:** T = 1 + (ub - lb + 1)
**T calculation:** 1 + (4 - 2 + 1) = 4
**T:** 4
**Document Storage (bytes):** 1375.20

**username**
**Query Type:** suffix
**lb:** 2
**ub:** 4
**v:** 10
**T formula:** T = 1 + (ub - lb + 1)
**T calculation:** 1 + (4 - 2 + 1) = 4
**T:** 4
**Document Storage (bytes):** 1375.20

== COLLECTION-LEVEL TOTALS ====================================================
**N:** 3000000
**T_Total:** 115
**Index Storage (bytes):** 10014
**Total Disk Storage (bytes):** 137339400000
**Memory (bytes):** 17991000000

