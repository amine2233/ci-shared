# ci-shared

Shared [GitHub Actions](https://docs.github.com/actions) for Swift package
development, consumed from any package repo
(e.g. [`cascade-kit`](https://github.com/amine2233/cascade-kit)).

**The CI does not re-implement build/test/docs/release scripts.** Every project
ships a [`mise.toml`](https://mise.jdx.dev) whose tasks already encode that logic
(via [`executor`](https://github.com/executor-cli/executor)). The shared
workflows just install mise and run `mise run <task>`. One source of truth: the
project's `mise.toml`.

```
   consumer mise.toml          ci-shared                       runner
   ────────────────            ─────────                       ──────
   [tasks.test]        ◀──── mise run test     ◀──── actions/mise-run (jdx/mise-action + mise run)
   [tasks.lint]        ◀──── mise run lint      ◀──── .github/workflows/ci.yml
   [tasks.build_…]     ◀──── mise run build_…   ◀──── .github/workflows/pages.yml
   [tasks.release]     ◀──── mise run release   ◀──── .github/workflows/semantic-release.yml
```

## Setup a consumer repo

1. Copy [`mise-template.toml`](mise-template.toml) → `mise.toml` and adjust tool
   versions / library name. Keep the task **names** (`test`, `lint`,
   `build_documentations`, `release`, …) so the workflows keep working.
2. Copy the workflows you want from [`examples/`](examples/) into
   `.github/workflows/`.
3. For Pages: **Settings → Pages → Source = "GitHub Actions"**.

> Pin to a tag (e.g. `@1` or `@1.0.0`) instead of `@1.0.1` once this repo is released.

## Building blocks

### Composite action — [`actions/mise-run`](actions/mise-run)

Installs mise (provisioning the `[tools]` from `mise.toml`, with caching via
[`jdx/mise-action`](https://github.com/jdx/mise-action)) and runs one or more
tasks. Use it directly when you want your own job/matrix layout.

| Input | Default | Description |
| --- | --- | --- |
| `tasks` | — (required) | Argument string for `mise run` (e.g. `test`, or `build_documentations macOS --hosting-base-path foo`). Chain several with ` ::: `. |
| `install-tools` | `true` | Install tools from `mise.toml` first |
| `mise-version` | `""` | Pin a mise version (empty = latest) |
| `cache` | `true` | Cache mise-installed tools |
| `working-directory` | `.` | Where `mise.toml` lives / tasks run |
| `env` | `""` | `KEY=VALUE` lines exported before the task (used to pass `GITHUB_TOKEN`, etc.) |

```yaml
- uses: actions/checkout@v4
- uses: amine2233/ci-shared/actions/mise-run@1.0.2
  with:
    tasks: "test"
```

### Reusable workflows

| Workflow | File | Runs |
| --- | --- | --- |
| **CI** | [`ci.yml`](.github/workflows/ci.yml) | `mise run lint` + `mise run test` on macOS & Linux (coverage optional) |
| **Pages** | [`pages.yml`](.github/workflows/pages.yml) | `mise run build_documentations` → upload `./public` → deploy to Pages |
| **Semantic Release** | [`semantic-release.yml`](.github/workflows/semantic-release.yml) | `mise run release` on full git history |

#### CI

```yaml
jobs:
  ci:
    uses: amine2233/ci-shared/.github/workflows/ci.yml@1.0.2
    with:
      enable-coverage: false
```

| Input | Default | Description |
| --- | --- | --- |
| `macos-runner` / `linux-runner` | `macos-15` / `ubuntu-latest` | Runner images |
| `enable-macos` / `enable-linux` / `enable-lint` | `true` | Toggle jobs |
| `enable-coverage` | `false` | Use `coverage-task` on macOS |
| `test-task` | `test` | mise task for tests |
| `coverage-task` | `test-coverage` | mise task for coverage (macOS) |
| `lint-task` | `lint` | mise task(s) for the lint job |

#### Pages

```yaml
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  docs:
    uses: amine2233/ci-shared/.github/workflows/pages.yml@1.0.2
    with:
      main-library-name: CascadeKit
      hosting-base-path: cascade-kit
```

| Input | Default | Description |
| --- | --- | --- |
| `main-library-name` | — (required) | Passed as `MAIN_LIBRARY_NAME` to the docs task |
| `hosting-base-path` | — (required) | Passed as `HOSTING_BASE_PATH`; usually the repo name |
| `platform` | `macOS` | `iOS` or `macOS` |
| `docs-task` | `build_documentations` | mise task building docs into `./public` |
| `output-path` | `public` | Directory the task writes into |

#### Semantic Release

```yaml
jobs:
  release:
    permissions:
      contents: write
      issues: write
      pull-requests: write
    uses: amine2233/ci-shared/.github/workflows/semantic-release.yml@1.0.2
    secrets: inherit
```

| Input | Default | Description |
| --- | --- | --- |
| `release-task` | `release` | mise task that runs the release |
| `release-args` | `--write-change-log` | Extra args (e.g. `--dry-run`) |

The workflow exports `GITHUB_TOKEN`/`GH_TOKEN` (from `secrets: inherit`) into the
task environment.

##### Repo setup: let the release push to a protected `main`

semantic-release commits the `CHANGELOG.md` / `README.md` bump **back to the
release branch** and pushes tags. If `main` is protected (require a pull
request, or "do not allow bypassing"), the push is rejected:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Changes must be made through a pull request.
 ! [remote rejected] HEAD -> main (protected branch hook declined)
```

The default `GITHUB_TOKEN` (acting as `github-actions[bot]`) **cannot** bypass a
"require pull request" rule. Pick one:

1. **Add a bypass actor (recommended).** In the branch ruleset/protection for
   `main`, add the identity that runs the release to the bypass list:
   - **Rulesets** (*Settings → Rules → Rulesets → your `main` ruleset →
     Bypass list*): add **Repository admin**, or the GitHub App / user whose
     token you use below.
   - **Classic protection** (*Settings → Branches → main*): enable
     **Allow specified actors to bypass required pull requests** and add that
     actor.
2. **Use a token that owns the bypass.** The built-in `GITHUB_TOKEN` can't be
   added to a bypass list, so provide your own and pass it as `GH_TOKEN`:
   - a **fine-grained PAT** (or classic PAT with `repo`) from an account in the
     bypass list, **or** a **GitHub App** installation token (recommended for
     orgs);
   - store it as a repo secret (e.g. `RELEASE_TOKEN`) and wire it in:

     ```yaml
     jobs:
       release:
         permissions:
           contents: write
           issues: write
           pull-requests: write
         uses: amine2233/ci-shared/.github/workflows/semantic-release.yml@1.0.1
         secrets:
           GH_TOKEN: ${{ secrets.RELEASE_TOKEN }}
     ```

> The git identity is set via `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env in the
> workflow, so the `Author identity unknown` / `empty ident name` error is
> already handled — this section is only about the **push permission**.
>
> The `git: 'credential-cache --timeout 3600' is not a git command` line in the
> log is a harmless warning (that credential helper isn't installed on the
> runner), not the cause of the failure.

## Notes

- Composite actions run *inside the caller's job*, so the job provides the
  runner, `permissions`, and `actions/checkout`.
- Inside the reusable workflows the action is referenced as
  `amine2233/ci-shared/actions/mise-run@1.0.2` (not `./actions/...`): a relative
  `uses:` in a reusable workflow resolves against the *caller's* checkout.

## Releasing ci-shared itself

This repo versions itself with semantic-release so consumers can pin a stable
ref. The [`mise.toml`](mise.toml) defines a `semantic-release` task; the manual
[`Release`](.github/workflows/release.yml) workflow (`workflow_dispatch`) runs it:

- **Actions → Release → Run workflow** (optionally tick *dry-run* to preview).
- semantic-release (config in [`.releaserc.json`](.releaserc.json)) then:
  cuts a `X.Y.Z` tag (no `v` prefix) + GitHub release from Conventional Commits;
  bumps the pinned `amine2233/ci-shared@<version>` refs in the README and
  [`examples/`](examples/) via [`bumpversion.sh`](bumpversion.sh); and moves the
  short tags `N` / `N.M` via [`post-release.sh`](post-release.sh) so callers can
  pin `@1` (latest 1.x) or `@1.2` (latest 1.2.x) and keep getting updates.

```bash
mise run semantic-release --dry-run   # preview locally
```

## Repository layout

```
mise-template.toml           # copy to consumer repos as mise.toml (the task source of truth)
mise.toml                    # tasks for releasing THIS repo (semantic-release)
.releaserc.json              # semantic-release config for THIS repo
actions/mise-run/            # composite action: setup mise + `mise run <task>`
.github/workflows/
  ci.yml pages.yml semantic-release.yml   # reusable workflows for consumers
  release.yml                             # manual workflow that releases ci-shared itself
examples/                    # caller workflows to copy into consumers
```
