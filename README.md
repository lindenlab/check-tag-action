# Version Check & Tag Action

A GitHub Action for automatic Git tagging with support for semantic versioning, date-based versioning, monorepos, and feature branch prereleases.

## Features

- **Semantic Versioning**: Standard `v1.2.3` style tags
- **Date-Based Versioning**: Automatic `vYYYY.M.D` tags (e.g., `v2025.10.17`)
- **Monorepo Support**: Multiple Version files create namespaced tags (e.g., `service1/v1.2.3`)
- **Prerelease Tags**: Automatic prerelease versioning for feature branches
- **Version Validation**: Check if version files need updating in pull requests
- **Same-Day Releases**: Auto-increment counters for multiple releases per day

## Quick Start

### 1. Create a Version File

Create a file named `Version` in your repository root:

```
1.2.3
```

Or for date-based versioning:

```
date
```

### 2. Add to Your Workflow

**For Pull Requests** (validate version was bumped):
```yaml
name: Check Version
on:
  pull_request:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: lindenlab/check-tag-action@v1
        with:
          mode: check
```

**For Main Branch** (create release tags):
```yaml
name: Tag Release
on:
  push:
    branches: [main]

jobs:
  tag:
    runs-on: ubuntu-latest
    steps:
      - uses: lindenlab/check-tag-action@v1
        with:
          mode: tag
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `mode` | Mode to run: `check` or `tag` | No | `tag` |
| `token` | GitHub token for pushing tags | No | `${{ github.token }}` |

## Outputs

| Output | Description |
|--------|-------------|
| `tag` | The Git tag that was created (only in `tag` mode) |

## Version File Format

Create a file named `Version` containing:

### Semantic Versioning
```
1.2.3
```
Creates tag: `v1.2.3`

### Date-Based Versioning
```
date
```
Creates tag: `vYYYY.M.D` (e.g., `v2025.10.17`)

If you tag multiple times on the same day, it auto-increments: `v2025.10.17.1`, `v2025.10.17.2`, etc.

### Monorepo Support

Place Version files in subdirectories:
```
service1/Version  → creates tag service1/v1.2.3
service2/Version  → creates tag service2/v2.0.0
```

## How It Works

### On Default Branch (main/master)
- Reads all `Version` files in the repository
- Creates release tags (e.g., `v1.2.3`)
- Skips if tag already exists

### On Feature Branches
- Creates prerelease tags with branch name
- Example: `v1.2.3-feature-DEV-123.1`
- Auto-increments counter for multiple pushes to same branch

### In Pull Requests (check mode)
- Validates that version has been updated
- Fails if version tag already exists (forces version bump)
- Allows merging if version is new

## Usage Examples

See the [`examples/`](./examples) directory for complete workflow examples:

- **[basic-usage.yml](./examples/basic-usage.yml)** - Simple CI/CD with version checking and tagging
- **[date-versioning.yml](./examples/date-versioning.yml)** - Using date-based versions
- **[monorepo-usage.yml](./examples/monorepo-usage.yml)** - Multiple services in one repo

## Permissions Required

The action needs permission to:
- Read repository contents
- Fetch tags
- Create tags
- Push to repository

**Default `GITHUB_TOKEN` has these permissions by default.**

If you need to trigger workflows from tag pushes, use a Personal Access Token (PAT):

```yaml
- uses: lindenlab/check-tag-action@v1
  with:
    token: ${{ secrets.PAT_TOKEN }}
```

## Advanced Configuration

### Environment Variables

You can customize behavior with environment variables:

```yaml
- uses: lindenlab/check-tag-action@v1
  env:
    GIT_REMOTE_NAME: origin  # Change remote name (default: origin)
    DRY_RUN: true            # Preview actions without pushing
```

### Dry Run Mode

Test without actually creating tags:

```yaml
- uses: lindenlab/check-tag-action@v1
  with:
    mode: tag
  env:
    DRY_RUN: true
```

## Complete Workflow Example

```yaml
name: CI/CD Pipeline

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  # Validate version in PRs
  check-version:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: lindenlab/check-tag-action@v1
        with:
          mode: check

  # Build and test
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: make test
      - name: Build
        run: make build

  # Tag releases on main
  tag-release:
    if: github.ref == 'refs/heads/main'
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: lindenlab/check-tag-action@v1
        with:
          mode: tag
```

## Versioning Strategy

This action follows semantic versioning. You can reference it as:

- `@v1` - Latest v1.x.x (recommended, automatically gets updates)
- `@v1.0.0` - Specific version (pinned, no automatic updates)
- `@main` - Latest commit (not recommended for production)

## License

MIT License - see [LICENSE](./LICENSE) for details

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.

## Support

For issues and questions, please [open an issue](../../issues) on GitHub.
