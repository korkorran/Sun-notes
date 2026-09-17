# pkg-config

Note de contexte, dans la continuité de [c-flags.md](./c-flags.md).

## Le problème qu'il résout

Pour compiler contre une bibliothèque C, il faut connaître ses chemins
d'en-têtes (`-I`), ses chemins de bibliothèques (`-L`), les bibliothèques à lier
(`-l`), et parfois des définitions supplémentaires.

Rien de tout cela n'est stable. Les chemins changent d'une distribution à
l'autre — `/usr/lib/x86_64-linux-gnu` chez Debian, `/usr/lib64` chez Fedora — et
d'une architecture à l'autre. Les écrire en dur donne un projet qui ne compile
que sur la machine de son auteur.

## Ce qu'est pkg-config

Un petit programme qui répond à ces questions, en lisant des fichiers
**`.pc`** que les bibliothèques installent avec leurs en-têtes — dans les
paquets `-dev` ou `-devel`.

```sh
pkg-config --cflags gtk+-3.0     # les -I
pkg-config --libs gtk+-3.0       # les -L et -l
pkg-config --modversion gtk+-3.0 # la version installée
pkg-config --exists gtk+-3.0     # 0 si présent, 1 sinon
```

Un fichier `.pc` est court :

```
prefix=/usr
libdir=${prefix}/lib/x86_64-linux-gnu
includedir=${prefix}/include

Name: GTK+
Description: GTK+ Graphical UI Library
Version: 3.24.38
Requires: gdk-3.0 atk pangocairo gio-2.0
Libs: -L${libdir} -lgtk-3
Cflags: -I${includedir}/gtk-3.0
```

## Ce qu'il faut en retenir

**Il est transitif.** La ligne `Requires:` désigne d'autres modules, que
pkg-config résout à son tour. C'est pourquoi une seule interrogation de
`gtk+-3.0` renvoie des dizaines de drapeaux : GLib, GObject, GIO, Pango, Cairo
et GdkPixbuf arrivent tous par ce graphe.

**Trois noms différents désignent la même bibliothèque**, et les confondre est
la source d'erreur la plus fréquente :

| | Exemple | Qui l'emploie |
|---|---|---|
| Le **module** pkg-config | `gtk+-3.0` | le code de construction |
| Le **paquet** de la distribution | `libgtk-3-dev`, `gtk3-devel` | apt, dnf |
| Le **soname** | `libgtk-3.so.0` | l'éditeur de liens, les dépendances RPM |

**On peut interroger une version** : `pkg-config --atleast-version=2.36
webkit2gtk-4.1` sort en succès ou en échec, ce qui permet à un script de
configuration d'exiger un minimum.

**`PKG_CONFIG_PATH`** ajoute des répertoires de recherche, pour une bibliothèque
installée hors des chemins système. `PKG_CONFIG_LIBDIR`, lui, les *remplace*.

**pkgconf** est une réimplémentation moderne, devenue l'implémentation par
défaut sur la plupart des distributions ; elle fournit `pkg-config` comme alias.
C'est pourquoi le paquet à installer sous Fedora s'appelle
`pkgconf-pkg-config` — nom qu'on retrouve dans la liste `dnf` du workflow
d'intégration continue.

## Dans ce projet

pkg-config n'intervient que sur **la branche Linux** d'`owebview`. macOS utilise
des frameworks système et Windows une liste fixe de bibliothèques d'import ;
ni l'un ni l'autre n'en a besoin.

`discover.ml` interroge deux modules, `gtk+-3.0` et `webkit2gtk-4.1`, à travers
l'API `C.Pkg_config` de `dune-configurator`, et distingue soigneusement deux
échecs :

- **pkg-config lui-même est absent** — sous opam il vient de `conf-pkg-config` ;
- **pkg-config est là, mais un module manque** — les paquets `-dev` n'ont pas
  été installés, ou la distribution ne fournit que `webkit2gtk-4.0`.

Ce sont deux problèmes distincts qui appellent deux corrections distinctes, et
le message d'erreur nomme le bon.

## Diagnostiquer

```sh
pkg-config --exists webkit2gtk-4.1 && echo présent || echo absent
pkg-config --modversion webkit2gtk-4.1
pkg-config --cflags --libs gtk+-3.0
pkg-config --list-all | grep -i webkit    # voir quelles variantes sont là
```

La dernière est la plus parlante quand la construction échoue sous Linux : elle
montre si la machine a `webkit2gtk-4.0`, `webkit2gtk-4.1`, les deux, ou aucune.
