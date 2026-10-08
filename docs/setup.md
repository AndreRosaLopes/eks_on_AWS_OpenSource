# Setup

AI tooling for this repository: Claude Code, AWS, Terraform and GitHub Spec Kit.

## 1. Prerequisites

Claude Code, AWS CLI v2, Terraform, Docker (running), Python 3.11+ with `uv`, Git and `gh`.

## 2. AWS

```bash
aws login
aws sts get-caller-identity
aws configure agent-toolkit --yes
```

`agent-toolkit` installs the AWS skills and the AWS MCP Server at user level. Manage skills with `aws agent-toolkit list-installed-skills | search-skills | add-skill | update-skill`.

## 3. Terraform

```bash
claude mcp add terraform -s project -t stdio -- docker run -i --rm hashicorp/terraform-mcp-server
claude plugin marketplace add hashicorp/agent-skills
claude plugin install terraform@hashicorp
```

- The MCP server is versioned in `.mcp.json`. Never put `TFE_TOKEN` there.
- Docker must be running when Claude Code starts.

## 4. Spec Kit

```bash
uv tool install specify-cli
git status                                        # clean working tree
specify init --here --force --integration claude
git status                                        # review generated files
```

If the init creates a `CLAUDE.md`, add `@AGENTS.md` to it; otherwise Claude Code stops reading `AGENTS.md`.

## 5. Validate

In a new Claude Code session:

- `claude mcp list`: `aws-mcp` and `terraform` connected.
- `/context`: `AGENTS.md` under Memory files.
- Skills: `aws-*`, Terraform and `speckit-*` available.

## 6. Sources

[Spec Kit](https://github.com/github/spec-kit) · [Spec Kit on existing projects](https://github.github.io/spec-kit/guides/existing-projects.html) · [Terraform MCP server](https://github.com/hashicorp/terraform-mcp-server) · [HashiCorp agent skills](https://github.com/hashicorp/agent-skills) · [Claude Code memory](https://code.claude.com/docs/en/memory) · `aws configure agent-toolkit help`
