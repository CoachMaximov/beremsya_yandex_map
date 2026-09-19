import 'package:flutter/material.dart';
import 'map_inputs.dart';

Widget buildOrdersMap(MapInputs inputs) => const ColoredBox(
  color: Color(0xFFF2F4F7),
  child: Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Карта доступна в приложении для iOS и Android.',
        textAlign: TextAlign.center,
      ),
    ),
  ),
);
