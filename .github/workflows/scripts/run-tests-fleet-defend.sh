#!/usr/bin/env bash

set -eu
set -o pipefail

source "${BASH_SOURCE[0]%/*}"/lib/testing.sh

ip_kb="$(service_ip kibana)"

declare -a kb_args=( '-s' '-u' 'elastic:testpasswd' '-H' 'kbn-xsrf: true' '--resolve' "kibana:5601:${ip_kb}" )

grouplog "Checking 'detection-lab-endpoints' agent policy Fleet preconfig"

response="$(curl "${kb_args[@]}" 'http://kibana:5601/api/fleet/agent_policies/detection-lab-endpoints')"
echo "$response"

for field in fleet_server_host_id data_output_id monitoring_output_id; do
	case "$field" in
		fleet_server_host_id) expected='fleet-external-agents-host' ;;
		*) expected='fleet-external-agents-output' ;;
	esac

	value="$(jq -r --arg f "$field" '.item[$f] // empty' <<<"$response")"
	if [ "$value" != "$expected" ]; then
		err "Expected item.${field} to be '${expected}', got '${value:-<empty>}'"
		exit 1
	fi
done

endgroup

grouplog "Checking 'endpoint-1' package policy has a full Elastic Defend protection config"

response="$(curl "${kb_args[@]}" 'http://kibana:5601/api/fleet/package_policies/endpoint-1')"
echo "$response"

for os in windows mac linux; do
	has_key="$(jq --arg os "$os" '[.item.inputs[] | select(.type == "endpoint") | .config.policy.value | has($os)] | any' <<<"$response")"
	if [ "$has_key" != 'true' ]; then
		err "Expected endpoint-1's policy.value to contain a '${os}' protection config"
		exit 1
	fi
done

endgroup
