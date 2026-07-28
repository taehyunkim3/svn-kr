# Changelog

## Unreleased

## 0.5.17 (2026-07-28)

- Discovered nested `.gitignore` files and resolved their rules relative to each source directory.
- Compared and imported compatible ignore rules across the full working-copy tree.

## 0.5.16 (2026-07-28)

- Distinguished locally missing files from SVN items already marked for deletion.
- Required an explicit restore-or-delete choice before a missing item can be committed.
- Added pending-deletion confirmation, batch handling, commit summaries, and pre-commit restoration.
- Added `svn:global-ignores` and inherited-rule visibility alongside existing `svn:ignore` management.
- Added one-way `.gitignore` comparison, conversion previews, unsupported-rule explanations, and selective SVN property application.

## 0.5.7 (2026-07-21)

- Built SVN 1.14.5 and its non-system dependencies from checksum-pinned sources for a macOS 14 arm64 deployment target.
- Statically linked SQLite 3.51.0, Serf, OpenSSL, APR, APR-util, Expat, LZ4, and utf8proc so packaging no longer inherits Homebrew versions or load paths.
- Made release packaging accept only a validated runtime with an immutable source manifest.

## 0.5.6 (2026-07-21)

- Bundled the exact SQLite runtime expected by the packaged SVN helper instead of loading a potentially different system SQLite version.
- Added checksum, deployment-target, load-path, and runtime-version validation to SVN packaging.

## 0.5.1 (2026-07-18)

- Prevented file and history searches from inserting duplicate macOS toolbar items when switching tabs.
- Made functional actions consistently appear as bordered buttons across the app.
- Kept empty change lists and history diff panels aligned across content states.
- Prevented long revision diff lines from wrapping into narrow vertical columns.
- Repaired display of recoverable legacy Korean commit-message mojibake.
- Marked restored commit messages and made their original text available from the history UI.
- Added a searchable working-copy file tree so unchanged files can be selected before editing.
- Connected tracked documents to lock-before-open and displayed current lock owners in the file tree.
- Prevented unversioned documents from attempting unsupported SVN lock operations.

## 0.5.0 (2026-07-16)

- Added searchable commit history, revision diffs, file history, and incremental history loading.
- Added SVN ignore rule creation, removal, and optional ignored-file display.
- Added document locking before opening, repository lock visibility, and safe unlock actions.
- Added text and binary document conflict resolution with automatic backups and side-by-side version preservation.
- Added incoming update previews, confirmed local reverts, Finder reveal, path copying, and project status badges.
- Split feature-specific project operations into focused store extensions.

## 0.4.2 (2026-07-16)

- Forced a UTF-8 locale for SVN commands so Korean commit messages are stored correctly when the app is launched from Finder or the Dock.

## 0.4.1 (2026-07-16)

- Fixed checkout into user-selected folders under App Sandbox.
- Added a per-repository option to allow self-signed certificates and hostname mismatches.
- Added an Open in Finder button for the current SVN working folder.
- Replaced diff errors for unversioned files with a clear status message.
- Fixed the final Korean character sometimes being omitted from commit messages.
- Cleared messages after commits and refreshed automatically when the window becomes active.
- Determined update status from actual remote changes for mixed-revision working copies.
- Declared exempt encryption export compliance for distribution outside France.
- Removed quarantine attributes before signing App Store packages.
