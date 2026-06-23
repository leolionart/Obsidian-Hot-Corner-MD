# Release Notes

## v1.0.3-quicknote

- Changed Quick Note Cancel to close the note window without clearing the draft.
- Pointed the in-app GitHub link and update path at the leolionart fork.
- Added Markdown list editing behavior for bullets, checklists, and numbered lists.

## v1.0.4-quicknote

- Prevented the hot-corner monitor from reopening Quick Note immediately after Cancel.
- Allowed the updater to see the fork's Quick Note pre-releases by default.

## v1.0.5-quicknote

- Added local mouse tracking while the Quick Note window is focused.
- Fixed dismissed Quick Notes getting stuck in the active hot-corner state.
- Added Escape handling from the Quick Note window and editor.

## v1.0.6-quicknote

- Fixed in-app update installing an older app when older DMGs were still mounted.
- Mounted update DMGs at a unique temporary path instead of parsing `/Volumes/ObsidianHotCornerMD*`.

## v1.0.7-quicknote

- Fixed the missing Quick Note word count localization.
- Routed Cancel, Save, and Escape through the same dismiss path used by the working status-item close flow.
- Added an Escape key monitor and fallback forced order-out after dismiss.
- Made Preview Width and Preview Lines control the Quick Note window size.
