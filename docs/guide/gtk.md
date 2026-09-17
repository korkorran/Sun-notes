# GTK, et ce qui sépare GTK 3 de GTK 4

Note de contexte pour comprendre pourquoi la compilation sous Linux réclame
`gtk+-3.0` — voir [compiling.md](./compiling.md) et [libsoup.md](./libsoup.md).

## Ce qu'est GTK

**GTK** est une bibliothèque de composants d'interface graphique écrite en C,
multiplateforme, sous licence LGPL. C'est la brique sur laquelle repose GNOME,
et l'une des deux grandes boîtes à outils du bureau Linux avec Qt.

Elle n'est pas seule : elle s'appuie sur une pile de bibliothèques qui reviennent
souvent dans les messages d'erreur et les dépendances de paquets.

| Bibliothèque | Rôle |
|---|---|
| **GLib** | les fondations non graphiques : système objet (GObject), boucle d'événements, structures de données |
| **GDK** | l'abstraction du système de fenêtrage : X11, Wayland, Windows, macOS |
| **Pango** | la mise en forme et le rendu du texte |
| **Cairo** | le dessin vectoriel 2D |
| **GdkPixbuf** | le chargement et la manipulation d'images |

Pour ce projet, GTK intervient d'une seule façon : **WebKitGTK est le portage de
WebKit sur GTK**. C'est lui qui fournit le moteur de rendu, et il a donc besoin
de GTK pour exister dans une fenêtre.

## GTK 3 et GTK 4

GTK 4 est sortie fin 2020. Ce n'est pas une mise à jour mais une rupture : le
passage de l'une à l'autre est un portage, pas une montée de version.

**Le rendu.** GTK 3 dessine avec Cairo, sur le processeur : chaque widget répond
à un signal `draw` et peint son contenu. GTK 4 introduit **GSK**, qui construit
un graphe de scène de nœuds de rendu confié à un moteur OpenGL ou Vulkan. Les
widgets ne dessinent plus, ils décrivent.

**Le modèle de widgets.** `GtkContainer` disparaît en GTK 4 : tout widget peut
avoir des enfants, et le placement est délégué à un `GtkLayoutManager`. Les
« propriétés d'enfant » de GTK 3 — le remplissage et l'expansion réglés sur le
parent — sont supprimées au profit de propriétés portées par le widget lui-même.

**Les événements.** GTK 3 exposait des signaux bas niveau (`button-press-event`
et compagnie). GTK 4 les remplace par des **contrôleurs d'événements** et des
gestes constitués en objets à part entière, attachés à un widget.

**Les listes.** Le couple `GtkTreeView` / `GtkTreeModel`, coûteux sur de grands
volumes, cède la place à `GtkListView` et `GtkColumnView`, adossés à `GListModel`
et capables de ne matérialiser que les lignes visibles.

**L'accessibilité** est réécrite autour de rôles proches d'ARIA, sans passer par
ATK.

**Le périmètre.** Un certain nombre de widgets propres au style GNOME sortent de
GTK 4 pour rejoindre **libadwaita**, bibliothèque distincte. GTK 4 vise à être
plus neutre, quitte à ce que l'apparence GNOME soit un choix explicite.

## Pourquoi Sun notes est en GTK 3

Ce n'est pas un choix direct, mais une conséquence.

`owebview` demande deux paquets à pkg-config sous Linux : `gtk+-3.0` et
`webkit2gtk-4.1`. Le second impose le premier — `webkit2gtk-4.1` est la variante
de WebKitGTK bâtie sur **GTK 3** (et sur libsoup 3, d'où son nom ; voir
[libsoup.md](./libsoup.md)).

Passer à GTK 4 ne se réduirait donc pas à changer une dépendance : il faudrait
viser `webkitgtk-6.0`, le nom pkg-config de la variante GTK 4, ce qui remonterait
encore le plancher de distribution. Rien ne le justifie tant que le seul usage de
GTK est de porter une fenêtre.

Concrètement, cela se lit dans les paquets produits :

- les `depexts` réclament `libgtk-3-dev` (Debian) ou `gtk3-devel` (Fedora) ;
- le `.deb` dépend de `libgtk-3-0`, et le `.rpm` du soname `libgtk-3.so.0`.

## Un détail qui affleure dans le code

`Webview.set_app_id` est une fonction GTK déguisée : elle appelle
`g_set_prgname`, qui devient le nom de classe `WM_CLASS` sous X11 et l'`app_id`
du toplevel sous Wayland. C'est par cet identifiant que le bureau relie une
fenêtre à un fichier `.desktop` installé, donc à une icône.

D'où la ligne `StartupWMClass=sun-notes` dans les entrées `.desktop` que génèrent
les scripts de packaging : sans elle, le lanceur ne fait pas le lien entre la
fenêtre ouverte et l'application installée.
