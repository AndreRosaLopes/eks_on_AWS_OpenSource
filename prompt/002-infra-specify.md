Feature: infrastructure of the data platform, described by functionality.

Why: a small company needs a data platform that extracts data from its sources, processes it and
delivers it to business users, with observability and governance. Today about 1 GB of new data
arrives per day, with exponential growth expected, so the platform must scale.

Requirements for every functionality:
- Hosted on one of the three main clouds: AWS, Azure or GCP.
- Minimal cloud provider lock-in: the solution must be interchangeable across at least these
  three clouds.
- Scalability, with cost tending to zero.
- Access only by the technical team, except where a functionality states otherwise.
- Encryption in transit and at rest only where it adds no cost; this is an exercise and simplicity
  comes first.
- Sensitive data exists (e.g., personal data under LGPD): access to it is restricted, it is hidden
  from business users in BI, and it never appears in logs or metrics.

Functionalities (user stories, in priority order):

P1 Ingestion: extract data from external and internal sources (APIs, databases and files) and store
it in a repository.

P2 Processing: computing power to process the data, using the medallion architecture and the star
schema as reference.

P3 Orchestration: run the workloads on a schedule, on demand and by tumbling windows. Data is
updated daily, with no streaming. Window granularity: [NEEDS CLARIFICATION: tumbling window
granularity, to be defined by the user].

P4 BI: deliver the final product to business users. Up to 10 business users access it over the
internet, each with an individual login (own accounts, the company login or another login are all
acceptable). External systems also consume the processed data over the internet.

P5 Observability: the technical team sees executions and failures, resource usage and cost, and is
alerted when something fails.

P6 Governance: data catalog, lineage, access control and classification of sensitive data.

Out of scope: data modeling decisions (e.g., history of dimension changes); they belong to the data
scope.
