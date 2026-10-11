
from fastapi import FastAPI, Request, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, FileResponse, JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
import edge_tts
import uuid
import os
import json
import re
import hashlib
import logging
import shutil
import subprocess
import tempfile
import io
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
import uuid
import json


# Firebase Admin SDK
try:
    import firebase_admin
    from firebase_admin import credentials, storage as fb_storage
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False
    print("WARNING: firebase-admin not available. Cloud storage disabled.")

# ============================================================================
# LOGGING AND FIREBASE SETUP
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("mirror-service")

FIREBASE_STORAGE_BUCKET = os.getenv("FIREBASE_STORAGE_BUCKET", "audiovix-69143.firebasestorage.app")
CANONICAL_AUDIO_ROOT = "audio-files"
CANONICAL_INDEX_ROOT = f"{CANONICAL_AUDIO_ROOT}/index"

def init_firebase():
    """Initialize Firebase Admin SDK if not already initialized."""
    if not FIREBASE_AVAILABLE:
        return None
    try:
        if firebase_admin.get_app():
            return firebase_admin.get_app()
    except ValueError:
        # App not initialized yet
        pass
    
    try:
        creds = credentials.ApplicationDefault()
        firebase_admin.initialize_app(creds, {
            'storageBucket': FIREBASE_STORAGE_BUCKET
        })
        logger.info("Firebase initialized successfully")
        return firebase_admin.get_app()
    except Exception as e:
        logger.error(f"Failed to initialize Firebase: {e}")
        return None

firebase_app = init_firebase()

def get_storage_bucket():
    """Get Firebase storage bucket."""
    if not FIREBASE_AVAILABLE or not firebase_app:
        return None
    return fb_storage.bucket(FIREBASE_STORAGE_BUCKET)

def log_event(level: str, event: str, details: dict = None):
    """Log an event with structured details."""
    entry = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'level': level,
        'event': event,
        **(details or {})
    }
    message = json.dumps(entry)
    if level == 'error':
        logger.error(message)
    elif level == 'warning':
        logger.warning(message)
    else:
        logger.info(message)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def normalize_whitespace(text: str) -> str:
    """Normalize whitespace in text."""
    return re.sub(r'\s+', ' ', text.strip())

def tokenize_for_alignment(text: str) -> List[str]:
    """Tokenize text for alignment."""
    normalized = normalize_whitespace(text)
    matches = re.findall(r"[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*", normalized)
    return matches

def ticks_to_seconds(ticks: int) -> float:
    """Convert ticks to seconds."""
    return round(ticks / 10_000_000, 3)

def hash_dict(d: dict) -> str:
    """Hash a dict to create a unique ID."""
    return hashlib.sha256(json.dumps(d, sort_keys=True).encode()).hexdigest()

def local_server_artifact_id(text: str, voice: str, variant: str, verses: list) -> str:
    """Match AudioVixServer's v2 JSON.stringify request key."""
    payload = {
        'version': 'v2',
        'voice': voice or 'en-US-JennyNeural',
        'variant': variant or 'original',
        'text': text,
        'verses': verses,
    }
    serialized = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
    return hashlib.sha256(serialized.encode('utf-8')).hexdigest()

def safe_path_component(value: Any, fallback: str = "unknown") -> str:
    component = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value or "").strip()).strip(".-")
    return component or fallback

def chapter_index_key(req: "AudioRequest", voice: str) -> Optional[str]:
    if req.version is None or req.book_number is None or req.chapter is None:
        return None

    return "-".join([
        safe_path_component(req.version),
        safe_path_component(req.book_number),
        safe_path_component(req.chapter),
        safe_path_component(voice),
        safe_path_component(req.variant or "original"),
    ]).lower()

def build_word_timings(metadata_entries: List[dict]) -> List[dict]:
    """Build word timings from metadata entries."""
    word_timings = []
    for idx, entry in enumerate(metadata_entries):
        if entry.get('type') == 'WordBoundary':
            start = ticks_to_seconds(entry.get('offset', 0))
            duration = ticks_to_seconds(entry.get('duration', 0))
            end = round(start + duration, 3)
            word_timings.append({
                'index': idx,
                'text': entry.get('text', ''),
                'start': start,
                'duration': duration,
                'end': end
            })
    return word_timings

def split_sentences(text: str) -> List[dict]:
    """Split text into sentences."""
    normalized = normalize_whitespace(text)
    sentences = re.findall(r'[^.!?]+[.!?]+|[^.!?]+$', normalized)
    return [
        {'sentence': i + 1, 'text': normalize_whitespace(s)}
        for i, s in enumerate(sentences)
        if normalize_whitespace(s)
    ]

def build_span_timings(
    segments: List[dict],
    word_timings: List[dict],
    label: str,
    start_cursor: int = 0,
) -> List[dict]:
    """Build verse or sentence timings."""
    timings = []
    cursor = start_cursor
    for segment in segments:
        token_count = len(tokenize_for_alignment(segment['text']))
        if token_count == 0:
            timings.append({
                label: segment.get(label, segment.get('sentence')),
                'text': segment['text'],
                'start': None,
                'duration': 0,
                'end': None
            })
            continue
        
        words = word_timings[cursor:cursor + token_count]
        cursor += token_count
        if not words:
            break
        
        start = words[0]['start']
        end = words[-1]['end']
        duration = round(end - start, 3)
        timings.append({
            label: segment.get(label, segment.get('sentence')),
            'text': segment['text'],
            'start': start,
            'duration': duration,
            'end': end
        })
    
    return timings

def parse_metadata_jsonl(metadata_raw: str) -> List[dict]:
    """Parse metadata JSONL."""
    entries = []
    for line in metadata_raw.strip().split('\n'):
        if line:
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


class AudioRequest(BaseModel):
    text: Optional[str] = None
    voice: Optional[str] = "en-US-AriaNeural"
    variant: Optional[str] = "original"
    verses: Optional[List[Dict[str, Any]]] = None
    version: Optional[str] = None
    book: Optional[str] = None
    book_number: Optional[int] = Field(default=None, alias="bookNumber")
    chapter: Optional[int] = None
    introduction: Optional[str] = None
    force_regenerate: Optional[bool] = Field(default=False, alias="forceRegenerate")


app = FastAPI(title="Mirror Service")

async def generate_audio_with_timings(text: str, voice: str, verses=None, introduction: Optional[str] = None):
    communicate = edge_tts.Communicate(
        text,
        voice,
        boundary="WordBoundary",
    )
    with tempfile.TemporaryDirectory() as tmp:
        audio_path = os.path.join(tmp, "audio.mp3")
        metadata_path = os.path.join(tmp, "metadata.jsonl")

        await communicate.save(audio_path, metadata_path)

        # Load audio
        with open(audio_path, "rb") as f:
            audio_buffer = f.read()

        # Parse metadata
        with open(metadata_path, "r", encoding="utf-8") as f:
            metadata_raw = f.read()

        metadata_entries = parse_metadata_jsonl(metadata_raw)
        word_timings = build_word_timings(metadata_entries)

        verse_segments = []
        if verses:
            verse_segments = [
                {"verse": v["verse"], "text": normalize_whitespace(v["text"])}
                for v in verses
            ]

        log_event('info', 'timing_metadata_built', {
            'metadata_count': len(metadata_entries),
            'word_count': len(word_timings),
            'verse_request_count': len(verse_segments),
            'text_token_count': len(tokenize_for_alignment(text)),
            'verse_token_count': sum(
                len(tokenize_for_alignment(segment['text']))
                for segment in verse_segments
            )
        })

        # Build sentence timings
        sentences = split_sentences(text)
        sentence_timings = build_span_timings(sentences, word_timings, "sentence")

        # Build verse timings
        verse_timings = []
        if verse_segments:
            if introduction:
                prefix_token_count = len(tokenize_for_alignment(normalize_whitespace(introduction)))
            else:
                # legacy fallback for callers not yet sending introduction
                verse_token_count = sum(len(tokenize_for_alignment(s['text'])) for s in verse_segments)
                text_token_count = len(tokenize_for_alignment(text))
                prefix_token_count = max(text_token_count - verse_token_count, 0) 
            verse_timings = build_span_timings(
                verse_segments,
                word_timings,
                "verse",
                start_cursor=prefix_token_count,
            )

            if len(verse_timings) != len(verse_segments):
                log_event('warning', 'verse_timing_alignment_incomplete', {
                    'requested_verses': len(verse_segments),
                    'generated_verses': len(verse_timings),
                    'word_count': len(word_timings),
                    'prefix_token_count': prefix_token_count
                })

        return {
            "audio_buffer": audio_buffer,
            "word_timings": word_timings,
            "sentence_timings": sentence_timings,
            "verse_timings": verse_timings,
        }
        




@app.post("/api/audio")
async def generate_audio(req: AudioRequest):
    """Generate audio with timings and upload to Firebase."""
    text = (req.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="text is required")
    
    voice = (req.voice or "en-US-AriaNeural").strip()
    
    try:
        normalized_text = normalize_whitespace(text)
        normalized_verses = [
            {
                **verse,
                'text': normalize_whitespace(verse.get('text', '')),
            }
            for verse in (req.verses or [])
            if isinstance(verse, dict) and isinstance(verse.get('text'), str)
        ]
        bucket = get_storage_bucket()
        index_key = chapter_index_key(req, voice)
        # indexed = load_indexed_audio(bucket, index_key)
        indexed = load_indexed_audio(bucket, index_key) if not req.force_regenerate else None
        if indexed:
            log_event('info', 'audio_generation_reused', {
                'index_key': index_key,
                'artifact_id': indexed.get('id'),
                'voice': voice,
            })
            return indexed

        # Generate audio and timings (now includes verse support)
        result = await generate_audio_with_timings(
            text=normalized_text, 
            voice=voice,
            verses=normalized_verses, 
            introduction=req.introduction
        )
        audio_buffer = result['audio_buffer']

        # Keep the artifact hash compatible with AudioVixServer's v2 request key.
        artifact_id = local_server_artifact_id(
            normalized_text,
            voice,
            req.variant or 'original',
            normalized_verses,
        )

        timings_data = {
            'wordTimings': result['word_timings'],
            'verseTimings': result['verse_timings'],
            'sentenceTimings': result['sentence_timings']
        }

        urls = upload_to_firebase(
            bucket,
            artifact_id,
            audio_buffer,
            timings_data,
            index_key=index_key,
            index_metadata={
                'version': req.version,
                'book': req.book,
                'bookNumber': req.book_number,
                'chapter': req.chapter,
                'voice': voice,
                'variant': req.variant or 'original',
                'counts': {
                    'words': len(result['word_timings']),
                    'sentences': len(result['sentence_timings']),
                    'verses': len(result['verse_timings']),
                },
            },
        )

        log_event('info', 'audio_generation_completed', {
            'artifact_id': artifact_id,
            'voice': voice,
            'text_length': len(text),
            'word_count': len(result['word_timings']),
            'sentence_count': len(result['sentence_timings']),
            'verse_count': len(result['verse_timings'])
        })

        return {
            'id': artifact_id,
            'voice': voice,
            'audioUrl': urls.get('audioUrl', ''),
            'url': urls.get('audioUrl', ''),
            'timings': {
                **urls.get('timings', {}),
                'wordTimings': result['word_timings'],
                'sentenceTimings': result['sentence_timings'],
                'verseTimings': result['verse_timings'],
            },
            'wordTimings': result['word_timings'],
            'sentenceTimings': result['sentence_timings'],
            'timingsAvailable': bool(
                result['word_timings']
                and urls.get('timings', {}).get('allUrl')
            ),
            'counts': {
                'words': len(result['word_timings']),
                'sentences': len(result['sentence_timings']),
                'verses': len(result['verse_timings'])
            }
        }

    except Exception as e:
        log_event('error', 'audio_generation_failed', {
            'error': str(e),
            'text_length': len(text)
        })
        raise HTTPException(status_code=500, detail=f"Audio generation failed: {str(e)}")


def upload_to_firebase(
    bucket,
    artifact_id: str,
    audio_buffer: bytes,
    timings_data: dict,
    index_key: Optional[str] = None,
    index_metadata: Optional[dict] = None,
) -> dict:
    """Upload audio and timings to Firebase Storage with a public download token."""
    if not bucket:
        return {}
    
    urls = {}
    try:
        # 1. Generate unique download tokens
        audio_token = str(uuid.uuid4())
        timings_token = str(uuid.uuid4())

        # 2. Upload audio with download token metadata
        audio_path = f"{CANONICAL_AUDIO_ROOT}/{artifact_id}.mp3"
        timings_path = f"{CANONICAL_AUDIO_ROOT}/{artifact_id}.all-timings.json"
        audio_blob = bucket.blob(audio_path)
        audio_blob.metadata = {"firebaseStorageDownloadTokens": audio_token}
        audio_blob.upload_from_string(audio_buffer, content_type="audio/mpeg")
        
        urls['audioUrl'] = (
            f"https://firebasestorage.googleapis.com/v0/b/{FIREBASE_STORAGE_BUCKET}/o/"
            f"{CANONICAL_AUDIO_ROOT.replace('/', '%2F')}%2F{artifact_id}.mp3?alt=media&token={audio_token}"
        )
        
        # 3. Upload timings with download token metadata
        timings_blob = bucket.blob(timings_path)
        timings_blob.metadata = {"firebaseStorageDownloadTokens": timings_token}
        timings_blob.upload_from_string(
            json.dumps(timings_data, indent=2),
            content_type="application/json"
        )
        
        urls['timings'] = {
            'allUrl': (
                f"https://firebasestorage.googleapis.com/v0/b/{FIREBASE_STORAGE_BUCKET}/o/"
                f"{CANONICAL_AUDIO_ROOT.replace('/', '%2F')}%2F{artifact_id}.all-timings.json?alt=media&token={timings_token}"
            )
        }

        if index_key:
            index_path = f"{CANONICAL_INDEX_ROOT}/{index_key}.json"
            index_blob = bucket.blob(index_path)
            index_blob.upload_from_string(
                json.dumps({
                    **(index_metadata or {}),
                    'indexKey': index_key,
                    'artifactId': artifact_id,
                    'audioPath': audio_path,
                    'timingsPath': timings_path,
                    'audioUrl': urls['audioUrl'],
                    'timings': urls['timings'],
                    'updatedAt': datetime.utcnow().isoformat() + 'Z',
                }, indent=2),
                content_type="application/json",
            )
        
        log_event('info', 'audio_artifacts_uploaded', {
            'artifact_id': artifact_id,
            'audio_size': len(audio_buffer),
            'timings_count': {
                'words': len(timings_data.get('wordTimings', [])),
                'sentences': len(timings_data.get('sentenceTimings', [])),
                'verses': len(timings_data.get('verseTimings', []))
            }
        })
    except Exception as e:
        log_event('error', 'firebase_upload_failed', {'artifact_id': artifact_id, 'error': str(e)})
    
    return urls


def load_indexed_audio(bucket, index_key: Optional[str]) -> Optional[dict]:
    """Return a previously generated chapter without synthesizing it again."""
    if not bucket or not index_key:
        return None

    try:
        index_blob = bucket.blob(f"{CANONICAL_INDEX_ROOT}/{index_key}.json")
        if not index_blob.exists():
            return None

        index = json.loads(index_blob.download_as_string())
        audio_path = index.get('audioPath')
        timings_path = index.get('timingsPath')
        if not audio_path or not timings_path:
            return None

        if not bucket.blob(audio_path).exists() or not bucket.blob(timings_path).exists():
            return None

        audio_url = index.get('audioUrl')
        timings = index.get('timings') or {}
        if not audio_url or not timings.get('allUrl'):
            return None
        timings_data = json.loads(bucket.blob(timings_path).download_as_string())
        response_timings = {
            **timings,
            'wordTimings': timings_data.get('wordTimings', []),
            'sentenceTimings': timings_data.get('sentenceTimings', []),
            'verseTimings': timings_data.get('verseTimings', []),
        }

        return {
            'id': index.get('artifactId', index_key),
            'voice': index.get('voice'),
            'audioUrl': audio_url,
            'url': audio_url,
            'timings': response_timings,
            'wordTimings': timings_data.get('wordTimings', []),
            'sentenceTimings': timings_data.get('sentenceTimings', []),
            'timingsAvailable': True,
            'counts': index.get('counts', {}),
            'reused': True,
        }
    except Exception as e:
        log_event('warning', 'audio_index_lookup_failed', {
            'index_key': index_key,
            'error': str(e),
        })
        return None


# ============================================================================
# REQUEST MODELS
# ============================================================================

# class AudioRequest(BaseModel):
#     text: Optional[str] = None
#     voice: Optional[str] = "en-US-AriaNeural"
#     variant: Optional[str] = "original"
#     verses: Optional[List[Dict[str, Any]]] = None

class BookTextRequest(BaseModel):
    path: str

# ============================================================================
# FASTAPI SETUP
# ============================================================================


@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all incoming requests."""
    request_id = str(uuid.uuid4())
    started_at = datetime.utcnow()
    
    # Log cloud access
    log_event('info', 'cloud_server_accessed', {
        'request_id': request_id,
        'method': request.method,
        'path': request.url.path,
        'client_ip': request.client.host if request.client else None,
    })
    
    response = await call_next(request)
    
    duration_ms = int((datetime.utcnow() - started_at).total_seconds() * 1000)
    log_event('info', 'request_completed', {
        'request_id': request_id,
        'method': request.method,
        'path': request.url.path,
        'status_code': response.status_code,
        'duration_ms': duration_ms
    })
    
    return response

# ============================================================================
# HEALTH & INFO ENDPOINTS
# ============================================================================

@app.get("/")
def root():
    return {"message": "Mirror Service - AVS Fallback Server"}

@app.get("/health")
def health():
    return {"status": "ok", "firebase": "available" if FIREBASE_AVAILABLE else "unavailable"}

# ============================================================================
# AUDIO & TIMINGS ENDPOINTS
# ============================================================================

@app.get("/api/timings/{artifact_id}/{kind}")
async def get_timings(artifact_id: str, kind: str):
    """Retrieve timings for an artifact from Firebase."""
    if kind not in ['words', 'verses', 'sentences', 'all']:
        raise HTTPException(status_code=400, detail="kind must be words, verses, sentences, or all")
    
    bucket = get_storage_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Firebase storage unavailable")
    
    try:
        timings_blob = bucket.blob(f"timings/{artifact_id}.all-timings.json")
        timings_data = json.loads(timings_blob.download_as_string())
        
        # Filter by kind
        if kind == 'words':
            return {'wordTimings': timings_data.get('wordTimings', [])}
        elif kind == 'verses':
            return {'verseTimings': timings_data.get('verseTimings', [])}
        elif kind == 'sentences':
            return {'sentenceTimings': timings_data.get('sentenceTimings', [])}
        else:
            return timings_data
    
    except Exception as e:
        log_event('error', 'timings_retrieval_failed', {'artifact_id': artifact_id, 'error': str(e)})
        raise HTTPException(status_code=404, detail="Timings not found")

MAX_VIDEO_SIZE = 500 * 1024 * 1024  # 500MB Limit

@app.post("/api/convert-video")
async def convert_video(request: Request, file: UploadFile = File(...)):
    """
    Convert an uploaded video to MP3.
    The UI should use <input type="file" accept="video/*"> for iOS photo library access.
    """
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_VIDEO_SIZE:
        log_event('warning', 'upload_too_large', {'size': content_length})
        raise HTTPException(status_code=413, detail="File too large. Maximum size is 500MB.")

    if not file.content_type or not file.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="Invalid file type. Please upload a video.")

    # Check if ffmpeg is actually installed and accessible
    ffmpeg_path = shutil.which("ffmpeg")
    if not ffmpeg_path:
        log_event('error', 'ffmpeg_missing', {'detail': 'FFmpeg binary not found in system PATH'})
        raise HTTPException(status_code=500, detail="Server Error: FFmpeg not installed. Please contact administrator.")

    artifact_id = str(uuid.uuid4())
    
    with tempfile.TemporaryDirectory() as tmp_dir:
        input_path = os.path.join(tmp_dir, "input_video")
        output_path = os.path.join(tmp_dir, f"{artifact_id}.mp3")
        
        # Save the uploaded file to the temporary directory
        with open(input_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        try:
            # Use FFmpeg to convert video to MP3
            # -vn: skip video, -acodec libmp3lame: use MP3 codec, -q:a 2: high quality VBR
            process = subprocess.run([ 
                'ffmpeg', '-i', input_path, 
                '-vn', '-acodec', 'libmp3lame', 
                '-q:a', '2', '-y', output_path
            ], capture_output=True, text=True)
            
            if process.returncode != 0:
                error_msg = process.stderr if process.stderr else "Unknown FFmpeg error"
                logger.error(f"FFmpeg error: {error_msg}")
                raise Exception(f"FFmpeg failed: {error_msg[:100]}")

            with open(output_path, "rb") as f:
                audio_buffer = f.read()
                
            bucket = get_storage_bucket()
            if bucket:
                # Upload to Firebase Storage
                audio_blob = bucket.blob(f"audio/{artifact_id}.mp3")
                audio_blob.upload_from_string(audio_buffer, content_type="audio/mpeg")
                audio_url = f"https://firebasestorage.googleapis.com/v0/b/{FIREBASE_STORAGE_BUCKET}/o/audio%2F{artifact_id}.mp3?alt=media"
                
                log_event('info', 'video_converted', {'artifact_id': artifact_id, 'filename': file.filename})
                return {"id": artifact_id, "audioUrl": audio_url, "filename": file.filename}
            else:
                # Fallback: stream the file back directly if Firebase is unavailable
                return StreamingResponse(io.BytesIO(audio_buffer), media_type="audio/mpeg", 
                                         headers={"Content-Disposition": f"attachment; filename={artifact_id}.mp3"})
        except Exception as e:
            log_event('error', 'conversion_error', {'error': str(e)})
            raise HTTPException(status_code=500, detail=f"Conversion failed: {str(e)}")

# ============================================================================
# BOOK TEXT ENDPOINT (Firebase)
# ============================================================================

@app.get("/api/book-text")
async def get_book_text(path: str):
    """Fetch book text asset from Firebase Storage."""
    # Validate path format
    if not re.match(r'^users/[^/]+/books/[^/]+/(?:original|modern)\.json$', path, re.IGNORECASE):
        raise HTTPException(status_code=400, detail="path is invalid")
    
    bucket = get_storage_bucket()
    if not bucket:
        raise HTTPException(status_code=503, detail="Firebase storage unavailable")
    
    try:
        blob = bucket.blob(path)
        data = json.loads(blob.download_as_string())
        
        log_event('info', 'book_text_fetched', {
            'path': path,
            'chapters': len(data.get('chapters', [])) if isinstance(data.get('chapters'), list) else 0
        })
        
        return data
    
    except Exception as e:
        log_event('error', 'book_text_fetch_failed', {'path': path, 'error': str(e)})
        raise HTTPException(status_code=404, detail="Book text asset not found")

# ============================================================================
# LEGACY ENDPOINTS (for compatibility)
# ============================================================================

@app.post("/echo")
def echo(data: dict):
    return {"you_sent": data}

@app.get("/text", response_class=HTMLResponse)
def text():
    try:
        with open("mirror.html", "r", encoding="utf-8") as f:
            return f.read()
    except:
        return "<h1>Mirror Service</h1>"

@app.post("/word-count")
def word_count(data: dict):
    text = data.get("text", "")
    return {
        "words": len(text.split()),
        "characters": len(text)
    }

@app.post("/tts")
async def tts_legacy(text: str, voice: str = "en-GB-SoniaNeural"):
    """Legacy TTS endpoint (returns file instead of JSON)."""
    output_path = f"/tmp/{uuid.uuid4()}.mp3"
    
    try:
        communicate = edge_tts.Communicate(
            text,
            voice,
            boundary="WordBoundary",
        )
        await communicate.save(output_path)
        return FileResponse(
            output_path,
            media_type="audio/mpeg",
            filename="speech.mp3"
        )
    except Exception as e:
        log_event('error', 'legacy_tts_failed', {'error': str(e)})
        raise HTTPException(status_code=500, detail="TTS generation failed")
