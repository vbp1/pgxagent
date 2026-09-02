# Roles and access

Who may do what in a project: member roles, access to targets, chat visibility and how tools are granted.

---

## What access is made of

Three quantities, each answering its own question:

| Quantity              | The question it answers                     | Where it is set                              |
| --------------------- | ------------------------------------------- | -------------------------------------------- |
| **Member role**       | What this person may do in the project       | **Settings → Members**, the member card       |
| **Target visibility** | Who can see this target at all               | The target card: `public` or `private`        |
| **Individual grant**  | Who this particular target is opened to      | The **Access** tab of the target              |

The role answers "may they at all", the other two answer "reaching what". Both sides are needed: a right without access to the target does nothing, and access to a target without the right does nothing either.

---

## The roles

| Role         | What it is for                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------ |
| **Owner**    | Everything, unconditionally. Deletes the project and hands ownership on                                  |
| **Manager**  | Runs the project and its people: targets, playbooks, schedules, webhooks, tools, settings                |
| **Operator** | Works with the databases: chats, playbooks, queries. No project settings, no member management           |
| **Viewer**   | Reads and joins the discussion: sees targets, dashboards and shared chats. Starts no agent work          |

A new member gets the **Viewer** role until someone assigns another one.

### What each role can and cannot do

| Action                                            | Owner | Manager    | Operator   | Viewer |
| ------------------------------------------------- | :---: | :--------: | :--------: | :----: |
| **Targets**                                       |       |            |            |        |
| See targets, dashboards and monitoring             |  ✅   |     ✅     |     ✅     |   ✅   |
| Open a database and run agent work against it      |  ✅   |     ✅     |     ✅     |   ❌   |
| Add and edit the shared targets of the project     |  ✅   |     ✅     |     ❌     |   ❌   |
| Create private targets                             |  ✅   |     ✅     |     ❌     |   ❌   |
| **Chats**                                         |       |            |            |        |
| Read chats                                         |  ✅   |     ✅     |     ✅     |   ✅   |
| Write to the people in a chat, without the agent   |  ✅   |     ✅     |     ✅     |   ✅   |
| Start a conversation with the agent                |  ✅   |     ✅     |     ✅     |   ❌   |
| Take their own chats out of the project view       |  ✅   |     ✅     |     ❌     |   ❌   |
| **Working with data**                             |       |            |            |        |
| Run SQL queries                                    |  ✅   |     ❌     |     ✅     |   ❌   |
| Approve a command that changes data or settings    |  ✅   |     ❌     |     ✅     |   ❌   |
| **Automation**                                    |       |            |            |        |
| Run playbooks                                      |  ✅   |     ✅     |     ✅     |   ❌   |
| Create and edit playbooks                          |  ✅   |     ✅     |     ✅     |   ❌   |
| Manage monitoring schedules                        |  ✅   |     ✅     |     ✅     |   ❌   |
| Manage webhooks and their tokens                   |  ✅   |     ✅     |     ✅     |   ❌   |
| Close and comment on incident records              |  ✅   |     ✅     |     ✅     |   ❌   |
| **Tools**                                         |       |            |            |        |
| Use metrics and logs                               |  ✅   |     ✅     |     ✅     |   ❌   |
| Use connected tools (MCP servers)                  |  ✅   | when granted | when granted |  ❌  |
| Choose the project's tool set                      |  ✅   |     ✅     |     ❌     |   ❌   |
| **Project**                                       |       |            |            |        |
| Project settings: models, integrations, notifications | ✅ |     ✅     |     ❌     |   ❌   |
| Add members and change their roles                 |  ✅   |     ✅     |     ❌     |   ❌   |
| Read the project action log                        |  ✅   |     ✅     |     ❌     |   ❌   |
| Delete the project, transfer ownership             |  ✅   |     ❌     |     ❌     |   ❌   |

Three things the table does not show:

- **A Manager does not run queries themselves.** They set up the project and its people; the databases are the Operator's work. When one person needs both, the right is given to them as a personal exception - see below.
- **An Owner cannot silently open somebody else's private target.** They see it and may open access to themselves in the open, but that is a separate action and it is written to the log.
- **A Viewer may write a message to the people** in a shared chat - that is joining the discussion, not starting agent work.

### Personal exceptions

The role sets the defaults, and for one member they can be narrowed or widened. The member card carries four switches - run queries, approve changing commands, create private targets, hide their own chats - and two access levels: to targets and to tools.

Until a switch is touched it shows the role's value and follows the role. Once set by hand it stays with the person and survives a change of role.

---

## Access to a target

**Visibility** comes in two kinds:

- `public` - a shared target of the project, visible to every member;
- `private` - visible to its creator and to whoever it was granted to by name on the **Access** tab.

Only a public target can be the default one, so that the default works for every member.

**Opening a database and working with it** is allowed in three cases, and any one of them is enough:

1. it is the member's own private target;
2. the target was granted to them by name on the **Access** tab;
3. it is a shared target of the project and the member's access level is "every shared target".

A grant works whatever the visibility: that is how a private target is opened to named people without publishing it to the whole project.

**The target access level** narrows the third case only. "Every shared target" opens the project's shared targets, the other values do not; a member's own targets and the ones granted by name stay reachable under every level. For Owner, Manager and Operator the level defaults to "every shared target".

**Seeing a target is a weaker right than using it.** A member sees the project's shared targets, their own and the ones granted to them in the lists, even when the level does not let them work with those targets.

---

## Chat visibility

Three conditions must hold before a member sees a chat. If any one fails, the chat does not exist for them: not in the list, not by a direct link.

1. **They are a member of the project.**
2. **The chat is shared or their own.** Somebody else's hidden chat is not visible; its author reads it, and an Owner through a separate action that is written to the log.
3. **The database the chat is about is visible to them.** A conversation is as closed as what it is about: a chat about a shared target is visible to the project, one about somebody else's private target is not.

A chat with no target at all is visible to the project. For a chat about a deleted target the answer depends on what the target was at deletion time: shared - it stays with the project, private - with its author and the Owner.

Alert investigations and scheduled checks are the project's record of what the system did, so they are always shared and cannot be hidden.

---

## Tools

Tools come in two kinds, and the access rule differs.

**Metrics and logs** are part of the product. Everyone entitled to use tools gets them: Owner, Manager and Operator. They need no separate grant.

**Connected tools (MCP servers)** are everything else: the third-party sources and systems you connected yourself. Such a tool may reach a system that has nothing to do with PostgreSQL and may carry credentials of its own, so by default it goes to nobody but the Owner - it is granted deliberately.

Access to a tool is checked at three tiers, and all three must pass:

1. the tool is enabled in the installation - the **MCP** section of the side menu, available to the installation administrator;
2. the tool is enabled in the project - **Settings → Roles**, the **Project tools (MCP)** card; enabling it here makes it available to everyone it is granted to in this project;
3. the member reaches the tool - the tool access level on their member card.

The tool access level governs connected tools only. "None" means "no connected tools"; metrics and logs remain. To keep somebody from those as well, they need a role that works with no tools - **Viewer**.

The check runs before every call to a tool, so a revoked access takes effect at once, including inside an investigation already under way.

---

## Automated runs

Scheduled checks and alert investigations hold no rights of their own - they run under the rights of the person who created them, and those rights are re-checked before every run:

- a **scheduled check** runs under the rights of the schedule's creator;
- an **alert investigation** runs under the rights of the webhook's creator, narrowed further by the webhook's own setting.

Two consequences follow. If the creator is demoted to Viewer or removed from the project, their schedules and webhooks stop running rather than carrying on from memory. And conversely: a webhook's setting can only narrow its creator's rights, never widen them.

---

## What goes into the log

The project log (**Settings → Audit**, available to Owner and Manager) records the actions that concern rights and access: role changes, granting and revoking access to targets and tools, and also revealing a target's secrets and an owner reading somebody else's private chat.

---

## See also

- [Targets: architecture and reference](targets.md)
- [Webhooks and alert matching](webhooks.md)
- [Quick start](quick-start.md)
