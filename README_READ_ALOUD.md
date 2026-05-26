# ClearBrowser Read Aloud Feature Guide

## Overview
The Read Aloud feature allows users to listen to article content from websites using the audioVix text-to-speech server at `10.0.0.152:4000`.

## Features

### What's Included
- **Article Content Extraction**: Automatically detects and extracts article text from web pages
- **Audio Synthesis**: Converts text to speech using the audioVix server
- **Playback Controls**: Play, pause, resume, and stop functionality
- **Playback Speed Control**: Adjust playback speed from 0.5x to 2.0x
- **Progress Tracking**: Visual progress bar with time display
- **Error Handling**: User-friendly error messages

### Supported Content Sources
The feature automatically detects article content from:
- HTML `<article>` tags
- `<main>` content sections
- Common article class patterns (`article`, `post-content`, `entry-content`)
- General page body content (fallback)

## How to Use

### Starting Read Aloud
1. Navigate to an article or content-rich webpage in ClearBrowser
2. Tap the **speaker icon** in the bottom toolbar
3. The app will extract article content and send it to the audioVix server
4. Audio synthesis will begin automatically once ready

### Playback Controls
- **Play/Pause**: Tap the speaker icon again to pause, tap to resume
- **Stop**: Tap the stop icon to stop playback and reset
- **Speed Control**: Use the slider to adjust playback speed (0.5x - 2.0x)

### Error Handling
If an error occurs:
- An error message will appear in the control panel
- Check your network connection to `10.0.0.152:4000`
- Ensure the audioVix server is running
- Verify the page has article content available

## Architecture

### Components

#### AudioVixService (`Services/AudioVixService.swift`)
Main service handling:
- Article content extraction via JavaScript injection
- HTTP requests to audioVix server
- Audio synthesis and playback management
- Progress tracking and delegation

**Key Methods:**
- `extractArticleContent(from:completion:)` - Extracts text from webpage
- `synthesizeSpeech(text:)` - Converts text to audio via audioVix server
- `play()`, `pause()`, `resume()`, `stop()` - Playback control
- `setPlaybackRate(_:)` - Adjusts playback speed

#### HomeViewModel Updates
Added read-aloud properties:
- `isReadAloudAvailable` - Whether audio has been synthesized
- `isReadAloudPlaying` - Current playback state
- `readAloudProgress` - Current playback time
- `readAloudDuration` - Total audio duration
- `currentWebView` - Reference to active WebView for content extraction

**Key Methods:**
- `startReadAloud(from:)` - Initiates extraction and synthesis
- `pauseReadAloud()` - Pauses playback
- `resumeReadAloud()` - Resumes playback
- `stopReadAloud()` - Stops and resets
- `setReadAloudSpeed(_:)` - Adjusts playback speed

#### ReadAloudControlView (`Views/ReadAloudControlView.swift`)
Optional advanced control interface providing:
- Detailed playback controls
- Speed adjustment slider
- Progress visualization
- Error display

#### UI Integration
- Read-aloud button added to bottom toolbar
- Orange color scheme for visual distinction
- Icon changes based on playback state

## Configuration

### AudioVix Server Settings
Edit `AudioVixService.swift` line 7 to change the server address:
```swift
private let audioVixBaseURL = "http://10.0.0.152:4000"
```

### Server Endpoint
The service expects the following endpoint:

**Endpoint:** `POST /synthesize`

**Request Body:**
```json
{
  "text": "Article content text...",
  "voice": "default",
  "rate": 1.0
}
```

**Expected Response:**
- Status: 200-299 (HTTP success)
- Body: MP3 audio file data (binary)
- Content-Type: Implied as MP3

## Customization Options

### Modifying Article Detection
Edit the `extractArticleContent` method in `AudioVixService.swift` to add or modify CSS selectors for your target websites:

```swift
// Add custom selectors
const articleDiv = document.querySelector('[class*="article"], [class*="custom-content"]');
```

### Adding Voice Options
Modify the `synthesizeSpeech` method to support multiple voices:
```swift
let payload: [String: Any] = [
    "text": text,
    "voice": userSelectedVoice,  // Allow user selection
    "rate": playbackRate
]
```

### Adjusting Speed Limits
Edit the `setPlaybackRate` method in `AudioVixService.swift`:
```swift
// Change range from 0.5...2.0 to desired limits
playerToPlay?.rate = max(0.25, min(3.0, rate))
```

## Troubleshooting

### No Audio Synthesized
- **Cause**: audioVix server unreachable
- **Solution**: 
  - Verify server is running at `10.0.0.152:4000`
  - Check network connectivity
  - Review server logs for errors

### No Article Content Found
- **Cause**: Page structure doesn't match detection patterns
- **Solution**:
  - Add custom CSS selectors for the website
  - Use page body content (automatic fallback)
  - Contact developer to add pattern support

### Audio Playback Fails
- **Cause**: AVAudioSession misconfiguration or invalid audio format
- **Solution**:
  - Ensure device audio is enabled
  - Verify volume is not muted
  - Check audioVix returns valid MP3 data

### High Battery Usage
- **Cause**: Continuous progress tracking
- **Solution**:
  - CADisplayLink is configured for 1 FPS (efficient)
  - Consider stopping audio extraction if not needed

## Performance Notes
- Article extraction runs on main thread but is typically <100ms
- Audio synthesis latency depends on server response time
- Progress updates limited to 1 per second to reduce CPU usage
- Memory footprint: ~2-5MB for typical article audio

## Future Enhancements
- Offline caching of synthesized audio
- Support for multiple voice profiles
- Text highlighting during playback
- Bookmark-specific audio preferences
- Integration with system accessibility features

## API Reference

### AudioVixService Public API

```swift
// Extract article from WebView
func extractArticleContent(from webView: WKWebView, completion: @escaping (String?) -> Void)

// Synthesize speech from text
func synthesizeSpeech(text: String) async throws -> AVAudioPlayer

// Playback control
func play(audioPlayer: AVAudioPlayer? = nil)
func pause()
func resume()
func stop()

// Speed control (0.5x to 2.0x)
func setPlaybackRate(_ rate: Float)

// Published properties
@Published var isPlaying: Bool
@Published var currentTime: TimeInterval
@Published var duration: TimeInterval
@Published var isLoading: Bool
@Published var errorMessage: String?
```

## Notes
- Read-aloud feature respects private mode (content not cached when private mode enabled)
- Multiple tabs can each trigger independent audio synthesis
- Switching tabs doesn't automatically stop playback (manual stop required)
