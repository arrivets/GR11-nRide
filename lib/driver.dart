import 'dart:async';
import 'dart:convert';
import 'package:location/location.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nkn_sdk_flutter/client.dart';
import 'package:nkn_sdk_flutter/wallet.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'utils.dart';

class DriverView extends StatefulWidget {
  const DriverView({Key? key}) : super(key: key);

  @override
  State<DriverView> createState() => DriverViewState();
}

class DriverViewState extends State<DriverView> {
  GoogleMapController? _controller;
  final Location _location = Location();
  final Set<Marker> _markers = <Marker>{};
  final LatLng _initialCameraPostion = const LatLng(20, 20);
  LatLng _currentPosition = const LatLng(20, 20);
  Client? _nknClient;

  // _subscribed is true when the node is subscribed to the area topic
  bool _subscribed = false;
  // _status indicates status of node between subscribing and unsubscribing. It
  // should be null when the state transition is complete.
  String? _status;

  String? _pendingRequestId;
  String? _requestSource;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _nknClient?.unsubscribe(topic: WorldTopic);
    _nknClient?.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("nRide driver"),
        automaticallyImplyLeading: false,
        actions: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Text(_status ?? '', textAlign: TextAlign.left),
          ),
        ],
      ),
      body: Stack(children: <Widget>[
        GoogleMap(
          zoomControlsEnabled: false,
          initialCameraPosition:
              CameraPosition(target: _initialCameraPostion, zoom: 15),
          onMapCreated: _onMapCreated,
          markers: _markers,
        ),
        Positioned(
          // this is a button that pops up when we receive a pickup request and
          // disappears when the request is accepted and confirmed
          left: 20,
          right: 20,
          bottom: 100,
          child: (_pendingRequestId != null)
              ? ElevatedButton(
                  onPressed: _acceptRequest,
                  child: Text(
                      'Accept pickup request (${_pendingRequestId!.substring(0, 4)}...)'),
                )
              : Container(),
        )
      ]),
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

    _controller!.setMapStyle(CustomMapStyle);

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
          icon: CarFocusMarker!,
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
        topic: WorldTopic,
        duration: 20, // 20 blocks
      );
      while (true) {
        var sub = await _nknClient!.getSubscription(
          topic: WorldTopic,
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
    _nknClient?.onMessage.listen((event) async {
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

      // handle pickup requests
      var isRequest = msg['request'] ?? false;
      if (isRequest) {
        print('XXX in request');
        var requestId = msg['request_id'];
        if (requestId != null) {
          setState(
            () => {
              _requestSource = source,
              _pendingRequestId = requestId,
            },
          );
          return;
        }
      }

      // handle pickup confirm
      var isConfirm = msg['confirm'] ?? false;
      if (isConfirm) {
        print('XXX in confirm');
        var requestId = msg['request_id'];
        if (requestId != null && requestId! == _pendingRequestId) {
          var txt = '$source confirmed request (${requestId!})';
          _showConfirmDialog(txt);
        }
        return;
      }

      // if we got this far, the message was a location update
      // add or update markers
      print('XXX location update');
      var pos = LatLng(
        msg['latitude'],
        msg['longitude'],
      );
      setState(() {
        _markers.add(Marker(
          markerId: MarkerId(source!),
          position: pos,
          icon: UserMarker!,
        ));
      });

      // respond directly to sender
      var position = await _location.getLocation();
      _nknClient!.sendText(
        <String>[source!],
        jsonEncode(
          {
            'latitude': position.latitude!,
            'longitude': position.longitude!,
          },
        ),
      );
    });
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
        WorldTopic,
        jsonEncode(
          {
            'remove': true,
          },
        ),
      );

      // unsubscribe and close
      try {
        await _nknClient?.unsubscribe(topic: WorldTopic);
        while (true) {
          var sub = await _nknClient!.getSubscription(
            topic: WorldTopic,
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
      } catch (e) {
        print('error trying to unsubscribe: ${e.toString()}');
      }

      setState(() => _status = 'disconnecting...');
      await _nknClient!.close();
      setState(() => {
            _subscribed = false,
            _status = null,
            _nknClient = null,
            _markers.removeWhere(
                (element) => element.markerId.value != MyLocationTag),
          });
    }
  }

  void _acceptRequest() async {
    _nknClient!.sendText(
      <String>[_requestSource!],
      jsonEncode(
        {
          'request_id': _pendingRequestId!,
        },
      ),
    );
  }

  Future<void> _showConfirmDialog(String msg) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pickup Confirmed'),
          content: SingleChildScrollView(
            child: Text(msg),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                setState(() => {
                      _pendingRequestId = null,
                      _requestSource = null,
                    });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
