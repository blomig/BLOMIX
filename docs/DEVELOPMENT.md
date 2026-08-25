# Blomix — Guide de développement

> **Version de référence** : 6.6 (local, TestFlight)  
> **Dernière mise à jour** : août 2026

---

## Prérequis

| Outil | Version minimale |
|---|---|
| macOS | Compatible Xcode 16 |
| Xcode | 16+ (Swift 6) |
| iOS (cible) | 18.0 (`IPHONEOS_DEPLOYMENT_TARGET`) |
| Compte Apple Developer | Requis pour Game Center, CloudKit et déploiement |
| Ruby + Bundler | Pour Fastlane (`bundle install` à la racine) |

---

## Ouvrir et compiler

```bash
git clone https://github.com/blomig/BLOMIX.git
cd BLOMIX
open Blomix/Blomix.xcodeproj
```

1. Scheme **Blomix** → destination simulateur ou appareil physique.
2. **Signing & Capabilities** : renseigner votre `DEVELOPMENT_TEAM` (le projet référence `blomig.BLOMIX`).
3. `⌘R` pour build et run.

| Paramètre Xcode | Valeur actuelle |
|---|---|
| `MARKETING_VERSION` | 6.6 (local) |
| `CURRENT_PROJECT_VERSION` | 123 |
| `PRODUCT_BUNDLE_IDENTIFIER` | `blomig.BLOMIX` |
| `SWIFT_VERSION` | 6.0 |
| Orientations | Portrait uniquement |

---

## Capabilities et services

Fichier : `Blomix/Blomix/Blomix.entitlements`

| Capability | Usage |
|---|---|
| **Game Center** | Classements solo/Zen, matchmaking PvP, invitations |
| **CloudKit** | Défis PvP asynchrones (`iCloud.blomig.BLOMIX`) |
| **Push (APS)** | Debug : `development` (`Blomix.entitlements`). Release / TestFlight / App Store : `production` (`BlomixRelease.entitlements`) |

### Tester le PvP

- Deux appareils ou simulateurs avec des comptes Game Center **distincts**.
- Connexion Game Center active dans Réglages iOS.
- Le RNG partagé et la synchronisation sont gérés par `BlomixPvPNetworking.swift`.
- Logique d’appariement et check-list de debug : [PVP_MATCHING.md](PVP_MATCHING.md).

### Tester les classements

- Authentification Game Center au lancement (`GameCenterManager.swift`, `ScoreManager.swift`).
- Simulateur : se connecter via Réglages → Game Center.

---

## Architecture (résumé)

La logique gameplay est centralisée dans `GameScene.swift` (~14,5k lignes) :

```
GameViewController          # Root UIKit, tutoriel, invitations GC
    └── SKView
        └── GameScene       # Grille, placement, Magix, stages, HUD SpriteKit

BlomixMoveAnalyzer          # Évaluation pure Swift (sans SpriteKit)
BlomixPvPNetworking         # GKMatch, état partagé, attaques
BlomixPublicCloudGate       # Throttle CloudKit Public (H2H + lobby)
BlomixProceduralSFX         # Sons procéduraux Magix / feedback
BlomixL10n                  # Pont typé vers Localizable.strings
```

Détail complet : [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) §16.

---

## Fichiers de configuration importants

| Fichier | Rôle |
|---|---|
| `color_skins.json` | Skins de couleurs (Default + Perso) |
| `en.lproj/` / `fr.lproj/` | Chaînes UI, tips, citations |
| `Assets.xcassets/WebImages/` | Sprites blox, Magix, HUD, écrans |
| `Info.plist` | Polices embarquées, localisations, Game Center |

---

## Ajouter un son

1. Placer le fichier dans `Blomix/Blomix/Sounds/` (formats `.wav` / `.mp3`).
2. Référencer via l'enum `BlomixMatchSFX` dans `GameScene.swift`.
3. Documenter dans [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md) (déclencheur, timing, volume).

Sons procéduraux : `BlomixProceduralSFX.swift` (pas de fichier audio).

---

## Ajouter une chaîne traduite

Voir [LOCALIZATION.md](LOCALIZATION.md). En bref :

1. Ajouter la propriété dans `BlomixL10n.swift`.
2. Ajouter la clé dans `en.lproj/Localizable.strings` **et** `fr.lproj/Localizable.strings`.
3. Utiliser `BlomixL10n.maCle` dans le code (jamais de chaîne en dur dans l'UI).

---

## Debug et flags utiles

| Flag / constante | Fichier | Effet |
|---|---|---|
| `evalEnabled` | `BlomixMoveAnalyzer.swift` | Active le moteur d'évaluation |
| `realtimeFeedbackEnabled` | `BlomixMoveAnalyzer.swift` | Popups `!!` / `?` en jeu (désactivé en prod) |
| `MagixRules.spawnProbabilityByKind` | `GameScene.swift` | Probabilités de spawn Magix |
| `PriksRules.spawnProbability` | `GameScene.swift` | Probabilité de spawn Brix |

---

## Tests

Aucune cible de tests unitaires n'est configurée actuellement.  
Validation manuelle recommandée :

- [ ] Partie solo complète (6 stages + game over)
- [ ] Mode Zen (pas de timer)
- [ ] Chaque variante Magix (spawn forcé en debug si besoin) — **6.5 : SLASHX** centre / bord / coin
- [ ] Sauvegarde / reprise (`BlomixSoloSaveManager`)
- [ ] PvP invitation + match complet
- [ ] Classements Game Center
- [ ] Changement de langue FR ↔ EN
- [ ] Réglages audio (mix SFX / musique)
- [ ] **6.5** Splash → popup TWISTX § / SLASHX (Ok = session, Ne plus montrer = définitif)
- [ ] **6.5** Guide : 9 Magix, glyphe TWISTX = §
- [ ] **6.5** Game Over : % / justesse au-dessus de la barre

---

## Maintenance de la documentation

Lors d'une évolution majeure du gameplay, mettre à jour **en priorité** :

1. `RULES.md` si les règles joueur changent
2. `PROJECT_CONTEXT.md` pour la référence technique
3. `VFX_AND_ANIMATIONS.md` pour tout effet visuel ou sonore
4. `EVAL.md` si la fonction d'évaluation change
5. `GLOSSARY.md` si un terme est ajouté ou renommé
6. `CHANGELOG.md` à chaque release
7. `store/whats-new/` (5 langues) à chaque **version marketing**

Voir [CONTRIBUTING.md](CONTRIBUTING.md) pour les conventions de commit et de nommage.

---

## Déploiement App Store Connect

Les champs **Nouveautés** et **Texte promotionnel** ne sont **pas** dans l’IPA. Source de vérité : `store/whats-new/` et `store/promotional-text/` (5 locales : `en-US`, `fr-FR`, `de-DE`, `es-ES`, `it-IT`). Fastlane les pousse via l’API ; **ne pas** lancer `fastlane deliver init` (ça duplique toute la fiche et peut écraser description / captures).

Rédaction : [LOCALIZATION.md](LOCALIZATION.md), `store/README.md`. À chaque `MARKETING_VERSION`, écrire les 5 Nouveautés dans le même lot que le CHANGELOG. Le texte promo est **figé** (≤ 170 car.) — on le re-pousse parce qu’Apple le vide souvent à la création de version.

### Prérequis (une fois)

1. App Store Connect → Users and Access → Integrations → **App Store Connect API** → Team Key, rôle **App Manager**.
2. Enregistrer le `.p8` hors git, ex. `~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8`.
3. `cp .env.example .env` et remplir `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.
4. Ruby **≥ 3.2** (pas le Ruby système Apple 2.6) :

```bash
brew install ruby@3.3
echo 'export PATH="/opt/homebrew/opt/ruby@3.3/bin:$PATH"' >> ~/.zshrc
hash -r
ruby -v   # 3.3.x
bundle install
```

`xcode-select` doit pointer sur **Xcode.app** (pas les Command Line Tools), ou exporter :

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
```

Le Fastfile le pose par défaut si la variable est vide.

La clé n’est pas dans le dépôt. Sans `.env`, `validate` fonctionne ; `metadata` / `beta` / `release` / `submit` s’arrêtent avec un message explicite.

### Lanes

Depuis la racine du dépôt :

```bash
bundle exec fastlane validate    # store/ + entitlements (aucun réseau ASC)
bundle exec fastlane metadata    # Nouveautés + promo, 5 langues
bundle exec fastlane beta        # archive Release → TestFlight
bundle exec fastlane release     # archive + binaire + textes — PAS de review
bundle exec fastlane submit      # envoi à la review (irréversible)
```

| Variable | Effet |
|---|---|
| `DRY_RUN=1` | `metadata` : génère `fastlane/metadata/.generated/` sans upload |
| `SKIP_WAIT=1` | `beta` : ne pas attendre la fin du processing |
| `CLEAN=0` | pas de `clean` xcodebuild |
| `EDIT_LIVE=1` | `metadata` : écrit le promo sur la version **en vente** |

`release` et `beta` bumpent `CURRENT_PROJECT_VERSION` : `max(local, dernier build ASC + 1)`. **Committer le pbxproj** après un bump.

Fastlane nomme l’italien `it` (pas `it-IT`) dans le dossier généré ; les fichiers `store/**/it-IT.txt` restent la source de vérité.

`submit` laisse la version en *Pending Developer Release* (`automatic_release: false`) — le bouton Release reste manuel dans ASC.

### Checklist release

1. `store/whats-new/` à jour (5 langues, mêmes puces) + CHANGELOG.
2. `bundle exec fastlane validate`
3. `bundle exec fastlane release` (ou `beta` puis `metadata`)
4. Vérifier dans ASC : Nouveautés / promo, build **Valid**, APS production.
5. TestFlight interne.
6. `bundle exec fastlane submit` quand le build est traité.
7. Après approbation Apple : Release manuel dans ASC.

Ce que le pipeline **ne** touche **pas** : description, mots-clés, captures, App Preview, age rating, prix.

### Entitlements push

| Config Xcode | Fichier | `aps-environment` |
|---|---|---|
| Debug | `Blomix/Blomix.entitlements` | `development` |
| Release | `Blomix/BlomixRelease.entitlements` | `production` |

Export compliance : `ITSAppUsesNonExemptEncryption = false` dans `Info.plist` (HTTPS / services Apple uniquement).
