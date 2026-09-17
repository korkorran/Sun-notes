# libsoup 2, libsoup 3, et la numérotation de WebKitGTK

Note de contexte pour comprendre d'où vient le `webkit2gtk-4.1` réclamé à la
compilation sous Linux — voir [compiling.md](./compiling.md).

## Ce qu'est libsoup

**libsoup** est la bibliothèque HTTP de la pile GNOME : le client réseau bâti
sur GLib et GIO. WebKitGTK s'en sert pour tout son trafic — chargement des
pages, requêtes, cookies, TLS.

## La rupture entre 2 et 3

**libsoup 3**, sortie en 2021, est une rupture d'API et d'ABI avec **libsoup 2**.
Les changements principaux :

- abandon du type maison `SoupURI` au profit du `GUri` de GLib ;
- API asynchrone refondue sur les flux GIO ;
- support HTTP/2 ;
- disparition des anciennes API synchrones.

Le point qui rend cette migration pénible est ailleurs : **les deux versions ne
peuvent pas coexister dans un même processus.** Elles exportent les mêmes
symboles `soup_*`, donc charger les deux provoque des collisions — libsoup
détecte le cas et avorte délibérément. Il n'y a pas de demi-mesure : tout ce qui
tourne dans un processus doit être d'accord sur la version.

## Pourquoi WebKitGTK a trois noms pkg-config

C'est la conséquence directe de ce qui précède. Pour que les deux variantes
soient installables en parallèle le temps que l'écosystème migre, WebKitGTK
publie plusieurs API versions :

| pkg-config | Boîte à outils | libsoup |
|---|---|---|
| `webkit2gtk-4.0` | GTK 3 | 2 |
| `webkit2gtk-4.1` | GTK 3 | 3 |
| `webkitgtk-6.0` | GTK 4 | 3 |

**`4.0` et `4.1` exposent la même API WebKit.** Le changement de numéro ne
signale aucune évolution de WebKit : il sert uniquement à dire de quelle libsoup
la bibliothèque dépend.

## Ce que cela implique pour Sun notes

`owebview` demande `webkit2gtk-4.1` à pkg-config, donc la variante libsoup 3,
apparue dans WebKitGTK 2.36 au début de 2022. C'est ce qui fixe le plancher de
distribution :

- Debian 12, Ubuntu 22.04 et les Fedora récentes conviennent ;
- Debian 11 et Ubuntu 20.04 ne fournissent que la `4.0` et sont hors jeu.

C'est aussi l'explication du `libsoup-3.0.so.0` qui apparaît dans les
dépendances du paquet `.deb` : il arrive par WebKitGTK, jamais directement par
le code de Sun notes.
