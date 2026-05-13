<p align="center">
  <img src="Resources/DiffyIcon-512.png" width="128" alt="Diffy icon">
</p>

# Diffy

Diffy is a small native macOS menu bar app for solo developers. It watches local git repositories and shows live working-tree diff stats directly in the menu bar.

Diffy is local-only and read-only. It does not use GitHub, GitLab, Bitbucket, PRs, issues, cloud services, or accounts. Its git commands are observational only.

## Status

v0.1.1— available via Homebrew Cask. The app uses macOS 26 Liquid Glass APIs and is ad-hoc signed (not notarized). Install instructions below handle Gatekeeper automatically.

## Features

- Single menu bar badge showing **aggregate** `+x / -y` line counts across every configured repo
- Left-click the badge opens a popover listing every repo with its staged and unstaged files — click a file to jump straight into your editor
- "Open Diffy" in the popover opens the full main window: sidebar lists every repo, detail pane shows that repo's changes plus its settings
- Window close hides Diffy back to the menu bar (no quit); ⌘Q or right-click → Quit to actually exit
- Per-repo detail pane: staged and unstaged changed-file sections with status labels (`M`, `A`, `D`, `U`, `C`) and per-file `+a / -b`
- Per-repo colors for additions, removals, and optional badge background
- Open changed files in a configured editor (Xcode, Cursor, VS Code, Zed, or a custom shell command)
- **Launch at Login** toggle (requires Diffy installed to `/Applications`)
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
./script/package_release.sh 0.1.1 2
```

The zip is created at `dist/release/Diffy-0.1.1.zip`.

## Install

The easiest path is Homebrew:

```bash
brew tap nick701/diffy
brew install --cask diffy
xattr -dr com.apple.quarantine /Applications/Diffy.app
```

The `xattr` step is required because Diffy is ad-hoc signed and not notarized — macOS will block it on first launch without it.

To upgrade an existing install:

```bash
brew upgrade --cask diffy
xattr -dr com.apple.quarantine /Applications/Diffy.app
```

## Auto-Updates

Diffy includes Sparkle integration, but update checks are enabled only in release bundles that include a Sparkle appcast URL and EdDSA public key. See `docs/release.md`.

## Read-Only Guarantee

Diffy never stages, commits, checks out, cleans, resets, rebases, merges, or writes to watched repositories. It uses read-only git inspection commands with optional locks disabled.
