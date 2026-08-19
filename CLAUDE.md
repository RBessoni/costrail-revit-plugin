# Working on BIM Cost for Revit

BIM Cost is a rebranded fork of Speckle's Revit connector. `BIMCOST.md` documents the
project for people; this file records what an agent needs to avoid re-learning the hard
parts. Read both before changing anything.

## The single most important fact

**The panel UI is not in this repo.** What a user sees inside Revit is a Nuxt 3 app that
lives in a separate repo, cloned as a sibling:

```
<parent>/
├── <this repo>/                  ← C# connector, installer, Revit integration
└── speckle-connectors-dui/       ← the panel UI (repo: RBessoni/costrail-connector-dui)
```

If a request is about how the panel *looks* or *reads* — colours, copy, buttons, layout —
the change belongs in `../speckle-connectors-dui`, not here. Searching this repo for panel
text will find nothing.

The UI folder **must** be named `speckle-connectors-dui`. `Connectors/Revit/Directory.Build.targets`
and `Build/installer/BIMCostForRevit.iss` resolve it by relative path. A plain `git clone`
of the fork produces `costrail-connector-dui` and the build then ships an installer with no
panel, silently and with no error.

## Both repos

| | Repo | Upstream | Branch |
| --- | --- | --- | --- |
| C# | `RBessoni/costrail-revit-plugin` | `specklesystems/speckle-sharp-connectors` | `bimcost/rebrand` |
| UI | `RBessoni/costrail-connector-dui` | `specklesystems/speckle-connectors-dui` | `bimcost/rebrand` |

Both keep `upstream` as a second remote with **push disabled** (`DISABLED_use_origin`).
Never re-enable it. Pull upstream changes with `git fetch upstream && git merge upstream/dev`
(`upstream/main` for the UI).

## Build and verify

One command builds everything, in the only order that works — UI first, because the
installer embeds its output:

```powershell
.\Build\build-installer.ps1              # full build
.\Build\build-installer.ps1 -SkipUi      # C#-only change, much faster
.\Build\build-installer.ps1 -Version 1.1.0
```

Gates that must pass before handing work over:

- UI repo: `corepack yarn lint:ci` (TypeScript + CSS). Non-negotiable.
- C#: the Release build inside the script. ILRepack emits three `Method reference is used
  with definition return type` warnings — those are pre-existing upstream noise, not
  regressions.

`ISCC.exe` lives at `%LOCALAPPDATA%\Programs\Inno Setup 6\` — winget installs it per-user,
so it is not on PATH and not under Program Files.

## Verifying UI changes

The dev server is flaky in this environment and has died mid-session more than once. The
reliable loop is to build the static bundle and serve it, which also tests closer to
production than dev mode does:

```powershell
cd ../speckle-connectors-dui; corepack yarn generate
# then serve .output/public over plain http and inspect the DOM
```

Two habits that repeatedly caught real bugs:

- **Assert against the built bundle, not the source.** `grep -rl "<string>" .output/public`
  is how you prove a removal actually shipped. Source greps have been misleading.
- **Read computed styles and DOM text via JS, not screenshots.** Screenshots return black
  frames whenever the browser pane is not displayed, and the page often renders a beat
  after navigation — query once, then query again before concluding anything is broken.

Production mode legitimately shows `BIM Cost plugin is not connected.` outside Revit: there
are no host bindings. That is correct, not a failure. Dev mode registers mocked bindings and
renders the full panel.

## Traps that have already cost time

**Theme tokens.** The upstream Tailwind theme defines every colour on `html`, `html.dark`
*and* `html[class*="dark"]`. Our overrides live at the end of `assets/css/tailwind.css`.
A `:root` override (0,1,0) beats `html` (0,0,1) so light mode works — but a plain `.dark`
(0,1,0) **loses** to `html.dark` (0,1,1) and dark mode silently reverts to Speckle blue.
The dark selector must be `:root.dark`. To diagnose, enumerate the CSSOM in the browser;
reading the compiled `plugin.js` is far slower.

**`<NuxtImg>` is forbidden.** It routes through the IPX provider, which needs a server. The
panel is static files behind a WebView2 virtual host, so it 404s silently. Use plain `<img>`;
Vite inlines small SVGs as data URIs anyway.

**The `/index.html` route.** The virtual host has no directory index, so the host opens
`/index.html` directly. `pages/index.vue` carries `definePageMeta({ alias: ['/index.html'] })`.
Remove it and the panel shows Nuxt's 404 on launch.

**WebView2 initialisation order.** `RevitControlWebView` must not set `Source` in the
constructor: `SetVirtualHostNameToFolderMapping` can only be called once `CoreWebView2`
exists. Initialisation is explicit (`EnsureCoreWebView2Async`) and navigation happens in
`OnInitialized`, after bindings are registered so host objects exist before the page loads.

**Building while Revit is open.** `AfterBuildRevit` copies the addin into the Revit Addins
folder and fails on locked DLLs. Always pass `-p:ContinuousIntegrationBuild=true` for
Release/packaging builds; the installer handles deployment. Installing also requires Revit
to be closed — the installer refuses to start otherwise.

## Editing conventions

**GUIDs are load-bearing.** The addin `ClientId` (`8ae12a74-…`) and `DockablePaneId`
(`8b926740-…`) were changed precisely because every upstream manifest shares one of each.
If they ever match upstream again, Revit conflicts when both connectors are installed and
one fails to load. Never take upstream's values in a merge.

**Telemetry must stay out.** Upstream's Release path exports logs and traces to
`seq.speckle.systems` with a hardcoded API key. `Sdk/Speckle.Connectors.Common/Connector.cs`
has it removed. Check this after every upstream merge.

**The debranding boundary.** Remove *visual* Speckle references — names, logos, docs links,
promo blocks, the update checker. Keep *functional* ones: the account flow still
authenticates against `app.speckle.systems`, and adding an account still downloads Speckle's
Desktop Service. Those cannot go without replacing the backend, and breaking them breaks
sign-in. Do not "fix" them.

**Multi-line edits.** Escaping through `bash -c "node -e ..."` has failed repeatedly on
backslashes and quotes; write the script to a file and run it. Several source files are
CRLF, so anchors containing `\n` silently fail to match — use `\r?\n`, and confirm a
replacement actually applied instead of trusting that the command exited zero.

**Do not count XML or Vue tags with grep.** `grep -c '<MenuItem'` also counts `<MenuItems>`,
which once hid an unbalanced tag and produced a 500 that looked like an unrelated bug. When
a structural edit goes wrong, restore the file from git and redo it with verified line
ranges rather than patching the damage.

## Not in version control

`output/` (installers) and the UI's `.output/` (generated bundle) are gitignored build
artifacts. Never commit the `.exe`. `.claude/` is also ignored, so any launch config there
is local-only.
