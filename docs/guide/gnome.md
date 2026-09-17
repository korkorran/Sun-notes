# GNOME, et son rapport avec GTK

Note de contexte, dans la continuité de [gtk.md](./gtk.md).

## Ce qu'est GNOME

**GNOME** désigne deux choses qu'on confond facilement.

Un **environnement de bureau**, d'abord : GNOME Shell et son compositeur Mutter,
le gestionnaire de session, les réglages, et une suite d'applications (Fichiers,
Logiciels, l'éditeur de texte…). C'est le bureau par défaut de Fedora
Workstation, de Debian, d'Ubuntu — avec des retouches — et de RHEL.

Un **projet**, ensuite : la communauté et la fondation qui développent ce bureau,
mais aussi la plateforme de développement sur laquelle il repose. GTK, GLib et
libadwaita sont maintenues sous cette bannière.

## Le rapport avec GTK

C'est une relation dans un seul sens, et c'est ce qui prête à confusion.

**GNOME est écrit avec GTK.** Le Shell, les réglages, les applications : tout
passe par la boîte à outils.

**Mais GTK ne dépend pas de GNOME.** C'est une bibliothèque généraliste — elle
s'appelait à l'origine « GIMP ToolKit », et existait avant le bureau. On peut
parfaitement écrire une application GTK qui ne touche à rien de GNOME, tourne
sous KDE, sous Windows ou sous macOS, et ignore tout des conventions du bureau.
Sun notes est exactement dans ce cas.

La séparation s'est d'ailleurs nettoyée avec GTK 4 : les widgets et le style
propres à GNOME ont quitté GTK pour **libadwaita**, bibliothèque distincte. GTK
se veut neutre, et l'apparence GNOME devient un choix explicite.

Ce qui reste couplé, c'est le calendrier : GNOME publie deux fois par an, au
printemps et à l'automne, et les versions de GTK et GLib s'alignent sur ce
rythme.

## Ce que Sun notes emprunte à GNOME

L'application n'est pas une application GNOME. Elle n'utilise ni libadwaita, ni
GSettings, ni les recommandations d'interface du projet. Elle ne touche à GTK
que parce que WebKitGTK en a besoin pour porter une fenêtre.

Elle respecte en revanche trois conventions issues de cet écosystème, et c'est
ce qui la rend présentable sur un bureau Linux — toutes trois produites par les
scripts de packaging :

**Le fichier `.desktop`**, dans `/usr/share/applications/`. C'est lui qui fait
apparaître l'application dans la vue d'ensemble, avec son nom et sa catégorie.
Son `StartupWMClass=sun-notes` permet au Shell de relier la fenêtre ouverte à
cette entrée, donc de lui donner la bonne icône.

**Les icônes dans `hicolor`**, sous `/usr/share/icons/hicolor/<taille>/apps/`.
C'est le thème de repli défini par freedesktop.org, contre lequel la clé `Icon=`
du fichier `.desktop` est résolue.

**Les métadonnées AppStream**, dans `/usr/share/metainfo/`. C'est ce que lit
**GNOME Logiciels**. Sans ce fichier, le paquet s'installe et fonctionne, mais
l'application n'y a ni description ni capture d'écran, et peut n'y pas figurer
du tout. Le paquet `.rpm` en fournit un.

Ces conventions ne sont pas propres à GNOME : elles viennent de freedesktop.org
et valent aussi pour KDE ou XFCE. GNOME en est simplement l'utilisateur le plus
visible.

## Un point qui touche au code

GNOME tourne sous **Wayland** par défaut. Or sous Wayland, il n'existe pas de
propriété `_NET_WM_ICON` à poser sur une fenêtre : le bureau résout l'icône en
rapprochant l'`app_id` du toplevel d'un fichier `.desktop` installé.

C'est la raison d'être de `Webview.set_app_id`, et la documentation d'`owebview`
le dit explicitement : sous Wayland, poser une icône sur la fenêtre ne suffit
pas, il faut que l'identifiant corresponde à une entrée `.desktop` installée.
Sous X11 le même appel fixe le `WM_CLASS`, qui joue le même rôle.

Autrement dit, l'icône d'une application Linux n'est pas dans l'application :
elle est dans le paquet.

## Pour aller plus loin

Le `packaging/README.md` évoque **Flatpak** comme la solution propre pour
distribuer une application WebKitGTK hors de la famille Debian. Le lien avec
GNOME est direct : le runtime `org.gnome.Platform` fournit GTK et WebKitGTK,
ce qui fait disparaître la question des dépendances système.
