# Route Builder — design

Dispatcher builds a morning van route on an iPhone, standing at the depot counter, one-handed. Two screens: pick stops, write driver instructions, send the route. English, left to right. iOS 16+. UIKit, programmatic layout, MVVM, async/await. The mock server in `server.js` is the contract. This document does not change that server.

## Approach

Programmatic UIKit. `SceneDelegate` owns the window. Launch screen stays in the storyboard. Each screen has a view controller and a view model. `APIClient` is the only type that speaks HTTP and the only type that repairs the payload the server actually returns. A single `RouteDraft` is the selection both screens read and write.

Storyboards for the two screens and SwiftUI were rejected. The first fights dynamic cards and the package sheet. The second contradicts the chosen UI stack.

## Scope

In:

- Load the full address book.
- Sectioned list by the first letter of the name. Row shows initials, name, address, phone.
- Server search via `q`, including an empty-result state with manual address entry.
- One stop and Multi-stop route.
- Package count: an `N×` pill opens a sheet with minus, value, plus, and Save.
- Selected-stop chips and `Continue (N stops)`.
- One instruction card per selected stop: name, count, address, text, counter, Clear all.
- Finish is blocked while any instruction is empty. The error sits on that card.
- Remove a stop from the route, including swipe.
- `POST /v1/routes` with sending, error, and success. A second tap does not create a second route.
- Last-delivery photos, loaded per card without blocking typing. A null photo URL is skipped.
- Driver notify after create, one stop at a time. HTTP 200 with `status: "failed"` stays a failure and retries with a new idempotency key.
- A drop-off photo taken on the device, stored locally, never uploaded.
- The client stays up when the server returns the failures baked into `server.js`.

Out:

- A separate screen after a successful send. The confirmation replaces the card feed.
- Auth, onboarding, settings, extra screens.
- iPad and landscape.

## Modules

| Unit | Responsibility | Depends on |
| --- | --- | --- |
| `Theme` | Colors, type sizes, spacing taken from the screen mock | nothing |
| `Stop`, `RouteStop`, `RouteDraft` | Value types for a stop and the in-progress route | nothing |
| `APIClient` | Requests, retries, decoding, quirk normalization | `URLSession` |
| `RouteDraftStore` | Shared draft: selection, counts, instructions, mode | domain types |
| `StopsViewModel` | Load, search, select, set package count | `APIClient`, `RouteDraftStore` |
| `StopsViewController` | Picker UI, sheet, chips | `StopsViewModel` |
| `InstructionsViewModel` | Validate, remove, submit | `APIClient`, `RouteDraftStore` |
| `InstructionsViewController` | Card feed, finish states | `InstructionsViewModel` |

A view model does not import UIKit. A view controller does not parse JSON or decide retry policy.

## Screens

Both screens share a header. Title is the fixed string `Morning route — Central area`, taken from the mock. The static “38 packages | 14 stops” has no API behind it. The subtitle is computed from the draft: `N packages | M stops`.

Under the header, a two-tab bar switches Stops and Instructions. Instructions with an empty draft shows an empty state and does not call the server. Continue on Stops switches to Instructions.

### Stops

- Segmented control: One stop / Multi-stop route. The screen opens on One stop.
- Search field placeholder: `Search by name, street, or phone`.
- An empty search offers `Enter an address`. That stop is client-only: id `local_` plus a UUID, package limit 99. The server accepts it on create because it does not check that the stop exists.
- Typing waits 300 ms, then calls `GET /v1/stops?q=`. The previous search task is cancelled. Clearing the field shows the address book already loaded, without another fetch.
- Rows are grouped by the first letter of `name`. A trailing A–Z index scrolls to that section. Letters with no section are visible and do nothing.
- Initials are at most two characters: the first alphanumeric of the first word, then of the second word. `24/7 Pharmacy` becomes `2P`. `Isaac's Hardware` becomes `IH`.
- Phone text is shown as the server sent it.
- One stop: choosing a row replaces the current selection. Tapping the selected row clears it.
- Multi-stop: tapping a row toggles it.
- A newly selected stop starts at 1 package.
- The pill shows `N×`. The sheet clamps the value from 1 to that stop’s maximum and writes it only when Save is tapped. Dismissing the sheet keeps the previous count.
- Chips sit above Continue. Each chip removes its stop. Continue is disabled at zero stops. The label is `Continue (N stops)`.

### Instructions

- Cards follow the draft order.
- The sharp card is the one with the largest visible fraction of its own height. Ties keep the previous focused stop. Inactive cards show a live `systemUltraThinMaterialLight` blur that fades in and out. The card stays at alpha 1. There is no content-view scale.
- The field accepts 200 characters. The counter is `N/200`. Clear all empties that card.
- Finish trims each instruction. An empty trimmed string is invalid. The first invalid card scrolls into view and shows `Add instructions for this stop before finishing`.
- Swipe reveals `Remove from route`. The same action is on the card so it is reachable one-handed without a precise swipe.
- Each card shows photos from the last delivery once they arrive. Tags map to Entrance, Parking, and Back door. A null URL is not shown. A manual stop has no server photos. The card also has `Photo of the drop-off point`. The JPEG is saved under Application Support and the path stays on the route stop. It is not part of the create body. If the camera is unavailable, the photo library is used.
- Finish label cycles through `Finish instructions`, `Sending…`, and the error text. On success the feed is replaced by a confirmation that names the returned route id and a driver-alert line per stop. A failed alert can be retried. There is no further screen. The Stops tab stays available. Editing the draft there clears the confirmation and allows another send.
- While a submit task is running, Finish ignores taps.

## Data

`Stop`: `id`, `name`, `address`, `phone`, `zone`, `packagesMax` as `Int`.

`RouteStop`: `stopID`, snapshot of name, address, and phone for display, `packages`, `instructions`, optional `dropOffPhotoPath`.

`RouteDraft`: mode (`.oneStop` or `.multiStop`) and ordered stops. The default mode is one stop. Removing a stop drops its instruction. Switching from multi-stop to one-stop keeps the first selected stop and drops the rest.

`CreatedRoute`: `id`, `status`.

## API client

Base URL is one value, `http://127.0.0.1:4000`, used by the simulator. `Info.plist` allows local networking so plain HTTP to that host loads. A physical phone would point this same value at the machine’s LAN address.

`URLSession` data tasks are wrapped in `async` methods. Each call gets a 20-second timeout.

List loading uses `page_size=50`. The client requests the next page only while the page contains at least one id that is not already collected. An empty page or `items: null` ends the load. Duplicate ids are dropped, first occurrence wins. `total`, `total_pages`, and `has_more` are not used to decide completeness.

Search uses the same endpoint with `q` and the same paging rules.

Retries run only for HTTP 429, 500, and 503, four tries total. If `Retry-After` is present it is honored, capped at 5 seconds. Without it the delay is 0.4 seconds times the attempt number. 400, 404, and 422 are returned to the caller.

Normalization applied before a model exists:

- `items: null` becomes an empty list for that page.
- `packages_max` as a number, a numeric string, or anything else. Unparseable and JSON `null` become 99.
- `notes` is ignored.
- `last_delivery_at` is ignored. The three formats the server emits are not shown.
- Create-route response is decoded for `id` and `status` only.

`POST /v1/routes` body:

```json
{ "stops": [{ "stop_id": "stp_1002", "packages": 2, "instructions": "Enter from the parking lot" }] }
```

`packages` is an integer from 1 through `packagesMax`. `instructions` is the trimmed string, already limited to 200 characters.

## Error handling

| Situation | What the dispatcher sees |
| --- | --- |
| Address book still loading | Spinner in the list area. Search and Continue wait. |
| Load failed after retries | Message and a Retry button. The draft is kept. |
| Search failed | Message under the field. The previous list stays. |
| Search with no rows | `No stop found`, subtitle `Try another street`, and a separate `Enter an address` action. |
| Finish with a gap | Inline error on the card. No request. |
| Submit failed | Error on the Finish button and a chance to retry the same body. |
| Submit succeeded | Confirmation with the route id. Finish cannot fire again until the draft changes. |

The in-flight submit flag is the double-tap guard. The create endpoint has no idempotency key.

## Testing

A unit-test target covers `APIClient` normalization and paging with a stubbed `URLProtocol`:

- numeric, string, and null `packages_max`
- `items: null`
- page 2 repeating the last id of page 1, and a last page whose `has_more` is true
- retry on 503 with `Retry-After`, then success
- 422 from create mapped to a validation error
- draft rules: one-stop replacement, package clamp, empty instruction after trim

View controllers are not part of the unit tests.

## Visual tokens

From the mock, applied with the system font at the mock’s sizes and weights. Heebo is not bundled.

- Screen background `#EEF1F3`
- Card and header `#FFFFFF`
- Teal `#0D6E76`, pressed `#0A585F`
- Primary text `#16232E`
- Secondary text `#6B7C8A`
- Hairline `#DFE5E9`
- Header title 20/28, weight 800
- Tab 14/20, selected weight 700 with a 3 pt teal underline
- Corner radius 12 on cards and the search field, 11 on the mark

Portrait phone only.

## Decisions recorded here

- Service behavior wins over `API.md` and over the mock where they disagree.
- Instruction limit is 200 because `server.js` slices there. The reference and the mock say 250.
- Package maximum 99 stands in for null or garbage `packages_max`.
- Header counts are the live draft, not the mock’s static “38 packages | 14 stops”.
- The picker opens in One stop.
- Search is case-sensitive because the server uses `String.includes` without folding case.
- Photos, notify, manual address, and the drop-off camera are in. The photo file never leaves the phone. Notify is sequential so it stays inside the server rate limit, and a failed payload is retried with a new `Idempotency-Key` because the same key replays the cached failure.
- Deployment target is lowered from the template’s 26.2 to 16.0 to match the assignment.
