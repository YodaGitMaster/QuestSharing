# Local quest voice acting — investigation
Last updated: 2026-11-17

## Scope and confirmed preferences
- Research a separate addon; no runtime implementation, model install, download, commit, release or new project authorized by this request.
- User plays WoW on Windows; GPU, VRAM and CPU unknown. Current workspace targets Forever interface 16001; confirm exact client/build before implementation.
- User explicitly clarified: high-quality LOCAL voice acting, not a generic accessibility reader. Mentioned Whisper as an example of a local model.
- Whisper is speech-to-text; synthesis needs expressive text-to-speech. An LLM is optional for directing delivery, not required to speak the existing quest text.
- Desired experience: accept quest, leave NPC, keep hearing quest through a GW2-inspired portrait/subtitle window while playing.

## Proposed experience
- Capture quest offer text, title, quest ID, NPC identity/model while the dialogue is open; start/commit narration when acceptance is confirmed.
- A persistent, movable portrait/subtitle panel survives QUEST_FINISHED and walking out of interaction range.
- Model-view portrait is an animation/visual, not guaranteed audio-driven lip sync. Treat lip sync as a separate research task.
- Same NPC keeps one voice across quests; choose explicit NPC overrides, then race/gender/persona fallback, then narrator for unknown speakers.
- Preserve original quest words. Acting direction changes delivery, not objectives, numbers or lore; stage directions such as <sigh> need deliberate treatment.
- Queue rapid acceptances without overlap; show queue count and allow skipping/replay. Closing/hiding captions and stopping audio should be separate actions.
- Combat behavior selectable: continue or pause at a sentence boundary. Sentence replay is an acceptable initial resume behavior; sample-accurate seeking is backend-dependent.
- Sentence-level subtitles first. Precise word highlighting needs alignment or reliable boundary events; text-length interpolation is only an estimate.
- Personalised names/class/race and client/localisation text variants need distinct handling; prebuilt audio can use a neutral address or generated variants.

## Model shortlist (capabilities documented, not auditioned here)
| Model | Relevant strengths | Limits and role |
| --- | --- | --- |
| Qwen3-TTS 1.7B VoiceDesign / CustomVoice / Base | Describe a voice, direct tone on supported variants, create reference then reuse clone prompt for consistent character | First audition candidate; separate checkpoints have different controls, Base does not expose the same instruction control as CustomVoice; verify expressive delivery plus identity together |
| Chatterbox original 500M / Turbo 350M | Reference-based voices; original has exaggeration/CFG controls; Turbo has paralinguistic tags | Existing ForeverVO uses Chatterbox; original and Turbo controls differ; current upstream README says retired research since August 2026, so maintenance is a material drawback |
| Fish S2-Pro | Natural-language inline emotion cues, multiple speakers, local inference | Official installation lists >=24 GB GPU memory for GPU path, CPU alternative, Linux/WSL; model weights use Research License; demanding comparison candidate, not default |
| Fish Drama 3 | Scene-style multiple characters, voice cloning, director revisions and editing | Official install lists >=48 GB NVIDIA memory with FP8; unsuitable as default on unknown gaming PC |
- Kokoro is useful as a lightweight baseline but does not define the user's acting-quality target.
- No provider latency claim is a benchmark of the user's Windows PC while WoW runs. GPU memory competes with the game; no FPS or startup-delay guarantee yet.
- Do not conflate hosted APIs with local model execution. Download weights once and run inference offline where supported.

## Three implementation proposals
### A — Locally produced voice packs + standalone cinematic addon (quality-first default)
- Generate known quest/turn-in text offline with the chosen expressive model, audition takes and cache audio plus caption metadata.
- Install sound files and Lua manifest before game launch. Addon chooses audio by quest ID, phase, locale and text revision, presents portrait/subtitles and manages queue.
- Advantages: no model cost during gameplay, immediate playback, can regenerate weak performances, natural fit for existing addon sound playback.
- Limits: substantial pack storage, dataset coverage, new/changed quests and player-specific variants; missing lines need capture and later generation.
- Primary prior art ForeverVO captures text to SavedVariables, ingests after logout, synthesises with Chatterbox, then restarts client for new sounds. Do not promise arbitrary newly written audio is discoverable mid-session.
- A new GUI/Windows generator would be a separate task; upstream shell/Nix/Linux workflows are not proven Windows installers.

### B — Local model acts as an installed Windows speech voice (live prototype)
- Planned chain: addon -> C_VoiceChat.SpeakText -> registered compatible Windows speech engine -> local expressive model -> audio through speech engine.
- VoiceLink registers local Kokoro and optional Qwen3 voices; Quest TTS says compatible third-party system voices can appear; Forever UI API export includes GetTtsVoices/SpeakText/StopSpeakingText.
- These sources establish a plausible route, NOT confirmed VoiceLink+Forever interoperability.
- Must first test voice enumeration, speaking, stopping, queue lifecycle, sentence/bookmark events and actual latency in the target client.
- Acting controls may not cross standard speech interfaces; do not assume arbitrary emotion prompts or per-NPC reference clips can be sent through SpeakText. A custom adapter/profile mapping may be required.
- Best if live synthesis is essential and the engine exposes both desired quality and delivery control.

### C — Addon + Windows capture companion (flexible live fallback)
- Addon renders quest text/ID and playback commands into a visible encoded strip. A screen-capture companion decodes it, runs expressive TTS and plays audio externally.
- JocysCom TTS Monitor implements this outgoing pixel transport; more recent WoW Context Bridge is another reference but explicitly leaves Forever live compatibility unverified.
- Full text requires chunking/sequence IDs/checksums, not a quest ID alone unless a matching local text database exists.
- Controls can travel outward the same way. No ordinary HTTP/socket call from addon to localhost.
- Companion owns real audio timing. The addon cannot assume a return channel: precise subtitles, buffering/error feedback and end-of-playback acknowledgement need separate design; an external overlay is one option.
- Adds capture/scaling/fullscreen/minimise fragility. Do not present this as a simple HTTP integration or claim official client approval.

## Existing addons worth studying
- Spoken: Forever quest/gossip packs, narrator windows, subtitles, queue and DialogueUI bridge. Word highlighting is estimated, per its README. Good UX comparison; pre-generated packs are not live model inference.
- ForeverVO: closest architecture precedent for LOCAL acted voice packs, talking-head player, queue, capture/generate/restart workflow.
- DialogueUI: quest/gossip window and public SetVOProvider hook; Spoken bridge documents additional internal hooks. Changes to another addon's internals carry version coupling.
- Quest TTS: native speech API/installed-voice precedent, not proof of desired acting quality.
- Reuse concepts or published APIs; check relevant licenses before distributing copied code/assets. No source vendored in this investigation.

## Current project evidence (read-only)
- QuestSharing/QuestSharing.toc targets interface 16001 and currently declares 0.4.17; older continuity entries discuss published 0.4.16. No release status changed here.
- QuestSharing/QuestAutomation.lua handles QUEST_DETAIL and immediately calls AcceptQuest when enabled. Capture must happen before that call, or text must be reacquired reliably; independent event callback order is not a sufficient cross-addon guarantee.
- QuestSharing/Core.lua stores callbacks in registration order for its own event dispatcher. A separate addon's dispatcher has no promised relative order.
- The proposed separate addon should not require QuestSharing. Optional interoperability must handle its auto-accept/auto-complete behavior and other quest-dialog addons.

## Planned data contract (not implemented)
- Line: client/build, questID, phase (offer/progress/complete/gossip), locale, source text, normalised text hash, NPC ID/model, speaker profile.
- Performance: model/checkpoint revision, reference/profile revision, acting direction, pronunciation dictionary revision, synthesis settings, audio file, duration, sentence/word timing.
- Cache key must cover text, locale, speaker, model and settings; questID alone silently reuses stale or wrong voices.
- Player runtime: pending offer snapshot, acceptance correlation, active line, queued lines, sentence position, state (idle/buffering/playing/paused/error).

## Proposed next investigation, not an implementation commitment
1. Learn GPU model/VRAM. Select local runners appropriate to Windows; benchmark on that machine.
2. Audition Qwen3-TTS and Chatterbox on identical real passages: urgent guard, grieving villager, mischievous goblin and solemn elder.
3. Judge acting/naturalness, word accuracy, repeated-name pronunciation, stable identity across lines and long-text drift; measure cold/warm delay, real-time factor, peak VRAM and frame-time impact alongside WoW.
4. Compare prebuilt pack path with native speech bridge before investing in an optical bridge.
5. Prototype a standalone portrait/caption queue only after scope chosen. Confirm accepting 3 quests, walking away, combat, replay and auto-accept compatibility in game.
- Proposed acceptance target (not measured): same NPC stays recognisable, no omitted/changed objectives, no overlapping speech, no frame stalls, subtitle window persists after NPC dialogue closes.

## Sources checked 2026-11-16
- Qwen models/control and design-then-clone workflow: https://github.com/QwenLM/Qwen3-TTS
- Chatterbox models, original emotion controls, Turbo differences and archive notice: https://github.com/resemble-ai/chatterbox
- Fish models/controls/licenses: https://github.com/fishaudio/fish-speech/blob/main/docs/en/index.md
- Fish hardware/platform requirements: https://github.com/fishaudio/fish-speech/blob/main/docs/en/install.md
- Local synthesis + Forever talking-head architecture: https://github.com/quinn-dougherty/forever-vo
- Spoken player/styles: https://github.com/rusty-key/spoken-wow
- DialogueUI bridge: https://github.com/rusty-key/spoken-wow/blob/master/docs/quests/DIALOGUEUI-BRIDGE.md
- Native installed voices: https://github.com/z0fa/WoWQuestTTS
- Windows model speech adapter: https://github.com/ManveerAnand/VoiceLink
- Forever speech API export: https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/VoiceChatDocumentation.lua
- Existing optical quest speech bridge: https://github.com/JocysCom/TextToSpeech
- Newer optical bridge and explicit live-compatibility limits: https://github.com/nukeador/wow-context-bridge

## Verification limits
- Repository/context and upstream primary documentation inspected. No models installed, audio generated, Windows machine inspected or native game test performed.
- Recommendations are design judgments to validate with auditions, not a measured ranking or a claim of professional-actor equivalence.

## 2026-11-17 — How the addon interfaces with the model
- User asks specifically about integration, not implementation. Rechecked Forever API export, VoiceLink README, ForeverVO workflow and JocysCom primary repo.
- Two different executables: WoW runs Lua UI/capture; Windows hosts model inference. Installing a Lua addon alone does not embed Qwen or permit arbitrary localhost HTTP.
- Proposed native chain: offer snapshot -> acceptance confirmed -> NPC-to-registered-voice/profile mapping -> C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap) -> compatible Windows speech adapter -> local model -> audio back through speech engine.
- The adapter may call a local model HTTP server; the addon itself does not make that call. Lua receives supported speech events, not raw model audio/WAV tensors. Playback feedback/timing must be established in client tests before promising synchronized captions.
- SpeakText has no documented NPC-ID, reference-audio or emotion-prompt parameters. Profiles could be configured behind registered voice IDs; arbitrary per-line acting directions need adapter-specific design and testing. VoiceLink is a proof of the adapter pattern, not a verified complete NPC acting solution.
- StopSpeakingText is documented; exact pause/resume is not established. Initial UI could stop then replay the current sentence. Avoid claiming ordinary StopSpeakingText supports seeking or affecting only this addon's speech without testing.
- Reliable offline alternative: local generator consumes matching quest text/NPC profiles before launch -> writes sound files + Lua manifest (quest/phase/locale/text hash, path, duration/captions) -> addon selects file and plays with PlaySoundFile. Newly captured unknown text is processed after SavedVariables flush/restart, not a live file-watcher transport.
- A screen-capture bridge is fallback if the native engine path fails; companion owns audio and true timing, with no automatic inbound acknowledgement to Lua.
- No model install, source implementation or live client verification performed. Native compatibility and expression control remain the first feasibility tests.

```mermaid
sequenceDiagram
    participant Game as WoW quest events
    participant Addon as Proposed narration addon
    participant Voice as Windows speech adapter
    participant Model as Local Qwen3-TTS
    Game->>Addon: Quest offer text, then acceptance
    Note over Addon: Keep portrait/subtitle window after dialogue closes
    Addon->>Voice: SpeakText via compatible registered voice
    Voice->>Model: Text and configured speaker profile
    Model-->>Voice: Generated audio
    Note over Voice,Model: Proposed native path; interoperability unverified
```

## 2026-11-17 — Where TTS is hosted
- Clarified proposed deployment: on the player's Windows PC, as a separate background model process managed by a companion/tray app; downloaded weights live on SSD and load into RAM/VRAM for inference.
- A localhost-only endpoint is a proposed internal connection between Windows voice adapter and inference process, not a public hosting service and not an HTTP endpoint the Lua addon calls directly.
- Proposed companion lifecycle: start before/with gameplay, load model once, accept queued requests and cache generated performances; close/unload when no longer needed. Autostart and caching are design choices, not verified existing addon features.
- VoiceLink primary README rechecked: self-contained Python runtime, local model/server directories under ProgramData, Windows voice registration and no internet required after setup. Its Qwen GPU requirements are specific to that runner and do not establish game performance.
- No cloud hosting account/subscription needed for local inference; hardware, storage and electricity remain local costs. No software installed by this explanation.
