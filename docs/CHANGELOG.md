# Changelog

Toutes les modifications notables du projet sont documentées ici.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).  
Versions alignées sur `MARKETING_VERSION` dans Xcode.

---

## [5.2] — 2026-07 (courant)

Build **64**.

### Ajouté
- **`AGENTS.md`** à la racine — brief opérationnel pour agents / contributeurs (architecture, conventions, boucle de clôture l10n / doc / git)

### Modifié
- **Transitions** (stage / Zen / PvP / **tutoriel**) : fill orange skin + contour thématisé **sans halo** (lisibilité par le contour seul)
- **Tutoriel** : même pipeline sticker + pop-in central (plus de slide latéral ni voile) ; lancement **sur la grille** (accueil masqué avant l’overlay)
- Version marketing **5.2** (build 64)

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
