# Changelog

Toutes les modifications notables du projet sont documentées ici.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).  
Versions alignées sur `MARKETING_VERSION` dans Xcode.

---

## [6.3] — 2026-08 (courant)

Build **117**.

### Corrigé (117)
- **CloudKit Public** : robinet unique (503 / Retry-After) partagé H2H + lobby ; plus de juge H2H au `didBecomeActive` ; juge = ≤3 `pairKey`, 1 flush ; poll défis saute si throttle — l’appariement n’était pas réécrit, il était affamé

### Corrigé (116)
- **H2H** : affichage = historique + Δ de série (plus de `max` qui avalait 2–1 derrière 50–49) ; seed fusionne IDs match/Elo/nom ; juge cloud ne remplace plus un gros plancher par un 33–32

### Corrigé
- **H2H** : une formule d’affichage (récap = Elo) ; lock ne rajoute plus la série ; nouveau Duel lobby reset les Δ ; gagnant **et** perdant écrivent un `PvPH2HEvent` (`matchId` + `reporterId`) ; juge cloud = 1 point / `matchId`, lecture complète sans le `+2` ; 0 CloudKit en manche

### Documenté
- **Passe d’alignement doc ↔ binaire** (aucun changement de jeu) : BRIXED = wipe des autres Brix ; bombe Arcade croix nuke par stage ; +500 grille vide ; SAINTX +200 × stage ; COMBO dès la 1re cascade ; bombe ≠ coup LIGNE ; timer Duel gelé en visée bombe ; reprise Arcade = timer plein du stage ; probabilités de file (Magix d’abord) ; justesse ignore Magix/bombes. PVP_MATCHING : `chfrom_*`, Partie rapide branchée sans skill Elo, overlay série ≥ 1.

### Version
- Marketing **6.3**, build **117**

---

## [6.2] — 2026-08

Build **114** (TestFlight).

### Corrigé (113)
- **COLORX** : overlays blancs de la roulette calés sur la taille des blox (`cell.size`, plus le débord de 40 pt vs 36 pt)
- **Tutoriel** : l’overlay Magix de fin montre **tous** les Magix, plus seulement les 4 premiers

### Corrigé (112)
- **Duel pile** : largeur ≈ un digit du gros score (plus la barre qui s’étirait jusqu’à TEMPS)

### Corrigé (111)
- **Duel pile** : plus de bande de couleur qui fuyait au-dessus des cases (`yScale` sur sprite) ; une **barre continue** 0…50, clipée, hauteur = mètre (lisible même petite)

### Modifié (110)
- **Duel** : le gros score HUD et le score adverse montrent `score % 50` (0…49) ; à l’envoi le chiffre monte à 50 puis pose le reste. Total interne et envoi inchangés ; plus d’explosions 100/1000 en Duel
- **Duel pile** : à droite du gros score, largeur ×2, fill continu (15 pts = 1 + ½) calé sur le roll des `+N` ; couleur = chiffre (`primaryText` + flash chaîne) ; case en cours un peu plus large, stagger si plusieurs cases

### Ajouté (109)
- **Puces LIGNE** : 4 points 2×2 à droite de LIGNE / X/10 (hauteur calée sur les deux lignes) ; allumage rouge = lignes en file ; une puce s’éteint à chaque départ
- **Duel pile d’attaque** : 5 segments à gauche de TEMPS / Xs (même écart que les puces) ; 10 pts / case, vert = `score % 50` ; flash 5/5 à l’envoi puis reste (ex. 80 → 3). HUD seul, calcul d’envoi inchangé

### Modifié (109)
- **Duel** : bande tremblotante = première ligne arrivée (chrono) ; les suivantes s’empilent (puces), plus de remplacement par la dernière attaque
- **Arcade LX** : reste visible pendant l’overlay ; grow ×2 / swap du chiffre au pic / retour 1,0 calés sur pop-in 0,45 + pause 1,0 + fade 0,35 (plus de hide ni petit pulse)

### Corrigé
- **Classement Duel** : `X - Y` pour **tous** les adversaires déjà joués (pont nom / récents), pas seulement le dernier match — toujours 0 CloudKit au scroll

### Version
- Marketing **6.2**, builds 109–114

---

## [6.1] — 2026-08

### Corrigé (108)
- **Duel / accueil** : plus de reprise Arcade fantôme (grille de prép sauvée) ; Duel depuis le menu → retour accueil
- **Classement Duel** : `X - Y` rétabli (précalcul 1 fois + alias en mémoire, 0 CloudKit au scroll)
- **H2H** : même lecture récap / Duel ; juge cloud hors tableau

### Modifié (106)
- Lexique joueur : **Arcade** (badge / onglet **Arc.**) à la place de Solo ; **Duel** à la place de P vs P
- Accueil : plus de ligne Elo ; **4ᵉ disque** Duel (rang Elo) à droite de Zen
- Overlay de connexion et onglet classement : **Duel**

Build **105** (TestFlight).

### Ajouté
- **Rejouer** sur le game over Solo / Zen (même mode, sans passer par l’accueil)
- **Écran record personnel** (titre + score + rang GC si dispo, OK → game over)
- Thème Sombre / Clair dans **Réglages**
- Interrupteur chrome custom « OK pour être défié » (lobby)

### Modifié
- Accueil compressé : nom + Elo sur une ligne, rangée d’icônes SF, Solo pleine largeur
- Slot-machine du titre uniquement à froid (splash)
- Menu ☰ : Accueil · Scores · Réglages ; pause du timer Solo (reprise du reste)
- Lobby : hero **Joueurs disponibles**, En ligne + Local sur l’écran, plus de bouton Adversaires récents
- Tutoriel uniquement depuis l’accueil
- Typo figée : Changa (display + grille) / Nunito (chrome : Regular / Medium / SemiBold)
- LIGNE Zen alignée sur Solo (haut gauche)
- Pulse du badge de stage au passage de palier
- Launch storyboard noir ; ambiants plus calmes sur les écrans texte

### Retiré
- Picker de polices (Alfa Slab, Dyna Puff hors jeu)
- Hint UI / ghost hint (l’analyse et le pire coup restent)
- Overlay tutoriel paginé du chemin joueur

### Corrigé
- **PvP invitations croisées** (bannière Récents + défi Elo) : un seul lancement de match, `targetPlayerID` sur l’Elo, pas de double dismiss
- **PvP défi (103)** : le 2ᵉ `beginPvP` (poll roster / delegate) ne `disconnect` plus le même `GKMatch` — plus de « Connexion perdue » ~10 s après l’overlay de préparation
- **H2H** : lecture CloudKit d’un seul duo après retour à l’accueil ; **105** : le cloud l’emporte si plus de pending et lecture plausible (plus de 34–33 vs 34–34 bloqué par le plancher)
- **H2H (106)** : une vérité d’affichage (récap = Duel = max live/cache/plancher) ; un cloud 28–30 n’écrase plus un 34–34 ; lancement Duel pose l’overlay P vs P avant de fermer les modales (plus de flash accueil)
- **H2H Elo** : plus de CloudKit / alias par cellule (serpent + scroll figés) ; précalcul O(1) ; juge 1 duo au foreground, pas à l’ouverture Duel ; dernier adversaire persisté (le perdant rattrape 34–35 après relance)
- **Défi CloudKit** : Refuser ne réaffiche plus la bannière 8 s plus tard ; badge « En match » lit `inMatch` en Int64
- **Accueil** : Elo et rangs des disques (#n) de nouveau après connexion Game Center (lookup du nom dans la ligne compressée)

### Version
- Marketing **6.1**, builds 102–108

---

## [6.0] — 2026-08

Build **101** (TestFlight).

### Ajouté
- **Serpentard d’attente** (`BlomixPvPSearchBlocksView`) : grille **10×10**, blox 11 / gap 1, serpent long. 16, tick/fade 0,10 s — lobby, listes, classements, overlay « P vs P », écrans résultat
- **BOMBX** : SFX procédural `playBombxStain` calé sur les vagues R0…R3

### Modifié
- **Overlay « P vs P »** : serpent UIKit bridge ; stack titre → serpent → phrases ; fade après dismiss lobby
- **Écran résultat PvP** : serpent pendant attente ; Elo **cache local** (~0,35 s) puis boutons libres ; GC en fire-and-forget ; Revanche grisée, Accueil libre ; boutons ancrés bas d’écran
- **Récap série** : dès **1** partie ; empilé sur le résultat ; present d’abord, flush CloudKit H2H après
- **Reprise solo après PvP** : snapshot mémoire figé à l’entrée (grille, score, file, bombes, stage, Zen…)

### Corrigé
- **H2H freeze 20–25 s** en fin de match / Accueil→récap : expansion d’alias plafonnée (≤ 8), writes UserDefaults différées (plus de `keys=82` monstre sur MainActor)
- **Récap qui rebondit** vers le résultat à la déco peer : pas de dismiss résultat si récap déjà empilé
- **Grille solo vide** après PvP : une seule capture, non écrasée par la prep

### Version
- Marketing **6.0**, build **101**

---

## [5.9] — 2026-08

Build **95** (TestFlight).

### Corrigé
- **Freeze 1er blox** : snapshot H2H différé (~0,4 s après boards ready), plus au markHandshakeComplete
- **Cumul qui se re-casse** : LOCK fin de série absorbe les Δ (baseline = total figé) ; seed nouvelle série = max(cache, committed) ; pas de double comptage baseline+série
- **Flash solo/grille** : Accueil depuis résultat → enchaîne l’écran fin de série **sans** dismiss préalable (garde l’overlay résultat)

### (94)
- Snapshot max-merge + forfait déco compté
- Version marketing **5.9** (build **95**)

---

## [5.8] — 2026-08

Build **79** (TestFlight).

### Ajouté
- **PvP H2H (total victoires)** : juge CloudKit Public `PvPH2HEvent` (1 point = 1 manche gagnée) ; cache + pending locaux ; affichage **Total historique** en fin de série de revanches
  - Module isolé `BlomixPvPH2HManager` — échec cloud = ligne total absente/stale **uniquement** (match / Elo / reconnexion intacts)
  - Writer = vainqueur (record `h2h_{uuid}`) ; lecture query `pairKey` ; flush au foreground

### Modifié
- **Écran résultat PvP** : score de la **série** en cours (entre Elo et boutons Revanche / Accueil)
- **Fin de série** : total H2H sous le bouton OK, libellé **Total historique**
- **`ITSAppUsesNonExemptEncryption` = false** dans `Info.plist` — plus de questionnaire Export Compliance à chaque upload ASC / TestFlight
- Version marketing **5.8** (build **79**)

---

## [5.7] — 2026-08

Build **76** (TestFlight).

### Ajouté
- **PvP — série de revanches** : compteur de victoires session (local only) ; HUD `ABC  X  ·  Y  DEF` après lancement d’une revanche ; overlay fin de série si ≥ 2 parties (Accueil / timeout / déco) — online + Multipeer ; Elo inchangé par partie
- **Crédits en cartes** : `BlomixCreditsViewController` (header BLOMIX + tagline + version, sections Studio/Code/Polices/Sons/Musique/Palette/Beta, accent skin, Jour/Nuit)

### Modifié
- **Game Center Solo/Zen** : sync `max(local, pending)` ; pending effacé seulement après submit OK ; réconciliation **local > GC** (auth + foreground) — récupère un hiscore Zen offline non poussé
- **Overlay défi Elo** : fond thème chrome (plus de noir fixe en mode Jour)
- **Timer Solo** : affiche tout de suite 32 s au lancement (plus de flash 4 s/8 s d’un stage précédent)
- **SCRUMBLX** : fin d’animation robuste (attente = max sur toutes les lignes + snapshot + token)
- **Blox ambiants** : UIKit aligné SK ; densité ×2 ; taille aléatoire 9…18 pt
- Version marketing **5.7** (build **76**)

---

## [5.6] — 2026-08

Build **74**.

### Ajouté
- **Accueil — lien Crédits** : « Réglages · Tutoriel · **Crédits** » ; modal `BlomixPlainTextModalViewController` (thème Sombre/Clair, police joueur, bouton Fermer) alimentée par `credits.txt` (FR/EN)

### Modifié
- **PvP Local (Multipeer) — reconnexion mid-match** :
  - Découverte maintenue pendant le match ; relance effective advertiser/browser après drop
  - Rebuild de `MCSession` + re-invite déterministe (anti-zombie / `notConnected` sans récupération)
  - Silence peer local → `forceTransportReset` ; callback `onTransportRestored` annule grace + keepAlive + rejoue critiques
  - Grace locale ~45 s, debounce overlay ~12 s ; logs `local_session_rebuild` / `local_peer_reconnected` / …
- Indicateur scroll modal texte (crédits) adapté au thème chrome (Sombre/Clair)
- Version marketing **5.6** (build **74**)

---

## [5.5] — 2026-08

Build **71**.

### Ajouté
- **PvP Local** (Partie rapide → **Local** / **En ligne**) :
  - MultipeerConnectivity (Bluetooth + Wi‑Fi local, **sans Internet**)
  - Prérequis : cache identité Game Center (auth au moins une fois sur l’appareil)
  - Handshake identité + profil Elo ; même `BlomixPvPMatchCoordinator` (canal dual GK / local)
  - Elo toujours calculé ; pending submit si GC offline (comme Solo/Zen)
  - UI choix + alertes en **dialogue in-app BLOMIX** (`BlomixInAppDialogView`, thèmes Sombre/Clair) — plus d’action sheet système
  - l10n FR/EN/DE/ES/IT ; `NSLocalNetworkUsageDescription` + Bonjour `_blomix-pvp`
  - Module `BlomixPvPLocalSession.swift`

### Modifié
- **Game Center offline** : files d’attente séparées Solo (`BlomixPendingGCScore`) / Zen (`BlomixPendingZenGCScore`) ; flush au succès d’auth vers le bon leaderboard ; resync **moyenne** locale (`BlomixAverageScore_v1`) à chaque auth — même robustesse Solo / Zen / moyenne
- **Elo offline** : pending profil + identité GC en cache pour le Local
- Version marketing **5.5** (build **71**)

---

## [5.4] — 2026-07

Build **70**.

### Ajouté
- **BOMBX** (Magix `B`) : tâche 3 rangs sur cases déjà occupées ; chaînes ; dots couleur → HUD bombes (1 salve, +1 garanti à l’arrivée, aussi si 0 clear) ; en plus des dots score ; rareté ≈ SAINTX. Solo/Zen (pas de Magix en PvP).

### Modifié
- **HUD bombe** : à stock 0 (et bombe non armée), arrêt du halo et des particules orbitales
- **Tutoriel** : pas de Brix dans les lignes entrantes (remplacement couleur pure)
- **Icône d’app** : nouveau logo (`AppIcon` / `icon_blomix.png`)
- Version marketing **5.4** (build **70**)

---

## [5.3] — 2026-07

Build **69**.

### Ajouté
- **Partage BLOMIX** (accueil + game over Solo/Zen) :
  - Chip **Partager** sur l’accueil (icône avion en papier custom + libellé) sous le toggle Sombre/Clair
  - Bouton **Partager** au game over (3ᵉ sous Classement) avec **carte image 1:1** (grille finale, skin + thème chrome, score, bandeau « Nouveau record » si PB)
  - Share sheet système (`UIActivityViewController`) : texte challenge + URL App Store `id6762053543` ; image au GO uniquement
  - Messages localisés FR/EN/DE/ES/IT (`share.*`) ; score accueil = best Solo sinon Zen sinon invitation sans score
  - Module `BlomixShareComposer` + `BlomixAppearance.shareButtonTexture`

### Modifié
- **Quitter la partie (Zen)** : message adapté — « Ton score ne sera pas sauvegardé » (plus de mention de la moyenne Solo) ; titre et boutons inchangés
- Version marketing **5.3** (build **69**)

---

## [5.2] — 2026-07

Build **67** (fonctionnelle).

### Ajouté
- **`AGENTS.md`** à la racine — brief opérationnel pour agents / contributeurs (architecture, conventions, boucle de clôture l10n / doc / git)
- **PvP robustesse (vagues 1–3)** :
  - `protocolVersion` au handshake + message d’update si incompatible
  - File d’envoi + ack pour messages critiques (`iLost`, attaques, revanche…)
  - Heartbeat + grace déco mid-game (4 s) avec overlay « Reconnexion… »
  - Ack de fin de partie (`ackVictory`)
  - `attackId` anti-doublon sur les lignes d’attaque
  - Lobby : bouton **Partie rapide** (auto-match)
  - Détection défi croisé CloudKit ; logs structurés `[PvP]`
  - Copy mode A : invitation in-app, adversaire doit avoir l’app ouverte
- **Classement Elo multipage** : charge jusqu’à N pages GC, filtre les entrées « jamais joué » (800/0), plus d’init GC 800/0 qui polluait le top
- **Dialogs in-app BLOMIX** : erreurs / timeouts PvP et défis unifiés (`BlomixInAppDialogView`) à la place des `UIAlertController` système

### Modifié
- **Transitions** (stage / Zen / PvP / **tutoriel**) : fill orange skin + contour thématisé **sans halo** (lisibilité par le contour seul)
- **Tutoriel** : même pipeline sticker + pop-in central (plus de slide latéral ni voile) ; lancement **sur la grille** (accueil masqué avant l’overlay)
- **PvP** : plus de fallback RNG local (anti-désync) ; reset défensif `isInActiveMatch` au `didBecomeActive`
- **PvP lancement** : overlay « P vs P » sur **grille vide** (plus sur l’accueil) ; si peer déjà connecté, check immédiat + poll roster (évite handshake qui tourne dans le vide)
- **Sauvegarde solo** : légalisation gravité/chaînes **toujours** avant persist **et** à la reprise (plus de blocs « flottants » après restore mid-vague)
- Game over : libellé **justesse** (FR) / placement / … (plus « optimalité ») — l10n FR/EN/DE/ES/IT
- **Hygiène Swift 6 / Xcode 26** : `findMatch` async, observers MainActor, completions Sendable, `contentEdgeInsets` → `blomixContentInsets`, police via `CTFontManagerRegisterFontsForURL`, assets `.png`/`.jpg`, settings projet (`LastUpgradeCheck` 2620, `DEAD_CODE_STRIPPING`)
- Version marketing **5.2** (build **67**)

---

## [5.1] — 2026-07

Build **63**.

### Ajouté
- **Thème chrome Sombre / Clair** (`BlomixAppearance`) — orthogonal aux skins de couleurs des blox (`color_skins.json`)
- Toggle soleil / lune sur l’écran d’accueil uniquement (manuel in-app ; ne suit pas le mode système) ; défaut = **Sombre** (look historique)
- Tokens UI pour fonds, textes, chips inversés, cases vides, voiles, panneaux, halos Magix/bombes/disques, colonnes ghost, popups de score
- Tokens **ombre chips** (`chipShadowColor`) et **transitions** (`transitionOutlineColor` / `transitionHaloColor`)

### Modifié
- Chrome gameplay, modales UIKit (réglages, PvP, classement, tutoriel) et boutons SK/UIKit branchés sur les tokens
- **Game over** et **pire coup** : voile beige `#F5EEDF` @ 0,94 + textes foncés en Clair ; Sombre inchangé (voile noir, textes clairs) ; accents d’optimalité inchangés
- Splash studio : fond toujours noir (logo néon) ; thème appliqué après le splash
- Pastilles radio réglages (police / set de couleurs) : gris moyen (`tertiaryText`) pour la lisibilité en Clair
- **Ombre des chips** en Sombre : gris clair (lisible sur noir) ; Clair inchangé (ombre noire)
- **Transitions stage / Zen / PvP** : fill orange skin inchangé ; contour et halo thématisés (Sombre : blanc + halo gris clair ; Clair : contour foncé + halo noir)
- Version marketing **5.1** (build 63)

---

## [5.0] — 2026-07

Build **61**.

### Modifié
- **Écran d'accueil** : refonte layout — carte joueur (nom, Elo cliquable, 3 disques SOLO/MOY./ZEN), liens « Réglages · Tutoriel », zone de jeu hero **Solo** + **PvP / Zen** côte à côte ; boutons Scores et Crédits retirés (accès classement via disques et ligne Elo)
- **Bouton Solo hero** : accent dynamique skin (1re couleur blox, bordure 2 pt) + fond `#232323` teinté à 22 % (`applyHeroAccent`)
- **Disques de rang** : libellé `#rang` rendu au-dessus du crop shader (sibling dans `discsContainer`) ; fetch GC avec repli `loadEntries(for: [localPlayer])`
- **LeaderboardViewController** : onglet initial `.elo` pour la ligne Elo de l'accueil
- **Animations Brix** : profil de mouvement distinct des blox couleur — stretch en vol plus discret (`BrixFlightStretch`), bounce à l'atterrissage moins marqué (`BrixLandingBounce`), vitesse et traîne inchangées
- **Disparition Brix** : pop blanc + implosion (remplace le spin 360°) ; paillettes **carrées** colorées (11–15 + 15 micro-carrés, même timing que dissolution blox)
- **Transitions stage / Zen / PvP** : texte **orange skin** + contour blanc + halo sombre (label fantôme) — remplace le sticker rasterisé (meilleur alignement, moins de code)
- Version marketing **5.0** (build 61)

---

## [4.9] — 2026-07

Build **60** — en revue App Store Connect.

### Ajouté
- Documentation **[PVP_MATCHING.md](PVP_MATCHING.md)** : appariement, défis CloudKit, invites GameKit, déconnexion et revanche
- Chaînes i18n déconnexion neutre et échec de connexion PvP (`pvp.disconnect.neutral_message`, `pvp.connection_failed.*`)

### Modifié
- Transitions **stage solo**, **Zen** et **préparation PvP** : pop-in central avec rebond (0,45 s), sans voile noir ; textes entourés d’un **halo blanc** (15 pt / 18 pt sur les grands titres)
- Overlay **tutoriel** inchangé (slide latéral + fond semi-transparent)
- **Défis joueurs disponibles** : record CloudKit `chfrom_{challenger}` (permissions Public DB) à la place de `chal_{défié}` qui provoquait `WRITE operation not permitted`
- **Revanche PvP** : overlay de connexion, retry réseau (2 s), timeout 45 s, `helloSeed` après `expectedPlayerCount == 0`, annulation explicite (`rematchCancel`)
- **Déconnexion PvP** : fermeture de l’écran résultat avant l’overlay, messages adaptés (partie en cours / écran résultat / échec handshake)
- Version marketing **4.9** (build 60)

### Corrigé
- **SCRUMBLX** : les cases vidées (−1 Brix → 0, case d’atterrissage) restent en **gris fond de grille** et participent au décalage horizontal (plus de « trous noirs »)
- **Sauvegarde solo** : prise en compte des poses, lignes injectées et chaînes en cours de dissolution avant écriture du fichier
- **Lobby PvP — défis** : échec CloudKit remonté à l’UI (plus de faux « Invitation envoyée »), upsert robuste, lecture `Int64` pour `matchPlayerGroup`
- **Revanche** : UI « Lancement… » synchronisée avec le coordinateur (plus de blocage asymétrique entre joueurs)
- **Handshake PvP** : échec silencieux remplacé par overlay « Connexion perdue »

---

## [4.8] — 2026-07

### Ajouté
- Localisation in-app **Allemand**, **Espagnol**, **Italien** (`de` / `es` / `it` : `Localizable.strings`, tips, citations, `InfoPlist.strings`)
- ~28 clés `BlomixL10n` (HUD, game over, PvP Game Center, overlays stage/Zen, disques classement)

### Modifié
- Extraction des chaînes UI encore codées en dur (FR/EN) vers `BlomixL10n`
- Taglines FR/EN alignées ASO ; bouton tutoriel « Skip » redimensionné dynamiquement
- `CFBundleLocalizations` étendu à 5 langues ; version marketing **4.8** (build 56)
- Documentation localisation et contexte projet mises à jour

---

## [4.7] — 2026-07

### Ajouté
- Documentation complète dans `docs/` (règles, contexte technique, VFX, évaluation, glossaire, dev, localisation)
- Spécification Juice Spec / VFX Bible ([VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md))
- `.gitignore` pour fichiers locaux Xcode et macOS

### Modifié
- Équilibrage audio global et simplification de l'UI des réglages sonores
- Documentation alignée sur le code v4.7 (modes stagé/Zen, hints, scoring, PvP)

---

## [4.4] — 2026

### Modifié
- Améliorations PvP (matchmaking, synchronisation, UI lobby)
- Animations blox améliorées (placement, suppression, feedback visuel)

---

## [4.0] — 2026

### Ajouté
- Mode PvP Game Center (1 vs 1, RNG partagé, attaques par paliers)
- Système Elo PvP (`BlomixEloManager`)
- Défis CloudKit asynchrones

### Modifié
- Refonte audio (sons procéduraux Magix, mix par stage)

---

## [3.0] — 2025

### Ajouté
- Mode Zen (sans timer ni stages)
- Tutoriel interactif au premier lancement
- Moteur d'évaluation v2 (`BlomixMoveAnalyzer`) et système de hints
- Sauvegarde solo v7 (reprise de partie)
- Localisation FR/EN structurée (`BlomixL10n`)
- Skins de couleurs personnalisables (`color_skins.json`)

### Modifié
- Système de stages solo (6 paliers, multiplicateur progressif)
- HUD SpriteKit (score animé, timer, file P0/P1/P2)

---

## [1.2] — 2025

### Ajouté
- Version iOS native (migration depuis la version web)
- Grille 8×8, chaînes 8-connexes, Brix, blocs Magix
- Lignes entrantes et bombes
- Game Center (classements solo)

### Notes
- Tag `v1.2 pre-bevel` : état avant ajout des effets lumière/ombre sur les blox

---

## [Non publié]

### Documentation
- Index `docs/README.md`, guide contribution, politique de confidentialité HTML
