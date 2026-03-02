# obsidian-git-backup-docker

A Docker image that syncs an Obsidian vault via obsidian-headless and backs it up to git automatically.

## Project overview

Read `docs/spec.md` for the full specification. In short:

- Runs `obsidian-headless` to sync one Obsidian vault
- Watches for filesystem changes (inotify, not polling)
- Commits and pushes to a git remote on every sync
- Optionally generates commit messages with an LLM (Ollama / OpenAI / Anthropic)

## Architecture decisions

All architecture decisions are recorded in `docs/adr/`. Use `docs/adr/0000-template.md` as the template. Assign the next sequential number.

## Session history

Session summaries live in `docs/sessions/{number}.md`. Check existing files there to determine the next number.

## IDE MCP

This project uses the **PyCharm** MCP tools (prefixed `pycharm_*`), not WebStorm. Always prefer PyCharm MCP tools when interacting with the IDE.

## Standards

- **Docker**: Follow linuxserver.io conventions — s6-overlay, clear layer separation, non-root runtime where possible, well-documented environment variables.
- **Shell**: POSIX sh unless bash is explicitly required. Use `set -euo pipefail`. Handle errors. Clean up with traps.
- **Naming**: Environment variables use `OBSIDIAN_GIT_` prefix. Consistent and intuitive.
- **Commits**: Small, atomic, conventional-commit style (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`). Commit as you work, not at the end.

## Agent workflow

The primary build agent must:

1. Commit work continuously in small atomic increments while working.
2. Before ending a session, request reviews from all three subagents (`@linux-expert`, `@ux-designer`, `@obsidian-expert`) and address their feedback.
3. Record any architecture decisions in `docs/adr/`.
4. Write a session summary in `docs/sessions/`.
