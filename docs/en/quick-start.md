# Quick Start Guide

Once XAgent is installed and running, set it up with the steps below.

## 1. Create a project

1. Open the web interface: `http://<host>:<port>` (port `8080` by default)
2. Click **Create Project**
3. Fill in:
   - **Project Name** - any name you like (for example, `production`)
   - **Resource Provider** - `Other`
4. Click **Create**

## 2. Set up the models

Go to **Models** (project side menu).

1. Click **Probe** next to the available models - XAgent checks the connection and the supported capabilities (Tool Calling, Structured Output, Reasoning)
2. Turn on the models you need with the switch in the **Enabled** column
3. Mark one model as **Default** - it is used for new chats and for monitoring jobs

> **Tip**: set the model context window in the **Context Window** field: `120k`.

## 3. Connect a database

### Preparation on the PostgreSQL side

Before you add a target, prepare the PostgreSQL server.

#### 1. Create a user and grant privileges

```sql
-- Create a dedicated user
CREATE USER xagent WITH PASSWORD '<strong_password>';

-- Read system statistics (pg_stat_activity, pg_locks, pg_settings,
-- pg_stat_replication, pg_stat_wal and others)
GRANT pg_monitor TO xagent;

-- Read data from user tables (PostgreSQL 14+)
-- Needed for: reading pg_stats (column statistics), EXPLAIN on queries,
-- table structure analysis, data sampling, SQL Query SubAgent
GRANT pg_read_all_data TO xagent;
```

> **Restricted access**: instead of `pg_read_all_data` you can grant access to specific schemas, but that limits what the agent can do:
>
> ```sql
> GRANT USAGE ON SCHEMA public TO xagent;
> GRANT SELECT ON ALL TABLES IN SCHEMA public TO xagent;
> ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO xagent;
> ```
>
> With that setup the following stop working: EXPLAIN on queries against other schemas, column statistics (`pg_stats`) outside the allowed schemas, and the SQL Query SubAgent for tables outside the allowed schemas.

#### 2. Set up the pg_stat_statements extension

The `pg_stat_statements` extension is **required** - without it the agent cannot analyse slow queries or build execution plans by queryId.

Add this to `postgresql.conf`:

```ini
shared_preload_libraries = 'pg_stat_statements'
```

> After changing `shared_preload_libraries`, PostgreSQL must be **restarted**.

Then create the extension in the target database:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Optionally, for a more precise index bloat analysis:

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
```

#### 3. Machine Name

To match a target with its logs (VictoriaLogs), metrics (VictoriaMetrics) and alerts (Webhooks), XAgent uses the **machine name** - the **Machine Name** field of the target. Set it by hand when you add or edit the target: this is the name the server publishes its logs and metrics under (usually the host FQDN, for example the output of `hostname -f`). The field is optional - you can leave it empty and fill it in later; until it is set, logs and metrics are not matched for that target.

> **PostgreSQL cluster**: if you run a cluster (Patroni, Pacemaker/Corosync, repmgr and so on), you have two options. For full monitoring of every node, add a target of type **Patroni** (nodes and roles are discovered automatically) or **Generic Cluster** (you list the nodes yourself) - see [targets.md](targets.md). If you only care about the current primary, it is simpler to create a **standalone target pointing at the VIP address** and bound to the primary role: the agent always works with the current primary, even after a failover or switchover. The machine name is set by hand for every cluster node as well.

> **PostgreSQL 15**: the `EXPLAIN (GENERIC_PLAN)` option is available from PostgreSQL 16 on. On PostgreSQL 15 the agent cannot build plans for parameterised queries from `pg_stat_statements` (queries with `$1`, `$2`, ...), but it says so instead of breaking.

### Add a target to XAgent

1. Go to **Targets** → **Add New Target**
2. Leave the type as **Standalone** (a single database) and fill in:
   - **Target Name** - the target name (for example, `prod-primary`)
   - **Connection String** - the connection string: `postgres://xagent:<password>@<host>:5432/<database>`
3. XAgent then:
   - Checks the connection
   - Collects information about the database (tables, extensions, settings)

> Besides a single database you can add a **cluster** (Generic or Patroni). For more on the target model, see [targets.md](targets.md).

## 4. Set up monitoring (optional)

Go to **Monitoring** → **Add Schedule**.

Schedule settings:

| Setting                | What it means                                                                                                                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Database**           | Pick a target from the list                                                                                                                                      |
| **Playbook**           | The analysis scenario (for example, `generalTroubleshooting`)                                                                                                    |
| **Model**              | The LLM model that runs it                                                                                                                                       |
| **Schedule Type**      | `cron` (a fixed schedule - visual builder or a hand-written cron expression) or `automatic` (the agent picks the next run time itself, within a min/max interval) |
| **Time Range**         | How far back logs and metrics are analysed (`15m`, `1h`, `6h`, `24h`, `7d`, `30d`)                                                                               |
| **Notification Level** | Notification level: `info`, `warning`, `alert`                                                                                                                   |

Problems the agent finds become **incident records** in the **Alerts** section. A record is opened once and closed once - a later run that finds the same problem appends a confirmation to the existing record instead of opening a new one. A record is always closed with a stated reason: the problem is gone, the level dropped below the notification threshold, a person closed the record, the source was deleted (schedule, target or webhook), or the investigation never reached a conclusion. If Slack is configured for the project (the **Notifications** section), opening and closing a record is posted to the channel.

### Run a playbook by hand

There are two ways to run a playbook:

1. **From the UI**: in the **Playbooks** section click the run button next to the playbook, then pick a target and a model
2. **From the chat**: open a chat, pick a target and a model, then type `Run playbook generalTroubleshooting`

The agent works through every step of the playbook and shows the result.

### Write your own playbook

1. Go to **Playbooks** → **Create Playbook**
2. Fill in:
   - **Name** - the playbook name (Latin letters, no spaces, for example `proactiveHealthCheck`)
   - **Description** - what it is for
   - **Content** - step-by-step instructions for the agent (in English)
   - **Allow Non-Interactive** - turn this on if the playbook will be used by schedules and webhooks
3. Click **Save**

An example playbook: [example-playbook-proactive-health-check.md](example-playbook-proactive-health-check.md)

## 5. Slack notifications (optional)

Go to **Notifications** (project side menu).

1. Create an Incoming Webhook in Slack for the channel you want
2. Paste its URL into the field on the page and save

From then on the agent posts to the channel when it opens and when it closes an incident record. The link in the message opens the record in the **Alerts** section.

## 6. Set up webhooks (optional)

On an alert from AlertManager, the webhook runs an investigation playbook on its own.

Full instructions: [webhooks.md](webhooks.md)

## 7. Commands on the server (optional)

By default the agent only reads the database. If you want it to be able to **propose** a command that changes data or configuration, turn that on explicitly:

1. **Targets** → the target → **Settings** → the **Allow changes** switch
2. The person who approves commands needs the **operator** or **owner** role (roles are set in **Settings** → the **Members** tab)

How it works in practice:

1. The agent shows a card in the chat with the command text, a risk rating (`none` / `reversible` / `irreversible`) and an explanation of what is at stake
2. A person clicks **Run** or **Decline**; an irreversible command asks for confirmation twice
3. The command runs on the server and survives closing the tab; a running command can be stopped with **Cancel**
4. Every command on the target, with its output and result, is visible on the **Commands** tab of that target

Only one changing command runs on a target at a time.

**Long reads.** A heavy query that does not fit the usual time limit (a count over a large table, a report over the whole history) is proposed by the agent through the same approval card. Such a query holds a data snapshot open, so the database cannot clean up old versions of rows that changed - on a busy table that means visible growth of the table and its indexes, and the card warns about it. Long reads are available when the target has **Enable SQL Mode** turned on and the person has the right to run queries (the **operator** or **owner** role). The **Enable SQL Mode** switch itself stays greyed out until `SQL_MODE=true` is set in `.env`. The number of concurrent long reads per target and their time limit are set by the `LONG_READ_MAX_PER_TARGET` (3 by default) and `LONG_READ_TIME_LIMIT_SECS` (4 hours by default) environment variables, and `LONG_READ_DISABLED=true` removes the feature entirely.

## Check that it works

Once everything is set up, make sure it works:

1. **Chat**: open a chat with the agent and ask about the state of the database, for example: _"Show me the current load on the database"_
2. **Monitoring**: if you configured a schedule, wait for the first run and check the result in the **Monitoring** section
3. **Target**: in the **Targets** section, make sure the target status is **Healthy**

## What the agent does besides analysis

- **PostgreSQL reference inside the installation** - the image ships with the official PostgreSQL 14-18 documentation. The agent searches it and quotes pages, answering for the version that runs on your server. If the server version is not known yet, the agent asks for it instead of answering for a different one.
- **Clusters** - Patroni and clusters built on other replication software: node roles, replica lag, settings that differ between nodes. See [targets.md](targets.md).
- **Memory per target** - the agent keeps notes about the project and its databases and searches past chats and monitoring runs for that target, so a new session does not start from a blank page.
- **Incident records and Slack notifications** - the **Alerts** section, and messages to the channel when a record is opened and closed.
- **Commands with human approval** - when the switch is explicitly turned on (see section 7 above).
- **Working together in a chat** - several people from the project can take part in one chat; messages are handled one after another, and you can see who is in the chat right now.
- **The answer is produced on the server** - generation is not tied to the tab: you can close or reload the page and come back to the full answer. An answer being written right now shows on every open of the chat, from another device too. A dropped connection is restored, and what was missed is caught up from history.

## Limits

- **Changes only with human approval** - the agent never changes the database on its own: it analyses and proposes. It can propose a changing command only if the target has the **Allow changes** switch turned on, and the command runs only after a person clicks. Everything else (restarting services, editing `postgresql.conf`, actions at the OS level) is done by hand.
- **Vanilla PostgreSQL only** - the agent does not know about forks (Postgres Pro, Tantor and others). All recommendations and analysis are based on what standard PostgreSQL offers.
- **No backup strategy analysis** - the agent sees the state of WAL archiving, but it does not review backup schemes (pg_basebackup, pgBackRest, WAL-G) or judge whether they fit.
- **No notification providers other than Slack** - there is no built-in delivery to Telegram, email or Mattermost.
- **No ticketing integration** - the agent cannot create tasks in Jira or other ticketing systems. Problems it finds have to be filed by hand.
- **Only the documentation pages shipped in the image** - PostgreSQL versions outside 14-18 and external sources (articles, extension documentation, forks) are not available to the agent.

These are product properties, meant to be that way. Bugs in the current version and the workarounds for them are tracked separately: [known-issues.md](known-issues.md). What is new in this version is in [changelog.md](changelog.md).
