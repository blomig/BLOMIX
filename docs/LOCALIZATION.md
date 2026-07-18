# Blomix — Guide de localisation

> **Langues supportées** : Français (`fr`), Anglais (`en`), Allemand (`de`), Espagnol (`es`), Italien (`it`)  
> **Version de référence** : 5.1

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
- `rules.txt` — anciennes règles statiques
- `credits.txt` — crédits

L'UI moderne utilise `RULES.md` / écrans in-game via `BlomixL10n`, pas `rules.txt`.

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
| Accueil & jeu | Boutons start, menu, game over, HUD |
| Game Center | Statut connexion GC |
| Skins | Noms des palettes couleur |
| Règles / crédits | Fallback si fichiers txt absents |
| Paramètres | Audio, police, langue |
| PvP | Lobby, invitations, résultats, Elo |
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
