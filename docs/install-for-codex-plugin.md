# Install Humanize as a Codex Plugin Repo

This repository now ships Codex-facing plugin metadata in [`.codex-plugin/plugin.json`](../.codex-plugin/plugin.json) plus a local marketplace entry in [`.agents/plugins/marketplace.json`](../.agents/plugins/marketplace.json).

## Recommended Install Path

For normal usage, install the Humanize skills into your Codex runtime:

```bash
./scripts/install-skills-codex.sh
```

This is the supported path for:
- `humanize`
- `humanize-gen-plan`
- `humanize-refine-plan`
- `humanize-rlcr`

See [Install for Codex](install-for-codex.md) for the full skill-runtime workflow.

## Repo-Local Plugin Metadata

If you are wiring this repository into a local Codex plugin catalog, use:

- [`.codex-plugin/plugin.json`](../.codex-plugin/plugin.json)
- [`.agents/plugins/marketplace.json`](../.agents/plugins/marketplace.json)

The hook manifest referenced by the plugin metadata is:

```bash
./hooks/hooks.json
```

## Available Commands

After installing the skills, the main commands are:

```bash
/humanize:start-rlcr-loop
/humanize:gen-plan
/humanize:refine-plan
/humanize:ask-codex
```

## Monitor Setup

Add the monitoring helper to your shell for real-time progress tracking:

```bash
source /path/to/humanize/scripts/humanize.sh
```

Then use:

```bash
humanize monitor rlcr   # Monitor RLCR loop
humanize monitor pr     # Monitor PR loop
```

## Next Steps

See the [Usage Guide](usage.md) for detailed command reference and configuration options, or [Install for Codex](install-for-codex.md) for the supported runtime install path.
