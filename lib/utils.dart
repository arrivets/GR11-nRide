import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const GoogleAPIKey = 'AIzaSyDUmOaeiGYOjxZoNPd8VS9Xhd0uEAn3k30';

const WorldTopic = "nride_world";
const MyLocationTag = "my_location";
const DestinationTag = "destination";

BitmapDescriptor? UserMarker; // indicates passengers in Driver view
BitmapDescriptor? UserFocusMarker; // indicates self in Passenger view
BitmapDescriptor? CarMarker; // indicates drivers in Passenger view
BitmapDescriptor? CarFocusMarker; // indicates self in Driver view

String? CustomMapStyle;

void loadMarkers() {
  // loading icons
  BitmapDescriptor.fromAssetImage(
    const ImageConfiguration(size: Size(48, 48)),
    'assets/user.png',
  ).then((onValue) {
    UserMarker = onValue;
  });
  BitmapDescriptor.fromAssetImage(
    const ImageConfiguration(size: Size(48, 48)),
    'assets/user-focus.png',
  ).then((onValue) {
    UserFocusMarker = onValue;
  });
  BitmapDescriptor.fromAssetImage(
    const ImageConfiguration(size: Size(48, 48)),
    'assets/car.png',
  ).then((onValue) {
    CarMarker = onValue;
  });
  BitmapDescriptor.fromAssetImage(
    const ImageConfiguration(size: Size(48, 48)),
    'assets/car-focus.png',
  ).then((onValue) {
    CarFocusMarker = onValue;
  });
}

void loadMapStyle() {
  rootBundle.loadString('assets/map-style.txt').then((string) {
    CustomMapStyle = string;
  });
}
