**N:** 3000000
**numUnindexed:** 1
**numIndexed:** 3
**numEntries:** 4

== FIELD VALUES ===============================================================

**SSN**
**v:** 11
**T:** 0
**Document Storage (bytes):** 71 + ceil((11+6)/16) * 16 = 71 + 2 * 16 = 103

**lastname**
**Query Type:** substring
**mlen:** 30
**lb:** 3
**ub:** 6
**v:** 20
**T formula:** T = 1 + (ub - lb + 1) * (2 * mlen + 2 - ub - lb) / 2
**T calculation:** 1 + (6 - 3 + 1) * (2 * 30 + 2 - 6 - 3) / 2
**T:** 107
**Document Storage (bytes):** 1.2 * (255 * 107 + 110 + ceil((20 + 6) / 16) * 16) = 1.2 * (27285 + 110 + 32) = 32912.4

**username**
**Query Type:** prefix
**lb:** 2
**ub:** 4
**v:** 10
**T formula:** T = 1 + (ub - lb + 1)
**T calculation:** 1 + (4 - 2 + 1)
**T:** 4
**Document Storage (bytes):** 1.2 * (255 * 4 + 110 + ceil((10 + 6) / 16) * 16) = 1.2 * (1020 + 110 + 16) = 1375.2

**username**
**Query Type:** suffix
**lb:** 2
**ub:** 4
**v:** 10
**T formula:** T = 1 + (ub - lb + 1)
**T calculation:** 1 + (4 - 2 + 1)
**T:** 4
**Document Storage (bytes):** 1.2 * (255 * 4 + 110 + ceil((10 + 6) / 16) * 16) = 1.2 * (1020 + 110 + 16) = 1375.2

== COLLECTION-LEVEL TOTALS ====================================================
**N:** 3000000
**T_Total:** 115
**Index Storage (bytes):** 1.2 * (67 * 115 + 640) = 1.2 * 8345 = 10014
**Total Disk Storage (bytes):** 3000000 * (10014 + (103 + 32912.4 + 1375.2 + 1375.2)) = 3000000 * 45779.8 = 137339400000
**Memory (bytes):** 3000000 * (52 * 115 + 17) = 3000000 * 5997 = 17991000000
