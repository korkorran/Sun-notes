# owebview et les autres façons de faire une interface en OCaml

Note de contexte. Ce document situe le choix fait par Sun notes ; il ne cherche
pas à désigner un vainqueur. Les versions citées sont celles du dépôt opam au
moment de la rédaction.

## Trois approches, avant trois bibliothèques

La distinction qui compte n'est pas entre les bibliothèques mais entre les
manières d'obtenir des pixels à l'écran. Tout le reste en découle.

**Widgets natifs.** La bibliothèque enveloppe la boîte à outils du bureau. On
hérite de son apparence, de ses dialogues, de son accessibilité — et de ses
dépendances. C'est `lablgtk3`.

**Widgets dessinés.** La bibliothèque peint elle-même chaque contrôle sur une
surface. L'apparence est identique partout et ne dépend de rien, mais tout ce
que le bureau offrait est à réimplémenter. C'est `bogue`, `imguiml`, `raylib`.

**Moteur web embarqué.** Une fenêtre native héberge le moteur web du système,
qui affiche une page. L'interface s'écrit en HTML et CSS. C'est `owebview`.

## owebview

> `0.1.0` · MIT · [korkorran/Owebview](https://github.com/korkorran/Owebview)

Liaisons OCaml vers la bibliothèque C `webview`. Une fenêtre native abrite
WKWebView sur macOS, WebKitGTK sur Linux, WebView2 sur Windows, et un pont
permet aux deux côtés de s'appeler.

L'interface s'écrit donc en HTML, CSS et JavaScript — mais avec js_of_ocaml on
reste en OCaml des deux côtés, ce que fait Sun notes en s'appuyant sur `vdom`.

**Ce qu'on y gagne.** Un moteur de rendu, de mise en page et de composition de
texte d'une maturité qu'aucune bibliothèque OCaml ne peut approcher : styles,
polices, internationalisation, sélection, défilement. Le binaire reste petit,
puisque le moteur appartient au système.

**Ce qu'on y perd.** Le moteur doit être présent, et ce n'est pas le même
partout : trois implémentations, donc trois comportements à tester. Le pont est
asynchrone et transite par des chaînes, ce qui interdit de passer des valeurs
OCaml directement. L'empreinte mémoire est celle d'un navigateur. Et sous
Windows, le runtime WebView2 peut manquer — c'est pourquoi l'installateur du
projet va le chercher.

La bibliothèque est par ailleurs jeune et portée par une seule personne, ce qui
se pèse quand on choisit une fondation.

## lablgtk3

> `3.1.5-1` · LGPL-2.1+ avec exception de liaison ·
> [garrigue/lablgtk](https://github.com/garrigue/lablgtk)

Les liaisons OCaml historiques vers GTK 3. L'API est orientée objet et reproduit
fidèlement la hiérarchie de classes de GTK.

**Ce qu'on y gagne.** De vrais widgets natifs, avec ce que cela implique :
dialogues du système, accessibilité, méthodes de saisie, thèmes du bureau. Une
maturité considérable — CoqIDE s'appuie dessus depuis des années.

**Ce qu'on y perd.** GTK 3 uniquement ; il n'existe pas de liaison GTK 4
comparable. Les paquets de développement GTK sont nécessaires à la compilation
comme à l'exécution, et la livraison hors Linux est ingrate : GTK fonctionne sur
Windows et macOS, mais lourdement et sans y avoir l'air natif. Enfin l'API est
celle de GTK, transposée — impérative, à base de signaux, éloignée de ce qu'on
écrirait en OCaml.

## Bogue

> `20260208` · ISC · [sanette/bogue](https://github.com/sanette/bogue)

Une bibliothèque d'interface écrite en OCaml, qui dessine ses propres widgets
au-dessus de SDL2 (`tsdl`, `tsdl-image`, `tsdl-ttf`). Elle apporte son système
de disposition, d'événements et d'animations.

**Ce qu'on y gagne.** Une API pensée pour OCaml, et non traduite d'une
bibliothèque C. Une seule dépendance système, SDL2, facile à embarquer partout.
Une apparence identique sur les trois plateformes. Le numéro de version, daté,
signale un développement actif.

**Ce qu'on y perd.** L'apparence n'est pas native et ne le sera pas. Tout ce que
le bureau fournissait — accessibilité, méthodes de saisie complexes, dialogues
de fichiers du système — est absent ou limité. Le catalogue de widgets est plus
restreint que celui de GTK, et le rendu du texte passe par SDL_ttf.

## Les autres, présentes dans opam

| Paquet | Version | Nature |
|---|---|---|
| `lablqml` | 0.7 | Qt / QML, via une extension ppx |
| `labltk` | 8.06.15 | Tcl/Tk — historique, à réserver à l'existant |
| `camlkit-gui` | 0.3.0 | AppKit et frameworks Cocoa ; **macOS uniquement** |
| `imguiml` | v1.90.6 | Dear ImGui, mode immédiat — outils et panneaux de débogage |
| `raylib` | 2.2.2 | orientée jeu, dessin direct |
| `tsdl` | 1.3.0 | SDL2 nu, si l'on veut tout dessiner soi-même |
| `ocaml-canvas` | 1.0.0 | une surface de dessin, sans widgets |
| `nottui` | 0.5 | interface **en terminal**, sur Notty et Lwd |

`nottui` sort du cadre, mais mérite d'être citée : pour bien des outils, une
interface en terminal règle le problème sans aucune des difficultés ci-dessus.

## Comparaison

| | owebview | lablgtk3 | bogue |
|---|---|---|---|
| Rendu | moteur web du système | widgets natifs GTK | dessinés sur SDL2 |
| Apparence | celle de votre CSS | celle du bureau | la sienne, partout |
| Interface écrite en | HTML/CSS (+ js_of_ocaml) | OCaml, API GTK | OCaml |
| Dépendance système | WebKit / WebKitGTK / WebView2 | GTK 3 | SDL2 |
| Présente par défaut | macOS, Windows 11 ; à installer sous Linux | rarement | non, mais facile à embarquer |
| Accessibilité | celle du moteur web | celle de GTK | limitée |
| Livraison multiplateforme | un moteur différent par système | pénible hors Linux | homogène |
| Maturité | jeune | très mûre | active |

## Pourquoi Sun notes utilise owebview

L'application est un éditeur de notes : son cœur est l'affichage et l'édition de
texte. C'est précisément le domaine où un moteur web a des décennies d'avance
sur ce qu'on réimplémenterait — sélection, curseur, polices, retour à la ligne,
écritures non latines. Et js_of_ocaml permet que toute l'interface reste en
OCaml malgré le détour par le HTML.

Le prix est exactement ce que décrit `packaging/README.md` : trois moteurs,
trois stratégies d'empaquetage, et la question du runtime WebView2 sous Windows.

## Comment choisir

- **Un outil qui doit se fondre dans le bureau Linux**, avec dialogues système et
  accessibilité : `lablgtk3`.
- **Une application livrée partout de façon identique**, sans dépendance lourde,
  dont l'apparence vous appartient : `bogue`.
- **Une interface riche en texte ou en mise en page**, où l'on accepte de payer
  la disparité des moteurs pour hériter du rendu web : `owebview`.
- **Un outil pour développeurs, ou un panneau de réglages dans un jeu** :
  `imguiml`.
- **Un outil en ligne de commande qui gagnerait à être interactif** : `nottui`,
  avant d'ouvrir une fenêtre.
