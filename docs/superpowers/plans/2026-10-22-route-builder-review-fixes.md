# Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a created route, its confirmation, and its driver alerts describe the same stops, and make the instruction card, the stop index, and empty search match the spec.

**Architecture:** `InstructionsViewModel` snapshots the draft once, before `POST /v1/routes`, and uses that value for notify. The instruction screen reconfigures visible cards when the stop ids do not change. Photo bytes and photo failures go through `DispatchAPI`. Stops UI changes stay in `StopsViewController` and `StopCell`.

**Tech Stack:** UIKit programmatic, MVVM, async/await, XCTest, iOS 16. View models do not import UIKit. `APIClient` is the only HTTP speaker.

## Global Constraints

- Deployment target stays iOS 16.
- English, LTR, one-handed.
- Instruction cap is 200 characters. Finish trims. Empty after trim is invalid.
- Unparseable or null `packages_max` is 99.
- Default selection mode is One stop.
- Subtitle stays `N packages | M stops`, always plural.
- Header title stays `Morning route — Central area`. Do not change it. The HTML mock won over the spec sentence that says `Morning route`.
- Instruction feed stays a vertical collection view with measured card height and snap-to-card paging. `isPagingEnabled` stays off. Stops stays a table.
- The sharp card is the largest visible fraction of its own height. No content-view scale. Inactive cards use `UIBlurEffect(style: .systemUltraThinMaterialLight)`, animated, and the card stays at alpha 1.
- Do not commit `.cursor/`, `xcuserdata`, or the unstaged `LD_RUNPATH_SEARCH_PATHS` reorder in `project.pbxproj`.
- Do not push.
- Every commit uses this author and committer, set on the `git commit` command itself. Do not change git config.

```bash
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Message here.

EOF
)"
```

- Test destination: `platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF`. Scheme: `Route Builder`.
- New tests that store a closure on a view model, or that construct `InstructionsViewModel` / `StopsViewModel`, are `async`. A synchronous test crashes at deinit with `swift_task_deinitOnExecutorMainActorBackDeploy`.
- `24/7 Pharmacy` stays in section `2`. The spec groups by the first character and the initials are `2P`. Do not invent an A–Z bucket for it.
- Card corner radius stays 16. Do not restyle tokens that the mock already uses.

## File map

- Modify: `Route Builder/Instructions/InstructionsViewModel.swift` — snapshot posted stops; photo gallery success versus failure; image bytes through the API.
- Modify: `Route Builder/Instructions/InstructionsViewController.swift` — reconfigure visible cards; wire image loading; pass the gallery into the cell.
- Modify: `Route Builder/Instructions/InstructionCardCell.swift` — current package count via `configure`, on-card remove, photo failure caption, image load callback.
- Modify: `Route Builder/Networking/APIError.swift` — `fetchImageData(from:)`.
- Modify: `Route Builder/Networking/APIClient.swift` — image GET on the shared session; cancellation stays cancellation.
- Modify: `Route Builder/Stops/StopsViewController.swift` — trailing index; empty-search copy.
- Modify: `Route Builder/Stops/StopCell.swift` — trailing slot for phone or pill, inset clear of the index.
- Modify: `Route BuilderTests/ViewModelTests.swift` — behavior tests and the two fakes.
- Modify: `Route BuilderTests/APIClientTests.swift` — cancellation and image GET.
- Modify: `docs/superpowers/specs/2026-10-22-route-builder-design.md` — focus, title, and empty-search sentences so they match this behavior.

---

### Task 1: Notify the stops that were posted

**Files:**
- Modify: `Route Builder/Instructions/InstructionsViewModel.swift`
- Modify: `Route BuilderTests/ViewModelTests.swift` (`GateAPI` and a new test)
- Test: `Route BuilderTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: `GateAPI.createRoute` already suspends until `resumeSuccess()`.
- Produces: `finish()` copies `store.draft.stops` into a local `let posted` before `createRoute`. Confirmation `notices` and the notify loop use `posted` only. `retryFailedNotices()` calls notify with the stop id stored on the notice. It does not look the stop up in the live draft.

- [ ] **Step 1: Write the failing test**

In `GateAPI`, record the ids:

```swift
var postedStopIDs: [String] = []
var notifiedStopIDs: [String] = []

func createRoute(stops: [RouteStop]) async throws -> CreatedRoute {
    postedStopIDs = stops.map(\.stopID)
    createCount += 1
    return try await withCheckedThrowingContinuation { continuation in
        continuations.append(continuation)
    }
}

func notify(routeID: String, stopID: String, idempotencyKey: String) async throws -> NotifyResult {
    notifiedStopIDs.append(stopID)
    return NotifyResult(stopID: stopID, status: "sent", reason: nil)
}
```

Add this test. `filledStore()` already selects stop `a` with instructions. Default mode is one stop, so the mutation switches to multi-stop and appends `b` while create is suspended.

```swift
func testNotifyUsesTheStopsThatWerePosted() async {
    let api = GateAPI()
    let store = filledStore()
    let viewModel = InstructionsViewModel(api: api, store: store)
    let task = Task { await viewModel.finish() }
    await waitUntil { api.createCount == 1 }
    store.update {
        $0.setMode(.multiStop)
        $0.select(makeStop(id: "b", name: "Birch"))
    }
    api.resumeSuccess()
    await task.value
    XCTAssertEqual(api.postedStopIDs, ["a"])
    XCTAssertEqual(viewModel.notices.map(\.stopID), ["a"])
    XCTAssertEqual(api.notifiedStopIDs, ["a"])
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests/ViewModelTests/testNotifyUsesTheStopsThatWerePosted" -quiet
```

Expected: FAIL. `notices` or `notifiedStopIDs` contains `b`, because `finish()` reads `store.draft.stops` again after the await.

- [ ] **Step 3: Snapshot before the await**

Replace the success path of `finish()` and the notify helpers:

```swift
submitting = true
submitState = .sending
invalidStopIDs = []
onChange?()
let posted = store.draft.stops
defer { submitting = false }
do {
    let created = try await api.createRoute(stops: posted)
    let generation = notifyGeneration
    notices = posted.map {
        DriverNotice(stopID: $0.stopID, name: $0.name, status: "sending", reason: nil)
    }
    submitState = .succeeded(routeID: created.id)
    onChange?()
    for stop in posted {
        guard generation == notifyGeneration else { return }
        await sendNotice(routeID: created.id, stopID: stop.stopID, generation: generation)
    }
} catch {
    submitState = .failed("Could not send the route. Try again.")
    onChange?()
}
```

`retryFailedNotices` becomes:

```swift
func retryFailedNotices() async {
    guard case .succeeded(let routeID) = submitState else { return }
    let generation = notifyGeneration
    let failedIDs = notices.filter { $0.status == "failed" }.map(\.stopID)
    for stopID in failedIDs {
        guard generation == notifyGeneration else { return }
        await sendNotice(routeID: routeID, stopID: stopID, generation: generation)
    }
}

private func sendNotice(routeID: String, stopID: String, generation: Int) async {
    guard generation == notifyGeneration else { return }
    if let index = notices.firstIndex(where: { $0.stopID == stopID }) {
        notices[index].status = "sending"
        notices[index].reason = nil
        onChange?()
    }
    let result: NotifyResult
    do {
        result = try await api.notify(
            routeID: routeID,
            stopID: stopID,
            idempotencyKey: UUID().uuidString
        )
    } catch {
        result = NotifyResult(stopID: stopID, status: "failed", reason: "Could not reach the driver.")
    }
    guard generation == notifyGeneration else { return }
    guard let index = notices.firstIndex(where: { $0.stopID == stopID }) else { return }
    let delivered = result.status == "sent"
    notices[index].status = delivered ? "sent" : "failed"
    notices[index].reason = delivered ? nil : (result.reason ?? "The driver was not notified.")
    onChange?()
}
```

Leave the cards and the Stops tab enabled during `Sending…`. The snapshot is what keeps the route and the alerts together. Do not add a second lock on the draft.

- [ ] **Step 4: Re-run the test**

Same command as Step 2. Expected: PASS. Then run `Route BuilderTests/ViewModelTests/testFailedNotifyRetriesWithANewKey` and `testOverlappingFinishSendsOneRoute`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder/Instructions/InstructionsViewModel.swift" "Route BuilderTests/ViewModelTests.swift"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Notify drivers for the stops that were actually posted.

EOF
)"
```

---

### Task 2: Show the current package count on the card

**Files:**
- Modify: `Route Builder/Instructions/InstructionsViewController.swift:194-201`
- Test: `Route BuilderTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: `InstructionCardCell.configure(stop:invalid:)` already writes `countLabel` as `"\(stop.packages)×"` and does not replace `textView.text` while that field is first responder.
- Produces: the `else` branch of `render()`, used when the stop ids are unchanged, calls `configure` for each visible card.

- [ ] **Step 1: Write the failing test**

```swift
func testInstructionCardShowsTheUpdatedPackageCount() async {
    let store = RouteDraftStore()
    store.update {
        $0.select(makeStop(id: "a", name: "Almond"))
        $0.setInstructions(stopID: "a", text: "Ring the bell")
    }
    let controller = InstructionsViewController(
        viewModel: InstructionsViewModel(api: FakeAPI(), store: store),
        store: store
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    XCTAssertNotNil(label(in: controller.view, text: "1×"))

    store.update { $0.setPackages(stopID: "a", packages: 3) }
    controller.render()
    XCTAssertNil(label(in: controller.view, text: "1×"))
    XCTAssertNotNil(label(in: controller.view, text: "3×"))
}

private func label(in view: UIView, text: String) -> UILabel? {
    if let label = view as? UILabel, label.text == text { return label }
    for subview in view.subviews {
        if let label = label(in: subview, text: text) { return label }
    }
    return nil
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests/ViewModelTests/testInstructionCardShowsTheUpdatedPackageCount" -quiet
```

Expected: FAIL on `XCTAssertNil` for `"1×"`. `render()` left the old count because the stop id did not change.

- [ ] **Step 3: Reconfigure visible cards**

In the `else` branch of `render()`:

```swift
} else {
    for case let cell as InstructionCardCell in collectionView.visibleCells {
        guard let stop = stops.first(where: { $0.stopID == cell.stopID }) else { continue }
        cell.configure(stop: stop, invalid: viewModel.invalidStopIDs.contains(cell.stopID))
        cell.showDeliveryPhotos(viewModel.photos[stop.stopID], local: stop.stopID.hasPrefix("local_"))
        cell.showDropOff(path: stop.dropOffPhotoPath)
    }
    collectionView.collectionViewLayout.invalidateLayout()
}
```

`configure` replaces the `setInvalid` call. Do not call `reloadData()` on this path. That would reset the text field.

- [ ] **Step 4: Re-run the test**

Same command. Expected: PASS. Also run `testInstructionCardsKeepTheDesignHeightAndCanScroll`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder/Instructions/InstructionsViewController.swift" "Route BuilderTests/ViewModelTests.swift"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Show the current package count on the instruction card.

EOF
)"
```

---

### Task 3: Put Remove on the card

**Files:**
- Modify: `Route Builder/Instructions/InstructionCardCell.swift`
- Test: `Route BuilderTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: `onRemove` is already wired in `cellForItemAt` to `viewModel.remove(stopID:)`.
- Produces: a `UIButton` titled `Remove from route` in the card stack, above the footer. `touchUpInside` calls `onRemove`. The horizontal pan still calls `onRemove` after a left drag past 100 points.

- [ ] **Step 1: Write the failing test**

```swift
func testRemoveButtonDropsTheStop() async {
    let store = RouteDraftStore()
    store.update {
        $0.select(makeStop(id: "a", name: "Almond"))
        $0.setInstructions(stopID: "a", text: "Ring the bell")
    }
    let controller = InstructionsViewController(
        viewModel: InstructionsViewModel(api: FakeAPI(), store: store),
        store: store
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    let button = buttonTitled("Remove from route", in: controller.view)
    XCTAssertNotNil(button)
    button?.sendActions(for: .touchUpInside)
    XCTAssertTrue(store.draft.stops.isEmpty)
}

private func buttonTitled(_ title: String, in view: UIView) -> UIButton? {
    if let button = view as? UIButton, button.currentTitle == title { return button }
    for subview in view.subviews {
        if let button = buttonTitled(title, in: subview) { return button }
    }
    return nil
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests/ViewModelTests/testRemoveButtonDropsTheStop" -quiet
```

Expected: FAIL. `XCTAssertNotNil` fails because the only remove affordance is the swipe label behind the card.

- [ ] **Step 3: Add the button**

Next to the other card controls:

```swift
private let removeButton = UIButton(type: .system)
```

After the camera button is configured, and before the stack is built:

```swift
removeButton.setTitle("Remove from route", for: .normal)
removeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
removeButton.setTitleColor(Theme.swipe, for: .normal)
removeButton.contentHorizontalAlignment = .leading
removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
```

Insert `removeButton` in the stack immediately before `footerLabel`.

```swift
@objc private func removeTapped() {
    onRemove?()
}
```

In `prepareForReuse`, keep `onRemove = nil` where it already is.

Give the package count priority over the name so `N×` does not compress:

```swift
nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
```

The swipe pan stays. Do not set `card.alpha` below 1.

- [ ] **Step 4: Re-run the test**

Same command. Expected: PASS. Also run `testInstructionCardsKeepTheDesignHeightAndCanScroll`. The card must stay shorter than the collection view. If the new row pushes it over `bounds.height - 80` but it is still shorter than `bounds.height`, change only that upper bound in the existing test to `bounds.height - 40`. Do not go back to a full-viewport cell.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder/Instructions/InstructionCardCell.swift" "Route BuilderTests/ViewModelTests.swift"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Offer remove on the instruction card, not only by swipe.

EOF
)"
```

---

### Task 4: Move the A–Z index to the trailing edge

**Files:**
- Modify: `Route Builder/Stops/StopsViewController.swift:160-169`
- Modify: `Route Builder/Stops/StopCell.swift`
- Test: `Route BuilderTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: `indexTapped` already ignores letters with no section.
- Produces: `indexStack` is pinned to the trailing edge, width 16. The checkbox leading inset is 16. Phone and pill share one trailing stack inset by 22 so the index does not cover them. A hidden phone no longer reserves width beside the pill.

- [ ] **Step 1: Write the failing test**

```swift
func testSectionIndexSitsOnTheTrailingEdge() async {
    let api = FakeAPI()
    api.stopsResult[""] = .success([makeStop(id: "a", name: "Almond")])
    let store = RouteDraftStore()
    let viewModel = StopsViewModel(api: api, store: store, debounceNanoseconds: 0)
    await viewModel.load()
    let controller = StopsViewController(viewModel: viewModel, store: store, onContinue: {})
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    let index = stackOfLetters(in: controller.view)
    XCTAssertNotNil(index)
    XCTAssertGreaterThan(index?.frame.minX ?? 0, 360)
}
```

```swift
private func stackOfLetters(in view: UIView) -> UIStackView? {
    if let stack = view as? UIStackView,
       stack.arrangedSubviews.count == 26,
       (stack.arrangedSubviews.first as? UIButton)?.currentTitle == "A" {
        return stack
    }
    for subview in view.subviews {
        if let stack = stackOfLetters(in: subview) { return stack }
    }
    return nil
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests/ViewModelTests/testSectionIndexSitsOnTheTrailingEdge" -quiet
```

Expected: FAIL. The index `minX` is about 1, not greater than 360.

- [ ] **Step 3: Pin the index and the row trailing slot**

In `buildBottomBar`, replace the index leading constraint:

```swift
indexStack.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 4),
indexStack.bottomAnchor.constraint(equalTo: tableView.bottomAnchor, constant: -4),
indexStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -1),
indexStack.widthAnchor.constraint(equalToConstant: 16),
```

In `StopCell`, put `phoneLabel` and `pillButton` in one horizontal stack. Pin that stack's trailing edge to `contentView.trailingAnchor` with constant `-22`. Point `textStack.trailingAnchor` at the stack's leading anchor, constant `-8`. Remove the two separate trailing constraints and the extra `textStack` constraint that targeted `phoneLabel`.

Move the checkbox:

```swift
box.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
```

`configure` still sets `phoneLabel.isHidden = selected` and `pillButton.isHidden = !selected`. A hidden arranged subview takes no space, so the name can use the width the hidden phone used to reserve.

- [ ] **Step 4: Re-run the test**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder/Stops/StopsViewController.swift" "Route Builder/Stops/StopCell.swift" "Route BuilderTests/ViewModelTests.swift"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Put the A–Z index on the trailing edge of the stop list.

EOF
)"
```

---

### Task 5: Split empty search from manual address

**Files:**
- Modify: `Route Builder/Stops/StopsViewController.swift:221-228`
- Test: `Route BuilderTests/ViewModelTests.swift`

**Interfaces:**
- Consumes: `messageView(title:subtitle:actionTitle:action:quietAction:)` already shows a subtitle and a separate button. `manualTapped` already presents `ManualAddressViewController`.
- Produces: empty search shows title `No stop found`, subtitle `Try another street`, and a button titled `Enter an address` whose action is `manualTapped`.

- [ ] **Step 1: Write the failing test**

Follow `testEmptySearchResultClearsSections`: load a catalog, search `ZZZ` with an empty success, then host the controller and read the background view.

```swift
func testEmptySearchOffersManualAddressSeparately() async {
    let api = FakeAPI()
    api.stopsResult[""] = .success([makeStop(id: "c", name: "Cafe")])
    api.stopsResult["ZZZ"] = .success([])
    let store = RouteDraftStore()
    let viewModel = StopsViewModel(api: api, store: store, debounceNanoseconds: 0)
    await viewModel.load()
    viewModel.searchTextChanged("ZZZ")
    await waitUntil { viewModel.sections.isEmpty && viewModel.query == "ZZZ" }
    let controller = StopsViewController(viewModel: viewModel, store: store, onContinue: {})
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    XCTAssertNotNil(label(in: controller.view, text: "No stop found"))
    XCTAssertNotNil(label(in: controller.view, text: "Try another street"))
    XCTAssertNotNil(buttonTitled("Enter an address", in: controller.view))
    XCTAssertNil(buttonTitled("Try another street or enter an address manually", in: controller.view))
}
```

Reuse `label(in:text:)` and `buttonTitled(_:in:)` from Tasks 2 and 3. If those helpers are still private on the test class, do not duplicate them.

- [ ] **Step 2: Run the test and confirm it fails**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests/ViewModelTests/testEmptySearchOffersManualAddressSeparately" -quiet
```

Expected: FAIL. The only control title is `Try another street or enter an address manually`.

- [ ] **Step 3: Use the subtitle and a separate action**

```swift
return messageView(
    title: "No stop found",
    subtitle: "Try another street",
    actionTitle: "Enter an address",
    action: #selector(manualTapped),
    quietAction: false
)
```

Do not add a second control that only resigns the search field. The subtitle is the instruction to try another street. The button opens the manual-address sheet.

- [ ] **Step 4: Re-run the test**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder/Stops/StopsViewController.swift" "Route BuilderTests/ViewModelTests.swift"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Separate the empty-search message from the manual-address action.

EOF
)"
```

---

### Task 6: Load delivery photos through the API client

**Files:**
- Modify: `Route Builder/Networking/APIError.swift`
- Modify: `Route Builder/Networking/APIClient.swift`
- Modify: `Route Builder/Instructions/InstructionsViewModel.swift`
- Modify: `Route Builder/Instructions/InstructionsViewController.swift`
- Modify: `Route Builder/Instructions/InstructionCardCell.swift`
- Modify: `Route BuilderTests/ViewModelTests.swift` (`FakeAPI`, `GateAPI`)
- Modify: `Route BuilderTests/APIClientTests.swift`
- Test: both test files

**Interfaces:**
- Consumes: `APIClient.send` for the GET. `URLSession` timeout stays 20 seconds.
- Produces:
  - `enum PhotoGallery: Equatable { case ready([StopPhoto]); case failed }`
  - `InstructionsViewModel.photos` is `[String: PhotoGallery]`
  - `DispatchAPI.fetchImageData(from url: URL) async throws -> Data`
  - `InstructionCardCell.showDeliveryPhotos(_ gallery: PhotoGallery?, local: Bool)`
  - `InstructionCardCell.loadImage: ((URL) async -> Data?)?`
  - Captions: `nil` gallery shows `Loading…`. `.failed` shows `Could not load photos from the last delivery`. `.ready` with no non-nil URL shows `No photos from the last delivery`.

- [ ] **Step 1: Write the failing tests**

API client, in `APIClientTests`:

```swift
func testImageDataUsesTheClientSession() async throws {
    stub { request in
        XCTAssertEqual(request.url?.absoluteString, "https://picsum.photos/seed/a/8/8")
        return (200, Data([0xFF, 0xD8]), [:])
    }
    let data = try await makeClient().fetchImageData(from: URL(string: "https://picsum.photos/seed/a/8/8")!)
    XCTAssertEqual(data, Data([0xFF, 0xD8]))
}
```

View model:

```swift
func testFailedPhotoLoadIsNotAnEmptyGallery() async {
    let api = FakeAPI()
    api.photoResults["a"] = .failure(APIError.transport)
    let store = RouteDraftStore()
    store.update { $0.select(makeStop(id: "a", name: "Almond")) }
    let viewModel = InstructionsViewModel(api: api, store: store)
    viewModel.loadPhotosIfNeeded(stopID: "a")
    await waitUntil { viewModel.photos["a"] != nil }
    XCTAssertEqual(viewModel.photos["a"], .failed)
}
```

Add `var photoResults: [String: Result<[StopPhoto], Error>] = [:]` to `FakeAPI`. `fetchPhotos` returns `try (photoResults[stopID] ?? .success([])).get()`.

Add `func fetchImageData(from url: URL) async throws -> Data { Data() }` to `FakeAPI` and `GateAPI` so they still conform.

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests/APIClientTests/testImageDataUsesTheClientSession" -only-testing:"Route BuilderTests/ViewModelTests/testFailedPhotoLoadIsNotAnEmptyGallery" -quiet
```

Expected: FAIL to compile. `fetchImageData` and `PhotoGallery` do not exist. That is the red step.

- [ ] **Step 3: Implement the gallery and the image GET**

On `DispatchAPI`:

```swift
func fetchImageData(from url: URL) async throws -> Data
```

On `APIClient`:

```swift
func fetchImageData(from url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    let (data, http) = try await send(request)
    guard (200..<300).contains(http.statusCode) else {
        throw APIError.http(status: http.statusCode, code: "")
    }
    return data
}
```

In `InstructionsViewModel`:

```swift
enum PhotoGallery: Equatable {
    case ready([StopPhoto])
    case failed
}

private(set) var photos: [String: PhotoGallery] = [:]

func loadPhotosIfNeeded(stopID: String) {
    guard !stopID.hasPrefix("local_") else { return }
    guard photos[stopID] == nil, photoTasks[stopID] == nil else { return }
    photoTasks[stopID] = Task { [weak self] in
        guard let self else { return }
        let gallery: PhotoGallery
        do {
            gallery = .ready(try await self.api.fetchPhotos(stopID: stopID))
        } catch {
            gallery = .failed
        }
        self.photos[stopID] = gallery
        self.photoTasks[stopID] = nil
        self.onChange?()
    }
}

func imageData(for url: URL) async -> Data? {
    try? await api.fetchImageData(from: url)
}
```

`PhotoGallery` can live in `InstructionsViewModel.swift` as an internal type. The cell is in the same module and may use it.

Cell signature:

```swift
var loadImage: ((URL) async -> Data?)?

func showDeliveryPhotos(_ gallery: PhotoGallery?, local: Bool) {
    photosTitle.isHidden = local
    photosRow.isHidden = local
    if local {
        cancelImageLoads()
        shownPhotoKey = nil
        return
    }
    if gallery == nil {
        guard shownPhotoKey != "loading" else { return }
        shownPhotoKey = "loading"
        clearPhotoRow()
        photosRow.addArrangedSubview(caption("Loading…"))
        return
    }
    if case .failed = gallery {
        guard shownPhotoKey != "failed" else { return }
        shownPhotoKey = "failed"
        cancelImageLoads()
        clearPhotoRow()
        photosRow.addArrangedSubview(caption("Could not load photos from the last delivery"))
        return
    }
    let visible = gallery?.readyPhotos ?? []
    let key = visible.map(\.id).joined(separator: ",")
    guard shownPhotoKey != key else { return }
    shownPhotoKey = key
    cancelImageLoads()
    clearPhotoRow()
    let withURL = visible.filter { $0.url != nil }
    if withURL.isEmpty {
        photosRow.addArrangedSubview(caption("No photos from the last delivery"))
        return
    }
    for photo in withURL {
        let tile = PhotoTile(title: photo.title)
        photosRow.addArrangedSubview(tile)
        guard let url = photo.url else { continue }
        let task = Task { [weak self] in
            guard let data = await self?.loadImage?(url), let image = UIImage(data: data) else { return }
            tile.setImage(image)
        }
        imageTasks.append(task)
    }
}
```

Add `var readyPhotos: [StopPhoto]` on the enum via:

```swift
var readyPhotos: [StopPhoto] {
    if case .ready(let photos) = self { return photos }
    return []
}
```

Replace the data task:

```swift
let task = Task { [weak self] in
    guard let data = await self?.loadImage?(url), let image = UIImage(data: data) else { return }
    tile.setImage(image)
}
imageTasks.append(task)
```

Change `imageTasks` to `[Task<Void, Never>]`. `cancelImageLoads` calls `task.cancel()`.

Call sites in `InstructionsViewController`:

```swift
cell.showDeliveryPhotos(viewModel.photos[stop.stopID], local: stop.stopID.hasPrefix("local_"))
cell.loadImage = { [weak self] url in
    await self?.viewModel.imageData(for: url)
}
```

Set `loadImage` in both `cellForItemAt` and the `render()` else branch. The sizing cell must not start a load:

```swift
sizingCell.showDeliveryPhotos(stop.stopID.hasPrefix("local_") ? nil : .ready([]), local: stop.stopID.hasPrefix("local_"))
sizingCell.loadImage = nil
```

Delete the `URLSession.shared.dataTask` path. A byte failure leaves the gray tile and its caption. It does not switch the row to `No photos`.

- [ ] **Step 4: Re-run the tests**

Same command as Step 2. Expected: PASS. Then run `Route BuilderTests/APIClientTests` and `Route BuilderTests/ViewModelTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder/Networking/APIError.swift" "Route Builder/Networking/APIClient.swift" "Route Builder/Instructions/InstructionsViewModel.swift" "Route Builder/Instructions/InstructionsViewController.swift" "Route Builder/Instructions/InstructionCardCell.swift" "Route BuilderTests/ViewModelTests.swift" "Route BuilderTests/APIClientTests.swift"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Load delivery photos through the API client and keep a failed load visible.

EOF
)"
```

---

### Task 7: Keep a cancelled request cancelled

**Files:**
- Modify: `Route Builder/Networking/APIClient.swift:125-134`
- Test: `Route BuilderTests/APIClientTests.swift`

**Interfaces:**
- Consumes: `send` is the only place that maps URL errors to `APIError.transport`.
- Produces: `CancellationError` and `URLError.cancelled` propagate. Every other URL error is still `APIError.transport`.

- [ ] **Step 1: Write the failing test**

```swift
func testCancelledFetchIsNotATransportError() async {
    stub { _ in throw CancellationError() }
    do {
        _ = try await makeClient().fetchStops(query: nil)
        XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
        XCTFail("Unexpected \(error)")
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests/APIClientTests/testCancelledFetchIsNotATransportError" -quiet
```

Expected: FAIL. The catch reports `APIError.transport`.

- [ ] **Step 3: Rethrow cancellation**

```swift
do {
    (data, response) = try await session.data(for: request)
} catch {
    if error is CancellationError || (error as? URLError)?.code == .cancelled {
        throw error
    }
    throw APIError.transport
}
```

- [ ] **Step 4: Re-run the test**

Same command. Expected: PASS. Run `Route BuilderTests/APIClientTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Route Builder/Networking/APIClient.swift" "Route BuilderTests/APIClientTests.swift"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Let a cancelled request stay cancelled.

EOF
)"
```

---

### Task 8: Make the spec match the agreed screens

**Files:**
- Modify: `docs/superpowers/specs/2026-10-22-route-builder-design.md`

**Interfaces:**
- Consumes: the behavior from Tasks 1–7 and the decisions in Global Constraints.
- Produces: three replaced sentences. No code changes.

- [ ] **Step 1: Replace the conflicting sentences**

Header paragraph. Replace the title sentence with:

```markdown
Both screens share a header. Title is the fixed string `Morning route — Central area`, taken from the mock. The static “38 packages | 14 stops” has no API behind it. The subtitle is computed from the draft: `N packages | M stops`.
```

Instructions focus. Replace the scale paragraph with:

```markdown
The sharp card is the one with the largest visible fraction of its own height. Ties keep the previous focused stop. Inactive cards show a live `systemUltraThinMaterialLight` blur that fades in and out. The card stays at alpha 1. There is no content-view scale.
```

Error table row. Replace the empty-search row with:

```markdown
| Search with no rows | `No stop found`, subtitle `Try another street`, and a separate `Enter an address` action. |
```

Leave the plan file `docs/superpowers/plans/2026-10-22-route-builder.md` stale. Do not edit it in this task. This review-fixes plan is the one that describes the current work.

- [ ] **Step 2: Commit**

```bash
git add "docs/superpowers/specs/2026-10-22-route-builder-design.md"
GIT_AUTHOR_NAME='danilasavitski-bit' GIT_AUTHOR_EMAIL='danila.savitski@innowise.com' GIT_COMMITTER_NAME='danilasavitski-bit' GIT_COMMITTER_EMAIL='danila.savitski@innowise.com' git commit -m "$(cat <<'EOF'
Record the agreed title, focus, and empty-search copy.

EOF
)"
```

---

### Task 9: Run the suite

- [ ] **Step 1: Run every Route Builder test**

```bash
xcodebuild test -scheme "Route Builder" -destination "platform=iOS Simulator,id=182546CA-C7C0-46AD-8244-1064D40F90EF" -only-testing:"Route BuilderTests" -quiet
```

Expected: TEST SUCCEEDED. If one test crashes only in `swift_task_deinitOnExecutorMainActorBackDeploy`, rerun that test alone. A pass on the rerun is the known deinit flake, not a failure of these fixes. Any assertion failure is a failure of this plan.

Do not merge in this task.

## Out of scope

- `DECISIONS.md`, `AI_PROCESS.md`, `docs/ai/`, and the screen video. Those are reviewer deliverables, not these bugs.
- Section key for `24/7 Pharmacy`.
- Card corner radius, `Theme.tealPressed`, and header line height.
- Changing the header title away from `Morning route — Central area`.
