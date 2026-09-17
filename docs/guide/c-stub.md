# Compiler un stub C/C++ avec dune

Note de contexte, dans la continuité de [c-flags.md](./c-flags.md). Les exemples
sont tirés d'`owebview`, qui enveloppe la bibliothèque C `webview`.

## Ce qu'est un stub

Un **stub** est la colle entre OCaml et une bibliothèque C. OCaml ne sait pas
appeler `webview_create` directement : il faut une fonction C intermédiaire qui
traduise les valeurs OCaml en valeurs C, appelle la bibliothèque, et retraduise
le résultat.

Cette colle se compile avec le projet et se retrouve liée dans tout exécutable
qui utilise la bibliothèque.

## Le côté OCaml : `external`

```ocaml
external create : bool -> t = "ocaml_webview_create"
```

La chaîne est le **nom du symbole C** à appeler. C'est tout : aucun en-tête,
aucune déclaration partagée. Le lien se fait au moment de l'édition de liens, et
une faute de frappe ne se manifeste qu'à ce moment-là.

Deux variantes utiles : au-delà de cinq arguments il faut donner deux noms — un
pour le bytecode, un pour le natif — et l'attribut `[@@noalloc]` promet que la
fonction n'alloue pas, ce qui permet un appel plus direct.

## Le côté C : la fonction

```c
CAMLprim value ocaml_webview_create(value vdebug) {
  CAMLparam1(vdebug);
  webview_t w = webview_create(Bool_val(vdebug), nullptr);
  if (w == nullptr)
    caml_failwith("webview_create returned NULL");
  CAMLreturn(val_of_wv(w));
}
```

Trois éléments de la convention OCaml :

- **`value`** est le type universel des valeurs OCaml. Les macros `Bool_val`,
  `Int_val`, `String_val` en extraient le contenu.
- **`CAMLparam` / `CAMLreturn`** déclarent les racines au ramasse-miettes. Elles
  sont obligatoires dès que la fonction alloue, faute de quoi le GC peut
  déplacer une valeur encore utilisée. Ce n'est pas une formalité.
- **`#define CAML_NAME_SPACE`** avant les en-têtes `caml/` restreint les
  définitions aux noms préfixés, et évite de polluer l'espace de noms.

## Le piège du C++ : la décoration des symboles

C'est le point qui surprend, et qui ne se manifeste qu'à l'édition de liens.

`CAMLprim` **n'ajoute rien** : dans `caml/misc.h`, la macro est définie vide.
Elle ne pose pas d'`extern "C"`. Compilé en C++, le symbole
`ocaml_webview_create` serait donc décoré, et l'OCaml qui cherche exactement ce
nom ne le trouverait pas.

La parade est explicite. Dans `webview_stubs.cpp`, toutes les fonctions
exportées sont enfermées dans un bloc :

```cpp
extern "C" {

CAMLprim value ocaml_webview_create(value vdebug) { /* … */ }
/* … toutes les autres … */

} /* extern "C" */
```

La vérification est immédiate sur l'archive compilée :

```sh
nm -g libwebview_stubs.a | grep ocaml_webview_create
# 0000000000000028 T _ocaml_webview_create
```

Le nom est nu — le tiret bas initial est le préfixe de symboles de macOS, pas de
la décoration C++. Si vous y lisiez quelque chose comme
`__Z19ocaml_webview_create5value`, c'est que l'`extern "C"` manque.

## Le côté dune : `foreign_stubs`

```lisp
(library
 (name webview)
 (public_name owebview)
 (foreign_stubs
  (language cxx)
  (names webview_stubs)
  (extra_deps %{workspace_root}/vendor/webview.h)
  (flags
   (:standard -I ../vendor (:include c_flags.sexp))))
 (c_library_flags (:include c_library_flags.sexp)))
```

Champ par champ :

**`(language c)` ou `(language cxx)`** choisit le compilateur et l'extension
attendue — `.c` ou `.cpp`.

**`(names …)`** liste les fichiers sans leur extension.

**`(flags …)`** donne les drapeaux de compilation. `(:standard)` conserve ceux
que dune ajoute de lui-même.

**`(extra_deps …)`** est essentiel et facile à oublier. Dune construit dans un
bac à sable où seules les dépendances déclarées sont présentes. Un en-tête que
le stub inclut mais que dune ne produit pas doit être déclaré, sans quoi la
construction échoue — parfois seulement sur une autre machine, selon la
rigueur du bac à sable. Ici, `vendor/webview.h` est vendoré et doit être copié
dans l'arbre de construction.

**`(c_library_flags …)`** donne les drapeaux d'édition de liens, et se propage à
tout exécutable liant la bibliothèque.

## Les chemins sont relatifs à l'arbre de construction

`-I ../vendor` ne désigne pas l'arbre source. Dune y recopie les fichiers sous
`_build/default/`, et c'est là que le stub est compilé. Le chemin est donc
relatif à `_build/default/lib/`.

C'est la seconde raison d'être d'`extra_deps` : sans elle, le répertoire
`../vendor` existerait dans les sources mais pas dans l'arbre de construction.

## Les drapeaux générés

`(:include fichier.sexp)` demande à dune de lire une liste de drapeaux dans un
fichier produit par une règle. C'est le mécanisme qui permet de calculer les
drapeaux à la construction — voir [c-flags.md](./c-flags.md) pour ce que fait
`discover.ml`.

## Ce que dune produit

Une archive statique, `libwebview_stubs.a`, posée à côté des artefacts OCaml et
installée dans le switch :

```sh
ls _opam/lib/owebview/
# libwebview_stubs.a  webview.a  webview.cma  webview.cmxa  …
```

Quand un exécutable lie la bibliothèque, dune lie cette archive **et** ajoute
les `c_library_flags`. C'est ainsi que le binaire de Sun notes se retrouve lié à
GTK et WebKitGTK sans que son propre `dune` les mentionne.

## Le C++ n'amène pas sa bibliothèque standard

OCaml édite les liens avec le pilote **C**, qui n'ajoute aucune bibliothèque
standard C++. Un stub en C++ doit donc la réclamer lui-même dans
`c_library_flags` : `-lstdc++` avec GNU, `-lc++` avec LLVM. C'est détaillé dans
[c-flags.md](./c-flags.md).

## Diagnostiquer

| Symptôme | Cause probable |
|---|---|
| `undefined symbol: ocaml_…` à l'édition de liens | `extern "C"` manquant, ou désaccord entre la chaîne de l'`external` et le nom C |
| En-tête introuvable alors qu'il est dans les sources | `extra_deps` manquant, ou chemin `-I` relatif à l'arbre source au lieu de `_build` |
| Erreurs de symboles C++ (`std::…`) à l'édition de liens | la bibliothèque standard C++ n'est pas dans `c_library_flags` |
| Segfault au ramasse-miettes | `CAMLparam` / `CAMLreturn` oubliés dans une fonction qui alloue |

Deux commandes qui font gagner du temps :

```sh
dune build --verbose          # les lignes de commande réelles du compilateur
nm -g _build/default/lib/libwebview_stubs.a | grep ocaml_
```
