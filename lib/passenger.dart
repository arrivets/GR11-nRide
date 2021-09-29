import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
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
  // controller to update and animate the map view
  GoogleMapController? _mapController;
  final Set<Marker> _markers = <Marker>{};

  // service to track where we are
  final loc.Location _locationService = loc.Location();
  final LatLng _initialCameraPostion = const LatLng(20, 20);
  LatLng _currentPosition = const LatLng(20, 20);

  // service to find destination addresses
  GooglePlace? _googlePlaceService;
  List<AutocompletePrediction> _predictions = [];
  bool _showPredictions = false;
  LatLng? _destination;

  // for drawing routes between current location and destination
  PolylinePoints? _polylinePointsService;
  final Set<Polyline> _polylines = {};

  // client to connect to and use the NKN network
  Client? _nknClient;

  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _googlePlaceService = GooglePlace(GoogleAPIKey);
    _polylinePointsService = PolylinePoints();
  }

  @override
  void dispose() {
    super.dispose();
    _mapController!.dispose();
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
            zoomControlsEnabled: false,
            initialCameraPosition:
                CameraPosition(target: _initialCameraPostion, zoom: 15),
            onMapCreated: _onMapCreated,
            markers: _markers,
            polylines: _polylines,
            onTap: (LatLng latLng) => setState(() => _showPredictions = false),
          ),
          Container(
            margin: EdgeInsets.only(right: 20, left: 20, top: 20),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _inputController,
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
                      if (_predictions.isNotEmpty && mounted) {
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
                            await _chooseDestination(
                                _predictions[index].placeId!);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: (_destination != null)
                ? ElevatedButton(
                    onPressed: () {},
                    child: const Text("Request pickup"),
                  )
                : Container(),
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

    _serviceEnabled = await _locationService.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _locationService.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await _locationService.hasPermission();
    if (_permissionGranted == loc.PermissionStatus.denied) {
      _permissionGranted = await _locationService.requestPermission();
      if (_permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    // set location settings
    _locationService.changeSettings(distanceFilter: 1);

    _locationService.onLocationChanged.listen((l) {
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
          var position = await _locationService.getLocation();
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
    var result = await _googlePlaceService!.autocomplete.get(value);
    if (result != null && result.predictions != null && mounted) {
      setState(() {
        _predictions = result.predictions!;
      });
    }
  }

  Future<void> _chooseDestination(String placeId) async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    // Get location details and draw a Marker
    DetailsResponse? details = await _googlePlaceService!.details.get(placeId);
    if (details != null && details.result != null && mounted) {
      // set destination
      _destination = LatLng(
        details.result!.geometry!.location!.lat!,
        details.result!.geometry!.location!.lng!,
      );

      // set the value of the text input
      var address = details.result!.formattedAddress!;
      _inputController.value = TextEditingValue(
        text: address,
        selection:
            TextSelection.fromPosition(TextPosition(offset: address.length)),
      );

      // hide suggestions and draw destination marker
      setState(() {
        _showPredictions = false;
        _markers.add(Marker(
          markerId: const MarkerId(DestinationTag),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarker,
        ));
      });

      // animate camera to include all markers in the screen
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          _getBounds(_markers.toList()),
          100,
        ),
      );

      // Draw route between current location and destination
      PolylineResult polyRoute =
          await _polylinePointsService!.getRouteBetweenCoordinates(
        GoogleAPIKey, // Google Maps API Key
        PointLatLng(
          _currentPosition.latitude,
          _currentPosition.longitude,
        ),
        PointLatLng(
          _destination!.latitude,
          _destination!.longitude,
        ),
        travelMode: TravelMode.driving,
      );
      List<LatLng> polylineCoordinates = [];
      if (polyRoute.points.isNotEmpty) {
        polyRoute.points.forEach((PointLatLng point) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        });
      }
      setState(() {
        var id = const PolylineId('route');
        _polylines.removeWhere((element) => element.polylineId == id);
        _polylines.add(Polyline(
          polylineId: id,
          color: Colors.black,
          points: polylineCoordinates,
          width: 3,
        ));
      });
    }
  }

  LatLngBounds _getBounds(List<Marker> markers) {
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
