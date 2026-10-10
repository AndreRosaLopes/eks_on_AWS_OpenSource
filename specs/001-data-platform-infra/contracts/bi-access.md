# Contract: BI Access for Business Users

Access of business users to the BI over the internet (FR-012). Decisions: D-016, D-017, D-018,
D-022, D-026 in [research.md](../research.md).

## Endpoint

| Item | Value |
|---|---|
| Tool | Metabase (open source) |
| Protocol | HTTP (no TLS, D-017) |
| Host | DNS name of the platform NLB; it changes when the cluster is recreated |
| Port | Dedicated BI port on the `Gateway` (number set at implementation) |
| Availability | Required on weekdays 08:00–18:00 Brasília time; the BI runs 24/7 (D-022) |

## Authentication

- One Metabase account per business user, up to 10 users (FR-012).
- A request without a login is redirected to the login page; no data is shown (SC-005).
- Passwords travel in clear text over HTTP (consequence of D-017).

## Data access

- Metabase connects to Trino with one service user over the Trino TLS (D-018 mode 1, D-028).
- That user reads only the gold layer; sensitive columns are masked or hidden by the Trino rules
  (FR-006, D-026).
- Data includes the previous day's data by 08:00 Brasília time (SC-002).

## Acceptance

See [quickstart.md](../quickstart.md), P4.
