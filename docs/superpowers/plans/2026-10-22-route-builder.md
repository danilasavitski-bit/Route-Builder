# Route Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the two-screen Route Builder client from the design spec: pick stops, write instructions, send one route, and stay up when the mock server misbehaves.

**Architecture:** Programmatic UIKit. `SceneDelegate` installs `DepotViewController`, which owns the header, the Stops / Instructions switch, one `RouteDraftStore`, and one `APIClient`. View models do not import UIKit. `APIClient` is the only type that performs HTTP and the only type that normalizes the payload.

**Tech Stack:** Swift 5, UIKit, async/await, URLSession, XCTest, iOS 16+. No third-party packages.

## Global Constraints

- English, left to right. Portrait iPhone only. Deployment target 16.0.
- Base URL is exactly `http://127.0.0.1:4000`.
- Instruction field and counter stop at 200 characters.
- Unparseable or null `packages_max` becomes 9.
- List page size is 50. Stop paging on an empty page, `items: null`, or a page with no new ids. Ignore `total`, `total_pages`, and `has_more`.
- Retry only HTTP 429, 500, and 503, four tries total. Honor `Retry-After`, cap the wait at 5 seconds. Otherwise wait `0.4 * attempt`.
- Each request timeout is 20 seconds.
- A second tap while a submit is running does not send a second `POST /v1/routes`.
- Header subtitle is `N packages | M stops` from the live draft. Title is `Morning route`.
- Do not build photos, notify, manual address, camera, or a screen after success.
- Commit as `danilasavitski-bit <danila.savitski@innowise.com>` via the environment, without changing git config. Stay on `feature/route-builder`.

---

### Task 1: Project shell

**Files:**
- Modify: `Route Builder.xcodeproj/project.pbxproj`
- Modify: `Route Builder/Info.plist`
- Modify: `Route Builder/SceneDelegate.swift`
- Delete: `Route Builder/ViewController.swift`
- Create: `Route Builder.xcodeproj/xcshareddata/xcschemes/Route Builder.xcscheme`
- Create: `Route BuilderTests/ShellTests.swift`

**Interfaces:**
- Consumes: the existing app target `Route Builder`, module name `Route_Builder`.
- Produces: a unit-test target `Route BuilderTests` that `@testable import`s `Route_Builder`. The app no longer loads `Main.storyboard`. `SceneDelegate` creates the window. Local HTTP is allowed. iPhone portrait only. Deployment target 16.0.

- [ ] **Step 1: Write the failing test**

`Route BuilderTests/ShellTests.swift` asserts `APIClient.baseURL.absoluteString == "http://127.0.0.1:4000"`. This fails because `APIClient` does not exist yet. Add the test target and shared scheme in the same step so `xcodebuild test` can compile the test file. The assertion file may be the only test; the type arrives in Task 3. Until Task 3, keep this file out of the test target run by writing the shell test against a placeholder that Task 1 adds:

```swift
import XCTest
@testable import Route_Builder

final class ShellTests: XCTestCase {
    func testBaseURLConstant() {
        XCTAssertEqual(AppConfig.baseURL.absoluteString, "http://127.0.0.1:4000")
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails to compile**

Run: `xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,name=iPhone 16" -only-testing:"Route BuilderTests/ShellTests" CODE_SIGNING_ALLOWED=NO`

Expected: compile failure, `AppConfig` is undefined.

- [ ] **Step 3: Implement the shell**

Create `Route Builder/AppConfig.swift`:

```swift
import Foundation

enum AppConfig {
    static let baseURL = URL(string: "http://127.0.0.1:4000")!
}
```

In both project-level build configurations set `IPHONEOS_DEPLOYMENT_TARGET = 16.0`.

In both target configurations:

- `TARGETED_DEVICE_FAMILY = 1`
- `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`
- delete `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`
- delete `INFOPLIST_KEY_UIMainStoryboardFile`

Add a `Route BuilderTests` unit-test target, bundle id `com.inn.Route-BuilderTests`, hosted by the app target, file-system synchronized on the `Route BuilderTests` folder. Copy the app target's Swift 5 and MainActor-isolation settings onto the test target. Add a shared scheme that tests `Route BuilderTests`.

`Info.plist`: remove `UISceneStoryboardFile`. Add:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
</array>
```

`SceneDelegate.scene(_:willConnectTo:options:)` creates a `UIWindow` on the `UIWindowScene` and sets `rootViewController` to a temporary `UIViewController` with `Theme` applied once Theme exists. Until Task 6, use an empty `UIViewController` with a white background so the project builds. Delete `ViewController.swift`.

- [ ] **Step 4: Run the test**

Same `xcodebuild test` command. Expected: `ShellTests` passes.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder.xcodeproj/project.pbxproj" "Route Builder.xcodeproj/xcshareddata/xcschemes/Route Builder.xcscheme" "Route Builder/Info.plist" "Route Builder/SceneDelegate.swift" "Route Builder/AppConfig.swift" "Route BuilderTests/ShellTests.swift"
git add -u "Route Builder/ViewController.swift"
git commit -m "Lower the app to iOS 16 and add the test target."
```

Author environment: `GIT_AUTHOR_NAME=danilasavitski-bit`, `GIT_AUTHOR_EMAIL=danila.savitski@innowise.com`, and the same two variables for `GIT_COMMITTER_NAME` and `GIT_COMMITTER_EMAIL`.

### Task 2: Draft model

**Files:**
- Create: `Route Builder/Theme.swift`
- Create: `Route Builder/Domain/RouteDraft.swift`
- Create: `Route Builder/Domain/RouteDraftStore.swift`
- Test: `Route BuilderTests/RouteDraftTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 except the test target.
- Produces:

```swift
struct Stop: Equatable, Identifiable {
    let id: String
    let name: String
    let address: String
    let phone: String
    let zone: String
    let packagesMax: Int
    var sectionLetter: String { get }
    var initials: String { get }
}

enum SelectionMode: Equatable { case oneStop, multiStop }

struct RouteStop: Equatable, Identifiable {
    var id: String { stopID }
    let stopID: String
    let name: String
    let address: String
    let phone: String
    let packagesMax: Int
    var packages: Int
    var instructions: String
    init(stop: Stop)
}

struct StopSection: Equatable {
    let letter: String
    let stops: [Stop]
}

enum StopGrouping {
    static func sections(_ stops: [Stop]) -> [StopSection]
}

struct RouteDraft: Equatable {
    var mode: SelectionMode
    var stops: [RouteStop]
    var packageTotal: Int { get }
    var subtitle: String { get }
    func isSelected(_ id: String) -> Bool
    mutating func select(_ stop: Stop)
    mutating func setMode(_ mode: SelectionMode)
    mutating func setPackages(stopID: String, packages: Int)
    mutating func setInstructions(stopID: String, text: String)
    mutating func remove(stopID: String)
    func invalidStopIDs() -> [String]
}

struct CreatedRoute: Equatable {
    let id: String
    let status: String
}

final class RouteDraftStore {
    private(set) var draft: RouteDraft
    @discardableResult func observe(_ body: @escaping (RouteDraft) -> Void) -> UUID
    func update(_ body: (inout RouteDraft) -> Void)
}
```

`RouteStop.init(stop:)` sets `packages` to 1 and `instructions` to `""`. `packagesMax` is copied from the stop.

- [ ] **Step 1: Write the failing tests**

Cover, in `RouteDraftTests`:

- `24/7 Pharmacy` initials are `2P`, section letter `2`. `Isaac's Hardware` initials are `IH`.
- Sections keep server order inside a letter and sort letters ascending.
- One-stop select replaces. Tapping the selected stop clears it.
- Multi-stop toggles and keeps order.
- Switching to one-stop keeps the first stop only.
- `setPackages` clamps to `1...packagesMax`.
- `setInstructions` keeps at most 200 characters.
- `invalidStopIDs` returns ids whose trimmed instructions are empty, in draft order. `"  hi "` is valid.
- `remove` drops that stop.
- `subtitle` for two stops with 2 and 3 packages is `5 packages | 2 stops`.
- `RouteDraftStore.update` replaces the draft and notifies the observer once.

- [ ] **Step 2: Run the tests and confirm they fail to compile**

Run: `xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,name=iPhone 16" -only-testing:"Route BuilderTests/RouteDraftTests" CODE_SIGNING_ALLOWED=NO`

Expected: compile failure.

- [ ] **Step 3: Implement the types**

`sectionLetter` is the uppercased first character of the trimmed name, or `#` when the name is empty.

`initials` walks the first two whitespace-separated words and takes the first alphanumeric from each, then uppercases the result.

`select` in `.oneStop`: if the only selected id equals the tapped id, clear the list; otherwise keep an existing `RouteStop` with that id or create one, and drop every other stop. In `.multiStop`: remove the id if present, otherwise append.

`setMode(.oneStop)` when more than one stop is selected keeps index 0.

`setInstructions` assigns `String(text.prefix(200))` and does not trim. Trimming happens only in `invalidStopIDs` and later in the POST body.

`Theme` holds the mock colors `#EEF1F3`, `#FFFFFF`, `#0D6E76`, `#0A585F`, `#16232E`, `#6B7C8A`, `#DFE5E9`, card radius 12, mark radius 11, and a `UIColor` hex initializer. `Theme` may import UIKit. Domain files import Foundation only.

- [ ] **Step 4: Run the tests**

Expected: `RouteDraftTests` passes.

- [ ] **Step 5: Commit**

```bash
git commit -m "Add the route draft and the rules for selecting stops."
```

### Task 3: API client

**Files:**
- Create: `Route Builder/Networking/APIError.swift`
- Create: `Route Builder/Networking/APIClient.swift`
- Create: `Route BuilderTests/StubURLProtocol.swift`
- Test: `Route BuilderTests/APIClientTests.swift`

**Interfaces:**
- Consumes: `Stop`, `RouteStop`, `CreatedRoute`, `AppConfig.baseURL`.
- Produces:

```swift
enum APIError: Error, Equatable {
    case transport
    case http(status: Int, code: String)
    case validation([String: String])
}

protocol DispatchAPI {
    func fetchStops(query: String?) async throws -> [Stop]
    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute
}

final class APIClient: DispatchAPI {
    init(baseURL: URL = AppConfig.baseURL, session: URLSession = APIClient.liveSession(), sleep: @escaping @Sendable (TimeInterval) async -> Void = APIClient.defaultSleep)
    func fetchStops(query: String?) async throws -> [Stop]
    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute
}
```

- [ ] **Step 1: Write the failing tests**

`StubURLProtocol` is an `URLProtocol` subclass. `nonisolated(unsafe) static var handler` returns `(Int, Data, [String: String])`. `startLoading` and `canInit` are `nonisolated`. The test session is ephemeral with `protocolClasses = [StubURLProtocol.self]`.

`APIClient` under test uses that session and a sleep closure that records delays and returns immediately.

Assert:

- `packages_max` number `5` becomes 5, string `"6"` becomes 6, `null` becomes 9, `"nope"` becomes 9.
- A page whose `items` is `null` yields `[]` and does not request page 2.
- Page 1 items A,B; page 2 items B,C with `has_more: true`; page 3 items C with `has_more: true`. Result ids are A,B,C and page 4 is not requested.
- `last_delivery_at` as a number and `notes: null` do not fail decoding.
- First response 503 with `Retry-After: 2`, second response 200 with one stop. Sleep was called once with 2. Result has that stop.
- Four 500 responses throw `APIError.http`. Sleep is called three times.
- `POST` body trims instructions, slices to 200, and clamps packages to `1...packagesMax`.
- HTTP 422 with `{"error":"validation_failed","fields":{"stops":"required"}}` throws `APIError.validation(["stops": "required"])`.
- Request timeout on the captured `URLRequest` is 20.
- Query `North` is sent as `q=North` without lowercasing. `page_size=50`.

- [ ] **Step 2: Run the tests and confirm they fail to compile**

Expected: `APIClient` is undefined.

- [ ] **Step 3: Implement `APIClient`**

`fetchStops` loops `page` from 1. It builds `GET /v1/stops` with `page`, `page_size=50`, and `q` only when the query is non-nil and non-empty. Decode `items` as an optional array. `null` or missing becomes `[]`. An empty page returns what has been collected. Ids already seen are skipped. A page that adds nothing returns what has been collected. Do not read `has_more`.

Decode each stop with a custom `packages_max`: JSON number, numeric string, otherwise 9. Ignore every other unexpected field.

`createRoute` posts JSON `{"stops":[{"stop_id","packages","instructions"}]}`. `packages` is clamped to `1...packagesMax`. `instructions` is trimmed, then prefixed to 200 characters. 422 decodes `fields` as `[String: String]` and throws `validation`. Any other non-2xx throws `http` with the `error` string, or `""` when that key is missing. 2xx decodes `id` and `status` only.

`data(for:)` tries up to four times. Status 429, 500, or 503 with attempts remaining calls `sleep` then repeats. Delay is `min(5, Retry-After)` when the header parses as a number, otherwise `0.4 * attempt` using the attempt that just failed (1, then 2, then 3). A thrown `URLError` becomes `APIError.transport` and is not retried.

- [ ] **Step 4: Run the tests**

Expected: `APIClientTests` and `ShellTests` pass.

- [ ] **Step 5: Commit**

```bash
git commit -m "Normalize the dispatch API and retry its transient failures."
```

### Task 4: View models

**Files:**
- Create: `Route Builder/Stops/StopsViewModel.swift`
- Create: `Route Builder/Instructions/InstructionsViewModel.swift`
- Test: `Route BuilderTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: `DispatchAPI`, `RouteDraftStore`, `Stop`, `RouteDraft`, `CreatedRoute`, `APIError`.
- Produces:

```swift
enum StopsLoadState: Equatable { case loading, loaded, failed(String) }

@MainActor
final class StopsViewModel {
    init(api: DispatchAPI, store: RouteDraftStore, debounceNanoseconds: UInt64 = 300_000_000)
    private(set) var state: StopsLoadState
    private(set) var sections: [StopSection]
    private(set) var query: String
    private(set) var searchFailed: Bool
    var onChange: (() -> Void)?
    func load() async
    func searchTextChanged(_ text: String)
    func select(_ stop: Stop)
    func setMode(_ mode: SelectionMode)
    func remove(stopID: String)
    func savePackages(stopID: String, packages: Int)
}

enum SubmitState: Equatable {
    case idle
    case sending
    case failed(String)
    case succeeded(routeID: String)
}

@MainActor
final class InstructionsViewModel {
    init(api: DispatchAPI, store: RouteDraftStore)
    private(set) var submitState: SubmitState
    private(set) var invalidStopIDs: [String]
    var onChange: (() -> Void)?
    func consumeScrollRequest() -> String?
    func draftChanged()
    func instructionsChanged(stopID: String, text: String)
    func clear(stopID: String)
    func remove(stopID: String)
    func finish() async
}
```

- [ ] **Step 1: Write the failing tests**

Use a fake `DispatchAPI` that records queries and can fail or return stops. No `URLSession`.

Assert:

- `load` stores sections from the catalog. A second `searchTextChanged("")` does not call `fetchStops` again.
- `searchTextChanged("North")` after the debounce calls `fetchStops(query: "North")`.
- A failed search sets `searchFailed` and leaves the previous sections in place.
- An empty search result clears sections and leaves `searchFailed` false.
- `finish` with a blank instruction does not call `createRoute`, sets `invalidStopIDs`, and `scrollToStopID` is the first blank id.
- Two overlapping `finish()` calls produce one `createRoute`. The fake waits on a continuation so the second call arrives while the first is in flight.
- A thrown `APIError.validation` sets `submitState` to `.failed("Could not send the route. Try again.")`.
- After `.succeeded`, `draftChanged()` returns the state to `.idle`.

- [ ] **Step 2: Run the tests and confirm they fail to compile**

- [ ] **Step 3: Implement the view models**

`load` sets `.loading`, fetches `query: nil`, saves the catalog, publishes grouped sections, then `.loaded`. On throw, `.failed("Could not load stops.")`. The draft is not touched.

`searchTextChanged` stores the query and cancels the previous task. Empty text republishes the catalog and clears `searchFailed` without a fetch. Other text sleeps for `debounceNanoseconds`, then fetches. Ignore the result when the task is cancelled. On throw, set `searchFailed` and do not replace `sections`. On success, replace `sections` and clear `searchFailed`.

`finish` returns immediately when a submit is already running or when `submitState` is `.succeeded`. When `invalidStopIDs` is non-empty, store them, set `scrollToStopID` to the first, and return without a request. Otherwise set `.sending`, await `createRoute` with the current stops, then `.succeeded(routeID:)`. On throw, `.failed("Could not send the route. Try again.")`. Clear the in-flight flag in `defer`.

`instructionsChanged` writes the text through the store. `clear` writes `""`. `remove` removes the stop. `draftChanged` sets `.succeeded` back to `.idle`. Neither import UIKit.

- [ ] **Step 4: Run the tests**

Expected: `ViewModelTests` passes.

- [ ] **Step 5: Commit**

```bash
git commit -m "Add stop search and route submission view models."
```

### Task 5: Stops screen

**Files:**
- Create: `Route Builder/Stops/StopCell.swift`
- Create: `Route Builder/Stops/PackageCountViewController.swift`
- Create: `Route Builder/Stops/StopsViewController.swift`

**Interfaces:**
- Consumes: `StopsViewModel`, `RouteDraftStore`, `Theme`, `Stop`.
- Produces: `StopsViewController(viewModel:store:onContinue:)`. Continue calls `onContinue` only when `store.draft.stops` is not empty and `state == .loaded`. The package sheet writes back only from Save.

- [ ] **Step 1: Build the screen in code**

No view-controller unit test. The screen must:

- Show two mode cards, `One stop` / `Single delivery` and `Multi-stop route` / `Several stops`. The active card uses a teal border.
- Search placeholder `Search by name, street, or phone`. Each change calls `searchTextChanged`.
- While `state == .loading`, show a spinner and disable the search field and Continue.
- While `state == .failed`, show the message and a Retry button that calls `load()`.
- Table sections use the letter as the header. Rows show initials in a teal circle, name, address, phone, and an `N×` pill. Unselected rows show `1×` as the value the sheet would start from only after selection; the pill on an unselected row shows nothing until the row is selected, then shows the draft count. Tapping the row calls `select`. Tapping the pill on a selected row presents the sheet. Tapping the pill on an unselected row selects it first with 1 package, then presents the sheet.
- A right-hand A–Z column scrolls to that section when the letter exists and does nothing otherwise.
- Empty query-driven sections with `searchFailed == false` and `state == .loaded` show `No stop found` and `Try another street`.
- `searchFailed` shows `Search failed. The list below is unchanged.` above the table. The previous rows stay.
- Chips list draft stops with name, `N×`, and a remove control that calls `remove(stopID:)`.
- Continue title is `Continue (N stops)` and is disabled at N = 0.
- The sheet shows `Number of packages`, minus, the value, plus, and Save. Minus and plus clamp to `1...packagesMax` locally. Save calls `savePackages`. Swiping the sheet away does not call `savePackages`.

Colors, type sizes, and radii come from `Theme` and the design spec.

- [ ] **Step 2: Build the app**

Run: `xcodebuild build -scheme "Route Builder" -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git commit -m "Build the stop picker, package sheet, and selected chips."
```

### Task 6: Instructions screen and window root

**Files:**
- Create: `Route Builder/Instructions/InstructionCardCell.swift`
- Create: `Route Builder/Instructions/InstructionsViewController.swift`
- Create: `Route Builder/Depot/DepotViewController.swift`
- Modify: `Route Builder/SceneDelegate.swift`
- Create: `README.md`
- Copy unchanged: `MockServer/server.js` from the provided server file

**Interfaces:**
- Consumes: both view models, `RouteDraftStore`, `APIClient`, `AppConfig`, `Theme`.
- Produces: `DepotViewController()` as the window root. It creates `APIClient()`, `RouteDraftStore()`, both view models, and both child controllers.

- [ ] **Step 1: Build the depot and the instruction feed**

`DepotViewController` lays out a white header and a tab bar. The mark is a 44×44 teal rounded rect (radius 11) with a white ring and a white center dot. Title `Morning route`, 20/28, heavy. Subtitle is `store.draft.subtitle`, 12/16, secondary. Tabs are `Stops` and `Instructions`, 14/20. The selected tab is teal, weight 700, with a 3 pt teal underline. The other tab is secondary.

The header observes the store. Switching tabs swaps the visible child. `onContinue` selects Instructions. Instructions with an empty draft shows `Select stops before writing instructions.` and does not call the API.

`InstructionsViewController`:

- One card per draft stop, in order: name, `N×`, address, text view, `N/200`, Clear all, and a `Remove from route` button.
- The text view rejects input past 200 characters and calls `instructionsChanged`.
- Clear all calls `clear`.
- The button and a trailing swipe action both call `remove`.
- In `scrollViewDidScroll`, the cell whose center is closest to the visible rect center has transform identity and alpha 1. Every other cell scales to 0.94 and uses alpha 0.55.
- Cards whose id is in `invalidStopIDs` show `Add instructions for this stop before finishing`.
- `scrollToStopID` scrolls that row into view, then the controller clears the request by calling a `consumeScrollRequest()` on the view model. Add that method: it returns the id and sets the stored id to nil.
- The bottom button title is `Finish instructions`, `Sending…` while sending, and `Could not send the route. Try again.` while failed. Taps call `finish()`. The button ignores taps while `submitState == .sending` because `finish` already returns.
- `.succeeded(routeID:)` replaces the feed with `Route <id> sent.` The Stops tab stays. `draftChanged()` on the next store notification removes the confirmation because the view model returns to `.idle`.

`SceneDelegate` sets `DepotViewController` as the root. Call `load()` from `viewDidLoad` of the stops screen.

`README.md` states: run `node MockServer/server.js` with Node 18, then run the `Route Builder` scheme on the iOS Simulator. The base URL lives in `Route Builder/AppConfig.swift`. A physical iPhone on the same Wi-Fi replaces that value with the computer’s LAN address. Copy `server.js` into `MockServer/server.js` byte for byte.

- [ ] **Step 2: Run the unit tests and build**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO
```

Expected: every test passes and the app builds.

- [ ] **Step 3: Commit**

```bash
git commit -m "Show instruction cards and send the route from the depot screen."
```

## Self-review notes

- Spec coverage: catalog load, sections, search, empty search, both modes, package sheet, chips, Continue, instruction cards, 200-character counter, empty-instruction error, remove including swipe, POST states, single submit, retries, paging quirks, and the live subtitle each have a task above. Photos, notify, manual address, and camera have no task.
- The shell test’s `AppConfig` is the base URL the spec assigns to `APIClient`. `APIClient` defaults to `AppConfig.baseURL`.
- `DispatchAPI` is the seam view models use. `APIClient` is its only production conformer and the only HTTP speaker.
