# Changelog

## Unreleased

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
