# Bricks Catalog — Arduino UNO Q App Lab

Complete, source-verified catalog of every official Brick shipped in
`app-bricks-py`. A **Brick** is a reusable Python component that wraps app logic
(and optionally Docker Compose infrastructure / an AI model runner). You compose
an app by declaring Bricks in `app.yaml` and using their Python classes from
`python/main.py`.

All facts below were read from the cloned source at
`/Users/tew/Desktop/UNO-Q/skill-sources/app-bricks-py/src/arduino/app_bricks/`.
Each entry cites its source file. Anything not confirmed in source is marked
**(unverified)**.

---

## How Bricks work (the contract)

- **Declare** a Brick in `app.yaml` under `bricks:` using its `id` (e.g.
  `arduino:llm`). The `id` comes from each brick's `brick_config.yaml`.
- **Import** the class from `arduino.app_bricks.<module>` and instantiate it.
- **Lifecycle**: every Brick class is decorated with `@brick`
  (`src/arduino/app_utils/brick.py`). The decorator patches `__init__` so that
  constructing an instance auto-registers it with the central `App` controller.
  `App.run()` then starts all registered Bricks, runs their
  `@brick.execute` (one-shot, dedicated thread) and `@brick.loop` (repeated,
  dedicated thread) methods, and blocks until Ctrl+C / SIGTERM.
- **Run**: `from arduino.app_utils import App` then `App.run()` as the last line
  of `python/main.py` (`src/arduino/app_utils/app.py`).

```python
from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI

ui = WebUI()                 # auto-registers with App
ui.expose_api("GET", "/hello", lambda: {"message": "hi"})
App.run()                    # starts every registered brick, blocks
```

### `brick_config.yaml` fields seen across bricks
| Field | Meaning |
| --- | --- |
| `id` | The `arduino:<name>` id you put under `bricks:` in `app.yaml`. |
| `category` | `text`, `audio`, `video`, `image`, `storage`, `ui`, `miscellaneous`. |
| `requires_container: true` | Brick spins up a Docker Compose service (model runner / DB). |
| `requires_model: true` + `model:` | Needs an AI model asset (`.eim` for Edge Impulse, Genie/QNN for others). |
| `requires_services:` | Depends on a platform service, e.g. `arduino:genie`, `arduino:genie_audio`. |
| `required_devices:` | Hardware binding: `camera`, `microphone`, `speaker`. |
| `supported_boards: ["ventunoq"]` | `ventunoq` = the UNO Q (Qualcomm) board id; `unoq` also appears. |
| `variables:` | Env vars (some `secret: true`, some `hidden: true` with defaults). |
| `ai_frameworks_compatibility:` | `edgeimpulse`, `genie`, `qnn`. |

> **`unoq` vs `ventunoq`**: several configs target only `ventunoq` (Qualcomm
> Dragonwing build) or branch model choice by platform (`model_by_platform`).
> Honor `supported_boards` when picking a Brick.

---

## Category index (29 bricks)

| Category | Bricks |
| --- | --- |
| AI text / LLM | `llm`, `cloud_llm`, `vlm`, `mood_detector` |
| AI vision (static) | `object_detection`, `image_classification`, `visual_anomaly_detection`, `camera_code_detection` |
| AI vision (video stream) | `video_objectdetection`, `video_imageclassification`, `gesture_recognition` |
| AI audio | `asr`, `cloud_asr`, `tts`, `audio_classification`, `keyword_spotting` |
| AI sensor | `motion_detection`, `vibration_anomaly_detection` |
| Sound synthesis | `sound_generator`, `wave_generator` |
| UI | `web_ui`, `streamlit_ui` |
| Data / DB | `dbstorage_sqlstore`, `dbstorage_tsstore` |
| Comms / cloud | `mqtt`, `telegram_bot`, `arduino_cloud` |
| Web data services | `weather_forecast`, `air_quality_monitoring` |

---

# AI — Text / LLM

### `arduino:llm` — Large Language Model (on-device)
Source: `llm/__init__.py`, `llm/local_llm.py`. Deep guide: `on-device-llm.md`.

- **Import**: `from arduino.app_bricks.llm import LargeLanguageModel`
- **Purpose**: chat with a locally-hosted LLM served by the **Genie** model
  runner (default model `genie:qwen3_4b_instruct_2507`). OpenAI-compatible API
  under the hood; subclasses `CloudLLM`. `requires_services: ["arduino:genie"]`,
  `supported_boards: ["ventunoq"]`.
- **Constructor**: `LargeLanguageModel(api_key=os.getenv("LOCAL_LLM_API_KEY","api_key"), system_prompt="", temperature=0.7, max_tokens=512, timeout=None, tools=None, model=None, **kwargs)`. If `model` is `None` it resolves from app/brick config.
- **Key methods**: `chat(message, images=None) -> str`, `chat_stream(message, images=None) -> Iterator[str]`, `stop_stream()`, `with_memory(max_messages=10) -> self`, `clear_memory()`, `list_models() -> List[str]`, `get_client() -> BaseChatModel`. `<think>...</think>` reasoning tags are stripped automatically.

```python
from arduino.app_bricks.llm import LargeLanguageModel
llm = LargeLanguageModel(system_prompt="You are a helpful assistant").with_memory(20)
for token in llm.chat_stream("Explain edge AI in one sentence"):
    print(token, end="", flush=True)
```
`app.yaml`: `bricks: [arduino:llm]`

### `arduino:cloud_llm` — Cloud LLM
Source: `cloud_llm/cloud_llm.py`, `cloud_llm/models.py`.

- **Import**: `from arduino.app_bricks.cloud_llm import CloudLLM, CloudModel, CloudModelProvider`
- **Purpose**: same chat API as `LargeLanguageModel` but against Anthropic /
  OpenAI / Google. Requires an `API_KEY` env var (`secret: true`).
- **Constructor**: `CloudLLM(api_key=os.getenv("API_KEY",""), model=CloudModel.ANTHROPIC_CLAUDE, system_prompt="", temperature=0.7, max_tool_loops=8, timeout=None, tools=None, callbacks=None, **kwargs)`. Model id accepts a provider prefix: `"openai:..."`, `"anthropic:..."`, `"google:..."`; no prefix defaults to OpenAI-compatible.
- **Defaults** (`models.py`): `ANTHROPIC_CLAUDE="claude-sonnet-4-6"`, `OPENAI_GPT="gpt-5.4-mini"`, `GOOGLE_GEMINI="gemini-2.5-flash"`.
- **Key methods**: identical surface — `chat`, `chat_stream`, `stop_stream`, `with_memory`, `clear_memory`, `get_client`. Built-in **tool/function calling** via `tools=[...]` (LangChain `@tool`) with `max_tool_loops` guard.

```python
from arduino.app_bricks.cloud_llm import CloudLLM, CloudModel
llm = CloudLLM(model=CloudModel.OPENAI_GPT, system_prompt="Be terse")
print(llm.chat("hi"))
```
`app.yaml`: `bricks: [arduino:cloud_llm]` + set `API_KEY` secret.

### `arduino:vlm` — Vision Language Model (on-device)
Source: `vlm/__init__.py`, `vlm/local_vlm.py`.

- **Import**: `from arduino.app_bricks.vlm import VisionLanguageModel`
- **Purpose**: multimodal local model (default `genie:qwen3-vl-4b`) — chat over
  text + images. Subclasses `LargeLanguageModel`. `requires_services: ["arduino:genie"]`, `ventunoq` only.
- **Key methods**: `chat(message, images=None)`, `chat_stream(message, images=None)`, `stop_stream()`, `with_memory(max_messages=0)` (note: memory **off by default** here), `clear_memory()`. `images` is a list of file paths or raw `bytes`.

```python
from arduino.app_bricks.vlm import VisionLanguageModel
vlm = VisionLanguageModel(system_prompt="Describe the scene")
print(vlm.chat("What is in this image?", images=["/app/frame.jpg"]))
```
`app.yaml`: `bricks: [arduino:vlm]`

### `arduino:mood_detector` — Mood Detection
Source: `mood_detector/__init__.py`.

- **Import**: `from arduino.app_bricks.mood_detector import MoodDetector`
- **Purpose**: classify text sentiment as positive / negative / neutral (local
  sentiment analyzer, no model download). `category: text`.
- **Constructor**: `MoodDetector()`
- **Key method**: `get_sentiment(text: str) -> str`

```python
from arduino.app_bricks.mood_detector import MoodDetector
print(MoodDetector().get_sentiment("I love this board!"))  # -> "positive"
```
`app.yaml`: `bricks: [arduino:mood_detector]`

---

# AI — Vision (single image)

These four classify/inspect a still image or file. The detection bricks
subclass `EdgeImpulseRunnerFacade` and run an Edge Impulse `.eim` model in a
container (`requires_container: true`, `requires_model: true`).

### `arduino:object_detection` — Object Detection
Source: `object_detection/__init__.py`. Default model `yolox-object-detection`.
- **Import**: `from arduino.app_bricks.object_detection import ObjectDetection`
- **Constructor**: `ObjectDetection(confidence: float = 0.3)`
- **Methods**: `detect(image_bytes, image_type="jpg", confidence=None) -> dict`, `detect_from_file(image_path, confidence=None) -> dict`, `draw_bounding_boxes(image, detections) -> PIL.Image`, `process(item)`.

```python
from arduino.app_bricks.object_detection import ObjectDetection
det = ObjectDetection(confidence=0.4)
result = det.detect_from_file("/app/photo.jpg")
```
`app.yaml`: `bricks: [arduino:object_detection]`

### `arduino:image_classification` — Image Classification
Source: `image_classification/__init__.py`. Default `mobilenet-image-classification`.
- **Import**: `from arduino.app_bricks.image_classification import ImageClassification`
- **Constructor**: `ImageClassification(confidence: float = 0.3)`
- **Methods**: `classify(image_bytes, image_type="jpg", confidence=None) -> dict`, `classify_from_file(image_path, confidence=None) -> dict`, `process(item)`.

### `arduino:visual_anomaly_detection` — Visual Anomaly Detection
Source: `visual_anomaly_detection/__init__.py`. Default `concrete-crack-anomaly-detection` (high-res on `ventunoq`).
- **Import**: `from arduino.app_bricks.visual_anomaly_detection import VisualAnomalyDetection`
- **Constructor**: `VisualAnomalyDetection()`
- **Methods**: `detect(image_bytes, image_type="jpg") -> dict`, `detect_from_file(image_path) -> dict`, `process(item)`.

### `arduino:camera_code_detection` — Camera Code Detection (QR / barcode)
Source: `camera_code_detection/detection.py`, `.../utils.py`. `required_devices: [camera]`. No model download — uses classical CV.
- **Import**: `from arduino.app_bricks.camera_code_detection import CameraCodeDetection, Detection, draw_bounding_box`
- **Constructor**: `CameraCodeDetection(...)` (camera-backed; see source for kwargs).
- **Methods**: `start()`, `stop()`, `loop()`, `on_detect(callback)` (callback gets `(frame: Image, detections)`), `on_frame(callback)`, `on_error(callback)`. `Detection` carries the decoded payload; `draw_bounding_box(frame, detection)` overlays it.

```python
from arduino.app_utils import App
from arduino.app_bricks.camera_code_detection import CameraCodeDetection
codes = CameraCodeDetection()
codes.on_detect(lambda frame, dets: print([d for d in dets]))
App.run()
```
`app.yaml`: `bricks: [arduino:camera_code_detection]` (+ camera device).

---

# AI — Vision (live video stream)

These attach to a camera and run continuous inference, emitting an annotated
stream and firing per-label callbacks. They use `@brick.execute` loops.

### `arduino:video_object_detection` — Video Object Detection
Source: `video_objectdetection/__init__.py`. Note the **id has underscores**:
`arduino:video_object_detection`. `required_devices: [camera]`,
`mount_devices_into_container: true`, `VIDEO_DEVICE=/dev/video1` default.
- **Import**: `from arduino.app_bricks.video_objectdetection import VideoObjectDetection`
- **Methods**: `on_detect(object: str, callback)` (fires when a **specific** label seen), `on_detect_all(callback: Callable[[dict], None])` (every detection event), `start()`, `stop()`, `override_threshold(value: float)`.

```python
from arduino.app_utils import App
from arduino.app_bricks.video_objectdetection import VideoObjectDetection
vod = VideoObjectDetection()
vod.on_detect("person", lambda: print("person!"))
App.run()
```
`app.yaml`: `bricks: [arduino:video_object_detection]`

### `arduino:video_image_classification` — Video Image Classification
Source: `video_imageclassification/__init__.py`. Id: `arduino:video_image_classification`.
- **Import**: `from arduino.app_bricks.video_imageclassification import VideoImageClassification`
- **Constructor**: `VideoImageClassification(camera=None, confidence=0.3, debounce_sec=0.0)`
- **Methods**: `on_detect(object, callback)`, `on_detect_all(callback)`, `start()`, `stop()`, `override_threshold(value)`.

### `arduino:gesture_recognition` — Gesture Recognition
Source: `gesture_recognition/__init__.py`. `ventunoq` only, `required_devices: [camera]`.
- **Import**: `from arduino.app_bricks.gesture_recognition import GestureRecognition`
- **Constructor**: `GestureRecognition(camera: BaseCamera | None = None, confidence: float = 0.0)`
- **Methods**: `on_gesture(gesture: str, callback, hand: "left"|"right"|"both" = "both")`, `on_enter(cb)`, `on_exit(cb)` (hand enters/leaves frame), `on_frame(cb)`, `start()`, `stop()`.

---

# AI — Audio

### `arduino:asr` — Automatic Speech Recognition (offline)
Source: `asr/local_asr.py`, `asr/local_asr_wav.py`. Model `whisper-small-quantized`, `requires_services: ["arduino:genie_audio"]` (QNN), `ventunoq` only.
- **Import**: `from arduino.app_bricks.asr import AutomaticSpeechRecognition, WAVAutomaticSpeechRecognition`
- **Mic transcription** (`AutomaticSpeechRecognition`): `start()`, `stop()`, `cancel()`, `transcribe(duration=60) -> str`, `transcribe_stream(duration=0) -> TranscriptionStream[ASREvent]`, `transcribe_sentence(timeout=0) -> str`, `transcribe_sentence_stream(...)`, `transcribe_until_cancelled()`.
- **File transcription** (`WAVAutomaticSpeechRecognition`): `transcribe() -> str`, `transcribe_stream()`.

```python
from arduino.app_bricks.asr import AutomaticSpeechRecognition
asr = AutomaticSpeechRecognition()
asr.start()
print(asr.transcribe(duration=5))
asr.stop()
```
`app.yaml`: `bricks: [arduino:asr]`

### `arduino:cloud_asr` — Cloud ASR
Source: `cloud_asr/cloud_asr.py`, `cloud_asr/providers/`. `required_devices: [microphone]`, vars `API_KEY`, `LANGUAGE`.
- **Import**: `from arduino.app_bricks.cloud_asr import CloudASR, CloudProvider`
- **Methods**: `start()`, `stop()`, `transcribe(duration=60.0) -> str`, `transcribe_stream(duration=60.0) -> Iterator[ASREvent]`.

### `arduino:tts` — Text-to-Speech (offline)
Source: `tts/local_tts.py`. Model `piper-tts-en`, `requires_services: ["arduino:genie_audio"]`, `ventunoq` only.
- **Import**: `from arduino.app_bricks.tts import TextToSpeech, SynthesisStream, TTSError, TTSBusyError`
- **Constructor**: `TextToSpeech(speaker: BaseSpeaker | None = None)`
- **Methods**: `start()`, `stop()`, `cancel()`, `speak(text)` (play through speaker), `synthesize_wav(text) -> bytes`, `synthesize_pcm(text) -> bytes`, `synthesize_pcm_stream(text) -> SynthesisStream`.

```python
from arduino.app_bricks.tts import TextToSpeech
tts = TextToSpeech(); tts.start(); tts.speak("Hello from the UNO Q"); tts.stop()
```
`app.yaml`: `bricks: [arduino:tts]`

### `arduino:audio_classification` — Audio Classification
Source: `audio_classification/__init__.py`. Edge Impulse, default `glass-breaking`. Subclasses `AudioDetector`.
- **Import**: `from arduino.app_bricks.audio_classification import AudioClassification`
- **Constructor**: `AudioClassification(mic: Microphone = None, confidence: float = 0.8)`
- **Methods**: `on_detect(class_name: str, callback)`, `start()`, `stop()`; static `AudioClassification.classify_from_file(audio_path, confidence=0.8) -> dict`.

### `arduino:keyword_spotting` — Keyword Spotting
Source: `keyword_spotting/__init__.py`. Edge Impulse, default `keyword-spotting-hey-arduino`. `required_devices: [microphone]`. Subclasses `AudioDetector`.
- **Import**: `from arduino.app_bricks.keyword_spotting import KeywordSpotting`
- **Constructor**: `KeywordSpotting(mic: BaseMicrophone | None = None, confidence: float = 0.8, debounce_sec: float = 2.0)`
- **Methods**: `on_detect(keyword: str, callback)`, `start()`, `stop()`.

```python
from arduino.app_utils import App
from arduino.app_bricks.keyword_spotting import KeywordSpotting
ks = KeywordSpotting()
ks.on_detect("hey arduino", lambda: print("wake word!"))
App.run()
```
`app.yaml`: `bricks: [arduino:keyword_spotting]`

---

# AI — Sensor (accelerometer)

Both subclass `EdgeImpulseRunnerFacade`, feed accelerometer samples, run an
`.eim` model. You push samples from the sketch via the Bridge.

### `arduino:motion_detection` — Motion Detection
Source: `motion_detection/__init__.py`. Default `updown-wave-motion-detection`.
- **Import**: `from arduino.app_bricks.motion_detection import MotionDetection`
- **Constructor**: `MotionDetection(confidence: float = 0.4)`
- **Methods**: `start()`, `stop()`, `on_movement_detection(movement: str, callback)`, `accumulate_samples(accelerometer_samples: Tuple[float,float,float])`, `get_sensor_samples()`.

### `arduino:vibration_anomaly_detection` — Vibration Anomaly Detection
Source: `vibration_anomaly_detection/__init__.py`. Default `fan-anomaly-detection`.
- **Import**: `from arduino.app_bricks.vibration_anomaly_detection import VibrationAnomalyDetection`
- **Constructor**: `VibrationAnomalyDetection(anomaly_detection_threshold: float = 1.0)`
- **Methods**: `start()`, `stop()`, `loop()` (non-blocking step, call periodically), `accumulate_samples(sensor_samples: Iterable[float])`, `on_anomaly(callback)`; `anomaly_detection_threshold` property is read/write at runtime.

---

# Sound synthesis

### `arduino:sound_generator` — Sound Generator
Source: `sound_generator/__init__.py` (+ `generator.py`, `effects.py`, `loaders.py`, `composition.py`). `required_devices: [speaker]`.
- **Import**: `from arduino.app_bricks.sound_generator import SoundGenerator, MusicComposition, ABCNotationLoader, SoundEffect`
- **Purpose**: synthesize notes, chords, tones, ABC-notation melodies, polyphony, and apply effects (overdrive, chorus, ADSR, tremolo, vibrato, bitcrusher, octaver).
- **Key methods**: `start()`, `stop()`, `play(note, note_duration=1/4, volume=None, block=False)`, `play_tone(note, duration=0.25, ...)`, `play_chord(notes, ...)`, `play_polyphonic(notes, as_tone=False, ...)`, `play_abc(abc_string, ...)`, `play_wav(wav_file, ...)`, `play_composition(...)`, `play_step_sequence(...)`, `set_master_volume(v)`, `set_bpm(bpm)`, `set_effects(list)`, `set_wave_form(name)`, `stop_sequence()`, `is_sequence_playing()`.

```python
from arduino.app_utils import App
from arduino.app_bricks.sound_generator import SoundGenerator
sg = SoundGenerator(); sg.start()
sg.play_abc("C D E F G", block=True)
App.run()
```
`app.yaml`: `bricks: [arduino:sound_generator]` (+ speaker device).

### `arduino:wave_generator` — Wave Generator
Source: `wave_generator/wave_generator.py`. `required_devices: [speaker]`. Continuous synth (sine/square/saw/triangle) with smooth glide — built for theremin-style control.
- **Import**: `from arduino.app_bricks.wave_generator import WaveGenerator`
- **Methods/props**: `start()`, `stop()`; properties `wave_type`, `frequency`, `amplitude`, `attack`, `release`, `glide`, `volume`, `sample_rate` (read), `block_duration` (read), `state` (read). Set frequency/amplitude live to bend the tone.

---

# UI

### `arduino:web_ui` — WebUI (HTML)
Source: `web_ui/web_ui.py`. Deep guide: `web-ui-brick.md`. `category: ui`, `requires_display: webview`, port `7000`.
- **Import**: `from arduino.app_bricks.web_ui import WebUI`
- **Purpose**: FastAPI + Uvicorn + Socket.IO server. Serves static `assets/`, REST APIs, and a bidirectional WebSocket. `assets/index.html` is **required** or `start()` raises.
- **Constructor**: `WebUI(addr="0.0.0.0", port=7000, ui_path_prefix="", api_path_prefix="", assets_dir_path="/app/assets", certs_dir_path="/app/certs", use_tls=False, cors_origins="*")`
- **Methods**: `expose_api(method, path, function)`, `on_message(message_type, cb(sid, data))` (returning a value emits `<type>_response` to that sid), `send_message(message_type, message, room=None)`, `on_connect(cb)`, `on_disconnect(cb)`, `expose_camera(path, camera, jpeg_quality=80)` (MJPEG); properties `local_url`, `url`.

```python
from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI
ui = WebUI()
ui.on_message("ping", lambda sid, data: {"pong": True})
App.run()
```
`app.yaml`: `bricks: [arduino:web_ui]`

### `arduino:streamlit_ui` — WebUI (Streamlit)
Source: `streamlit_ui/__init__.py`, `streamlit_ui/addons.py`. `category: ui`, `requires_display: webview`, port `7000`.
- **Import**: `from arduino.app_bricks.streamlit_ui import st` (re-exported Streamlit) and `from arduino.app_bricks.streamlit_ui.addons import arduino_header`
- **Purpose**: build a Python-only dashboard with Streamlit; `arduino_header(title)` adds the Arduino-branded header.
- `app.yaml`: `bricks: [arduino:streamlit_ui]`. **(Method surface beyond `arduino_header` is plain Streamlit — see Streamlit docs; brick-specific glue beyond the re-export is unverified.)**

---

# Data / Database

### `arduino:dbstorage_sqlstore` — Database (SQL / SQLite)
Source: `dbstorage_sqlstore/__init__.py`. `category: storage`, `requires_container: false` (local SQLite file).
- **Import**: `from arduino.app_bricks.dbstorage_sqlstore import SQLStore`
- **Constructor**: `SQLStore(database_name: str = "arduino.db")`
- **Methods**: `start()`, `stop()`, `create_table(table, columns: dict[str,str])`, `drop_table(table)`, `create_or_replace_table(table, columns, force_drop_table=False)`, `store(table, data: dict, create_table=True)`, `read(...)`, `update(table, data, condition="")`, `delete(table, condition="")`, `execute_sql(sql, args=None) -> list[dict] | None`.

```python
from arduino.app_bricks.dbstorage_sqlstore import SQLStore
db = SQLStore("sensors.db"); db.start()
db.store("temp", {"value": 21.5, "ts": 1716000000})
rows = db.execute_sql("SELECT * FROM temp")
```
`app.yaml`: `bricks: [arduino:dbstorage_sqlstore]`

### `arduino:dbstorage_tsstore` — Database (Time Series / InfluxDB)
Source: `dbstorage_tsstore/__init__.py`. `category: storage`, `requires_container: true` (spins up InfluxDB via Compose). Vars: `DB_USERNAME`, `DB_PASSWORD`, `INFLUXDB_ADMIN_TOKEN`, `BIND_ADDRESS` (all defaulted; secrets).
- **Import**: `from arduino.app_bricks.dbstorage_tsstore import TimeSeriesStore`
- **Constructor**: `TimeSeriesStore(host=<default>, port=<default>, retention_days: int = 7)`
- **Methods**: `start()`, `stop()`, `write_sample(measure, value, ts=0, measurement_name="arduino")`, `read_last_sample(measure, measurement_name="arduino", start_from="-1d") -> tuple | None`, `read_samples(...)`, `get_client() -> InfluxDBClient`.

```python
from arduino.app_bricks.dbstorage_tsstore import TimeSeriesStore
ts = TimeSeriesStore(retention_days=30); ts.start()
ts.write_sample("temperature", 21.5)
print(ts.read_last_sample("temperature"))
```
`app.yaml`: `bricks: [arduino:dbstorage_tsstore]`

---

# Comms / Cloud

### `arduino:mqtt` — MQTT Connector
Source: `mqtt/__init__.py`. **Note `disabled: true` in `brick_config.yaml`** — not exposed by default in the App Lab brick list; usable directly but confirm availability.
- **Import**: `from arduino.app_bricks.mqtt import MQTT`
- **Methods**: `start()`, `stop()`, `publish(topic, message: str | dict)`, `subscribe(topic)`, `on_message(topic, fn(client, userdata, msg))`.

```python
from arduino.app_bricks.mqtt import MQTT
m = MQTT(...); m.start()
m.on_message("sensors/#", lambda c, u, msg: print(msg.payload))
m.subscribe("sensors/#")
m.publish("sensors/temp", {"value": 21.5})
```
`app.yaml`: `bricks: [arduino:mqtt]` (verify it's enabled).

### `arduino:telegram_bot` — Telegram Bot
Source: `telegram_bot/telegram_bot.py`. Var `TELEGRAM_BOT_TOKEN` (secret).
- **Import**: `from arduino.app_bricks.telegram_bot import TelegramBot, Sender, Message`
- **Methods**: `start()`, `stop()`, `add_command(command, callback(sender, message), description="")`, `on_text(cb)`, `on_photo(cb)`, `on_audio(cb)`, `on_video(cb)`, `on_document(cb)`, `send_message(chat_id, text)`, `send_photo/audio/video/document(...)`, `schedule_message(...)`, `cancel_scheduled_message(task_id)`. `Sender` offers `reply()`, `reply_photo()`, `reply_audio()`, `reply_video()`, `reply_document()`.

```python
from arduino.app_utils import App
from arduino.app_bricks.telegram_bot import TelegramBot
bot = TelegramBot()
bot.on_text(lambda sender, msg: sender.reply(f"You said: {msg}"))
bot.start()
App.run()
```
`app.yaml`: `bricks: [arduino:telegram_bot]` + `TELEGRAM_BOT_TOKEN`.

### `arduino:arduino_cloud` — Arduino Cloud
Source: `arduino_cloud/arduino_cloud.py`. Vars `ARDUINO_DEVICE_ID`, `ARDUINO_SECRET` (secrets). Exports `ArduinoCloud, Location, Color, ColoredLight, DimmedLight, Schedule`.
- **Import**: `from arduino.app_bricks.arduino_cloud import ArduinoCloud, ColoredLight, Color`
- **Methods**: `start()`, `loop()`, `register(aiotobj, **kwargs)`. Cloud variables are accessed as natural attributes (custom `__getattr__`/`__setattr__`): assign `cloud.my_var = value` to push, read `cloud.my_var` to get.

```python
from arduino.app_utils import App
from arduino.app_bricks.arduino_cloud import ArduinoCloud
cloud = ArduinoCloud()
cloud.register("temperature", value=0.0)
cloud.temperature = 21.5
App.run()
```
`app.yaml`: `bricks: [arduino:arduino_cloud]` + device id/secret.

---

# Web data services (require internet)

### `arduino:weather_forecast` — Weather Forecast
Source: `weather_forecast/__init__.py`. Uses open-meteo.com. `category: miscellaneous`.
- **Import**: `from arduino.app_bricks.weather_forecast import WeatherForecast, WeatherData`
- **Constructor**: `WeatherForecast()`
- **Methods**: `get_forecast_by_city(city, timezone="GMT", forecast_days=1) -> WeatherData`, `get_forecast_by_coords(latitude, longitude, timezone="GMT", forecast_days=1) -> WeatherData`, `process(item)`.

```python
from arduino.app_bricks.weather_forecast import WeatherForecast
wx = WeatherForecast().get_forecast_by_city("Bangkok")
```
`app.yaml`: `bricks: [arduino:weather_forecast]`

### `arduino:air_quality_monitoring` — Air Quality Monitoring
Source: `air_quality_monitoring/__init__.py`. Uses aqicn.org (token required). `category: miscellaneous`.
- **Import**: `from arduino.app_bricks.air_quality_monitoring import AirQualityMonitoring, AirQualityData`
- **Constructor**: `AirQualityMonitoring(token: str)`
- **Methods**: `get_air_quality_by_city(city) -> AirQualityData`, `get_air_quality_by_coords(latitude, longitude) -> AirQualityData`, `get_air_quality_by_ip() -> AirQualityData`, `process(item)`.

```python
from arduino.app_bricks.air_quality_monitoring import AirQualityMonitoring
aq = AirQualityMonitoring(token="YOUR_AQICN_TOKEN").get_air_quality_by_city("Bangkok")
```
`app.yaml`: `bricks: [arduino:air_quality_monitoring]`

---

# Peripherals (not Bricks — no `app.yaml` entry)

Peripherals live under `arduino.app_peripherals` and are consumed *by* Bricks
(e.g. a `Camera` passed to a video brick) or used directly. They need no
`bricks:` entry; just import. Source: `src/arduino/app_peripherals/`.

### Camera — `arduino.app_peripherals.camera`
`from arduino.app_peripherals.camera import Camera`. `Camera` is a factory
(`__new__`) returning the right backend (USB/V4L, CSI, IP/RTSP/HLS, WebSocket).
- **Constructor**: `Camera(source="0|usb:0|csi:0|rtsp://...|ws://...", resolution=(640,480), fps=10, adjustments=None, **kwargs)`
- Backends exported: `V4LCamera`, `CSICamera`, `IPCamera`, `WebSocketCamera`; base `BaseCamera` (`start()`, `stop()`, `capture()`, `is_started`).

### Microphone — `arduino.app_peripherals.microphone`
`from arduino.app_peripherals.microphone import Microphone`. Static recorders:
- `Microphone.record_pcm(duration, sample_rate, channels, format, device=USB_MIC_1) -> np.ndarray`
- `Microphone.record_wav(duration, sample_rate, channels, format, device=USB_MIC_1) -> np.ndarray`
- Format helpers: `FormatPlain`, `FormatPacked`. Backends: `ALSAMicrophone`, `WebSocketMicrophone`.

### Speaker — `arduino.app_peripherals.speaker`
`from arduino.app_peripherals.speaker import Speaker`. Static players:
- `Speaker.play_pcm(...)`, `Speaker.play_wav(wav_audio: np.ndarray, device=USB_SPEAKER_1)`
- Backends: `ALSASpeaker`; formats `FormatPlain`, `FormatPacked`.

### App utilities — `arduino.app_utils`
`App`, `brick`, `Bridge` (MCU RPC: `Bridge.call`, `Bridge.provide`, `Bridge.notify`),
`Logger`, `JSONParser`, `HttpClient`, `FolderWatcher`, `SlidingWindowBuffer`,
`Leds`, `SineGenerator`, `FrameDesigner`/`Frame` (LED matrix).
Source: `src/arduino/app_utils/__init__.py`.

---

## Quick reference: import path ↔ app.yaml id

| `app.yaml` id | Import |
| --- | --- |
| `arduino:llm` | `arduino.app_bricks.llm.LargeLanguageModel` |
| `arduino:cloud_llm` | `arduino.app_bricks.cloud_llm.CloudLLM` |
| `arduino:vlm` | `arduino.app_bricks.vlm.VisionLanguageModel` |
| `arduino:mood_detector` | `arduino.app_bricks.mood_detector.MoodDetector` |
| `arduino:object_detection` | `arduino.app_bricks.object_detection.ObjectDetection` |
| `arduino:image_classification` | `arduino.app_bricks.image_classification.ImageClassification` |
| `arduino:visual_anomaly_detection` | `arduino.app_bricks.visual_anomaly_detection.VisualAnomalyDetection` |
| `arduino:camera_code_detection` | `arduino.app_bricks.camera_code_detection.CameraCodeDetection` |
| `arduino:video_object_detection` | `arduino.app_bricks.video_objectdetection.VideoObjectDetection` |
| `arduino:video_image_classification` | `arduino.app_bricks.video_imageclassification.VideoImageClassification` |
| `arduino:gesture_recognition` | `arduino.app_bricks.gesture_recognition.GestureRecognition` |
| `arduino:asr` | `arduino.app_bricks.asr.AutomaticSpeechRecognition` |
| `arduino:cloud_asr` | `arduino.app_bricks.cloud_asr.CloudASR` |
| `arduino:tts` | `arduino.app_bricks.tts.TextToSpeech` |
| `arduino:audio_classification` | `arduino.app_bricks.audio_classification.AudioClassification` |
| `arduino:keyword_spotting` | `arduino.app_bricks.keyword_spotting.KeywordSpotting` |
| `arduino:motion_detection` | `arduino.app_bricks.motion_detection.MotionDetection` |
| `arduino:vibration_anomaly_detection` | `arduino.app_bricks.vibration_anomaly_detection.VibrationAnomalyDetection` |
| `arduino:sound_generator` | `arduino.app_bricks.sound_generator.SoundGenerator` |
| `arduino:wave_generator` | `arduino.app_bricks.wave_generator.WaveGenerator` |
| `arduino:web_ui` | `arduino.app_bricks.web_ui.WebUI` |
| `arduino:streamlit_ui` | `arduino.app_bricks.streamlit_ui.st` |
| `arduino:dbstorage_sqlstore` | `arduino.app_bricks.dbstorage_sqlstore.SQLStore` |
| `arduino:dbstorage_tsstore` | `arduino.app_bricks.dbstorage_tsstore.TimeSeriesStore` |
| `arduino:mqtt` | `arduino.app_bricks.mqtt.MQTT` |
| `arduino:telegram_bot` | `arduino.app_bricks.telegram_bot.TelegramBot` |
| `arduino:arduino_cloud` | `arduino.app_bricks.arduino_cloud.ArduinoCloud` |
| `arduino:weather_forecast` | `arduino.app_bricks.weather_forecast.WeatherForecast` |
| `arduino:air_quality_monitoring` | `arduino.app_bricks.air_quality_monitoring.AirQualityMonitoring` |
