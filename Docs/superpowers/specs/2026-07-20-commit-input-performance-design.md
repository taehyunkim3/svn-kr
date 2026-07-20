# Commit Input Performance Design

## Problem

`ChangesView` owns both the commit-message `@State` and the changed-file `List`. Every text edit invalidates the parent view, recreates the list input, and evaluates a newly concatenated status array. With tens of thousands of changed paths, this blocks the main thread enough for text input and Korean composition to lag behind the caret.

## Design

Extract the commit-message field and its controls into a dedicated `CommitControlsView`. The child view owns `commitMessage` and focus state, while it reads only the store values and actions required for selection and commit. Editing the message therefore invalidates the controls subtree rather than the changed-file list subtree.

Replace `displayedStatuses`, which currently concatenates `statuses` and `ignoredStatuses`, with list sections that consume each existing collection directly. The regular-status section is always present; the ignored-status section is conditionally present when ignored files are visible. No combined array is allocated during view evaluation, and stable `SVNStatusEntry.id` values continue to identify rows.

The existing `WorkspaceSplitView`, toolbar, list container, empty-state overlay, diff panel, and layout constants remain unchanged.

## Behavior

- The commit message clears after a completed direct or resumed authenticated commit.
- Return and the commit button both finish text composition before submitting.
- Select All, Clear Selection, selected-count display, disabled state, and commit progress retain their current behavior.
- Ignored entries appear after regular entries when enabled and remain non-selectable.
- The empty-state overlay appears only when neither visible collection contains entries.

## Verification

- Add source-structure regression tests proving commit input state is owned by the isolated controls view and the changed-file list no longer uses concatenated status arrays.
- Run `swift test` for the full package.
- Review the layout combinations in `Docs/LayoutArchitecture.md`; this change does not alter size ownership or introduce a split view.
