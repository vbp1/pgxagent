# XAgent

An AI agent that watches your PostgreSQL databases: it reads logs and metrics, finds what is going
wrong, suggests configuration changes, investigates incidents on request, and tells you when something
needs attention.

This repository is where XAgent is distributed from. The source lives elsewhere; what you will find
here is the installer, the release archives, and the documentation.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/vbp1/pgxagent/main/install.sh | bash
```

The script downloads the newest release, checks it against the published checksum, unpacks it, and
prints the command to run next. It stops there on purpose: the installer asks questions — the port, the
database credentials, which model provider to use — and needs a terminal to ask them on.

Then:

```sh
cd xagent-<version>
./xagent-installer verify
sudo ./xagent-installer install --path /opt/xagent --up
```

## Which archive

Every release carries two archives of the same version. They differ only in whether the container
images travel inside them.

| Archive                                    | Size    | For                                                              |
| ------------------------------------------ | ------- | ---------------------------------------------------------------- |
| `xagent-<version>-linux-amd64-online.zip`   | ~35 MB  | A server with internet — the images are downloaded during install |
| `xagent-<version>-linux-amd64-offline.zip`  | ~320 MB | A closed network — every image travels inside the archive         |

To take the offline one: `curl -fsSL .../install.sh | bash -s -- --offline`.

Downloading needs no account of any kind: the images come from a public repository and are fetched
anonymously.

## Checking what you downloaded

Each release publishes `SHA256SUMS-<version>.txt` **beside** the archives — a checksum list packed
inside the archive it describes cannot vouch for that archive.

```sh
sha256sum -c SHA256SUMS-<version>.txt
```

The installer's own `verify` command is a different check: it confirms that the files inside the
archive match the manifest that travels with them.

## Documentation

The guides are in [`docs/`](./docs). They are currently in Russian; English translations are in
progress and will appear under [`docs/en`](./docs/en) as they are ready.

| Guide                                                                                                | What it covers                                            |
| ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| [Quick start](./docs/ru/quick-start.md)                                                                | First run: connect a database, ask the first question       |
| [Installation](./docs/ru/install-guide.md)                                                             | Requirements, both archives, install, update, exit codes    |
| [Targets](./docs/ru/targets.md)                                                                        | Adding the databases XAgent watches                         |
| [Webhooks](./docs/ru/webhooks.md)                                                                      | Sending alerts to an external system                        |
| [Example playbook](./docs/ru/example-playbook-proactive-health-check.md)                               | A worked playbook, as something to copy from                |

## What you need

| | Minimum | Recommended |
| --- | --- | --- |
| OS | Linux | Ubuntu 22.04 LTS |
| Docker Engine | 20.10+ | 24.0+ |
| Docker Compose | v2.0+ | v2.20+ |
| RAM | 4 GB | 8–16 GB |
| Disk | 15 GB | 30+ GB |

XAgent also needs a model to think with — a cloud API such as DeepSeek, or anything OpenAI-compatible
you run yourself, including a local one. The [installation guide](./docs/ru/install-guide.md) lists the
providers that have been tried.

XAgent does not install Docker. If Docker is not on the machine, install it the way your distribution
recommends first.

## Releases

Every version is published on the [releases page](https://github.com/vbp1/pgxagent/releases), with both
archives and their checksums.

## Licensing

XAgent is a fork of [xataio/agent](https://github.com/xataio/agent), now archived. Code derived from
the upstream project is licensed under the Apache License 2.0 — see
[LICENSE-APACHE-2.0](./LICENSE-APACHE-2.0). Everything else is proprietary and is not licensed for use,
copying, modification, or distribution.
