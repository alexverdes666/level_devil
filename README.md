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

## Cut a release for friends

Releases are built and published entirely by GitHub Actions. To ship:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

The workflow at `.github/workflows/release.yml` will:

1. Install Godot 4.3 + export templates on the runner
2. Export `build/game.exe` from the Godot project
3. Build `LevelDevilLauncher.exe` with MSVC (CMake project under `launcher/`)
4. Install Inno Setup and produce `LevelDevilSetup-<version>.exe`
5. Publish a GitHub Release tagged `v0.1.0` with all three assets attached

Friends download `LevelDevilSetup-<version>.exe` from the
[Releases page](https://github.com/alexverdes666/level_devil/releases) and run it.

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
