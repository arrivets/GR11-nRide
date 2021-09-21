# nRide
## A free and decentralized Uber-like service powered by NKN

For more information please visit our [project website](https://nride.org)

This project is intended as a submission to 
[NKN's open innovation Gitcoin grant](https://gitcoin.co/issue/nknorg/nBounty/8/100026451),
and welcomes new contributors. 

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
  - [ ] Passengers send 'request' to available riders
  - [ ] Riders automatically send a 'response'
  - [ ] Passenger selects 'best' response and establishes 1-1 communication
        with selected rider
  - [ ] Realtime position updates between passenger and rider
- [ ] iOS 

