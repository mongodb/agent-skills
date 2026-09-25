# QE Sizing Calculations

**N:** 3000000

**numUnindexed:** 2
**numIndexed:** 7
**numEntries:** 9

== FIELD VALUES ===============================================================

**ssn**
**Query Type:** equality
**v:** 11
**T:** 1
**Document Storage (bytes):** 1.2 * (255 * 1 + 110 + ceil((11 + 6) / 16) * 16) = 1.2 * (255 + 110 + 32) = 1.2 * 397 = 476.4

**name**
**Query Type:** prefix
**lb:** 2
**ub:** 10
**v:** 20
**T formula:** T = 1 + (ub - lb + 1)
**T calculation:** 1 + (10 - 2 + 1)
**T:** 10
**Document Storage (bytes):** 1.2 * (255 * 10 + 110 + ceil((20 + 6) / 16) * 16) = 1.2 * (2550 + 110 + 32) = 1.2 * 2692 = 3230.4

**name**
**Query Type:** suffix
**lb:** 2
**ub:** 10
**v:** 20
**T formula:** T = 1 + (ub - lb + 1)
**T calculation:** 1 + (10 - 2 + 1)
**T:** 10
**Document Storage (bytes):** 1.2 * (255 * 10 + 110 + ceil((20 + 6) / 16) * 16) = 1.2 * (2550 + 110 + 32) = 1.2 * 2692 = 3230.4

**bio**
**Query Type:** substring
**mlen:** 50
**lb:** 3
**ub:** 6
**v:** 200
**T formula:** T = 1 + (ub - lb + 1) * (2 * mlen + 2 - ub - lb) / 2
**T calculation:** 1 + (6 - 3 + 1) * (2 * 50 + 2 - 6 - 3) / 2 = 1 + 4 * 93 / 2
**T:** 187
**Document Storage (bytes):** 1.2 * (255 * 187 + 110 + ceil((200 + 6) / 16) * 16) = 1.2 * (47685 + 110 + 208) = 1.2 * 48003 = 57603.6

**userId**
**Query Type:** equality
**v:** 8
**T:** 1
**Document Storage (bytes):** 1.2 * (255 * 1 + 110 + ceil((8 + 6) / 16) * 16) = 1.2 * (255 + 110 + 16) = 1.2 * 381 = 457.2

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
**Document Storage (bytes):** 71 + ceil((500 + 6) / 16) * 16 = 71 + 512 = 583

**idScan**
**v:** 20000
**T:** 0
**Document Storage (bytes):** 71 + ceil((20000 + 6) / 16) * 16 = 71 + 20016 = 20087

== COLLECTION-LEVEL TOTALS ====================================================
**N:** 3000000
**T_Total:** 209
**Index Storage (bytes):** 1.2 * (67 * 209 + 640) = 1.2 * 14643 = 17571.6
**Total Disk Storage (bytes):** 3000000 * (17571.6 + 85668) = 3000000 * 103239.6 = 309718800000
**Memory (bytes):** 3000000 * (52 * 209 + 17) = 3000000 * 10885 = 32655000000
