# Feature Specification: Data Platform Infrastructure

**Feature Branch**: `001-data-platform-infra`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: see `prompt/002-infra-specify.md` (infrastructure of the data platform,
described by functionality: ingestion, processing, orchestration, BI, observability and governance).

## Clarifications

### Session 2026-10-10

- Q: How must the platform be turned on and off? → A: It stays on 24/7; the daily update runs
  automatically.
- Q: If the processing environment or a tool's own database is lost, what must be recoverable? → A: Only the
  stored data; the catalog of the tables and the state of the other tools are not backed up (first
  answer "data and catalog, backed up daily" revised by the user on the same day).
- Q: How long is raw (bronze) data kept in the repository? → A: All data is kept with no time
  limit; nothing is deleted.
- Q: When must the BI be available to business users? → A: Weekdays (Monday to Friday), 08:00
  to 18:00, Brasília time (America/Sao_Paulo); it may be unavailable outside that window.
- Q: By what time must the daily data be updated in the BI? → A: By 08:00 Brasília time, with the
  previous day's data.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ingestion (Priority: P1)

The technical team extracts data from external and internal sources (APIs, databases and files)
and stores it in a repository.

**Why this priority**: every other functionality works on the data that ingestion brings in.

**Independent Test**: extract data from one API, one database and one file, from internal and
external sources, and confirm the data is in the repository.

**Acceptance Scenarios**:

1. **Given** an external source of each type (API, database, file), **When** the technical team
   runs an extraction, **Then** the data is stored in the repository.
2. **Given** an internal source of each type, **When** the technical team runs an extraction,
   **Then** the data is stored in the repository.
3. **Given** a person outside the technical team, **When** they try to access the ingestion,
   **Then** access is denied.

---

### User Story 2 - Processing (Priority: P2)

The technical team processes the stored data with computing power that scales with demand, using
the medallion architecture and the star schema as reference.

**Why this priority**: raw data only becomes useful to business users after processing.

**Independent Test**: process a sample of stored data through the medallion layers into a star
schema and confirm the result is available.

**Acceptance Scenarios**:

1. **Given** data stored by ingestion, **When** the technical team runs processing, **Then** the
   data goes through the medallion layers and is available in a star schema.
2. **Given** a larger volume of data, **When** processing runs, **Then** computing power scales
   with the demand.
3. **Given** no processing is running, **When** the cost is checked, **Then** the processing cost
   tends to zero.

---

### User Story 3 - Orchestration (Priority: P3)

The technical team runs the workloads on a schedule, on demand and by tumbling windows. Data is
updated daily, with no streaming.

**Why this priority**: it turns ingestion and processing into a repeatable daily routine.

**Independent Test**: schedule a workload, run it on demand, and run it for one tumbling window;
confirm each run happens as requested.

**Acceptance Scenarios**:

1. **Given** a workload with a daily schedule, **When** the scheduled time arrives, **Then** the
   workload runs.
2. **Given** a workload, **When** the technical team starts it on demand, **Then** it runs.
3. **Given** a workload run by tumbling windows, **When** a window closes, **Then** the workload
   processes exactly that window; the window size is set per workload.

---

### User Story 4 - BI (Priority: P4)

Business users receive the final product over the internet, each with an individual login.
External systems also consume the processed data over the internet.

**Why this priority**: it is the final product of the platform for the business.

**Independent Test**: a business user logs in over the internet and sees the processed data; an
external system consumes the processed data over the internet.

**Acceptance Scenarios**:

1. **Given** a business user with an individual login, **When** they access the BI over the
   internet, **Then** they see the processed data.
2. **Given** a person without a login, **When** they try to access the BI, **Then** access is
   denied.
3. **Given** a business user, **When** they look at data classified as sensitive, **Then** the
   sensitive data is hidden.
4. **Given** an external system with its own credential, **When** it requests the processed data
   over the internet, **Then** it receives the data.
5. **Given** an external system without a valid credential, **When** it requests the processed
   data, **Then** access is denied.

---

### User Story 5 - Observability (Priority: P5)

The technical team sees executions and failures, resource usage and cost, and is alerted when
something fails.

**Why this priority**: the team must know what ran, what failed and what it costs to operate the
platform.

**Independent Test**: run a workload that succeeds and one that fails; confirm both appear with
their resource usage and cost, and that the failure generates an alert to the technical team.

**Acceptance Scenarios**:

1. **Given** workloads that ran, **When** the technical team looks at the platform, **Then** it
   sees each execution, its result and its resource usage.
2. **Given** the platform running, **When** the technical team looks at the cost, **Then** it sees
   the cost of the platform.
3. **Given** a failure, **When** it happens, **Then** the technical team is alerted.
4. **Given** logs and metrics, **When** they are inspected, **Then** no sensitive data appears.

---

### User Story 6 - Governance (Priority: P6)

The technical team has a data catalog, lineage, access control and classification of sensitive
data.

**Why this priority**: it gives control over what data exists, where it came from, who accesses it
and which data is sensitive.

**Independent Test**: for one processed dataset, find it in the catalog, follow its lineage back to
the source, check who can access it and whether it has sensitive data.

**Acceptance Scenarios**:

1. **Given** a processed dataset, **When** the technical team searches the catalog, **Then** it
   finds the dataset.
2. **Given** a processed dataset, **When** the technical team looks at its lineage, **Then** it
   sees the source and each step the data went through.
3. **Given** a dataset with sensitive data, **When** it is classified, **Then** access to the
   sensitive data is restricted.

---

### Edge Cases

- A source is unavailable during an extraction: the failure is shown to the technical team and
  generates an alert (User Story 5).
- A workload fails during processing: the failure is shown and generates an alert (User Story 5).
- Sensitive data reaches a log or metric: this violates FR-006 and must not happen.
- The platform is moved to another of the three clouds: functionalities keep working
  (FR-002).
- A business user accesses the BI outside the availability window (FR-012): the BI may be
  unavailable; it is available again at the start of the next window.
- The processing environment is lost: the stored data remains; the tables are recreated by
  reloading from the sources and the other tools are rebuilt (FR-018).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST be hosted on one of the three main clouds: AWS, Azure or GCP.
- **FR-002**: The solution MUST be interchangeable across at least AWS, Azure and GCP, with minimal
  cloud provider lock-in.
- **FR-003**: Every functionality MUST scale with demand, with cost tending to zero.
- **FR-004**: Every functionality MUST be accessed only by the technical team, except BI (FR-012).
- **FR-005**: Encryption in transit and at rest MUST be used only where it adds no cost.
- **FR-006**: Access to sensitive data MUST be restricted; sensitive data MUST be hidden from
  business users in BI and MUST NOT appear in logs or metrics.
- **FR-007**: The platform MUST extract data from external and internal sources of three types:
  APIs, databases and files.
- **FR-008**: Extracted data MUST be stored in a repository and kept with no time limit, in every
  medallion layer; no data is deleted by age.
- **FR-009**: The platform MUST provide computing power to process the data, using the medallion
  architecture and the star schema as reference.
- **FR-010**: Workloads MUST run on a schedule, on demand and by tumbling windows.
- **FR-011**: Data MUST be updated daily, with the previous day's data available by 08:00 Brasília
  time; streaming is not required. The platform stays on 24/7, so
  the daily update runs automatically, without anyone turning the platform on.
- **FR-012**: Up to 10 business users MUST access the BI over the internet, each with an individual
  login (own accounts, the company login or another login are all acceptable). The BI MUST be
  available on weekdays (Monday to Friday) from 08:00 to 18:00 Brasília time (America/Sao_Paulo);
  outside that window it MAY be unavailable.
- **FR-013**: External systems MUST be able to consume the processed data over the internet, each
  identified by its own credential; requests without a valid credential MUST be denied.
- **FR-014**: The technical team MUST see executions and failures, resource usage and cost.
- **FR-015**: The technical team MUST be alerted when something fails.
- **FR-016**: The platform MUST provide a data catalog, lineage, access control and classification
  of sensitive data.
- **FR-017**: The platform MUST support growth of the daily data volume from today's 1 GB per day
  up to 1000x (about 1 TB per day) without redesign.
- **FR-018**: The stored data MUST survive the loss of the processing environment. The catalog of
  the tables and the state of the other tools (dashboards, run history, metadata catalog) are not
  backed up; after such a loss, the tables are recreated by reloading the data from the sources and
  the other tools are rebuilt by hand or from the repository.

### Key Entities

- **Source**: an external or internal origin of data; API, database or file.
- **Repository**: where extracted and processed data is stored.
- **Medallion layer**: a stage of processing in the medallion architecture.
- **Star schema**: the reference model for processed data.
- **Workload**: a run of ingestion or processing; scheduled, on demand or by tumbling window.
- **Tumbling window**: a fixed, non-overlapping time period processed by one run.
- **Business user**: a person who accesses the BI with an individual login.
- **External system**: a system that consumes the processed data over the internet with its own
  credential.
- **Sensitive data**: data that requires restricted access (e.g., personal data under LGPD).
- **Catalog entry**: the description of a dataset, with its lineage and classification.
- **Alert**: a notice to the technical team that something failed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the three source types (API, database, file), internal and external, are
  extracted into the repository.
- **SC-002**: Every day, by 08:00 Brasília time (America/Sao_Paulo), the data available to
  business users includes the previous day's data.
- **SC-003**: When no workload is running, processing cost tends to zero.
- **SC-004**: The platform handles a daily data volume from 1 GB up to about 1 TB without
  redesign.
- **SC-005**: Up to 10 business users access the BI over the internet with individual logins; 100%
  of access attempts without a login are denied.
- **SC-006**: 0 occurrences of sensitive data visible to business users in BI or present in logs
  and metrics.
- **SC-007**: 100% of failures generate an alert to the technical team.
- **SC-008**: 100% of processed datasets appear in the catalog with lineage and classification.
- **SC-009**: The solution can be moved between AWS, Azure and GCP changing only cloud-specific
  configuration (constitution VIII).

## Assumptions

- From the prompt: a small company; about 1 GB of new data per day today, with exponential growth
  expected; this is an exercise and simplicity comes first.
- From the constitution: a single `dev` environment; no secrets in the repository; every resource
  is created from the repository.
- Data modeling decisions (e.g., history of dimension changes) belong to the data scope and are out
  of scope here.
- LGPD is applied per user and group in the data layers; access to sensitive data (FR-006) is
  controlled there, not by the cloud permissions of the workloads.
- Dependencies: none; this is the first feature.
