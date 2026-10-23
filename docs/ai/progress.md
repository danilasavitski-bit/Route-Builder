# SDD ledger

Copied from `.superpowers/sdd/progress.md` before that scratch ledger is dropped. Entries below are the review-fix pass on `feature/route-builder`.

Task 1: complete (commits bd704b2..607d2b6, review clean)
Minor for final review: retry of a failed notice after the stop leaves the draft has no direct test. Cosmetic: notify loop could iterate stop ids only.
Task 2: complete (commits 607d2b6..e57cd6b, review clean)
Task 3: complete (commits e57cd6b..926329c, review clean)
Task 4: complete (commits 926329c..25a0afa, review clean)
Minor for final review: StopCell checkbox inset and hidden-phone width are untested.
Task 5: complete (commits 25a0afa..0e949ed, review clean)
Task 6: complete (commits 0e949ed..09e07a0, review clean)
Minor for final review: loadImage is assigned after showDeliveryPhotos; a failed gallery is not retried; the failed-photo caption can truncate.
Task 7: complete (commits 09e07a0..7158527, review clean)
Minor for final review: cancellation also maps NSError domain Swift.CancellationError; no test for URLError.cancelled or a non-cancel URL error still becoming transport.
Task 8: complete (commits 7158527..713ead4, review clean after wording fix)
Task 9: complete. The test target was run again by hand and passed.

## After the ledger

Final review asked for four fixes. Commit 925437a keeps a rendered-stop snapshot, clears the in-flight finish lock after create, treats `URLError.cancelled` as cancellation, and makes the card-height test async.
Image bytes moved off the cell's async closure in ce2c3c8, after that closure crashed while Swift copied it.
Translucent instruction circles removed in e191d58.
`feature/route-builder` merged into `develop` at 082bee6.
