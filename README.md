# nRide
## A free and decentralized Uber-like service powered by NKN

For more information please visit our [project website](https://nride.org)

This project is intended as a submission to 
[NKN's open innovation Gitcoin grant](https://gitcoin.co/issue/nknorg/nBounty/8/100026451),
and welcomes new contributors. 

Here is the demo video: https://www.youtube.com/watch?v=99owl1Bdnaw

## Getting Started

This project is built with Flutter.

For help getting started with Flutter, view the
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Roadmap

The following is a high level roadmap of what we would like to achieve as part
of the [hackathon](https://gitcoin.co/issue/nknorg/nBounty/8/100026451).

- [ ] Android
  - [x] Display a map with current location 
  - [x] Create/Join NKN pub/sub group corresponding to geographical area
  - [x] Display positions of other users in the same area
    - [x] Different UI for riders and passengers. 
    - [x] Riders subscribe to topic
    - [x] Passengers periodically publish their location to topic
    - [x] Riders respond to passengers through direct channel.
    - [x] Riders and passengers display markers on the map.
  - [x] Passengers send 'request' to available riders
  - [x] Rider gets a notification with the ability to accept
  - [x] Passenger receives a notification and has ability to confirm
  - [x] Realtime position updates between passenger and rider
- [ ] iOS 

