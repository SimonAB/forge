# PROJECT_TEMPLATE.md

Template README for new Forge kanban projects. Copy this into a new
project directory and fill in the fields below.

---

## Project Description

- **Name:** <Project name>
- **Column:** <Plan | Watch | Coding | Write | Review | Shipped | Paused>
- **Short description:** <One-line summary of the project's purpose and goal.>

---

## Kanban Column

| Field | Value |
|-------|-------|
| **Current Column** | `<Plan>` |
| **Workflow Tag** | `Plan 📐` |
| **Radar Bucket** | `<calm | watch | heat>` |
| **Next Action** | <What is the very next step? Make it concrete and actionable.> |
| **Next Action Due** | `<YYYY-MM-DD or "not set">` |

Transitioning projects through the kanban flow:

```
Plan → Watch → Coding → Write → Review → Shipped
```

Plus a pausable side-column:

```
<All columns> ← Paused → <Resume to Plan or Watch>
```

---

## Collaboration

| Field | Value |
|-------|-------|
| **Assignee** | `#<Person>` |
| **Collaborators** | `#<Person>`, `#<Person>` |
| **Delegate To** | `#<Person>` if delegated |
| **Contact** | <Email or communication channel> |
| **Notes** | <Any collaboration notes, dependencies, or agreements.> |

Add or remove `#Person` tags via the forge CLI:

```bash
forge project-tag add <Project> "#Halfan"
forge project-tag add <Project> "#Simon"
forge project-tag remove <Project> "#Halfan"
```

---

## Tag Reference

Forge uses Finder tags on project directories. The following table shows
the configured columns and meta tags in this Forge instance.

### Column Tags (from `config.yaml`)

| Column Name | Column Tag | Colour |
|-------------|-----------|--------|
| Plan | `Plan 📐` | 4 |
| Watch | `Watch 👁️` | 2 |
| Coding | `Coding 🦔` | 5 |
| Write | `Write ✅` | 6 |
| Review | `Review 📍` | 7 |
| Shipped | `Shipped 🚀` | 3 |
| Paused | `Paused ⏸️` | 1 |

### Meta Tags

| Meta Tag | Purpose |
|----------|---------|
| `URGENT ⚠️` | Flag a project as requiring immediate attention. |
| `Student 🎓` | Indicate a student project (supervision, mentoring). |

### Column Transitions

| From → To | Allowed |
|-------------|---------|
| Plan → Watch | Yes |
| Watch → Coding | Yes |
| Coding → Write | Yes |
| Write → Review | Yes |
| Review → Shipped | Yes |
| Any → Paused | Yes |
| Paused → Plan | Yes |
| Paused → Watch | Yes (rare) |
| Shipped → Paused | No |

### Forge CLI Commands

```bash
# View the board
forge board
forge board --json

# Move a project to another column
forge move <Project> <ColumnName>

# Manage meta / assignee tags
forge project-tag add <Project> "URGENT ⚠️"
forge project-tag add <Project> "#Halfan"
forge project-tag remove <Project> "URGENT ⚠️"
forge project-tag list <Project>

# Generate a brief
python3 scripts/forge-brief.py
```

---

## Notes

- Track progress in this README or in `TASKS.toml` within the project directory.
- Update the kanban column when the project moves to a new stage.
- Add `#Person` tags when work is delegated.
- Mark `URGENT ⚠️` when a project needs immediate attention (requires user approval).
- Use `forge board --json` to check `radarBucket`, `daysSinceActivity`, and `activitySource` for project health.
- Stale projects (≥7 days inactive) or in-flight stale (≥14 days in Watch/Coding/Write/Review) will be surfaced in briefs.
- Never invent Kanban column names, meta tags, or task IDs — always validate against `config.yaml` or `forge board --json`.
