import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit_lite/init.dart' as sdk_init;
import 'package:yandex_maps_mapkit_lite/mapkit.dart' as mk;
import 'package:yandex_maps_mapkit_lite/mapkit_factory.dart' as yfactory;
import 'package:yandex_maps_mapkit_lite/image.dart' as mk_image;
import 'package:yandex_maps_mapkit_lite/yandex_map.dart';

import 'map_inputs.dart';
import 'map_stub.dart' as stub;

Widget buildOrdersMap(MapInputs inputs) {
  if (!Platform.isIOS && !Platform.isAndroid) {
    return stub.buildOrdersMap(inputs);
  }

  return _NativeOrdersMap(inputs: inputs);
}

// One initialization Future and one lifecycle owner for the whole Dart isolate.
// Do not initialize MapKit independently in a Custom Action or main.dart.
class _MapRuntime with WidgetsBindingObserver {
  static final instance = _MapRuntime();

  Future<void>? _initialization;
  String? _key;

  final Set<Object> _owners = {};

  bool _started = false;

  Future<void> ensureInitialized(String apiKey) {
    final key = apiKey.trim();

    if (key.isEmpty) {
      return Future.error(
        StateError('Map key is missing'),
      );
    }

    if (_key != null && _key != key) {
      return Future.error(
        StateError('Restart required after key change'),
      );
    }

    _key = key;

    // Keep a failed Future too:
    // a partly initialized native SDK needs a restart.
    return _initialization ??=
        sdk_init.initMapkit(apiKey: key);
  }

  void acquire(Object owner) {
    if (!_owners.add(owner)) {
      return;
    }

    if (_owners.length == 1) {
      WidgetsBinding.instance.addObserver(this);
    }

    _sync();
  }

  void release(Object owner) {
    if (!_owners.remove(owner)) {
      return;
    }

    _sync();

    if (_owners.isEmpty) {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  void _sync() {
    final state = WidgetsBinding.instance.lifecycleState;

    final shouldStart =
        _owners.isNotEmpty &&
        (state == null ||
            state == AppLifecycleState.resumed);

    if (shouldStart == _started) {
      return;
    }

    if (shouldStart) {
      yfactory.mapkit.onStart();
    } else {
      yfactory.mapkit.onStop();
    }

    _started = shouldStart;
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    _sync();
  }
}

class _NativeOrdersMap extends StatefulWidget {
  const _NativeOrdersMap({
    required this.inputs,
  });

  final MapInputs inputs;

  @override
  State<_NativeOrdersMap> createState() =>
      _NativeOrdersMapState();
}

class _NativeOrdersMapState
    extends State<_NativeOrdersMap> {
  mk.MapObjectCollection? _houses;

  final Map<String, mk_image.ImageProvider>
      _markerIcons = {};

  late final _HouseTapListener _listener =
      _HouseTapListener(_handleTap);

  bool _ready = false;
  bool _failed = false;
  bool _active = false;
  bool _routeVisible = true;
  bool _busy = false;

  List<Object> _lastData = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _MapRuntime.instance.ensureInitialized(
        widget.inputs.apiKey,
      );

      if (!mounted) {
        return;
      }

      _ready = true;

      _syncActivity();

      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _routeVisible =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.of(context);

    _syncActivity();
  }

  void _syncActivity() {
    final next =
        _ready &&
        !_failed &&
        widget.inputs.isActive &&
        _routeVisible;

    if (next == _active) {
      return;
    }

    if (next) {
      _MapRuntime.instance.acquire(this);
    } else {
      _MapRuntime.instance.release(this);
    }

    _active = next;
  }

  @override
  void didUpdateWidget(
    covariant _NativeOrdersMap oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.inputs.apiKey !=
        widget.inputs.apiKey) {
      // Changing SDK credentials in a running
      // native process is unsupported here.
      _failed = true;
    }

    _syncActivity();
    _refreshMarkers();
  }

  void _onMapCreated(mk.MapWindow window) {
    if (!mounted) {
      return;
    }

    _houses =
        window.map.mapObjects.addCollection();

    _houses!.addTapListener(_listener);

    window.map.move(
      const mk.CameraPosition(
        mk.Point(
          latitude: 55.6160,
          longitude: 37.4125,
        ),
        zoom: 15.5,
        azimuth: 0,
        tilt: 0,
      ),
    );

    _lastData = const [];

    _refreshMarkers(force: true);
  }

  void _refreshMarkers({
    bool force = false,
  }) {
    final houses = _houses;

    if (houses == null || !houses.isValid()) {
      return;
    }

    final data = widget.inputs;

    // A copy detects mutation of an existing
    // list as well as list replacement.
    final fingerprint = <Object>[
      ...data.latitudes,
      '|lat',
      ...data.longitudes,
      '|lon',
      ...data.houseIds,
      '|id',
      ...data.addresses,
      '|address',
      ...data.ordersCounts,
    ];

    if (!force &&
        listEquals(
          fingerprint,
          _lastData,
        )) {
      return;
    }

    _lastData = fingerprint;

    houses.clear();

    if (!data.lengthsMatch) {
      return;
    }

    final seen = <String>{};

    for (var i = 0;
        i < data.houseIds.length;
        i++) {
      final id = data.houseIds[i];
      final lat = data.latitudes[i];
      final lon = data.longitudes[i];
      final count = data.ordersCounts[i];

      if (id.isEmpty ||
          count <= 0 ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lon < -180 ||
          lon > 180 ||
          !seen.add(id)) {
        continue;
      }

      houses.addPlacemark()
        ..geometry = mk.Point(
          latitude: lat,
          longitude: lon,
        )
        ..userData = id
        ..setIcon(
          _markerIconForCount(count),
        );
    }
  }

  mk_image.ImageProvider _markerIconForCount(
    int count,
  ) {
    final label =
        count > 99 ? '99+' : '$count';

    final cacheKey =
        label.replaceAll('+', 'plus');

    return _markerIcons.putIfAbsent(
      label,
      () => mk_image.ImageProvider(
        () => _drawMarker(label),
        id: 'beremsya-house-v3-$cacheKey',
      ),
    );
  }

  Future<ui.Image> _drawMarker(
    String label,
  ) async {
    final width = label.length == 1
        ? 66.0
        : label.length == 2
            ? 74.0
            : 86.0;

    const height = 66.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final shadowRect = Rect.fromLTRB(
      6,
      8,
      width - 6,
      59,
    );

    final shadowRRect =
        RRect.fromRectAndRadius(
      shadowRect,
      const Radius.circular(23),
    );

    // Deep soft shadow.
    canvas.drawRRect(
      shadowRRect.shift(
        const Offset(0, 4),
      ),
      Paint()
        ..color =
            const Color(0x4200201B)
        ..maskFilter =
            const MaskFilter.blur(
          BlurStyle.normal,
          7,
        ),
    );

    // Secondary diffuse shadow.
    canvas.drawRRect(
      shadowRRect.shift(
        const Offset(0, 2),
      ),
      Paint()
        ..color =
            const Color(0x26000000)
        ..maskFilter =
            const MaskFilter.blur(
          BlurStyle.normal,
          3,
        ),
    );

    final bodyRect = Rect.fromLTRB(
      5,
      5,
      width - 5,
      56,
    );

    final bodyRRect =
        RRect.fromRectAndRadius(
      bodyRect,
      const Radius.circular(23),
    );

    // Main Beremsya turquoise gradient.
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader =
            ui.Gradient.linear(
          Offset(
            width * 0.18,
            4,
          ),
          Offset(
            width * 0.78,
            58,
          ),
          const [
            Color(0xFF45E6D1),
            Color(0xFF17B5A2),
            Color(0xFF078475),
            Color(0xFF04665E),
          ],
          const [
            0.0,
            0.38,
            0.72,
            1.0,
          ],
        ),
    );

    // Inner depth at the bottom.
    final bottomShadeRect =
        Rect.fromLTRB(
      8,
      34,
      width - 8,
      54,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bottomShadeRect,
        const Radius.circular(18),
      ),
      Paint()
        ..shader =
            ui.Gradient.linear(
          Offset(
            width / 2,
            34,
          ),
          Offset(
            width / 2,
            54,
          ),
          const [
            Color(0x00000000),
            Color(0x30002F29),
          ],
        ),
    );

    // Fine bright rim.
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..style =
            PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(
          0xBFFFFFFF,
        ),
    );

    // Glossy upper highlight.
    final highlightRect =
        Rect.fromLTRB(
      12,
      9,
      width - 15,
      27,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        highlightRect,
        const Radius.circular(13),
      ),
      Paint()
        ..shader =
            ui.Gradient.linear(
          const Offset(0, 9),
          const Offset(0, 28),
          const [
            Color(0xA8FFFFFF),
            Color(0x35FFFFFF),
            Color(0x00FFFFFF),
          ],
          const [
            0.0,
            0.55,
            1.0,
          ],
        ),
    );

    // Small orange brand accent.
    final accentRect =
        Rect.fromCenter(
      center: Offset(
        width / 2,
        55,
      ),
      width: 22,
      height: 6,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        accentRect,
        const Radius.circular(4),
      ),
      Paint()
        ..shader =
            ui.Gradient.linear(
          accentRect.centerLeft,
          accentRect.centerRight,
          const [
            Color(0xFFFFB582),
            Color(0xFFFF7A4C),
            Color(0xFFF4512A),
          ],
        ),
    );

    // Order count.
    final textPainter =
        TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize:
              label.length >= 3
                  ? 18
                  : 22,
          fontWeight:
              FontWeight.w800,
          letterSpacing: -0.4,
          shadows: const [
            Shadow(
              color:
                  Color(0x50000000),
              blurRadius: 4,
              offset:
                  Offset(0, 1.5),
            ),
          ],
        ),
      ),
      textDirection:
          TextDirection.ltr,
      textAlign:
          TextAlign.center,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (width -
                textPainter.width) /
            2,
        30 -
            textPainter.height / 2,
      ),
    );

    final picture =
        recorder.endRecording();

    try {
      return await picture.toImage(
        width.round(),
        height.round(),
      );
    } finally {
      picture.dispose();
    }
  }

  Future<void> _handleTap(
    String id,
  ) async {
    if (!mounted ||
        !_active ||
        _busy) {
      return;
    }

    _busy = true;

    try {
      await widget.inputs
          .onHouseTap(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось открыть заказы дома.',
            ),
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    final houses = _houses;

    if (houses != null &&
        houses.isValid()) {
      houses.removeTapListener(
        _listener,
      );
      houses.clear();
    }

    _houses = null;

    _MapRuntime.instance
        .release(this);

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_failed) {
      return const Center(
        child: Text(
          'Не удалось запустить карту. '
          'Перезапустите приложение.',
          textAlign:
              TextAlign.center,
        ),
      );
    }

    if (!_ready) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        YandexMap(
          onMapCreated:
              _onMapCreated,
        ),
        if (!widget.inputs
            .lengthsMatch)
          const Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              child: Padding(
                padding:
                    EdgeInsets.all(
                  12,
                ),
                child: Text(
                  'Не удалось загрузить '
                  'отметки домов.',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HouseTapListener
    implements mk.MapObjectTapListener {
  _HouseTapListener(this.onTap);

  final Future<void> Function(
    String,
  ) onTap;

  @override
  bool onMapObjectTap(
    mk.MapObject mapObject,
    mk.Point point,
  ) {
    final id =
        mapObject.userData;

    if (id is! String ||
        id.isEmpty) {
      return false;
    }

    unawaited(
      onTap(id),
    );

    return true;
  }
}
