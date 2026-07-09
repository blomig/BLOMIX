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
| Constante, algorithme, architecture | `PROJECT_CONTEXT.md` |
| Animation, particule, son, timing | `VFX_AND_ANIMATIONS.md` |
| Fonction d'évaluation / hints | `EVAL.md` |
| Nouveau terme ou renommage | `GLOSSARY.md` |
| Nouvelle clé UI ou langue | `LOCALIZATION.md` + `BlomixL10n.swift` |
| Release App Store / version Xcode | `CHANGELOG.md` + `MARKETING_VERSION` |
| Nouveau document | `docs/README.md` + `README.md` (racine) |

### Version de référence

Chaque document technique commence par une ligne **Version de référence** alignée sur `MARKETING_VERSION` (actuellement **4.7**). La mettre à jour lors d'une release majeure.

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
- [ ] Pas de fichiers locaux commités (`.DS_Store`, `xcuserdata/`)

---

## Fichiers à ne pas committer

Voir `.gitignore` : `DerivedData/`, `xcuserdata/`, `.DS_Store`, secrets (`.env`).

---

## Contact

Dépôt : [github.com/blomig/BLOMIX](https://github.com/blomig/BLOMIX)
