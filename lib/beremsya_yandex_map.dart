import 'package:flutter/widgets.dart';
import 'src/map_inputs.dart';
import 'src/map_stub.dart'
    if (dart.library.io) 'src/map_native.dart'
    as platform;

class OrdersMap extends StatelessWidget {
  const OrdersMap({
    super.key,
    this.width,
    this.height,
    required this.apiKey,
    required this.latitudes,
    required this.longitudes,
    required this.houseIds,
    required this.addresses,
    required this.ordersCounts,
    required this.onHouseTap,
    this.isActive = true,
  });

  final double? width;
  final double? height;
  final String apiKey;
  final List<double> latitudes;
  final List<double> longitudes;
  final List<String> houseIds;
  final List<String> addresses;
  final List<int> ordersCounts;
  final Future Function(String houseId) onHouseTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: platform.buildOrdersMap(
      MapInputs(
        apiKey: apiKey,
        latitudes: latitudes,
        longitudes: longitudes,
        houseIds: houseIds,
        addresses: addresses,
        ordersCounts: ordersCounts,
        onHouseTap: onHouseTap,
        isActive: isActive,
      ),
    ),
  );
}
