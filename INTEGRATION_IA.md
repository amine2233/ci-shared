# Integrating ci-shared — guide for AI agents

This file tells an AI agent how to wire `amine2233/ci-shared` into a Swift
GitHub repository: an **SPM library**, a **Swift CLI**, or an **app** (Xcode
project). Read it fully before editing the target repo.

## 1. The contract

The shared workflows contain **no build, test, lint, docs or release logic**.
Each one installs [mise](https://mise.jdx.dev) through the
`actions/mise-run` composite action and runs `mise run <task>`. The target
repo's `mise.toml` is the single source of truth for what each task does.

| Layer | Lives in | Role |
| --- | --- | --- |
| Tasks | target repo `mise.toml` | What each step really runs (`assay`, `executor`, `swift`, `xcodebuild`) |
| Composite action | `ci-shared/actions/mise-run` | Installs mise + `[tools]`, exports `env`, runs `mise run <tasks>` |
| Reusable workflows | `ci-shared/.github/workflows/*.yml` | Runners, permissions, secrets, job layout |
| Caller workflows | target repo `.github/workflows/*.yml` | `uses:` the reusable workflows, pinned to a tag |

Tools:

| Tool in `[tools]` | Version | Used by |
| --- | --- | --- |
| `github:executor-cli/assay-cli` (`assay`) | 1.1.3 | `format`, `check_code`, `check_documentation` |
| `github:executor-cli/executor` (`executor`) | 0.27.1 | `test-coverage`, `release`, `check_commit_title`, `check_merge_request_title`, `build_documentations` |

## 2. Pick the project type

| | SPM library | Swift CLI | App (Xcode project) |
| --- | --- | --- | --- |
| Build system | `Package.swift` | `Package.swift` with an `executable` product | `.xcodeproj` / `.xcworkspace` (Tuist/XcodeGen generated or committed) |
| Test task body | `swift test` | `swift test` | `xcodebuild test …` (see §4.3) |
| Linux tests | yes (if the code is portable) | yes | **no** — set `enable-linux: false` |
| Lint (`assay`) | yes | yes | yes |
| Coverage | `test-coverage` (macOS) | `test-coverage` (macOS) | adapt the task to `xcodebuild -enableCodeCoverage YES` |
| DocC → Pages | `pages.yml` | optional | usually not |
| Release workflow | `release.yml` (tag + changelog) | `release-binaries.yml` (tag + `.tar.gz` assets) | `release.yml` for tag/changelog only; store delivery is out of scope (use fastlane separately) |

Use **one** release workflow per repo, never both: both release on push to `main`.

## 3. Prerequisites (all types)

- Hosted on GitHub, default branch `main`.
- Conventional Commits (`feat:`, `fix:`, `chore:`, `ci:` …) — semantic-release
  derives versions from them; the title check validates PR titles.
- Sources the linter should check live in `./Sources` (change the path in the
  lint tasks otherwise, e.g. `./App/Sources`).
- `.env.local` is loaded by `mise.toml`; add it to `.gitignore`.
- Locally: mise installed, then `mise install`.

## 4. Create `mise.toml`

Copy [`mise-template.toml`](mise-template.toml) to `mise.toml` at the target
repo root. **Keep the task names** — the workflows call them. Change bodies freely.

| Task | Called by | Required for |
| --- | --- | --- |
| `lint` (→ `check_code` + `check_documentation`) | `ci.yml` lint job, PRs only | CI |
| `test` | `ci.yml` macOS + Linux jobs | CI |
| `test-coverage` | `ci.yml` macOS when `enable-coverage: true` | CI with coverage |
| `check_merge_request_title` | `ci.yml` when `enable-title-check: true` | PR title check |
| `build_documentations` | `pages.yml` | Pages |
| `release` | `semantic-release.yml`, `release-binaries.yml` | releases |
| `build-release` | `release-binaries.yml` build matrix | CLI binaries |
| `format`, `check_commit_title` | developers, locally | — |

Format and lint always go through `assay` (subcommand `linter`, **not**
`linting`):

```toml
[tools]
"github:executor-cli/executor" = "0.27.1"
"github:executor-cli/assay-cli" = "1.1.3"

[tasks.format]
run = "assay format ."

[tasks.check_code]
run = "assay linter code ./Sources --reporter console"

[tasks.check_documentation]
run = "assay linter documentation ./Sources --reporter console"

[tasks.lint]
depends = ["check_code", "check_documentation"]
```

Useful `assay linter` flags: `--throw-error` (fail on findings),
`--exclude <dir>` (repeatable), `--config-file <.swiftlint.yml>` (code only).

### 4.1 SPM library

Use the template as is. Set the default `--main-library-name` in
`build_documentations` to the package's main library. Drop `build-release`.

### 4.2 Swift CLI

Use the template as is. `build-release` must leave the executable at
`.build/release/<binary-name>` (or the per-arch dirs
`.build/arm64-apple-macosx/release`, `.build/x86_64-apple-macosx/release`):

```toml
[tasks.build-release]
usage = '''
flag "--arch <arch>" help="Target architecture, e.g. arm64 or x86_64 (empty = host)." default=""
'''
run = '''
#!/usr/bin/env bash
set -euo pipefail
swift build -c release --disable-sandbox ${usage_arch:+--arch "$usage_arch"}
'''
```

The executable must build on Linux too, or set `enable-linux: false` in
`release-binaries.yml`.

### 4.3 App (Xcode project)

`swift test` does not work for an app target. Replace the `test` body; keep
the name:

```toml
[tasks.test]
description = "Run the app tests on a simulator."
run = '''
#!/usr/bin/env bash
set -euo pipefail
xcodebuild test \
    -scheme "<AppScheme>" \
    -destination "platform=iOS Simulator,name=iPhone 16" \
    -skipPackagePluginValidation
'''
```

- If the project is generated (Tuist/XcodeGen), generate it first inside the
  task (`tuist generate --no-open` / `xcodegen generate`) and add the tool to
  `[tools]`.
- Point the lint tasks at the app sources (e.g. `./App ./Modules`).
- Drop `build-release`. Drop `test-coverage` unless adapted to `xcodebuild`.

## 5. Add the caller workflows

Copy from [`examples/`](examples/) into `.github/workflows/`, pin to a tag
(`@1.2.0`, or `@1.2` / `@1` to follow updates), replace placeholders.

| Caller file | Uses | Job permissions | Secrets | Inputs to set |
| --- | --- | --- | --- | --- |
| `ci.yml` | `ci.yml` | `contents: read`, `pull-requests: write` | none | `enable-linux`, `enable-coverage`, `enable-title-check` |
| `pages.yml` | `pages.yml` | `contents: read`, `pages: write`, `id-token: write` | none | `main-library-name`, `hosting-base-path` (required), `platform` |
| `release.yml` | `semantic-release.yml` | `contents: write`, `issues: write`, `pull-requests: write` | `secrets: inherit` | `release-args` |
| `release-binaries.yml` | `release-binaries.yml` | same as release | `secrets: inherit` | `binary-name` (required), `tag`, `targets` |

### CI (all types)

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  ci:
    permissions:
      contents: read
      pull-requests: write
    uses: amine2233/ci-shared/.github/workflows/ci.yml@1.2.0
    with:
      enable-linux: true        # false for apps
      enable-coverage: false
      enable-title-check: true
```

### Pages (SPM library)

```yaml
name: Pages
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  docs:
    uses: amine2233/ci-shared/.github/workflows/pages.yml@1.2.0
    with:
      main-library-name: <MainLibrary>
      hosting-base-path: <repo-name>
      platform: macOS
```

### Release (SPM library, app)

```yaml
name: Release
on:
  push:
    branches: [main]
  workflow_dispatch:
jobs:
  release:
    permissions:
      contents: write
      issues: write
      pull-requests: write
    uses: amine2233/ci-shared/.github/workflows/semantic-release.yml@1.2.0
    with:
      release-args: "--write-change-log"
    secrets: inherit
```

### Release binaries (Swift CLI)

```yaml
name: Release Binaries
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      tag:
        description: "Existing tag to attach binaries to (empty = cut a new release)."
        type: string
        default: ""
jobs:
  binaries:
    permissions:
      contents: write
      issues: write
      pull-requests: write
    uses: amine2233/ci-shared/.github/workflows/release-binaries.yml@1.2.0
    with:
      binary-name: <binary-name>
      tag: ${{ inputs.tag }}
    secrets: inherit
```

Uploads `<binary-name>-darwin-arm64`, `-darwin-amd64`, `-linux-x86_64`,
`-linux-arm64` `.tar.gz` assets. Build jobs are skipped when no new version is cut.

Custom job layout: call the composite action directly after
`actions/checkout@v4` — `uses: amine2233/ci-shared/actions/mise-run@1.2.0`
with `tasks: "test"`. The job then owns runner and permissions.

## 6. GitHub settings (a person must do these)

The agent cannot change these from the repo; list them for the user.

| Setting | Where | Needed for |
| --- | --- | --- |
| Pages source = **GitHub Actions** | Settings → Pages | `pages.yml` |
| Release can push to protected `main` | Settings → Rules → Rulesets (bypass list) or Settings → Branches | release workflows |
| `RELEASE_TOKEN` secret (optional) | Settings → Secrets and variables → Actions | when `GITHUB_TOKEN` can't bypass protection |
| `NPM_TOKEN` secret (optional) | same | only if the release publishes to npm |

semantic-release pushes `CHANGELOG.md`/`README.md` and tags to `main`. If
`main` requires pull requests, `GITHUB_TOKEN` is rejected
(`GH006: Protected branch update failed`). Either add a bypass actor to the
ruleset, or pass a PAT / GitHub App token from a bypass account:

```yaml
    secrets:
      GH_TOKEN: ${{ secrets.RELEASE_TOKEN }}
```

## 7. Checklist for the agent

1. Ask for unknowns: project type, main library or scheme name, repo name,
   binary name (CLI), coverage / title check / Pages wanted.
2. Check prerequisites (§3) and that the project builds and tests locally.
3. Create `mise.toml` (§4 + the subsection for the project type).
4. Add `.env.local` to `.gitignore`.
5. `mise install`, then run locally: `mise run format`, `mise run lint`,
   `mise run test`, plus `build-release` (CLI), `build_documentations macOS`
   (Pages), `release --dry-run`.
6. Add the caller workflows (§5).
7. Commit on a branch (`ci: integrate ci-shared workflows`) and open a PR.
   Do not push without the user's OK.
8. Verify the PR jobs are green: Lint, Test (macOS), Test (Linux, unless
   disabled), Merge request title (if enabled).
9. Give the user the remaining GitHub settings (§6).

## 8. Rules and pitfalls

- Never put build/test/lint commands in workflow YAML — change the `mise.toml`
  task body instead.
- Never rename tasks; if a name must differ, pass it via the input
  (`test-task`, `lint-task`, `coverage-task`, `docs-task`, `release-task`, `build-task`).
- `assay` for format and lint; `executor` for everything else. Never
  `executor linting …`.
- Pin caller `uses:` to a tag, never `@main`.
- Reference the composite action by full path
  (`amine2233/ci-shared/actions/mise-run@<tag>`), never `./actions/...`.
- `test-coverage`, `build_documentations` and any `xcodebuild` task need macOS.
- Lint and title check run only on `pull_request` events.
- The title check comments on the PR, so the caller job needs `pull-requests: write`.
- `darwin-amd64` is cross-compiled on Apple Silicon; use `macos-15-intel` in
  `targets` for a native Intel build.
