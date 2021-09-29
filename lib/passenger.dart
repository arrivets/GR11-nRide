import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:location/location.dart' as loc;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nkn_sdk_flutter/client.dart';
import 'package:nkn_sdk_flutter/wallet.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';

import 'utils.dart';

class PassengerView extends StatefulWidget {
  const PassengerView({Key? key}) : super(key: key);

  @override
  State<PassengerView> createState() => PassengerViewState();
}

class PassengerViewState extends State<PassengerView> {
  GoogleMapController? _mapController;
  final loc.Location _location = loc.Location();
  GooglePlace? _googlePlace;
  List<AutocompletePrediction> _predictions = [];
  bool _showPredictions = false;
  DetailsResult? _detailsResult;
  final Set<Marker> _markers = <Marker>{};
  final LatLng _initialCameraPostion = const LatLng(20, 20);
  LatLng _currentPosition = const LatLng(20, 20);
  Client? _nknClient;

  @override
  void initState() {
    super.initState();
    _googlePlace = GooglePlace('AIzaSyDUmOaeiGYOjxZoNPd8VS9Xhd0uEAn3k30');
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
        title: const Text("nRide passenger"),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _initialCameraPostion, zoom: 15),
            onMapCreated: _onMapCreated,
            markers: _markers,
            onTap: (LatLng latLng) => setState(() => _showPredictions = false),
          ),
          Container(
            margin: EdgeInsets.only(right: 20, left: 20, top: 20),
            child: Column(
              children: <Widget>[
                TextField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: "Where to",
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.blue,
                        width: 2.0,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.black54,
                        width: 2.0,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty) {
                      _autoCompleteSearch(value);
                      _showPredictions = true;
                    } else {
                      if (_predictions.length > 0 && mounted) {
                        setState(() {
                          _predictions = [];
                        });
                      }
                    }
                  },
                ),
                SizedBox(
                  height: 10,
                ),
                Visibility(
                  visible: _showPredictions,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _predictions.length,
                    itemBuilder: (context, index) {
                      return Container(
                        color: Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              Icons.pin_drop,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(_predictions[index].description!),
                          onTap: () async {
                            debugPrint(_predictions[index].placeId);
                            await _getDetails(_predictions[index].placeId!);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Request user permissions for location services, and wire location services
  // to move camera and marker when location changes.
  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;

    _mapController!.setMapStyle(CustomMapStyle);

    bool _serviceEnabled;
    loc.PermissionStatus _permissionGranted;

    _serviceEnabled = await _location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await _location.hasPermission();
    if (_permissionGranted == loc.PermissionStatus.denied) {
      _permissionGranted = await _location.requestPermission();
      if (_permissionGranted != loc.PermissionStatus.granted) {
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
          icon: UserFocusMarker!,
        ));
      });
      _mapController!.animateCamera(
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

  Future<void> _run() async {
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

  Future<void> _autoCompleteSearch(String value) async {
    var result = await _googlePlace!.autocomplete.get(value);
    if (result != null && result.predictions != null && mounted) {
      setState(() {
        _predictions = result.predictions!;
      });
    }
  }

  Future<void> _getDetails(String placeId) async {
    var result = await _googlePlace!.details.get(placeId);
    if (result != null && result.result != null && mounted) {
      setState(() {
        _detailsResult = result.result;
        _showPredictions = false;
        _markers.add(Marker(
          markerId: const MarkerId(DestinationTag),
          position: LatLng(
            result.result!.geometry!.location!.lat!,
            result.result!.geometry!.location!.lng!,
          ),
          icon: BitmapDescriptor.defaultMarker,
        ));
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            getBounds(_markers.toList()),
            10,
          ),
        );
      });
    }
  }

  LatLngBounds getBounds(List<Marker> markers) {
    var lngs = markers.map<double>((m) => m.position.longitude).toList();
    var lats = markers.map<double>((m) => m.position.latitude).toList();

    double topMost = lngs.reduce(max);
    double leftMost = lats.reduce(min);
    double rightMost = lats.reduce(max);
    double bottomMost = lngs.reduce(min);

    LatLngBounds bounds = LatLngBounds(
      northeast: LatLng(rightMost, topMost),
      southwest: LatLng(leftMost, bottomMost),
    );

    return bounds;
  }
}
