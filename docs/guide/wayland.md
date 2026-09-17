# Wayland et X11

Note de contexte, dans la continuité de [gtk.md](./gtk.md) et
[gnome.md](./gnome.md).

## X11

**X11** est la onzième version du protocole X Window System, figée en 1987. Son
implémentation de référence sur Linux est le serveur **Xorg**.

Le modèle est client/serveur. Le serveur X détient l'écran, le clavier et la
souris ; les applications sont des clients qui lui parlent par une socket. Le
protocole étant réseau dès l'origine, un client peut tourner sur une autre
machine — c'est ce que fait `ssh -X`.

Le bureau se compose de trois pièces distinctes : le serveur X, un
**gestionnaire de fenêtres** qui décide des positions et des décorations, et,
depuis les années 2000, un **compositeur** qui assemble le résultat. Elles se
coordonnent par des conventions accumulées au fil des décennies — les propriétés
`_NET_*`, `WM_CLASS`, et le reste.

## Wayland

**Wayland** n'est pas un serveur mais un **protocole**, dont la première version
stable date de 2012. Il n'existe pas de « serveur Wayland » de référence : c'est
le **compositeur** qui l'implémente, et il réunit à lui seul les trois rôles
que X séparait. Mutter pour GNOME, KWin pour KDE, Sway, Hyprland.

Le protocole de base est volontairement minimal : il ne sait rien dessiner. Les
clients produisent eux-mêmes leur contenu dans un tampon et le remettent au
compositeur. Tout le reste — fenêtres de bureau, menus, presse-papiers — passe
par des extensions, `xdg-shell` en tête.

## Les différences qui comptent

| | X11 | Wayland |
|---|---|---|
| Nature | un protocole et son serveur (Xorg) | un protocole ; le compositeur en est l'implémentation |
| Architecture | serveur + gestionnaire de fenêtres + compositeur | un seul processus |
| Rendu | le client remet des pixmaps au serveur | le client dessine, remet un tampon |
| Isolation | un client peut lire les fenêtres des autres et capturer le clavier | chaque client ne voit que lui-même |
| Position des fenêtres | le client peut se placer et se déplacer | le client ne connaît ni ne choisit sa position |
| Capture d'écran | directe | par un portail (`xdg-desktop-portal`) |
| Réseau | transparent nativement | non ; il faut `waypipe` ou du RDP |

La différence la plus lourde de conséquences est **l'isolation**. Sous X11,
n'importe quel client peut lire le contenu des fenêtres voisines et intercepter
les frappes au clavier : un enregistreur de frappes tient en quelques lignes.
Wayland ferme cela, ce qui casse au passage tout un écosystème d'outils — capture
d'écran, partage d'écran, automatisation — qui doivent désormais passer par des
portails demandant le consentement de l'utilisateur.

La seconde est la **position des fenêtres**. Un client Wayland ne sait pas où il
est à l'écran et ne peut pas s'y déplacer. Les applications qui plaçaient leurs
propres fenêtres doivent repenser cela.

**XWayland** assure la transition : c'est un serveur X qui tourne comme client du
compositeur, et fait fonctionner les applications X11 non portées.

## Ce que cela change pour une application GTK

Rien, le plus souvent. GDK possède un backend X11 et un backend Wayland, choisis
à l'exécution ; la même binaire fonctionne sous les deux. La variable
`GDK_BACKEND` force l'un ou l'autre au besoin.

Ce qui casse, ce sont les hypothèses héritées de X : coordonnées globales,
captures d'entrées globales, et propriétés posées directement sur la fenêtre.

## Le cas de Sun notes

Deux points concrets, tous deux liés à l'icône de l'application.

`Webview.set_app_icon` pose la propriété X11 `_NET_WM_ICON`. **Cette propriété
n'existe pas sous Wayland**, où le bureau résout l'icône autrement : en
rapprochant l'`app_id` du toplevel d'un fichier `.desktop` installé. Sous
GNOME — donc sous Wayland par défaut — poser une icône sur la fenêtre ne suffit
pas ; c'est le paquet qui la fournit, comme l'explique [gnome.md](./gnome.md).

`Webview.set_app_id` est le pendant : il fixe le nom de programme GLib, qui
devient le `WM_CLASS` sous X11 et l'`app_id` sous Wayland. Un seul appel, deux
mécanismes.

## Une réserve sur les tests

Les tests de démarrage de l'intégration continue tournent sous **Xvfb**, un
serveur X virtuel sans écran. Ils s'exécutent donc sur le backend X11 de GDK,
alors que la plupart des utilisateurs seront sous Wayland.

Cette différence n'a pas d'incidence sur ce que ces tests vérifient réellement —
que les bibliothèques se résolvent et que la fenêtre se crée. Mais elle vaut
d'être connue : un défaut spécifique à Wayland ne serait pas attrapé là.
