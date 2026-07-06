---
description: Cut a Clipsmith release — verify versions, run the full test suite, then tag and push to trigger the GitHub release build
---

Cut a Clipsmith release. Optional argument overrides the version: `$ARGUMENTS` (when empty, the version is the newest section heading in CHANGELOG.md).

Execute the steps in order. **Stop at the first failure and report it — never skip a step, never work around a failing check.** Tagging and pushing publishes a release; it is not reversible in practice.

## 0. Documentation freshness

Determine `VERSION` now (same rule as step 2: the argument, or the newest section heading in CHANGELOG.md). Then verify the docs describe this release — commit any fixes before moving on (preflight requires a clean tree):

- **CHANGELOG.md** — all three must hold, mechanically:
  ```bash
  # a) the section for VERSION exists and has content
  awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]"{f=1; next} /^## \[/{f=0} f && NF' CHANGELOG.md | head -3   # must print at least one line
  # b) the compare link exists
  grep -c "^\[$VERSION\]:" CHANGELOG.md                                                                   # must print 1
  # c) [Unreleased] is empty — shipped work must be documented under VERSION
  awk '/^## \[Unreleased\]/{f=1; next} /^## \[/{f=0} f && NF' CHANGELOG.md | head -3                      # must print nothing
  ```
  If (c) fails, move the `[Unreleased]` items into the `[VERSION]` section (they are shipping in this release) and commit.
- **README.md** — read the `[VERSION]` changelog section and check each user-facing change is reflected where the README covers that area (features list, shortcut tables, requirements). Update and commit if not.
- **Website (`site/index.html`)** — same review against the changelog section: feature copy, hero tagline, counts (transforms, prompts, docs). The site changelog itself regenerates from CHANGELOG.md on deploy — only static copy needs review. Update and commit if not.

New commits made here ship with the release push — that is the point.

## 1. Preflight

- Current branch must be `main`: `git rev-parse --abbrev-ref HEAD`. On any other branch, stop — releases are cut from main after the feature branch merges.
- Working tree must be clean: `git status --porcelain` prints nothing.
- Not behind the remote: `git fetch origin && git rev-list --count HEAD..origin/main` must print `0`. (Being *ahead* is fine — unpushed commits ship with the release push.)

## 2. Determine and verify the version

- `VERSION`: use `$ARGUMENTS` if given, otherwise:
  ```bash
  awk '/^## \[[0-9]/{gsub(/[][]/,"",$2); print $2; exit}' CHANGELOG.md
  ```
- The version must be consistent in all three places. Stop and list any mismatch:
  ```bash
  plutil -extract CFBundleShortVersionString raw Clipsmith/Info.plist                          # must print exactly VERSION
  sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Clipsmith.xcodeproj/project.pbxproj | sort -u  # must print exactly one line: VERSION
  ```
- The tag must not exist yet, locally or on the remote:
  ```bash
  git tag -l "v$VERSION"                                   # must print nothing
  git ls-remote --tags origin "refs/tags/v$VERSION"        # must print nothing
  ```

## 3. Run the full test suite

```bash
xcodebuild test -scheme Clipsmith -destination 'platform=macOS' 2>&1 | tail -20
```

Must end with `** TEST SUCCEEDED **`. If ANY test fails, stop and report the failing test names — do not exclude suites, do not re-run with `-only-testing`, do not release on a red suite even if the failures look unrelated. The user decides what to do with failures.

## 4. Summarize, then proceed

Print (no question, do not pause): the version, `git log --oneline -1`, and the number of unpushed commits (`git rev-list --count origin/main..HEAD`). The user's decision to release IS the `/release` invocation — the gates above (main branch, clean tree, version consistency, fresh tag, green full suite) are the safety net. Pushing the tag triggers the public release build (`.github/workflows/release-signed.yml`, tag pattern `v*`).

## 5. Tag and push

```bash
git tag "v$VERSION"
git push origin main "v$VERSION"
```

## 6. Report

- Watch for the run: `gh run list --workflow=release-signed.yml --limit 1` and share the run URL.
- Remind: the workflow builds the signed DMG and creates the GitHub release; release notes are generated from the commit log by the workflow (CHANGELOG.md's section feeds the website changelog, not the GitHub release notes).
