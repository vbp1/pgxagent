# Known issues

This page collects what you can run into in the current version of XAgent, and what to do about it. The list grows as issues are found and is updated with every release.

## Installation and configuration

### The `OLLAMA_HEADERS` variable must not be set

If you set `OLLAMA_HEADERS` in `.env`, the service does not start: the value is read as an object, while the environment delivers a string.

**What to do:** leave this variable unset. Extra HTTP headers for Ollama cannot be configured in the current version; if Ollama requires an authorisation header, put a reverse proxy in front of it that adds the header.

### The `TZ` variable in `.env` shifts when schedules fire

The next run time is stored in UTC, but before it is compared with the current time the offset of the container's time zone is added to it. By default the container runs on UTC, the offset is zero, and everything lines up. If you set `TZ` in `.env`, schedules start firing earlier or later than the time you set, by exactly that offset. The next-run column still shows the time you set: it is the firing that drifts.

**What to do:** do not set `TZ` in `.env`. The time zone of the host itself has no effect on schedules, so there is no need to change it.

## Accounts and sign-in

### A service failure during sign-in looks like a wrong password

If the core does not answer, or answers with an error, the sign-in page says "invalid login or password" - that is, it blames the credentials instead of the real cause.

**What to do:** if sign-in suddenly fails with a password you know is right, look at `docker compose logs xagent` before you change the password.

## Scheduled monitoring

### Changing a schedule while it is running does not stick

The settings a run works from are read when the run starts, and at the end of the run the "enabled" flag and the next run time are written back from that reading. A check you turned off mid-run keeps running on schedule, and a new due time you set mid-run is replaced when the run finishes.

**What to do:** change a schedule while no run is in progress, and check the switch and the next-run column again after the current run finishes.

### A long run is ended before it finishes

`TIMEOUT_FOR_RUNNING_SCHEDULE_SECS` (900 seconds by default) is how long a run is given before it is taken for dead. A run that reaches the limit is ended, recorded as a failed run and counted towards the schedule's failure streak, so a heavy playbook on a large database can keep failing without ever writing a report.

**What to do:** for heavy playbooks, raise `TIMEOUT_FOR_RUNNING_SCHEDULE_SECS` to the time they actually need. The lowest value the service accepts is 60 seconds.

### A time range that cannot be parsed is replaced with the default

If a schedule is created through the API, the analysis time range is not validated: a value in a format that cannot be parsed is silently replaced with the playbook default (usually `1h`), and the report says nothing about the substitution. In the interface the **Time Range** field is a dropdown, so an unparseable value cannot be entered by hand.

**What to do:** when you create a schedule through the API, write the range the same way the interface lists it (`15m`, `1h`, `6h`, `24h`, `7d`, `30d`), or as a full date such as `2026-08-27T10:00:00Z`. If a check covered a different period than the one you set, check how the range is spelled.

## Webhooks

### The value 0 in the "Max Steps" field cannot be saved

The field accepts 0 and is labelled as the way to stop the investigation from moving on to other playbooks, but on save the setting is rejected: allowed values are 1 to 50.

**What to do:** leave it at 1 - the investigation runs the chosen playbook and does not call others.

### With several databases on one host name, the alert goes to the oldest one

Matching is done by host name only, ignoring the port and the rest of the alert labels. If one machine hosts several watched databases, the investigation runs on the one that was added first.

**What to do:** for machines with several databases, give the nodes different **Machine Name** values and send that same value in the alert label.

## Interface

### When the connection drops, the menu counters silently show stale numbers

The number badges next to the **Alerts** item keep showing the last value they read, with nothing to say the update failed. The **Alerts** page itself does warn about it with a red line; the menu does not.

**What to do:** if the numbers look suspiciously frozen, open the **Alerts** page and see whether it warns about a failed update.

### Stopping an answer is drawn as a failure

If you click **Stop** while the agent is answering, a red error bar appears under the answer even though nothing broke.

**What to do:** the bar after your own **Stop** can be ignored: the part of the answer that was already saved stays in the chat.
