# Release

> **Status: not yet implemented.** No export preset exists and no build has been
> produced. Packaging is Milestone 10. This document records the intended
> process and the prerequisites, so nothing is a surprise when we get there.

## Prerequisites

**Export templates.** Godot cannot export without the template pack matching the
engine version exactly — 4.7.1-stable. It is roughly 1 GB and is *not* included
in the editor download.

Install via the editor (Editor → Manage Export Templates → Download), or fetch
`Godot_v4.7.1-stable_export_templates.tpz` from the GitHub release and extract it
to:

```
%APPDATA%\Godot\export_templates\4.7.1.stable\
```

The `.tpz` is a zip despite the extension.

## Intended export

Preset name `Windows Desktop`, committed as `export_presets.cfg` (it contains no
secrets and is needed for reproducible builds).

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" builds/windows/FocusGarden.exe
```

Metadata to set in the preset:

| Field | Value |
|---|---|
| Product name | Focus Garden |
| File description | Focus Garden |
| Version | matches `application/config/version` in `project.godot` |
| Icon | `assets/ui/app_icon.ico` (not yet created — needs a multi-size `.ico`) |
| Console wrapper | off for the shipped build |

`builds/` is gitignored.

## Release checklist

Every item must be genuinely verified, not assumed.

- [ ] Headless boot is clean — no errors, no missing resources
- [ ] API probe passes
- [ ] Full test suite passes
- [ ] Screenshots reviewed at 1280×720 and 1920×1080
- [ ] Version bumped in `project.godot` and the export preset
- [ ] `CHANGELOG.md` updated
- [ ] Theme re-baked and committed if tokens changed
- [ ] Documentation matches what actually ships
- [ ] Save migration tested by loading a save from the previous release
- [ ] Windowed, fullscreen and borderless transitions all work
- [ ] Timer accuracy confirmed across a real sleep/resume cycle
- [ ] Exported `.exe` launches on a machine with no Godot installed
- [ ] Save files land in `%APPDATA%` and survive a restart

## Cross-platform

The project is structured so Linux and macOS presets can be added later — no
Windows-specific code exists outside the export configuration. Neither is
targeted for the first release.

macOS additionally requires signing and notarization to run without warnings;
budget for that separately.
