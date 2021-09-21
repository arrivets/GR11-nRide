import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:nkn_sdk_flutter/client.dart';
import 'package:nkn_sdk_flutter/wallet.dart';

const _worldTopic = "nride_world";
const _myLocationTag = "my_location";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Wallet.install();
  Client.install();
  runApp(const MyApp());
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
  LatLng _currentPosition = const LatLng(20, 20);
  Client? _nknClient;
  BitmapDescriptor? _customMarker;
  // _subscribed is true when the node is subscribed to the area topic
  bool _subscribed = false;
  // _status indicates status of node between subscribing and unsubscribing. It
  // should be null when the state transition is complete.
  String? _status;

  @override
  void initState() {
    super.initState();

    // loading icons
    BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/user.png',
    ).then((onValue) {
      _customMarker = onValue;
    });
  }

  @override
  void dispose() {
    super.dispose();
    _nknClient?.unsubscribe(topic: _worldTopic);
    _nknClient?.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("nRide"),
        actions: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Text(_status ?? '', textAlign: TextAlign.left),
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition:
            CameraPosition(target: _initialCameraPostion, zoom: 15),
        onMapCreated: _onMapCreated,
        markers: _markers,
      ),
      floatingActionButton: (_subscribed)
          ? FloatingActionButton(
              onPressed: (_status == null) ? _leave : null,
              child: const Text('Leave'),
            )
          : FloatingActionButton(
              onPressed: (_status == null) ? _join : null,
              child: const Text('Join'),
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
          markerId: const MarkerId(_myLocationTag),
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

  void _join() async {
    if (_nknClient != null) {
      return;
    }

    // create a new transient wallet
    // in future we might want to persist wallets and accounts to be reused
    Wallet wallet = await Wallet.create(null, config: WalletConfig());
    _nknClient = await Client.create(wallet.seed);

    // connect to NKN network and subscribe to the area topic.
    setState(() => {_status = 'connecting...'});
    _nknClient?.onConnect.listen((event) async {
      setState(() => {_status = 'subscribing...'});
      await _nknClient?.subscribe(
        topic: _worldTopic,
        duration: 20, // 20 blocks
      );
      while (true) {
        var sub = await _nknClient!.getSubscription(
          topic: _worldTopic,
          subscriber: _nknClient!.address,
        );
        if (sub?.isNotEmpty ?? false) {
          var expiresAt = sub?['expiresAt'] ?? 0;
          if (expiresAt > 0) {
            break;
          }
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      setState(() => {
            _subscribed = true,
            _status = null,
          });
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
            icon: _customMarker ?? BitmapDescriptor.defaultMarker));
      });
    });

    // periodically broadcast my position
    Timer.periodic(
      const Duration(seconds: 5),
      (Timer t) async {
        bool shouldBroadcast = _subscribed && (_status == null);
        if (!shouldBroadcast) {
          return;
        }
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

    // periodically clear unsubscribed users
    Timer.periodic(
      const Duration(seconds: 5),
      (Timer t) async {
        bool shouldQuery = _subscribed && (_status == null);
        if (!shouldQuery) {
          return;
        }
        var subscriptions =
            await _nknClient!.getSubscribers(topic: _worldTopic);
        setState(() {
          _markers.removeWhere((element) =>
              element.markerId.value != _myLocationTag &&
              !subscriptions!.containsKey(element.markerId.value));
        });
      },
    );
  }

  void _leave() async {
    if (_nknClient != null) {
      // setting _status to a non-null value will cause the timers that
      // broadcast our position and clear orphan markers to be stopped.
      setState(() => {
            _status = 'unsubscribing...',
          });

      // notify other users that I am leaving
      _nknClient?.publishText(
        _worldTopic,
        jsonEncode(
          {
            'remove': true,
          },
        ),
      );

      // unsubscribe and close
      await _nknClient?.unsubscribe(topic: _worldTopic);
      while (true) {
        var sub = await _nknClient!.getSubscription(
          topic: _worldTopic,
          subscriber: _nknClient!.address,
        );
        if (sub?.isNotEmpty ?? false) {
          var expiresAt = sub?['expiresAt'] ?? 0;
          if (expiresAt == 0) {
            break;
          }
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() => _status = 'disconnecting...');
      await _nknClient!.close();
      setState(() => {
            _subscribed = false,
            _status = null,
            _nknClient = null,
            _markers.removeWhere(
                (element) => element.markerId.value != _myLocationTag),
          });
    }
  }
}
