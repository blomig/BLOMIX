# Blomix — Spécification VFX, animations et sons

> **Version de référence** : 4.7  
> **Sources principales** : `GameScene.swift`, `BlomixProceduralSFX.swift`, `BlomixSKButtonNode.swift`, `BlomixAmbientBlocksView.swift`  
> **Dernière mise à jour** : juillet 2026

---

## Méthodologie (bonne pratique)

Ce document suit le format **Juice Spec** / **VFX Bible**, utilisé en game dev pour documenter le « game feel » :

| Colonne | Rôle |
|---|---|
| **Déclencheur** | Événement gameplay qui lance l'effet |
| **Visuel** | Animation, particules, shader, overlay |
| **Audio** | Fichier `.wav`/`.mp3` ou son procédural |
| **Timing** | Durées, staggers, easings |
| **Paramètres clés** | Constantes nommées dans le code |
| **Réf. code** | Enum / fonction source |

**Organisation** : par **catégorie d'objet / d'événement**, pas par fichier source — plus lisible pour designers, sound designers et développeurs.

**Convention de timing** : toutes les durées sont en secondes sauf mention contraire. Les easings SpriteKit sont indiqués quand ils sont explicites (`easeOut`, `easeIn`, etc.).

---

## Inventaire des sons

### Sons fichiers (`BlomixMatchSFX` → `Sounds/`)

| ID enum | Fichier | Usage principal |
|---|---|---|
| `begin` | `begin.wav` | Début de partie |
| `place` | `place.wav` | Atterrissage blox isolé (groupe < 2) |
| `connectE` | `connect_E.wav` | Atterrissage → groupe de 2 |
| `connectF` | `connect_F.wav` | Atterrissage → groupe de 3 |
| `connectGb` | `connect_Gb.wav` | Atterrissage → groupe de 4 |
| `chainNew` | `chain_new.wav` | Chaîne niveau 0, taille 5 |
| `chainNewCascade1` | `chain_new-1.wav` | Chaîne 6–8 OU cascade niveau 1 |
| `chainNewCascade2` | `chain_new-2.wav` | Chaîne ≥ 9 OU cascade niveau ≥ 2 |
| `line` | `line.mp3` | Injection ligne entrante |
| `end` | `end.wav` | Game Over |
| `victory` | `victory.mp3` | Victoire PvP |
| `wrong` | `wrong.wav` | Colonne pleine (autres libres) |
| `emptyColumnClear` | `empty_coll.wav` | Colonne entièrement vidée |
| `pendingRandomLineBloopa` | `5251__noisecollector__bloopa01.aiff` | Apparition preview ligne (coup 9) |
| `priksVanish` | `prix.wav` | Brix disparaît (compteur → 0) |
| `transition` | `transition.wav` | Overlay de transition (stage, tuto) |
| `magix` | `magix.wav` | Atterrissage bloc Magix |
| `bombLoad` | `gun_load.wav` | Activation mode bombe |
| `bomb` | `bomb.wav` | Explosion bombe |
| `cleanx` | `cleanx.wav` | Animation SAINTX (cleanx) |
| `scrumblx` | `scrumblx.wav` | Déclenchement SCRUMBLX |

### Sons procéduraux (`BlomixProceduralSFX`)

Synthèse PCM en mémoire (44,1 kHz, pool de 14 `AVAudioPlayerNode`). Volume modulé par `BlomixMatchAudioSettings.shared.masterVolume`.

| Fonction | Déclencheur | Durée | Pitch / timbre | Gain |
|---|---|---|---|---|
| `playChromaxTick(step, total)` | CHROMAX : chaque case transformée | 0,055 s | C5→C6 selon `step/total` | 0,55 |
| `playCrosxPulse(ring)` | CROSSX : chaque anneau Manhattan | 0,075 s | 700 Hz / 1,07^ring | 0,50 |
| `playTwistxFlip(index)` | TWISTX : chaque case swappée | 0,038 s | 880 Hz (pair) / 660 Hz (impair) | 0,45 |
| `playColorxRouletteClick(step)` | COLORX : étape roulette (0–4) | 0,055 s | 880→728 Hz (−38/step) | 0,60 |
| `playColorxDissolvePop()` | COLORX : dissolution par bloc | 0,030 s | 340–480 Hz aléatoire | 0,40 |
| `playBrixedImpact()` | BRIXED : flash initial | 0,210 s | Sweep 115→42 Hz + bruit | 0,70 |

Staggers audio Magix alignés sur les animations visuelles :
- CHROMAX : **0,08 s**/case
- CROSSX : **0,06 s**/anneau
- TWISTX : **0,04 s**/case
- COLORX roulette : durées visuelles `[0,10, 0,15, 0,22, 0,30, 0,50]` s

### Musique (`BlomixMusicPlayer`)

Fichiers `Puzzle Game 2*.mp3` — un par stage solo (voir § Transitions).

---

## Calques z-order (repère scène)

| z | Élément |
|---|---|
| −10 | Fond noir |
| 0–5 | Grille, strip preview ligne, titre |
| 12 | HUD score, timer, compteurs |
| 17 | Hint ghost |
| 18 | Ghost preview (appui long) |
| 20 | Bloc en chute |
| 22 | Bombe en placement |
| 24 | Dissolution chaîne (sprites) |
| 34–38 | Particules score, bombe, milestones |
| 45–47 | Flash bombe, popup Magix |
| 46 | Ondes de choc bombe |
| 160 | Game Over focus rings |
| 200 | Overlay Game Over |
| 300 | Overlay transition stage/tuto |

---

## 1. Placement de bloc (Blox, Brix, Magix)

### 1.1 Chute et atterrissage (`dropBlock`)

| | |
|---|---|
| **Déclencheur** | Tap colonne valide, bloc normal |
| **Réf. code** | `dropBlock`, `LandingBounce`, `FlightStretch` |

**Vol :**
- Départ : position preview → snap instantané bas de colonne (`duration: 0`)
- Vitesse : `cellPoints × 8 / 0,25` ≈ **1280 pts/s**
- Durée montée : `max(0,07, distance / vitesse)` — `easeOut`
- Stretch en vol : `xScale 0,82`, `yScale 1,25` → retour `(1,1)` en `easeIn`

**Traînée de particules** (`makeTrailSpawnAction`) :
- Intervalle spawn : **0,04 s** (~25/s)
- 3 traînées (centre + ±9 pt) + 4 micro-dots aléatoires
- Rayon dots : 1,8–3,0 pt (centre), 1,0–2,0 pt (latérales)
- Fade-out : **0,38 s**

**Atterrissage** (`playLandingBounce`) — total **0,15 s** :

| Phase | Durée | Mouvement | Scale |
|---|---|---|---|
| A — squash | 0,09 s | y + h×0,055 | x 1,32, y 0,78 |
| B — rebond | 0,03 s | y − h×0,13 | x 0,94, y 1,15 |
| C — settle | 0,03 s | retour p0 | x/y 1,0 |

**Particules impact** (`spawnLandingImpactSparkles`) :
- Couche éjection : 12 dots, **0,22 s**, rayon 0,8–1,8 pt, drift 12–26 pt
- Couche poudre : 38 dots, **0,80 s**, rayon 0,5–1,2 pt, drift 1–5 pt

**Sons d'atterrissage** (`landingSoundForPlacedBlock`) :

| Groupe formé | Son |
|---|---|
| 1 (isolé) | `place` |
| 2 connexes | `connectE` |
| 3 connexes | `connectF` |
| 4 connexes | `connectGb` |
| ≥ 5 (chaîne) | *(aucun — le son chaîne prend le relais)* |
| Magix | `magix` |
| Brix | `place` |

**Délai post-bounce** : `LandingBounce.totalDuration` (0,15 s) avant `resolveChains()` ou effet Magix.

### 1.2 Preview bloc courant

| Effet | Paramètres |
|---|---|
| Respiration (`previewBreathKey`) | scale 1,0↔1,2, **0,5 s**/phase, `easeInEaseOut`, infini |
| Jitter imminent ligne (`startPreviewJitter`) | cycle **1,1 s**, amplitude X **±1,0**, Y **±0,5** pt, sin/cos ×1,7 fréquence |
| Stop | snap scale 1,0 en **0,06 s** |

### 1.3 Ghost preview (appui long ≥ 120 ms)

| | |
|---|---|
| **Déclencheur** | `ghostHoldDelay = 0,12 s` maintenu |
| **Visuel** | Colonne : cases vides `#444` α 0,9 ; bloc fantôme α **0,55** |
| **z** | container **18** |
| **Audio** | — |
| **Réf.** | `showGhostPreview`, `ghostHoldTimer` |

### 1.4 Colonne invalide

| Son | `wrong` |
| Haptique | — |

---

## 2. Rendu des blocs

### 2.1 Blox couleur

- Sprite plein 36×36 pt (`cellPoints − 4`)
- **Jonctions** : barres arrondies entre voisins même couleur (`junction_*`, z ≈ 2)
- Couleurs : skin actif (`BlomixSkinCatalog`)

### 2.2 Brix (Priks)

- Fond couleur `priks` du skin
- Chiffre centré, police joueur ; taille ×0,72 si valeur ≥ 10
- Pas d'animation idle

### 2.3 Blocs Magix (rendu continu)

| Élément | Paramètres |
|---|---|
| Shader | Dégradé 6 couleurs animé via `u_time` (GLSL) |
| Halo (`magixGlow`) | Spread **16 pt**, α pulse 0,28↔0,55, cycle **1,2 s** |
| Particules orbitales | Spawn toutes **0,175 ± 0,09 s** ; dot r 1,0–1,8 pt ; fade in 0,28 s, hold 0,35 s, out 0,62 s ; drift 6–12 pt en **1,25 s** |
| Symbole | Police ×0,69 hauteur bloc, noir, z 5 |
| En chute | Même rendu via `makeMagixShaderSprite` |

### 2.4 Bombe (sprite HUD + chute)

- Shader noir → rouge → jaune (cycle 3 couleurs)
- Chiffre « nuke » si stage ≥ 2
- Activation : `bombLoad` ; tremblement pré-explosion **0,3 s** (±6 pt, 6 oscillations × 0,05 s)

---

## 3. Chaînes et cascades

### 3.1 Dissolution (`animateWinningChainDisappearance`)

| | |
|---|---|
| **Déclencheur** | Groupe ≥ 5 détecté |
| **Haptique** | `hapticLight()` |
| **Son** | `playChainClearSound` (voir tableau ci-dessous) |
| **Stagger** | **0,04 s**/case, ordre ligne→colonne |
| **Réf.** | `ChainClearFeedback` |

**Par case (durée totale ≈ 0,50 s) :**

| Étape | Durée | Détail |
|---|---|---|
| Scale up | 0,20 s | ×1,30, `easeOut` |
| Pop dots | instant | `spawnChainPopDots` |
| Scale down + brighten | 0,16 s | lerp blanc 30 %, `easeInEaseOut` |
| Fade | 0,14 s | α → 0 |

**Placeholder gris** (`cell_dissolve_bg_*`) sous le sprite pendant le fondu.

**Particules dissolution** (`spawnChainPopDots`) :
- 7–10 dots r 2,0–3,5 pt + 10 micro-dots r 1,5 pt
- Chute 10–22 pt, fade **0,45 s**, `easeIn`
- Couleur = couleur exacte du blox

### 3.2 Sons de chaîne (`playChainClearSound`)

| `chainSeriesLevel` | Taille max vague | Son |
|---|---|---|
| 0 | 5 | `chainNew` |
| 0 | 6–8 | `chainNewCascade1` |
| 0 | ≥ 9 | `chainNewCascade2` |
| 1 | * | `chainNewCascade1` |
| ≥ 2 | * | `chainNewCascade2` |

### 3.3 Compactage (`CompactRiseAnimation`)

| Durée déplacement | **0,25 s**, `easeOut` |
| Déclencheur | Après vidage + décrément Brix |

### 3.4 Cascade

| Pause entre vagues | `cascadeBeatDuration` = **0,07 s** |
| Puis | `chainSeriesLevel += 1` → re-scan |

### 3.5 Popup COMBO (`spawnComboLabelPopup`)

| Niveau | Texte | Délai | Shake écran |
|---|---|---|---|
| 1 | COMBO | 0,45 s | intensity **1,4** |
| ≥ 2 | SUPER / COMBO (2 lignes) | 0,45 s | intensity **2,0** |

Animation texte (identique au `+N`) :
- Grow scale 0,12→1,0 en **0,58 s** `easeOut`
- Shrink 1,0→0,72 + fade **0,33 s**
- Couleur = couleur de la plus grande composante

---

## 4. Brix (Priks)

### 4.1 Décrément (compteur > 0)

- Mise à jour label uniquement (pas d'animation dédiée)

### 4.2 Disparition (`animateVanishingPriks`)

| | |
|---|---|
| **Déclencheur** | Compteur → 0 (chaîne adjacente ou SCRUMBLX/BRIXED) |
| **Durée** | `priksVanishDuration` = **0,18 s** |
| **Visuel** | Spin 360° `easeIn` + fade + shrink ×0,65 |
| **Son** | `priksVanish` ; stagger **0,07 s** si plusieurs |
| **Score** | `+20` pts, popup flottant après animation |

---

## 5. Bombe

### 5.1 Séquence complète (`placeBombAtCell` → `animateBombExplosionAtLanding`)

| Étape | Timing | Détail |
|---|---|---|
| Placement sprite | — | Shader bombe, z 22 |
| Tremblement | **0,3 s** | ±6 pt horizontal |
| Explosion | voir §5.2 | |
| Score | — | +10 pts centre ; +20/Brix |
| Compactage | 0,25 s | puis cascades depuis `chainSeriesLevel = 1` |

### 5.2 Explosion visuelle (`BombExplosionFeedback`)

**Audio / haptique** : `bomb` + `hapticHeavy()` + `shakeScreen(2,5)`

| Élément | Paramètres |
|---|---|
| Flash central | rayon 28 pt, α 0,9→0, scale→0,1, **0,15 s** |
| Ondes de choc | 5 anneaux, stagger **0,09 s**, durée **0,52 s**/anneau, scale 1→3,5 ; 2 premiers **jaunes**, 3 suivants blancs |
| Particules radiales | 50 dots blancs, v 60–200 pts/s, flight 0,30–0,65 s |
| Blocs 3×3 | stagger **0,02 s**/case ; push radial 12–20 pt (**0,18 s**) ; scale up ×1,25 (**0,12 s**) ; rotation 15–30° (**0,2 s**) ; collapse scale→0,01 + fade (**0,22 s**) |

**Emitters SKEmitterNode** (option `spawnEmitter: true`, non utilisé en solo actuel) :
- Gerbe blanche : 72 particules, lifetime 0,32 s, speed 100±60
- Débris colorés : jusqu'à 3 couleurs, 16 particules/couleur
- Durée holder : **0,4 s**

### 5.3 Animation bombe gagnée (`spawnBombEarnedAnimation`)

*Legacy — barre bombe supprimée ; code conservé.*
- Bombe volante 0,52 s vers icône HUD ; 12 dots transfert ; pulse compteur ×1,6

---

## 6. Blocs Magix — effets à l'atterrissage

Popup commun : `spawnMagixNamePopup` — texte blanc 22 pt, montée **44 pt** en **0,85 s**, fade après **0,38 s**.

### 6.1 CHROMAX

| | |
|---|---|
| **Visuel** | Chemin serpentin ≤ 15 cases → couleur aléatoire ; scale pop 0,5→1,4→1,0 par case |
| **Timing** | **0,08 s**/case + pause finale 0,12 s |
| **Audio** | `playChromaxTick` procédural |
| **Suite** | `resolveChains()` |

### 6.2 BRIXED

| | |
|---|---|
| **Visuel** | Devient Brix(9) ; flash blanc α 0,85 sur tous les Brix, **0,20 s** |
| **Logique** | −2 sur tous les autres Brix |
| **Audio** | `playBrixedImpact()` |
| **Suite** | Gravité + `resolveChains()` |

### 6.3 CROSSX

| | |
|---|---|
| **Visuel** | Ligne + colonne → couleur aléatoire ; expansion par distance Manhattan |
| **Timing** | **0,06 s**/anneau ; scale pop 0,5→1,35→1,0 |
| **Audio** | `playCrosxPulse(ring)` |
| **Suite** | `resolveChains()` |

### 6.4 SCRUMBLX

| | |
|---|---|
| **Visuel** | Flash blanc sprite ; décalage horizontal par ligne 1–7 cases, wrap-around ; **0,08 s**/cran, délai **0,3 s** entre lignes |
| **Logique** | −1 tous Brix avant shift |
| **Audio** | `scrumblx` + `priksVanish` staggeré pour Brix à 0 |
| **Suite** | `resolveChains()` |

### 6.5 COLORX

| | |
|---|---|
| **Visuel** | Roulette 5 étapes sur sprite ; overlays blancs α 0,70 sur cases de la couleur courante |
| **Timing** | `[0,10, 0,15, 0,22, 0,30, 0,50]` s/étape ; pop scale ×1,25 |
| **Dissolution** | stagger **0,025 s**/bloc ; scale 1,30→0,01 + fade 0,14 s ; max 8 pops audio |
| **Audio** | `playColorxRouletteClick` + `playColorxDissolvePop` |
| **Score** | Formule chaîne sur le nombre de blocs effacés |

### 6.6 SAINTX (cleanx)

| | |
|---|---|
| **Visuel** | Overlay blanc 0,1→1,0 sur toutes les cases, **2,0 s** ; cycle couleurs 0,40 s/bloc |
| **Dissolution** | Fade overlay 0,20 s ; pop particules + scale 1,30→0,01 |
| **Transform** | Sprite CLEANX → Brix(N) visuel |
| **Audio** | `cleanx` |
| **Score** | +200 pts + Brix(N) sur grille |

### 6.7 TWISTX

| | |
|---|---|
| **Visuel** | Swap couleur↔Brix case par case, ordre mélangé |
| **Timing** | stagger **0,04 s** ; scale pop 0,5→1,35→1,0 |
| **Audio** | `playTwistxFlip(index)` |
| **Suite** | `resolveChains()` |

---

## 7. Ligne entrante (tous les 10 coups)

### 7.1 Preview (`refreshPendingBottomLinePreview`)

| | |
|---|---|
| **Déclencheur** | `moveCount % 10 == 9` ou attaque PvP |
| **Visuel** | 8 demi-cases masquées (crop 50 % bas) sous la grille |
| **Jitter** | cycle **1,1 s**, X ±1,0 / Y ±0,5 pt (sin/cos) |
| **Son** | `pendingRandomLineBloopa` (une fois par apparition) |

### 7.2 Injection (`addRandomLinePushingGridUp`)

| | |
|---|---|
| **Déclencheur** | `moveCount % 10 == 0` |
| **Visuel** | 8 sprites montent depuis bas grille ; stretch proportionnel distance |
| **Vitesse** | ≈ 1280 pts/s (identique chute blox) |
| **Strip fade** | **0,15 s** au départ |
| **Son** | `line` + `hapticHeavy()` |
| **Bounce** | `playLandingBounce` par case, stagger **0,018 s**/colonne |
| **Suite** | `resolveChains()` après `LandingBounce.totalDuration` + stagger |

---

## 8. Score et feedback points

### 8.1 Popup flottant `+N` (`spawnFloatingScorePopup`)

| Paramètre | Valeur |
|---|---|
| Font size | 62 pt |
| z | 35 |
| Grow | 0,12→1,0 en **0,58 s** |
| Shrink + fade | **0,33 s** |
| Couleur | blanc ou couleur chaîne |

### 8.2 Transfert points vers HUD (`ScorePopupFeedback`)

| Paramètre | Valeur |
|---|---|
| Dots | `clamp(points × 0,38, 9, 52)` |
| Rayon dot | 1,8–2,8 pt |
| Fade in | **0,06 s** |
| Burst radial | **0,08 s**, distance 22–46 pt |
| Vol vers score | **0,20 s** `easeIn` |
| Jitter cible | ±26 x, ±12 y pt |

### 8.3 Rolling counter score

| Paramètre | Valeur |
|---|---|
| Durée | `min(0,60, 0,40 + gain/2000 × 0,20)` |
| Easing | ease-out cubique |
| Flash couleur | lerp couleur chaîne → blanc en **0,30 s** après roll |
| Pulse scale | pic `1,2 + chainLevel×0,03` (max ~1,38), montée **0,33 s**, retour **0,11 s** |

### 8.4 Milestones

| Palier | Particules | Distance |
|---|---|---|
| Centaine (100…) | 22 dots blancs | 28–130 pt, 0,35–0,65 s |
| Millier (1000…) | 220 dots multicolores | 56–260 pt (2× distance) |

### 8.5 Colonne vidée (`awardFullyClearedColumnBonuses`)

- Stagger **0,09 s**/colonne (gauche→droite)
- Son : `emptyColumnClear`
- Score : +10 pts/colonne

### 8.6 Feedback qualité coup (`showMoveQualityFeedback`)

*Désactivé* (`realtimeFeedbackEnabled = false`). Si activé :
- `!!` vert, `?` orange-rouge, font 22 pt, montée 22 pt en 0,55 s

### 8.7 Hint ghost (`showHintGhost`)

- α 0,60, clignotement 0,60↔0,20, cycle **0,45 s**/phase
- Reste jusqu'au prochain coup
- 5 hints/partie

---

## 9. Game Over

### 9.1 Pré-animation focus (`playGameOverFocusAnimation`)

| | |
|---|---|
| **Déclencheur** | Colonne pleine, point focal fourni |
| **Durée totale** | **1,38 s** |
| **Shake** | intensity **2,5** |
| **Ondes** | 4 anneaux, stagger **0,12 s**, rayon 2,1×cellule → scale 0,18, **0,34 s** |
| **Titre** | fade in + grow 20→40 pt, hold **0,18 s** |
| **Son** | `end` (déclenché avant overlay) |

### 9.2 Overlay (`presentGameOverOverlay`)

| Élément | Paramètre |
|---|---|
| Fond dim | noir α **0,72** |
| Score, citation, boutons | fade séquentiel |
| Blocs ambiants | spawn continu (voir §11) |
| Victoire PvP | `victory` |

---

## 10. Transitions et stages

### 10.1 Overlay transition (`showTransitionOverlay`)

| | |
|---|---|
| **Déclencheur** | Changement stage, intro tuto/Zen |
| **Son** | `transition` |
| **Fond** | α 0→0,52 en **0,20 s** |
| **Slide in** | **0,45 s** `easeOut` |
| **Pause** | **1,0 s** |
| **Fade out** | **0,35 s** |
| **Particules** | Traînées jaunes dans le sillage des textes |

### 10.2 Timer stage

| Stage | Durée/coup | Multiplicateur |
|---|---|---|
| 1 | 32 s | ×1 |
| 2 | 16 s | ×2 |
| 3 | 8 s | ×3 |
| 4 | 4 s | ×4 |
| 5 | 2 s | ×5 |
| Ultime | 1 s | ×6 |

- Grace period preview : **1,5 s** minimum avant premier tick
- Couleur timer : rouge (0–2 s), orange (3–5 s), blanc (6+)
- Auto-drop : `hapticSoft()` + `dropBlock` colonne préférée

---

## 11. UI et ambiance

### 11.1 Écran d'accueil

| Effet | Paramètres |
|---|---|
| Tips rotation | toutes les **5 s**, fade swap texte |
| Titre slot machine | cycle **2,0 s**, ease custom |
| Chips entrée | stagger bas→haut, slide **16 pt**, scale 1,15→1,0, fade **0,12 s** |
| Blocs ambiants | spawn aléatoire 0–2 s (voir §11.3) |

### 11.2 Boutons (`BlomixSKButtonNode`)

| Phase | Durée | Détail |
|---|---|---|
| Press | `pressAnimDuration` | scale down + move Y |
| Release phase 1 | `releasePhase1Duration` | scale 1,07 + retour position |
| Under-shoot | 0,06 s | scale 0,98 |
| Settle | 0,04 s | scale 1,0 |

### 11.3 Blocs ambiants (`BlomixAmbientBlocksView`)

- SpriteKit (accueil, Game Over) et UIKit (settings)
- Vitesse aléatoire, rotation lente, rebond sur bords
- z 0,5 (entre fond et contenu)

### 11.4 Compteur LIGNE x/10

| Valeur | Couleur | Effet |
|---|---|---|
| 0–5 | gris `#A3A3A3` | — |
| 6–8 | orange `#F4A261` | — |
| 9–10 | rouge | shake ±2 pt, cycle 0,05 s |

---

## 12. Haptique et screen shake

| Fonction | Style UIKit | Usage |
|---|---|---|
| `hapticSoft()` | `.soft` | Auto-drop stage |
| `hapticLight()` | `.light` | Début dissolution chaîne |
| `hapticHeavy()` | `.heavy` | Bombe, ligne entrante, explosion |

**Screen shake** (`shakeScreen`) :
- `CAKeyframeAnimation` position.x, durée **0,14 s**
- Valeurs : `[0, v, −v, 0,55v, −0,55v, 0,2v, −0,2v, 0]`
- Intensités courantes : combo **1,4–2,0**, bombe/GO **2,5**

---

## Annexe — Enums de constantes (référence rapide)

```
LandingBounce          squash 0,09 | stretch 0,03 | settle 0,03
FlightStretch          x 0,82 | y 1,25
CompactRiseAnimation   duration 0,25
ChainClearFeedback     dissolve 0,20+0,16+0,14 | stagger 0,04 | cascade 0,07 | priks 0,18
PendingLinePreview     jitter X 1,0 Y 0,5 | cycle 1,1
ScorePopupFeedback     transfer 0,20 | fadeIn 0,06 | burst 0,08 | dots 9–52
GameOverFocus          total 1,38 | rings 4 | stagger 0,12
BombExplosionFeedback  shock 0,52×5 | flash 0,15 | block stagger 0,02
ghostHoldDelay         0,12
```

---

*Ce document doit être mis à jour à chaque modification des enums `*Feedback`, des sons `BlomixMatchSFX`, ou des effets Magix dans `GameScene.swift`.*
