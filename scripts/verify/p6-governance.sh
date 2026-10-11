#!/usr/bin/env bash
# Acceptance checks of P6 Governance (quickstart.md P6). Catalog, lineage and classification of a
# dataset are checked in the OpenMetadata UI.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/apps.sh"
require_tools kubectl

openmetadata_healthy() {
  kubectl -n openmetadata get pods -l app.kubernetes.io/name=openmetadata | grep -q '1/1'
}

check "opensearch Application Synced and Healthy" app_synced_healthy opensearch
check "openmetadata Application Synced and Healthy" app_synced_healthy openmetadata
check "OpenMetadata server ready" openmetadata_healthy
summary
