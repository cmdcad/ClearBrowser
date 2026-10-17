# Text Reader

Text Reader is a self-contained reading tool in ClearBrowser's Apps hub. It currently opens without a StoreKit purchase; no new product or price has been configured.

Paste text or import a static HTTP(S) HTML article, text file, or JSON document. Login and JavaScript-rendered pages may require pasting their text. Imports have no explicit total-length cap; available memory, storage, and service capacity still apply. HTML imports currently require UTF-8.

Documents split into pages of at most 3,000 Swift characters. Splitting prefers sentence endings and whitespace, preserving the complete source text. An individual token longer than the limit splits at a character boundary.

Audio generation uses AudioVix's existing `/api/audio` protocol with `original`, `en-US-AndrewNeural`, and sentence entries in `verses`. A five-second local `/health` check selects `AudioServerBaseURL` from Info.plist; otherwise the current Mirror cloud endpoint is used. The client supports immediate responses, queued jobs with bounded polling, inline timing arrays, and linked timing JSON. There are no changes to the sibling AudioVix project.

Playback begins when the current page is ready, preparing one page ahead. Audio and timings are cached in Application Support/TextReader under each document UUID. Documents and small, separate position files persist locally; no account sync is implemented. Delete a document by swiping its library row to remove its cached assets too.

Sentence highlighting uses AudioVix timestamps and the player's actual time. Sequential text matching maps timings into the original page, including repeated sentences. Unmatched timing text is skipped rather than guessed. Missing timings allow audio-only playback. Word timings are retained for a later word-highlighting option; this version highlights sentences.

Auto-follow centers each active sentence. Dragging the text suspends following; Follow reading restores it. Page changes occur on audio completion, including any trailing silence; this avoids cutting off the final spoken word. If the next page is still generating, playback waits for it. The queue reduces gaps but does not guarantee gapless audio.

The miniplayer provides play/pause, previous/next page, seeking within the loaded page, and speed. Position saves every five seconds, on pause, page changes, and scene transitions. Opening a saved document restores page/time/speed and waits for Play. Leaving Text Reader pauses playback.

Validation on an Apple build host is still required; this Windows workspace has no Swift compiler, Xcode, or iOS simulator. See tests/TextReaderTests/README.md for the test and device checklist.
