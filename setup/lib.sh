#!/usr/bin/env bash

# Log a message.
function log {
	echo "[+] $1"
}

# Log a message at a sub-level.
function sublog {
	echo "   ⠿ $1"
}

# Log an error.
function err {
	echo "[x] $1" >&2
}

# Log an error at a sub-level.
function suberr {
	echo "   ⠍ $1" >&2
}

# Inject common arguments to curl commands based on the environment.
function augment_curl_args {
	local args_var_name=$1
	local -n args_ref="${args_var_name}"
	if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
		args_ref+=( '-u' "elastic:${ELASTIC_PASSWORD}" )
	fi
}

# Poll the 'elasticsearch' service until it responds with HTTP code 200.
function wait_for_elasticsearch {
	local elasticsearch_host="${ELASTICSEARCH_HOST:-elasticsearch}"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}' "http://${elasticsearch_host}:9200/" )

	augment_curl_args args

	local -i result=1
	local output

	# retry for max 300s (60*5s)
	for _ in $(seq 1 60); do
		local -i exit_code=0
		output="$(curl "${args[@]}")" || exit_code=$?

		if ((exit_code)); then
			result=$exit_code
		fi

		if [[ "${output: -3}" -eq 200 ]]; then
			result=0
			break
		fi

		sleep 5
	done

	if ((result)) && [[ "${output: -3}" -ne 000 ]]; then
		echo -e "\n${output::-3}"
	fi

	return $result
}

# Poll the Elasticsearch users API until it returns users.
function wait_for_builtin_users {
	local elasticsearch_host="${ELASTICSEARCH_HOST:-elasticsearch}"

	local -a args=( '-s' '-D-' '-m15' "http://${elasticsearch_host}:9200/_security/user?pretty" )

	augment_curl_args args

	local -i result=1

	local line
	local -i exit_code
	local -i num_users

	# retry for max 30s (30*1s)
	for _ in $(seq 1 30); do
		num_users=0

		# read exits with a non-zero code if the last read input doesn't end
		# with a newline character. The printf without newline that follows the
		# curl command ensures that the final input not only contains curl's
		# exit code, but causes read to fail so we can capture the return value.
		# Ref. https://unix.stackexchange.com/a/176703/152409
		while IFS= read -r line || ! exit_code="$line"; do
			if [[ "$line" =~ _reserved.+true ]]; then
				(( num_users++ ))
			fi
		done < <(curl "${args[@]}"; printf '%s' "$?")

		if ((exit_code)); then
			result=$exit_code
		fi

		# we expect more than just the 'elastic' user in the result
		if (( num_users > 1 )); then
			result=0
			break
		fi

		sleep 1
	done

	return $result
}

# Verify that the given Elasticsearch user exists.
function check_user_exists {
	local username=$1

	local elasticsearch_host="${ELASTICSEARCH_HOST:-elasticsearch}"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"http://${elasticsearch_host}:9200/_security/user/${username}"
		)

	augment_curl_args args

	local -i result=1
	local -i exists=0
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 || "${output: -3}" -eq 404 ]]; then
		result=0
	fi
	if [[ "${output: -3}" -eq 200 ]]; then
		exists=1
	fi

	if ((result)); then
		echo -e "\n${output::-3}"
	else
		echo "$exists"
	fi

	return $result
}

# Set password of a given Elasticsearch user.
function set_user_password {
	local username=$1
	local password=$2

	local elasticsearch_host="${ELASTICSEARCH_HOST:-elasticsearch}"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"http://${elasticsearch_host}:9200/_security/user/${username}/_password"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\" : \"${password}\"}"
		)

	augment_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Create the given Elasticsearch user.
function create_user {
	local username=$1
	local password=$2
	local role=$3

	local elasticsearch_host="${ELASTICSEARCH_HOST:-elasticsearch}"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"http://${elasticsearch_host}:9200/_security/user/${username}"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\":\"${password}\",\"roles\":[\"${role}\"]}"
		)

	augment_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Base curl args for the Kibana API: auth, xsrf header, HTTP code suffix.
function kibana_curl_args {
	local args_var_name=$1
	local -n args_ref="${args_var_name}"
	args_ref+=( '-s' '-D-' '-m30' '-w' '%{http_code}' '-H' 'kbn-xsrf: true' )
	augment_curl_args "${args_var_name}"
}

# Poll the 'kibana' service until its status API reports 'available'.
function wait_for_kibana {
	local kibana_host="${KIBANA_HOST:-kibana}"

	local -a args=()
	kibana_curl_args args
	args+=( "http://${kibana_host}:5601/api/status" )

	local -i result=1
	local output

	# retry for max 300s (60*5s)
	for _ in $(seq 1 60); do
		output="$(curl "${args[@]}")" || true

		if [[ "${output: -3}" -eq 200 ]] && [[ "${output::-3}" =~ \"level\":\"available\" ]]; then
			result=0
			break
		fi

		sleep 5
	done

	return $result
}

# Trigger (and wait for) Fleet's own setup: package installation and
# preconfigured agent policy creation. Idempotent, safe to call repeatedly.
function init_fleet {
	local kibana_host="${KIBANA_HOST:-kibana}"

	local -a args=()
	kibana_curl_args args
	args+=( "http://${kibana_host}:5601/api/fleet/setup" '-X' 'POST' )

	local -i result=1
	local output

	# Fleet setup can take a few minutes on a cold start (package downloads).
	# retry for max 600s (60*10s)
	for _ in $(seq 1 60); do
		output="$(curl "${args[@]}")" || true

		if [[ "${output: -3}" -eq 200 ]] && [[ "${output::-3}" =~ \"isInitialized\":true ]]; then
			result=0
			break
		fi

		sleep 10
	done

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Echo 1 if the given Fleet resource path returns 200, 0 otherwise.
function fleet_resource_exists {
	local path=$1
	local kibana_host="${KIBANA_HOST:-kibana}"

	local -a args=()
	kibana_curl_args args
	args+=( "http://${kibana_host}:5601/api/fleet/${path}" )

	local output
	output="$(curl "${args[@]}")"

	if [[ "${output: -3}" -eq 200 ]]; then
		echo 1
	else
		echo 0
	fi
}

# Echo the installed version of the given Fleet package, or an empty string
# if it isn't installed. Retries: package installation is async.
function get_package_version {
	local name=$1
	local kibana_host="${KIBANA_HOST:-kibana}"

	local -a args=()
	kibana_curl_args args
	args+=( "http://${kibana_host}:5601/api/fleet/epm/packages/${name}" )

	local output version=''

	# retry for max 120s (24*5s)
	for _ in $(seq 1 24); do
		output="$(curl "${args[@]}")" || true

		if [[ "${output: -3}" -eq 200 ]]; then
			# 'item.version' (installed version) is the first "version" key in
			# the response, ahead of 'latestVersion' and nested version fields.
			version="$(grep -oE '"version" *: *"[^"]+"' <<<"${output::-3}" \
				| head -n1 | sed -E 's/.*"([^"]+)"$/\1/')"
			[[ -n "$version" ]] && break
		fi

		sleep 5
	done

	echo "$version"
}

# Create a package policy for the given package/version/agent policy, with an
# explicit 'id' so re-runs hit 409 (treated as success) instead of duplicating.
function create_package_policy {
	local id=$1
	local package_name=$2
	local package_version=$3
	local agent_policy_id=$4

	local kibana_host="${KIBANA_HOST:-kibana}"

	local -a args=()
	kibana_curl_args args
	args+=(
		# Overrides kibana_curl_args' -m30: the endpoint package's first-time
		# policy creation runs a server-side callback that can take a while.
		'-m180'
		"http://${kibana_host}:5601/api/fleet/package_policies"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"id\":\"${id}\",\"name\":\"${id}\",\"namespace\":\"default\",\"policy_ids\":[\"${agent_policy_id}\"],\"package\":{\"name\":\"${package_name}\",\"version\":\"${package_version}\"}}"
		)

	local -i result=1
	local output

	output="$(curl "${args[@]}")" || true
	local -i http_code="${output: -3}"

	if ((http_code == 200)); then
		result=0
	elif ((http_code == 409)); then
		# Already created by a previous run.
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Ensure that the given Elasticsearch role is up-to-date, create it if required.
function ensure_role {
	local name=$1
	local body=$2

	local elasticsearch_host="${ELASTICSEARCH_HOST:-elasticsearch}"

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"http://${elasticsearch_host}:9200/_security/role/${name}"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "$body"
		)

	augment_curl_args args

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" -eq 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}
