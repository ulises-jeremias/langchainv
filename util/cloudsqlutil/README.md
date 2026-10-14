# Cloud SQL connection helpers

`cloudsqlutil` validates Cloud SQL instance settings and builds the strings a
caller needs to open a PostgreSQL connection: the instance connection name
(`project:region:cluster:instance`) and a percent-encoded PostgreSQL DSN
through a caller supplied host and port.

Google's connector and IAM token exchange are not bundled. Run the Cloud SQL
Auth Proxy or resolve a private endpoint yourself, pass its host and port to
`postgres_dsn`, and feed the DSN to the existing `tools/sqldatabase`,
`memory/sqlhistory`, or pgvector adapters. An empty password omits the
password segment for IAM database authentication. A DSN with a password
contains a secret; do not log it.
