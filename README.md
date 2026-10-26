# Quarry

One place for my small Mac tools. Quarry installs them, runs them, keeps them up to date and
puts all of their settings in one window, behind one menu bar icon.

Every tool still works as its own app. Download it on its own and it has its own menu bar icon,
settings window and updater. Add it to Quarry and those go away: Quarry's menu gets a section
for it, Quarry's window gets its pages, and Quarry handles updates.

| Tool | What it does |
| --- | --- |
| [Spinel](https://github.com/PzmuV1517/Spinel) | Tiling that works with native Spaces, fullscreen apps and every display. |

## Install

Grab `Quarry-<version>.zip` from [Releases](https://github.com/PzmuV1517/Quarry/releases),
unzip it and move `Quarry.app` to Applications. It isn't notarized yet, so the first time,
right-click it → **Open**.

Then open **Library** in Quarry's window and pick **Install**, or **Add** for a tool that's
already in Applications. Tools that move windows (Spinel) need Accessibility access, which
Quarry asks for once on behalf of all of them.

**From source:**

```sh
make install     # builds, signs, copies to /Applications and launches
```

Other targets: `make test`, `make run` (launch from `build/`), `make icon`, `make release`.

## How it works

- **One process.** A tool ships its code as a library inside its app
  (`Contents/Frameworks`, named by the `QuarryLibrary` Info.plist key). On its own, the app
  loads that library itself. In Quarry, Quarry loads the same library, so there is one menu bar
  icon, one window and one Accessibility grant.
- **The contract** is `QuarryKit`'s `QuarryTool` and `QuarryHost` protocols, plus two C
  functions each tool exports (see `Sources/QuarryKit/Interface.swift`). QuarryKit also holds the
  shared look, so every tool's pages match Quarry's.
- **Who runs what.** `~/.config/quarry/config.json` lists the tools Quarry runs. A tool
  launched on its own checks that list first and, if Quarry has it, opens Quarry on its page
  (`quarry://tool/<bundle id>`) instead of running twice.
- **Updates** come from each tool's GitHub releases. A download is installed only if it has the
  right bundle identifier and is signed by the same team as Quarry. A running library can't be
  unloaded, so installing an update restarts Quarry.
- **The tool list** is [`catalog.json`](catalog.json), read live from this repository, so new
  tools show up without updating Quarry.

## Making a tool

1. Depend on `QuarryKit` (`.package(url: "https://github.com/PzmuV1517/Quarry.git", from: "0.1.0")`).
2. Build the app's code as a dynamic library, and make the app's executable a launcher that
   loads it (see Spinel's `Sources/Spinel/main.swift`).
3. Export `quarry_interface_version` and `quarry_tool_make`, returning a `QuarryTool`.
4. Add `QuarryLibrary` (and `QuarryNeedsAccessibility` if needed) to Info.plist.
5. At launch, if `QuarryHub.manages(<bundle id>)`, call `QuarryHub.show(tool:)` and quit.
6. Publish `<Name>-<version>.zip` releases and add the tool to `catalog.json`.

**Easter eggs** (`Sources/QuarryKit/EasterEgg.swift`): mark views `.fallable("id")`, wrap the
window or page in `.easterEggStage(host:) { done in Finale() }`, and put
`.easterEggTrigger(taps: 5)` on whatever starts it. The marked views fall with gravity and
collisions, the finale plays full window with a Back button, and everything springs back.
Inside Quarry, pass the `QuarryHost`: the tool's trigger asks Quarry to play it
(`QuarryHost.playEasterEgg`), so Quarry's sidebar falls along with the tool's page and the
finale covers Quarry's whole window. `EasterEggClip(url:onEnd:)` plays a video as the finale.
