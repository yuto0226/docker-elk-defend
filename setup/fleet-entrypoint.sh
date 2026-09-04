#!/usr/bin/env bash

set -eu
set -o pipefail

source "${BASH_SOURCE[0]%/*}"/lib.sh

declare policy_id="${FLEET_AGENT_POLICY_ID:-detection-lab-endpoints}"


log 'Waiting for availability of Kibana. This can take several minutes.'

if ! wait_for_kibana; then
	suberr 'Connection to Kibana failed'
	exit 1
fi

sublog 'Kibana is available'

log 'Initializing Fleet'

if ! init_fleet; then
	suberr 'Fleet setup did not complete'
	exit 1
fi

sublog 'Fleet is initialized'

log "Agent policy '${policy_id}'"

if [[ "$(fleet_resource_exists "agent_policies/${policy_id}")" -eq 0 ]]; then
	sublog 'Policy not found (fleet extension not configured for it?), skipping'
	exit 0
fi

log "Package policy 'endpoint-1'"

if [[ "$(fleet_resource_exists 'package_policies/endpoint-1')" -eq 1 ]]; then
	sublog 'Already exists, skipping'
	exit 0
fi

declare endpoint_version
endpoint_version="$(get_package_version 'endpoint')"

if [[ -z "$endpoint_version" ]]; then
	suberr "Package 'endpoint' is not available in Fleet"
	exit 1
fi

sublog "Creating for package 'endpoint' version ${endpoint_version}"

if ! create_package_policy 'endpoint-1' 'endpoint' "$endpoint_version" "$policy_id"; then
	suberr 'Failed to create package policy'
	exit 1
fi
