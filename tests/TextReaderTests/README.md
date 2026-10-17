# Text Reader checks

Add `TextReaderTests.swift` to a ClearBrowser iOS unit-test target in Xcode. The existing Swift package builds BingBot only. These tests require the Apple SDK and have not run in the Windows workspace.

Tests cover lossless Unicode chunking, the 3,000-character bound, overlong tokens, sentence boundary preference, repeated sentence alignment, unmatched timing safety, AudioVix timing JSON, and saved document round trips.

Device validation still required:

- Import pasted text longer than three pages; verify the first page starts before remaining audio is generated.
- Import a static HTML article and a plain-text URL; exercise failed URL and unsupported file responses.
- Verify the local `/health` route selects the local audio service and unavailability selects the cloud.
- Exercise AudioVix immediate and queued responses, inline and linked timing data, missing timings, and request failure/retry.
- Listen across page boundaries; a delayed next page should show preparation status and then resume automatically.
- Pause during generation, change pages during generation, and leave the reader; stale requests must never start playback.
- Seek forward/backward and change speed; sentence highlighting must track the actual audio time.
- Drag the text to suspend follow mode; tap Follow reading to restore it.
- Pause, leave the app, relaunch, select the document, and resume at the saved page/time/speed.
- Delete a document and verify its audio and position files are removed.
