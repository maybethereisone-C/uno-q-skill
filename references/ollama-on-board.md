# Ollama on the UNO Q (local LLM runtime + Claude Code on-board)

A second way to run a local LLM on the board, **alongside** the App Lab `llm` Brick (see `on-device-llm.md`). Ollama is a standalone, model-agnostic runtime — better when you want to pick your own GGUF model (e.g. a function-calling-tuned SLM) or run **Claude Code itself on the board**, 100% offline.

Source: AndreaRichetta, "Build Smarter with Claude Code & Ollama on UNO Q" (projecthub.arduino.cc, Apr 2026). Verified by rendering the page; the exact Ollama download URL is behind the project's "full script" and is marked unverified below.

## When to use which

| | App Lab `llm` Brick | Ollama |
|---|---|---|
| Integration | inside an App, Python `LargeLanguageModel` API, wired to Bricks/WebUI | standalone daemon, HTTP API on `localhost:11434` |
| Model choice | App Lab-managed | any GGUF you pull (`ollama pull/run <model>`) |
| Best for | product features inside an App | custom/function-calling models, running Claude Code on-board, quick experiments |
| Call from Python | `from arduino.app_bricks.llm import LargeLanguageModel` | HTTP (`POST /api/chat`) or the `ollama` Python client |

You can use **both**: Ollama to host a function-calling SLM, called from your App's `python/main.py` over the local HTTP API; the `llm` Brick when you want the integrated path.

## Requirements

- UNO Q **4 GB** variant (QRB2210, ARM64, Debian). CPU inference — no GPU.
- Ollama **v0.21.0+** (per the project).

## Install Ollama

```sh
# 1. Download the Ollama ARM64 (linux-arm64) build to the board.
#    (unverified exact URL — get the current linux-arm64 release archive,
#     e.g. ollama-linux-arm64.tgz/.tar.zst, into /home/arduino/)
#    The project used: /home/arduino/ollama.tar.zst

# 2. Extract it into place (per the project's full script).

# 3. Register + start the systemd service:
sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama

# 4. Verify (no errors = good):
ollama --version

# 5. Free space — remove the archive:
rm /home/arduino/ollama.tar.zst
```

(unverified) The exact download URL and extract command are in the project's "full bash code" block — fetch the current Ollama `linux-arm64` release rather than hard-coding a version.

## Pull & run a model

```sh
ollama run llama3.2:3b      # the project's choice, ~2 GB
```

### Model choice — IMPORTANT

`llama3.2:3b` is a **generic** 3B model. For this skill's main use case — **natural language → structured app action** (e.g. "I ate a hamburger at 9am" → a logged meal) — generic small Llamas are **weak at function-calling**. Prefer a **function-calling-tuned GGUF** at **Q4_K_M** (the reliability floor), e.g. a Qwen 3–4B or Hammer/xLAM-class function-calling model. Benchmark 2–3 on the real board for accuracy + latency + RAM. See `on-device-llm.md` (function-calling guidance) and `rules/resource-limits.md` (RAM budget — keep a ~3B Q4 ≈ 2 GB; don't run vision + LLM simultaneously).

## Run Claude Code ON the board (offline dev assistant)

```sh
ollama launch claude        # then select your model (e.g. llama3.2:3b)
```

You get the Claude Code CLI running on the UNO Q, backed by the local model — no cloud, no API cost. Pick a theme, trust the folder, go.

If the `claude` binary isn't found, re-link it and fix PATH:

```sh
rm /home/arduino/.local/bin/claude
ln -s /home/arduino/.local/share/claude/versions/<VERSION> /home/arduino/.local/bin/claude   # project used 2.1.117
chmod +x /home/arduino/.local/bin/claude
echo 'export PATH="/home/arduino/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
ollama launch claude
```

## Caveats

- **CPU inference is slow**, especially the first prompts (model load). Smaller / quantized models respond faster.
- **Respect the 4 GB budget** — see `rules/resource-limits.md`. Sequence Ollama with camera/vision; don't run both large models at once.
- This is a local *coding/runtime* assistant. For the shipped product's pet personality + deep conversation, the cloud-LLM path (see `on-device-llm.md`) remains the option when on-device quality isn't enough.
