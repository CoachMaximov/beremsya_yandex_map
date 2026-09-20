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

      if (!mounted) {
        return;
      }

      _icon = mk_image.ImageProvider(
        _drawMarker,
        id: 'beremsya-house-v5',
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
        ..setIcon(_icon!)
        ..setText(
          count > 99 ? '99+' : '$count',
        )
        ..setTextStyle(
          const mk.TextStyle(
            size: 17,
            color: Colors.white,
            outlineColor: Color(0x66000000),
            outlineWidth: 1.5,
            placement:
                mk.TextStylePlacement.Center,
            textOptional: false,
          ),
        );
    }
  }

  Future<ui.Image> _drawMarker() async {
    const size = 64.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const center = Offset(
      size / 2,
      30,
    );

    // Простая тень снизу.
    canvas.drawCircle(
      center + const Offset(0, 4),
      27,
      Paint()
        ..color = const Color(
          0x33000000,
        ),
    );

    // Белый внешний кант.
    canvas.drawCircle(
      center,
      27,
      Paint()..color = Colors.white,
    );

    // Нижняя тёмная подложка,
    // чтобы появился эффект объёма.
    canvas.drawCircle(
      center + const Offset(0, 2),
      24,
      Paint()
        ..color = const Color(
          0xFF087165,
        ),
    );

    // Основной бирюзовый круг.
    canvas.drawCircle(
      center,
      24,
      Paint()
        ..color = const Color(
          0xFF19B7A3,
        ),
    );

    // Светлая верхняя зона.
    canvas.drawOval(
      const Rect.fromLTRB(
        17,
        9,
        47,
        29,
      ),
      Paint()
        ..color = const Color(
          0x554FFFF0,
        ),
    );

    // Внутренняя светлая рамка.
    canvas.drawCircle(
      center,
      22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(
          0x80FFFFFF,
        ),
    );

    // Нижний объёмный сегмент.
    final lowerArcRect =
        Rect.fromCircle(
      center: center,
      radius: 23,
    );

    canvas.save();

    canvas.clipRect(
      const Rect.fromLTRB(
        8,
        31,
        56,
        56,
      ),
    );

    canvas.drawCircle(
      center,
      23,
      Paint()
        ..color = const Color(
          0x22002D27,
        ),
    );

    canvas.restore();

    // Фирменный оранжевый акцент.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(
          24,
          55,
          16,
          5,
        ),
        const Radius.circular(3),
      ),
      Paint()
        ..color = const Color(
          0xFFFF7045,
        ),
    );

    final picture =
        recorder.endRecording();

    try {
      return await picture.toImage(
        size.round(),
        size.round(),
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
