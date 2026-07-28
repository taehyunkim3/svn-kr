# App Store Metadata — English

## App Name

SVN KR

## Subtitle

A focused native SVN client

## Promotional Text

Review changes, inspect diffs, compare revisions, and browse commit history across multiple SVN working copies in one native macOS app.

## Description

SVN KR is a native macOS client for managing multiple Subversion working copies in one place.

Handle everyday SVN tasks without memorizing complex commands. Review local changes, inspect file diffs, commit selected files, update a working copy, and browse server history from a focused macOS interface.

Key features

• Check out a repository URL into a new local working folder
• Register and switch between multiple existing SVN working copies
• Review modified, added, and unversioned files
• Inspect text diffs for individual files
• Commit only the files you select
• Compare the server revision with your local working-copy revision
• Browse recent commits with author, time, and changed paths
• Visualize server commits, the local base, and uncommitted work on a timeline
• Manage a username and macOS Keychain password for each project
• Switch between Korean and English interfaces
• Choose the time zone used for commit timestamps

SVN KR includes the command-line tools and libraries it needs, so users don't need to install Homebrew or SVN separately.

Passwords are stored in macOS Keychain instead of app preference files. Repository connections go directly to the SVN server configured by the user.

## Keywords

version control,developer tools,revision,commit,checkout,working copy,diff

## Categories

Primary: Developer Tools

Secondary: Productivity

## Version 0.5.18 Release Notes

• Identifies outdated scheduled-directory deletions as requiring an update while preserving the original SVN error details.
• Allows Update to run even when the incoming-change list is empty, so conflicts can be reviewed before retrying the commit.
