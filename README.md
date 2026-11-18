<p align="center">
  <img src="./logo.png" width="200" alt="sun-notes">
</p>
<h1 align=center>Sun notes</h1>
<p align="center">A note-taking app written in OCaml</p>
<br/>

Implemented with the libraries Owebview for the desktop-GUI bindings and Vdom for the web rendering.

![Screenshot of Sun notes](./screenshot.jpg)

## Download

Click on the "Releases" link of the Github page of the repository to access the installers.

Pick the file matching your system **and its architecture** — `uname -m` tells
you which (`x86_64` for a PC, `aarch64`/`arm64` for an ARM machine, including a
Linux VM on an Apple Silicon Mac).

| Platform | File | Notes |
|---|---|---|
| macOS, Apple Silicon | `Sun-notes-<version>-arm64.dmg` | macOS 11 or later. Signed ad-hoc but not notarised: on first launch, right-click it in Applications and choose *Open*. |
| Debian, Ubuntu and derivatives | `sun-notes_<version>_amd64.deb`<br>`sun-notes_<version>_arm64.deb` | Debian 12 / Ubuntu 22.04 or later, which is where webkit2gtk-4.1 arrives. `sudo apt install ./sun-notes_<version>_<arch>.deb` |
| Fedora and other RPM distributions | `sun-notes-<version>-1.<dist>.x86_64.rpm`<br>`sun-notes-<version>-1.<dist>.aarch64.rpm` | Built on the current Fedora, so it needs that release's glibc or newer. `sudo dnf install ./sun-notes-<version>-1.<dist>.<arch>.rpm` |
| Windows 10/11, x64 | `Sun-notes-<version>-x64-setup.exe` | Also installs on Windows on ARM, under emulation. Fetches the Microsoft Edge WebView2 runtime if it is missing. Not code-signed, so SmartScreen will warn. |

The leading `./` in the apt and dnf commands matters: without it they look for a
package of that name in your repositories rather than the file you downloaded.

Intel Macs and 32-bit systems are not built; see [packaging/](./packaging) to
build from source.

## Install with opam

If you have an opam switch, Sun notes installs into it straight from the
repository, with no release to download:

```sh
opam pin git+https://github.com/korkorran/Sun-notes.git
```

One command: it pins the repository, builds it and installs it. Sun notes is
not in the opam repository, so opam asks first whether to create it as a new
package — answer yes. The `git+` prefix is not decoration: without it opam
takes the URL for an archive to download, and fails on the HTML page GitHub
sends back.

You then have a `sun-notes` command in the switch, with the page and the icon
in `share/sun-notes` beside it. `opam pin remove sun-notes` undoes the whole
thing.

The build needs a C++ toolchain and the native web engine's development files,
which is what [owebview](https://github.com/korkorran/Owebview) builds against
— `webkit2gtk-4.1` on Linux, the WebView2 SDK on Windows (`nuget install
Microsoft.Web.WebView2` before installing), nothing extra on macOS. A
downloaded installer from the table above needs none of that, and stays the
easier route for anyone who is not already an OCaml user.

If the icon does not show up under Wayland, run

```sh
sun-notes --install-icon
```

Wayland has no window icon to set: the shell resolves an application's icon
from an installed desktop entry instead, and this writes one into
`~/.local/share/applications`. The command prints the path it wrote, and
deleting that file is all it takes to undo.

## Contribute

Clone the repository.

All the dependencies can be installed with the command

```sh
opam install . --deps-only
```
The project depends on owebview so on Windows, prior to 'opam install .', run the command `nuget install Microsoft.Web.WebView2` to install the WebView2 SDK.

To run the app :

```sh
dune build
dune exec run/main.exe
```

## License

MIT