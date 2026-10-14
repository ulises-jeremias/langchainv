# MongoDB vector store

`mongodb.Store` stores documents in a MongoDB collection and implements the
shared `vectorstores.VectorStore` interface with cosine search.

The package does not bundle a MongoDB driver. The caller adapts a driver
collection to the narrow `MongoCollection` interface: insert documents, find
documents by filter, and delete documents by filter. Filters sent to the
collection use equality matches and `$in` lists only.

Each stored document carries a generated UUID in `id`, plus `namespace`,
`page_content`, `metadata`, and `embedding` fields. Searches scan at most
`max_scan_documents` documents in the namespace (default 10,000, at most
100,000), filter by scalar metadata equality, and rank by cosine score in
process. This is a bounded scan, not Atlas `$vectorSearch`: collections
larger than the scan bound need a server-side search adapter. Tests use an
in-memory fake collection and make no network calls.
