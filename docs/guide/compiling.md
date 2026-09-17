# Compiler Sun notes — la partie native

Ce guide couvre la compilation de l'exécutable : le binaire OCaml natif, ses
stubs C++ et le moteur de rendu du système auquel il se lie. La compilation de
la page vers JavaScript sort du cadre de ce document.

## Ce qui est compilé

`run/main.exe` est un exécutable OCaml natif produit par `ocamlopt`. Il lie
quatre bibliothèques :

| Bibliothèque | Rôle |
|---|---|
| `owebview` | la fenêtre native et le pont vers la page |
| `unix` | accès au système de fichiers |
| `lwt.unix` | la boucle d'événements des appels natifs |
| `threads.posix` | donne un fil d'exécution propre à cette boucle |

`owebview` est le seul élément qui ne soit pas du pur OCaml : il embarque des
stubs C++ (`lib/webview_stubs.cpp`) construits autour d'un en-tête `webview.h`
vendoré. C'est de là que vient toute la complexité multiplateforme.

Le dernier point mérite une explication. Sous macOS, Cocoa exige que la boucle
d'interface possède le fil principal du processus. `Webview.run` le garde donc,
et la boucle Lwt part sur un fil créé pour elle — d'où la dépendance à
`threads.posix`. Un disque lent ou un montage réseau ne peut ainsi pas figer la
fenêtre.

## Un binaire, trois moteurs de rendu

Sun notes n'embarque pas de moteur de rendu : il utilise celui du système.

| Plateforme | Moteur | Fourni par |
|---|---|---|
| macOS | WKWebView (WebKit) | le système, rien à installer |
| Linux | WebKitGTK (GTK 3) | les paquets de la distribution |
| Windows | WebView2 (Edge Chromium) | le runtime Microsoft |

**Le choix se fait à la compilation, pas à l'exécution.** Un binaire construit
sur Linux contient les appels GTK et rien d'autre ; il n'y a pas de bascule au
démarrage.

## Comment le backend est choisi

`owebview` détermine sa cible dans `lib/config/discover.ml`, un script
`dune-configurator` exécuté au début de la construction. Il interroge la
variable `system` de la configuration OCaml :

```ocaml
match system with
| "macosx"  -> (* Cocoa + WebKit *)
| "mingw64" -> (* WebView2 *)
| _         -> (* GTK 3 + WebKitGTK, via pkg-config *)
```

Deux conséquences pratiques :

- **Sous Windows, seul mingw-w64 est pris en charge.** Il n'y a pas de branche
  MSVC. Un switch opam configuré pour MSVC tomberait dans la branche par
  défaut, chercherait GTK avec pkg-config et échouerait de façon déroutante.
- Toute plateforme non reconnue est traitée comme un Linux. Les BSD passent
  donc par le chemin GTK, ce qui fonctionne si les paquets sont présents.

Le résultat est écrit dans `c_flags.sexp` et `c_library_flags.sexp`, que
`lib/dune` inclut.

## Prérequis

### Communs à toutes les plateformes

- opam, avec un switch en OCaml **4.14 ou plus récent** — c'est la version qui
  a introduit `In_channel` et `Out_channel`, utilisés par les liaisons.
- dune **3.24 ou plus récent**, la version déclarée par `dune-project`. Un dune
  plus ancien refuse de construire le projet. Attention : le `dune` du switch
  ambiant est souvent plus vieux que celui du projet.
- Un compilateur C++ (`conf-c++` s'en assure).

L'installation des dépendances se fait normalement :

```sh
opam install . --deps-only
```

opam installe aussi les dépendances système lui-même, `owebview` les déclarant
en `depexts`.

### Linux

Le backend GTK est localisé avec `pkg-config`, qui doit trouver **`gtk+-3.0`**
et **`webkit2gtk-4.1`**.

| Distribution | Paquets |
|---|---|
| Debian, Ubuntu | `libgtk-3-dev`, `libwebkit2gtk-4.1-dev` |
| Fedora, RHEL | `gtk3-devel`, `webkit2gtk4.1-devel` |
| Arch | `gtk3`, `webkit2gtk-4.1` |
| Alpine | `gtk+3.0-dev`, `webkit2gtk-4.1-dev` |

Le `4.1` n'est pas un détail : c'est la série de WebKitGTK liée à **libsoup 3**,
distincte de la série `4.0` liée à libsoup 2. Elle fixe un plancher de
distribution — Debian 12, Ubuntu 22.04, ou une Fedora récente. Debian 11 et
Ubuntu 20.04 ne fournissent que la `4.0` et ne conviennent pas.

`discover.ml` distingue deux échecs qu'il serait tentant de confondre :
pkg-config absent, et pkg-config présent mais un paquet `-dev` manquant. Le
message nomme le cas réel, parce que chercher le mauvais est une perte de temps
garantie.

### macOS

Rien à installer. WebKit et Cocoa sont des frameworks système ; seuls les
*Xcode command line tools* sont nécessaires, pour le compilateur C++.

### Windows

Deux choses, et **l'ordre compte**.

D'abord une chaîne **mingw-w64**, telle que la fournit opam sous Windows.

Ensuite les en-têtes du SDK WebView2, que `webview.h` inclut via `WebView2.h`.
Cet en-tête n'est pas vendoré — sa licence interdit la redistribution — il faut
donc le récupérer auprès de Microsoft :

```sh
nuget install Microsoft.Web.WebView2
```

`discover.ml` le cherche à deux endroits, dans cet ordre :

1. la variable d'environnement `MICROSOFT_WEB_WEBVIEW2`, qui doit pointer sur le
   répertoire du paquet (l'en-tête est attendu sous `build/native/include/`) ;
2. le cache global NuGet, `%USERPROFILE%\.nuget\packages\microsoft.web.webview2\`,
   dont il retient la version la plus récente contenant réellement l'en-tête.

**Piège fréquent :** `nuget install` dépose le paquet dans le **répertoire
courant**, pas dans le cache global. Selon l'endroit d'où vous lancez la
commande, le second chemin de recherche peut donc rester vide. La façon fiable
est de désigner le répertoire explicitement :

```powershell
nuget install Microsoft.Web.WebView2 -OutputDirectory C:\sdk -ExcludeVersion
$env:MICROSOFT_WEB_WEBVIEW2 = "C:\sdk\Microsoft.Web.WebView2"
```

Et cela doit être fait **avant `opam install`**, pas avant la construction de
Sun notes : `owebview` est une dépendance, donc son `discover.ml` s'exécute — et
réclame l'en-tête — pendant l'installation des dépendances.

## Les drapeaux de liens

Ce que `discover.ml` produit, par plateforme :

**macOS** — tout vient du système, aucun pkg-config :
```
-lc++ -lobjc -framework WebKit -framework Cocoa
```

**Linux** — la sortie de pkg-config pour `gtk+-3.0` et `webkit2gtk-4.1`,
précédée de :
```
-lstdc++
```

**Windows** — aucune découverte, une liste fixe :
```
-static-libgcc -static-libstdc++ -lstdc++
-ladvapi32 -lole32 -lshell32 -lshlwapi -luser32 -lversion
-lwindowscodecs -lgdi32 -luuid
```
`windowscodecs` (WIC), `gdi32` et `uuid` sont là pour `set_app_icon`, qui décode
lui-même le fichier image et construit le `HICON`.

Le standard C++ diffère aussi : `-std=c++11` partout, sauf sous mingw où c'est
`-std=c++14`.

## Ce que le binaire traîne avec lui

C'est la différence la plus visible à la distribution.

**Linux** : GTK et WebKitGTK sont liés dynamiquement et ne sont pas embarqués.
Le binaire suppose leur présence, et c'est au paquet (`.deb`, `.rpm`) de les
déclarer.

**macOS** : les frameworks sont fournis par le système. Rien à embarquer.

**Windows** : il n'existe aucun gestionnaire de paquets pour résoudre quoi que
ce soit à l'installation, donc tout ce qui n'est pas fourni par Windows doit
voyager avec l'exécutable. Le `-lstdc++` amène `libstdc++-6.dll`, qui importe à
son tour `libgcc_s_seh-1.dll` et `libwinpthread-1.dll`. Ces deux-là
n'apparaissent **pas** dans la table d'import de l'exécutable : il faut suivre
la fermeture transitive pour les trouver.

`-static-libgcc -static-libstdc++` sont précisément là pour replier ce runtime
dans l'exécutable. Une réserve : `-static-libstdc++` est implémenté par le
pilote *g++*, qui remplace le `-lstdc++` qu'il ajoute lui-même — or OCaml lie
via le pilote C avec un `-lstdc++` explicite, donc l'option peut rester sans
effet. La vérification est directe :

```sh
objdump -p main.exe | grep 'DLL Name'
```

Si `libstdc++-6.dll` y figure encore, les trois DLL doivent accompagner le
binaire.

## Construire

```sh
opam install . --deps-only     # dépendances OCaml et système
dune build                     # profil dev
dune build --profile release   # pour distribution
dune exec run/main.exe         # construit puis lance
```

Le profil `release` retire les drapeaux de développement. Les scripts de
`packaging/` y ajoutent un `strip` du binaire — sans danger, OCaml conservant
dans ses propres sections ce dont il a besoin pour les traces d'exécution.

Si `dune` n'est pas celui du switch du projet, la construction peut échouer sur
la version de `(lang dune ...)`. Les scripts de packaging contournent cela en
préférant `_opam/bin/dune` à celui du `PATH` ; en ligne de commande, `opam exec
-- dune build` a le même effet.

Une note sur le lancement : l'exécutable cherche un répertoire `web/` **à côté
de lui**. `dune build` l'y place, et `dune exec` fonctionne donc directement ;
un binaire déplacé à la main sans ce répertoire ouvrira une fenêtre vide.

## La compilation croisée est impossible

`ocamlopt` n'a pas de `--target` : il produit du code pour sa machine hôte.

Il n'existe donc aucun moyen de construire un binaire Windows depuis Linux, ni
un binaire ARM64 depuis x86-64. Chaque combinaison plateforme/architecture exige
une machine réelle de ce type — ce qui explique la structure des workflows
d'intégration continue, où chaque paquet est construit sur un exécuteur qui lui
correspond.

## Dépannage

| Symptôme | Cause |
|---|---|
| `pkg-config was not found` | pkg-config absent ; sous opam il vient de `conf-pkg-config` |
| `could not find: gtk+-3.0 webkit2gtk-4.1` | pkg-config est là, les paquets `-dev` manquent ; ou la distribution n'a que `webkit2gtk-4.0` |
| `could not find the WebView2 SDK header` | l'étape NuGet a été oubliée, ou le paquet n'est pas là où `discover.ml` regarde — posez `MICROSOFT_WEB_WEBVIEW2` |
| Sous Windows, la construction cherche GTK | le switch n'est pas en mingw64 ; MSVC n'est pas pris en charge |
| `Version ... of dune is not supported` | le `dune` du `PATH` est plus ancien que celui du projet |
| Fenêtre vide au démarrage sous Windows | le runtime WebView2 est absent de la machine |
| Fenêtre vide après avoir déplacé le binaire | le répertoire `web/` ne l'a pas suivi |
