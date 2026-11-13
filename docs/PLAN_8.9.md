# BLOMIX 8.9 — plan à valider

> **13 novembre 2026.** Branche `8.9`, à partir de `f7abd5d` et de [EVALUATION_EDITEUR.md](EVALUATION_EDITEUR.md) (12 novembre, note **4/10**).
> État binaire : `MARKETING_VERSION` **8.8**, build iPhone **163**, Watch **8.0 / 147**. Ce document ne bumpe rien et ne lance aucun lane.
> Les décisions D1… étaient des choix produit. Elles sont tranchées ci-dessous. La section 2 garde le contexte et les options.

---

## Décisions validées (13/11/2026)

Lomig a validé la liste suivante. Ce qui n’est pas dans les lots 0 à 6 de ce passage reste hors code (fiche, kit, notification).

- **D1** : Analytics App Store + télémétrie anonyme dans le jeu (CloudKit, sans SDK tiers).
- **D2** : rester gratuit, sans pub ni achat pour la 8.9.
- **D3** : réécrire la description App Store dans les 6 langues (rédigée par le CM, validée par Lomig). Publication après la nomination, après le 2 décembre (D17).
- **D4** : garder le nom BLOMIX, changer le sous-titre.
- **D5** : refaire 6 à 8 captures App Store avec accroche.
- **D6** : attendre la mesure avant de simplifier l’accueil. **Lot abandonné** pour la 8.9 (L10).
- **D7** : geler les modes pour la 8.9.
- **D8** : chaque **nouveau** trophée maxé (plein + 3 étoiles) donne **une fois** un MAGIX B comme premier bloc de la partie solo suivante (jamais en Duel). L’idée « commencer avec 6 bombes » n’est pas retenue. L’historique déjà maxé au premier lancement 8.9 ne crédite rien.
- **D9** : ne pas changer la rareté des Magix.
- **D10** : corriger les textes du tuto (bombes page 2, tu/vous, bonus) sans nouveau parcours. Le bonus « moyenne statistique » **n’est pas dans le code** (seul un commentaire orphelin dans `GameScene` en parle) : la page 3 retire la phrase, elle ne l’explique pas.
- **D11** : notification locale du défi du jour, **après** la mise en place de la mesure. Pas dans ce passage.
- **D12** : **C**, ne pas changer le Duel. **Lot abandonné** (L13).
- **D13** : **B**, une phrase « Les Magix ne sont pas notés » (6 langues).
- **D14** : ne rien changer. Les couleurs sont déjà paramétrables (skin perso). Retour positif d’un joueur daltonien. Point éditeur jugé non pertinent. **Lot abandonné** (L12).
- **D15** : **A**, retirer l’iPad des textes presse et du kit (app iPhone + Watch). Hors code. **L16 abandonné**.
- **D16** : **B**, tests de référence (moteur Watch, `BlomixMoveAnalyzer`, `BlomixDailyRNG`) sans toucher `GameScene`. **L14 abandonné** (extraction du moteur).
- **D17** : une version publique toutes les 2–3 semaines (TestFlight entre les deux). Nouvelle fiche App Store (D3–D5) publiée après la nomination (après le 2 déc.).
- **D18** : **B**, garder la DA. Supprimer seulement les polices non référencées, après audit de licence.

---

## 1. Synthèse

Un éditeur ne signe pas aujourd’hui. Le puzzle (gravité vers le haut, chaînes de 5 en 8-connexité, Brix, Magix) est le point fort. Autour, trois blocages : aucune courbe de rétention, une fiche qui vend un « puzzle de blocs » périmé, et une base non transférable (0 €, un `GameScene.swift` de 20 520 lignes, zéro test, un seul développeur).

| Métier | Note | Lecture pour 8.9 |
| :--- | ---: | :--- |
| Équipe dev | 5/10 | Doc solide, monolithe et absence de tests inchangés |
| Joueur | 6/10 | Boucle forte ; tuto, rappel du défi et justesse encore ouverts |
| Direction artistique | 5/10 | Le feel du 11 nov. est déjà dans la note juice (7/10). L’identité et la musique de banque restent |
| Game design | 6/10 | Profondeur réelle ; trop de portes à l’accueil, méta sans récompense, Magix trop rares |
| UX/UI | 4/10 | Captures et accessibilité. Les doublons FR et quelques coquilles sont traités dans ce lot |
| Com / marketing | 3/10 | Nom, description figée, kit presse, lien éditeurs sur le build 160 |
| Business | 2/10 | 225 premières installations (1er mai – 7 nov.), 0 €, App Analytics inactif |

Traction citée par l’évaluation : pic de mai (77), puis 11 à 46 / mois, 64 % en France. Note store 5,0 sur un petit nombre d’avis. Rétention J1 / J7 / J30 non mesurée.

### Déjà dans le code depuis la 8.8

Les trois commits du **11 novembre 2026** sont dans cette branche. L’évaluation les a en partie vus (« commits du 11 nov. ») et s’appuie encore sur l’état **8.8 / 163** pour la fiche et la popup en vente.

| Commit | Déjà livré en local | Critique de l’évaluation |
| :--- | :--- | :--- |
| `766ec8a` | Popup `BlomixWhatsNew.campaignID = "8.9"` (6 langues). Phases de dégradé du salon. Le point orange s’éteint à la dernière fiche | La 8.8 **en vente** est bien partie avec `7.1_daily_duel`. Le correctif est dans le source 8.9, pas dans le binaire 163. Le commentaire du fichier le rappelle encore, à dessein |
| `5305738` | Voisins qui bougent à la pose, haptique de matière, cascade (COMBO plus tard), ligne menaçante, grille assombrie à la défaite. « Réduire les animations » coupe le décor | Le feel est déjà crédité (juice 7/10). Pas un chantier à rouvrir |
| `f7abd5d` | Accueil qui s’ouvre par étapes. Air dans les trous. Rotation pendant la montée (Magix et appui long). Voix d’arrivée `magix.wav` / `magix_follow.wav`. Cases vides Clair | Même constat : le polish de partie est fait. L’accueil **anime** l’entrée ; il **empile** toujours héros, défis, Duel, Zen, Five, disques de rang et icônes |

Critiques qui restent entières : mesure, fiche, modèle économique, monolithe, tests, onboarding de fond, notifications, accessibilité, iPad, Watch à moteur séparé, musique de banque, trophées sans récompense.

### Vérifié, et ce n’est pas un bug

`tutorial.dont_show_again` affiche « Afficher ce guide au démarrage » (et l’équivalent dans les 6 langues). L’interrupteur suit ce sens : coché → `hasSeenGameTutorial = false` → le guide revient (`GameTutorialOverlayView`, `LeaderboardViewController`). Le **nom de clé** est à l’envers du libellé. Le joueur voit le bon texte. Renommer la clé ne change rien à l’écran : laissé de côté.

---

## 2. Décisions produit

Chaque point peut être écarté. Tant qu’il n’est pas validé, le lot qui en dépend ne part pas.

### D1 — Mesurer ou rester sans télémétrie

Contexte : App Analytics est inactif. Aucun `UNUserNotificationCenter`, aucune télémétrie de session. 225 installs ne disent pas si les joueurs reviennent.

- **A.** Activer App Analytics seulement (console), zéro code.
- **B.** A + événements locaux anonymes : session, durée, fin de tuto, mode joué. Pas de pub, pas d’identifiant publicitaire.
- **C.** Ne rien mesurer. Le pitch éditeur reste sans courbe.

Recommandation : **B**. Sans J1/J7, le reste du plan 90 jours ne se tranche pas. Le script `create_analytics_request.py` cité par l’évaluation **n’est pas dans ce dépôt**.

### D2 — Promesse « gratuit, sans pub, sans achat »

Contexte : revenu 0 € par construction. L’évaluation propose un pack Supporter cosmétique, un pitch Apple Arcade, ou une licence du défi du jour. La promesse est aussi l’argument le plus répété de la fiche.

- **A.** Tenir la promesse. Aucun IAP, aucune pub. Le revenu n’est pas un objectif de la 8.9.
- **B.** Préparer un pack cosmétique (skins, thèmes, musiques) sans le sortir tant que D8 n’a pas de méta gratuite.
- **C.** Dossier Arcade ou licence média, sans changer l’app.

Recommandation : **A** pour le code 8.9. **C** peut avancer en parallèle, hors binaire. **B** attend des courbes (D1) et une méta (D8).

### D3 — Description App Store figée

Contexte : `store/description/` ne versionne que `pt-BR`. La règle de `store/README.md` (« nouvelle locale seulement ») a laissé FR/EN/DE/ES/IT sur « 7 Magix, 3 modes ». Le jeu a 9 Magix, Five, deux défis, le salon, la Watch.

- **A.** Réécrire les 6 langues et retirer la règle de gel. Five, défi, trophées, Watch, gravité vers le haut. Noms Magix non traduits.
- **B.** Corriger seulement les faits faux (7 → 9, 3 modes) sans changer le ton.
- **C.** Laisser la description. Le pt-BR récent sert de modèle le jour où on réécrit.

Recommandation : **A**, dans un lot dédié, après D4 (le nom et l’accroche doivent dire la même chose).

### D4 — Nom de fiche et sous-titre

Contexte : « BLOMIX - Puzzle de blocs » et « Chaînes de 5, gratuit sans pub » rangent le jeu à côté de Block Blast. « Gratuit sans pub » est une valeur, répétée dans le promo. « Bloomix » (Winx) parasite la recherche. Le nom d’icône iPhone reste BLOMIX.

- **A.** Garder le nom. Changer le sous-titre seulement (≤ 30 car.), par exemple autour de « tout remonte ».
- **B.** Tester un nom de fiche du type « BLOMIX : Chain Drop Puzzle » (≤ 30) et un sous-titre qui dit la mécanique, pas le prix.
- **C.** Ne rien changer. Le nom est installé depuis mai.

Recommandation : **A** maintenant (sous-titre), **B** seulement si un test de fiche est acceptable. Ne pas trancher le nom à la place du développeur.

### D5 — Captures et preview

Contexte : 3 captures brutes (barre d’état, pseudo, score 25, date de défi). 10 emplacements possibles. La preview actuelle ne montre pas Five. Fastlane ne pousse pas les screenshots (`store/asc-assets/`).

- **A.** 6 à 8 captures 1290×2796, légende, cascade, sans barre d’état ni pseudo. Preview Five plus tard.
- **B.** Remplacer les 3 actuelles par 3 plans propres, sans aller à 8.
- **C.** Garder les captures du 8 nov. (accueil, Five, salon) déjà uploadées pour la 8.8.

Recommandation : **A** avant toute prise de contact éditeur. **C** suffit tant que la 8.8 est le binaire en review.

### D6 — Portes de l’accueil

Contexte : Arcade en héros, Défi Arcade | Défi Five, Duel | Zen | Five, plus les disques de rang. L’évaluation demande 3 portes (Jouer, Défi, Duel) et les modes en variantes. `f7abd5d` n’a changé que l’animation d’entrée.

- **A.** Trois portes. Zen, Arcade et Five deviennent des variantes de Jouer. Les classements restent.
- **B.** Garder les 7 entrées. Alléger seulement les disques de rang (moins de couleurs d’un coup).
- **C.** Ne pas toucher à l’accueil en 8.9.

Recommandation : **C** tant que D1 n’a pas dit quel mode revient. **A** est le bon dessin si on assume le gel des modes (D7), pas avant.

### D7 — Nouveaux modes

Contexte : Five est Zen avec une ligne tous les 5 coups, ce que `MODE_PISTES.md` voulait éviter. L’évaluation dit : plus de mode, puis un 4ᵉ mode à contrats (« vider la grille en 30 coups »).

- **A.** Gel. Aucun mode nouveau en 8.9. Five reste.
- **B.** Gel + spec contrats, sans code.
- **C.** Coder un mode Contrats dans la 8.9.

Recommandation : **A**. **B** si l’écriture aide. **C** contredit le constat « on a ajouté des modes au lieu de creuser ».

### D8 — Trophées et récompenses

Contexte : plus de 60 trophées, salon en place, `TROPHIES.md` : skins « hors v1 ». Aucun déblocage.

- **A.** Les paliers débloquent des skins, thèmes ou musiques déjà dans le jeu.
- **B.** Le salon reste une vitrine. Pas de récompense en 8.9.
- **C.** Réduire le nombre de trophées avant d’en faire une méta.

Recommandation : **B** pour la 8.9. **A** est la méta tangible, et le seul pont propre vers D2-B plus tard. **C** jette de la copie déjà traduite.

### D9 — Rareté des Magix

Contexte : 9 Magix, environ 3 % cumulés. La plupart des joueurs ne les voient pas assez pour apprendre BRIXED, TWISTX, SCRUMBLX.

- **A.** 4 ou 5 Magix plus fréquents en Arcade / Zen / Five. Les autres réservés au défi ou à un trophée.
- **B.** Garder les 9 et les taux. Améliorer le guide, pas les probabilités.
- **C.** Première partie : un Magix garanti et expliqué, taux inchangés ensuite.

Recommandation : **B** ou **C**. **A** change l’équilibre et les graines du défi : hors « correctif évident ».

### D10 — Tutoriel

Contexte : 3 pages puis un overlay interactif. Mélange tu / vous. Page 3 explique un bonus de pitié (« plus de Brix que la moyenne statistique ») au pire moment. Le code fait bien un bonus ≥ 0 d’excès sur N/8 (`GameScene`, +1 pt par Brix au-delà du théorique). Page 2 dit encore « une bombe au départ, une nouvelle toutes les 10 chaînes » et « 9 cases autour » : le stock est **5** (3 en Duel), il n’y a pas de recharge toutes les 10 chaînes, la zone Zen/Five/Duel/tuto est un **3×3**, l’Arcade passe ensuite en croix.

- **A.** Relire les 3 pages en 6 langues : tutoiement unique, bombes alignées sur `RULES.md`, « Duel » à la place de « Player Vs Player ». Pas de nouveau flux. Le bonus « moyenne statistique » décrit ici **n’existe pas** dans le calcul du score : le commentaire au-dessus de `chainSeriesLevel` est orphelin. La page 3 retire la phrase.
- **B.** Remplacer les pages par une première partie guidée (~60 s), Magix introduits plus tard.
- **C.** Laisser le texte. Seules les coquilles de ce lot (section 6) sont corrigées.

Recommandation : **A** bientôt, **B** seulement si on accepte de toucher le flux. **C** est l’état après ce lot. Le mélange tu/vous et la page 2 périmée ne sont pas des coquilles : les reformuler change le discours.

### D11 — Rappel du défi du jour

Contexte : aucun appel à `UNUserNotificationCenter`. Le défi est le meilleur crochet D1/D7, et il n’a pas de rappel.

- **A.** Notification locale opt-in, une fois par jour, heure choisie, réglage pour couper.
- **B.** Pas de notification. Partage du score en image seulement.
- **C.** Rien.

Recommandation : **A**, après D1 (sinon on ne saura pas si le rappel sert). Le partage image peut suivre sans attendre.

### D12 — Duel quand il n’y a personne

Contexte : ~1,4 installation / jour. Le joueur doit se déclarer disponible. Les bots (BABYBOT … BOT1) existent depuis la 8.2. L’évaluation veut : bot de niveau proche d’abord, humain dès qu’il y en a un, sans geste.

- **A.** « Duel » lance un bot proche, et bascule vers un humain si la liste n’est pas vide.
- **B.** Garder le lobby. Mettre le bot en premier bouton, l’humain en second.
- **C.** Ne pas changer le Duel.

Recommandation : **B**. **A** change le contrat PvP (RNG, Elo, revanche) dans une zone sensible. Le conseil du jour qui demande de se déclarer disponible reste tant que **C** ou **B** n’a pas de phrase de remplacement.

### D13 — Justesse et Magix

Contexte : `BlomixMoveAnalyzer` ignore les Magix (et les bombes, déjà dit dans `RULES.md`). Le pourcentage peut juger un coup Magix comme une erreur.

- **A.** Exclure les coups Magix du pourcentage et l’écrire sous le chiffre.
- **B.** Garder le calcul. Une ligne d’écran : « Les Magix ne sont pas notés ».
- **C.** Étendre l’analyseur aux Magix.

Recommandation : **B** (une phrase, 6 langues). **A** si le chiffre doit devenir honnête tout de suite. **C** est un projet à part, documenté dans `EVAL.md` avant tout code.

### D14 — Accessibilité

Contexte : peu de `accessibilityLabel`, pas de Dynamic Type, 6 couleurs sans motif. « Réduire les animations » est déjà respecté.

- **A.** Motif ou symbole par couleur (réglage), et Dynamic Type sur le chrome UIKit.
- **B.** Dynamic Type seul.
- **C.** Plus tard.

Recommandation : **A** avant un dossier éditeur, pas dans le premier build 8.9. Le jeu est un jeu de couleurs : le motif touche la DA (D18).

### D15 — iPad

Contexte : `TARGETED_DEVICE_FAMILY = 1`. Des mails presse ont dit « iPhone, iPad et Apple Watch ».

- **A.** Retirer iPad des pitches et du kit. L’app reste iPhone + Watch.
- **B.** Support iPad réel (layout, pas un simple agrandissement).
- **C.** Laisser les textes presse tels quels.

Recommandation : **A** cette semaine (hors code). **B** est un projet, pas un correctif de fiche.

### D16 — Moteur partagé, tests, CI

Contexte : `GameScene.swift` 20 520 lignes, 594 fonctions. Watch : `WatchZenEngine.swift` 743 lignes + `WatchMagixResolve.swift` 328, sans test de parité. CI GitHub : métadonnées store seulement. Cinq formats de sauvegarde, save version 8.

- **A.** Extraire un moteur pur (grille, gravité, chaînes, Brix, Magix, sauvegarde) en Swift Package, iPhone + Watch, tests de graines, Xcode Cloud.
- **B.** Tests d’or sur le moteur **Watch** et sur `BlomixMoveAnalyzer` / `BlomixDailyRNG`, sans toucher `GameScene`.
- **C.** Pas d’extraction en 8.9. Checklist manuelle inchangée.

Recommandation : **B**. **A** est juste et trop large pour un train 8.9 : `AGENTS.md` interdit d’éclater `GameScene` sans demande explicite, et la parité Watch se casse à chaque Magix. **C** laisse la critique « base non transférable » ouverte.

### D17 — Cadence de release

Contexte : 68 versions en 7 mois, environ 3 nouveaux joueurs par version. La 8.8 est partie en mise en ligne automatique pendant une nomination 18 nov.–2 déc.

- **A.** Une version marketing toutes les 2 à 3 semaines. Builds TestFlight internes entre les deux. Checklist : `campaignID`, whats-new 6 langues, version des docs, Featuring.
- **B.** Continuer au fil des correctifs, avec bump dès qu’un lot est jouable.
- **C.** Geler toute fiche ASC jusqu’aux seuils D20.

Recommandation : **A** pour la cadence, **C** pour la **fiche magasin** tant que D1 n’a pas deux semaines de chiffres. TestFlight peut tourner (section 4).

### D18 — Identité visuelle et son

Contexte : carrés plats, logo / titre / boutons de trois traitements, 11 fichiers `.ttf` dans le dossier pour 2 visages réellement posés (`BlomixTypography` : Changa One + Nunito). Musique « Puzzle Game 2 » (Eric Matyas / Soundimage), déjà créditée. Les clés `settings.font.*` sont du legacy : plus aucun écran ne les lit.

- **A.** Bible d’une page (1 logo, 2 polices, 6 couleurs, une matière Brix, un fond). Thème musical propre 60–90 s ensuite. Icône et capture 1 ensemble.
- **B.** Garder la DA. Purger seulement les fichiers de polices non référencés, après audit de licence.
- **C.** Commander le thème, ne pas toucher aux formes.

Recommandation : **B** comme hygiène (lot L8, licences d’abord). **A** est un projet de marque, pas un lot de code 8.9. Le choix « pierre ou verre » pour les Brix est de la DA : non tranché ici.

---

## 3. Lots de travail

Estimation : **S** moins d’une journée, **M** quelques jours, **L** une semaine ou plus.

Lots **abandonnés** après validation : **L10** (accueil, D6), **L12** (accessibilité, D14), **L13** (Duel, D12), **L14** (moteur partagé, D16-A), **L16** (iPad, D15-B). **L15** ne débloque plus de skins : il devient la récompense MAGIX B de D8. **L4** (notification) attend la mesure (D11). **L5** et **L6** (fiche, captures) attendent le 2 décembre (D17).

| Lot | Contenu | Fichiers | Taille | Risque | Dépend de |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **L1** | Doublons FR et coquilles. **Fait** (section 6) | `fr.lproj/Localizable.strings`, `en.lproj/Localizable.strings`, `fr.lproj/rules.txt`, `en.lproj/rules.txt` | S | Nul sur le gameplay. `rules.txt` n’est plus lu (le guide passe par `guide.section.*`) | — |
| **L2** | Copie du tuto alignée sur les règles actuelles, 6 langues, tutoiement choisi | `Localizable.strings` ×6, éventuellement `tips_of_day.json` | M | Les 3 pages sont le premier écran. Une phrase fausse sur les bombes reste tant que ce lot n’est pas fait | D10 |
| **L3** | Phrase sous la justesse : les Magix ne sont pas notés | `GameScene.swift` (libellé seulement), `BlomixL10n.swift`, 6 `.strings`, `docs/RULES.md`, `docs/EVAL.md` | S | Zone sensible n° 4 si on change le **calcul**. La phrase seule ne le change pas | D13 |
| **L4** | Notification locale du défi, opt-in | nouveau petit type, `GameViewController` ou hub, réglages, `BlomixL10n`, entitlements **si** on ajoute un droit (à éviter : une notif locale n’en demande pas) | M | Permission au mauvais moment, fuseau vs minuit UTC du défi | D11 |
| **L5** | Description 6 langues, sous-titre, promo qui cite la mécanique une fois | `store/description/`, `store/subtitle/`, `store/promotional-text/`, `store/README.md` | M | `metadata` / `release` réécrivent la fiche ASC. Ne pas lancer ces lanes pour un essai | D3, D4 |
| **L6** | Captures marketing | `store/asc-assets/` (inbox gitignoré), procédure manuelle ASC | M | Fastlane ne les pousse pas. Upload manuel | D5 |
| **L7** | Hygiène doc : versions de référence encore à 8.6 / 7.x, `AGENTS.md` et `README.md` disent 8.6 build 158 et `DOCS/` alors que le dossier est `docs/` | `AGENTS.md`, `README.md`, en-têtes `docs/*.md` | S | Écrire « 8.9 » avant le bump de `MARKETING_VERSION` recreuse le décalage. Le faire **le jour du bump** | D17 |
| **L8** | Audit licences (polices, Freesound, Soundimage) puis retrait des `.ttf` et wav non référencés (`place.wav` / `place_new.wav`, `empty_coll_old.wav`, 53 Mo de `Sounds/`) | `Blomix/Blomix/*.ttf`, `Sounds/`, `project.pbxproj` **seulement** si un fichier sort du target, `credits` | M | Effacer un son encore branché sur `BlomixMatchSFX`. Licences à lire avant de supprimer | D18-B |
| **L9** | Tests d’or Watch + analyseur, sans extraire `GameScene` | target de test nouveau, `Watch/Engine/`, `BlomixMoveAnalyzer.swift`, `BlomixDailyRNG.swift` | L | Faux verts si les graines ne sont pas figées. Ne pas « réparer » le monolithe au passage | D16-B |
| **L10** | **Abandonné** (D6). Accueil inchangé tant que la mesure n’a pas parlé | — | — | — | D6 |
| **L11** | Télémétrie anonyme | type dédié, branchements session / fin de partie / défi, politique `docs/privacy-policy.html`, schéma CloudKit | M | Vie privée, review Apple si le texte de politique ment. Pas d’IDFA. Échec d’envoi silencieux | D1 |
| **L12** | **Abandonné** (D14). Couleurs déjà dans le skin perso | — | — | — | D14 |
| **L13** | **Abandonné** (D12-C). Duel inchangé | — | — | — | D12 |
| **L14** | **Abandonné** (D16-B). Pas d’extraction de `GameScene` | — | — | — | D16 |
| **L15** | Récompense MAGIX B : un trophée **nouveau** à 3 étoiles crédite un BOMBX, premier bloc de la prochaine partie Arcade / Zen / Five. Pas le Défi, pas le Duel, pas le tutoriel, pas la reprise. Historique non crédité | `BlomixTrophyStore.swift`, `GameScene.swift` (injection + message), `BlomixL10n`, 6 `.strings`, `docs/TROPHIES.md`, `docs/RULES.md` | M | Crédit rétroactif ou consommation sur une grille jetée (retour accueil, prep Duel). Graine du Défi si on injectait là | D8, D9 |
| **L16** | **Abandonné** (D15-A). iPad retiré des textes presse, pas du binaire | — | — | — | D15 |
| **L17** | Checklist de release automatisée (`campaignID`, 6 whats-new, en-têtes docs) | `scripts/`, éventuellement le workflow `store-metadata.yml` | S | Un script qui bumpe ou qui pousse ASC serait hors contrat. Lecture seule | D17-A |

Lots explicitement non ouverts : probabilités Magix (D9), mode Contrats (D7), thème musical et nouvelle icône (D18-A), monétisation (D2), accueil (D6 / L10), accessibilité (D14 / L12), Duel (D12 / L13), extraction du moteur (L14), iPad (L16).

---

## 4. Builds TestFlight 8.9

**Ne pas lancer.** Aucun `fastlane`, aucun appel App Store Connect dans ce lot.

Aujourd’hui le binaire est **8.8 (163)**. La lane `beta` (`fastlane/Fastfile`) :

1. valide le projet **sans** exiger `store/` (`validate_project!(require_store: false)`) ;
2. lit la clé API ASC et le dernier build TestFlight / App Store ;
3. écrit `CURRENT_PROJECT_VERSION` iPhone dans `project.pbxproj` à `max(local, distant + 1)` — la Watch ne bouge pas ;
4. archive le scheme **`Blomix`** (le scheme Xcode s’appelle `Blomix`, la target s’appelle `BLOMIX`) en Release et uploade sur TestFlight **interne** (`distribute_external: false`) ;
5. met comme notes TestFlight le fichier `store/whats-new/en-US.txt` **tel quel**.

Elle ne bumpe pas `MARKETING_VERSION`. Un upload fait demain s’afficherait donc comme **8.8 (164)** tant que la version marketing n’a pas été passée à 8.9 à la main. Elle ne soumet pas la fiche et ne déplace pas le groupe Featuring.

Le lien éditeurs `https://testflight.apple.com/join/4zA8hFqB` pointe sur le groupe **Featuring = build 160**. Il n’y a **pas** de lane `tf_featuring` dans le `Fastfile` actuel. Changer ce groupe se fait dans App Store Connect, sur demande, et colle le lien public au build choisi.

| Build | Contenu visé | Avant de lancer `bundle exec fastlane beta` |
| ---: | :--- | :--- |
| **164** | Ce lot : coquilles + plan. Smoke accueil, 3 pages de tuto, overlay, réglages (libellé Brix du son), guide | Décider si l’étiquette TestFlight doit dire **8.9** (bump `MARKETING_VERSION` à la main, puis la lane posera 164) ou **8.8 (164)**. Réécrire `store/whats-new/en-US.txt` **seulement** si ces notes peuvent servir de journal TestFlight : aujourd’hui elles décrivent la 8.8 et les testeurs les verront. Ne pas lancer `metadata` / `release` pour ça. La 8.8 peut encore être en review : un build TestFlight ne la remplace pas |
| **165** | Premier lot validé parmi L2, L3, L4 | D10 ou D13 ou D11 tranché. Notes TestFlight à jour. Pas de Featuring |
| **166** | L5 + L6 si D3, D4, D5 sont oui : textes de fiche **préparés dans git**, captures prêtes, upload captures **manuel** | `beta` ne pousse pas la description. La fiche magasin attend une décision D17 séparée (`release` / `submit`, hors de ce plan d’exécution) |
| **167** | L9 (tests) ne produit pas un build joueur. Le build suivant utile est L11 si D1-B, ou L4 si la notif n’était pas dans 165 | Politique de confidentialité à jour avant un binaire qui mesure |
| **168+** | L10, L12, L13 selon les D validés. Un build = un lot jouable, pas un mélange | Checklist L17 si elle existe. Sinon la checklist de `AGENTS.md` à la main |

Ordre conseillé des premiers binaires jouables : **164 (copie)** → **165 (tuto ou phrase de justesse)** → notif ou mesure. L’extraction du moteur (L14) n’a pas de numéro de build tant que D16-A n’est pas demandé.

Commande, le jour où c’est voulu, et seulement alors :

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
bundle exec fastlane beta
```

Puis commit du `project.pbxproj` que la lane aura modifié. Pas de `--force`. Pas de `submit`.

---

## 5. Actions hors code

À faire par le développeur. Rien de ceci n’a été exécuté.

1. **App Analytics** — activer le rapport dans App Store Connect (clé Admin). Le script cité par l’évaluation n’est pas dans le dépôt.
2. **Sondage 8.8** — lire les records CloudKit `PlayerSurvey` (3 questions, note 0–10). En tirer un NPS et les raisons de revenir, pour le pitch. Pas un nouveau sondage.
3. **Featuring** — la nomination `ff8e6688-d23f-4222-a4ff-579274bd264e` (plage 18 nov.–2 déc.) existe. Ne pas en créer une seconde. Le 8 nov., `submit` est parti avec `automatic_release: true` sur le build **163**. Vérifier dans ASC si la 8.8 est en vente ou encore en review. Le groupe Featuring est toujours sur **160** : le déplacer est une décision (D5 / éditeurs), pas un automatisme.
4. **Lien éditeurs** — tant que Featuring reste sur 160, le mail et `RELEASE_8.8.md` disent vrai. Le jour du déplacement, mettre à jour le tableau de bord.
5. **Pitch iPad** — retirer « iPad » des mails et d’un futur kit tant que D15-A tient. La Watch, elle, est réelle (Zen light).
6. **Licences** — polices `GoogleSans-Regular.ttf` et `gameboy.ttf` (et les autres `.ttf` hors Changa / Nunito), sons Freesound, musique Soundimage. Écrit avant tout effacement (L8).
7. **Kit presse** — page, 3 GIF de 6 s, vidéo 30 s, logo, fiche d’une page. L’évaluation a raison : le mail ne doit pas demander aux journalistes de réclamer les captures.
8. **Mots-clés ASC** — seul `store/keywords/pt-BR.txt` est versionné. Noter quelque part les mots-clés FR/EN/DE/ES/IT réellement en ligne, ou les exporter. Ne pas les inventer dans git sans copie d’écran ASC.
9. **Seuils** — si D20 n’est pas repris tel quel, écrire les siens. L’évaluation propose : à 60 jours, présenter à des éditeurs seulement si J1 > 35 % et J7 > 12 % sur au moins 500 installations. Sinon, retravailler la boucle avant la com.
10. **Communauté** — l’évaluation demande un rendez-vous hebdo (score du défi) et un lieu (pas seulement @BLOmiG). À décider, pas à coder.
11. **Go fiche 8.9** — `MARKETING_VERSION`, whats-new 6 langues, popup `campaignID` (déjà `8.9` ; nouvel id si les puces changent encore après des « Ne plus montrer »), puis `metadata` / `release` / `submit`. Hors de ce plan d’exécution.

### D20 — Seuils, pour mémoire

L’évaluation fixe un go / no-go. C’est une décision, pas une consigne déjà acceptée.

- **A.** Reprendre ses seuils (J1 35 %, J7 12 %, n ≥ 500).
- **B.** Seuils plus bas, adaptés à 1,4 install / jour (500 installs prennent un an au rythme actuel).
- **C.** Pas de seuil. On continue le jeu pour lui-même (cohérent avec D2-A).

Recommandation : **B** ou **C**. **A** est le seuil d’un éditeur, et le rythme actuel ne l’atteint pas sans une distribution qui n’existe pas.

---

## 6. Correctifs de ce lot (L1)

Faits. Compilation à vérifier avec le scheme `Blomix`. Pas de bump, pas de fastlane, pas de gameplay, pas de DA.

| Fichier | Correction |
| :--- | :--- |
| `fr.lproj/Localizable.strings` | 12 clés de tuto en double. Le parseur garde la **dernière** (`plutil`), déjà alignée sur l’anglais (« Tape sur une colonne… », « Ta bombe casse les blox et les Brix »). Le premier bloc, plus ancien, est retiré. Le texte effectif ne change pas |
| Même fichier | `Cliques` → `Tape` (l’anglais dit *Tap*, l’overlay interactif dit déjà « Tape »). `apparait` / `disparait` → accents. `une brix` / `Cette brix` → `un Brix` / `Ce Brix`, comme le reste du français. `chaine` → `chaîne`. `A vous` → `À vous` (le vouvoiement de la page 3 est conservé) |
| `fr` + `en` `settings.sound.priks_vanish` | « Disparition Priks » / « Priks vanish » → Brix. DE, ES, IT et PT disaient déjà Brix |
| `fr` + `en` `rules.txt` | « Prix » → « Brix ». FR : « Toutes les 10 lancers » → « Tous les 10 lancers ». EN : *included* → *including*. Fichier embarqué, plus affiché : le guide lu par le joueur est `guide.section.*`, déjà en Brix |

### Laissé, parce qu’un doute ou une décision reste

- Tutoiement mêlé (`Ton score`, « À vous de jouer », conseils du jour en vous puis en tu). D10.
- Page 2 : stock de bombes, recharge « toutes les 10 chaînes », « 9 cases autour ». Faux par rapport à `RULES.md`. Le réécrire est D10, pas une coquille.
- Page 3 : bonus « moyenne statistique », « Player Vs Player », « gérer les polices » (le sélecteur de police est du legacy, plus aucun écran ne le lit). D10.
- Nom de clé `tutorial.dont_show_again`. Comportement correct.
- Skin `Alea` sans accent : le même nom propre dans les 6 langues.
- `AGENTS.md` / versions de docs. L7, le jour du bump.
- Numéros de version, `project.pbxproj`, `Info.plist`, fastlane, store, probabilités, accueil, captures.

---

## 7. Ordre après validation (13/11/2026)

1. Décisions écrites en tête de ce fichier. Lots L10, L12, L13, L14, L16 abandonnés. L15 = MAGIX B (D8).
2. D8 (L15), D10 (L2), D13 (L3), D1 (L11), D16-B (L9), D18-B (polices seulement).
3. D11 (L4) seulement une fois que la mesure tourne.
4. D3 + D4 + D5 (L5, L6) et D15-A (textes presse) **après le 2 décembre**. Pas de `metadata` / `release` avant.
5. D2, D7, D9, D12, D14 : rien à coder.
