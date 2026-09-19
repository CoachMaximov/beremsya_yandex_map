# beremsya_yandex_map

Small FlutterFlow adapter for the official `yandex_maps_mapkit_lite` **4.42.0**.
It keeps the native SDK out of the Web import graph and renders a placeholder on
Web. No API keys, Supabase settings, or app code are included in this package.

Requirements: Flutter >=3.29, Android API >=26, Android Java 21 build toolchain,
iOS >=15. Use CocoaPods for this SDK version; its SwiftPM manifest has an empty
native dependency version.

Import only `package:beremsya_yandex_map/beremsya_yandex_map.dart`.
Never import or export `src/map_native.dart` from an application barrel.

`OrdersMap` requires matching `latitudes`, `longitudes`, `houseIds`, `addresses`,
`ordersCounts` lists, an `apiKey`, and `onHouseTap(String houseId)` callback.
Give the widget bounded width/height. Initialization is lazy and memoized for the
Dart isolate. Do not also initialize from an app action. After a key change or
failed native initialization, restart the application process.

Empty lists show the map centered at 55.6160, 37.4125 with zoom 15.5. Invalid
coordinates, empty IDs, zero/negative counts and duplicate house IDs are skipped.
Mismatching list lengths show a data error and no markers. Map camera position is
not reset on list updates. Markers are rebuilt when list contents change.

The package owns global onStart/onStop calls for its map instances and handles
application lifecycle, route visibility, TickerMode and an explicit `isActive`
flag. For a retained IndexedStack tab, wire isActive to the selected tab; an
IndexedStack alone does not guarantee correct visibility detection. The supplied
FlutterFlow project currently replaces the selected page instead.

No geolocation, location prompts, routing, native key injection, backend queries,
or order mutations are performed. SDK authentication errors may be asynchronous;
successful initMapkit completion does not prove the key is valid.

For FlutterFlow, host this directory as a Git package and add its dependency in
Custom Dependencies, pinned to a commit. This is separate from FlutterFlow's
"Connect GitHub Repo" project-export feature. For a downloaded Flutter project,
a local path dependency also works; FlutterFlow cloud builds cannot access that
local path.

See ../INTEGRATION_RU.md for project-specific steps and verification status.
