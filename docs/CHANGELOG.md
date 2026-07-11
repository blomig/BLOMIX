# Changelog

Toutes les modifications notables du projet sont documentées ici.

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).  
Versions alignées sur `MARKETING_VERSION` dans Xcode.

---

## [4.8] — 2026-07 (courant)

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
