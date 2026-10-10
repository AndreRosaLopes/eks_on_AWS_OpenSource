#!/usr/bin/env bash
# Acceptance checks of step 0.1 Network (quickstart.md 0.1).
source "$(dirname "$0")/lib.sh"
require_tools aws terraform

vpc_id="$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$CLUSTER_NAME" --query 'Vpcs[0].VpcId' --output text)"

subnets_per_az() {
  local count
  count="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'length(Subnets)' --output text)"
  local azs
  azs="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'Subnets[].AvailabilityZone' --output text | tr '\t' '\n' | sort -u | wc -l)"
  [ "$count" = "4" ] && [ "$azs" = "2" ]
}

single_nat_route() {
  local nats
  nats="$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
    --query 'length(NatGateways)' --output text)"
  [ "$nats" = "1" ]
}

private_default_route_to_nat() {
  aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" \
    --query "RouteTables[].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId" --output text | grep -q nat-
}

s3_endpoint_route() {
  aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'RouteTables[].Routes[].DestinationPrefixListId' --output text | grep -q pl-
}

public_subnets_tagged() {
  local count
  count="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:kubernetes.io/role/elb,Values=1" \
    --query 'length(Subnets)' --output text)"
  [ "$count" = "2" ]
}

no_changes() {
  terraform -chdir="$REPO_ROOT/infra/terraform/foundation" plan -detailed-exitcode -input=false -lock=false
}

check "VPC exists" test -n "$vpc_id" -a "$vpc_id" != "None"
check "2 public and 2 private subnets in 2 AZs" subnets_per_az
check "public subnets tagged for load balancers" public_subnets_tagged
check "one NAT gateway" single_nat_route
check "private default route to the NAT gateway" private_default_route_to_nat
check "S3 gateway endpoint route" s3_endpoint_route
check "terraform plan in foundation has no changes" no_changes
summary
