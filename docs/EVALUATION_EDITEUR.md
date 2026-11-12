# BLOMIX — Évaluation éditeur

**12 novembre 2026**

BLOMIX vu par un éditeur mobile qui se demande s'il le propose à ses partenaires : verdict, critique par métier et plan sur 90 jours pour le rendre présentable. Sans pincettes.

## Sommaire

- [Verdict](#verdict)
- [Les 3 points bloquants](#les-3-points-bloquants)
- [Tableau des notes](#tableau-des-notes)
- [Équipe dev — 5/10](#équipe-dev--510)
- [Joueur — 6/10](#joueur--610)
- [Direction artistique — 5/10](#direction-artistique--510)
- [Game design — 6/10](#game-design--610)
- [UX/UI — 4/10](#uxui--410)
- [Direction com / marketing — 3/10](#direction-com--marketing--310)
- [Business / éditeur — 2/10](#business--éditeur--210)
- [Traction réelle](#traction-réelle)
- [Comparables marché](#comparables-marché)
- [KPI exigés par un éditeur](#kpi-exigés-par-un-éditeur)
- [Plan 30 / 60 / 90 jours](#plan-30--60--90-jours)
  - [J+30 : mesurer et arrêter de se desservir](#j30--mesurer-et-arrêter-de-se-desservir)
  - [J+60 : retenir](#j60--retenir)
  - [J+90 : devenir présentable](#j90--devenir-présentable)
- [Méthode et limites](#méthode-et-limites)

## Verdict

On ne signe pas aujourd'hui. Le noyau de jeu est original et soigné, mais rien autour ne permet de le vendre : aucune donnée de rétention, une fiche store qui dessert le jeu, aucun modèle économique, et une base technique qui ne repose que sur une personne. À revoir dans 90 jours si le plan ci-dessous est tenu.

| Valeur | Indicateur | Détail |
| ---: | :--- | :--- |
| **4/10** | Note éditeur globale |  |
| 225 | Premières installations | 1er mai – 7 nov. 2026 |
| 1,4/j | Rythme d'installation | stable, sans pic presse |
| 0 € | Revenu | sans pub, sans achats |

## Les 3 points bloquants

1. On ne sait rien de la rétention ni de l'engagement : App Analytics est inactif, aucune télémétrie n'existe, et 225 installations en 6 mois sans pic de presse.
2. Le jeu est mal vendu : 3 captures brutes (pseudo du dev, barre d'état), une description périmée (« 7 Magix, 3 modes »), un nom générique qui le range parmi les clones de Block Blast, et la collision avec « Bloomix ».
3. Il n'y a ni modèle économique ni base transférable : 0 € par construction, un `GameScene.swift` de 20 520 lignes, zéro test, un seul développeur avec des agents IA, et 68 versions en 7 mois.

## Tableau des notes

| Métier | Note | En une ligne |
| :--- | ---: | :--- |
| Équipe dev | 5/10 | Doc de studio, code de prototype géant, zéro test |
| Joueur | 6/10 | Boucle originale et addictive, onboarding et rappels faibles |
| Direction artistique | 5/10 | Propre mais sans identité, musique de banque |
| Game design | 6/10 | Mécanique profonde, trop de modes, méta sans récompense |
| UX/UI | 4/10 | Captures indignes du jeu, accessibilité absente |
| Com / marketing | 3/10 | Positionnement faux, fiche périmée, pas de kit presse |
| Business | 2/10 | Pas de mesure, pas de revenu, pas de traction |
| **Global (pondéré business)** | **4/10** | Pas signable aujourd'hui |

## Équipe dev — 5/10

| Critère | Note | Constat |
| :--- | ---: | :--- |
| Architecture | 3/10 | `GameScene.swift` fait 20 520 lignes (594 fonctions, 55 `MARK`) sur 50 035 lignes Swift au total |
| Tests automatisés | 1/10 | Aucun. `AGENTS.md` l'assume : « valider par raisonnement + checklist manuelle » |
| CI | 2/10 | Un seul workflow GitHub (`store-metadata.yml`), qui valide les textes du store, pas le code |
| Documentation | 8/10 | 23 docs, `CHANGELOG` de 48 entrées, tableau de bord `RELEASE_8.8.md`, mais en retard sur le code |
| Discipline de release | 4/10 | 68 versions mises en vente en 7 mois, et la 8.8 a été publiée avec l'ancienne popup 7.1 |
| Stack | 7/10 | Swift 6 en concurrence stricte, SpriteKit, GameKit, CloudKit, fastlane, cible Watch |
| Dépendance au fondateur | 2/10 | 1 seul contributeur (149 commits), code produit en grande partie par des agents IA |

**Points forts**

- Une documentation de studio, rare chez un dev solo : règles, glossaire, specs VFX, PvP, éval
- Un pipeline fastlane complet (validate, metadata, beta, release, submit) et une l10n en 6 langues tenue
- Des briques non triviales : Elo, bots de Duel, analyseur de coups avec 3 coups d'avance, défi du jour à graine fixe
- `AGENTS.md` (352 lignes) cadre bien les agents IA : zones sensibles, boucle de clôture

**Critiques**

- Un monolithe de 20 520 lignes alors que `AGENTS.md` annonce « ~12k+ » et interdit de le refactorer sans demande : la dette grossit sans contrôle
- Le moteur est dupliqué : la Watch a le sien (`WatchZenEngine.swift`, 743 lignes, plus `WatchMagixResolve.swift`), sans test de parité
- Zéro test sur un jeu dont la sauvegarde en est à sa version 8 et coexiste avec 5 formats de partie
- La doc ne suit plus : README, AGENTS et RULES indiquent « 8.6 build 158 », et AGENTS renvoie à `DOCS/` alors que le dossier s'appelle `docs/`
- Le commentaire de `BlomixWhatsNew.swift` le reconnaît : « La 8.8 est sortie avec `7.1_daily_duel` encore en place »
- 53 Mo de sons dans le dépôt, avec des doublons (`place.wav` et `place_new.wav`, `empty_coll_old.wav`), pour une app de 63,7 Mo
- 11 polices dans le dossier source pour 2 utilisées selon `BlomixTypography`, dont `GoogleSans-Regular.ttf` et `gameboy.ttf`, dont la licence reste à vérifier

**Correctifs, par ordre d'impact :**

- Extraire un moteur pur en Swift Package, sans SpriteKit (grille, gravité, chaînes, Brix, Magix, sauvegarde), partagé par l'iPhone et la Watch
- Ajouter des tests unitaires sur ce moteur, plus des parties à graine rejouées en golden tests, branchés sur Xcode Cloud
- Passer à un train de release toutes les 2 à 3 semaines, avec une checklist automatisée (campaignID, whats-new, version des docs)
- Auditer les licences (polices, sons Freesound, musique Soundimage) et purger les assets morts
- Générer la ligne de version des docs depuis `MARKETING_VERSION` avec un script

## Joueur — 6/10

| Critère | Note | Constat |
| :--- | ---: | :--- |
| Boucle de jeu | 7/10 | Gravité inversée et chaînes de 5 en 8-connexité : une boucle originale, lisible en un tap |
| Onboarding | 4/10 | 3 pages de texte puis un overlay interactif (chaîne, Brix, bombe), le reste « tu le découvriras en jouant » |
| Difficulté | 5/10 | 6 couleurs, Brix, 9 Magix, bombes, lignes entrantes, timer et stages : beaucoup de couches dès Arcade |
| Rétention | 5/10 | Défi du jour, trophées, Game Center, mais aucune notification locale pour rappeler le défi |
| Durée de session | 7/10 | Five vise des parties de quelques minutes, et un avis cite le Duel « le temps d'un café » |
| Multijoueur | 3/10 | Le Duel humain manque de joueurs à 1,4 installation par jour ; les bots (8.2) sont un pansement |

**Points forts**

- Le noyau est différenciant : on lâche un blox dans une colonne, il remonte, et la chaîne de 5 se lit tout de suite
- Le défi du jour à graine UTC, avec fantôme, est équitable et partageable
- L'analyse de fin de partie (pourcentage d'optimalité, pire coup) est un vrai crochet de maîtrise
- Les avis parlent d'« addictif » (deux fois), de « ma soirée dessus », de « dès que j'ai quelques minutes »

**Critiques**

- La copie du tuto est fautive : « Cliques sur une colonne » (verbe souris, faute d'accord), et « À vous de jouer ! » côtoie « Ton score »
- Le tuto promet « un petit bonus si vous avez plus de Brix que la moyenne statistique » : un système de pitié opaque, expliqué au pire moment
- Pour jouer en PvP, il faut se déclarer disponible, et l'accueil le dit en conseil du jour : c'est au joueur de compenser le manque de joueurs
- Aucun rappel push ou local : aucun appel à `UNUserNotificationCenter` dans le code, alors que le défi du jour est le meilleur crochet D1/D7
- Le pourcentage d'optimalité ignore les Magix (`BlomixMoveAnalyzer`, zone sensible n° 4) : le joueur peut se sentir jugé à tort

**Correctifs, par ordre d'impact :**

- Ajouter une notification locale opt-in pour le défi du jour, à heure fixe, une fois par jour au maximum
- Remplacer les pages de texte par une première partie guidée de 60 s, puis introduire les Magix un par un au fil des premières parties
- Dans le Duel, proposer d'abord un bot de niveau proche, puis basculer vers un humain dès qu'il y en a un, sans action du joueur
- Exclure les coups Magix du calcul d'optimalité ou les signaler, et le dire à l'écran

> Je n'ai pas joué au jeu : ce jugement vient du code, des docs, des captures et des avis.

## Direction artistique — 5/10

| Critère | Note | Constat |
| :--- | ---: | :--- |
| Identité | 4/10 | Des carrés plats sur fond crème : propre, mais rien qui se reconnaisse à 2 m dans un fil de captures |
| Cohérence | 4/10 | Logo rose dégradé, titre bleu-vert, boutons à bords multicolores : 3 traitements sur 3 captures |
| Lisibilité grille | 6/10 | Couleurs franches ; les Brix (carré marine et chiffre jaune) se lisent, mais ne disent pas « pierre » |
| Juice | 7/10 | Spec VFX détaillée, haptique `CHHapticEngine`, feux d'artifice à un record, SFX procéduraux |
| Son | 4/10 | Musique de banque « Puzzle Game 2 » d'Eric Matyas (Soundimage.org), présente dans d'innombrables jeux |

**Points forts**

- Une palette pastel cohérente, avec thèmes Sombre et Clair et skins de blox séparés proprement dans le code
- Un vrai travail de feel : vol des Magix, cascade, défaite (commits du 11 nov.)
- Les crédits sont honnêtes : Freesound et Soundimage sont cités

**Critiques**

- Pas d'univers : ni personnage, ni décor, ni récit visuel. Un avis parle de « charme années 80-90 » que rien ne porte dans la DA actuelle
- La typographie n'est pas tranchée : 11 polices dans le dossier source (DynaPuff, Londrina Shadow, Alfa Slab, Bitcount, gameboy…)
- Aucune signature sonore : la musique de banque rend le jeu interchangeable
- L'écran d'accueil empile 6 icônes rondes, 7 compteurs de rang en couleurs différentes et 6 boutons

**Correctifs, par ordre d'impact :**

- Écrire une bible DA d'une page : 1 logo, 2 polices, 6 couleurs, un matériau pour les Brix (pierre, verre ?) et un motif de fond signature
- Commander ou composer un thème musical propre de 60 à 90 s, déclinable par mode
- Refaire l'icône et la première capture ensemble, comme une seule image de marque

## Game design — 6/10

| Critère | Note | Constat |
| :--- | ---: | :--- |
| Profondeur mécanique | 8/10 | Chaînes, compteurs de Brix, 9 Magix, bombes, lignes entrantes : beaucoup de décisions par coup |
| Modes | 3/10 | Arcade, Zen, Five, Défi Arcade, Défi Five, Duel (humain et bots), tutoriel ; 7 onglets de classement |
| Équilibrage | 5/10 | Magix à 3 % cumulés pour 9 variantes, soit environ 0,3 % chacune : la plupart des joueurs ne les comprendront jamais |
| Méta-progression | 4/10 | Plus de 60 trophées, mais aucune récompense concrète (`TROPHIES.md` : « Hors v1 : toutes les skins ») |
| Rejouabilité | 7/10 | Défi du jour à graine fixe, Elo, records, rangs |

**Points forts**

- Une mécanique de famille Drop7 (lâcher en colonne, blocs résistants qui se fissurent), un créneau peu occupé face aux clones de Block Blast
- `MODE_PISTES.md` pose les bonnes questions de design (« changer l'objectif ou le contrat, pas la physique »)
- Les bots du Duel ont des niveaux (BABYBOT … BOT1) et un Elo : de quoi faire tenir un mode compétitif

**Critiques**

- Five est exactement ce que `MODE_PISTES.md` disait d'éviter : « ni Zen plus calme, ni Arcade plus vite ». C'est Zen avec une ligne tous les 5 coups au lieu de 10
- Le jeu en est à la 8.8 avec 7 entrées sur l'accueil et 7 rangs affichés : on a ajouté des modes au lieu de creuser une boucle
- 60 trophées sans rien à débloquer, c'est de la comptabilité, pas de la méta
- BRIXED, TWISTX, SCRUMBLX… les noms ne disent pas l'effet, et ils sont trop rares pour s'apprendre en jouant

**Correctifs, par ordre d'impact :**

- Ramener l'accueil à 3 portes (Jouer, Défi du jour, Duel), avec Zen, Arcade et Five comme variantes dans « Jouer »
- Construire le 4ᵉ mode autour de contrats (« vider la grille en 30 coups »), comme le propose déjà `MODE_PISTES.md`
- Faire débloquer des skins, thèmes et musiques par les trophées : une méta tangible, et un futur catalogue d'achats cosmétiques
- Garder 4 à 5 Magix « de base » plus fréquents, et réserver les autres aux défis

## UX/UI — 4/10

| Critère | Note | Constat |
| :--- | ---: | :--- |
| Captures App Store | 2/10 | 3 captures (10 possibles), brutes : barre d'état à 10:57, batterie en charge, aucune légende |
| Première impression | 4/10 | La capture n° 1 est un menu, avec le pseudo « lomigunger » et « Défi avant le 9 nov. à 03:00 » |
| Gameplay montré | 3/10 | Score de 25 et une grille à moitié vide : rien ne donne envie |
| Accessibilité | 2/10 | 12 `accessibilityLabel` dans toute l'app, pas de Dynamic Type, aucun mode daltonien pour un jeu de couleurs |
| Support iPad | 1/10 | `TARGETED_DEVICE_FAMILY = 1` : iPhone seulement, alors que les emails presse annonçaient « iPhone, iPad et Apple Watch » |
| Watch | 5/10 | Zen light seulement, moteur séparé, versionné à part (marketing 8.0, build 147) |

**Points forts**

- « Réduire les animations » est respecté (2 points du code) et le retour haptique est soigné
- Les chaînes de l'interface passent par `BlomixL10n` (865 lignes) : pas de texte en dur
- Un avis US parle d'une interface « simple to navigate »

**Critiques**

- Les captures montrent l'état du dev (16 536 au trophée Obsédé, record 1768) au lieu d'un joueur type en pleine action
- Le jeu repose sur 6 couleurs sans motif ni forme de secours : inutilisable pour une partie des joueurs daltoniens
- `fr.lproj` contient des clés en double (`tutorial.skip` aux lignes 238 et 251…), et `tutorial.dont_show_again` affiche « Afficher ce guide au démarrage » : sens inversé, bug possible à vérifier
- Sur la Watch, le moteur dupliqué fait diverger les règles à chaque évolution

**Correctifs, par ordre d'impact :**

- Refaire 6 à 8 captures marketing en 1290×2796 : une légende par capture, du gameplay en pleine cascade, sans barre d'état ni pseudo, et le bénéfice en premier (« Une chaîne de 5, tout remonte »)
- Ajouter un mode daltonien (un motif ou un symbole par couleur) et le Dynamic Type sur le chrome UIKit
- Corriger le pitch presse (iPad) ou ajouter un vrai support iPad
- Nettoyer les fichiers `.strings` (doublons, tutoiement uniforme) et relire la copie FR

## Direction com / marketing — 3/10

| Critère | Note | Constat |
| :--- | ---: | :--- |
| Nom et découvrabilité | 3/10 | « BLOMIX - Puzzle de blocs » est générique, et « Bloomix » (Winx) parasite la recherche sur X |
| Fiche store | 3/10 | La description parle de « 7 blocs Magix » (il y en a 9) et de « 3 modes » ; rien sur Five, les défis, les trophées ou la Watch |
| ASO | 3/10 | Le dépôt ne versionne que les mots-clés pt-BR ; ceux des autres langues sont invérifiables |
| Presse | 2/10 | 5 médias contactés (24 oct.–1er nov.) puis relancés, aucune réponse, aucun pic d'installations |
| Featuring Apple | 4/10 | Nomination pour la plage 18 nov.–2 déc., mais la 8.8 est en ligne depuis le 9 nov. (`automatic_release: true`) |
| Communauté | 1/10 | Ni Discord, ni TikTok, ni compte joueur : juste le compte perso @BLOmiG, LinkedIn et le blog |

**Points forts**

- Une promesse nette et honnête : gratuit, sans pub, sans achats
- Une note de 5/5 (20 notes en France), avec des avis spontanés et chaleureux
- Des métadonnées versionnées en 6 langues et un lien TestFlight dédié aux éditeurs

**Critiques**

- « Puzzle de blocs » place le jeu face à Block Blast et Woodoku, alors que la mécanique n'a rien à voir (on lâche en colonne, pas de polyominos)
- « Gratuit, sans pub » revient dans le sous-titre, le texte promo et la description : c'est une valeur, pas une accroche
- La règle `store/README.md` (« Description : nouvelle locale seulement, ne pas réécrire FR/EN/DE/ES/IT ») a figé une description périmée
- Le lien TestFlight des éditeurs pointe encore sur le build 160, pas sur le 163 publié
- Pas de kit presse (page, GIF, logo HD, fiche d'une page) : le mail demande aux journalistes de réclamer les captures
- 7 des 9 avis écrits viennent de France, dont 5 de la semaine de lancement : sans doute surtout l'entourage (inférence)

**Correctifs, par ordre d'impact :**

- Repositionner le jeu (« Le puzzle où tout remonte ») et tester un nom de fiche comme « BLOMIX : Chain Drop Puzzle »
- Réécrire la description dans les 6 langues, avec Five, défi du jour, trophées et Watch, puis supprimer la règle de gel
- Monter un kit presse sur blomig.com : 3 GIF de 6 s, une vidéo de 30 s, le logo, une fiche d'une page et l'angle « physicien solo + IA »
- Pousser `tf_featuring` sur le build 163, et pour la prochaine nomination, lier la date de sortie à la plage proposée (sortie manuelle)
- Créer un rendez-vous hebdo, par exemple le score du défi du jour partagé, pour générer de l'UGC

## Business / éditeur — 2/10

| Critère | Note | Constat |
| :--- | ---: | :--- |
| Traction | 2/10 | 225 premières installations du 1er mai au 7 nov., environ 1,4 par jour, dont 64 % en France |
| Monétisation | 0/10 | Aucune : ni pub ni achat. Le revenu est nul par construction |
| Mesure | 1/10 | App Analytics pas activé (`run_log.txt` : « no ONGOING report request ») : aucun D1, D7, D30 ni durée de session |
| Feedback | 5/10 | Sondage 8.8 dans CloudKit (3 questions, dont une note 0 à 10 façon NPS), réponses pas encore lues |
| Scalabilité | 3/10 | Le PvP dépend d'un vivier de joueurs qui n'existe pas, et le solo repose sur une seule personne |

**Points forts**

- Coût d'acquisition nul jusqu'ici, et aucune promesse non tenue
- Environ 500 à 780 mises à jour par mois pour 11 à 46 nouvelles installations : un noyau semble garder l'app (inférence, non mesuré)
- La promesse « sans pub, sans achats » est exactement le cahier des charges d'Apple Arcade

**Critiques**

- Un éditeur ne signe pas sans courbe de rétention : aujourd'hui, personne ne sait si les joueurs reviennent à J+1
- Le marché du block puzzle est tenu par des jeux hybrid-casual financés par la pub (Block Blast, Woodoku, 1010!) : impossible de rivaliser en acquisition payante sans revenu
- 68 versions en 7 mois pour 225 installations, soit environ 3 nouveaux joueurs par version : l'effort va au produit, pas à la distribution

**Correctifs, par ordre d'impact :**

- Activer App Analytics dès cette semaine (le script de la clé Admin est prêt) et ajouter une télémétrie minimale respectueuse : sessions, durée, fin de tuto, mode joué
- Choisir une piste de revenu compatible avec la promesse : pack Supporter cosmétique (skins débloqués, musiques), pitch Apple Arcade, ou licence du défi du jour pour un média
- Fixer des seuils de go/no-go à 60 jours et s'y tenir

## Traction réelle

*Premières installations par mois, App Store Connect (Sales Reports), jusqu'au 7 nov. 2026*

| Mois | Premières installations |
| :--- | ---: |
| **mai** | **77** |
| juin | 11 |
| juil. | 26 |
| août | 23 |
| sept. | 37 |
| oct. | 46 |
| nov. (1–7) | 5 |

Le pic de mai, c'est le lancement et l'entourage. Depuis, la courbe remonte lentement (46 en octobre), mais ni les envois presse du 24 oct. ni la 8.8 ne se voient. Les installations viennent à 64 % de France (145), puis des États-Unis (29), de Suisse (10) et d'Allemagne (9), dans 20 pays.

## Comparables marché

| Jeu | Mécanique | Modèle | Ce que BLOMIX doit en retenir |
| :--- | :--- | :--- | :--- |
| Block Blast! | Polyominos sur grille 8×8 | Pub (interstitiels, rewarded) | Le leader du genre : ne pas se vendre comme « puzzle de blocs » face à lui |
| Woodoku | Polyominos et sudoku, DA bois | Pub et abonnement sans pub | Une DA matière suffit à se distinguer |
| 1010! | Polyominos 10×10 | Pub et achats | La simplicité extrême comme argument |
| Drop7 | Lâcher en colonne, disques qui se fissurent | Premium puis pub | Le vrai cousin mécanique de BLOMIX (Brix ≈ disques gris) |

Les modèles économiques sont ceux connus publiquement ; je n'ai pas vérifié ici de chiffres de revenus ou de téléchargements. Le rapprochement avec Drop7 est mon analyse.

## KPI exigés par un éditeur

| KPI | Seuil puzzle usuel | BLOMIX aujourd'hui |
| :--- | ---: | ---: |
| Rétention J1 | 35–40 % | **non mesuré** |
| Rétention J7 | 12–15 % | **non mesuré** |
| Rétention J30 | 5–8 % | **non mesuré** |
| Session moyenne | 8–12 min | **non mesuré** |
| Sessions par jour | 3+ | **non mesuré** |
| Conversion de la fiche | 25–35 % | **non mesuré** |
| Fin du tutoriel | 80 %+ | **non mesuré** |
| Note store | 4,5+ | 5,0 (21 notes) |

Les seuils sont des ordres de grandeur courants dans le marché du puzzle casual, pas des chiffres vérifiés ici. La seule ligne mesurée est la note.

## Plan 30 / 60 / 90 jours

### J+30 : mesurer et arrêter de se desservir

1. **Activer App Analytics**

   Lancer `create_analytics_request.py` avec la clé Admin, et ajouter une télémétrie anonyme : session, durée, fin de tuto, mode.
2. **Refaire la fiche store**

   6 à 8 captures légendées, une description à jour en 6 langues, un texte promo qui cite Five et le défi du jour.
3. **Geler les features**

   Plus de nouveau mode. Une release toutes les 2 à 3 semaines, avec une checklist de release automatisée.
4. **Lire le sondage CloudKit**

   Calculer le NPS et les 3 raisons de revenir citées, pour s'en servir dans le pitch.
5. **Corrections rapides**

   Lien TestFlight des éditeurs sur 163, mention iPad dans le pitch, doublons `.strings`, copie du tuto.

### J+60 : retenir

1. **Rappel du défi du jour**

   Notification locale opt-in, plus un partage du score en image.
2. **Accueil à 3 portes**

   Jouer, Défi du jour, Duel. Zen, Arcade et Five passent en variantes.
3. **Méta tangible**

   Les trophées débloquent skins, thèmes et musiques.
4. **Accessibilité**

   Mode daltonien (motifs), Dynamic Type sur le chrome.
5. **Moteur extrait et testé**

   Un Swift Package partagé par l'iPhone et la Watch, avec des parties à graine rejouées en CI.

### J+90 : devenir présentable

1. **Dossier de pitch**

   Courbes J1, J7 et J30 sur au moins 500 installations, durée de session, NPS, vidéo de 30 s.
2. **Décision de modèle**

   Pack Supporter cosmétique, pitch Apple Arcade, ou licence du défi du jour à un média : en choisir un.
3. **Bible DA et son**

   Une identité et un thème musical propres, avec la nouvelle icône.
4. **Go / no-go**

   Si J1 dépasse 35 % et J7 dépasse 12 %, on présente à des éditeurs. Sinon, on retravaille la boucle avant tout marketing.

## Méthode et limites

> **Ce que je n'ai pas pu vérifier**
>
> Je n'ai pas joué au jeu. Les jugements sur le ressenti, la difficulté et le feel viennent du code, des docs, des 3 captures de la fiche, des notes de version et des avis. Les points marqués « inférence » ou « à vérifier » ne sont pas prouvés. Les licences des polices et l'usage réel des mots-clés dans App Store Connect restent à contrôler.

Sources : le dépôt `blomig/BLOMIX` (149 commits du 6 avr. au 11 nov. 2026, dont `AGENTS.md`, `docs/`, `store/` et les sources Swift), la fiche App Store et l'API iTunes Lookup (FR et US), ainsi que les exports App Store Connect sur le box (ventes, avis, 68 versions).

> Jeu super addictif, simple, sans fioriture! On a qu'une envie c'est d y retourner pour casser des brix !
>
> — Avis App Store, France, 7 mai 2026

- [Fiche App Store FR](https://apps.apple.com/fr/app/blomix-puzzle-de-blocs/id6762053543) (apps.apple.com)
- [Dépôt blomig/BLOMIX](https://github.com/blomig/BLOMIX) (github.com)
