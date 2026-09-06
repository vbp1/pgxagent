<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand-kit/banner/xagent-banner-github-dark-mode@2x.png">
    <source media="(prefers-color-scheme: light)" srcset="brand-kit/banner/xagent-banner-github-light-mode@2x.png">
    <img alt="XAgent logo" src="brand-kit/banner/xagent-banner-github@2x.png">
  </picture>
</div>

# XAgent, your AI expert in PostgreSQL

XAgent is an AI agent that watches your PostgreSQL databases: it reads logs and metrics, finds what is
going wrong, suggests configuration changes, investigates incidents on request, and tells you when
something needs attention. It is like having an experienced DBA on your team, available 24/7.

This repository holds the installer, the release archives, and the documentation. The source lives elsewhere.

XAgent is free to use, in production too: see [Licensing](#licensing).

**Key features:**

- Monitoring on a schedule: a playbook runs against a database, and what it finds becomes an incident
  record - opened once, confirmed while it lasts, closed with a stated reason
- Chat with the agent about a specific database, with the answer produced on the server and kept if the
  page is closed or the connection drops
- Logs and metrics analysis (VictoriaLogs, VictoriaMetrics) through sub-agents that investigate on their
  own
- Investigation triggered by an alert from a monitoring system (AlertManager, Prometheus)
- 17 built-in diagnostic playbooks, plus playbooks you write yourself
- Commands on the server with human approval: the agent proposes, shows the risk, and a person clicks.
  The feature is off by default and turned on per database
- The official PostgreSQL 14-18 documentation inside the installation: searched and quoted without going
  to the internet
- Clusters: Patroni, or a cluster built on other replication software - node roles, replica lag,
  settings that differ between nodes
- Multi-LLM support: a cloud API such as DeepSeek, any OpenAI-compatible server, LiteLLM, or a local
  model through Ollama or vLLM
- Team access: four built-in roles, per-database grants, chats that stay private when you say so, and a
  project activity log
- Slack notifications when an incident record opens and closes
- On-premise deployment, including a closed network with no internet access
- Experimental SQL mode: natural language queries to your data
- Extensible via MCP servers

The agent never changes anything on its own: it analyses and proposes, and a person decides. The
[quick start guide](./docs/en/quick-start.md) lists what the agent does and where its limits are.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/vbp1/pgxagent/main/install.sh | bash
```

The script downloads the newest release, checks it against the published checksum, unpacks it, and
prints the command to run next. It stops there on purpose: the installer asks questions (the port, the
database credentials, which model provider to use) and needs a terminal to ask them on.

Then:

```sh
cd xagent-<version>
./xagent-installer verify
sudo ./xagent-installer install --path /opt/xagent --up
```

## Which archive

Every release carries two archives of the same version. They differ only in whether the container
images are included.

| Archive                                    | Size    | For                                                               |
| ------------------------------------------ | ------- | ----------------------------------------------------------------- |
| `xagent-<version>-linux-amd64-online.zip`  | ~35 MB  | A server with internet - the images are downloaded during install |
| `xagent-<version>-linux-amd64-offline.zip` | ~320 MB | A closed network - every image is inside the archive              |

To take the offline one: `curl -fsSL .../install.sh | bash -s -- --offline`.

Downloading needs no account: the images come from a public repository and are fetched anonymously.

## Checking what you downloaded

Each release publishes `SHA256SUMS-<version>.txt` beside the archives, because a checksum list packed
inside the archive it describes cannot vouch for that archive. It lists both archives, so check the
line for the one you took:

```sh
grep xagent-<version>-linux-amd64-online.zip SHA256SUMS-<version>.txt | sha256sum -c
```

The installer's own `verify` command is a different check: it confirms that the files inside the
archive match the manifest included with them.

## Documentation

The guides are in [`docs/`](./docs), in English ([`docs/en`](./docs/en)) and in Russian
([`docs/ru`](./docs/ru)).

| Guide                                                                    | What it covers                                           |
| ------------------------------------------------------------------------ | -------------------------------------------------------- |
| [Quick start](./docs/en/quick-start.md)                                  | First run: connect a database, ask the first question    |
| [Installation](./docs/en/install-guide.md)                               | Requirements, both archives, install, update, exit codes |
| [Targets](./docs/en/targets.md)                                          | Adding the databases XAgent watches                      |
| [Roles and access](./docs/en/rbac.md)                                    | Roles, database access, chat visibility and tool grants  |
| [Webhooks](./docs/en/webhooks.md)                                        | Sending alerts to an external system                     |
| [Example playbook](./docs/en/example-playbook-proactive-health-check.md) | A worked playbook, as something to copy from             |
| [What's new](./docs/en/changelog.md)                                     | What changed in this release                             |
| [Known issues](./docs/en/known-issues.md)                                | Known issues of this release and how to work around them |

## What you need

|                | Minimum | Recommended      |
| -------------- | ------- | ---------------- |
| OS             | Linux   | Ubuntu 22.04 LTS |
| Docker Engine  | 20.10+  | 24.0+            |
| Docker Compose | v2.0+   | v2.20+           |
| RAM            | 4 GB    | 8-16 GB          |
| Disk           | 15 GB   | 30+ GB           |

XAgent also needs a model to think with: a cloud API such as DeepSeek, or anything OpenAI-compatible
you run yourself, including a local one. The [installation guide](./docs/en/install-guide.md) lists the
providers we have tried.

XAgent does not install Docker. If Docker is not on the machine, install it the way your distribution
recommends first.

## Releases

Every version is published on the [releases page](https://github.com/vbp1/pgxagent/releases), with both
archives and their checksums.

## Licensing

XAgent is free to use, including in production and for commercial purposes, on any number of servers
and databases. You may not resell it, redistribute it to third parties or offer it as a hosted service.
The full terms are in [LICENSE.md](./LICENSE.md).

XAgent is a fork of [xataio/agent](https://github.com/xataio/agent), now archived. Code derived from
the upstream project remains under the Apache License 2.0; see
[LICENSE-APACHE-2.0](./LICENSE-APACHE-2.0).
