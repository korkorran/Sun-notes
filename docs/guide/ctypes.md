# ctypes, et les autres façons de lier du C depuis OCaml

Note de contexte, dans la continuité de [c-stub.md](./c-stub.md), qui décrit la
solution retenue par `owebview`. Ce document situe les alternatives et explique
pourquoi elles n'ont pas été choisies ici.

## Trois familles

### 1. Le stub écrit à la main

`external` côté OCaml, une fonction C côté natif, `foreign_stubs` dans dune.

Contrôle total, aucune dépendance supplémentaire — mais c'est du C à écrire et à
maintenir, avec les règles du ramasse-miettes à respecter. C'est l'approche
d'`owebview`, détaillée dans [c-stub.md](./c-stub.md).

### 2. ctypes — décrire l'API en OCaml plutôt que l'écrire en C

Avec **ctypes**, on décrit la signature C *en OCaml*, et la bibliothèque prend en
charge la conversion des valeurs :

```ocaml
let webview_create =
  foreign "webview_create" (bool @-> ptr void @-> returning (ptr void))
```

Deux modes existent, et la différence entre eux est structurante.

**Liaison dynamique** (`ctypes.foreign`). Les symboles sont résolus à
l'exécution par `dlopen`/`dlsym`, à travers libffi. **Aucun code C n'est
compilé.** C'est le plus rapide à mettre en place, mais chaque appel traverse
libffi, et surtout rien ne confronte votre description au véritable en-tête :
une signature erronée devient un plantage à l'exécution.

**Génération de stubs** (`cstubs`). La même description alimente un programme
générateur qui émet le code C *et* le code OCaml, compilés normalement ensuite.
On retrouve la vitesse d'un stub écrit à la main, et le compilateur C vérifie la
description contre l'en-tête réel. C'est le mode à privilégier dès que le projet
est sérieux. Dune sait l'automatiser avec une strophe `(ctypes …)`, à activer par
un `(using ctypes …)` dans `dune-project`.

### 3. `foreign_archives` — quand le code natif vient d'ailleurs

Ce n'est pas une alternative aux stubs mais à leur empaquetage. Si le code natif
est volumineux, partagé entre plusieurs bibliothèques, ou produit par un `make`
ou un CMake externe, on le construit à part et on le lie :

```lisp
(foreign_library
 (archive_name mylib)
 (language c)
 (names a b c))

(library
 (name wrapper)
 (foreign_archives mylib))
```

Utile également pour lier une bibliothèque déjà compilée qu'on ne souhaite pas
reconstruire.

## Comparaison

| | Stub manuel | ctypes dynamique | ctypes + cstubs |
|---|---|---|---|
| Code C à écrire | oui | non | non |
| Compilation C | oui | non | oui (générée) |
| Coût par appel | minimal | libffi | minimal |
| Vérifié contre l'en-tête | oui | **non** | oui |
| Dépendances ajoutées | aucune | ctypes, libffi | ctypes |

## Pourquoi owebview n'utilise pas ctypes

Deux raisons, et la première est dirimante.

**ctypes lie du C, pas du C++.** Une API C++ exige de toute façon une couche C
intermédiaire. Or `vendor/webview.h` est un en-tête unique qui fournit l'API C
**et son implémentation** : il faut bien une unité de traduction compilée en C++
quelque part. Le stub n'aurait pas disparu, il aurait seulement rétréci.

**Le pont rappelle OCaml.** Les liaisons ne se contentent pas d'appeler du C :
la page invoque des fonctions OCaml à travers la webview, donc le code natif
doit appeler `caml_callback` et gérer les racines du ramasse-miettes. C'est
faisable avec ctypes, mais nettement plus pénible qu'en C direct.

Le stub écrit à la main reste donc le bon choix ici.

## Quand ctypes s'impose

À l'inverse, ctypes prend tout son sens sur une **grosse API C, stable et
purement descendante** — SQLite, libcurl, une bibliothèque système. Là où il
faudrait écrire et maintenir des centaines de fonctions répétitives, une
description déclarative est bien plus économique, et le mode `cstubs` ne coûte
rien à l'exécution.

## Une voie intermédiaire

**`ppx_cstubs`** permet d'écrire les fragments C directement dans le fichier
OCaml et les extrait à la compilation. C'est un compromis élégant entre les deux
approches, mais moins répandu — à peser contre le fait d'ajouter une dépendance
de plus à la chaîne de construction.
