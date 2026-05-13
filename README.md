# AiLA — Interview Assistant for macOS

Push-to-talk interview helper that lives in the Mac notch. The interviewer asks a question, you tap a global hotkey, and a structured answer (lead → beats → closer + likely follow-ups) appears in the notch — enough to read aloud while you speak. The HUD is invisible to screen recording, so it stays hidden during shared screens.

> **Origin.** AiLA is built on top of [jpomykala/NotchPrompter](https://github.com/jpomykala/NotchPrompter), an MIT-licensed teleprompter app for macOS. We retained the notch window, screen-recording invisibility, and menu-bar shell, and rebuilt the app around an interview-assistant pipeline (ScreenCaptureKit audio → ElevenLabs Scribe → Anthropic claude-sonnet-4-6 with a structured Interview Ace prompt). Future fixes and visual improvements from upstream NotchPrompter are tracked via the `upstream` git remote — see [§ Pulling upstream NotchPrompter changes](#pulling-upstream-notchprompter-changes).

## How it works

```
⌃⌥? pressed         ⌃⌥? pressed again
   ↓                       ↓
[─── system audio ───] → ElevenLabs Scribe → Anthropic claude-sonnet-4-6
                                                       ↓
                                  METRIC pill · LEAD · BEATS · CLOSER · RUNWAY
```

- **Audio source** — Apple's ScreenCaptureKit captures the system audio mix. No virtual audio cable, no Audio MIDI Setup, no microphone access. Whatever is playing on your Mac (Zoom, Meet, Teams, anything) is what the app hears.
- **Transcription** — ElevenLabs Scribe v1, batch upload of the captured WAV.
- **Answer** — Anthropic `claude-sonnet-4-6` driven by the Interview Ace prompt, with prompt caching on the system blocks (operating principles + setup context). Streamed token-by-token.
- **Display** — Five visual zones: a high-contrast METRIC pill, a large bold LEAD, scannable BEATS, an italic CLOSER, and a RUNWAY line predicting likely follow-ups.
- **Privacy** — API keys in macOS Keychain (or bundled in the team build); HUD invisible to screen recording (`sharingType = .none`); conversation history stays in memory only.

## Team install (90 seconds, no API keys needed)

If you're on the internal team using a build distributed via Slack, follow [TEAM_INSTALL.md](TEAM_INSTALL.md) — it has step-by-step instructions for installing the `.app`, granting Screen Recording permission, filling in your interview setup, and running a smoke test. API keys are pre-bundled into the team build; you don't need to obtain or paste any.

## Setup (per-user, ~2 minutes — building from source)

### 1. API keys

Open the app's **Settings → API Keys** and paste:

- **Anthropic** — get a key at <https://console.anthropic.com/settings/keys>
- **ElevenLabs** — get a key at <https://elevenlabs.io/app/settings/api-keys>

Both are stored in macOS Keychain. (Team distributions of the app may ship with keys already bundled.)

### 2. Interview Setup

In **Settings → Interview**, fill in:

- Interviewer name + company (the company sets the domain language used in every answer)
- Your current employer + project
- 1-2 past companies, one line each

This is the entire context the LLM uses. Keep it tight; it's the Interview Ace skill's lightweight setup, not a resume dump.

### 3. Screen Recording permission

The first time you trigger the hotkey, macOS will prompt for **Screen Recording** permission. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and relaunch the app once. After that it just works.

## Usage

1. Start the call (Zoom / Meet / Teams).
2. When you're asked a question, press **⌃⌥?** (Ctrl+Option+Shift+/).
3. The notch shows a red pulsing dot — **listening**.
4. After the interviewer finishes, press **⌃⌥?** again.
5. While the audio is being transcribed and the answer generated, the notch shows a calming cue rotating through *breathe / smile / relax / pause / steady / easy*.
6. ~1-3 seconds later, the answer appears: a high-contrast metric pill, a bold lead sentence, a few scannable beats, an italic closer, and a small runway line predicting where the interviewer might go next. Read the lead aloud first, then expand into the story using the beats.
7. The answer stays visible until your next hotkey press. Press ⌃⌥H to hide the HUD globally; ⌃⌥N to start a fresh interview (clears conversation history).

All shortcuts are customizable in **Settings → Shortcuts**. Each combo must include at least one of ⌃ ⌥ ⌘.

## Build

The Xcode project is generated locally (it's not checked into git — see `.gitignore`). You'll need:

- **Xcode 15+** on **macOS 14 (Sonoma) or later**
- **XcodeGen** (`brew install xcodegen`)
- The [HotKey](https://github.com/soffes/HotKey) Swift package — auto-fetched by `project.yml`

```bash
cd path/to/repo
xcodegen generate
open NotchPrompter.xcodeproj
# ⌘R in Xcode
```

OpenDyslexic font files and the Interview Ace prompt are bundled in-tree; nothing extra to install.

## Privacy & data flow

- **What leaves your machine:** the audio captured between your two hotkey presses (sent to ElevenLabs); the conversation transcript + your interview setup (sent to Anthropic). Nothing is sent outside an active question.
- **What stays local:** API keys (Keychain), interview setup (UserDefaults), captured WAVs (`~/Library/Caches/notch-prompter/`), conversation history (in-memory only — wiped on `⌃⌥N` or app quit).
- **The HUD is hidden from screen recording.** On by default. Toggle in **Settings → Layout → Privacy** if you ever need to record it.

## Limitations

- **Push-to-talk only.** No auto-detection of question end. You commit each answer with the hotkey.
- **Single-machine audio.** ScreenCaptureKit captures the entire Mac mix. If you're playing music while interviewing, the music is in the recording too. Mute other apps.
- **Caching threshold.** Anthropic prompt caching for `claude-sonnet-4-6` activates above ~2k tokens. The Interview Ace operating principles + your setup typically clear that. If they don't, the request still works, just at full price (~$0.005/question instead of ~$0.001).

## Pulling upstream NotchPrompter changes

The original [jpomykala/NotchPrompter](https://github.com/jpomykala/NotchPrompter) is configured as the `upstream` remote. To check what they've shipped since the last sync:

```bash
git fetch upstream
git log --oneline main..upstream/main          # what's new upstream that we don't have
git diff main upstream/main -- notch-prompter/  # diff their Swift sources vs ours
```

When something is worth bringing in (e.g. a notch geometry fix, a window-behavior tweak, a localization update), cherry-pick selectively rather than merging — most upstream changes are about the teleprompter feature and don't apply here:

```bash
git cherry-pick <commit-sha>          # bring one upstream commit over
git cherry-pick --no-commit <sha>     # stage only — useful when only a hunk applies
```

If upstream renames or moves files we've already deleted (`PrompterView.swift`, `PrompterViewModel.swift`, `HighlightingTextEditor.swift`), expect merge conflicts — resolve by deleting again.

## License

MIT (app source, retained from upstream NotchPrompter). OpenDyslexic font ships under the SIL Open Font License — see `notch-prompter/Fonts/OFL.txt`.

## Acknowledgements

- [jpomykala/NotchPrompter](https://github.com/jpomykala/NotchPrompter) — the original notch-shell teleprompter that AiLA was built from.
- [Interview Ace](https://github.com/anthropics/skills) skill style — the system-prompt pattern (METRIC removed, LEAD / BEATS / CLOSER / RUNWAY retained, BRIDGE phrase added) that drives the answer structure in the HUD.
