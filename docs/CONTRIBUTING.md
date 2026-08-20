# Blomix — Guide de contribution

> Conventions pour maintenir le code et la documentation cohérents.

---

## Avant de commencer

1. Lire [DEVELOPMENT.md](DEVELOPMENT.md) pour l'environnement de build.
2. Consulter [GLOSSARY.md](GLOSSARY.md) pour la terminologie officielle.
3. Vérifier si votre changement impacte [RULES.md](RULES.md) ou [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md).

---

## Branches et commits

- Branche principale : `main`
- Messages de commit en **français** ou **anglais**, style impératif :
  - `feat: …` — nouvelle fonctionnalité
  - `fix: …` — correction de bug
  - `docs: …` — documentation uniquement
  - `chore: …` — maintenance (gitignore, config)
  - `refactor: …` — restructuration sans changement fonctionnel

Exemples :
```
feat: ajouter variante Magix TWISTX au tutoriel
fix: corriger compteur Brix en cascade SCRUMBLX
docs: mettre à jour les probabilités de spawn dans RULES.md
```

---

## Conventions de code

| Sujet | Convention |
|---|---|
| Langue du code | Swift, commentaires en français |
| Fichier principal | `GameScene.swift` — préférer les extensions `// MARK: -` |
| Constantes gameplay | Regrouper dans `GridLayout`, `PriksRules`, `MagixRules` |
| UI texte | Toujours via `BlomixL10n` (jamais de chaîne en dur) |
| Sons | Enum `BlomixMatchSFX` ou `BlomixProceduralSFX` |
| Types grille | `BlockType`, `MagixKind` — ne pas dupliquer |

### Swift 6

Le projet cible Swift 6 avec concurrency stricte. Les délégués GameKit utilisent `@preconcurrency` et `nonisolated` — conserver ce pattern pour les callbacks réseau.

---

## Documentation à maintenir

| Changement | Fichier(s) à mettre à jour |
|---|---|
| Règle gameplay visible par le joueur | `RULES.md` |
| Magix (effet en jeu ou piste) | `MAGIX.md` (+ `RULES.md` / `PROJECT_CONTEXT.md` si en jeu) |
| Constante, algorithme, architecture | `PROJECT_CONTEXT.md` |
| Animation, particule, son, timing | `VFX_AND_ANIMATIONS.md` |
| Fonction d'évaluation / récap | `EVAL.md` |
| Nouveau terme ou renommage | `GLOSSARY.md` |
| Nouvelle clé UI ou langue | `LOCALIZATION.md` + `BlomixL10n.swift` |
| Release App Store / version Xcode | `CHANGELOG.md` + `MARKETING_VERSION` + **`store/whats-new/` (5 langues)** |
| Nouveau document | `docs/README.md` + `README.md` (racine) |

### Version de référence

Chaque document technique commence par une ligne **Version de référence** alignée sur `MARKETING_VERSION` (actuellement **6.4**). La mettre à jour lors d'une release majeure.

### Nouveautés App Store (systématique à la release)

À chaque **nouvelle version marketing**, le lot n’est pas fini sans les 5 fichiers `store/whats-new/` :

1. Rédiger les puces **joueur** (FR), puis **EN, DE, ES, IT** — même ordre, même nombre.
2. Ne pas coller le `CHANGELOG.md` (trop technique). Noms Magix **non traduits**.
3. L’humain copie-colle dans App Store Connect (le champ Nouveautés est vide). Rien n’est lu depuis l’IPA.

**Texte promotionnel** (`store/promotional-text/`) : **stable**, ≤ 170 car. Coller si ASC l’a vidé. **Ne pas** le réécrire avec le CHANGELOG.

Procédure : [LOCALIZATION.md](LOCALIZATION.md) + `store/README.md`.  
Si un lot ultérieur change encore le bénéfice joueur de **cette** version : mettre à jour les **5** fichiers `whats-new` tout de suite.

---

## Localisation

Toute chaîne visible par le joueur doit exister en **français et anglais** :

1. `BlomixL10n.swift` — propriété statique
2. `en.lproj/Localizable.strings`
3. `fr.lproj/Localizable.strings`

Détail : [LOCALIZATION.md](LOCALIZATION.md).

---

## Assets

| Type | Emplacement |
|---|---|
| Sprites jeu | `Assets.xcassets/WebImages/` |
| Sons | `Blomix/Blomix/Sounds/` |
| Polices | Bundle principal + `UIAppFonts` dans `Info.plist` |
| Skins couleur | `color_skins.json` |

Nommer les imagesets de façon explicite (`red_new`, `magix`, `bomb_new`…). Documenter tout nouvel effet dans la Juice Spec.

---

## Pull requests (checklist)

- [ ] Build Xcode sans erreur
- [ ] Test manuel du flux concerné (solo / Zen / PvP selon le cas)
- [ ] Documentation mise à jour si le comportement change
- [ ] `CHANGELOG.md` mis à jour si release
- [ ] `store/whats-new/` FR+EN+DE+ES+IT si nouvelle version marketing
- [ ] Pas de fichiers locaux commités (`.DS_Store`, `xcuserdata/`)

---

## Fichiers à ne pas committer

Voir `.gitignore` : `DerivedData/`, `xcuserdata/`, `.DS_Store`, secrets (`.env`).

---

## Contact

Dépôt : [github.com/blomig/BLOMIX](https://github.com/blomig/BLOMIX)
