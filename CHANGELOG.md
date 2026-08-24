# Changelog

## 1.0.5 (2026-08-24)

- Added a split file browser view with a resizable divider, starting at a one-to-three ratio, and switchable from the Files tab.
- Made a single click select a row in the file list, even when the panel was not focused, and made the selection visible.
- Showed folder names in full with horizontal scrolling instead of truncating them, and widened the name and action columns.
- Added a choice of how documents open: ask every time, always open without locking, or always lock and open.
- Added a do-not-ask-again checkbox to the open confirmation, with a warning that locked files block other users until commit or unlock.

## 1.0.4 (2026-08-24)

- Fixed Korean filenames added on Mac appearing as separated letters on Windows.
- Added a warning for working folders on disks that can only store Korean filenames in separated form.
- Added a repository cleanup that finds Korean paths already stored in the separated form and renames them so they display correctly on Windows.
- Showed the stored name form and the differing characters for each rename target, because the two forms look identical on Mac.
- Hid Mac and Office temporary files from the changes list by default, and excluded them from commit targets so they can no longer be uploaded by accident.
- Added a settings toggle that reveals temporary files again when they need to be committed or inspected deliberately.
- Offered an optional cleanup commit after an update that deletes Mac and Office temporary files already stored in the repository, gated by name patterns, magic-byte checks, and a per-file review step.
- Rebuilt the file browser list with modification date, size, and kind columns that sort by header.
- Made the file list fully keyboard driven: arrow keys expand, collapse, and move between folders, and Return opens a file.
- Added a split view that keeps a folder tree on the left and the selected folder's contents with per-row actions on the right, switchable from the Files tab.
- Kept expanded folders and the current selection after a refresh, instead of collapsing the whole tree on every action.
- Fixed clicking a file name not selecting the row, and made double-click open a file or toggle a folder.
- Added a settings button to the sidebar so the app-wide settings are reachable without the menu bar.

## 0.5.26 (2026-08-04)

- Showed a progress spinner inside every long-running action button instead of only disabling it.
- Made canceling an in-progress checkout terminate the running SVN process after an explicit confirmation.
- Blocked the add-repository sheet from closing while a checkout is running so no work is left behind.
- Allowed an already registered folder to change its local path, keeping the same project identity and Keychain password.
- Verified an SVN account against the server before saving it, and offered re-entry or discarding the change when it fails.
- Added a reveal toggle to every password field, which also allows Korean input that macOS secure entry blocks.

## 0.5.25 (2026-07-31)

- Allowed committing without a message after an explicit confirmation prompt.
- Kept the commit button enabled for an empty message and applied the same confirmation to button and Return submissions.
- Preserved the entered text and the selected files when the confirmation is declined.

## 0.5.24 (2026-07-29)

- Added an incoming-commit count badge to the Update toolbar action.
- Marked incomplete or mixed-revision counts with a trailing plus sign.
- Kept the update badge separate from its label and the global progress indicator.

## 0.5.20 (2026-07-28)

- Prevented persistent automatic-refresh failures from reopening the same error dialog until the user explicitly retries.
- Coalesced parallel project, file, and lock refresh failures into one presentation.
- Discarded stale repository-lock responses after switching projects and kept detailed errors owned by the active sheet.

## 0.5.19 (2026-07-28)

- Restored the `Distributed by MR.DEVELLO` credit in the custom About window.
- Kept the individual copyright notice alongside the distribution credit.

## 0.5.18 (2026-07-28)

- Classified SVN `E155011` and `E170004` commit failures as working-copy update requirements while preserving the original SVN details.
- Kept pending commit selections intact and allowed Update to run when a scheduled directory deletion hides incoming changes.

## 0.5.17 (2026-07-28)

- Discovered nested `.gitignore` files and resolved their rules relative to each source directory.
- Compared and imported compatible ignore rules across the full working-copy tree.

## 0.5.16 (2026-07-28)

- Distinguished locally missing files from SVN items already marked for deletion.
- Required an explicit restore-or-delete choice before a missing item can be committed.
- Added pending-deletion confirmation, batch handling, commit summaries, and pre-commit restoration.
- Added `svn:global-ignores` and inherited-rule visibility alongside existing `svn:ignore` management.
- Added one-way `.gitignore` comparison, conversion previews, unsupported-rule explanations, and selective SVN property application.

## 0.5.15 (2026-07-24)

- Renamed the distributed app and user-facing product from SVN for Mac to SVN KR.
- Preserved the existing bundle identifier and saved credentials during the rebrand.

## 0.5.14 (2026-07-23)

- Added automatic App Store version checks and a manual Check for Updates command.
- Added update status and release lookup to the custom About window.

## 0.5.13 (2026-07-22)

- Added shared horizontal padding to frequent toolbar actions and progress indicators.

## 0.5.12 (2026-07-22)

- Kept frequent actions visibly labeled and used bordered controls for clearer affordance.

## 0.5.11 (2026-07-22)

- Added a reviewable sample project and an explicit demo exit flow.
- Added language selection to the first-run repository screen and improved App Review guidance.

## 0.5.10 (2026-07-22)

- Added support-email error reports with sensitive-data redaction.
- Unified raw UTF-8 SVN path transport and moved repository locks into the shared project header.

## 0.5.9 (2026-07-22)

- Allowed an existing local file to open when its remote lock lookup fails.
- Added a detailed fallback choice to open the document without acquiring a lock.

## 0.5.8 (2026-07-21)

- Completed Unicode-safe text and binary conflict resolution using the exact SVN-managed path.
- Preserved recovery copies and prevented stale conflict or revert completions from changing a newer request.

## 0.5.7 (2026-07-21)

- Built SVN 1.14.5 and its non-system dependencies from checksum-pinned sources for a macOS 14 arm64 deployment target.
- Statically linked SQLite 3.51.0, Serf, OpenSSL, APR, APR-util, Expat, LZ4, and utf8proc so packaging no longer inherits Homebrew versions or load paths.
- Made release packaging accept only a validated runtime with an immutable source manifest.

## 0.5.6 (2026-07-21)

- Bundled the exact SQLite runtime expected by the packaged SVN helper instead of loading a potentially different system SQLite version.
- Added checksum, deployment-target, load-path, and runtime-version validation to SVN packaging.

## 0.5.5 (2026-07-21)

- Bundled the SQLite runtime required by SVN to prevent installed-app startup crashes.

## 0.5.4 (2026-07-20)

- Added in-place repair for canonically equivalent Korean paths and automatic repair before commit.
- Added byte-level validation, ambiguity blocking, and recovery guidance for unsafe aliases.

## 0.5.3 (2026-07-20)

- Removed commit-message typing lag for very large change selections.
- Added canonical-path snapshots, collision summaries, commit blocking, and safe rollback.

## 0.5.2 (2026-07-20)

- Displayed mixed working-copy revision ranges in history.
- Added selected-project commit progress and scalable targets-file commits for large selections.

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
