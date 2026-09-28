# Targets: architecture and reference

A reference for the **Targets** model: what a target is made of and how it is configured.

---

## What a target is

A **target** is a monitored object: one PostgreSQL database or a whole cluster. One target describes one monitored object in full, including database access, rights (privacy and owner), labels for metrics and logs, and connection security settings.

### Target types

| Type                | What it is                                                                                                        | Where nodes and roles come from                                                                   |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| **Standalone**      | A single PostgreSQL database                                                                                       | One node; roles are not needed                                                                        |
| **Generic Cluster** | A cluster on any replication or failover software (repmgr, pg_auto_failover, Stolon, Pacemaker/PAF, manual switchover) | You list the nodes; the role of each node is read **straight from PostgreSQL** (`pg_is_in_recovery()`) |
| **Patroni Cluster** | A cluster managed by Patroni                                                                                       | Nodes and roles are **discovered automatically** through the Patroni REST API (`/cluster`)             |

The type is set at creation and **does not change** later - to change the type, create the target again.

---

## The node model: three independent address "planes"

A cluster node has three address-like properties that **must not be mixed up** - they serve different purposes and can differ from each other:

| Plane                 | Fields                        | What it is for                                                                                                                                        |
| --------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Identity**          | `nodeName`                    | The stable key of the node (the Patroni member name or your own label). Everything is stitched together by it across topology refreshes; it survives a change of address and of role |
| **Address for the agent** | `connectHost` / `connectPort` | Where the agent **actually reaches** the database. It can differ from what Patroni reports (the cluster often sits in a separate network)               |
| **Host name for labels**  | `hostname` / `port`           | The `{{hostname}}` label in metric and log selectors, and the identity used to match webhooks. It can differ from both `nodeName` and `connectHost`     |

Why one shared host cannot describe a cluster: the agent has to reach **every** node separately (the role of each, the settings of each, the metrics of each), so the address is always **per node**. A cluster's shared credentials (user, password, database) **carry no host**.

**Node address override.** The address for the agent (`connectHost`/`connectPort`) is prefilled at discovery, but it can be edited. The edit is saved as a permanent override (bound to `nodeName`) and **survives rediscovery and even removing and re-adding the node** - useful when the agent and the cluster sit in different networks.

**Ports.** Every port a target carries is a whole number from 1 to 65535; any other value is refused on save, and the form names the field to correct. A cluster node declared without a port gets 5432. A standalone target takes its port from the connection string, read the way the driver dials it (5432 when the string names none); the **Instance Port** field of the target form sets it by hand where the monitor reports a different port than the agent dials - a connection pooler in front of the instance, for example. Within a project, two nodes cannot share the same machine name and port.

---

## Monitoring labels (selectors)

So that the agent knows which charts and logs belong to a target, the target carries **selectors** - query templates for your monitoring system. They are configured right in the target form (the **Monitoring Labels** block), with a live preview.

### Placeholder

Templates support **one** placeholder, `{{hostname}}`, which expands to the node's host name. It is the only token that expands; if a template has a typo or an unknown placeholder (`{{port}}`, `{{cluster}}` and so on), saving is rejected with the offending field named. The hint under the **Cluster-level selector** field suggests `{{cluster}}` - a template like that cannot be saved.

> Single curly braces (in LogsQL, for example) are left alone - only the paired `{{…}}` form is treated as a placeholder.

### Selector fields

| Field                                                        | What it sets                                                                                                                                  | Example                                                        |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `metricsNodeSelectorTemplate` (**Metrics node selector**)    | The base node label for metrics (PromQL)                                                                                                        | `node_name="{{hostname}}"`                                     |
| `metricsNodeSelectorRules` (**Per-prefix rules**)            | Refinements by metric name prefix (an array of `{prefix, template}`)                                                                            | `[{ prefix: "node_", template: "_node_id=\"{{hostname}}\"" }]` |
| `logsStreamSelectorTemplate` (**Logs stream selector**)      | The log stream (LogsQL)                                                                                                                         | `hostname:{{hostname}} AND app_name:postgresql`                |
| `metricsClusterSelectorTemplate` (**Cluster-level selector**) | The cluster-level label for metrics (clusters only). Saved for the future: cluster-level metric queries are not driven by it yet                | `cluster_name="{{hostname}}"`                                  |

Per-prefix rules let different metric families use different labels. When a query is built, the rule with the **longest matching prefix** wins; if none matches, the base node template is used.

### Selector Presets

So that you do not have to type templates by hand for every target, there are **presets** - on the **Selector Presets** page (a settings group in the side menu).

- **Built-in** presets are read-only. Three of them ship with the product:

  | Preset            | Node label (metrics)       | Log stream                                      |
  | ----------------- | -------------------------- | ------------------------------------------------- |
  | **Spectrum**      | `node_name="{{hostname}}"` | `hostname:{{hostname}} AND app_name:postgresql`   |
  | **Node Exporter** | `instance="{{hostname}}"`  | `hostname:{{hostname}}`                           |
  | **pgwatch**       | `host="{{hostname}}"`      | `host:{{hostname}}`                               |

- **Your own** presets can be created, edited and deleted; they show up in the dropdown of the target form.

**A preset is copied as a snapshot.** When you apply a preset, its values are copied into the target fields. Changing the preset later does **not** change targets that are already configured. The link to the preset is kept only as a note about where the values came from.

### Live check

The **Monitoring Labels** block gives you two ways to see the result:

- **Preview** - statically shows what the template expands to for a sample host name.
- **The check button** - sends a real query to VictoriaMetrics/VictoriaLogs with the expanded selector and reports whether it found any data. This catches a typo in a label right away.

---

## What the agent is allowed to do on this target

Two independent switches in the target form. Both are off until someone turns them on: reading data and changing it are different decisions, and they are made about the database itself.

| Switch              | What it opens                                                                                                | The second condition                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Enable SQL Mode** | Queries against table data, and long read-only queries that do not fit the usual time limit                   | The member's right to run queries (`operator`, `owner`); the switch itself is unlocked only when `SQL_MODE=true` is set in `.env` |
| **Allow changes**   | The agent may **propose** a command that changes data or configuration; it runs after a person clicks         | The member's right to approve changes (`operator`, `owner`)                                                                       |

Neither switch alone gives the agent a tool: both halves are needed - the target setting and the person's right in the project. An irreversible command is confirmed twice, a running one can be stopped, and the command history with its output is kept on the **Commands** tab of that target.

---

## The target page

| Tab          | What is on it                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------ |
| **Overview** | Target status or the cluster map: nodes, roles, replica lag                                     |
| **Settings** | The target form: connection, host name, selectors, TLS, access switches                         |
| **Data**     | The collected performance and vacuum settings per node, with differences highlighted            |
| **Commands** | Commands the agent proposed on this target: the text, who approved, the output, the result      |
| **Access**   | Which project members this target is available to                                               |

---

## Connection security (TLS)

The database and the Patroni REST API have **independent** TLS settings (you can verify the database certificate but not Patroni's, and the other way round).

### Database (`Database Security (TLS)`)

| Setting                       | What it means                                                                                                                                       |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **SSL Mode**                  | `disable` (no encryption) · `require` (encrypt, do not verify) · `verify-ca` (verify the chain) · `verify-full` (verify the chain and the host name) |
| **CA certificate**            | The PEM of the root or corporate CA used to verify the server certificate; empty ⇒ system CAs                                                       |
| **Client certificate**        | The PEM for mutual authentication (mutual TLS)                                                                                                      |
| **Client key**                | The PEM key - a **secret** (masked, access by rights)                                                                                               |
| **Verify Server Certificate** | A switch: explicitly turn off verification of the server certificate (encryption without verification)                                              |

These settings apply to standalone targets and to clusters alike (clusters have no connection string, so the mode is stored in its own field).

### Patroni REST API

The same set for the REST client: `http://` vs `https://` (from the URL scheme), system CA / your own CA / no verification, and authentication of none / basic / client certificate (mTLS). A Patroni running with `verify_client: required` refuses even a read of `/cluster` without a client certificate, so mTLS is mandatory to connect to such clusters.

---

## Clusters: discovery, roles, topology

### Node discovery

- **Patroni** - the system calls `GET {patroniApiUrl}/cluster`, extracts the members, their addresses and roles, and creates the nodes automatically. The address for the agent is prefilled from the answer and stays editable.
- **Generic Cluster** - you list the nodes yourself (address and port of each). Optionally you can ask the agent to **suggest** standbys: it connects to the primary you named, reads `pg_stat_replication` and offers the connected replicas. This is a best-effort hint (it sees only the currently connected replicas, returns the `client_addr` IP, and misses cascading or disconnected nodes) - membership is still yours to decide.

### Roles along two axes

A node carries **two independent roles**, which usually agree but diverge during a switchover and during a split brain:

- **`pgRole`** - what PostgreSQL **actually** is right now: `primary` (`pg_is_in_recovery() = false`, accepts writes) or `standby` (in recovery). It is read straight from the live node and marked with `roleConfirmed`.
- **`clusterRole`** - what the orchestrator says: `leader` (holds the leader lock in the DCS), `replica`, `sync_standby`, `standby_leader`, `quorum_standby`. The source is Patroni `/cluster`. A generic cluster has none (there is no lock).

`pgRole` is confirmed against PostgreSQL **even when the API is available** (a cross-check) and remains the **only** source of the role when the API is not - which is common precisely during an incident.

### Special states

- **Split brain.** Two PostgreSQL primaries under one `leader`. The legitimate primary is the one with `clusterRole = leader`; any other node with `pgRole = primary` is a stuck or fenced primary that did not demote in time. A generic cluster has no leader, so a split brain shows up only as "2 or more reachable primaries" without naming the legitimate one.
- **Standby cluster.** A cluster replicating from an external upstream **legitimately** has no `primary` at all (its leader is a `standby_leader`, itself in recovery). This is a valid topology, not an error.

### Topology refresh

The cluster map is refreshed by several triggers: on scheduled monitoring runs, in the background when a chat starts (the chat opens immediately on the saved map), and **lazily** - when a cluster tool runs and the data is stale. The staleness threshold is no shorter than the cluster TTL (Patroni serves `/cluster` from the DCS cache anyway, usually around 30 s). For Patroni, a refresh adds new nodes and **removes** nodes that have been missing from `/cluster` for several checks in a row (with a delay to guard against flapping); for a generic cluster, membership is **not** touched automatically - nodes stay until you remove them.

### Timeouts

Every connection to a node and every call to the Patroni API is time-limited, and nodes are polled independently: one unreachable node spoils only its own status and **never hangs** the refresh of the whole topology. A host name that does not resolve is reported together with the host and port the agent was dialing, so the error says which node it is about.

---

## Collecting schema information

The cache of database information (tables, extensions, settings) is stored per node:

- "Replicated" categories (tables, extensions) are collected **once from the primary**.
- "Per-node" categories (performance and vacuum settings) are collected **from every node** - that is how configuration differences between nodes become visible.

The cache is disposable: it is deleted together with the node.

---

## Matching webhooks

An alert is matched to a target by the node's **saved** machine name (the **Machine Name** field) - a fast index lookup within the project, without touching the databases themselves. In the usual "one database per host" case the host name is unique and the match is unambiguous. Nodes are distinguished by the `(hostname, port)` pair: where one machine hosts several watched databases, the webhook's **Port Label** supplies the port that picks one of them, and without a usable port the investigation is refused with a message saying how many databases share the machine and what to set. An alert port that differs from the registered port is refused as well, even when the machine carries a single database. For a cluster, the investigation is bound to the node where the alert fired, with access to the context of the whole cluster. For more, see [webhooks.md](webhooks.md).

---

## Rights and secrets

Access to a target comes from three things: the member's role in the project, the visibility of the target itself, and individual grants.

**Project member roles** (the project **Settings** section) are Owner, Manager, Operator and Viewer. A new member gets the Viewer role until someone assigns another one. The role sets the default set of actions; for a specific member it is narrowed by exceptions - including how much of the project's shared targets they reach. The full "what each role can and cannot do" table, the chat-visibility rules and how tools are granted are in [rbac.md](rbac.md).

**Target visibility** is `public` (visible to every project member) or `private` (visible to the owner and to people granted it by name, on the **Access** tab). Only a **public** target can be the default target, so that the default value works for every member.

Five fields are stored as **secrets** (masked on the wire, revealed by rights, audited on break-glass): the standalone connection string, the cluster database password, the Patroni API password, and the two client TLS keys (database and Patroni).

Deleting a target is **blocked** while monitoring schedules point at it, so that monitoring is not wiped out by an accidental click, and while a command the agent proposed on it is still waiting, running, or has an outcome not yet reported.

---

## See also

- [Quick start](quick-start.md)
- [Webhooks and alert matching](webhooks.md)
