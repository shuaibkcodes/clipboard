# ClipboardMac

ClipboardMac is a native macOS clipboard history utility built with Swift and
AppKit. It runs as a menu bar app, keeps data local, and uses only system
frameworks.

## What It Does

- Opens with `⌥⌘V` (customizable in Preferences)
- Tracks clipboard changes and stores text, URLs, images, file URLs, HTML, and
  RTF variants
- Lets you search, pin, tag, delete, and re-paste items
- Keeps history local in `~/Library/Application Support/ClipboardMac/`
- Optionally encrypts the stored history (AES-GCM, key in your Keychain)
- Exports and imports the full history as JSON
- Can start automatically at login (macOS 13+)
- Filters common secret patterns and ignores known password manager apps by
  default

## Build

```sh
swift build
./Scripts/make-app.sh
./Scripts/make-app.sh --dmg
```

For App Store release planning, see [`docs/app-store-deployment.md`](docs/app-store-deployment.md).

Open the app with:

```sh
open build/ClipboardMac.app
```

## Usage

The clipboard panel opens with focus on the item list and the first item
selected.

| Key | Action |
| --- | --- |
| `⌥⌘V` (customizable) | Open or close the history panel |
| Type | Search clipboard items (`#tag` searches tags only) |
| `↑` / `↓`, `Page Up` / `Page Down`, `Home` / `End` | Move through items |
| `↩` | Paste the selected item into the previous app |
| `⌘P` | Pin or unpin the selected item |
| `⌘T` | Edit tags for the selected item |
| `⌘⌫` | Delete the selected item |
| `Esc` | Close the panel |

A single click on an item pastes it. Pin and delete actions are also available
per row.

## Preferences

- **Start at login** — registers a login item via `SMAppService` (macOS 13+,
  requires running from the built `.app` bundle).
- **Open panel shortcut** — click the shortcut button, then press the new
  combination (must include ⌘, ⌥, or ⌃). Esc cancels, ⌫ restores `⌥⌘V`.
- **Encrypt clipboard database** — encrypts history text and blob files on
  disk with AES-GCM. The key is created on first use and stored in your
  Keychain. Toggling re-encodes all existing items in place.

## Tags and Export

- Tag items with `⌘T` in the panel; tags show in each row and can be searched
  with `#tag`.
- The menu bar menu offers **Export History…** / **Import History…**. Exports
  are plain (unencrypted) JSON containing all items, tags, and embedded
  image/RTF data — treat exported files as sensitive. Imports skip items that
  already exist.

## Permissions

- Accessibility permission is required only for auto-paste after selecting an
  item.
- No Input Monitoring permission is required because the global shortcut uses
  the Carbon hotkey API.

## Legal

ClipboardMac is intended to be used under the terms of the Apache License 2.0.
In practical terms, that means:

- You may use, modify, and redistribute the software.
- You must keep the copyright and license notices when distributing it.
- If a `NOTICE` file is present, keep its contents in your distributions.
- The software is provided on an `AS IS` basis, without warranties or
  guarantees.

Refer to the full Apache 2.0 license for the complete legal terms before
redistributing or incorporating this project into another product.

## Project Layout

```text
Sources/ClipboardMac/
├── App/            App lifecycle, menu bar, preferences
├── Clipboard/      Capture, read, write, and paste handling
├── Hotkeys/        Global shortcut registration
├── Privacy/        Sensitive data filtering and app exclusions
├── Storage/        SQLite storage and cleanup
├── UI/             Floating panel and preferences window
└── Utilities/      Hashing, file storage, date formatting
```
