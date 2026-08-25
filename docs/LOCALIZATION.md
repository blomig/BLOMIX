# Blomix — Guide de localisation

> **Langues supportées** : Français (`fr`), Anglais (`en`), Allemand (`de`), Espagnol (`es`), Italien (`it`)  
> **Version de référence** : 6.6 (local, TestFlight)

---

## Architecture

```
Blomix/Blomix/
├── BlomixL10n.swift          # Pont typé (point d'entrée code)
├── en.lproj/
│   ├── Localizable.strings   # Chaînes UI principales
│   ├── tips_of_day.json
│   ├── gameover_quotes.json
│   └── InfoPlist.strings     # NSGKFriendListUsageDescription
├── fr.lproj/
│   ├── Localizable.strings
│   ├── tips_of_day.json
│   ├── gameover_quotes.json
│   └── InfoPlist.strings
├── de.lproj/
    ├── Localizable.strings
    ├── tips_of_day.json
    ├── gameover_quotes.json
    └── InfoPlist.strings
├── es.lproj/
│   ├── Localizable.strings
│   ├── tips_of_day.json
│   ├── gameover_quotes.json
│   └── InfoPlist.strings
└── it.lproj/
    ├── Localizable.strings
    ├── tips_of_day.json
    ├── gameover_quotes.json
    └── InfoPlist.strings
```

Fichiers legacy (encore référencés en fallback) :
- `rules.txt` — anciennes règles statiques (legacy ; non exposé par l’UI moderne)
- `credits.txt` — legacy (non branché UI) ; crédits via clés `credits.section.*` + `BlomixCreditsViewController`  
- Overlay tutoriel paginé UIKit (`GameTutorialOverlayView`) — legacy ; le chemin joueur est le tuto interactif dans `GameScene`

L'UI moderne utilise `BlomixL10n` pour les chaînes ; le tutoriel remplace l’ancien `rules.txt`.

---

## Ajouter une chaîne UI

### 1. Déclarer dans `BlomixL10n.swift`

```swift
// MARK: - Ma section

static var monBouton: String { tr("ma_section.mon_bouton", comment: "Description pour traducteur") }

static func scoreFormat(_ points: Int) -> String {
    String(format: tr("ma_section.score_format", comment: "%lld = score"), points)
}
```

Conventions de clés : `section.sous_section` en snake_case (ex. `game_over.restart`, `hud.next_blox`).

### 2. Ajouter les traductions

**`en.lproj/Localizable.strings`**
```
"ma_section.mon_bouton" = "My button";
"ma_section.score_format" = "Score: %lld";
```

**`fr.lproj/Localizable.strings`** (et `de` / `es` / `it` si la clé est visible dans ces langues)
```
"ma_section.mon_bouton" = "Mon bouton";
"ma_section.score_format" = "Score : %lld";
```

### 3. Utiliser dans le code

```swift
label.text = BlomixL10n.monBouton
scoreLabel.text = BlomixL10n.scoreFormat(1250)
```

> Ne pas utiliser `String(localized:)` pour les clés dynamiques — `BlomixL10n.tr()` utilise `NSLocalizedString` à la place.

---

## Nouveautés App Store (hors bundle)

Le champ **What’s New** d’App Store Connect n’est **pas** une chaîne `lproj` et n’est **pas** lu dans l’IPA. Source de vérité : `store/whats-new/`. **Systématique** à chaque version marketing (même lot que le CHANGELOG) — Fastlane pousse ensuite vers ASC (`metadata` / `release`).

### Fichiers (toujours les 5)

| Fichier | Locale ASC | `lproj` |
|---|---|---|
| `store/whats-new/en-US.txt` | English (U.S.) | `en` |
| `store/whats-new/fr-FR.txt` | French | `fr` |
| `store/whats-new/de-DE.txt` | German | `de` |
| `store/whats-new/es-ES.txt` | Spanish (Spain) | `es` |
| `store/whats-new/it-IT.txt` | Italian | `it` |

### Rédaction

1. Partir du **bénéfice joueur** de la version (spec / CHANGELOG), pas des noms de fonctions.
2. FR d’abord, puis EN / DE / ES / IT **dans le même lot**. Même nombre de puces, même ordre.
3. Puces courtes (`• …`). Limite Apple : 4000 caractères. Noms Magix **non traduits**.
4. Ne pas recopier `DOCS/CHANGELOG.md`. Ne pas ajouter à `BlomixL10n` ni au target Xcode.
5. Un lot qui change encore le bénéfice joueur **de cette version** : rafraîchir les **5** fichiers.

Détail release : `store/whats-new/README.md`.

### Popup in-app (accueil 6.5)

Après le splash, une fois par campagne (`BlomixWhatsNew`, clé `blomix_whatsnew_dont_show_6.5_slashx_twistx`) :

| Clé | Usage |
|---|---|
| `whatsnew.title` | Titre |
| `whatsnew.twistx` | Ligne TWISTX + sprite § |
| `whatsnew.slashx` | Ligne SLASHX + sprite X |
| `whatsnew.dont_show` | Bouton définitif ; `generic.ok` = cette session seulement |

Ce n’est **pas** le champ ASC Nouveautés.

---

## Texte promotionnel App Store (hors bundle, **stable**)

Champ ASC **Texte promotionnel** (≤ **170** car.). Ce n’est **pas** une Nouveauté et **pas** une chaîne `lproj`.

- Source : `store/promotional-text/` (`en-US`, `fr-FR`, `de-DE`, `es-ES`, `it-IT`)
- **Ne pas** le mettre dans `whats-new/` (réécrit à chaque version) ni dans le target Xcode
- On ne le régénère **pas** à chaque `MARKETING_VERSION` — Fastlane re-pousse les fichiers existants si le champ ASC est vide

Index : `store/README.md`.

---

## Format JSON (tips et citations)

### `tips_of_day.json`

Tableau d'objets affichés en rotation sur l'écran d'accueil :

```json
[
  { "text": "Tip text here." }
]
```

Toutes les langues doivent avoir le **même nombre d'entrées** (même index = même tip).

### `gameover_quotes.json`

Citations affichées à la fin de partie. Même structure que les tips.

---

## Sections `BlomixL10n` existantes

| MARK | Contenu |
|---|---|
| Commun | Fermer, annuler, alertes quitter |
| Accueil & jeu | Boutons start, liens utilitaires (Réglages · Tutoriel · Crédits), game over, HUD |
| Game Center | Statut connexion GC |
| Skins | Noms des palettes couleur |
| Règles / crédits | Titres modals, bouton avis App Store (`credits.review_*`) |
| Paramètres | Audio, police, langue |
| PvP | Lobby, invitations, résultats, Elo |
| Partage | Bouton, a11y, messages accueil/GO, badge record (`share.*`) |
| Tutoriel | Étapes guidées |
| Classements | Leaderboard, Zen |

Parcourir `BlomixL10n.swift` avant d'ajouter une clé pour éviter les doublons.

---

## Terminologie à respecter

Utiliser les noms du [GLOSSARY.md](GLOSSARY.md) :

| Français | Anglais |
|---|---|
| Blox | Blox |
| Brix | Brix |
| Bloc Magix | Magix block |
| Ligne entrante | Incoming line |
| Mode Zen | Zen mode |
| PvP | PvP |

Noms Magix (**CHROMAX**, **BRIXED**, etc.) : **ne pas traduire** — identiques dans toutes les langues.

---

## Config projet

`Info.plist` :
```xml
<key>CFBundleLocalizations</key>
<array>
    <string>en</string>
    <string>fr</string>
    <string>de</string>
    <string>es</string>
    <string>it</string>
</array>
```

La langue affichée suit les réglages iOS de l'appareil. Pas de sélecteur in-app dédié actuellement.

---

## Checklist traduction

- [ ] Clé ajoutée dans `BlomixL10n.swift` avec commentaire traducteur
- [ ] Entrées dans `en`, `fr`, `de`, `es`, `it` (`Localizable.strings`)
- [ ] Placeholders `%@`, `%lld`, `%d` identiques dans toutes les langues
- [ ] Termes gameplay conformes au glossaire
- [ ] Test visuel sur simulateur (Réglages → Général → Langue) — au minimum FR et EN

---

## Ajouter une nouvelle langue

1. Créer `xx.lproj/` avec `Localizable.strings`, `tips_of_day.json`, `gameover_quotes.json`, `InfoPlist.strings`.
2. Ajouter la locale dans `CFBundleLocalizations` (`Info.plist`) et `knownRegions` (`project.pbxproj`).
3. Enregistrer les fichiers dans les `PBXVariantGroup` Xcode (Localizable, tips, quotes, InfoPlist).
4. Mettre à jour ce document et `PROJECT_CONTEXT.md` §15.

---

*Les règles détaillées du jeu pour les joueurs sont dans [RULES.md](RULES.md), pas dans les fichiers de localisation.*
