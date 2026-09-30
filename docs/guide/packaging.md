# Empaqueter Sun notes pour Debian et pour Fedora

Note de contexte, dans la continuité de [compiling.md](./compiling.md). Ce
guide explique **comment** les deux formats résolvent le même problème et en
quoi ils diffèrent. Pour l'usage des scripts — options, prérequis, intégration
continue — voir [`packaging/README.md`](../../packaging/README.md).

## Le même problème, deux réponses

Un paquet doit poser quatre choses aux bons endroits : l'exécutable, ses
ressources web, une entrée de menu, une icône. Et surtout, il doit **déclarer ce
dont l'application a besoin** pour que le gestionnaire de paquets l'installe
avec elle.

C'est sur ce dernier point que les deux formats divergent le plus.

## La contrainte qui façonne la disposition

`Webview.Utils.web_dir` cherche un répertoire `web/` **à côté du binaire**. Or
aucune des deux distributions n'accepte des fichiers HTML dans `/usr/bin`, qui
est réservé aux exécutables.

La solution est la même des deux côtés — binaire et ressources ensemble dans un
répertoire privé, plus un lien symbolique dans le `PATH` — mais le répertoire
privé n'est pas au même endroit :

| | Debian | RPM |
|---|---|---|
| Binaire et ressources | `/usr/lib/sun-notes/` | `/usr/libexec/sun-notes/` |
| Lanceur | `/usr/bin/sun-notes` → `../lib/sun-notes/sun-notes` | `/usr/bin/sun-notes` → `../libexec/sun-notes/sun-notes` |

Cela fonctionne parce qu'OCaml résout `Sys.executable_name` à travers
`/proc/self/exe`, qui suit le lien : `exe_dir ()` renvoie le répertoire réel,
quelle que soit la façon dont le programme a été invoqué.

Côté RPM, le chemin n'est pas écrit en dur : le script interroge
`rpm --eval %{_libexecdir}`, et calcule le lien relatif avec
`realpath --relative-to`. Le nombre de `..` entre `_bindir` et `_libexecdir`
n'est pas quelque chose à supposer.

## Deux mots de vocabulaire : ELF et soname

Les deux formats reposent sur la même source de vérité — le binaire lui-même —
et le vocabulaire revient partout dans ce qui suit.

### ELF

**ELF** (*Executable and Linkable Format*) est le format des exécutables, des
bibliothèques partagées et des fichiers objets sous Linux. C'est un format
propre à cette famille de systèmes : macOS utilise Mach-O, Windows utilise PE.

Un fichier ELF ne contient pas que du code. Il porte aussi une table de
métadonnées où figurent l'architecture visée et, surtout, la liste des
bibliothèques partagées dont il aura besoin à l'exécution — les entrées
`DT_NEEDED` :

```sh
readelf -d /usr/lib/sun-notes/sun-notes | grep NEEDED
#  0x0000000000000001 (NEEDED)  Shared library: [libwebkit2gtk-4.1.so.0]
#  0x0000000000000001 (NEEDED)  Shared library: [libgtk-3.so.0]
#  …
```

C'est cette table que lisent les outils d'empaquetage. Ils ne devinent rien : la
liste des dépendances est déjà dans le binaire, il ne reste qu'à la traduire.

### soname

Un **soname** (*shared object name*) est le nom qu'une bibliothèque partagée
déclare pour elle-même, inscrit dans le fichier. Ce n'est pas son nom de
fichier : `libwebkit2gtk-4.1.so.0.9.2` déclare le soname
`libwebkit2gtk-4.1.so.0`.

Le numéro qui suit `.so.` est la **version d'ABI**. Il ne change que lorsque la
bibliothèque rompt la compatibilité binaire — une correction de bogue ou une
nouvelle version mineure le laissent intact. C'est ce qui permet à l'éditeur de
liens dynamique de trouver au démarrage une version compatible, quelle que soit
la version exacte installée.

Les entrées `DT_NEEDED` d'un exécutable contiennent donc des sonames, pas des
chemins ni des noms de paquets. Toute la différence entre les deux formats tient
à ce qu'ils en font ensuite.

Côté RPM, le soname apparaît tel quel dans les dépendances, avec deux suffixes
qui déroutent à la première lecture :

```
libwebkit2gtk-4.1.so.0()(64bit)
```

Les parenthèses vides signalent l'absence d'exigence sur les versions de
symboles, et `(64bit)` la classe du fichier ELF — pour qu'une dépendance 32 bits
et son équivalent 64 bits ne se confondent pas.

## Les dépendances : traduire tout de suite ou plus tard

C'est la différence de fond. Les deux formats partent du même endroit — les
`DT_NEEDED` du binaire — mais l'un les traduit à la construction, l'autre laisse
le gestionnaire de paquets s'en charger à l'installation.

### Debian déclare

Un `.deb` nomme des **paquets** dans son champ `Depends:`. Le script ne les
écrit pas à la main : il appelle `dpkg-shlibdeps`, qui lit l'ELF, associe chaque
entrée `DT_NEEDED` au paquet qui la fournit, et déduit la version minimale des
symboles réellement utilisés. Résultat :

```
Depends: libc6 (>= 2.35), libgcc-s1 (>= 3.0), libglib2.0-0 (>= 2.12.0),
         libgtk-3-0 (>= 3.9.10), libjavascriptcoregtk-4.1-0,
         libstdc++6 (>= 11), libwebkit2gtk-4.1-0 (>= 2.39.90)
```

Cela inclut le plancher glibc, déduit de la machine qui construit — un point sur
lequel nous revenons plus bas.

Comment `dpkg-shlibdeps` connaît-il le paquet qui fournit un soname ? Par une
**table de correspondance locale** : les fichiers `symbols` et `shlibs` que
chaque paquet `-dev` installe sous `/var/lib/dpkg/info/`. La traduction a donc
lieu sur la machine de construction, et elle exige que les paquets de
développement y soient présents — sans quoi elle échoue.

Une liste écrite à la main sert de repli si `dpkg-shlibdeps` est absent, mais
elle ne porte **aucune contrainte sur la libc** : une valeur devinée serait pire
qu'aucune.

### RPM recopie, et laisse dnf conclure

Côté RPM, il n'y a rien à faire — et rien à demander. Le générateur automatique
de dépendances lit l'ELF à chaque construction, et on ne peut pas le
désactiver par distraction.

Surtout, il n'émet pas des noms de paquets mais des **sonames** :

```
libwebkit2gtk-4.1.so.0()(64bit)
libgtk-3.so.0()(64bit)
libc.so.6(GLIBC_2.42)(64bit)
```

C'est un avantage réel, pas seulement un confort. Fedora, RHEL et openSUSE
nomment le paquet WebKitGTK de trois façons différentes ; un soname se résout
sur les trois. Le `.deb`, lui, est lié à la nomenclature d'une seule famille.

Le spec ne nomme donc qu'une seule dépendance à la main,
`hicolor-icon-theme` — la propriété d'un répertoire n'est pas quelque chose
qu'un analyseur d'ELF puisse déduire.

### Comment la jonction se fait réellement

Le point contre-intuitif : **RPM ne cherche jamais quel paquet fournit un
soname.** Il n'en a pas besoin. Le mécanisme est symétrique, et les deux moitiés
tournent à la construction, chacune de son côté.

**Côté consommateur.** Quand votre `.rpm` est construit, `rpmbuild` lance
`elfdeps --requires` sur chaque binaire du paquet. Il lit les `DT_NEEDED` et
émet :

```
Requires: libwebkit2gtk-4.1.so.0()(64bit)
```

**Côté fournisseur.** Quand Fedora construit son paquet `webkit2gtk4.1`, le même
mécanisme lance `elfdeps --provides` sur les bibliothèques partagées qu'il
installe, lit leur `DT_SONAME`, et émet :

```
Provides: libwebkit2gtk-4.1.so.0()(64bit)
```

Exactement la même chaîne, produite indépendamment, à partir de la même
métadonnée ELF. **La jonction se fait à l'installation**, par simple
correspondance de chaînes entre les `Requires` de ce que vous installez et les
`Provides` indexés des dépôts. Le nom `webkit2gtk4.1` n'est écrit nulle part —
ni dans le spec, ni dans le paquet.

Les trois faces du mécanisme sont observables :

```sh
rpm -q --requires sun-notes                                    # ce que vous demandez
rpm -q --provides webkit2gtk4.1                                # ce qu'il offre
dnf repoquery --whatprovides 'libwebkit2gtk-4.1.so.0()(64bit)' # la jonction
```

Le même procédé couvre les versions de symboles : un binaire réclamant
`GLIBC_2.42` produit `libc.so.6(GLIBC_2.42)(64bit)`, et la glibc de chaque
distribution déclare un `Provides` par version qu'elle offre. C'est ce qui
explique le mur de lignes `nothing provides libc.so.6(GLIBC_2.x)` qu'affiche dnf
quand l'architecture ne correspond pas : aucun fournisseur x86-64 n'existant sur
une machine aarch64, *chaque* version de symbole est signalée comme
insatisfaite.

### Ce que ça change

| | Debian | RPM |
|---|---|---|
| Moment de la traduction | à la construction | jamais : la jonction a lieu à l'installation |
| Ce qu'il faut sur la machine de construction | les paquets `-dev`, pour leurs tables `symbols` | rien de particulier |
| Ce qui finit dans le paquet | des noms de paquets Debian | des sonames |
| Portabilité entre distributions | liée à une nomenclature | indépendante du nommage |

## Ce que chaque format demande en plus

| | Debian | RPM |
|---|---|---|
| Métadonnées | `DEBIAN/control` | le fichier spec |
| Intégrité | `DEBIAN/md5sums`, vérifié par `dpkg -V` | empreintes internes, vérifiées par `rpm -V` |
| Licence | `/usr/share/doc/<paquet>/copyright`, au format DEP-5 | directive `%license` |
| Journal | `changelog.gz` | section `%changelog` du spec |
| AppStream | absent | `/usr/share/metainfo/<app-id>.metainfo.xml` |

Deux subtilités méritent un mot.

**Le nom du changelog.** La version ne porte pas de révision Debian
(`0.1.0`, pas `0.1.0-1`), ce qui en fait un paquet dit *natif*. Le journal d'un
paquet natif s'appelle `changelog.gz`, et non `changelog.Debian.gz`.

**Les métadonnées AppStream** ne sont produites que côté RPM, parce que c'est ce
que lit **GNOME Logiciels** — par où passeront la plupart des utilisateurs
Fedora. Sans ce fichier, l'application s'installe et fonctionne, mais n'a ni
description ni capture d'écran dans la logithèque, et peut n'y pas figurer du
tout.

## Le plancher de distribution

Le paquet ne peut s'installer que sur une machine dont la glibc est au moins
aussi récente que celle qui l'a construit. Les deux scripts n'en tirent pas la
même conséquence, et c'est délibéré.

**Le `.deb` est construit sur Ubuntu 22.04**, choisie comme la plus ancienne
distribution portant `webkit2gtk-4.1`. Le plancher obtenu est glibc 2.35, ce qui
couvre Debian 12, Ubuntu 22.04 et tout ce qui suit.

**Le `.rpm` est construit sur `fedora:latest`**, donc le plancher est le plus
haut possible. Le compromis est assumé — les images Fedora en fin de vie
pointent vers des miroirs archivés, et les épingler donne une construction qui
casse d'elle-même — mais il a un coût : un paquet marqué `fc44` exigera
`GLIBC_2.42` et refusera de s'installer sur une Fedora plus ancienne.

Dans les deux cas, `webkit2gtk-4.1` impose son propre plancher, puisque c'est la
variante liée à libsoup 3 — voir [libsoup.md](./libsoup.md).

## Ce que les scripts refusent de produire

Les deux échouent plutôt que de livrer un paquet douteux :

- si l'architecture de l'ELF ne correspond pas à celle annoncée ;
- si le binaire est lié à une bibliothèque hors des répertoires système, donc
  absente de la machine de l'utilisateur ;
- si `index.html` ou `app.js` manquent de la charge utile ;
- si le fichier `.desktop` ne passe pas `desktop-file-validate`.

Et ils avertissent si les dépendances calculées ne mentionnent pas
`libwebkit2gtk-4.1` — auquel cas le problème est dans le binaire, pas dans le
paquet. `lintian` et `rpmlint` sont exécutés quand ils sont présents.

Les sources OCaml de la page sont filtrées au passage : dune les stage dans le
même répertoire que les fichiers produits, et elles n'ont rien à faire dans un
paquet.

## Quelques détails qui surprennent

**`%global debug_package %{nil}`.** La charge utile est construite par dune
avant que `rpmbuild` ne soit appelé ; il n'y a donc pas de section `%build` et
pas de symboles de débogage à extraire dans un sous-paquet `-debuginfo`. En
réclamer un ne ferait qu'échouer.

**`dpkg-deb -Zxz` explicitement.** Certaines versions de dpkg compressent en
zstd par défaut, et un `.deb` en zstd ne s'installe pas sur un dpkg plus ancien.

**`--root-owner-group` plutôt que `fakeroot`.** Tous les fichiers doivent
appartenir à root dans l'archive ; ce drapeau l'obtient sans dépendance
supplémentaire, avec un repli sur `fakeroot` pour les dpkg antérieurs à
Debian 10.

**Aucun script de post-installation.** Rafraîchir le cache d'icônes ou la base
des entrées de bureau était autrefois la charge du paquet ; les distributions
modernes s'en occupent par des déclencheurs de fichiers, et le dupliquer est
désormais déconseillé.
