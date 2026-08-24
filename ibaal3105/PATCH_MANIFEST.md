# ibaal3105 Patch Build

Baseline: uploaded 3105 source (1.1.1)

## Included
- 3105 modern SwiftUI navigation retained.
- Cyan accent theme.
- Home device label changed to `Device Model` and shows the friendly model name.
- Telegram social card for `ibaal` / `@meugom`.
- Recursive Plist Editor with add/edit/delete.
- Boolean, String, Number, Data, Date, Array and Dictionary values.
- Search/filter for plist keys and values.
- Actual serialized plist byte-size comparison.
- Overwrite is disabled when the edited file is larger than the original.
- Best-effort adjacent backup before overwrite.
- Dedicated system target display for:
  `/var/db/com.apple.xpc.launchd/disable.plist`
- Existing 3105 Files, Patch Workspace, Cleaner and Wallpaper Lab/Tendies sources retained.
- Bundle identifier remains `com.apple.mobile.MobileHouseArrest`.

## Important
The Plist Editor can open a user-selected plist or attempt the configured system target. Actual access to a protected system path depends on the backend/capability available on the device. The UI does not claim access merely from the configured path.

This package is source code. It has not been signed or packaged as an IPA.
