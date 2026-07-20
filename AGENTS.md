# AGENTS.md — BLOMIX

Instructions pour les agents (et humains) qui travaillent sur ce dépôt.

---

## Qu’est-ce que ce projet ?

**BLOMIX** est un jeu de puzzle combinatoire **iOS en production** (App Store).

| | |
|---|---|
| Version courante | **5.2** (build 67, `MARKETING_VERSION`) |
| Plateforme | iOS 18+, portrait |
| Stack | Swift 6, UIKit + SpriteKit, Game Center, CloudKit |
| Bundle ID | `blomig.BLOMIX` |
| Langues | FR, EN, DE, ES, IT |
| Studio / propriétaire | Projet propriétaire (pas open-source) |

**Genre de jeu** : grille 8×8, gravité **inversée** (compactage vers le haut), chaînes ≥ 5 en **8-connexité**, Brix résistants, Magix, bombes, lignes entrantes tous les 10 coups. Modes : solo stagé, Zen, PvP 1v1, tutoriel.

Ce n’est **pas** un prototype : privilégier les changements ciblés, la non-régression et la cohérence avec la doc existante.

---

## Carte du dépôt

```
BLOMIX/
├── AGENTS.md                 # Ce fichier
├── README.md                 # Entrée humaine
├── DOCS/                     # Documentation de référence (lire en premier)
│   ├── README.md             # Index
│   ├── RULES.md              # Règles joueur
│   ├── PROJECT_CONTEXT.md    # Référence technique
│   ├── PVP_MATCHING.md       # Appariement / CloudKit / GameKit
│   ├── EVAL.md               # BlomixMoveAnalyzer
│   ├── VFX_AND_ANIMATIONS.md # Juice Spec
│   ├── GLOSSARY.md           # Terminologie canonique
│   ├── LOCALIZATION.md       # i18n
│   ├── DEVELOPMENT.md        # Build / debug
│   ├── CONTRIBUTING.md       # Conventions
│   └── CHANGELOG.md
├── Blomix/
│   ├── Blomix.xcodeproj
│   └── Blomix/               # Sources Swift, assets, lproj, Sounds
├── scripts/                  # Export preview / promo
├── icones_app/               # Marketing
├── Palette couleur/          # Références design
└── old_web_code/             # Archive web (ne pas faire évoluer)
```

> Le dossier de doc s’appelle **`DOCS/`** (majuscules). Les liens du README racine disent parfois `docs/` — utiliser le chemin réel.

---

## Où lire quoi (ordre recommandé)

| Besoin | Document / fichier |
|---|---|
| Comprendre le jeu | `DOCS/RULES.md` → `DOCS/GLOSSARY.md` |
| Comprendre le code | `DOCS/PROJECT_CONTEXT.md` → `DOCS/DEVELOPMENT.md` |
| PvP / défis / bugs matchmaking | `DOCS/PVP_MATCHING.md` |
| Hints / optimalité | `DOCS/EVAL.md` |
| Animations / sons | `DOCS/VFX_AND_ANIMATIONS.md` |
| Nouvelle chaîne UI | `DOCS/LOCALIZATION.md` |
| Historique versions | `DOCS/CHANGELOG.md` |

**Ne pas inventer les règles** : si le code et la doc divergent, vérifier le code puis proposer une mise à jour de la doc.

---

## Architecture (contraintes pour les agents)

### Fichier monolithe

La logique gameplay est concentrée dans :

`Blomix/Blomix/GameScene.swift` (~12k+ lignes)

- Préférer des extensions / sections `// MARK: - …` plutôt que d’éclater le fichier sans demande explicite.
- Constantes gameplay : `GridLayout`, `PriksRules`, `MagixRules` (dans `GameScene` ou modules déjà établis).
- Types grille : `BlockType`, `MagixKind` — **ne pas dupliquer**.

### Modules satellites (les utiliser, ne pas réimplémenter)

| Fichier | Rôle |
|---|---|
| `BlomixMoveAnalyzer.swift` | Eval pure Swift, hints, lookahead 3 |
| `BlomixPvPNetworking.swift` | GKMatch, RNG partagé, attaques |
| `BlomixPvPUI.swift` | Lobby, résultats, UI PvP |
| `BlomixAvailablePlayersManager.swift` | CloudKit « joueurs disponibles » |
| `BlomixEloManager.swift` | Elo PvP |
| `ScoreManager.swift` / `GameCenterManager.swift` | Classements GC |
| `BlomixL10n.swift` | Pont typé localisation |
| `BlomixAppearance.swift` | Thème chrome Sombre / Clair |
| `BlomixTypography.swift` | Polices joueur |
| `BlomixProceduralSFX.swift` | SFX Magix procéduraux |
| `BlomixMusicPlayer.swift` | Musique par stage |
| `GameViewController.swift` | Root UIKit, invitations, tutoriel |
| `LeaderboardViewController.swift` | Classements UIKit |

### Thème vs skins

- **Thème chrome** (`BlomixAppearance`) : fonds, textes, chips UI — Sombre (défaut) / Clair.
- **Skins couleur** (`color_skins.json`) : couleurs des blox uniquement.
- Les deux sont **orthogonaux** : ne pas les fusionner.

### Sauvegarde solo

- Format `BlomixSoloGameSave` version **7**, clé `blomix_solo_save_v2`.
- Avant d’écrire : respecter le flush des états transitoires (voir `PROJECT_CONTEXT` / historique v4.9).
- Ne pas casser la reprise de partie sans tests manuels explicites.

---

## Conventions de travail

### Langue

| Contexte | Langue |
|---|---|
| Discussion avec le mainteneur | **Français** (par défaut) |
| Commentaires code | Français (convention projet) |
| Identifiants Swift | Anglais (`priks`, `MagixKind.chromax`, …) |
| Commits | FR ou EN, style impératif + préfixe (`feat:`, `fix:`, `docs:`, …) — voir `DOCS/CONTRIBUTING.md` |
| Chaînes joueur | Via `BlomixL10n` uniquement — **jamais** de texte UI en dur |

### Terminologie (canonique)

Respecter `DOCS/GLOSSARY.md` :

| Joueur / doc | Code |
|---|---|
| Blox | `BlockType.color` |
| Brix | `BlockType.priks` / `priks` |
| Magix | `BlockType.magix` / `MagixKind` |
| SAINTX | `.cleanx` |
| CROSSX | `.crosx` (orthographe code : `crosx`) |
| Solo stagé | mode défaut (pas « classique ») |

### Localisation

Toute chaîne visible par le joueur :

1. Propriété dans `BlomixL10n.swift`
2. Clé dans **toutes** les langues supportées : `en`, `fr`, et si impact large aussi `de` / `es` / `it`
3. Au minimum **FR + EN** pour tout ajout

### Swift 6

- Concurrency stricte.
- Callbacks GameKit : conserver les patterns `@preconcurrency` / `nonisolated` existants.
- Ne pas « moderniser » le threading réseau sans raison et sans test PvP.

### Scope des changements

- Modifier uniquement ce qui est demandé.
- Pas de refactor massif de `GameScene` sauf demande explicite.
- Pas de suite de tests unitaires en place : valider par raisonnement + checklist manuelle (`DOCS/DEVELOPMENT.md`).
- Ne pas committer sans demande : `xcuserdata/`, `.DS_Store`, secrets, DerivedData.

---

## Documentation à synchroniser

Si le comportement change, mettre à jour **en même temps** :

| Changement | Fichiers |
|---|---|
| Règle joueur | `DOCS/RULES.md` |
| Algo / archi / constantes | `DOCS/PROJECT_CONTEXT.md` |
| Son / VFX / timing | `DOCS/VFX_AND_ANIMATIONS.md` |
| Eval / hints | `DOCS/EVAL.md` |
| Terme nouveau | `DOCS/GLOSSARY.md` |
| i18n | `DOCS/LOCALIZATION.md` + lproj |
| Release | `DOCS/CHANGELOG.md` + version Xcode |
| Nouveau doc | `DOCS/README.md` (+ README racine si besoin) |

Ligne **Version de référence** des docs = `MARKETING_VERSION` courante.

---

## Boucle de clôture (à ne pas oublier)

À certains moments, le travail **n’est pas fini** tant que ces trois volets n’ont pas été traités (ou explicitement reportés par l’humain). L’agent doit **les proposer proactivement**, pas attendre qu’on les redemande.

### 1. Fichiers de langues (l10n)

**Quand** : toute UI / message / label / alerte / tip touché ou ajouté ; toute feature visible par le joueur.

**Quoi** :
- `BlomixL10n.swift` + clés dans les `.lproj` concernés
- Minimum **FR + EN** ; idéalement aussi **DE / ES / IT** si la chaîne est exposée en prod
- Pas de chaînes en dur dans le code UI

Voir `DOCS/LOCALIZATION.md`.

### 2. Documentation (`DOCS/`)

**Quand** : règle, constante, mode, VFX/son, PvP, eval, terminologie, ou version qui change.

**Quoi** : synchroniser les fichiers du tableau ci-dessus **dans le même lot de travail** que le code (pas « on documentera plus tard »).  
Release / jalon : mettre aussi à jour `DOCS/CHANGELOG.md` (et la version de référence des docs si besoin).

### 3. Commit et push GitHub

**Quand** (moments naturels) :
- Fin d’une feature ou d’un fix cohérent (état buildable, l10n + doc à jour si concernés)
- Fin d’un lot demandé par l’humain (« fais X »)
- Avant de passer à un autre sujet non trivial (éviter un working tree fourre-tout)
- Jalon / release (avec message et éventuelle note CHANGELOG)

**Comment** :
- L’agent **rappelle** ces trois points en fin de tâche quand c’est pertinent
- **Commit + push** : les faire dès que l’humain le demande, ou **proposer** clairement (« je peux committer et pusher ») si le lot est prêt
- Un seul commit logique par intention quand c’est possible ; messages selon `DOCS/CONTRIBUTING.md` (`feat:`, `fix:`, `docs:`, …)
- Ne jamais forcer le push (`--force`) sur `main` sans demande explicite
- Remote attendu : dépôt GitHub du projet (`origin` / `github.com/blomig/BLOMIX`)

**Ordre conseillé en fin de lot** :

```
code OK → (1) langues → (2) doc → checklist manuelle si besoin → (3) commit → push
```

Ces trois points sont la **hygiène de livrable** du projet : un diff code seul, sans l10n/doc/remote à jour, est souvent un travail incomplet.

---

## Build & capacités (rappel)

```bash
open Blomix/Blomix.xcodeproj
```

| Paramètre | Valeur |
|---|---|
| Xcode | 16+ |
| `SWIFT_VERSION` | 6.0 |
| `IPHONEOS_DEPLOYMENT_TARGET` | 18.0 |
| Scheme | Blomix |

Capabilities : Game Center, CloudKit (`iCloud.blomig.BLOMIX`), push (souvent `development` en local — attention avant release).

**PvP** : 2 comptes Game Center distincts ; lire `DOCS/PVP_MATCHING.md` avant de toucher à l’appariement (permissions CloudKit `chfrom_*`, handshake, revanche).

---

## Zones sensibles (prudence)

1. **`GameScene.swift`** — cœur gameplay ; régressions faciles (chaînes, save, Magix, HUD).
2. **PvP** — CloudKit Public DB (écriture seulement sur records créés par soi), RNG partagé, déconnexion / revanche.
3. **Sauvegarde solo** — versioning du save, flush avant write.
4. **Eval** — `BlomixMoveAnalyzer` ignore les Magix ; ne pas simuler des effets non modélisés sans le documenter.
5. **Audio** — mix global + procédural ; volumes via réglages existants.
6. **`old_web_code/`** — archive ; ne pas y baser de nouvelles features.

---

## Checklist avant de considérer un travail « terminé »

- [ ] Build Xcode raisonnable (pas d’erreur introduite sur les fichiers touchés)
- [ ] Flux impacté pensé (solo / Zen / PvP / tutoriel selon le cas)
- [ ] **(1) Langues** : clés `BlomixL10n` + `.lproj` à jour (FR+EN min.) si UI touchée
- [ ] **(2) Doc** : `DOCS/` alignée si le comportement / les règles changent
- [ ] Terminologie GLOSSARY respectée
- [ ] Pas de fichiers locaux / secrets dans le diff
- [ ] **(3) Git** : proposer (ou faire sur demande) commit + push vers GitHub quand le lot est prêt

---

## Ce que l’agent peut faire librement vs demander

| OK sans confirmation | Demander d’abord |
|---|---|
| Lire le code et la doc | **Push** vers GitHub (sauf si l’humain a déjà dit de pusher) |
| Éditer sources + **docs liées** + **l10n** dans le même lot | Tag release / changer version marketing / build |
| Proposer **commit + push** en fin de lot | Refactor large de `GameScene` |
| Petits fix ciblés | Modifier entitlements / CloudKit schema prod |
| Proposer design / plan | Actions destructives (reset hard, force-push) |
| **Commit** si l’humain a demandé d’enregistrer / committer / finaliser le lot | Commit « surprise » sur un arbre non validé |

En pratique : langues et doc font partie du lot de code ; le **rappel** commit/push est systématique en clôture ; l’**exécution** du push reste confirmée sauf consigne déjà donnée (« commit et push », « envoie sur GitHub », etc.).

---

## Messages utiles pour l’humain

- Préférer des réponses en **français**, structurées, avec chemins de fichiers concrets.
- Pour une feature non triviale : plan court → implémentation → points de test manuel.
- En fin de lot pertinent : rappeler explicitement **langues / doc / commit+push** s’ils n’ont pas encore été faits.
- En cas d’ambiguïté de design (équilibre, UX, copy) : **poser la question** plutôt que d’imposer un choix arbitraire.

---

*Maintenir ce fichier à jour lors des changements d’architecture majeurs ou de conventions de contribution.*
