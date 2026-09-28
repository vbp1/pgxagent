# Known issues

This page collects what you can run into in the current version of XAgent, and what to do about it. The list grows as issues are found and is updated with every release.

## Installation and configuration

### The `OLLAMA_HEADERS` variable must not be set

If you set `OLLAMA_HEADERS` in `.env`, the service does not start: the value is read as an object, while the environment delivers a string.

**What to do:** leave this variable unset. Extra HTTP headers for Ollama cannot be configured in the current version; if Ollama requires an authorisation header, put a reverse proxy in front of it that adds the header.

## Scheduled monitoring

### A new interval saved during a run applies from the run after next

A run plans the next due time from the settings it started with. If you change the interval or the cron expression while a run is in progress, the next run is still planned by the old settings, and the new ones take effect from the run after it. The on/off switch takes effect at once.

**What to do:** change the interval while no run is in progress. If you changed it mid-run, check the next-run column after the run finishes and, if the time is not the one you expect, save the schedule once more.

### Deleting a schedule can fail without a message

If the service refuses to delete a schedule, the settings screen stays as it was, with the delete confirmation still open, and says nothing about the refusal.

**What to do:** if pressing delete does not take you back to the list of schedules, reload the page, check whether the schedule is still there, and look at `docker compose logs xagent` for the reason.

### A long run is ended before it finishes

`TIMEOUT_FOR_RUNNING_SCHEDULE_SECS` (900 seconds by default) is how long a run is given before it is taken for dead. A run that reaches the limit is ended, recorded as a failed run and counted towards the schedule's failure streak, so a heavy playbook on a large database can keep failing without ever writing a report.

**What to do:** for heavy playbooks, raise `TIMEOUT_FOR_RUNNING_SCHEDULE_SECS` to the time they actually need. The lowest value the service accepts is 60 seconds.

### A time range that cannot be parsed is replaced with the default

If a schedule is created through the API, the analysis time range is not validated: a value in a format that cannot be parsed is silently replaced with the playbook default (usually `1h`), and the report says nothing about the substitution. In the interface the **Time Range** field is a dropdown, so an unparseable value cannot be entered by hand.

**What to do:** when you create a schedule through the API, write the range the same way the interface lists it (`15m`, `1h`, `6h`, `24h`, `7d`, `30d`), or as a full date such as `2026-08-27T10:00:00Z`. If a check covered a different period than the one you set, check how the range is spelled.

## Interface

### When the connection drops, the menu counters silently show stale numbers

The number badges next to the **Alerts** item keep showing the last value they read, with nothing to say the update failed. The **Alerts** page itself does warn about it with a red line; the menu does not.

**What to do:** if the numbers look suspiciously frozen, open the **Alerts** page and see whether it warns about a failed update.

### Stopping an SQL chat while it picks a schema is drawn as a failure

In an SQL chat that has no schema chosen yet, the agent first picks the schema to work in. If you click **Stop** at that moment, an error bar appears instead of the usual note that the answer was interrupted.

**What to do:** the bar after your own **Stop** can be ignored; ask the question again when you are ready.

### A failed read of the target list shows an empty list

If the **Targets** page cannot read the list of databases, it shows no rows and zeros on the summary tiles, with no message about the failure.

**What to do:** if the list is suddenly empty, reload the page; if it stays empty, look at `docker compose logs xagent`.

### The target creation window locks when the check after creation fails

Adding a standalone database takes three steps in one window: create the record, check the connection, collect facts about the database. If the service does not answer the connection check (for example, the network dropped or the session expired), the window stays in its busy state and cannot be closed. The database record is already created at that point.

**What to do:** reload the page. The new database is in the **Targets** list with its connection status.

### Times on screen use the browser's time zone

The time zone chosen in the user menu reaches the agent: it uses that zone for times in its answers. Dates and times on the pages themselves - the last check of a target, the last and next run of a schedule, and so on - are shown in the browser's time zone.

**What to do:** keep the time zone in the user menu the same as the browser's, or read the times on the pages as the browser's local time.
