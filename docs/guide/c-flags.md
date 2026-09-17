# Les drapeaux de compilation et de liens d'owebview

Note de contexte, dans la continuité de [compiling.md](./compiling.md).

`owebview` n'est pas du pur OCaml : elle embarque un stub C++
(`lib/webview_stubs.cpp`) bâti autour d'un en-tête `webview.h` vendoré. Ce stub
doit être compilé, puis lié au moteur de rendu du système. Les drapeaux
nécessaires diffèrent radicalement d'une plateforme à l'autre, et sont donc
calculés à la construction plutôt qu'écrits en dur.

## Deux fichiers, deux rôles

La distinction est importante et revient partout ensuite :

| Fichier | Rôle | Concerne |
|---|---|---|
| `c_flags.sexp` | drapeaux de **compilation** du stub C++ | la construction d'owebview seulement |
| `c_library_flags.sexp` | drapeaux d'**édition de liens** | **tout exécutable** qui lie owebview |

Le second est le plus lourd de conséquences : il se propage. Un binaire qui lie
`owebview` — celui de Sun notes, par exemple — hérite de ces drapeaux sans les
déclarer nulle part. C'est ainsi qu'il finit par dépendre de GTK et de WebKitGTK
alors que son `dune` ne mentionne que `owebview`.

## Comment dune les branche

Dans `lib/dune`, une règle produit les deux fichiers en exécutant le script de
configuration, et la bibliothèque les inclut :

```lisp
(library
 (name webview)
 (foreign_stubs
  (language cxx)
  (names webview_stubs)
  (flags (:standard -I ../vendor (:include c_flags.sexp))))
 (c_library_flags (:include c_library_flags.sexp)))

(rule
 (targets c_flags.sexp c_library_flags.sexp)
 (deps (:discover config/discover.exe))
 (action (run %{discover})))
```

`(:include …)` est le mécanisme qui permet à dune de lire une liste de drapeaux
depuis un fichier généré, plutôt que de l'avoir dans le `dune`.

## Comment ils sont produits

`lib/config/discover.ml` est un programme `dune-configurator`. Il interroge la
variable `system` de la configuration OCaml et choisit une branche :

```ocaml
match system with
| "macosx"  -> (std_flags, macos_link_flags)
| "mingw64" -> (* en-têtes WebView2 + drapeaux mingw *)
| _         -> (* GTK via pkg-config *)
```

Puis il écrit les deux `.sexp`. Rien n'est décidé à l'exécution.

## macOS

**Compilation** : `-std=c++11`

**Liens** :

| Drapeau | Ce qu'il apporte |
|---|---|
| `-lc++` | la bibliothèque standard C++ de LLVM, requise par le stub |
| `-lobjc` | le runtime Objective-C, les API Cocoa étant en Objective-C |
| `-framework WebKit` | WKWebView, le moteur de rendu |
| `-framework Cocoa` | la fenêtre, le menu, la boucle d'interface |

Aucune découverte n'est nécessaire : ce sont des frameworks système, présents
sur toute machine.

## Linux

**Compilation** : `-std=c++11`, suivi de la sortie de
`pkg-config --cflags gtk+-3.0 webkit2gtk-4.1`.

**Liens** : `-lstdc++`, suivi de `pkg-config --libs` pour les mêmes paquets.

C'est la seule plateforme où la liste n'est pas fixe : elle est **découverte**.
`discover.ml` distingue d'ailleurs deux échecs qu'on confond volontiers —
pkg-config absent, et pkg-config présent mais un paquet `-dev` manquant — parce
que chercher le mauvais coûte du temps.

La sortie de pkg-config est longue : au-delà de `-lgtk-3` et
`-lwebkit2gtk-4.1`, elle amène GLib, GObject, GIO, Pango, Cairo, GdkPixbuf et
les chemins d'en-têtes correspondants.

## Windows (mingw64)

**Compilation** : `-isystem <répertoire des en-têtes WebView2>` puis
`-std=c++14`.

Deux choses à noter. Le chemin des en-têtes est **découvert** — via
`MICROSOFT_WEB_WEBVIEW2` ou le cache NuGet — et c'est le seul élément variable
de cette branche. Et le standard C++ y est **14**, non 11 : `mingw_flags`
remplace `std_flags` au lieu de s'y ajouter.

**Liens** — une liste fixe :

| Drapeau | Ce qu'il apporte |
|---|---|
| `-static-libgcc`, `-static-libstdc++` | repli du runtime GCC dans l'exécutable (voir plus bas) |
| `-lstdc++` | la bibliothèque standard C++ de GNU |
| `-ladvapi32` | l'accès au registre |
| `-lole32` | COM — l'API WebView2 est une API COM |
| `-lshell32`, `-lshlwapi` | les chemins et utilitaires du shell |
| `-luser32` | les fenêtres, les messages, les entrées |
| `-lversion` | la lecture des informations de version de fichiers |
| `-lwindowscodecs` | WIC, le décodage d'images |
| `-lgdi32` | la construction du `HICON` |
| `-luuid` | les constantes GUID des interfaces COM |

Les trois derniers sont attribués explicitement par le commentaire d'owebview à
`set_app_icon`, qui décode lui-même le fichier image et construit l'icône.

## Pourquoi `-lc++` ici et `-lstdc++` là

Le stub est du C++, il lui faut donc une bibliothèque standard C++. Or OCaml
édite les liens avec le pilote **C**, qui ne l'ajoute pas de lui-même : il faut
la demander.

Laquelle dépend de la chaîne d'outils. `libc++` est l'implémentation de LLVM,
celle de macOS ; `libstdc++` est celle de GNU, utilisée sous Linux et sous
mingw. D'où deux drapeaux pour un même rôle.

## Les deux drapeaux statiques de Windows

`-static-libgcc` et `-static-libstdc++` replient le runtime GCC dans
l'exécutable, au lieu de le laisser chercher `libgcc_s_seh-1.dll`,
`libstdc++-6.dll` et `libwinpthread-1.dll` à côté de lui au démarrage. Sans eux,
un programme liant cette bibliothèque n'est pas redistribuable seul : il
fonctionne sur la machine qui l'a construit, où le `bin/` de la chaîne d'outils
est dans le `PATH`, et nulle part ailleurs.

Une réserve, consignée dans le code : `-static-libstdc++` est implémenté par le
pilote **g++**, qui remplace le `-lstdc++` qu'il ajoute lui-même. OCaml liant
par le pilote C avec un `-lstdc++` explicite, l'option peut rester sans effet.
`-static-libgcc`, lui, est traité par le pilote commun et prend bien.

La vérification est directe :

```sh
objdump -p monbinaire.exe | grep 'DLL Name'
```

Si `libstdc++-6.dll` y figure encore, remplacer `-lstdc++` par
`-l:libstdc++.a` est la correction suivante.

## Inspecter ce qui a été produit

Les deux fichiers sont lisibles après une construction :

```sh
cat _build/default/lib/c_flags.sexp
cat _build/default/lib/c_library_flags.sexp
```

C'est le premier réflexe utile quand une édition de liens échoue : il montre ce
que `discover.ml` a réellement décidé, au lieu de ce qu'on croit qu'il a décidé.

## Ce que cela entraîne en aval

Parce que `c_library_flags` se propage à tout exécutable liant owebview, ces
drapeaux déterminent les dépendances des paquets construits.

Sous Linux, les `.so` de GTK et WebKitGTK deviennent des dépendances déclarées
du `.deb` — où `dpkg-shlibdeps` les traduit en noms de paquets — et du `.rpm`,
où le générateur automatique les traduit en sonames. Sous Windows, les DLL du
runtime doivent voyager dans l'installateur. Sous macOS, rien : les frameworks
sont fournis par le système.
