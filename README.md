# Elastic stack (ELK) on Docker: detection lab

[![Elastic Stack version](https://img.shields.io/badge/Elastic%20Stack-9.5.2-00bfb3?style=flat&logo=elastic-stack)](https://www.elastic.co/blog/category/releases)
[![Build Status](https://github.com/yuto0226/docker-elk-defend/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/yuto0226/docker-elk-defend/actions/workflows/ci.yml?query=branch%3Amain)

Fork of [deviantony/docker-elk][upstream] with Fleet Server and Elastic Defend wired up, for a self-contained
detection lab. This README covers only what's specific to that: bringing up the stack and enrolling agents.
Everything about the base ELK stack itself (per-component configuration, JVM tuning, plugins, scaling, other
extensions, older Elastic versions) is in the [upstream README][upstream-readme].

This fork only tracks `main` (Elastic 9.x). It does not carry upstream's other branches (`tls`, `release-8.x`, etc.).

> [!IMPORTANT]
> [Platinum][subscriptions] features are enabled by default for a [trial][license-mngmt] of **30 days**. After that,
> you keep the free Open Basic features, without losing data. See
> [How to disable paid features](#how-to-disable-paid-features) to opt out.

---

## tl;dr

```sh
docker compose up setup
```

```sh
docker compose up
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/6f67cbc0-ddee-44bf-8f4d-7fd2d70f5217">
  <img alt="Animated demo" src="https://github.com/user-attachments/assets/501a340a-e6df-4934-90a2-6152b462c14a">
</picture>

---

## Requirements

### Host setup

* [Docker Engine][docker-install] version **18.06.0** or newer
* [Docker Compose][compose-install] version **2.0.0** or newer
* 1.5 GB of RAM

> [!NOTE]
> Especially on Linux, make sure your user has the [required permissions][linux-postinstall] to interact with the
> Docker daemon.

By default, the stack exposes the following ports:

* 5044: Logstash Beats input
* 50000: Logstash TCP input
* 9600: Logstash monitoring API
* 9200: Elasticsearch HTTP
* 9300: Elasticsearch TCP transport
* 5601: Kibana

The [Fleet extension](extensions/fleet) additionally exposes 8220 (Fleet Server).

> [!WARNING]
> Elasticsearch's [bootstrap checks][bootstrap-checks] are disabled by default to simplify development setups. For
> production, follow the Elasticsearch documentation: [Important System Configuration][es-sys-config].

On Docker Desktop (Windows/macOS), see upstream's [Docker Desktop notes][upstream-desktop] for file sharing setup.

## Usage

### Bringing up the stack

Clone this repository onto the Docker host that will run the stack:

```sh
git clone https://github.com/yuto0226/docker-elk-defend.git
```

Then, initialize the Elasticsearch users and groups required by docker-elk:

```sh
docker compose up setup
```

Generate encryption keys for Kibana. Required for Fleet, not optional in this fork:

```sh
docker compose up kibana-genkeys
```

Copy the three generated values into the matching variables in the [`.env`](.env) file
(`KIBANA_SECURITY_ENCRYPTION_KEY`, `KIBANA_ENCRYPTED_SAVED_OBJECTS_ENCRYPTION_KEY`, `KIBANA_REPORTING_ENCRYPTION_KEY`).

Start the other stack components:

```sh
docker compose up
```

> [!NOTE]
> You can also run all services in the background (detached mode) by appending the `-d` flag to the above command.

Give Kibana about a minute to initialize, then access the Kibana web UI by opening <http://localhost:5601> in a web
browser and use the following (default) credentials to log in:

* user: *elastic*
* password: *changeme*

> [!NOTE]
> Upon the initial startup, the `elastic`, `logstash_internal` and `kibana_system` Elasticsearch users are initialized
> with the values of the passwords defined in the [`.env`](.env) file (_"changeme"_ by default). Rotating these
> passwords for anything beyond local testing is covered in upstream's
> [Setting up user authentication][upstream-auth].

### Cleanup

Elasticsearch data is persisted inside a volume by default.

In order to entirely shutdown the stack and remove all persisted data, use the following Docker Compose command:

```sh
docker compose --profile=setup down -v
```

## Fleet Server and Elastic Defend

See [`extensions/fleet/README.md`](extensions/fleet/README.md) for enabling Fleet Server and enrolling Elastic Defend
agents from lab VMs.

## How to disable paid features

To revert to a basic license before the trial expires, use the [License Management][license-mngmt] panel in Kibana,
or Elasticsearch's `start_basic` [Licensing API][license-apis]. The API is the only way to regain access to Kibana if
the trial expires before switching to `basic` or upgrading.

## Going further

For everything else, from configuring individual components to JVM tuning to adding plugins, see the
[upstream README][upstream-readme].

[upstream]: https://github.com/deviantony/docker-elk
[upstream-readme]: https://github.com/deviantony/docker-elk#readme
[upstream-desktop]: https://github.com/deviantony/docker-elk#docker-desktop
[upstream-auth]: https://github.com/deviantony/docker-elk#setting-up-user-authentication

[subscriptions]: https://www.elastic.co/subscriptions
[license-mngmt]: https://www.elastic.co/docs/deploy-manage/license/manage-your-license-in-self-managed-cluster
[license-apis]: https://www.elastic.co/docs/api/doc/elasticsearch/group/endpoint-license

[docker-install]: https://docs.docker.com/get-started/get-docker/
[compose-install]: https://docs.docker.com/compose/install/
[linux-postinstall]: https://docs.docker.com/engine/install/linux-postinstall/

[bootstrap-checks]: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/bootstrap-checks
[es-sys-config]: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/important-system-configuration

<!-- markdownlint-configure-file
{
  "MD033": {
    "allowed_elements": [ "picture", "source", "img" ]
  }
}
-->
