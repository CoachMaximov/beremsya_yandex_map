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

    return _initialization ??=
        sdk_init.initMapkit(apiKey: key);
  }

  void acquire(Object owner) {
    if (!_owners.add(owner)) return;

    if (_owners.length == 1) {
      WidgetsBinding.instance.addObserver(this);
    }

    _sync();
  }

  void release(Object owner) {
    if (!_owners.remove(owner)) return;

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

    if (shouldStart == _started) return;

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

  mk_image.ImageProvider? _icon;

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

      if (!mounted) return;

      _icon = mk_image.ImageProvider(
        _drawMarker,
        id: 'beremsya-house-v4',
      );

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

    if (next == _active) return;

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
      _failed = true;
    }

    _syncActivity();
    _refreshMarkers();
  }

  void _onMapCreated(mk.MapWindow window) {
    if (!mounted) return;

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

    if (!data.lengthsMatch) return;

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

      final placemark = houses.addPlacemark()
        ..geometry = mk.Point(
          latitude: lat,
          longitude: lon,
        )
        ..userData = id
        ..setIcon(_icon!)
        ..setText(
          count > 99 ? '99+' : '$count',
        )
        ..setTextStyle(
          const mk.TextStyle(
            size: 15,
            color: Colors.white,
            outlineColor: Color(0x33000000),
            outlineWidth: 1,
            placement:
                mk.TextStylePlacement.Center,
            textOptional: false,
          ),
        );
    }
  }

  Future<ui.Image> _drawMarker() async {
    const width = 58.0;
    const height = 58.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bodyRect = Rect.fromLTRB(
      5,
      4,
      width - 5,
      height - 8,
    );

    final body = RRect.fromRectAndRadius(
      bodyRect,
      const Radius.circular(22),
    );

    // Мягкая тень.
    canvas.drawRRect(
      body.shift(
        const Offset(0, 4),
      ),
      Paint()
        ..color = const Color(0x45001E18)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          6,
        ),
    );

    // Основной объёмный градиент.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(8, 5),
          const Offset(50, 52),
          const [
            Color(0xFF48E4D0),
            Color(0xFF16B6A2),
            Color(0xFF087D70),
          ],
          const [
            0.0,
            0.5,
            1.0,
          ],
        ),
    );

    // Затемнение снизу.
    final lowerRect = Rect.fromLTRB(
      7,
      30,
      width - 7,
      height - 9,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        lowerRect,
        const Radius.circular(18),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 30),
          const Offset(0, 52),
          const [
            Color(0x00000000),
            Color(0x2D003B32),
          ],
        ),
    );

    // Светлый кант.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xBFFFFFFF),
    );

    // Верхний блик.
    final highlightRect = Rect.fromLTRB(
      11,
      8,
      width - 14,
      23,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        highlightRect,
        const Radius.circular(12),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 8),
          const Offset(0, 24),
          const [
            Color(0xAFFFFFFF),
            Color(0x20FFFFFF),
            Color(0x00FFFFFF),
          ],
          const [
            0.0,
            0.6,
            1.0,
          ],
        ),
    );

    // Фирменный оранжевый акцент.
    final accentRect = Rect.fromCenter(
      center: const Offset(
        width / 2,
        height - 7,
      ),
      width: 18,
      height: 5,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        accentRect,
        const Radius.circular(3),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          accentRect.centerLeft,
          accentRect.centerRight,
          const [
            Color(0xFFFFB27B),
            Color(0xFFFF7849),
            Color(0xFFF4512A),
          ],
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
      await widget.inputs.onHouseTap(id);
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
      houses.removeTapListener(_listener);
      houses.clear();
    }

    _houses = null;

    _MapRuntime.instance.release(this);

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
          textAlign: TextAlign.center,
        ),
      );
    }

    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        YandexMap(
          onMapCreated: _onMapCreated,
        ),
        if (!widget.inputs.lengthsMatch)
          const Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Не удалось загрузить отметки домов.',
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

  final Future<void> Function(String) onTap;

  @override
  bool onMapObjectTap(
    mk.MapObject mapObject,
    mk.Point point,
  ) {
    final id = mapObject.userData;

    if (id is! String || id.isEmpty) {
      return false;
    }

    unawaited(onTap(id));

    return true;
  }
}
