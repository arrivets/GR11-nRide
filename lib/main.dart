import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:nkn_sdk_flutter/client.dart';
import 'package:nkn_sdk_flutter/wallet.dart';

const _worldTopic = "nride_world";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Wallet.install();
  Client.install();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Maps',
      home: MapSample(),
    );
  }
}

class MapSample extends StatefulWidget {
  const MapSample({Key? key}) : super(key: key);

  @override
  State<MapSample> createState() => MapSampleState();
}

class MapSampleState extends State<MapSample> {
  GoogleMapController? _controller;
  final Location _location = Location();
  final Set<Marker> _markers = <Marker>{};
  final LatLng _initialCameraPostion = const LatLng(20, 20);
  Client? _nknClient;
  BitmapDescriptor? _customMarker;

  @override
  void initState() {
    super.initState();
    BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/user.png',
    ).then((onValue) {
      _customMarker = onValue;
    });
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

    _location.changeSettings(distanceFilter: 1);

    _location.onLocationChanged.listen((l) {
      var currentLatLng = LatLng(l.latitude!, l.longitude!);
      setState(() {
        _markers.add(Marker(
          markerId: const MarkerId('current_location'),
          position: currentLatLng,
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
  }

  @override
  void dispose() {
    super.dispose();
    _nknClient?.unsubscribe(topic: _worldTopic);
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
      floatingActionButton: (_nknClient == null)
          ? FloatingActionButton(
              onPressed: _join,
              child: const Text('Join'),
            )
          : FloatingActionButton(
              onPressed: _leave,
              child: const Text('Leave'),
            ),
    );
  }

  void _join() async {
    if (_nknClient == null) {
      // create a new transient wallet
      // in future we might want to persist wallets and accounts to be reused
      Wallet wallet = await Wallet.create(null, config: WalletConfig());
      _nknClient = await Client.create(wallet.seed);
    }
    _nknClient?.onConnect.listen((event) {
      print('------onConnect1-----');
      print(event.node);
    });
    _nknClient?.onMessage.listen((event) {
      var source = event.src;
      Map<String, dynamic> msg = jsonDecode(event.data!);
      var pos = LatLng(
        msg['latitude'],
        msg['longitude'],
      );
      setState(() {
        _markers.add(Marker(
            markerId: MarkerId(source!),
            position: pos,
            icon: _customMarker ?? BitmapDescriptor.defaultMarker));
      });
    });
    var res = await _nknClient?.subscribe(topic: _worldTopic);
    print(res);
    Timer.periodic(
      const Duration(seconds: 5),
      (Timer t) async {
        var position = await _location.getLocation();
        _nknClient?.publishText(
          _worldTopic,
          jsonEncode(
            {
              'latitude': position.latitude!,
              'longitude': position.longitude!,
            },
          ),
        );
      },
    );
  }

  void _leave() async {
    if (_nknClient != null) {
      await _nknClient?.unsubscribe(topic: _worldTopic);
      setState(() => {_nknClient = null});
    }
  }
}
