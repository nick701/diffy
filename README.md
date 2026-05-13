# Diffy

Diffy is a small native macOS menu bar app for solo developers. It watches local git repositories and shows live working-tree diff stats directly in the menu bar.

Diffy is local-only and read-only. It does not use GitHub, GitLab, Bitbucket, PRs, issues, cloud services, or accounts. Its git commands are observational only.

## Status

Early v1 implementation. The current UI uses macOS 26 Liquid Glass APIs and is unsigned/unnotarized, so macOS Gatekeeper will warn on first launch.

## Features

- One menu bar badge per configured repository
- Repo-level `+x / -y` line counts in green and red
- Per-repo colors for additions, removals, and optional badge background
- Popover with staged and unstaged changed-file sections
- Per-file status labels like `M`, `A`, `D`, `U`, and `C`
- Per-file `+a / -b` counts
- Open changed files in a configured editor
- Filesystem-triggered refresh with polling fallback
- Sparkle-ready update packaging for GitHub Releases

## Build and Run Locally

From the Mac terminal:

```bash
swift test
./script/build_and_run.sh
```

The run script builds the SwiftPM target, creates `dist/Diffy.app`, ad-hoc signs it, and launches it.

## Package a Release

```bash
./script/package_release.sh 0.1.0 1
```

The zip is created at `dist/release/Diffy-0.1.0.zip`.

## Download and Install

Once releases are published, download the zipped `.app` from GitHub Releases, unzip it, and move `Diffy.app` to `/Applications`.

Because Diffy is unsigned and unnotarized, first launch requires a Gatekeeper override:

1. Try to open Diffy.
2. Open **System Settings > Privacy & Security**.
3. Click **Open Anyway** for Diffy.
4. Confirm **Open**.

## Auto-Updates

Diffy includes Sparkle integration, but update checks are enabled only in release bundles that include a Sparkle appcast URL and EdDSA public key. See `docs/release.md`.

## Read-Only Guarantee

Diffy never stages, commits, checks out, cleans, resets, rebases, merges, or writes to watched repositories. It uses read-only git inspection commands with optional locks disabled.
