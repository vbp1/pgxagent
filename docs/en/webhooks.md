# Webhook integration

XAgent accepts alerts from external monitoring systems through webhooks. When an alert arrives, the agent opens an incident record, runs a playbook to investigate, and creates an incident chat with the results.

## How it fits together

```
┌─────────────────────┐     POST /api/projects/{id}/webhooks/{configId}/alerts
│   AlertManager      │ ──────────────────────────────────────────────────────►
│   (or another       │     Authorization: Bearer xagent_wh_xxxxx
│    system)          │
└─────────────────────┘
                                          │
                                          ▼
                              ┌───────────────────────┐
                              │     XAgent            │
                              │                       │
                              │  1. Check the token   │
                              │  2. Match the         │
                              │     hostname          │
                              │  3. Incident          │
                              │     record            │
                              │  4. Run the playbook  │
                              │  5. Create the chat   │
                              └───────────────────────┘
                                          │
                        ┌─────────────────┴─────────────────┐
                        ▼                                   ▼
            ┌───────────────────────┐          ┌───────────────────────┐
            │   Incident chat       │          │  Alerts section       │
            │   with the results    │          │  and a Slack message  │
            │   of the investigation│          │  (if configured)      │
            └───────────────────────┘          └───────────────────────┘
```

## Setup

### 1. Create a webhook configuration

1. Open your project in XAgent
2. Go to **Webhooks** in the side menu
3. Click **Add Webhook**
4. Fill in the settings:

   | Field                       | What it sets                                                                                                                                                            |
   | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | **Name**                    | A unique identifier (snake_case, for example `alertmanager_prod`)                                                                                                        |
   | **Playbook**                | The investigation playbook; `generalTroubleshooting` suits alerts well                                                                                                   |
   | **Model**                   | The LLM model that runs it                                                                                                                                               |
   | **Hostname Label**          | The AlertManager label carrying the database host name (`instance` by default)                                                                                           |
   | **Severity Label**          | The label carrying the alert severity (`severity` by default). An unfamiliar value is refined by the agent once the investigation is done                                 |
   | **Flap Window**             | A window in minutes (1-1440, 5 by default): if the same problem is reported again within that time after an all-clear, it goes back into the existing record instead of opening a new one |
   | **Notify Level**            | The lowest level from which a Slack notification is sent                                                                                                                 |
   | **Keep History**            | How many webhook runs to keep in the history (1-1000)                                                                                                                    |
   | **Max Steps**               | How many times the investigation may call other playbooks; allowed values are 1 to 50, and at 1 only the chosen playbook runs                                             |
   | **Additional Instructions** | Extra instructions for the playbook. The field cannot be left empty at creation - see [known-issues.md](known-issues.md)                                                  |
   | **Allow SQL diagnostics**   | Gives the investigation the database query tools. **On by default**; turn it off if the investigation must not touch the data                                             |
   | **MCP access**              | Which MCP servers the investigation can reach; always within what the webhook creator can reach                                                                           |
   | **Enabled**                 | Turns the webhook on and off                                                                                                                                             |

5. Click **Create Webhook**

### 2. Create an API token

1. On the webhook page find the **API Tokens** section
2. Click **Create Token**
3. Enter a name (for example, "AlertManager Production")
4. Copy the token right away: it is shown only once.

Token format: `xagent_wh_<64 hex characters>`

### 3. Get the webhook URL

The webhook URL is shown on the configuration page:

```
POST {PUBLIC_URL}/api/projects/{projectId}/webhooks/{configId}/alerts
```

### 4. Configure AlertManager

Add a webhook receiver to the AlertManager configuration:

```yaml
# alertmanager.yml
receivers:
  - name: 'xagent'
    webhook_configs:
      - url: 'https://your-xagent.example.com/api/projects/PROJECT_ID/webhooks/CONFIG_ID/alerts'
        http_config:
          authorization:
            type: Bearer
            credentials: 'xagent_wh_your_token_here'
        send_resolved: true

route:
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'xagent'
    - match:
        severity: warning
      receiver: 'xagent'
```

### 5. Hostname matching

The agent matches alerts to targets by host name. By default it uses the `instance` label from the alert.

**How it works:**

1. An alert arrives with labels (for example, `instance: "db-prod-01"`)
2. The agent takes the host name from the configured label
3. The agent looks for a target node whose saved machine name (the **Machine Name** field) equals that value - a fast index lookup within the project, **without** touching the databases themselves. If several watched databases carry that host name, the one added first is taken - see [known-issues.md](known-issues.md)
4. On a match the playbook runs on that target; for a cluster the investigation is bound to the node where the alert fired, with access to the context of the whole cluster

**Configuring the hostname label:**

- If your alerts use a different label (for example, `host`, `node`, `server`), change the **Hostname Label** field in the webhook configuration

**Make sure the target has a machine name:**

Matching uses the host name saved on the target (the **Machine Name** field), not a query to the database. It is set by hand when the target is created or edited - use the same name that arrives in the alert label (see the "Machine Name" section in quick-start.md).

## API reference

### Send an alert

Accepts alerts from AlertManager and starts a playbook run.

```
POST /api/projects/{projectId}/webhooks/{configId}/alerts
Authorization: Bearer xagent_wh_xxxxx
Content-Type: application/json
```

**Request body** (the AlertManager webhook format):

```json
{
  "version": "4",
  "groupKey": "{}:{alertname=\"HighCPU\"}",
  "status": "firing",
  "receiver": "xagent",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "HighCPU",
        "instance": "db-prod-01",
        "severity": "critical"
      },
      "annotations": {
        "summary": "High CPU usage detected",
        "description": "CPU usage is above 90% for 5 minutes"
      },
      "startsAt": "2024-01-15T10:00:00Z",
      "fingerprint": "abc123def456"
    }
  ]
}
```

**Response** (202 Accepted):

```json
{
  "received": 1,
  "runs": [
    {
      "runId": "uuid-xxx",
      "alertName": "HighCPU",
      "hostname": "db-prod-01",
      "status": "pending"
    }
  ],
  "skipped": []
}
```

- `received` - how many alerts arrived in the request
- `runs` - one entry per investigation that was created
- `skipped` - alerts that get no investigation; each entry carries `alertName`, `fingerprint` and `reason` (the reason texts are listed under "How alerts are handled")

**Errors:**

- `401 Unauthorized` - the token is missing or invalid
- `403 Forbidden` - the token does not belong to this configuration; the webhook is off; the creator is blocked or no longer a project member; or their role no longer allows working with targets and running playbooks (after a demotion to **viewer**, for example)
- `404 Not Found` - the webhook configuration was not found
- `400 Bad Request` - the payload format is invalid

### Check the status of a run

Checks the status of a webhook run and returns the incident chat URL.

```
GET /api/projects/{projectId}/webhooks/runs/{runId}
Authorization: Bearer xagent_wh_xxxxx
```

**Response**:

```json
{
  "runId": "uuid-xxx",
  "status": "completed",
  "alertName": "HighCPU",
  "alertFingerprint": "abc123def456",
  "hostnameReceived": "db-prod-01",
  "hostnameMatched": "db-prod-01",
  "chatId": "uuid-chat",
  "chatUrl": "https://agent.example.com/projects/xxx/chats/uuid-chat",
  "errorMessage": null,
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:05:00Z"
}
```

**Run statuses:**

- `pending` - waiting in the queue
- `running` - the playbook is running
- `completed` - finished successfully
- `failed` - something went wrong (see `errorMessage`)

### Test hostname matching (internal)

A dry run of hostname matching without running the playbook. Requires session authentication.

```
POST /api/projects/{projectId}/webhooks/{configId}/test
Content-Type: application/json

{
  "hostname": "db-prod-01"
}
```

**Response**:

```json
{
  "matched": true,
  "targetId": "uuid-target",
  "targetName": "Production DB",
  "targetNodeId": "uuid-node",
  "matchedHostname": "db-prod-01"
}
```

## How alerts are handled

Everything hangs on the **incident record** (the **Alerts** section). A record is opened once and closed once; further signals with the same `fingerprint` are appended to it instead of spawning new investigations. Records are visible in the **Alerts** section, and with Slack configured their opening and closing are posted to the channel.

### Firing alerts

1. The host name (the **Hostname Label** label) and the severity (the **Severity Label** label) are read from the alert
2. The host name is matched to a target node
3. A new incident record is opened for the `fingerprint` - or an already open one is confirmed, or a closed one is reopened if its all-clear came no earlier than **Flap Window** minutes ago
4. A new record gets an investigation: the configured playbook runs and an incident chat is created

What happens to repeat signals:

| Situation                                                              | The `skipped` reason                                                                        |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| The problem is already open                                            | `already recorded — the problem is still open`                                                |
| The problem came back within the flap window and already has an investigation | `recorded on the record it came back to — that record already has its investigation`     |
| The signal is older than a closed record with the same `fingerprint`   | `refused — this signal is older than the problem already settled under the same fingerprint`  |

A problem that comes back within the flap window is additionally reported to the channel and to the incident chat, so that an all-clear sent earlier does not stay the last word.

### Resolved alerts

A resolved alert closes the record. No new investigation is created, the response is `202 Accepted`, and the alert itself lands in `skipped` with a reason describing the outcome:

| Situation                                                             | The `skipped` reason                                                                       |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| The record is closed                                                  | `resolved - the record is closed`                                                            |
| An all-clear for this problem has already been received               | `resolved - this all-clear has already been recorded`                                        |
| The all-clear is about an earlier episode while the current one is open | `resolved - this all-clear is about an earlier spell of trouble; a later one is still open`  |
| Nothing was open under this `fingerprint`                             | `resolved - nothing was open under this fingerprint`                                         |
| The record is closed, but the problem itself was never reported to the channel | `resolved - recorded, though the problem itself was never reported`                  |

When a record is closed, a closing note is added to the incident chat and a message goes to Slack saying the problem is gone. The whole context of the incident stays in one chat.

## Concurrency control

The agent limits how many investigations run at once, so as not to overload the installation:

- By default: 3 investigations at a time; set by the `WEBHOOK_MAX_PARALLEL_RUNS` environment variable
- The limit counts across the whole installation, however many copies of the service are running
- The remaining alerts wait in the queue and are handled in the order they arrived

## Troubleshooting

### An alert does not start the playbook

1. **Check that the webhook is on** - a webhook that is off returns 403
2. **Check the token** - make sure the token belongs to this webhook configuration
3. **Check hostname matching** - use the Test button on the webhook page
4. **Look through the run history** - check the Runs table for errors

### No suitable target found

The host name in the alert must exactly match the host name (**Machine Name**) set on a node of one of your targets.

Steps to diagnose:

1. Check which host name AlertManager sends (look at the alert labels)
2. Make sure the hostname label setting matches the labels of your alerts
3. Use the Test feature to check hostname matching
4. Check the **Machine Name** field of the target in the **Targets** section - that is what the alert is matched against; set it to the same name that arrives in the alert label

### The token does not work

- A token is shown only once, at creation - if it is lost, create a new one
- Make sure the header format is right: `Authorization: Bearer <token>`
- The token must belong to the webhook configuration in the URL

## Testing with curl

You can check a webhook without AlertManager, with plain curl.

### What you need

1. Create a webhook configuration in the UI
2. Create an API token and copy it
3. Make sure the target has the **Machine Name** field set (see quick-start.md)
4. Use that same value as the host name in the test alert

### Set the environment variables

```bash
# Replace with your own values
export XAGENT_URL="http://localhost:4001"
export PROJECT_ID="your-project-uuid"
export WEBHOOK_CONFIG_ID="your-webhook-config-uuid"
export WEBHOOK_TOKEN="xagent_wh_your_token_here"
export DB_HOSTNAME="your-db-hostname"
```

**Where to find these values:**

- **PROJECT_ID**: in the URL when you view the project. Example: `/projects/550e8400-e29b-41d4-a716-446655440000/...` → the UUID after `/projects/`
- **WEBHOOK_CONFIG_ID**: go to **Webhooks** → click a configuration. The URL looks like `/projects/.../webhooks/6ba7b810-9dad-11d1-80b4-00c04fd430c8` → the last UUID. It is also shown on the configuration page.
- **WEBHOOK_TOKEN**: copied when a new token is created (shown only once). If it is lost, create a new one in the Tokens section.
- **DB_HOSTNAME**: the value of the **Machine Name** field on the target (the **Targets** section), or check it in the Test section on the webhook page.

### Send a test firing alert

The minimal payload (the other fields are generated automatically):

```bash
curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/alerts" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "firing",
    "alerts": [
      {
        "status": "firing",
        "labels": {
          "alertname": "TestAlert",
          "instance": "'"${DB_HOSTNAME}"'"
        }
      }
    ]
  }'
```

The full payload (every field spelled out):

```bash
curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/alerts" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "4",
    "groupKey": "{}:{alertname=\"TestAlert\"}",
    "status": "firing",
    "receiver": "xagent",
    "alerts": [
      {
        "status": "firing",
        "labels": {
          "alertname": "TestAlert",
          "instance": "'"${DB_HOSTNAME}"'",
          "severity": "warning"
        },
        "annotations": {
          "summary": "Test alert from curl",
          "description": "This is a manual test alert to verify webhook integration"
        },
        "startsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
        "fingerprint": "test-'"$(date +%s)"'"
      }
    ]
  }'
```

**Expected response** (202 Accepted):

```json
{
  "received": 1,
  "runs": [
    {
      "runId": "uuid-xxx",
      "alertName": "TestAlert",
      "hostname": "your-db-hostname",
      "status": "pending"
    }
  ],
  "skipped": []
}
```

### Check the run status

Copy the `runId` from the response and check the status:

```bash
export RUN_ID="uuid-from-previous-response"

curl "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/runs/${RUN_ID}" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}"
```

**The response once it finishes**:

```json
{
  "runId": "uuid-xxx",
  "status": "completed",
  "alertName": "TestAlert",
  "chatId": "uuid-chat",
  "chatUrl": "http://localhost:4001/projects/xxx/chats/uuid-chat"
}
```

### Send a resolved alert

To check how resolved alerts are handled (this adds a message to the existing incident chat):

```bash
# Use the same fingerprint as the firing alert
export FINGERPRINT="test-1234567890"

curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/alerts" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "4",
    "groupKey": "{}:{alertname=\"TestAlert\"}",
    "status": "resolved",
    "receiver": "xagent",
    "alerts": [
      {
        "status": "resolved",
        "labels": {
          "alertname": "TestAlert",
          "instance": "'"${DB_HOSTNAME}"'",
          "severity": "warning"
        },
        "annotations": {
          "summary": "Test alert resolved"
        },
        "startsAt": "2024-01-15T10:00:00Z",
        "endsAt": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
        "fingerprint": "'"${FINGERPRINT}"'"
      }
    ]
  }'
```

### Test hostname matching

Check whether a host name will be matched to a target, without running the playbook:

```bash
curl -X POST "${XAGENT_URL}/api/projects/${PROJECT_ID}/webhooks/${WEBHOOK_CONFIG_ID}/test" \
  -H "Content-Type: application/json" \
  -H "Cookie: your-session-cookie" \
  -d '{
    "hostname": "'"${DB_HOSTNAME}"'"
  }'
```

Note: the test endpoint requires session authentication (a browser cookie), not a token.

### Typical test scenarios

| Scenario                                  | Expected result                                                        |
| ----------------------------------------- | ---------------------------------------------------------------------- |
| Valid token, matching host name           | 202, a run is created                                                  |
| Invalid token                             | 401 Unauthorized                                                       |
| Valid token, wrong configuration          | 403 Forbidden                                                          |
| Webhook turned off                        | 403 Forbidden                                                          |
| Host name matches no target               | 202, a run is created but fails with "No usable target found"          |
| A repeat alert with the same fingerprint  | 202, the alert is skipped: the record is already open                  |
| An empty alerts array                     | 400 Bad Request                                                        |

## Execution context

When a playbook runs through a webhook, the agent works **as the person who created the webhook**:

- **Tools**: every AI tool (MCP servers, database queries, access to metrics and so on) uses the rights of the webhook creator
- **Chat ownership**: the incident chat belongs to the webhook creator
- **Access control**: the creator must be a project member with the matching rights

**What follows from this:**

1. If the webhook creator is removed from the project, or loses the right to work with targets and run playbooks, the webhook run fails
2. The creator's access to connected resources (MCP servers, cloud providers) sets what the agent can do
3. Incident chats show up in the creator's account

So a webhook grants no more rights than its creator has, the log shows who set up the automated actions, and rights work the same way as in an ordinary chat.

## Security

- Tokens are stored as SHA-256 hashes (never in the clear)
- Every token is bound to a single webhook configuration
- Webhooks that are off return 403 (not a silent skip)
- The payload is validated strictly against the AlertManager schema
- Every operation is subject to project-level access control
- **A webhook run uses the creator's rights** (see "Execution context")
