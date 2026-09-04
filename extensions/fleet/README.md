# Fleet Server

> [!WARNING]
> This extension currently exists for preview purposes and should be considered **EXPERIMENTAL**. Expect regular changes
> to the default Fleet settings, both in the Elastic Agent and Kibana.
>
> See [Known Issues](#known-issues) for a list of issues that need to be addressed before this extension can be
> considered functional.

Fleet provides central management capabilities for [Elastic Agents][fleet-doc] via an API and web UI served by Kibana,
with Elasticsearch acting as the communication layer.
Fleet Server is the central component which allows connecting Elastic Agents to the Fleet.

## Requirements

The Fleet Server exposes the TCP port `8220` for Agent to Server communications.

## Usage

To include Fleet Server in the stack, run Docker Compose from the root of the repository with an additional command line
argument referencing the `fleet-compose.yml` file:

```console
$ docker compose -f docker-compose.yml -f extensions/fleet/fleet-compose.yml up
```

## Configuring Fleet Server

Fleet Server — like any Elastic Agent — is configured via [Agent Policies][fleet-pol] which can be either managed
through the Fleet management UI in Kibana, or statically pre-configured inside the Kibana configuration file.

To ease the enrollment of Fleet Server in this extension, docker-elk comes with a pre-configured Agent Policy for Fleet
Server defined inside [`kibana/config/kibana.yml`][config-kbn].

Please refer to the following documentation page for more details about configuring Fleet Server through the Fleet
management UI: [Fleet UI Settings][fleet-cfg].

## Enrolling Elastic Defend agents from lab VMs

A `Detection Lab Endpoints` agent policy is pre-configured in
[`kibana.yml`][config-kbn] (with `system` and `elastic_agent` package
policies). Elastic Defend requires at least a trial license; Elasticsearch
self-generates one on first start (`xpack.license.self_generated.type: trial`
in [`elasticsearch.yml`][config-es], see [Known Issues](#known-issues)).

The `endpoint` package policy itself is added separately, via the Fleet API:
Security Solution registers a server-side callback that fills in the full
Windows/Mac/Linux protection config, and that callback only runs on package
policy creation through the API, not through `kibana.yml` preconfiguration.
The `fleet-setup` service runs that API call for you, idempotent and safe to
re-run any time (e.g. after rebuilding the stack):

```console
$ docker compose -f docker-compose.yml -f extensions/fleet/fleet-compose.yml up fleet-setup
```

Alternatively, do this from the Kibana UI: **Fleet → Agent policies →
Detection Lab Endpoints → Add integration → Elastic Defend**.

To enroll an agent from a VM:

1. Set `FLEET_SERVER_PUBLIC_URL` and `ELASTICSEARCH_PUBLIC_URL` in `.env` to a
   Docker-host address reachable from the VM, e.g. `http://192.168.186.1:8220`
   and `http://192.168.186.1:9200`, then `docker compose up -d kibana`.
   Agents ship data straight to `ELASTICSEARCH_PUBLIC_URL`, not through Fleet
   Server, so both must be reachable.
2. In Kibana: **Fleet → Agent policies → Detection Lab Endpoints → Add
   agent**, copy the enrollment command/token.
3. On the VM, install the Elastic Agent and run the enrollment command with
   `--url` set to `FLEET_SERVER_PUBLIC_URL` and `--insecure` (Fleet Server
   runs over plain HTTP by default).

## Known Issues

- The Elastic Agent auto-enrolls using the `elastic` super-user. With this approach, you do not need to generate a
  service token — either using the Fleet management UI or [CLI utility][es-svc-token] — prior to starting this
  extension. However convenient that is, this approach _does not follow security best practices_, and we recommend
  generating a service token for Fleet Server instead.
- The trial license (see the root [README][readme-trial]) does not renew in place. After it expires, Elastic Defend
  requires a paid Platinum/Enterprise subscription. Getting another 30-day trial means wiping the `elasticsearch`
  volume and rebuilding the cluster, which discards all data.
- Fleet Server and lab agents communicate over plain HTTP, and `ELASTIC_PASSWORD` defaults to `changeme`. Enrollment
  tokens, endpoint telemetry, and the superuser password all cross the network in cleartext. Don't run this on a
  network you don't control.

## See also

[Fleet and Elastic Agent Guide][fleet-doc]

## Screenshots

![fleet-agents](https://user-images.githubusercontent.com/3299086/202701399-27518fe4-17b7-49d1-aefb-868dffeaa68a.png
"Fleet Agents")
![elastic-agent-dashboard](https://user-images.githubusercontent.com/3299086/202701404-958f8d80-a7a0-4044-bbf9-bf73f3bdd17a.png
"Elastic Agent Dashboard")

[fleet-doc]: https://www.elastic.co/docs/reference/fleet
[fleet-pol]: https://www.elastic.co/docs/reference/fleet/agent-policy
[fleet-cfg]: https://www.elastic.co/docs/reference/fleet/fleet-settings

[config-kbn]: ../../kibana/config/kibana.yml
[config-es]: ../../elasticsearch/config/elasticsearch.yml
[readme-trial]: ../../README.md#how-to-disable-paid-features

[es-svc-token]: https://www.elastic.co/docs/reference/elasticsearch/command-line-tools/service-tokens-command
