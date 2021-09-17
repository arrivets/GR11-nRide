import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:nkn_sdk_flutter/client.dart';
import 'package:nkn_sdk_flutter/utils/hash.dart';
import 'package:nkn_sdk_flutter/utils/hex.dart';
import 'package:nkn_sdk_flutter/wallet.dart';

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
      floatingActionButton: FloatingActionButton(
        onPressed: _join,
        child: const Text('Join'),
      ),
    );
  }

  void _join() async {
    if (_nknClient == null) {
      Wallet wallet = await Wallet.restore(
          '{"Version":2,"IV":"d103adf904b4b2e8cca9659e88201e5d","MasterKey":"20042c80ccb809c72eb5cf4390b29b2ef0efb014b38f7229d48fb415ccf80668","SeedEncrypted":"3bcdca17d84dc7088c4b3f929cf1e96cf66c988f2b306f076fd181e04c5be187","Address":"NKNVgahGfYYxYaJdGZHZSxBg2QJpUhRH24M7","Scrypt":{"Salt":"a455be75074c2230","N":32768,"R":8,"P":1}}',
          config: WalletConfig(password: '123'));

      _nknClient = await Client.create(wallet.seed);
    }
    _nknClient?.onConnect.listen((event) {
      print('------onConnect1-----');
      print(event.node);
    });
    _nknClient?.onMessage.listen((event) {
      print('------onMessage1-----');
      print(event.type);
      print(event.encrypted);
      print(event.messageId);
      print(event.data);
      print(event.src);
    });
    // genChannelId('nride_world')
    var res = await _nknClient?.subscribe(topic: 'nride_world');
    print(res);
  }
}
