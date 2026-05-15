<p align="center">
  <img src="Resources/DiffyIcon-512.png" width="128" alt="Diffy icon">
</p>

# Diffy

Diffy is a small native macOS menu bar app for solo developers. It watches local git repositories and shows live working-tree diff stats directly in the menu bar.

Diffy is local-only. It does not use GitHub, GitLab, Bitbucket, PRs, issues, cloud services, or accounts. Its git commands are read-only with one explicit, user-initiated exception: removing a linked worktree from the in-app confirmation dialog.

## Status

v0.3.2 — available via Homebrew Cask. The app uses macOS 26 Liquid Glass APIs and is ad-hoc signed (not notarized). Install instructions below handle Gatekeeper automatically.

## Features

- **Groups**: every repo belongs to a group, and each group owns one menu-bar icon, one color scheme, and an optional small label (1–2 chars or an emoji, positioned around the `+/-` counts). New repos default to their own single-repo group; combine or split groups by drag-drop in the main window. A group with N repos shows the aggregate `+x / -y` of its (non-hidden) members.
- **Hide a group from the menu bar** with an eye toggle in the sidebar header — the icon disappears entirely until toggled back on. Per-repo "Exclude from group totals" is also available for silencing a noisy repo within a multi-repo group without removing the icon.
- Left-click any group's menu-bar icon opens a popover listing **that group's** repos with their staged and unstaged files — click a file to jump straight into your editor. "See all groups" opens the full main window.
- Main window: sidebar with one section per group (drag-drop repos between sections, reorder groups, edit colors / labels / names / hidden state), detail pane with per-repo settings.
- Window close hides Diffy back to the menu bar (no quit); ⌘Q or right-click → Quit to actually exit.
- Per-repo detail pane: staged and unstaged changed-file sections with status labels (`M`, `A`, `D`, `U`, `C`, `!`) and per-file `+a / -b`.
- **Branch labels** on every row (popover, sidebar, detail pane). Detached HEAD shows the short SHA in italics.
- **Linked worktrees** discovered automatically from `git worktree list --porcelain` and shown as indented sub-rows under their parent repo, each with their own diff stats and branch. Per-worktree "Exclude from group totals" toggle works the same way as for any other repo. Remove a finished worktree from inside Diffy via a confirmation dialog in the detail pane — Diffy never uses `--force`, so any uncommitted changes or untracked files in the worktree must be handled in your terminal first.
- Open changed files in a configured editor (Xcode, Cursor, VS Code, Zed, or a custom shell command).
- **Launch at Login** toggle (requires Diffy installed to `/Applications`).
- Filesystem-triggered refresh with polling fallback.
- Sparkle-ready update packaging for GitHub Releases.

## Build and Run Locally

From the Mac terminal:

```bash
swift test
./script/build_and_run.sh
```

The run script builds the SwiftPM target, creates `dist/Diffy.app`, ad-hoc signs it, and launches it.

## Package a Release

```bash
./script/package_release.sh 0.3.1 1
```

The zip is created at `dist/release/Diffy-0.3.1.zip`.

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

Diffy is read-only with one explicit, user-initiated exception: removing a linked worktree via the in-app confirmation dialog (which runs `git worktree remove <path>` without `--force`). All other git operations Diffy performs (`diff`, `status`, `worktree list`) are strictly observational, run with `GIT_OPTIONAL_LOCKS=0` and `--no-optional-locks`. Diffy never stages, commits, checks out, cleans, resets, rebases, merges, or otherwise mutates a repository's working tree.
