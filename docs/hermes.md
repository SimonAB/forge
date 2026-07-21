# Hermes + Forge (local assistant)

Forge recommends **[Hermes Agent](https://hermes-agent.nousresearch.com/)** with **[Ollama](https://ollama.com)** for privacy-first LLM-assisted kanban work. Inference stays on your Mac; Forge does not send board data to any Forge-hosted service.

## Privacy first

| Surface | What leaves your Mac |
|---------|----------------------|
| `forge board`, `forge-brief.py` | Nothing (no LLM) |
| **Forge.app → Brief** | Board/calendar summary to the URL you configure (use loopback Ollama only for local-only) |
| **Hermes + Ollama** | Prompts/responses to your local Ollama instance when configured for a loopback provider |
| **Cursor (optional)** | Depends on your Cursor model settings — use Hermes for sensitive board/OmniFocus work |

**Strict local-only checklist:**

1. Ollama serving **local** models only (not Ollama Cloud).
2. Hermes `model.provider` → custom Ollama at `http://127.0.0.1:11434/v1`.
3. `fallback_providers: []` in `~/.hermes/config.yaml`.
4. Brief base URL → `http://127.0.0.1:11434/v1` (or leave default).

Forge has **no telemetry**. LLM egress is entirely under your control.

## Requirements

- macOS 14+
- [Ollama](https://ollama.com) running (menu bar app or `ollama serve`)
- [Hermes Agent](https://hermes-agent.nousresearch.com/docs/guides/local-ollama-setup) installed
- `forge` on `$PATH` (Forge → Preferences → Install CLI…)
- A tool-capable local model sized to your RAM (e.g. `qwen3-coder`, `qwen3.6` coding variants)

## Quick setup (plug-and-play)

From your Forge directory:

```bash
python3 scripts/setup-hermes-forge.py
```

This script (idempotent):

- Adds `{forge-home}/.hermes/skills` to `skills.external_dirs` in `~/.hermes/config.yaml`
- Optionally creates `~/.cursor/mcp.json` from `packaging/hermes/cursor-mcp.sample.json` if missing
- Verifies Ollama, Hermes, `forge`, and the `forge-board` skill

Flags: `--dry-run`, `--forge-home PATH`, `--skip-cursor-mcp`, `--verify-only`.

**Forge.app:** Preferences → **Hermes** tab → **Check setup** / **Run setup in Terminal**.

## Verify

```bash
python3 scripts/setup-hermes-forge.py --verify-only
hermes skills list | grep forge-board
forge status
python3 scripts/forge-brief.py | head
```

Start Hermes in your Forge directory:

```bash
cd ~/Documents/Forge   # or your Forge home
hermes
/skill:forge-board
```

Ask for a read-only brief first; approve any column or tag changes explicitly.

## Daily use

| Task | Tool |
|------|------|
| Morning board scan (no LLM) | `python3 scripts/forge-brief.py` |
| URGENT / stale triage, proposed moves | Hermes + `/skill:forge-board` |
| Quick narrative brief in the app | Forge → Preferences → Brief → Ollama |
| Code edits | Cursor (or your editor) |

Hermes follows the same approval gates as `AGENTS.md`: reads are safe; `forge move` and `forge project-tag` need your confirmation.

## Cursor complement

Cursor excels at in-repo coding. Hermes handles sensitive board context locally.

Optional MCP bridge (after setup):

```json
{
  "mcpServers": {
    "hermes": {
      "command": "hermes",
      "args": ["mcp", "serve"]
    }
  }
}
```

See `packaging/hermes/cursor-mcp.sample.json`. Restart Cursor after adding `~/.cursor/mcp.json`.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `forge-board` not in `hermes skills list` | Re-run `python3 scripts/setup-hermes-forge.py`; restart Hermes |
| `forge` not found | Preferences → General → Install CLI… |
| Ollama unreachable | Start Ollama; confirm `curl http://127.0.0.1:11434/api/tags` |
| Hermes config missing | Run `hermes setup`, then setup script again |
| General health | `hermes doctor` |

## Lighter alternative: Pi

For a minimal terminal coding agent (no full Hermes stack), see **Ollama with [Pi](https://github.com/badlogic/pi-mono)** in [`PRIVACY.md`](../PRIVACY.md#ai-assistants). Forge remains agnostic; Hermes is recommended for kanban skills and autonomous board workflows.

## See also

- [`AGENTS.md`](../AGENTS.md) — assistant operating manual
- [`.hermes/skills/forge-board/SKILL.md`](../.hermes/skills/forge-board/SKILL.md) — skill reference
- [`docs/app.md`](app.md) — Brief and Hermes preferences tabs
