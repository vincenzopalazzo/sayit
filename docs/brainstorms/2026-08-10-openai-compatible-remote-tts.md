# Clarified Problem Statement

**Goal:** Let users opt into an Advanced mode that sends synthesis to an OpenAI-compatible TTS HTTP endpoint on another machine (e.g. NVIDIA Spark / any GPU PC), while the Mac app keeps selection, playback, history, and UI local.

**Context (repo + user):**
- Today synthesis is MLX-only via `SynthesisActor` (`BackendSpeechSynthesizing` / `SpeechSynthesizing`) constructed in `SayItBackendService`.
- Optional HTTP API is **server-side and loopback-only** (`SayItHTTP` → `127.0.0.1`); it is not a remote client.
- Product promise (`README` / `SECURITY.md`): local-by-default, no cloud inference unless the user clearly opts in.
- User Spark host (personal reference only, not hardcoded): `vincenzo@spark-8c33.tail48e96f.ts.net` over Tailscale; recent workload there is LLM chat (`:8000`), not TTS. Feature should be **generic OpenAI-compatible**, not Spark-specific SSH.

**Constraints:**
- Default remains fully local MLX; remote is explicit opt-in.
- UI must make privacy leave-local obvious (text leaves the Mac).
- Playback, hotkeys, history, and menu-bar player stay on the Mac.
- Auth via bearer token (and optionally custom headers); base URL configurable.
- Compatible with common OpenAI-style TTS APIs (`POST /v1/audio/speech` with `model`, `voice`, `input`, audio bytes back)—exact dialect may vary; document assumptions.
- No credentials in git; store secrets in Keychain (or equivalent), not plain `Backend Settings.json` if possible.
- Do not break XPC app/CLI path or existing loopback automation API.
- Apple silicon still required for local mode; remote mode should work even when local MLX models are absent (or degrade gracefully).

**Non-goals:**
- SSH host management, deploy scripts, or bundling a TTS stack for Spark.
- Replacing the loopback Say It HTTP API with a remote-bind server.
- Full remote control of playback/history on the PC (Mac remains the client).
- Cloud SaaS vendor lock-in or multi-provider marketplace in v1.
- Voice cloning / Voice Studio over the remote endpoint in v1 (unless the endpoint happens to accept a simple voice id).
- Changing the “local by design” default messaging for users who never enable Advanced.

**Success criteria:**
- User can enable Advanced → set base URL + API key + model/voice ids → speak selection/clipboard and hear audio in the existing player.
- Failure modes are clear: unreachable host, 401, unsupported format, timeout.
- Local mode unchanged when Advanced remote is off.
- Basic test coverage for request shaping + response decode (fixture-based, no live network).
- Settings copy states that text is sent to the configured endpoint.

## Approaches Considered

### Approach A: Remote synthesizer backend (recommended)
- **Sketch:** Implement `OpenAICompatibleSpeechSynthesizer: BackendSpeechSynthesizing` that maps `SpeechRequest` → `POST {baseURL}/v1/audio/speech`, decodes audio (mp3/wav/pcm) into `AudioChunk` / `SynthesisEvent` stream. `SayItBackendService` picks local `SynthesisActor` vs remote impl from settings. Add an **Advanced** settings pane (or section under Service): enable toggle, base URL, API key, model id, voice id, timeout, optional path prefix.
- **Affected files:** `Sources/SayItBackend/Synthesis/` (new client), `SayItBackendService.swift` (wiring), `BackendSettingsSnapshot.swift` + `BackendSettingsStore.swift`, `Sources/SayIt/Settings/` (`SettingsRootView`, new `AdvancedSettingsView` or extend `ServiceSettingsView`), Keychain helper if needed, tests under `Tests/SayItBackendTests/`.
- **Tradeoffs:** Gains a clean seam at the existing protocol; keeps playback/history local; works with any OpenAI-compatible TTS on a home PC. Costs: audio format conversion, less feature parity (no MLX voice clone/tuning), need careful secret storage. Does not solve discovering models on the remote automatically (manual model/voice strings in v1).
- **Effort:** M

### Approach B: Remote as a catalog “network model”
- **Sketch:** Add a special model type/provider in the model catalog (`ModelDescriptor` / install flow) representing a remote endpoint. Choosing that model routes synthesis to the HTTP client; settings hang off the model row.
- **Affected files:** model catalog + `ModelsSettingsView`, `ModelDescriptor`, download/install paths, `SynthesisActor` / service routing, protocol snapshots.
- **Tradeoffs:** Feels native in Models UI; but stretches “model = local MLX weights” abstraction, complicates install/unload/disk estimates, and couples networking to catalog. Harder to explain vs a simple Advanced backend switch.
- **Effort:** L

### Approach C: Thin client to a full remote Say It stack
- **Sketch:** Run Say It backend/API on the other machine and point the Mac app at that remote service (extend beyond `127.0.0.1`, tunnel or bind on Tailscale).
- **Affected files:** `SayItHTTP` bind/auth, app XPC assumptions, service discovery, security model, possibly replace local backend.
- **Tradeoffs:** Maximum reuse of Say It semantics, but requires Say It (and Apple/MLX) on the remote—or a full reimplementation. Contradicts “normal PC / NVIDIA Spark” CUDA world. Largest security and architecture blast radius.
- **Effort:** L

## Recommendation

**Approach A.** The user wants OpenAI-compatible endpoints for ordinary PCs, not Spark-specific deploy or a second Say It instance. A second `BackendSpeechSynthesizing` implementation plus opt-in Advanced settings is the smallest seam that preserves local-by-default, Mac-side playback, and generic GPU-box compatibility.

Suggested v1 shape:
- Settings: `remoteTTSEnabled`, `remoteTTSBaseURL`, `remoteTTSModel`, `remoteTTSVoice`, timeout; API key in Keychain.
- Client: OpenAI `audio/speech` request; accept `mp3`/`wav`/`pcm` with explicit response format preference.
- UX: Advanced pane warning; optional “Test connection”.
- Out of v1: SSH tunnels as first-class UI, remote voice cloning, streaming PCM if not widely supported (buffer full response is OK initially).

## Open questions

- Exact OpenAI TTS dialect to target first (official OpenAI `/v1/audio/speech` vs common self-hosted clones: Speaches, OpenAudio, custom FastAPI wrappers)—may need one “compatibility profile” or configurable path.
- Whether remote mode should hide local model download requirements in onboarding when enabled.
- Streaming vs full-file response for long texts (latency vs complexity).
- Should the existing loopback automation API ever proxy to remote, or only interactive app/CLI synthesis?
- Default Tailscale URL is user-specific—never ship as a default; placeholders only.

## Next

```
/ship --from-brainstorm docs/brainstorms/2026-08-10-openai-compatible-remote-tts.md
```
