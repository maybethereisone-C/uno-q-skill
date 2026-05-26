# On-Device LLM Brick — Deep Guide

The **LLM Brick** runs a large language model **locally on the UNO Q** (no
cloud, no API key to a third party) through the on-board **Genie** model runner.
There is also a **Cloud LLM** sibling with an identical API for hosted models.

> **See also `references/ollama-on-board.md`** — running a local model via **Ollama**
> (model-agnostic runtime, good for a function-calling-tuned SLM, and for running
> Claude Code on the board). The `llm` Brick = integrated App path; Ollama = flexible
> standalone runtime. For natural-language→action (meal logging etc.), pick a
> **function-calling-tuned** model, not generic `llama3.2:3b`.

Sources (verified):
- `app-bricks-py/src/arduino/app_bricks/llm/local_llm.py` — `LargeLanguageModel`
- `app-bricks-py/src/arduino/app_bricks/llm/__init__.py`
- `app-bricks-py/src/arduino/app_bricks/llm/brick_config.yaml`
- `app-bricks-py/src/arduino/app_bricks/cloud_llm/cloud_llm.py` — `CloudLLM` (the parent)
- `app-bricks-py/src/arduino/app_bricks/cloud_llm/models.py`, `.../memory.py`
- Example: `app-bricks-examples/examples/edge-ai-assistant/`

---

## 1. Architecture

`LargeLanguageModel` **subclasses `CloudLLM`**. Almost all behavior lives in
`CloudLLM`; the local class just rewrites the connection so it points at the
local Genie runner instead of a cloud provider.

- Genie exposes an **OpenAI-compatible** HTTP API. The local class forces the
  OpenAI provider and points `base_url` at `http://genie-models-runner:9001/v1`
  (host `genie-models-runner`, port `9001`).
- `brick_config.yaml`: `requires_services: ["arduino:genie"]`,
  `requires_model: true`, default `model: genie:qwen3_4b_instruct_2507`,
  `supported_boards: ["ventunoq"]`, framework `genie`.
- Under the hood it's LangChain (`ChatOpenAI`) → the response is plain text;
  any `<think>...</think>` reasoning block is stripped automatically (both in
  `chat` and `chat_stream`).

Declare it in `app.yaml`:
```yaml
bricks:
  - arduino:llm
```

---

## 2. Constructor

```python
LargeLanguageModel(
    api_key: str = os.getenv("LOCAL_LLM_API_KEY", "api_key"),
    system_prompt: str = "",
    temperature: Optional[float] = 0.7,
    max_tokens: int = 512,
    timeout: Optional[int] = None,
    tools: List[Callable[..., Any]] = None,
    model: str = None,            # e.g. "genie:qwen3-4b"; None => resolve from config
    **kwargs,                     # forwarded to the model; e.g. base_url override
)
```

Model resolution order when `model=None`:
1. App-level configured model (App Lab / app config), then
2. the brick's default (`genie:qwen3_4b_instruct_2507`).

A `genie:`/`llamacpp:`/`ollama:` prefix is parsed; only `genie:` is wired today
(the llamacpp/ollama branches are commented out in source). On init the brick
calls `list_models()` and logs an error if your model isn't present locally —
download/configure it first.

```python
from arduino.app_bricks.llm import LargeLanguageModel

llm = LargeLanguageModel(
    system_prompt="You are a concise home-automation assistant.",
    temperature=0.3,
    max_tokens=256,
)
```

---

## 3. Full public API

| Method | Signature | Notes |
| --- | --- | --- |
| `chat` | `(message: str, images: List[str\|bytes]=None) -> str` | Blocking one-shot. Manages history if memory on. |
| `chat_stream` | `(message: str, images: List[str\|bytes]=None) -> Iterator[str]` | Yields token chunks; stoppable. Raises `AlreadyGenerating` if a stream is active. |
| `stop_stream` | `() -> None` | Sets a flag; the `chat_stream` iterator breaks early. Safe no-op if idle. |
| `with_memory` | `(max_messages: int = 10) -> self` | Windowed history of the last N messages. `0` disables. Chainable. |
| `clear_memory` | `() -> None` | Wipes history (keeps the system prompt). |
| `list_models` | `() -> List[str]` | Queries the local Genie server for available model ids. |
| `get_client` | `() -> BaseChatModel` | The underlying LangChain model for advanced use. |

`images` accepts file paths **or** raw `bytes`; each is base64-encoded as a
`data:image/jpeg` URL. (Image input only makes sense with a vision model — for
that, use the **VLM Brick**, `arduino.app_bricks.vlm.VisionLanguageModel`,
default `genie:qwen3-vl-4b`.)

---

## 4. Streaming pattern

```python
from arduino.app_bricks.llm import LargeLanguageModel

llm = LargeLanguageModel(system_prompt="Answer briefly.")
for token in llm.chat_stream("Name three sensors I can attach to the UNO Q"):
    print(token, end="", flush=True)
```

Only one stream may run at a time per instance. Starting a second while one is
active raises `AlreadyGenerating`. To interrupt from another thread (e.g. a UI
"stop" button), call `llm.stop_stream()`. Partial output already streamed is
still committed to memory.

---

## 5. Conversational memory

```python
llm = LargeLanguageModel(system_prompt="You are a tutor.").with_memory(20)
llm.chat("My name is Tew.")
llm.chat("What is my name?")   # -> remembers "Tew"
llm.clear_memory()             # start a fresh topic; system prompt preserved
```

Memory is a **windowed** history (`WindowedChatMessageHistory`, keeps the last
`k` messages plus the system message). The base `CloudLLM` enables memory with
`DEFAULT_MEMORY = 10` in its constructor; call `with_memory(n)` to resize or
`with_memory(0)` to disable. (The **VLM** subclass defaults memory to `0`.)

---

## 6. System prompts

`system_prompt` is set once at construction and stored in the history object, so
it is prepended on every turn (and survives `clear_memory()`). Re-instantiate
or call `with_memory(...)` again to change it. The edge-ai-assistant example
loads it from a separate `prompts.py` (`load_system_prompt()`), which keeps long
prompts out of `main.py` — a good pattern.

---

## 7. Function calling / structured output → turning language into actions

`CloudLLM` (and therefore the local LLM) supports **tool calling** via LangChain
`@tool` functions passed as `tools=[...]`. The brick binds them to the model,
and `_chat_invoke` / `_chat_stream_invoke` loop: if the model emits tool calls,
the brick invokes the matching Python function, feeds the result back, and
continues — bounded by `max_tool_loops` (default `8`) to prevent runaway loops.

```python
from arduino.app_bricks.llm import LargeLanguageModel, tool   # `tool` re-exported
from arduino.app_utils import Bridge

@tool
def set_led(on: bool) -> str:
    """Turn the board LED on or off."""
    Bridge.call("set_led_state", on)     # RPC to the sketch
    return f"LED is now {'on' if on else 'off'}"

@tool
def read_temperature() -> str:
    """Return the latest temperature reading in Celsius."""
    return f"{Bridge.call('get_temp'):.1f}"

llm = LargeLanguageModel(
    system_prompt="You control a board. Use tools to act, then confirm briefly.",
    tools=[set_led, read_temperature],
)
print(llm.chat("It's dark in here"))      # model calls set_led(on=True), then replies
```

Notes:
- `max_tool_loops` is a `CloudLLM.__init__` arg; `LargeLanguageModel.__init__`
  doesn't expose it directly but forwards `**kwargs` to the parent, so you can
  pass `max_tool_loops=...`.
- For **structured JSON output** without tools, instruct the format in the
  system prompt and parse with `arduino.app_utils.JSONParser`, or use
  `llm.get_client()` to access LangChain's `with_structured_output(...)`
  directly. **(Exact structured-output helper on the brick is not exposed; use
  `get_client()` — unverified beyond the LangChain passthrough.)**

---

## 8. Model & RAM constraints on the 4 GB board

- The UNO Q ships **4 GB RAM** (cross-ref `resource-limits` reference). The
  default local model is a **4B** quantized model (`qwen3_4b_instruct_2507`).
- The brick maps HTTP **503** from the runner to a `RuntimeError` whose message
  says *"Cannot load model due to a potential memory exhaustion"*
  (`_handle_api_error`). If you hit this: pick a smaller/more-quantized model,
  reduce `max_tokens`, shrink the memory window, and avoid running other heavy
  Bricks (vision/video model runners) at the same time.
- Genie loads the model lazily on first use; the first token after load is slow.
- `requires_services: ["arduino:genie"]` and `requires_container: true`
  semantics mean a model-runner container must be up — App Lab provisions it
  when the brick is declared. `ventunoq` only.

Error handling to catch:
```python
try:
    reply = llm.chat("...")
except RuntimeError as e:
    # 503 -> memory exhaustion; 400 -> bad request; others -> API error
    ui.send_message("llm_error", {"error": str(e)})
```

---

## 9. Local vs Cloud — same API, different transport

| | `arduino:llm` (local) | `arduino:cloud_llm` (cloud) |
| --- | --- | --- |
| Import | `arduino.app_bricks.llm.LargeLanguageModel` | `arduino.app_bricks.cloud_llm.CloudLLM` |
| Runs on | On-device Genie runner | Anthropic / OpenAI / Google |
| Credentials | none (local) | `API_KEY` env var (`secret: true`) — **required** |
| Default model | `genie:qwen3_4b_instruct_2507` | `claude-sonnet-4-6` (`CloudModel.ANTHROPIC_CLAUDE`) |
| Model select | `model="genie:..."` | `model=CloudModel.X` or `"openai:..."`/`"anthropic:..."`/`"google:..."` |
| Board | `ventunoq` only | any (needs internet) |
| Methods | `chat`, `chat_stream`, `stop_stream`, `with_memory`, `clear_memory`, `list_models`, `get_client` | same minus `list_models` |

`CloudModel` enum (`models.py`): `ANTHROPIC_CLAUDE="claude-sonnet-4-6"`,
`OPENAI_GPT="gpt-5.4-mini"`, `GOOGLE_GEMINI="gemini-2.5-flash"`. No prefix =>
treated as OpenAI-compatible.

Cloud example:
```python
from arduino.app_bricks.cloud_llm import CloudLLM, CloudModel
llm = CloudLLM(model=CloudModel.ANTHROPIC_CLAUDE, system_prompt="Be helpful.")
print(llm.chat("Hello"))   # reads API_KEY from env
```

---

## 10. Complete working example — local chatbot with a Web UI

This is the verified `edge-ai-assistant` shape: `arduino:llm` + `arduino:web_ui`.

`app.yaml`:
```yaml
name: Edge AI Assistant
icon: 💬
description: Chatbot powered by a local LLM
bricks:
  - arduino:web_ui
  - arduino:llm
```

`python/main.py`:
```python
from arduino.app_bricks.llm import LargeLanguageModel
from arduino.app_bricks.web_ui import WebUI
from arduino.app_utils import App

def generate_prompt(_sid, data):
    try:
        for resp in llm.chat_stream(data.get("prompt", "")):
            ui.send_message("response", resp)      # stream token to browser
        ui.send_message("stream_end", {})
    except Exception as e:
        ui.send_message("llm_error", {"error": str(e)})

def commands_handler(_sid, data):
    command = data.get("command", "")
    if command == "clear_chat":
        llm.stop_stream(); llm.clear_memory()
        ui.send_message("command_ok", {"command": command})
    elif command == "stop_stream":
        llm.stop_stream()
        ui.send_message("command_ok", {"command": command})
    else:
        ui.send_message("command_error", {"command": command, "error": "Unknown command"})

llm = LargeLanguageModel(system_prompt="You are a helpful assistant.")
llm.with_memory(20)

ui = WebUI()
ui.on_message("prompt", generate_prompt)
ui.on_message("commands", commands_handler)

App.run()
```

The browser sends a `prompt` Socket.IO event; Python streams `response` events
back token-by-token and a final `stream_end`. A `commands` event drives
stop/clear. See `web-ui-brick.md` for the `assets/` frontend wiring.
