# REST API for integrations

An outside system works with XAgent through the REST API `/api/v1` as a **service account**: it manages projects, databases, webhooks and schedules, and reads chats, alerts and investigations.

## Where the description is

The API description is open without signing in to XAgent:

- `https://<XAgent address>/api/docs` — the Swagger UI page with every operation;
- `https://<XAgent address>/api/docs/openapi.json` — the same document as OpenAPI 3.1, for a client generator or Postman.

The **OpenAPI** entry of the XAgent side menu opens that page.

## The key

Every request carries the service account's key in the header `Authorization: Bearer xagent_sa_…`. Signing in to the XAgent UI does not open the API, and a service account cannot sign in to the UI.

An installation administrator issues the key under **Admin › Service accounts**:

1. **Create service account** — a new account.
2. Rights: system roles of the account, or membership in projects with a role, the same as for a person (see [`rbac.md`](rbac.md)).
3. **Issue key** — pick its lifetime: 30 days, 90 days, 1 year (the default) or no expiry. The key is shown once: copy it right away.

A key that expires within 30 days is marked in the list. A key no longer needed is revoked with **Revoke key**: the next request with it gets `401`.

## The first request

From Swagger UI: press **Authorize**, paste the key, open an operation and press **Try it out**. The request goes to this installation.

From the command line (`-k` is for the installation's self-signed certificate):

```bash
curl -k -H "Authorization: Bearer <key>" "https://<XAgent address>/api/v1/me"
```

The answer names the account the key belongs to.

## Answers

- Errors come as problem details (`application/problem+json`, RFC 9457).
- Times are ISO 8601 in UTC with `Z`.
- Lists take `limit` (1-200, default 50) and `cursor` and answer `{ data, nextCursor }`.
- `401` — no key, or the key is revoked or expired.

## Note writer events

An alert’s timeline can contain `kind: "note_writer"`: the background note writer finished processing the closed alert. Its `message` reports notes written, nothing new, a skip or an error, without model-generated reasons. Detailed reasons are available only through the source-authorized writer view, which also checks every recorded read source. This is a service entry; `user` is null. Clients must accept this kind and display an unfamiliar kind as an ordinary timeline entry. The entry remains after the writer’s source and trajectory are removed after 90 days.

## How to turn it off

The setting `PUBLIC_API_ENABLED=false` in `.env.production` (see [`install-guide.md`](install-guide.md)) turns the API off: requests to `/api/v1` get `503`, the description page and the document `404`, and the **OpenAPI** entry disappears from the menu. Alerts keep arriving at the `/api/projects/...` addresses with the API off. Applied on restart of `xagent-core`.
