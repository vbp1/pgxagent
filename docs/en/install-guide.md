# XAgent installation guide

## System requirements

| Component      | Minimum                                  | Recommended                                                                                                            |
| -------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| OS             | Linux                                    | Ubuntu 22.04 LTS                                                                                                         |
| Docker Engine  | 20.10+                                   | 24.0+                                                                                                                    |
| Docker Compose | v2.0+                                    | v2.20+                                                                                                                   |
| RAM            | 4 GB                                     | 8-16 GB                                                                                                                  |
| Disk           | 15 GB                                    | 30+ GB                                                                                                                   |
| Network        | Network access to the target PostgreSQL  | Network access to the target PostgreSQL                                                                                  |
| Time zone      | Any                                      | The host clock changes nothing: the container runs on UTC. Cron expressions of schedules are read in the container's time zone; set `TZ` in `.env` to read them in another one |
| **LLM**        | One of the options below                 | A cloud API (DeepSeek)                                                                                                   |

**Ways to connect an LLM**:

- **A cloud API** - needs internet access to the API provider (DeepSeek, OpenRouter, HuggingFace and others). More in [Preparing an LLM provider](#preparing-an-llm-provider).
- **A local LLM** - no internet access needed. Use Ollama, vLLM or any OpenAI-compatible server on your local network.

> XAgent does not install Docker. If Docker is missing, install it following the instructions for your Linux distribution.

## Preparing an LLM provider

The agent needs an LLM. Prepare one of the options **before you start the installation**:

### Recommended: DeepSeek V4 Pro

- API: `https://api.deepseek.com`
- Model: `OPENAI_MODEL=deepseek-v4-pro`
- Provider type in the installer: **OpenAI-compatible** (`OPENAI_API_TYPE=compatible`)

### Models we tested

| Model             | When to pick it                                                              | Vendor name         |
| ----------------- | ----------------------------------------------------------------------------- | ------------------- |
| DeepSeek V4 Pro   | The default choice                                                            | `deepseek-v4-pro`   |
| DeepSeek V4 Flash | Faster and cheaper than V4 Pro                                                | `deepseek-v4-flash` |
| GLM-5.3           | An alternative to DeepSeek                                                    | `glm-5.3`           |
| GLM-5.2           | The previous GLM release                                                      | `glm-5.2`           |
| Qwen3.8 Max       | An alternative to DeepSeek                                                    | `qwen3.8-max`       |
| gpt-oss-120b      | With a loss of quality; fits on a single A100/H100, so it also runs locally   | `gpt-oss-120b`      |

The last column is the name the model's own vendor uses. Aggregators put a prefix in front of it - the exact shape is in the "Model name shape" column.

### Supported platforms

| Platform    | Base URL                           | `OPENAI_API_TYPE` | Model name shape                                                                          |
| ----------- | ---------------------------------- | ----------------- | ------------------------------------------------------------------------------------------- |
| DeepSeek    | `https://api.deepseek.com`         | `compatible`      | DeepSeek models only, the vendor name as is: `deepseek-v4-pro`                             |
| OpenRouter  | `https://openrouter.ai/api/v1`     | `openrouter`      | Vendor prefix: `deepseek/deepseek-v4-pro`, `z-ai/glm-5.3`, `qwen/qwen3.8-max`               |
| HuggingFace | `https://router.huggingface.co/v1` | `compatible`      | Repository id: `deepseek-ai/DeepSeek-V4-Pro`, `zai-org/GLM-5.3`, `Qwen/Qwen3.8-2.4T-A95B`  |

> **`OPENAI_API_TYPE`**: `compatible` is the standard OpenAI-compatible API. `openrouter` covers OpenRouter and OpenRouter-compatible proxies; they support the `:provider` suffix in the model name to pick the upstream provider (for example `OPENAI_MODEL=deepseek-v4-pro:DeepSeek` is sent as `provider.only` in the request body). If `OPENAI_BASE_URL` is set and `OPENAI_API_TYPE` is not, `compatible` is used.

> **HuggingFace routing**: on the HuggingFace router the `:provider` suffix is part of the model name itself, not OpenRouter routing - write `zai-org/GLM-5.3:novita` and keep `OPENAI_API_TYPE=compatible`.

### Other providers

| Type in the installer | What you need                                                                        |
| --------------------- | -------------------------------------------------------------------------------------- |
| OpenAI-compatible API | The base URL and API key of any OpenAI-compatible server (a local vLLM, for example)  |
| OpenAI (native)       | An OpenAI API key                                                                      |
| LiteLLM proxy         | The URL and key of a LiteLLM instance                                                 |
| Ollama (local)        | The URL of a local Ollama server                                                      |

## Installation

### 1. Get the package

Two archives are published for the same version - pick one by whether the server has internet access.

| Archive                                    | Size     | What it is for                                                                    |
| ------------------------------------------ | -------- | --------------------------------------------------------------------------------- |
| `xagent-<version>-linux-amd64-online.zip`  | ~35 MB   | A server with internet access: images are pulled from Docker Hub at install time  |
| `xagent-<version>-linux-amd64-offline.zip` | ~320 MB  | An air-gapped environment: every image is inside the archive, no network needed   |

Inside, the archives are identical apart from the image directory.

The easiest way is a single command - it downloads the latest release, checks it against the published
checksum and unpacks it:

```bash
curl -fsSL https://raw.githubusercontent.com/vbp1/pgxagent/main/install.sh | bash
```

Options: `--version <x.y.z>` takes a specific release, `--dir <path>` unpacks into another directory,
`--offline` takes the archive with the images inside. The command does not launch the installer: the
installer asks questions, and a script run through a pipe has no terminal to ask them in, so at the end
the command prints the command for the next step.

The archives can also be downloaded by hand from the [releases page](https://github.com/vbp1/pgxagent/releases).

The application image ships with the official PostgreSQL 14-18 documentation: the agent searches it and quotes pages without going to the internet. After the first start it is loaded into the agent database in the background - the service keeps working meanwhile, and documentation search becomes available as the load progresses.

The online archive pulls images **without an account**: no Docker Hub login or password is needed or
asked for. The application image is pulled by the exact digest recorded in `manifest.json`, which
confirms that the registry served exactly the build released under this version.

### 2. Unpack and check integrity

If you downloaded the archive by hand, check it against the checksum published **next to** it. The
checksum file lists both archives, so take the line for the one you downloaded:

```bash
grep xagent-<version>-linux-amd64-online.zip SHA256SUMS-<version>.txt | sha256sum -c
unzip xagent-<version>-linux-amd64-online.zip
cd xagent-<version>
./xagent-installer verify
```

These are two different checks. The first answers the question "did the archive arrive intact"; the
checksum list sits next to the archive rather than inside it, because a list inside the archive cannot
vouch for the archive itself. `verify` answers a different question: "do the files inside match the
inventory that travelled with them".

The `verify` command checks the SHA256 hashes of every file in the package against `manifest.json`. For a manual check there is also a `SHA256SUMS` file (`sha256sum -c SHA256SUMS`).

### 3. Run the installation

```bash
sudo ./xagent-installer install --path /opt/xagent --up
```

Options:

- `--path <dir>` - the installation directory (`/opt/xagent` by default)
- `--up` - start XAgent automatically once installed
- `--offline` - take images from the archive only, never reach the network
- `--online` - pull images even if they are in the archive

Without these options the source picks itself: if the images are there, they are loaded; if not, they
are pulled. The options are mutually exclusive. Pulling goes through Docker itself, so on a machine
that reaches the internet through an intermediary (a proxy) it is **Docker** that has to be configured,
not the installer's environment: the intermediary set in the daemon settings works here too.

The installer then runs an interactive wizard:

1. **General settings** - port, URL, PostgreSQL credentials, `AUTH_TRUST_HOST`
2. **Authentication** - optional: OpenID SSO
3. **LLM provider** - choice and configuration (required)
4. **Integrations** - optional: VictoriaLogs, VictoriaMetrics
5. **Agent answer language** - English / Русский (written to `.env` as `SYSTEM_PROMPT_ADD`)

The wizard generates `AUTH_SECRET` and `CORE_SECRET` itself, without asking. The PostgreSQL password is
generated when you leave its prompt empty.

Signing in through an identity provider is turned on by the three `AUTH_OPENID_*` variables. Register
`<installation URL>/api/auth/callback/default` with the provider as the redirect URI. Password sign-in
stays on the sign-in page either way: the installation's superadmin signs in with a password, and the
provider's button stands next to that form.

Everything that can fail is checked **before** the wizard and before the directory is created: whether
the images are available in the registry, and whether there is free disk space. A failure at this stage
leaves no trace on the machine - you can fix the cause and start the installation again.

Once the wizard is done, the installer:

- Gets the images: pulls them (showing progress) or loads them from the archive
- Creates the configuration directory
- Writes `.env` (chmod 0600)
- Starts the stack (if `--up` was given)

Images that are already there are not pulled again: the decision is made by digest, so a repeat run
after an interrupted download continues with what is missing.

### 4. Check that it works

```bash
cd /opt/xagent

# Container status
docker compose ps

# Application logs
docker compose logs -f xagent
```

Open in a browser: `http://<host>:<port>` (port `8080` by default).

### 5. First sign-in

On the first open the sign-in page shows the **Create the superadmin** form: a username, an optional
display name and a password. This account administers the installation and grants access to everyone
else. The form is shown until the installation has a superadmin with a password; after that the page
shows the regular **Sign in** form (username or email, and password).

With the `AUTH_OPENID_*` variables set, the **Sign in with your identity provider** button stands under
either form.

## Updating

### 1. Unpack the new package

```bash
unzip xagent-<new-version>-linux-amd64-online.zip
cd xagent-<new-version>
```

An update takes the same `--offline` and `--online` options. Images are obtained **before** the stand is
stopped: if the network fails, the running installation is untouched and keeps working.

### 2. Run the update

```bash
sudo ./xagent-installer update --path /opt/xagent --backup full --up
```

Options:

- `--path <dir>` - the directory of the existing installation
- `--backup <mode>` - the backup mode before the update:
  - `none` - no backup
  - `files` - a backup of the configuration (the default)
  - `full` - a backup of the configuration plus the PostgreSQL data
- `--up` - start automatically once updated

The update, step by step:

- Gets the images - pulls them or loads them from the archive, while the previous version keeps running
- Stops the stack (`docker compose down --remove-orphans`)
- Creates the backup (if one was chosen)
- Updates `docker-compose.yaml`, `init.sql` and the documentation in `docs/`
- **Adds** new variables to `.env` at the end of the file, under a `# Added in <version>` comment (existing
  values are left alone; an empty `AUTH_SECRET` or `CORE_SECRET` gets a generated value)
- Starts the stack (if `--up` was given)

## Backup and rollback

### Backup modes

| Mode    | What is saved                                       | Size                   |
| ------- | --------------------------------------------------- | ---------------------- |
| `files` | `docker-compose.yaml`, `.env`, `.xagent/state.json`  | ~10 KB                 |
| `full`  | The files plus the PostgreSQL data (a Docker volume) | Depends on the data    |

Backups are saved to `<install-path>/backups/<timestamp>/`.

### Rollback

If something goes wrong after an update:

```bash
sudo ./xagent-installer rollback --path /opt/xagent
```

This rolls back to the latest backup: it restores the configuration, the data (with a `full` backup) and starts the stack.

To roll back to a specific backup:

```bash
sudo ./xagent-installer rollback --path /opt/xagent \
  --backup-dir /opt/xagent/backups/2026-02-21T12-00-00-000Z
```

## Installation layout

```
/opt/xagent/
├── docker-compose.yaml     # Compose configuration
├── .env                    # Environment variables (chmod 0600)
├── .env.example            # An example of the base set of variables
├── init.sql                # The database initialisation script
├── docs/                   # User documentation
│   ├── ru/                 # Russian texts
│   └── en/                 # English
├── .xagent/
│   └── state.json          # Installation metadata (version, port, dates)
├── logs/
│   └── installer.log       # The installer log (secrets are redacted)
└── backups/
    └── <timestamp>/        # Backups made during updates
```

## Managing the stack

Every command is run from the installation directory. Docker Compose picks up `docker-compose.yaml` and `.env` from the current directory on its own.

```bash
cd /opt/xagent

docker compose up -d       # Start
docker compose down        # Stop
docker compose logs -f     # View the logs
docker compose restart     # Restart
docker compose ps          # Container status
```

## Environment variables

The variables live in `.env`. The wizard writes the required values itself; the rest are added by hand from this reference. The `.env.example` file next to the installation shows the base set of lines - for the full list of settings see the tables below. Its values are samples: take the secrets (`AUTH_SECRET`, `CORE_SECRET`, the database password) only from what the wizard generated, otherwise the installation runs on well-known keys.

### Required

| Variable            | What it is                     | Default               |
| ------------------- | ------------------------------ | --------------------- |
| `PUBLIC_URL`        | The public URL of the app      | `http://0.0.0.0:8080` |
| `POSTGRES_USER`     | The PostgreSQL user            | `dbagent`             |
| `POSTGRES_PASSWORD` | The PostgreSQL password        | Generated             |
| `POSTGRES_DB`       | The database name              | `dbagent`             |
| `AUTH_SECRET`       | The secret for JWT             | Generated             |
| `CORE_SECRET`       | The secret for the core binary | Generated             |

### LLM provider (at least one)

| Variable                       | What it is                             |
| ------------------------------ | -------------------------------------- |
| `OPENAI_API_KEY`               | The OpenAI API key                     |
| `OPENAI_BASE_URL`              | The URL of an OpenAI-compatible API    |
| `OPENAI_API_TYPE`              | `native` / `compatible` / `openrouter` |
| `OPENAI_MODEL`                 | An explicit model name                 |
| `DEEPSEEK_API_KEY`             | The Deepseek API key                   |
| `ANTHROPIC_API_KEY`            | The Anthropic API key                  |
| `GOOGLE_GENERATIVE_AI_API_KEY` | The Google Generative AI API key       |
| `LITELLM_BASE_URL`             | The URL of a LiteLLM proxy             |
| `LITELLM_API_KEY`              | The LiteLLM API key                    |
| `OLLAMA_HOST`                  | The URL of an Ollama server            |
| `OLLAMA_HEADERS`               | Extra HTTP headers for Ollama. **Must not be set** - the service does not start; see [known-issues.md](known-issues.md) |

### Optional

| Variable                            | What it is                                                                                          | Default |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------- | ------- |
| `AUTH_TRUST_HOST`                   | The trusted host for auth                                                                             | `true`  |
| `AUTH_OPENID_ID`                    | The OpenID Client ID                                                                                  | -       |
| `AUTH_OPENID_SECRET`                | The OpenID Client Secret                                                                              | -       |
| `AUTH_OPENID_ISSUER`                | The OpenID Issuer URL                                                                                 | -       |
| `SQL_MODE`                          | Unlocks the **Enable SQL Mode** switch in the target form; without it the switch stays greyed out    | `false` |
| `MAX_PARALLEL_RUNS`                 | How many schedule runs may be in flight at once. Below `1` the service does not start                | `20`    |
| `TIMEOUT_FOR_RUNNING_SCHEDULE_SECS` | How long a run is given before it is ended and taken for dead (seconds). From `60` to `86400`         | `900`   |
| `CHAT_TURN_IDLE_TIMEOUT_SECS`       | How long a chat turn may produce nothing before it is taken as stopped (seconds). Counted between signs of life; waiting for someone to approve a command does not count | `900`   |
| `LLM_MAX_ATTEMPTS`                  | How many failures in a row a run may take when talking to the model provider (a refused connection, a 429 or 5xx, an answer cut off midway); every completed exchange resets the count. A whole number, at least `1` | `10`    |
| `LLM_RESPONSE_START_TIMEOUT_MS`     | How long to wait for a streaming answer to start before the attempt is retried (milliseconds). `0` waits indefinitely | `30000` |
| `CORE_PORT`                         | The port the core binary listens on inside the container. `docker-compose.yaml` points the web server at `3001` (`CORE_URL`), so change both together | `3001`  |
| `SYSTEM_PROMPT_ADD`                 | An addition to the system prompt                                                                      | -       |
| `SQL_SYSTEM_PROMPT_ADD`             | An addition to the SQL agent prompt                                                                   | -       |

### Monitoring (optional - logs and metrics)

| Variable                             | What it is                                                             | Default                  |
| ------------------------------------ | ------------------------------------------------------------------------ | ------------------------ |
| `VICTORIALOGS_URL`                   | The VictoriaLogs API URL                                                 | -                        |
| `VICTORIALOGS_TOKEN`                 | The VictoriaLogs bearer token                                            | -                        |
| `VICTORIALOGS_TLS_INSECURE`          | Allow self-signed certificates                                           | `false`                  |
| `VICTORIAMETRICS_URL`                | The URL of a Prometheus-compatible API                                   | -                        |
| `VICTORIAMETRICS_TOKEN`              | The VictoriaMetrics bearer token                                         | -                        |
| `VICTORIAMETRICS_TLS_INSECURE`       | Allow self-signed certificates                                           | `false`                  |
| `VICTORIAMETRICS_NODE_INFO_METRIC`   | The metric carrying the node role                                        | `spectrum_instance_role` |
| `VICTORIAMETRICS_LABEL_NODE_NAME`    | The name of the label carrying the node name                             | `node_name`              |
| `VICTORIAMETRICS_LABEL_CLUSTER_NAME` | The name of the label carrying the cluster name                          | `cluster_name`           |
| `VICTORIAMETRICS_LABEL_ROLE`         | The name of the label carrying the node role                             | `role`                   |
| `VICTORIALOGS_MAX_RESPONSE_BYTES`    | The response size limit of the built-in logs MCP server, in bytes        | `16384`                  |
| `VICTORIAMETRICS_MAX_RESPONSE_BYTES` | The response size limit of the built-in metrics MCP server, in bytes     | `16384`                  |

> Both size limits take a whole number of bytes. A value that is not one — `16k`, `32KB`, `auto` — stops the matching MCP server at startup with the reason on its error output, rather than being read as a smaller number.

> The variables in each pair are set together, and the pairs are independent: the VictoriaLogs pair opens the **Enable Log Access** switch, the VictoriaMetrics pair opens **Enable Metrics Access**. If only the URL is set and the token is not, the matching switch in the target form stays unavailable. If your VictoriaLogs or VictoriaMetrics runs without authorisation, still set the token to any non-empty value. The wizard accepts an empty token and then writes only the URL - add the token to `.env` by hand.

> Log and metric selectors (the node and cluster templates) are set per target in the **Targets** section, not through environment variables.

### Commands on the server (optional)

| Variable                    | What it is                                                            | Default |
| --------------------------- | ----------------------------------------------------------------------- | ------- |
| `LONG_READ_MAX_PER_TARGET`  | How many long reads may run on one target (1-20)                       | `3`     |
| `LONG_READ_TIME_LIMIT_SECS` | The time limit of a single long read, in seconds (60-86400)            | `14400` |
| `LONG_READ_DISABLED`        | `true` removes long reads from the agent                               | `false` |

> The ability to propose changing commands is not turned on by environment variables: it is set per target with the **Allow changes** switch plus the member's right.

### Other (optional)

| Variable                    | What it is                                                                | Default                                              |
| --------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------- |
| `WEBHOOK_MAX_PARALLEL_RUNS` | How many webhook investigations run at once                                 | `3`                                                  |
| `ALERT_RETENTION_DAYS`      | How many days a **closed** incident record is kept (1-3650); open records are never removed. A value outside that range stops the service | `90`                    |
| `ALERT_CLOSE_NEWS_RETRY_SECS` | How often, in seconds, the agent retries the news of an incident a monitor has called over, when that news did not reach the incident chat or Slack the first time (60-86400). Also the pause before the first retry of a Slack message, doubled after every further failure. Three times this value must be shorter than `ALERT_CLOSE_NEWS_MAX_AGE_HOURS`. A value outside that range stops the service | `300` |
| `ALERT_CLOSE_NEWS_MAX_AGE_HOURS` | How many hours after an incident was called over its news is still retried (1-168). A value outside that range stops the service | `24` |
| `MAX_CATCHUP_BYTES`         | The weight one connection may be handed when it joins an answer already being written (at least 8192). A value below that stops the service | `5242880`            |
| `WIDGETS_DISABLED`          | `true` removes the graphical widgets from interactive chats                 | `false`                                              |
| `PG_DOCS_ARTIFACT_PATH`     | The path to the PostgreSQL documentation pack inside the container          | `/app/docs/postgresql-docs.json`                     |
| `MCP_SERVERS_DIR`           | The directory holding the MCP servers inside the container                  | `/app/mcp-servers` (set in `docker-compose.yaml`)    |
| `LANGFUSE_HOST`             | The Langfuse URL for tracing the agent's work                               | -                                                    |
| `LANGFUSE_PUBLIC_KEY`       | The Langfuse public key                                                     | -                                                    |
| `LANGFUSE_SECRET_KEY`       | The Langfuse secret key                                                     | -                                                    |
| `LANGFUSE_DEBUG`            | Verbose trace output                                                        | `false`                                              |

## Installer exit codes

| Code | What it means                                    |
| ---- | ------------------------------------------------ |
| 0    | Success                                          |
| 2    | Argument error or cancellation                   |
| 10   | Package integrity error                          |
| 11   | Docker Engine not found                          |
| 12   | Docker Compose v2 not found                      |
| 13   | The images could not be obtained from the registry |
| 14   | Not enough disk space for the images             |
| 15   | Another installer run is already in progress     |
| 16   | The lock file could not be created or removed    |
| 20   | Execution error                                  |

## Troubleshooting

Below are failures of the installer and the stack. Failures of the application itself that already have a workaround are collected in [known-issues.md](known-issues.md).

### Docker not found

```
✖ Docker Engine not found
```

Install Docker following the [instructions](https://docs.docker.com/engine/install/).

### The port is taken

```
✖ Port 8080 is occupied
```

Free the port or choose another one during installation. To see what is holding the port:

```bash
ss -tlnp | grep 8080
```

### The images will not download

The installer names the cause for each case separately - there is no generic "no network".

- **That version is not in the registry** - code 13. Check the version number of the archive; the archive
  is built only after the image is published, so a mismatch means a broken or home-made build.
- **The registry will not serve the image** - code 13. Docker Hub answers the same way whether the image
  is missing or closed, so the message names both possibilities.
- **The download limit is exhausted** - code 13. Docker Hub limits the number of pulls without an account.
  Wait for the limit to reset or take the archive with the images (`…-offline.zip`).
- **The data stopped arriving** - code 13. The download was aborted after 10 minutes without a single new
  byte. Start it again: whatever was downloaded is not downloaded twice.
- **Not enough space** - code 14. Space is checked only for the missing images. If the Docker image
  directory is unreachable from this machine (the daemon lives in its own virtual machine), the installer
  says it cannot measure and carries on - it has no right to refuse over a value it cannot measure.

### Another run is already in progress

```
✖ Another xagent installer run is already in progress (process 1234, lock file /var/lock/xagent-installer.lock)
```

Code 15. Install, update and rollback take a shared lock - they must not change the stand at the same time.
Wait for the first run to finish. If that process no longer exists, the lock is taken over automatically.

Code 16 is a different case: something is wrong with the lock file itself, and the message says what.
The lock is left over from a run under a different user - delete the file as the user who owns it and
start the installer again.
The file could not be created at all - check the permissions on the `/var/lock` directory and start the
installer again.

### The installation broke off halfway

If the installation directory was created but the installation did not finish, a repeat `install` says so
outright and suggests what to do: check the contents of the directory, delete it and install again.
The `update` command will not help here - there is nothing to update yet.

### Integrity error

```
✖ Bundle integrity check failed
```

The ZIP was damaged in transit. Download it again and check `SHA256SUMS`.

### The container will not start

Check the logs:

```bash
cd /opt/xagent
docker compose logs xagent
```

Common causes:

- A wrong LLM API key → check `.env`
- PostgreSQL is not initialised yet → wait for the healthcheck (about 30 seconds)

### Sign-in says the service is unavailable

```
Sign-in is temporarily unavailable: your credentials could not be checked. This is not a problem with your password
```

The web server could not get an answer from the core, so the password was never checked. The cause is in
the logs (`docker compose logs xagent`), on a line starting with `[auth]`. The ending
`the shell and Core do not share the same CORE_SECRET` means the two halves of the agent hold different
`CORE_SECRET` values: check that `.env` sets `CORE_SECRET` once, with a non-empty value, and apply it with
`docker compose up -d`.
The first-run form reports the same cause with the message
`Setup could not be completed: the service refused the request before reading it`.

### The container is marked `unhealthy`

`docker compose ps` shows `xagent` as `unhealthy`. That means one of the agent's two halves - the core
(port 3001 inside the container) or the web server (port 8080) - has stopped answering, while its
process is still alive.

See which one it is and with what error:

```bash
cd /opt/xagent
docker inspect --format '{{range .State.Health.Log}}{{.End}} exit={{.ExitCode}} {{.Output}}{{end}}' xagent-xagent-1
```

A line like `core did not answer at http://127.0.0.1:3001/...` points at the core, a line
`web server did not answer at http://127.0.0.1:8080/...` points at the web server.

Then restart the service:

```bash
docker compose restart xagent
```

If a half of the agent has not merely gone quiet but exited, the container stops on its own and comes
back up under the restart policy - no intervention needed. The restart counter:

```bash
docker inspect --format '{{.RestartCount}}' xagent-xagent-1
```
