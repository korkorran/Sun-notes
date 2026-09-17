# Guides

Notes techniques sur la construction de Sun notes et sur l'écosystème auquel
l'application se lie. Si vous cherchez à compiler le projet,
[compiling.md](./compiling.md) est le point d'entrée ; le reste éclaire un point
précis rencontré en chemin.

## Choix de conception

- **[comparing-owebview.md](./comparing-owebview.md)** — owebview face à
  lablgtk3, Bogue et les autres, et pourquoi ce projet a choisi un moteur web
  embarqué.

## Compiler

- **[compiling.md](./compiling.md)** — la compilation de la partie native, les
  prérequis par plateforme, et comment le moteur de rendu est choisi.

## Interfacer du C et du C++

- **[c-stub.md](./c-stub.md)** — comment un stub C/C++ se compile avec dune, et
  le piège de la décoration des symboles en C++.
- **[c-flags.md](./c-flags.md)** — les drapeaux de compilation et de liens
  d'owebview, plateforme par plateforme, et comment ils se propagent.
- **[ctypes.md](./ctypes.md)** — les autres façons de lier du C depuis OCaml, et
  pourquoi le stub manuel a été retenu ici.

## L'écosystème Linux

- **[pkg-config.md](./pkg-config.md)** — comment les chemins et bibliothèques
  sont découverts à la compilation.
- **[gtk.md](./gtk.md)** — ce qu'est GTK, et ce qui sépare GTK 3 de GTK 4.
- **[libsoup.md](./libsoup.md)** — pourquoi WebKitGTK a trois noms pkg-config,
  et d'où vient le plancher de distribution.
- **[gnome.md](./gnome.md)** — ce qu'est GNOME, son rapport avec GTK, et les
  conventions de bureau que les paquets doivent respecter.
- **[wayland.md](./wayland.md)** — Wayland et X11, et pourquoi l'icône d'une
  application Linux se trouve dans son paquet.

---

L'empaquetage et la distribution sont traités à part, dans
[`packaging/README.md`](../../packaging/README.md).
