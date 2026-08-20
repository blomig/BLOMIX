# BLOMIX 6.4 — Spec (build 118)

> **Statut** : livré (build 119)  
> **Cible** : marketing **6.4**, build **119**  
> **Date** : août 2026  
> **Règles de jeu** : inchangées vs [RULES.md](RULES.md) 6.3, sauf **affichage** (HUD, accueil, guide). Le gel du timer Duel en visée bombe **reste** ; on le rend visible.

Cette spec fige les 15 points tranchés après la revue 6.3. Elle sert de cahier d’implémentation : ne pas élargir le périmètre sans mettre à jour ce fichier.

---

## 1. Objectif

Rendre lisible ce que le binaire fait déjà, et fermer les frictions d’accueil / Duel / défis — **sans** changer le resolveur, le scoring, ni le protocole filaire.

**Bénéfice joueur visé :** comprendre Magix et le mètre Duel, ne plus écraser une save par accident, réussir un défi Récents/Elo, viser bombe / auto-drop / Brix plus clairement.

---

## 2. Hors scope

- VoiceOver / Dynamic Type sur le shell SpriteKit
- File Elo (skill) sur Partie rapide
- Départage H2H si déco mutuelle
- Tests unitaires, ménage polices / assets
- Éclatement de `GameScene.swift`
- Push APNs pour les défis
- Changer la règle « viser une bombe gèle le 10 s » (on affiche seulement)
- Réactiver hints / `!!` en jeu
- Save v8

---

## 3. Dépendances internes

| D’abord | Puis |
|---|---|
| **§1 Guide** | §7 (livre = guide), §8 (☰ Tutoriel) |
| **§5 + §6** | Même hero : une table de priorité, un seul gros bouton |
| §2, §3, §9, §10, §12, §13, §14, §15 | Autonomes |
| **§4** | Isolé PvP (Récents + classement Elo) |

**l10n :** toute chaîne nouvelle via `BlomixL10n` + `en` / `fr` au minimum ; **de / es / it** pour tout ce qui est à l’accueil, HUD, GO, ☰, bannière, guide. Noms Magix **non traduits**.

---

## 4. Hero accueil — une vérité

Après le splash (et après ☰ Accueil), **toujours** `presentStartScreen` — plus de saut auto dans une save (`presentStartScreenOrRestoreSoloSave` ne restaure plus en silence).

Le chip hero (pleine largeur) :

| Priorité | Condition | Titre | Sous-ligne (9 pt, Nunito) | Action |
|---|---|---|---|---|
| 1 | Save solo/Zen présente | **Continuer** | **Arcade** ou **Zen** (`isZenMode` de la save) | `restoreFromSoloSave` |
| 2 | Pas de save **et** tuto jamais terminé/passé | **Découvrir** | — | Tuto interactif (inchangé) |
| 3 | Sinon | **Arcade** | — | Nouvelle partie Arcade (inchangé) |

Duel et Zen (paire sous le hero) : **inchangés**.

Lien **Nouvelle partie** : visible **seulement** s’il y a une save. Sous le hero, petit, chrome secondaire.

1. Tap → dialog in-app (même famille que « Quitter la partie ? »).
2. Annuler → rien.
3. Confirmer → `BlomixSoloSaveManager.clear()`, **rester à l’accueil**, recalculer le hero (Arcade ou Découvrir). **Ne pas** lancer une partie.

`hasSeenInteractiveTutorial` est posé dès le **démarrage** du tuto (comportement actuel). Un joueur qui a tapé Zen le premier jour peut donc avoir une save **et** un tuto non fait : le hero est **Continuer** (priorité 1). Le guide (§1) reste sur l’icône livre.

Fin de tuto / retour Duel avec `restoreSave: true` : afficher l’accueil (éventuellement Continuer), **pas** restaurer en pleine grille.

Game Over → Accueil : pas de save (déjà `clear`) → hero Arcade.

---

## 5. Les 15 points

### 5.1 Guide Magix / règles (rejouable)

**Quoi :** modal UIKit plein écran, chrome Sombre/Clair, blox ambiants, **Fermer** en haut à droite — même famille que `BlomixCreditsViewController`. **Pas** l’overlay paginé `GameTutorialOverlayView`.

**Contenu** (sections `BlomixL10n`, termes [GLOSSARY.md](GLOSSARY.md) / [RULES.md](RULES.md)) :

1. Blox, chaînes ≥ 5, 8-connexité, gravité vers le haut  
2. Brix (−1 / vague, +20)  
3. Ligne des 10 ; **une bombe n’est pas un coup**  
4. Bombes : stock 5 / 3 ; table nuke Arcade ; Zen/Duel/tuto = 3×3  
5. Huit Magix : symbole + effet **réel** (BRIXED = wipe, BOMBX = +1, TWISTX auto, SAINTX +200 ×stage)  
6. Bonus +500 grille vide ; scoring cascade  
7. Duel : chiffre + barre = mètre **attaque** 0…50  

Bas de modal : chip secondaire **Rejouer le tuto** → `startTutorialGameWithIntro` (save solo conservée comme aujourd’hui).

**Entrées :**

- Accueil, icône livre → ce guide (plus une partie tuto)  
- ☰ **Tutoriel** → ce guide (timer déjà en pause chrome)

**Fichiers probables :** nouveau VC (ou extension crédits) ; `GameScene` (livre + ☰) ; `BlomixL10n` + 5 `.lproj`.

---

### 5.2 Score Duel — caption « attaque »

Caption Nunito, même gabarit que **LIGNE** / **TEMPS**, collée au gros chiffre HUD. Libellé joueur : **attaque** (clé type `hud.attack_caption`).

Le chiffre reste `score % 50`. La barre 0…50 à droite est le **même** mètre. Pas de total affiché.

Même idée à côté du remplissage / score adverse (caption ou accessoire, pas un 2ᵉ gros chiffre).

Arcade / Zen : caption absente.

---

### 5.3 Gel bombe Duel — visible

Règle inchangée : `isBombMode` → `blomixPvP_shouldRunTurnTimer` faux, auto-drop ignoré.

**UI :** dès visée, le 10 s passe en état « pause / visée » (couleur distincte du rouge urgence + picto ou libellé court). Annuler ou poser → style timer normal.

Pas de message filaire. L’adversaire a son propre chrono.

---

### 5.4 Défis Récents / classement Elo

Après `findMatch` / `match(for:)` sur les chemins **B** (`BlomixPvPRecentPlayersViewController`) et **C** (`LeaderboardViewController`) : **même** attente que le mode A / `ChallengeMatchDelegate` —

- `expectedPlayerCount == 0` **et** `players` non vide  
- y compris si le peer est déjà `.connected` (poll ~0,4 s, plafond ~16 s)  
- même `GKMatch` rejoué = no-op (PVP-25)

Timeout / erreurs : overlays in-app existants. Pas de `disconnect` pour « relancer ».

---

### 5.5 Premier lancement — Découvrir

Couvert par la table §4, priorité 2. Duel / Zen tapables sans tuto.

---

### 5.6 Continuer / Nouvelle partie

Couvert par §4. Save = une seule (`blomix_solo_save_v2`) ; pas deux Continuer.

Dialog Nouvelle partie : `BlomixInAppDialog` ou overlay SK déjà utilisé pour quitter — même ton, clés dédiées (`home.new_game_confirm_*`).

---

### 5.7 Captions icônes accueil

Sous les 5 icônes, **un mot**, Nunito **8 pt**, `tertiaryText`, une ligne, largeur max = pas d’icône (~52 pt). Si une locale déborde : raccourcir la **chaîne**, ne pas monter la taille.

| Icône | Légende (FR de référence) | Action 6.4 |
|---|---|---|
| `gearshape.fill` | Réglages | Settings (inchangé) |
| `book.fill` | Tutoriel | **Guide §5.1** |
| soleil / lune | Thème | Toggle (inchangé) |
| `paperplane.fill` | Partager | Share (inchangé) |
| `info.circle.fill` | Crédits | Crédits cartes (inchangé) |

Ne pas réactiver `makeStartScreenUtilityLinks` en bandeau texte.

---

### 5.8 Menu ☰

| Ligne | Action |
|---|---|
| Accueil | Inchangé (confirm solo / forfait Duel) |
| Scores | `showLeaderboard(initialTab:)` selon le mode : Arcade → Arc. · Zen → Zen · Duel → Elo |
| Tutoriel | **Nouveau** — guide §5.1 ; timer déjà pausé |
| Réglages | Inchangé |

Pas de Crédits dans le ☰. Pas de relance du tuto **partie** depuis le ☰.

---

### 5.9 Best score — légende au-dessus

Arcade / Zen uniquement. Clé existante `hud.best_score_title` (vérifier les 5 langues) **au-dessus** du 14 pt. Pas en Duel.

---

### 5.10 Justesse GO

Une ligne Nunito sous le % : hors Magix et bombes. Formule analyzer **inchangée**. Pas de `!!` / `?` en jeu.

---

### 5.11 Bannière défi

Pas de push système.

Côté **défié** : `hapticHeavy` + son catalogue existant + léger pulse + `bringSubviewToFront`. Texte 2 lignes : *qui* défie + « l’app doit rester ouverte · 60 s ».

Côté **invitant** : hint actuel conservé.

Si `BlomixPublicCloudGate` bloque le poll : statut visible dans le **lobby** (pas un silence).

---

### 5.12 Auto-drop Arcade — ghost

Quand `stageTimerSecondsRemaining` passe à **≤ 2** : calculer **une fois** `autoDropPreferredColumn()`, figer l’index, afficher le **ghost** existant sur cette colonne. Timeout → `dropBlock` de **cette** colonne (pas un nouveau `randomElement()`).

Si la colonne figée devient injouable (cascade / ligne) avant t = 0 : recalculer une fois et mettre à jour le ghost.

Pas d’analyzer. Zen / Duel : N/A (Duel a déjà son auto-drop réseau).

---

### 5.13 Décrément Brix

Si compteur **reste > 0** : flash blanc + pop du chiffre ~**0,12 s** (plus léger que BRIXED). Disparition à 0 : inchangée. **Pas** de SFX supplémentaire (éviter la saturation). Max 1 flash / Brix / vague (déjà −1 max).

Documenter dans [VFX_AND_ANIMATIONS.md](VFX_AND_ANIMATIONS.md) à l’implémentation.

---

### 5.14 Cible bombe HUD (hit test)

**Ce n’est pas** la zone d’explosion sur la grille.

C’est le bouton **bas droite** (icône 36 pt + chiffre) qui **arme** le mode bombe.

**6.4 :** visuel **identique**. `touchHitsBombHUD` : après l’union icône + label, infalter le rect à **min. 44×44 pt** (centré). Ne pas recouvrir la grille. Même principe que le ☰ déjà ≥ 44.

---

### 5.15 Reprise timer Arcade

`restoreFromSoloSave` : `resumeStageTimerKeepingRemaining()` avec `stageTimerSecondsRemaining` persisté, clamp **`[1 … durée du stage courant]`**.

Si l’app reste en mémoire après un flush mid-anim (`removeAllActions`) : relancer sur le **reste**, pas `restartStageTimer()`.

Pas de bump save (champ déjà en v7).

---

## 6. Fichiers probablement touchés (implémentation)

| Zone | Fichiers |
|---|---|
| Accueil / hero / icônes / ☰ | `GameScene.swift` |
| HUD Duel, best, timer, bombe hit, ghost, Brix | `GameScene.swift` |
| Guide | nouveau VC + `BlomixL10n` + `.lproj` |
| Défis B/C | `BlomixPvPUI.swift`, `LeaderboardViewController.swift` (réutiliser le poll A) |
| Bannière / lobby 503 | `BlomixPvPUI.swift`, `GameViewController.swift` |
| Doc à la livraison | RULES (si une phrase joueur change), PROJECT_CONTEXT, VFX (§5.13), CHANGELOG, ce fichier → **fait** |

`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` : **6.4** / **118** au moment du build, pas avant.

---

## 7. Checklist manuelle (quand on code)

- [ ] Premier install : splash → Découvrir ; Duel/Zen OK ; après tuto → Arcade  
- [ ] Save Arcade : cold launch → Continuer + « Arcade » ; lien Nouvelle partie → confirm → reste accueil, hero Arcade  
- [ ] Save Zen + tuto jamais fait : Continuer + « Zen » (pas Découvrir en hero)  
- [ ] ☰ Accueil mid-partie : Continuer, pas un Arcade qui wipe  
- [ ] Livre et ☰ Tutoriel → guide ; Rejouer le tuto conserve la save  
- [ ] Duel : caption « attaque » ; visée bombe = timer visiblement en pause ; hit bombe 44 pt  
- [ ] Arcade L2+ : à 2 s le ghost est figé ; le drop = cette colonne  
- [ ] Brix −1 : flash, pas de son extra ; Brix à 0 : anim actuelle  
- [ ] Reprise save : timer = reste (pas 32 s si on était à 4 s)  
- [ ] GO : légende sous le % ; best score légendé au-dessus (hors Duel)  
- [ ] Défi depuis Récents et depuis Elo : match si peer déjà connected  
- [ ] FR + EN (idéalement DE/ES/IT) : Découvrir, Continuer, Nouvelle partie, attaque, guide  

---

## 8. Décisions figées (ne pas rouvrir sans raison)

- Guide = modal lecture, pas l’ancien overlay 3 pages  
- Caption Duel = **attaque**  
- Gel bombe = **gardé** + visible  
- Hero 1er lancement = **Découvrir**  
- Continuer = titre + **mode tout petit**  
- Nouvelle partie = lien → confirm → **reste accueil**  
- Save bat Découvrir sur le hero  
- Captions icônes = **8 pt**, un mot  
- Best score = **au-dessus**  
- Hit bombe = pad invisible, pas une icône plus grosse  

---

*Implémenter uniquement ce qui est ici. Après merge 6.4 : passer ce fichier en « livré », aligner RULES / PROJECT_CONTEXT / VFX / CHANGELOG, version de référence 6.4.*
