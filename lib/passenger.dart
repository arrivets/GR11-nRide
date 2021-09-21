import 'dart:async';
import 'dart:convert';
import 'package:location/location.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nkn_sdk_flutter/client.dart';
import 'package:nkn_sdk_flutter/wallet.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'utils.dart';

class PassengerView extends StatefulWidget {
  const PassengerView({Key? key}) : super(key: key);

  @override
  State<PassengerView> createState() => PassengerViewState();
}

class PassengerViewState extends State<PassengerView> {
  GoogleMapController? _controller;
  final Location _location = Location();
  final Set<Marker> _markers = <Marker>{};
  final LatLng _initialCameraPostion = const LatLng(20, 20);
  LatLng _currentPosition = const LatLng(20, 20);
  Client? _nknClient;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _nknClient?.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("nRide"),
      ),
      body: GoogleMap(
        initialCameraPosition:
            CameraPosition(target: _initialCameraPostion, zoom: 15),
        onMapCreated: _onMapCreated,
        markers: _markers,
      ),
    );
  }

  // Request user permissions for location services, and wire location services
  // to move camera and marker when location changes.
  void _onMapCreated(GoogleMapController controller) async {
    _controller = controller;

    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _serviceEnabled = await _location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await _location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await _location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    // set location settings
    _location.changeSettings(distanceFilter: 1);

    _location.onLocationChanged.listen((l) {
      var currentLatLng = LatLng(l.latitude!, l.longitude!);
      if (currentLatLng == _currentPosition) {
        return;
      }
      setState(() {
        _currentPosition = currentLatLng;
        _markers.add(Marker(
          markerId: const MarkerId(MyLocationTag),
          position: currentLatLng,
          icon: PinMarker!,
        ));
      });
      _controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: currentLatLng,
            zoom: 15,
          ),
        ),
      );
    });

    _run();
  }

  void _run() async {
    // create a new transient wallet
    // in future we might want to persist wallets and accounts to be reused
    Wallet wallet = await Wallet.create(null, config: WalletConfig());
    _nknClient = await Client.create(wallet.seed);

    // once connected, start a timer to periodically ping drivers
    _nknClient?.onConnect.listen((event) async {
      // periodically broadcast my position
      Timer.periodic(
        const Duration(seconds: 2),
        (Timer t) async {
          var position = await _location.getLocation();
          _nknClient?.publishText(
            WorldTopic,
            jsonEncode(
              {
                'latitude': position.latitude!,
                'longitude': position.longitude!,
              },
            ),
          );
        },
      );
    });

    // listen to incoming messages from other users and track their positions.
    _nknClient?.onMessage.listen((event) {
      var source = event.src;
      // if this is me, do nothing
      if (source == _nknClient!.address) {
        return;
      }

      Map<String, dynamic> msg = jsonDecode(event.data!);

      // handle removing markers for users that are leaving
      bool remove = msg['remove'] ?? false;
      if (remove) {
        setState(() {
          _markers.removeWhere((m) => m.markerId == MarkerId(source!));
        });
        return;
      }

      // add or update markers
      var pos = LatLng(
        msg['latitude'],
        msg['longitude'],
      );
      setState(() {
        _markers.add(Marker(
          markerId: MarkerId(source!),
          position: pos,
          icon: CarMarker!,
        ));
      });
    });
  }
}
