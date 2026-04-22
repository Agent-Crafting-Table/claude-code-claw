# claude-code-claw

A full-featured starter kit for running a personal AI ops agent powered by **Claude Code CLI** inside Docker. Includes Discord integration, a cron scheduler, persistent memory, and a self-healing restart loop — everything you need to go from zero to a running agent in under an hour.

## What you get

- **Always-on Claude Code session** — runs in Docker via tmux, auto-restarts on exit
- **Discord integration** — your agent listens and replies in your Discord server via the [fleet-discord](https://github.com/Agent-Crafting-Table/fleet-discord) MCP plugin
- **Slash commands** — `/status`, `/model`, `/herc <message>` work out of the box
- **Cron scheduler** — schedule tasks as natural language prompts; Claude executes them on schedule
- **Persistent memory** — structured markdown memory system your agent writes to and reads from
- **Model switching** — swap between Claude models at runtime without restarting the container

## Prerequisites

- Docker + docker-compose installed on your host
- A Claude Max subscription (uses OAuth, not API tokens — no per-token billing)
- A Discord bot token and application ID ([create one here](https://discord.com/developers/applications))

## Quick start

```bash
git clone https://github.com/Agent-Crafting-Table/claude-code-claw
cd claude-code-claw
cp config/.env.example config/.env
# Edit config/.env with your tokens
docker-compose up -d
```

Then authenticate Claude Code once:

```bash
docker exec -it claude-code-agent bash
claude  # follow the OAuth flow, then Ctrl+C
exit
docker-compose restart
```

Your agent is now running and connected to Discord.

## Architecture

```
claude-code-claw/
├── Dockerfile              # Node 22 + Claude Code CLI + tmux
├── docker-compose.yml      # Container definition + volume mounts
├── start.sh                # Entrypoint — launches tmux session with 3 windows
├── restart-loop.sh         # Supervises the Claude session, resumes on restart
├── config/
│   └── .env.example        # All required environment variables
├── scripts/
│   ├── cron-runner.js      # Reads crons/jobs.json, fires jobs on schedule
│   ├── discord-slash-handler.js  # Handles Discord slash command interactions
│   ├── discord-slash-register.js # Registers slash commands with Discord API
│   └── discord-post.js     # Utility — posts a message to a Discord channel
├── crons/
│   ├── jobs.json           # Cron job definitions
│   └── logs/               # Per-job log output
├── memory/
│   ├── AGENT.md            # Your agent's identity and session init instructions
│   └── active-threads.md   # What's currently in flight
└── data/
    └── current-model.json  # Active model (read by restart-loop on each start)
```

### tmux windows

| Window | Name | What runs |
|--------|------|-----------|
| `claude:0` | `bash` | Interactive Claude Code session |
| `claude:cron` | `cron` | `cron-runner.js` — scheduled jobs |
| `claude:slash` | `slash` | `discord-slash-handler.js` — slash command listener |

```bash
# Attach to main agent session:
docker exec -it claude-code-agent tmux attach -t claude:0

# Watch cron runner:
docker exec -it claude-code-agent tmux attach -t claude:cron
```

## Identity layer

Your agent's personality and context live in six files at the workspace root. Fill these in before your first run — they're loaded every session and shape everything your agent does.

| File | Purpose |
|------|---------|
| `SOUL.md` | Core personality, values, communication style, boundaries |
| `IDENTITY.md` | Name, role, vibe, emoji |
| `USER.md` | About you — name, preferences, context |
| `TOOLS.md` | Your specific setup — servers, channels, repos, services |
| `HEARTBEAT.md` | What to check during scheduled proactive runs |
| `MEMORY.md` | Long-term memory index (keep under 40 lines; details go in `memory/references/`) |

Each file ships as a blank template. Fill them in, commit them, and your agent reads itself into being every session.

**Rule of thumb:**
- Who the agent *is* → `SOUL.md`
- How the agent *presents* → `IDENTITY.md`
- Who *you* are → `USER.md`
- How to *operate* → `AGENTS.md` (in `memory/`)
- What tools/infra exist → `TOOLS.md`
- What to check proactively → `HEARTBEAT.md`

## Configuration

### `config/.env`

| Variable | Required | Description |
|----------|----------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Yes | Claude Max OAuth token — from `~/.claude.json` after logging in |
| `DISCORD_BOT_TOKEN` | Yes | Discord bot token |
| `DISCORD_APP_ID` | Yes | Discord application ID |
| `DISCORD_GUILD_ID` | Yes | Your Discord server ID |
| `DISCORD_CHANNEL_ID` | Yes | Default channel for agent replies |
| `AGENT_TIMEZONE` | No | Cron timezone (default: `UTC`) |

**Important**: Do NOT set `ANTHROPIC_API_KEY`. This kit uses Claude Max OAuth — setting an API key overrides it and bills your API account per token.

### Customizing your agent

Edit `memory/AGENT.md` to define your agent's identity, behaviors, and session init instructions. This file is read at the start of every Claude session.

### Adding cron jobs

Edit `crons/jobs.json`. Each job is a natural language prompt sent to Claude on schedule:

```json
{
  "id": "my-daily-summary",
  "name": "Daily Summary",
  "enabled": true,
  "schedule": "0 9 * * *",
  "tz": "UTC",
  "timeoutSeconds": 120,
  "message": "Post a brief summary of yesterday's activity to Discord channel 123456789."
}
```

### Slash commands

Register your slash commands once:

```bash
docker exec claude-code-agent node /workspace/scripts/discord-slash-register.js
```

Available commands:

| Command | Description |
|---------|-------------|
| `/status` | Health check — uptime, memory, cron status |
| `/model [name]` | Show or set the Claude model (opus / sonnet / haiku) |
| `/herc <message>` | Send an arbitrary prompt to your agent |
| `/cron list` | List enabled cron jobs |
| `/cron run <id>` | Manually trigger a cron job |

## Model switching

Models are stored in `data/current-model.json`. The restart loop reads this file on each restart.

```bash
# Switch to opus:
docker exec claude-code-agent sh -c 'echo "{\"model\":\"opus\"}" > /workspace/data/current-model.json'
docker exec claude-code-agent tmux send-keys -t claude:0 C-c ''

# Or use /model opus in Discord
```

| Alias | Model |
|-------|-------|
| `sonnet` | claude-sonnet-4-6 (default) |
| `opus` | claude-opus-4-6 |
| `haiku` | claude-haiku-4-5 |

## Health checks

```bash
# Is the tmux session alive?
docker exec claude-code-agent tmux has-session -t claude && echo "OK" || echo "DOWN"

# Tail the agent session:
docker exec claude-code-agent tmux capture-pane -t claude:0 -p | tail -20

# Tail cron runner:
docker exec claude-code-agent tmux capture-pane -t claude:cron -p | tail -20
```

## Recovery

```bash
# Quick restart (no rebuild):
docker-compose restart

# Full rebuild:
docker-compose down && docker-compose build --no-cache && docker-compose up -d
```

## Related repos

These smaller Agent-Crafting-Table libraries are used as building blocks:

- [fleet-discord](https://github.com/Agent-Crafting-Table/fleet-discord) — Discord MCP plugin (multi-agent routing)
- [discord-streaming](https://github.com/Agent-Crafting-Table/discord-streaming) — Lightweight Discord plugin with live status updates
- [mcp-self-reload](https://github.com/Agent-Crafting-Table/mcp-self-reload) — MCP server restart-loop pattern
- [evolution-loop](https://github.com/Agent-Crafting-Table/evolution-loop) — Agent self-improvement via Reflexion diffs

## License

MIT
