# Route Builder

iPhone client for a dispatcher building a morning van route. It talks to the mock dispatch API.

## Run

Node 18 or newer:

```sh
node MockServer/server.js
```

The server listens on port 4000. Open `Route Builder.xcodeproj` and run the **Route Builder** scheme on an iPhone simulator.

The base URL is `http://127.0.0.1:4000`. It is set in `Route Builder/AppConfig.swift`. The simulator reaches that host directly. A physical iPhone on the same Wi-Fi needs this computer’s LAN address in `AppConfig.baseURL` instead.

`Route Builder/Info.plist` allows local networking so the debug app can call the plain HTTP server.

## Tests

```sh
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,name=iPhone 16"
```
