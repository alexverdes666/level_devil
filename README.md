# Level Devil

A troll platformer. Reach the green door. The level is out to get you.

| Folder | What's in it |
| --- | --- |
| `main.gd`, `main.tscn`, `project.godot` | Godot 4 game (single procedural scene, primitives only) |
| `launcher/` | C++ launcher (CMake + WinHTTP) that auto-updates the game from GitHub Releases |
| `installer/` | Inno Setup script that bundles the launcher + game into `LevelDevilSetup.exe` |
| `.github/workflows/` | Builds everything and publishes a Release on every `v*` tag |

## Controls

| Action | Key |
| --- | --- |
| Move | `A`/`D` or arrow keys |
| Jump | `W`, `Up`, or `Space` |
| Restart level | `R` |
| Pause / open menu | `Esc` |

## Play locally (no installer)

The repo includes the Godot project but no binaries. Open it in Godot 4.3:

```powershell
& "D:\Godot4\Godot_v4.3-stable_win64.exe" --path .
```

Then press `F5` to run.

## Development workflow

There are two distinct push flows. Knowing which one you want is the whole
trick to working in this repo.

### A. Everyday changes (no release for friends)

Edit, test, commit, push to `main`. Friends with the installer are **not**
affected — their launcher only updates when a new GitHub Release exists.

```powershell
# Test the change locally first
& "D:\Godot4\Godot_v4.3-stable_win64.exe" --path .   # then F5 in the editor

# Commit and push
git add -A
git commit -m "Tweak level 3 door speed"
git push
```

CI runs the release workflow on tag pushes only, so pushing to `main` is
cheap — it doesn't build or release anything.

### B. Cutting a release that friends will receive

When `main` is in a state you're happy to ship, push a semver tag. CI does
everything else.

```powershell
# Make sure main is up to date and pushed first
git status
git push

# Bump the tag — use the next semver. Existing tags are visible with `git tag`.
git tag v0.1.1
git push origin v0.1.1
```

That tag push triggers `.github/workflows/release.yml`, which will:

1. Install Godot 4.3 + export templates on the runner
2. Export `build/game.exe` from the Godot project
3. Build `LevelDevilLauncher.exe` with MSVC (CMake project under `launcher/`)
4. Install Inno Setup and produce `LevelDevilSetup-<version>.exe`
5. Publish a GitHub Release with all three assets attached, named after the tag

Friends download `LevelDevilSetup-<version>.exe` from the
[Releases page](https://github.com/alexverdes666/level_devil/releases) — that
single .exe is what you share with them.

Existing installs auto-update: on next launch, `LevelDevilLauncher.exe`
queries the GitHub Releases API, sees the newer tag, downloads the new
`game.exe`, and replaces the local copy before launching it. The in-game
**Check for updates** button forces the same flow without a relaunch.

### Versioning rules

- `v0.x.y` while pre-1.0. Bump `y` for any user-visible change, `x` for bigger
  feature jumps.
- Tags must start with `v` — the CI trigger and the launcher both depend on
  that prefix.
- Don't reuse or move tags. If a release is broken, ship `v0.x.(y+1)` rather
  than re-tagging. Moving a tag will not propagate to installed launchers
  (they cache by tag name).

### If a release is broken

1. Fix the bug on `main`, commit, push.
2. Tag `v0.x.(y+1)` and push the tag.
3. Optionally delete the broken release from the GitHub Releases page so
   nobody installs it fresh. (Launchers that already have the broken version
   will pick up `v0.x.(y+1)` on next launch regardless.)

### If you only changed the launcher or installer

Same flow — bump the tag and push. The Godot game export is fast (~30s on
the runner), so there's no point splitting the pipeline.

### Workflow dispatch (manual build without tagging)

The release workflow also has a `workflow_dispatch` trigger. From the GitHub
Actions tab, you can run it with a manual tag string (e.g. `v0.0.0-dev`).
That builds all the artifacts and uploads them as workflow artifacts, but
does **not** create a GitHub Release. Useful for verifying CI changes.

## How auto-update works

`LevelDevilLauncher.exe` is what the Start Menu shortcut points at — never `game.exe` directly. On every launch it:

1. Optionally waits for a passed `--wait-pid` to exit (used by the in-game **Check for updates** button)
2. `GET https://api.github.com/repos/alexverdes666/level_devil/releases/latest`
3. Compares `tag_name` against the local `version.txt`
4. If different, downloads the `game.exe` asset and atomically replaces the local copy
5. Spawns `game.exe`

The in-game **Pause → Check for updates** and **Title → Check for updates** buttons spawn the launcher with `--update --wait-pid <gamepid>`, then quit the game so the file isn't locked when the launcher tries to overwrite it.

## Local launcher build (optional, for development)

```powershell
cmake -S launcher -B launcher\build -G "Visual Studio 17 2022" -A x64
cmake --build launcher\build --config Release
```

Result: `launcher\build\Release\LevelDevilLauncher.exe`.

## Levels (what each one trolls)

| # | Mechanic |
| --- | --- |
| 1 | Tutorial — actually fair |
| 2 | Falling spike triggered as you approach the door |
| 3 | Floor chunks vanish ~0.5s after you stand on them |
| 4 | Door flees and wraps around the screen |
| 5 | Floor spikes rise as you cross trigger points |
| 6 | Three identical-looking doors, only the middle one is honest, plus all of the above |
