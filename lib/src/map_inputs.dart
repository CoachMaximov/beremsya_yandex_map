class MapInputs {
  const MapInputs({
    required this.apiKey,
    required this.latitudes,
    required this.longitudes,
    required this.houseIds,
    required this.addresses,
    required this.ordersCounts,
    required this.onHouseTap,
    required this.isActive,
  });

  final String apiKey;
  final List<double> latitudes;
  final List<double> longitudes;
  final List<String> houseIds;
  final List<String> addresses;
  final List<int> ordersCounts;
  final Future Function(String houseId) onHouseTap;
  final bool isActive;

  bool get lengthsMatch =>
      latitudes.length == houseIds.length &&
      longitudes.length == houseIds.length &&
      addresses.length == houseIds.length &&
      ordersCounts.length == houseIds.length;
}
