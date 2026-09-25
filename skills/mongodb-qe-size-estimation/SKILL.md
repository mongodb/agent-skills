---
name: mongodb-qe-size-estimation
license: Apache-2.0
metadata:
  version: "1.0.0"
description: >
  Estimates the storage and memory impact of encrypting fields in collections with Queryable Encryption (QE) enabled. 
  Do NOT use for collections that use Client-Side Field Level Encryption (CSFLE) instead of QE.
---

# mongodb-qe-size-estimation

## General Instructions

- **CRITICAL: Never ask for or accept sample data.** QE is an encryption feature, meant to secure sensitive information. Do not request sample data, and if provided, reject it for security reasons. Inform the user that you can't accept sample documents, though you can take an encryption schema as an input to see which fields are encrypted, which allow queries, and what those query settings are.
- **IMPORTANT: Validation constraints and value limits are current as of MongoDB 9.0** They don't apply to previous versions.
- Any parenthetical in the form (LLM Note: <content>) is for LLM use. Don't save it to qe-sizing-calculations.md or mention it to the user.
- This skill currently has no calculations for range queries, so it accepts "range" as a valid query type, but uses 0 for estimated values.


### Definitions

- **field** For the purposes of this skill, "field" refers to an encrypted field in a MongoDB document, in a QE-enabled collection.
- **entry** For an unindexed field, the field name. For a field with one or more query types enabled, the combination of the field name and one of its enabled query types. This skill calculates sizing impact per entry, so a field with both prefix and suffix queries enabled has two entries.
- **unindexed** Describes the state of a field with no query types enabled, indicated by the absence of a "queries" key if using an encryption schema.


### Validation

Validate the user's inputs, whether manual or via an encryption schema, against the following:

  An encrypted field may be "unindexed" meaning it has no query types enabled. Fields of BSON type object or array *only* support unindexed encryption, though other BSON types can also be unindexed. Otherwise, allowed query types based on a field's BSON type are:

  - string fields: "equality", "prefix", "suffix", "substring", or both "prefix" and "suffix". This is the only permitted case where one field has more than one query type.
  - int/long/date fields: "equality", "range"
  - decimal/double fields: "range"

  No other BSON type + query type combinations are permitted. "queries" may be an array of two objects if a string field has both prefix and suffix queries enabled. 

If the user's input violates any of the preceding rules, reject it. If a user doesn't specify BSON type, only check that each field either has no query types enabled, exactly one valid query type, or exactly two (prefix and suffix). Enumerate validation failures, list allowed combinations, and don't proceed until the user provides valid input.


# Steps

## 1. Prepare the Working Directory

Create a qe-sizing-calculations.md file in a temporary directory. If working in a repository, check gitignore to see if there are existing directories you should use. If no ignored scratch directory exists, use the OS temp directory ($TMPDIR, or /tmp if unset). If a qe-sizing-calculations.md file already exists at that location, inform the user and ask for confirmation to delete it and create a new one for the new set of calculations.

## 2. State Purpose and Request Input Preference

State: This agent skill estimates the storage impact of enabling Queryable Encryption on a collection. Values are saved to the <path to qe-sizing-calculations.md> file if you want to verify the calculations or see per-field numbers. Do you want to provide field information manually, or use an encryption schema file?

If the user opts for an encryption schema, request it as either pasted content or a file path, and expect JSON format. Validate the schema against this skill's "Validation" section. If the schema is valid but includes fields with "range" queries enabled, inform the user that no calculations are available for those fields, so their impact is estimated as 0.

## 3. Get the Number of Documents

Ask the user how many documents in the collection have encrypted fields. If they don't know, a safe default is the total number of documents in the collection. Save this value to qe-sizing-calculations.md as:

**N:** <value>

## 4. Get the Number of Entries

- If the user chose manual input, ask: How many fields are you encrypting without enabling queries?
- If the user chose encryption schema, count the number of encrypted fields without queries enabled.

Save this value to qe-sizing-calculations.md as:

**numUnindexed:** <number of unindexed encrypted fields>

- If the user chose manual input, ask: How many encrypted fields have queries enabled?
- If the user chose encryption schema, count the number of fields with queries enabled. If "queries" includes both "prefix" and "suffix", count it twice towards the total.

Save this value to qe-sizing-calculations.md as:

**numIndexed:** <number of queries enabled>

Save the sum of numUnindexed and numIndexed to qe-sizing-calculations.md as:

**numEntries:** <sum of numUnindexed and numIndexed>

## 5. Get Inputs Per Field

Write a heading line to qe-sizing-calculations.md:

== FIELD VALUES ===============================================================

As you get information, write it to qe-sizing-calculations.md in the following format, omitting any lines that don't apply. For unindexed fields, this means omitting the Query Type.

**<Field Name>** <the name provided by the user, or the dot notation "path" value if taken from the encryption schema>
**Query Type:** <equality, range, prefix, suffix, or substring>
**mlen:** <include if Query Type is substring. Integer from 2-50, inclusive>
**lb:** <include if Query Type is prefix, suffix, or substring. Integer 1+ for prefix and suffix queries, or 2+ for substring queries>
**ub:** <include if Query Type is prefix, suffix, or substring. Integer 1+ for prefix and suffix queries, or 2-6 for substring queries>
**v:** <omit if Query Type is range, otherwise include. integer, representing the average byte length of the unencrypted values for the field>

- If the user provided an encryption schema, do this once:
  - Add one entry to qe-sizing-calculations.md for each unindexed field, omitting the "Query Type" line.
  - Add one entry per query type enabled on each field. Map the keys in each "queries" object to field values as follows, omitting all keys that aren't listed:
    - strMaxLength (substring only) -> mlen
    - strMinQueryLength -> lb
    - strMaxQueryLength -> ub

- If the user didn't provide an encryption schema, do this per field:
  - Only validate BSON types against allowed query types if the user provides a field's BSON type. Otherwise, don't ask for or validate field BSON types.
  - Ask for the field name and whether it's unindexed or has a query type enabled (LLM Note: If it has a query type, valid options are: "equality", "range", "prefix", "suffix", "substring", or both prefix and suffix. Reject other values or combinations. If the user specifies "range", warn them that no formula is available for calculating it)
    - (LLM Note:If the user specifies both prefix and suffix for the same field, increment numIndexed and numEntries in qe-sizing-calculations.md, and create two entries with the same field name but different Query Types).
  - Validate the inputs.

Do this per field:

  Check the list below, and ask the user for the values that aren't already populated. Write all values to the qe-sizing-calculations.md file.

  **mlen:** (LLM Note: only include if no schema provided, and Query Type is substring) Max Length, the maximum allowable length of the string.
  **lb:** (LLM Note: only include if no schema provided, and Query Type is prefix, suffix, or substring) Lower Bound, the minimum searchable characters.
  **ub:** (LLM Note: only include if no schema provided, and Query Type is prefix, suffix, or substring) Upper Bound, the maximum searchable characters.
  **v:** (LLM Note: skip if Query Type is range, otherwise needed once per field. If a field has both prefix and suffix queries enabled, only ask for v once and use the same value for both entries) Average byte length of the unencrypted values for the field. If the user is uncertain, suggest 20 as a default.

  Validate values against the formatting snippet at the start of this step. Validate that lb ≤ ub ≤ mlen (if present). If a value falls outside allowable bounds, reject it and inform the user. Do not proceed without a valid value.

Repeat until you have populated the full number of entries, numEntries, in qe-sizing-calculations.md.

## 6. Add Formulas and Results to qe-sizing-calculations.md

This step populates calculation information to file, including intermediate steps.

For every entry in qe-sizing-calculations.md:

1. Add the following to each entry in qe-sizing-calculations.md. It is critical that you copy formula templates exactly to avoid cascading issues. When running calculations, defer to available mathematical parsing tools and ensure correct order of operations.

  - For fields with no Query Type:

    **T:** 0
    **Document Storage (bytes):** <run the calculation: 71 + ceil((v+6)/16) * 16>

  - For fields with a Query Type of equality:

    **T:** 1
    **Document Storage (bytes):** <run the calculation: 1.2 * (255 * T + 110 + ceil((v + 6) / 16) * 16)>

  - For fields with a Query Type of range, there is currently no formula, so record an entry with values of 0:

    **T:** 0
    **Document Storage (bytes):** 0

  - For fields with a Query Type of prefix or suffix:

    **T formula:** T = 1 + (ub - lb + 1)
    **T calculation:** <formula template with all placeholders populated by the field's values>
    **T:** <run the calculation in "T calculation" and write the result here>
    **Document Storage (bytes):** <run the calculation: 1.2 * (255 * T + 110 + ceil((v + 6) / 16) * 16)>

  - For fields with a Query Type of substring:

    **T formula:** T = 1 + (ub - lb + 1) * (2 * mlen + 2 - ub - lb) / 2
    **T calculation:** <formula template with all placeholders populated by the field's values>
    **T:** <run the calculation in "T calculation" and write the result here>
    **Document Storage (bytes):** <run the calculation: 1.2 * (255 * T + 110 + ceil((v + 6) / 16) * 16)>

2. Do a silent audit pass to verify the entries you just added use the correct T formula or static value, and use the correct values for the T calculation, then proceed.

## 7. Calculate Index Storage, Total Disk Storage, and Memory

These values are collection-level and calculated as totals across all entries. For fields with both prefix and suffix entries, they all count towards the total.

At the end of the qe-sizing-calculations.md file, silently write the following lines:

== COLLECTION-LEVEL TOTALS ====================================================
**N:** <move the N value from the top of the file down to here, for easier reading>
**T_Total:** <the sum of all T values.>
**Index Storage (bytes):** <run the calculation: 1.2 * (67 * T_Total + 640)>
**Total Disk Storage (bytes):** <run the calculation: N * (Index Storage + (the sum of all Document Storage values))>
**Memory (bytes):** <run the calculation: N * (52 * T_Total + 17)>

## 8. Sum Total Results and Report Conclusions

Output the following, and include the units:

**Total Disk Storage Impact:** <the Total Disk Storage value from qe-sizing-calculations.md, converted to decimal GB (1000³ bytes) >
**Required Memory:** <the Memory value from qe-sizing-calculations.md, converted to binary GiB (1024³ bytes)>
**Fields by Impact (descending):** <sort all fields in qe-sizing-calculations.md by T, descending, then list them as: Name (<either the Query Type, or unindexed>): T>

If the encryption schema or manual inputs included fields with range queries enabled, list those fields and remind the user that their impact wasn't calculated.

## 9. Interpret Results

Present advice. Don't provide any advice the user has explicitly rejected, such as suggesting different query types if they insist a field needs to allow substring queries. Only raise problems, don't mention something if it passes all checks.

- (LLM Note: Only run this check if the number of fields with substring queries enabled is greater than floor(50m/N). Defer to available mathematical parsing tools to ensure correct calculation) Tell the user to the number of substring queryable fields to no more than: floor(50 million/<documents in collection>). Tell them not to use substring queries on collections of more than 50 million documents.
- (LLM Note: Only run this check if one or more substring queryable fields are present) Check if substring-indexed fields might be suitable for prefix or suffix queries instead, and suggest that to the user. For example, queries against encrypted "name" fields can often use prefix instead of substring, though this admittedly presents drawbacks for cases like hyphenated surnames.
- (LLM Note: Only make these suggestions if they apply to the user's inputs, and if the changes don't make the modified value go outside its allowed limits) Tell the user to consider raising lb, lowering ub, or lowering mlen values.

Also inform the user of the path to the qe-sizing-calculations.md file, and ask if they want to review the data, or delete the temporary file. Remind them that the temporary file contains the names of encrypted fields and their average plaintext lengths, and should be deleted once finished.