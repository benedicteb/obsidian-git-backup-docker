This repo provides a `Dockerfile` which sync one specific Obsidian repo with
obsidian-headless (an official headless sync client for Obsidian):

https://help.obsidian.md/headless

Every time files are changed the changes are committed to a git repo and pushed
to a git server.

This provides Obsidian sync with a private versioned backup.

## Architecture

The commit/push is *not* polling. Instead file-system events trigger the watcher
script which will debounce for a short period (to catch running syncs) and then
commit everything.

Optionally commit messages can be generated with an LLM.

The user must run one one of these images per Obsidian repo they want to
sync/backup.

## Features

1. Configuring Obsidian sync of 1 repo through environment variables

2. Configuring git repo through environment variables

3. Optionally configuring an ollama host through environment variables

4. Optionally configure OpenAI/Anthropic credentials

## AI provider

If an ollama host or AI credentials are configured then the image will use that
host to produce meaningful commit messages.
