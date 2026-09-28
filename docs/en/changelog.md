# What's new

## Version 0.6.1

A maintenance release: bug fixes and tighter access rules.

- Fixed bugs across alerts and webhooks, chat, scheduled checks, access rights, sign-in, the diagnostic tools, and the metric and log sources.

### What to watch for when upgrading

- **Alerts from a machine running several databases.** The agent no longer picks the oldest database on the machine. Set the new **Port Label** on the receiver to the alert label that carries the instance port. Without a port, such an alert is refused and the refusal says what to set. If the machine has only one database and the port in the alert does not match it, the alert is refused too. Standalone targets now have an **Instance Port** field. On first start the agent reads each standalone's port from its connection string. A port outside the valid range is refused; it is no longer replaced with 5432.
- **Settings that stop the service.** `MAX_PARALLEL_RUNS` now limits how many scheduled runs are in progress at once; the others wait in a queue. It must be a whole number of at least 1. `TIMEOUT_FOR_RUNNING_SCHEDULE_SECS` must be between 60 and 86400. `VICTORIALOGS_MAX_RESPONSE_BYTES` and `VICTORIAMETRICS_MAX_RESPONSE_BYTES` take a whole number of bytes. A value outside these rules stops the service at startup and names the setting.
- **Custom check scenarios.** `getConnectionsStats` and `getDeadlockCount` are gone: their data is now in `getConnectionsGroups` and `getTransactionStats`. The Google Cloud instance tool is now `getCloudSQLInstanceInfo`. A scenario that names the old tools has to be rewritten.

## Version 0.6.0

In this version the agent runs commands on the databases it watches with a person's approval, keeps incident records instead of a stream of identical messages, reads the PostgreSQL documentation, and tells project roles apart.

### What to watch for when upgrading

- **Member roles.** The old pair "owner / member" is replaced by four roles: owner, manager, operator, viewer. Everyone who was a member becomes an operator - day-to-day work does not change. Project settings (models, integrations, notifications, cloud keys) are now open to managers and owners. A person added without an explicit role becomes a viewer. Metrics and logs come with the role - to owners, managers and operators - while connected tools are still granted by name. Roles and access are described in full in [rbac.md](rbac.md).
- **Per-person access to individual targets** starts from a clean slate: if you had opened a specific database to specific people, grant that access again on the **Access** tab of the target.
- **Chats are created as shared.** A new chat used to be visible only to its author. It is now visible to the whole team by default, and you can hide it with a switch when you create it. Chats already saved as private stay private. Alert investigations and scheduled checks are always visible to the team. A chat is visible to whoever can see its database: a conversation about a private target is not shown to people that target was never opened to.
- **The installer archive is now two archives** - one with images and one without. Releases and the install script live in a public repository: the latest version can be downloaded and unpacked with a single command. Details in [install-guide.md](install-guide.md).
- **Custom check scenarios.** The search over a target's past is split into three separate tools - over conversations, over scheduled-check reports, and over incident records. A hand-written scenario that names the former single search by name has to be rewritten to the new names: `searchChatHistory`, `searchMonitoringRuns` and `searchAlertRecords`.
- The rough edges of this version are collected in [known-issues.md](known-issues.md).

### Commands on the server

- The agent can propose **one command that changes data**, and a person can allow or decline it right in the chat. The command runs in the background for as long as it needs, it is visible on the **Commands** tab of the target, and when it finishes the agent picks the conversation back up with the result.
- The feature is off by default: it is turned on with the **Allow changes** switch on a specific target, and only a person with the right to change data can allow commands. Irreversible commands ask for confirmation a second time.
- **Long read-only queries.** A fast read is capped at ten seconds; anything longer is now proposed to a person and, once allowed, runs to the end or up to the overall time limit. The answer is shown as a table.
- Either side can stop a running command; before it stops you see what is running, how long it has been running and who allowed it - with a plain warning that what is already done will not be undone.
- The command history for a target is paged and can be filtered by time, by who allowed the command, and by outcome.

### Incident records

- A problem the agent finds no longer turns into a stream of identical messages. It is opened **once**, confirmed while it lasts, and closed once - with a stated reason and a count of how many times it was seen.
- Every record has a timeline of events, comments from people, and a link to the investigation.
- There is a new **Alerts** section: tiles by severity, grouping by target, and a separate view of closed records. In the side menu the counter is broken down by severity, and clicking it opens the list already narrowed to that level.
- Slack messages are sent once per record - when it opens, when its severity rises, and when it closes. The model's report arrives in the channel as readable text with a link to the full investigation.
- A closed record is kept for a bounded time - 90 days by default, set by `ALERT_RETENTION_DAYS`. An open record is never deleted, at any age.

### Investigating signals from monitoring systems

- Investigations are now **queued**: receiving a signal only records the work and answers immediately, while worker processes run it under a shared concurrency limit. Restarting the service no longer loses an investigation that has started - it continues in the same chat.
- **A flapping problem gets one investigation, not one per firing.** A problem that comes back within the flap window (5 minutes by default, configurable in the receiver form) is attached to the existing record.
- If an investigation never started, the reason is saved and visible in the list - instead of a permanent "pending".
- The **Keep History** setting on a receiver bounds how many investigations are kept. Only those whose work is over and whose trouble is settled for good count as history: an unfinished investigation, and a record that can still come back, stay where they are. A monitor that sends no all-clears keeps its records open, so the limit never bounds it.

### Access rights and the activity log

- Four built-in roles and a catalogue of 21 rights; a single person can be given an exception on top of their role - for four rights: ordinary read-only queries, changing data, their own private targets, and their own private chats.
- The project **Settings** section is rebuilt: a **Members** tab with the list of members and what each of them can actually do, a member panel, a **Roles** tab, and people search when adding someone.
- Every target has its own **Access** tab: publish it to the whole project or open it to named people.
- **A project activity log** for owners and managers: who changed what, in plain sentences, with the original entry available on expand.
- Scheduled checks and alert investigations re-check the rights of whoever created them: work created by a person who has been demoted to viewer no longer runs.
- **An account's display name can be corrected.** The **Admin** section, open to the installation admin, now edits the name of an existing account. A name in any script works: a non-Latin name no longer makes the interface unusable. An account that signs in through an external identity provider takes its name from there at every sign-in, so the field is closed and the reason is stated in the dialog.

### Watching target health

- One status vocabulary for single databases and clusters: **Checking** (not checked yet), **Healthy**, **Degraded** (answers, but is not healthy), **Unreachable** (nobody answered), **Rejected** (the server refused the connection). A refused connection and a missing server are now told apart - they are different faults with different owners.
- Row status updates **live**: a row is redrawn as soon as its own check finishes, and a stuck check does not hold up the rest. A check that takes too long turns yellow.
- A green dot means "we reached the database": status is written from the agent's ordinary work, without extra probes.
- On the project list every project now has its own database health indicator with the number of problem targets.
- A target whose host name cannot be resolved to an address reads as **Unreachable** - such a check used to end with no verdict at all.

### Clusters

- The replication mode and the synchronous state of every replica are visible.
- The **Refresh topology** button really does refresh the cluster map.
- Any member of a Patroni cluster works as a switchover point.

### What the agent knows

- **The PostgreSQL documentation inside the installation** (versions 14-18) is now available in full: a table of contents, reading a page in parts, and exact string search with as many neighbouring lines as you need. The answer is always given for the version being asked about; if that version is not in the installation, the agent declines and lists the ones it has.
- The agent remembers the PostgreSQL version of every node and since when it has been that version.
- **The version upgrade readiness check** is rewritten: it works from the documentation rather than from rules for one release baked into the text, and it goes through to the end - a step that cannot be done automatically ends up in the report as a task for a person.
- **Search over saved monitoring reports**: the agent finds what it needs in past checks and opens the match in full.
- **Agent notes** are stored one per note, with an author and an edit time, are searched by text, and changes to shared notes go into the project log. Personal notes are closed to automated runs.
- In the chat history you can open a matched message and expand which tools it called.
- **What is open on a target right now**: the agent lists the incident records that are still open, with a tally per severity, and reads them page by page - no need to guess the words to search for. It sees the investigation behind a record and can search inside one chosen conversation.

### Settings recommendations

- Every proposed value names its source: whether the tool computed it from the machine it measured, or the agent composed it from a server reading, which it names.
- Machine facts are never inferred. When the amount of memory could not be read, the values that depend on it are not given, and the missing reading is named.
- The advice in the built-in playbooks has been checked against a live server: whether a setting needs a restart is taken from the server itself, and query-plan analysis says when a plan was built from generic parameters and why a plan could not be obtained.

### Chatting with the agent

- **A dropped connection no longer breaks the conversation**: the page survives losing the live connection and catches up on what it missed.
- The agent's question is addressed to whoever holds the turn; everyone else sees how it ended without answering for them.
- A pending question can be answered from the chat command list - even if the page was opened after the question was asked.
- Long lines in database output wrap instead of running off to the side.
- A message sent while the agent is answering lands in the chat after that answer, not before it.
- A refusal from the model provider is shown in its own words, not as a retelling.
- Charts and diagrams are drawn when a person holds the turn, including inside an alert investigation.
- A conversation with a reasoning model no longer goes quiet after a background command.
- **An answer being written right now shows on every open of the chat** - from another device, in another tab, and after a page reload; an answer that started while the page was closed is caught up in full.
- A turn ends on silence, not on elapsed time: while an answer keeps writing, or while a question stands in front of a person, the turn is not cut. The silence window is `CHAT_TURN_IDLE_TIMEOUT_SECS`, 15 minutes by default.

### Metric and log sources

- The tool set is built from the source's own descriptions instead of being rewritten in the agent's code: adding a second metric or log source no longer means edits in every place.
- The source's answer is checked against a contract on both sides - anything that does not match the contract is reported as a failure instead of being passed off as a finding.
- A time range in a log query that cannot be parsed is now **rejected with an explanation** instead of being replaced with the last hour.
- Turning a source off on the MCP servers page closes access to it immediately, including for an investigation already under way.

### Reliability and speed

- Connections to the control database are returned to the pool instead of being torn down.
- The limits on concurrent calls to the model provider now take effect, and a failed call is retried.
- Connection checks run in parallel; the schedules page opens without waiting for the full list of targets; the chat list is paged on the database side.
- The container shuts down as a whole if one of its halves stops, instead of carrying on at half strength.
- The interface, the actions and the automated runs show the real reason for a failure.
- The application image is smaller; unused indexes were removed from the control database.

### Branding and legal

- The product has its own mark and logo.
- The full text of the Apache-2.0 licence is restored and the origin of the project is described.
