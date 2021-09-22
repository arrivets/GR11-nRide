import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nkn_sdk_flutter/client.dart';
import 'package:nkn_sdk_flutter/wallet.dart';

import 'utils.dart';
import 'driver.dart';
import 'passenger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Wallet.install();
  Client.install();
  loadMarkers();
  loadMapStyle();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'nRide',
      home: MyHome(),
    );
  }
}

class MyHome extends StatelessWidget {
  const MyHome({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ElevatedButton(
            child: const Text('Driver'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DriverView()),
              );
            },
            style: ElevatedButton.styleFrom(
              fixedSize: const Size.fromWidth(300),
            ),
          ),
          ElevatedButton(
            child: const Text('Passenger'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PassengerView()),
              );
            },
            style: ElevatedButton.styleFrom(
              fixedSize: const Size.fromWidth(300),
            ),
          ),
        ],
      ),
    );
  }
}
