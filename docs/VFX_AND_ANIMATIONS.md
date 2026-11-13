# Blomix — Spécification VFX, animations et sons

> **Version de référence** : 8.8  
> **Sources principales** : `GameScene.swift`, `BlomixProceduralSFX.swift`, `BlomixSKButtonNode.swift`, `BlomixAmbientBlocksView.swift`  
> **Dernière mise à jour** : novembre 2026 (lots matière, cascade, ligne, mort, accueil, modaux, Clair, air — local 8.9, sans bump)  
> Pistes d’amélioration (pas la spec) : [JUICE_PISTES.md](JUICE_PISTES.md)

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
| `magix` | `magix.wav` | Atterrissage Magix (accord voix court, ex-chaîne Trace). Pas les sons d’effet (SAINTX, SCRUMBLX, procéduraux) |
| `magixFollow` | `magix_follow.wav` | Magix posé juste après un autre Magix (accord voix long). Une ligne entre les deux ne compte pas comme un coup |
| `bombLoad` | `gun_load.wav` | Activation mode bombe |
| `bomb` | `bomb.wav` | Explosion bombe |
| `cleanx` | `cleanx.wav` | Animation SAINTX (cleanx) |
| `scrumblx` | `scrumblx.wav` | Déclenchement SCRUMBLX |

### Sons procéduraux (`BlomixProceduralSFX`)

Synthèse PCM en mémoire (44,1 kHz, pool de 14 `AVAudioPlayerNode`). Volume modulé par `BlomixMatchAudioSettings.shared.masterVolume`.

| Fonction | Déclencheur | Durée | Pitch / timbre | Gain |
|---|---|---|---|---|
| `playChromaxTick(step, total)` | CHROMAX : chaque case transformée | 0,055 s | C5→C6 selon `step/total` | 0,55 |
| `playCrosxPulse(ring)` | CROSSX / SLASHX : chaque anneau | 0,075 s | 700 Hz / 1,07^ring | 0,50 |
| `playBombxStain(rank, indexInRank)` | BOMBX : chaque case peinte (R0…R3) | 0,055–0,095 s | ~195→410 Hz selon rang ; tête de vague +20 % | 0,42–0,74 |
| `playTwistxFlip(index)` | TWISTX : chaque case swappée | 0,038 s | 880 Hz (pair) / 660 Hz (impair) | 0,45 |
| `playColorxRouletteClick(step)` | COLORX : étape roulette (0–4) | 0,055 s | 880→728 Hz (−38/step) | 0,60 |
| `playColorxDissolvePop()` | COLORX : dissolution par bloc | 0,030 s | 340–480 Hz aléatoire | 0,40 |
| `playBrixedImpact()` | BRIXED : flash initial | 0,210 s | Sweep 115→42 Hz + bruit | 0,70 |

Staggers audio Magix alignés sur les animations visuelles :
- CHROMAX : **0,08 s**/case
- CROSSX / SLASHX : **0,06 s**/anneau
- BOMBX : **0,055 s**/case (vagues R0→R3 ; R0 plus présent)
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
| 220 | Toast trophée (palier, overlay) |
| 250 | Overlay quitter / record perso |
| 300 | Overlay transition stage/tuto |

---

## 1. Placement de bloc (Blox, Brix, Magix)

### 1.1 Chute et atterrissage (`dropBlock`)

| | |
|---|---|
| **Déclencheur** | Tap colonne valide, bloc normal |
| **Réf. code** | `dropBlock`, `LandingBounce`, `FlightStretch`, `BrixLandingBounce`, `BrixFlightStretch` |

**Vol (commun Blox / Brix / Magix) :**
- Départ : position preview → snap instantané bas de colonne (`duration: 0`)
- Vitesse : `cellPoints × 8 / 0,25` ≈ **1280 pts/s** (identique pour tous les types)
- Durée montée : `max(0,07, distance / vitesse)` — `easeOut`
- De-stretch en vol : retour `(1,1)` en `easeIn`

**Tour en vol** (`flightSpinAction`) — Magix toujours, et tout bloc lâché après un appui long qui a montré la colonne ghost (≥ 0,12 s). Pas le ghost du timer ≤ 2 s, pas un tap court, pas la bombe.
- Un tour pile (±2π), sens 1 chance sur 2, sur **la durée de cette montée**
- easeOut quadratique, même famille que la montée : le tour se pose avec le bloc, droit à l’arrivée
- Le sprite de grille qui le remplace est à rotation 0. Chiffre Brix et symbole Magix tournent avec le sprite
- **Réduire les animations** : pas de tour. Vitesse, stretch, traîne et bounce inchangés

**Stretch en vol** (`flightStretchScales(for:)`) :

| Type | xScale | yScale | Enum |
|---|---|---|---|
| Blox / Magix | 0,82 | 1,25 | `FlightStretch` |
| Brix | 0,88 | 1,16 | `BrixFlightStretch` |

**Traînée de particules** (`makeTrailSpawnAction`) — Blox / Brix identiques ; Magix / bombe = palette d’orbite **par grain** :
- Intervalle spawn : **0,04 s** (~25/s)
- 3 traînées (centre + ±9 pt) + 4 micro-dots aléatoires
- Rayon dots : 1,8–3,0 pt (centre), 1,0–2,0 pt (latérales) — pas les rayons d’orbite (lisibilité à 1280 pt/s)
- Fade-out : **0,38 s**
- Couleur : blox = couleur skin ; brix = `priksSolidFillColor()` ; **Magix** = `bloxSKColors` aléatoire ; **bombe** (pose) = rouge / jaune / quasi-noir

**Atterrissage** (`playLandingBounce`) — profil selon le type posé :

| | Blox / Magix | Brix |
|---|---|---|
| **Enum** | `LandingBounce` | `BrixLandingBounce` |
| **Total** | **0,15 s** | **0,12 s** |
| A — squash | 0,09 s · y + h×0,055 · x 1,32 / y 0,78 | 0,07 s · y + h×0,035 · x 1,18 / y 0,86 |
| B — rebond | 0,03 s · y − h×0,13 · x 0,94 / y 1,15 | 0,025 s · y − h×0,07 · x 0,97 / y 1,08 |
| C — settle | 0,03 s · retour p0 · x/y 1,0 | 0,025 s · idem |

**Particules impact** (`spawnLandingImpactSparkles`) — couleur du bloc ; pose **et** compactage :
- Blox — éjection : 12 ronds, **0,22 s**, rayon 0,8–1,8 pt, drift 12–26 pt
- Brix — éjection : **6–8 micro-carrés**, côté 1,5–2,5 pt, même drift / durée ; **pas** de vol HUD (≠ mort)
- Poudre (les deux) : 38 ronds, **0,80 s**, rayon 0,5–1,2 pt, drift 1–5 pt

**Gerbe Magix** (`spawnMagixLandingBurst`) — **à la place** de l’impact blanc, tous Magix identiques :
- 40–48 ronds r **1,0–1,8 pt** (même matière que l’orbite preview)
- Couleur = palette blox du skin, **par** particule
- Spawn sur l’anneau du disque (±4 pt), vol radial **+24–52 pt**, **0,34 s** `easeInEaseOut`
- Fade 0 → 0,85 en 0,05 s puis 0 ; z 37 ; **scène** (pas enfant du sprite)
- Ne retarde pas l’effet Magix (toujours après bounce **0,15 s**)

**Sons d'atterrissage** (`landingFeel`) :

| Groupe formé | Son |
|---|---|
| 1 (isolé) | `place` |
| 2 connexes | `connectE` |
| 3 connexes | `connectF` |
| 4 connexes | `connectGb` |
| ≥ 5 (chaîne) | *(aucun — le son chaîne prend le relais)* |
| Magix | `magix` |
| Brix | `place` |

**Haptique d’arrivée** (même instant que le son ; voir § 12) : pose douce, connect 2/3/4 de plus en plus net, Magix medium, refus de colonne sourd. Une chaîne (≥ 5) ne tape pas ici : les deux impulsions partent au début de la dissolution.

**Voisins** (`nudgeNeighbors`) — pose seule, pas la ligne entrante :
- 8 voisins occupés, diagonales comprises. Pas la case qui rebondit
- Même couleur de Blox : **2 pt vers** la case. Autre Blox, Brix ou Magix : **2 pt loin** d’elle. Même distance en diagonal
- 0,04 s aller + 0,06 s retour (`neighborNudge`)
- Fini avant la dissolution (attente bounce 0,15 s / 0,12 s)
- **Réduire les animations** : pas de coup

**Délai post-bounce** : `landingBounceTotalDuration(for:)` (0,15 s blox / 0,12 s brix) avant `resolveChains()` ou effet Magix. Le coup de voisin n’allonge pas cette attente.

**Ligne entrante** : stretch proportionnel par colonne via `flightStretchScales(for:)` ; bounce et délai post-ligne adaptés au type de chaque case.

### 1.2 Preview bloc courant

| Effet | Paramètres |
|---|---|
| Respiration (`previewBreathKey`) | scale 1,0↔1,2, **0,5 s**/phase, `easeInEaseOut`, infini |
| Jitter imminent ligne (`startPreviewJitter`) | cycle **0,85 s**, amplitude X **±1,6**, Y **±0,9** pt, sin/cos ×1,7 fréquence. **Réduire les animations** : la respiration calme reste |
| Stop | snap scale 1,0 en **0,06 s** |

### 1.3 Ghost preview (appui long ≥ 120 ms)

| | |
|---|---|
| **Déclencheur** | `ghostHoldDelay = 0,12 s` maintenu |
| **Visuel** | Colonne : cases vides, sprite couleur du token `ghostColumnHighlight` (sombre ~`#444` α 0,9 ; clair `#E6DCC8` α 0,92). Bloc fantôme α **0,55**, même construction que la grille (`makeSolidGameplayBlockSprite`). Pas de `SKShapeNode`, pas de texture 1×1 partagée : une texture UIGraphics statique reste blanche jusqu’au prochain lancement du processus. |
| **z** | container **18** ; cases **1**, bloc fantôme **2** |
| **Audio** | — |
| **Réf.** | `showGhostPreview`, `ghostHoldTimer`, `hideDropGhostVisuals` |
| **Sortie** | Masqué ☰ / overlay quitter / accueil (`clearAutoDropAim`). Colonne auto-drop conservée pendant pause chrome ; réaffichée si ≤ 2 s. Timeout (Arcade / Défi / Duel) : si l’appui est encore là, drop **dans cette colonne**. |

### 1.4 Colonne invalide

| Son | `wrong` |
| Haptique | tap sourd (voir § 12). La colonne pleine sans autre issue passe par le game over, choc lourd. |

---

## 2. Rendu des blocs

### 2.1 Blox couleur

- Sprite plein 36×36 pt (`cellPoints − 4`), coins droits, couleur unie (`SKSpriteNode(color:)`, pas de texture en cache)
- **Jonctions** : barres H 4×36 / V 36×4 / diagonales entre voisins même couleur (`junction_*`, z ≈ 2)
  - **Chaîne / cascade** : la barre fond avec le **premier** des deux blox (`min(index) × 0,04 s`, 0,20 s, z 25, squash dans l’épaisseur du joint). Pas de retrait à t = 0.
  - **Magix peinture, COLORX roulette, bombe, compactage, réarrangements** : `removeBloxJunctionElementsTouching` immédiat (le réseau est cassé, ce n’est pas une mort de groupe).
- Couleurs : skin actif (`BlomixSkinCatalog`)

### 2.2 Brix (Priks)

- Fond couleur `priks` du skin
- Chiffre centré, police joueur ; taille ×0,72 si valeur ≥ 10
- Teinte du glyphe : mix `prikstext` → fond `priks` selon le compteur (`priksDigitSKColor(remainingHits:)`). n ≥ 5 = 100 % glyphe ; 4 = 80 % ; 3 = 60 % ; 2 = 40 % ; 1 = 20 % (presque le fond). Swap au pic du −1, même cran que le texte.
- Pas d'animation idle

### 2.3 Blocs Magix (rendu continu)

| Élément | Paramètres |
|---|---|
| Forme | **Disque inscrit** (taille bombe : `cell − 4 pt`) + couronne noire (même recette shader que la bombe) |
| Shader | Dégradé 6 couleurs animé via `u_time` (GLSL) |
| Halo (`magixGlow`) | Spread **16 pt**, α pulse 0,28↔0,55, cycle **1,2 s** |
| Particules orbitales | Spawn **0,12 ± 0,06 s**, **2–3** grains/burst (~2/3 petits r 0,40–0,80, le reste 1,0–1,8). Naissance dans la **couronne colorée** (épaisseur = 2 liserés noirs, UV 0,38←0,50). Vol jusqu’au **bord du halo** (spread 16 pt) en **1,55 s** ; opaque pendant le disque + halo interne (fade in 0,25 / hold 0,80) ; fade out **0,50 s** au bout du halo. α 0,82, z 1. Même recette bombe (`SpecialOrbitJuice`). |
| Symbole | Police ×0,69 hauteur bloc, noir, z 5 |
| En chute | Même rendu via `makeMagixShaderSprite` |
| Après effet | Blox / Brix restants **carrés** |

### 2.4 Bombe (sprite HUD + chute)

- Disque + couronne noire (shader)
- Shader noir → rouge → jaune (cycle 3 couleurs)
- Halo + orbites : **même géométrie** que Magix (`SpecialOrbitJuice`) ; dots rouge / jaune / quasi-noir
- Chiffre « nuke » si stage ≥ 2
- Activation : `bombLoad` ; tremblement pré-explosion **0,3 s** (±6 pt, 6 oscillations × 0,05 s)

---

## 3. Chaînes et cascades

### 3.1 Dissolution (`animateWinningChainDisappearance`)

| | |
|---|---|
| **Déclencheur** | Groupe ≥ 5 détecté |
| **Haptique** | deux transients Core Haptics à 0 et 0,04 s (intensité 0,48 → 0,82). Repli : deux `UIImpact` `.light` |
| **Son** | `playChainClearSound` (voir tableau ci-dessous) |
| **Stagger** | Vague 1 : **0,04 s**/case. Vague 2 : **0,028 s**. Vague 3+ : **0,020 s**. Ordre ligne→colonne. **Réduire les animations** : toujours 0,04 s |
| **Shake** | Vague 2 : intensity **1,4** au début de la dissolution. Vague 3+ : **2,0**. Vague 1 (y compris CONNECT seul) : rien. Pas un second shake avec le texte. **Réduire les animations** : pas de shake |
| **Réf.** | `ChainClearFeedback.waveFeel` |

**Par case (durée totale ≈ 0,50 s) :**

| Étape | Durée | Détail |
|---|---|---|
| Scale up | 0,20 s | ×1,30, `easeOut` |
| Pop dots | instant | `spawnChainPopDots` |
| Scale down + brighten | 0,16 s | lerp blanc 30 %, `easeInEaseOut` |
| Fade | 0,14 s | α → 0 |

**Jonctions** : pas de `remove` à t = 0. Chaque barre H/V/D part avec le premier blox du couple (`dissolveBloxJunctionsWithChainCells`). H : `xScale` → 0,02 ; V : `yScale` → 0,02 ; D : les deux. Fade 0,20 s `easeOut`, z 25 pendant la fonte. Combo / cascade = le même path (le `drawGrid` inter-vague recoud le reste).

**Placeholder gris** (`cell_dissolve_bg_*`) sous le sprite pendant le fondu.

**Particules dissolution** (`spawnChainPopDots`) :
- 7–10 dots : vague 1 r **2,0–3,5** pt ; vague 2 r **2,6–4,4** ; vague 3+ r **3,2–5,2**. + 10 micro-dots r **1,5** pt (inchangés). COLORX / SAINTX / bombe, et **Réduire les animations**, gardent le rayon de la vague 1
- **Vol vers le gros score** à **vitesse constante** (~820 pt/s = 0,25 s du centre de grille au score), `easeIn`, plancher **0,12 s**
- Pas de chute / fondu ; spawn au pic du scale-up
- Couleur = couleur exacte du blox
- HUD : le roulement **part à la première** arrivée et **s’arrête à la dernière**. Compactage / cascade / saisie **n’attendent pas**.
- Dots du `+N` : plus de vol t0. Le glyphe se brise à **t = 0,58 s** (voir § 8.1) ; les paillettes de cases restent indépendantes.
- **Magix** : si la chaîne est née d’un Magix (peinture CHROMAX / CROSSX / SLASHX / TWISTX / BOMBX, ou cascade après COLORX / SAINTX / BRIXED / SCRUMBLX), **+10 grains d’orbite** locaux au même pic (`spawnSpecialOrbitLingerSparks`, palette Magix, pas HUD). Coup joueur ou bombe : pas de linger Magix.

### 3.2 Sons de chaîne (`playChainClearSound`)

| `chainSeriesLevel` | Taille max vague | Son |
|---|---|---|
| 0 | 5 | `chainNew` |
| 0 | 6–8 | `chainNewCascade1` |
| 0 | ≥ 9 | `chainNewCascade2` |
| 1 | * | `chainNewCascade1` |
| ≥ 2 | * | `chainNewCascade2` |

### 3.3 Compactage (`CompactRiseAnimation`)

| Durée file de jeu | **0,20 s** (premier départ → dernière arrivée) |
| Stagger colonne | Le blox **le plus haut** (près du trou) part le premier, puis celui d’en dessous, etc. **0,018 s**/blox, budget max **0,06 s** (vol min **0,14 s**). Même durée de vol dans la colonne ; tout le monde atterrit à 0,20 s. Colonnes indépendantes. |
| Stretch en montée | Même profil que le lancer (`FlightStretch` 0,82/1,25 ; Brix plus discret) ; destretch pendant le vol (pas pendant l’attente). |
| Bounce + paillettes | À l’arrivée, **cosmétique** (`playCompactLandingJuice`) : squash/stretch/settle + 2 couches d’impact. **N’attend pas** cascade / saisie. Pas de son `place` / `connect`. |
| Voisins immobiles | Après le bounce : **1 pt** vers l’arrivée si même couleur de Blox, sinon loin (8 voisins). Une fois, direction moyenne si plusieurs. Pas les blocs qui rebondissent. **Réduire les animations** : rien. |
| Cascade pendant bounce | La dissolution **annule** le bounce (et le coup de voisin) et recale scale/position. |
| Déclencheur | Après vidage + décrément Brix |

### 3.4 Cascade

| Pause entre vagues | `cascadeBeatDuration` = **0,07 s** (le crescendo ne l’allonge pas, ni le compactage 0,20 s) |
| Puis | `chainSeriesLevel += 1` → re-scan |

### 3.5 Popup COMBO (`spawnComboLabelPopup`)

Commentaire, pas la monnaie. Le `+N` (62 pt, grow 0,58 s) reste devant. Le shake est celui de la dissolution (§3.1), pas celui du texte. Jamais de vol vers le HUD.

| Niveau | Texte | Délai |
|---|---|---|
| 1 | COMBO | 0,72 s |
| ≥ 2 | SUPER / COMBO (2 lignes, écart 36 pt) | 0,72 s |

- Police **40** pt (couleur de la plus grande composante)
- Grow scale **0,55→1,0** en **0,36 s** `easeOut`
- Shrink 1,0→**0,82** + fade **0,28 s**
- **Réduire les animations** : même délai, fondu d’entrée **0,12 s** à l’échelle 1, puis fondu de sortie. Pas de scale

### 3.6 CONNECT (pont latéral)

| | |
|---|---|
| **Déclencheur** | Composante chaîne qui touche col 0 **et** col 7 |
| **Score** | +100 (puis × stage Arcade) ; inclus dans le `+N` de la composante |
| **Popup** | **CONNECT**, même cinématique que COMBO (delay 0,72 s, 40 pt, pas de shake). Si COMBO la même vague : CONNECT **52** pt plus haut |
| **Flash** | Point chrome (r 3,6 pt, blanc Sombre / noir Clair) sur la **face externe** d’un blox mur G et d’un blox mur D (paire à plus petit écart de ligne). Départ = stagger de **cette** case ; grow 0,20 s puis fade 0,30 s (fenêtre de dissolution) |
| **Pont** | Trait chrome (même teinte, largeur 3,2 pt) : face G → centres du **plus court chemin 8-connexe dans la composante** → face D. Fade in / hold / fade out dans la fenêtre stagger des blox du chemin (≤ compactage). `z` 25,8 (sous les points). Pas enfant des sprites. |
| **Réf.** | `LateralConnectBonus`, `spawnConnectLabelPopup`, `spawnLateralConnectFlash`, `spawnLateralConnectPath` |

---

## 4. Brix (Priks)

### 4.1 Décrément (compteur > 0)

- Le **bloc** ne bouge pas (pas de scale / colorize).
- Le **chiffre** : ×1,0 → ×**1,3** en **0,12 s** (`easeOut`) ; **au pic** le texte **et** la teinte passent à n−1 (palier 20 % vers le fond) ; retour ×1,0 en **0,60 s** (`easeInEaseOut`). Pas de SFX.
- Plusieurs Brix dans la même vague : stagger **0,04 s**/chiffre, ordre `(ligne, colonne)` (même famille que la dissolution). Le compactage attend le dernier swap.
- **SCRUMBLX** : même anim, **avant** le décalage des lignes (`max(flash 0,18 s, dernier swap)`). Le settle peut continuer pendant le slide.

### 4.2 Disparition (`animateVanishingPriks`)

| | |
|---|---|
| **Déclencheur** | Compteur → 0 (chaîne adjacente, SCRUMBLX, BRIXED…) |
| **Durée totale** | `BrixVanishFeedback.totalDuration` = **0,20 s** |
| **Réf. code** | `BrixVanishFeedback`, `spawnBrixVanishSquareDots`, `spawnBrixVanishPresenceStars` |

**Séquence par Brix :**

| Phase | Durée | Détail |
|---|---|---|
| Pop | 0,07 s | scale → 1,10, flash blanc 35 %, `easeOut` |
| Paillettes carrées | instant | `spawnBrixVanishSquareDots` (voir ci-dessous) |
| Étoiles de présence | instant | `spawnBrixVanishPresenceStars` — 3 étoiles 4 branches dans la case |
| Implosion | 0,13 s | scale → 0,55, fade α→0, wobble ±54° (`π×0,3`), `easeIn` |
| Chiffre | 0,10 s | fade du label en parallèle de l'implosion |

**Paillettes carrées** (même vol HUD que les blox, forme carrée) :
- 11–15 carrés principaux (côté 4–7 pt) + 15 micro-carrés (3 pt)
- Spawn au pic du pop (t = **0,07 s**), dans la case
- Vol vers le gros score à **~824 pt/s**, `easeIn`, plancher **0,12 s** (pas de chute / fondu)
- Couleur = teinte brix du skin (`priksSolidFillColor()`)

**Étoiles de présence** (restent dans la case, **pas** de vol HUD) :
- **3** étoiles 4 branches, rayon 5–7 pt, spread `±0,42 × case`
- Spawn au pic du pop (même t que les carrés)
- Rotation continue, sens et période tirés au sort (0,55–1,10 s / tour)
- Blanc en Sombre, noir en Clair (`BlomixAppearance.isDark`)
- Hold 0,41 s puis fade 0,23 s. Compactage **n’attend pas**. Nœuds scène, pas enfants du sprite.

**Son** : `priksVanish` ; stagger **0,07 s** si plusieurs Brix disparaissent ensemble.

**Score** : `+20` pts / Brix, un `+N` au centroïde (couleur Brix, shatter comme les chaînes), **au pic du pop** (même t que les carrés). Roulement HUD **linéaire** : **première** paillette → **dernière** (+ **0,08 s** de marge). Compactage / cascade **n’attendent pas**.

SCRUMBLX : carrés + étoiles + `+N` au trou (pas de pop/implosion, le slide suit). **Bombe** : mêmes étoiles dans chaque case Brix au pic ×1,25 (explosion inchangée).

**Magix** : si le Brix → 0 est causé par un Magix (BRIXED, SCRUMBLX, ou décrément adjacent d’une chaîne Magix), **+10 grains d’orbite** Magix au pic du pop (en plus des carrés HUD / étoiles). Chaîne joueur / bombe : pas de linger Magix.

---

## 5. Bombe

### 5.1 Séquence complète (`placeBombAtCell` → `animateBombExplosionAtLanding`)

| Étape | Timing | Détail |
|---|---|---|
| Placement sprite | — | Shader bombe, z 22 |
| Tremblement | **0,3 s** | ±6 pt horizontal |
| Explosion | voir §5.2 | |
| Score | pic scale-up (t ≈ 0,12 s) | +10 pts centre + +20/Brix ; paillettes HUD (ronds blox / carrés Brix) au même pic, stagger 0,02 s/case. **Étoiles de présence** dans chaque case Brix (même recette §4.2). Compactage **n’attend pas** le HUD |
| Compactage | 0,20 s | puis cascades depuis `chainSeriesLevel = 1` |

Zone logique : **3×3** (Zen / Duel / tuto / Arcade L1) ; en Arcade L2+ : 3×3 + bras cardinaux (`bombCrossArmLength` = index de stage), texture HUD **nuke**. L’anim de destruction ci-dessous s’applique à **toutes** les cases de `bombAffectedCells` (le nom « Blocs 3×3 » est historique).

### 5.2 Explosion visuelle (`BombExplosionFeedback`)

**Audio / haptique** : `bomb` + `hapticHeavy()` + `shakeScreen(2,5)`

| Élément | Paramètres |
|---|---|
| Flash central | rayon 28 pt, α 0,9→0, scale→0,1, **0,15 s** |
| Ondes de choc | 5 anneaux, stagger **0,09 s**, durée **0,52 s**/anneau, scale 1→3,5 ; 2 premiers **jaunes**, 3 suivants blancs |
| Particules radiales | 50 dots blancs, v 60–200 pts/s, flight 0,30–0,65 s |
| Blocs 3×3 | stagger **0,02 s**/case ; push radial 12–20 pt (**0,18 s**) ; scale up ×1,25 (**0,12 s**) ; rotation 15–30° (**0,2 s**) ; collapse scale→0,01 + fade (**0,22 s**) |
| Paillettes score | au pic ×1,25 : ronds blox (`spawnChainPopDots`) / carrés Brix (`spawnBrixVanishSquareDots`) → HUD ~824 pt/s. Anim des blocs **inchangée**. 50 dots blancs **restent** (pas HUD) |
| Grains d’orbite | **+10** / case occupée, même recette idle (`SpecialOrbitJuice`), palette bombe, vol local ~16 pt **1,55 s**, z 37, nœuds scène. **Pas** vers le score. Compactage n’attend pas. `spawnSpecialOrbitLingerSparks` |

**Emitters SKEmitterNode** (option `spawnEmitter: true`, non utilisé en solo actuel) :
- Gerbe blanche : 72 particules, lifetime 0,32 s, speed 100±60
- Débris colorés : jusqu'à 3 couleurs, 16 particules/couleur
- Durée holder : **0,4 s**

### 5.3 Animation bombe gagnée (`spawnBombEarnedAnimation`)

*Legacy — barre bombe supprimée ; code conservé.*
- Bombe volante 0,52 s vers icône HUD ; 12 dots transfert ; pulse compteur ×1,6

---

## 6. Blocs Magix — effets à l'atterrissage

**Pose commune** (avant l’effet) : bounce blox **0,15 s** + gerbe palette §1.1 (`spawnMagixLandingBurst`). Popup nom : `spawnMagixNamePopup` — texte 22 pt, montée **44 pt** en **0,85 s**, fade après **0,38 s**.

**Langue linger** : toute disparition de blox / Brix **causée par un Magix** (wipe direct **ou** chaînes / cascades / Brix → 0 après peinture) reçoit ~10 grains d’orbite Magix (`spawnSpecialOrbitLingerSparks`) au pic, en plus du HUD. Compactage n’attend pas. Bombe : linger sur le blast seulement (§5.2). Flag `magixCausedDisappearLinger` de `applyMagixEffect` jusqu’à la fin des cascades (pas persisté).

### 6.1 CHROMAX

| | |
|---|---|
| **Visuel** | Chemin serpentin ≤ 15 cases → couleur aléatoire. **Case d’atterrissage** : le disque **mue** en blox (strip aura, pulse ×1,18). Autres cases : pop 0,5→1,4→1,0 |
| **Timing** | **0,08 s**/case + pause finale 0,12 s |
| **Audio** | `playChromaxTick` procédural |
| **Suite** | `resolveChains()` — chaînes / Brix → 0 nés de la peinture : linger Magix (§3.1 / §4.2) |

### 6.2 BRIXED

| | |
|---|---|
| **Visuel** | Le disque **mue** en Brix(9) (même sprite, pulse ×1,18) ; flash blanc α 0,85 sur tous les Brix, **0,20 s** |
| **Logique** | Devient Brix(9) ; **détruit** tous les autres Brix (+20 chacun) |
| **Audio** | `playBrixedImpact()` |
| **Orbite locale** | Au pic du pop : +10 grains palette Magix / case (en plus des carrés HUD) |
| **Suite** | Gravité + `resolveChains()` — chaînes / Brix suivants : même linger |

### 6.3 CROSSX

| | |
|---|---|
| **Visuel** | Ligne + colonne → couleur aléatoire ; expansion par distance Manhattan. **Centre** : mue du disque ; autres cases : pop 0,5→1,35→1,0 |
| **Timing** | **0,06 s**/anneau |
| **Audio** | `playCrosxPulse(ring)` |
| **Suite** | `resolveChains()` — chaînes / Brix → 0 nés de la peinture : linger Magix (§3.1 / §4.2) |

### 6.3b SLASHX

Même pipeline que CROSSX (`applyMagixAxisPaint`) : une couleur, pop, `playCrosxPulse`, puis `resolveChains()`. Géométrie = **deux diagonales** ; anneaux = `|Δrow|`.

| | |
|---|---|
| **Visuel** | Diagonales → couleur aléatoire ; expansion depuis le centre. **Centre** : mue du disque |
| **Timing** | **0,06 s**/anneau (identique CROSSX) |
| **Audio** | `playCrosxPulse(ring)` (cousin) |
| **Suite** | `resolveChains()` — chaînes / Brix → 0 nés de la peinture : linger Magix (§3.1 / §4.2) |

### 6.4 SCRUMBLX

| | |
|---|---|
| **Visuel** | Gerbe palette **consommation** + flash blanc sprite ; **chiffres Brix −1** (même anim §4.1) avant le mélange ; décalage horizontal par ligne 1–7 cases, wrap-around ; **0,08 s**/cran, délai **0,3 s** entre lignes ; **placeholders gris** (`white: 0.12`) sur cases vidées (Brix −1→0, atterrissage) pour l’animation. Brix → 0 : carrés HUD + **+10 grains d’orbite Magix** (linger, pas score) |
| **Logique** | −1 tous Brix avant shift |
| **Audio** | `scrumblx` + `priksVanish` staggeré pour Brix à 0 |
| **Fin d’anim** | Attente = **max** sur toutes les lignes de `preShiftHold + idx×0,3 + steps×0,08` (`preShiftHold = max(flash 0,18 s, dernier swap chiffre)`) ; réapplication idempotente des shifts depuis snapshot pré-décalage ; `drawGrid` puis compaction vers le haut |
| **Suite** | compaction animée + `resolveChains()` — chaînes / Brix suivants : linger Magix |

### 6.5 COLORX

| | |
|---|---|
| **Visuel** | Roulette 5 étapes sur sprite ; overlays blancs α 0,70 **taille blox** (`cell.size`) sur la couleur courante ; **jonctions H/V/D retirées avant** le 1er overlay |
| **Timing** | `[0,10, 0,15, 0,22, 0,30, 0,50]` s/étape ; pop scale ×1,25 |
| **Fin du disque** | gerbe palette consommation + fade **0,18 s** (avant la dissolution des blox) |
| **Dissolution** | stagger **0,025 s**/bloc ; scale 1,30 (0,10 s) → paillettes HUD **et** +10 grains d’orbite Magix (linger scène) → 0,01 + fade 0,14 s ; max 8 pops audio |
| **Audio** | `playColorxRouletteClick` + `playColorxDissolvePop` |
| **Score** | Formule chaîne sur le nombre de blocs effacés |
| **Suite** | compaction + `resolveChains()` — cascades suivantes : même linger |

### 6.6 SAINTX (cleanx)

| | |
|---|---|
| **Visuel** | Overlay blanc 0,1→1,0 sur toutes les cases, **2,0 s** ; cycle couleurs 0,40 s/bloc |
| **Dissolution** | Fade overlay 0,20 s ; pop particules HUD **et** +10 grains d’orbite Magix / case ; scale 1,30→0,01 |
| **Transform** | Dès l’atterrissage : SAINTX → Brix visuel **0** ; le chiffre défile linéairement jusqu’à **N** pile à l’explosion (2,2 s) |
| **Audio** | `cleanx` |
| **Score** | +200 pts + Brix(N) sur grille |
| **Suite** | compaction + `resolveChains()` — cascades suivantes : linger Magix |

### 6.7 TWISTX

| | |
|---|---|
| **Visuel** | Disque **consommé** (gerbe palette + fade 0,18 s) ; swap couleur↔Brix case par case, ordre mélangé |
| **Timing** | stagger **0,04 s** ; scale pop 0,5→1,35→1,0 |
| **Audio** | `playTwistxFlip(index)` |
| **Suite** | `resolveChains()` — chaînes / Brix → 0 nés du swap : linger Magix (§3.1 / §4.2) |

### 6.8 BOMBX

| | |
|---|---|
| **Visuel** | Tâche 3 rangs sur cases occupées. **Rang 0** : mue du disque ; autres : pop 0,5→1,35→1,0 |
| **Timing** | **0,055 s**/case (R0→R1→R2→R3) + pause finale 0,12 s |
| **Audio** | `playBombxStain(rank, indexInRank)` — R0 plus fort/long, pitch monte avec le rang ; pas `bomb.wav` / bombLoad |
| **Suite** | `resolveChains()` ; dots couleur → HUD bombe (+1) ; chaînes / Brix nés de la tâche : linger Magix |

---

## 7. Ligne entrante (tous les 10 coups)

### 7.1 Preview (`refreshPendingBottomLinePreview`)

| | |
|---|---|
| **Déclencheur** | Dernier coup de la période (`% 10 == 9`, ou `% 5 == 4` en Five) ou attaque PvP |
| **Visuel** | 8 demi-cases masquées (crop 50 % bas) sous la grille |
| **Jitter** | cycle **0,85 s**, X ±1,6 / Y ±0,9 pt (sin/cos), sur la bande |
| **Respiration** | chaque case 1,0↔**1,08**, **0,21 s**/phase. Le nœud bande reste à l’origine scène (un scale dessus déformerait la ligne) |
| **Réduire les animations** | bande et son inchangés ; pas de jitter, pas de respiration |
| **Son** | `pendingRandomLineBloopa` (une fois par apparition) |

### 7.2 Injection (`addRandomLinePushingGridUp`)

| | |
|---|---|
| **Déclencheur** | `moveCount % 10 == 0` (Five : `% 5 == 0`) |
| **Anticipation** | le plateau monte de **2 pt** (0,05 s ease-out) puis revient (0,08 s ease-in). Les sprites, leur traîne et la fin d’injection attendent **0,08 s**. **Réduire les animations** : pas de montée, pas d’attente. L’action est retirée avant `drawGrid` |
| **Visuel** | 8 sprites montent depuis bas grille ; stretch proportionnel distance |
| **Vitesse** | ≈ 1280 pts/s (identique chute blox) |
| **Strip fade** | **0,15 s** dès le départ (pendant la montée du plateau) |
| **Son** | `line` + `hapticHeavy()` |
| **Bounce** | `playLandingBounce(for:)` par case, stagger **0,018 s**/colonne ; délai post-ligne = max bounce selon types présents |
| **Suite** | `resolveChains()` après durée bounce max + stagger |

---

## 8. Score et feedback points

### 8.1 Popup flottant `+N` (`spawnFloatingScorePopup`)

Look-and-feel **grille** : même recette dans tous les modes (Arcade, Zen, Défi, Duel, tuto, Magix, bonus colonne, bombe). Flag `ScorePopupFeedback.glyphShatterEnabled` (`false` = recette shrink + dots t0).

| Paramètre | Valeur |
|---|---|
| Font size | 62 pt Changa |
| z | 35 |
| Grow | 0,12→1,0 en **0,58 s** `easeOut` |
| Sortie | **Shatter** : le `+` et les chiffres deviennent les paillettes (plus de shrink) |
| Couleur | couleur de la chaîne (sinon `floatingScoreAccent`) |

### 8.2 Transfert points vers HUD (`ScorePopupFeedback`)

Le glyphe **est** le transfert (plus de dots au t=0 autour du centroïde).

| Paramètre | Valeur |
|---|---|
| Dots | `clamp(points × 0,57, 14, 78)` — **1,5×** l’ancienne formule ; placement = pixels opaques du label |
| Mix taille | comme les cases : ~46 % grosses (r **2,0–3,5**) + micros r **1,5** |
| Répartition | par caractère ; le `+` a un plancher (2), chaque chiffre 1 |
| Dispersion | **0,08 s** `easeOut`, 6–16 pt depuis le centroïde du label |
| Vol vers score | **vitesse constante ~824 pt/s** (même que les paillettes de cases), `easeIn`, plancher **0,12 s** |
| Stagger départ | **0,14 s** (plus proche du HUD → part le premier) |
| Jitter cible | ±26 x, ±12 y pt |

`glyphShatterEnabled = false` : fade-in 0,06 + burst 22–46 pt + vol 0,20 (arrivée **0,34 s**), shrink+fade **0,33 s**.

### 8.3 Rolling counter score

| Paramètre | Valeur |
|---|---|
| Début | arrivée de la **première** paillette (cases **ou** shards du `+N`) |
| Fin | arrivée de la **dernière** paillette (même fenêtre) |
| Durée | `max(0,12, last − first + 0,08)` — plus de 0,40–0,60 s après que tout soit posé |
| Easing | **linéaire** si fenêtre paillettes ; ease-out cubique sinon |
| Flash couleur | lerp couleur chaîne → blanc en **0,30 s** après roll |
| Pulse scale | pic `1,2 + chainLevel×0,03` (max ~1,38), montée **0,33 s**, retour **0,11 s** |

### 8.4 Milestones

| Palier | Particules | Distance |
|---|---|---|
| Centaine (100…) | 22 dots blancs | 28–130 pt, 0,35–0,65 s |
| Millier (1000…) | 220 dots multicolores | 56–260 pt (2× distance) |

### 8.4b Jauge 0→N°1 — sillage, prochain gris, passage de rang

Sillage : `SKCropNode` `hudScoreRaceWake` — gouttière **3 pt** de 0 au curseur, **même shader peau** que le wordmark BLOMIX (`timeOffset` 0,08). Fenêtre qui s’ouvre sur la matière du titre (le fill reste largeur de grille). Ligne grise non parcourue : **1 pt**. Points gris déjà dépassés **masqués** (plus de voile sous les dots).

Prochain gris (`min` des `grayScores` strictement > live) : rose `#FF5A9A`, rayon **2,4**. Les autres encore devant : ticks **1×4 pt** centrés sur la ligne, opaque (Sombre blanc **0,48** / `#7A7A7A` ; Clair blanc **0,36** / `#5C5C5C`). Déjà dépassés : masqués. Pas de respiration. RECORD vert et N°1 jaune inchangés.

Quand le rang logique change (on dépasse un autre score de la ligne figée) :

**Chiffre de place** (plus de `+1` flottant) : gonflement **×1,22** en **0,10 s** easeOut, hold **0,08 s**, retour **0,16 s** easeIn. En parallèle, le label défile **±1** toutes les **0,06 s** jusqu’à la cible (un saut de 3 places = 50→49→48→47). Si la cible recule encore pendant le défilement, on enchaîne sans relancer le burst. Couleur du chiffre inchangée (losange / vert / jaune).

**Paillettes** (une fois par vague, au curseur) : **12** dots (2/3 rose, 1/3 chrome `primaryTextSK`), r **0,7–1,35**, expulsion radiale **10–18 pt**, **0,26 s** easeOut, fade dès 0,03 s, z 20.

Pas de son. Premier layout : pas de burst ni de tick. Échelle de la ligne **linéaire** (0 → N°1 figé).

### 8.5 Colonne vidée (`awardFullyClearedColumnBonuses`)

- Stagger **0,09 s**/colonne (gauche→droite)
- Son : `emptyColumnClear`
- Score : +10 pts/colonne

### 8.6 Feedback qualité coup (`showMoveQualityFeedback`)

*Désactivé* (`realtimeFeedbackEnabled = false`). Si activé :
- `!!` vert, `?` orange-rouge, font 22 pt, montée 22 pt en 0,55 s

### 8.7 Hint ghost

*Retiré en v6.1* (bouton et ghost). L’analyse alimente uniquement le récap / pire coup.

---

## 9. Game Over

### 9.1 Pré-animation focus (`playGameOverFocusAnimation`)

| | |
|---|---|
| **Déclencheur** | Colonne pleine, point focal fourni |
| **Durée totale** | **1,38 s** |
| **Shake** | intensity **2,5**. **Réduire les animations** : pas de shake ici (les autres shakes du jeu restent) |
| **Plateau** | voile noir α **0,46** sur la grille (fondu **0,28 s**, z 12, sous le cadre z 50). La case du focus passe à z **30** et reste en couleur. Les `junction_*` qui ne la touchent pas sont retirés (le coup précédent les laisse souvent à z ≥ 12, une fonte les passe à z 25 : les diagonales dépassent alors du voile). Celles de la case focus passent à z **29**. Le pont CONNECT encore en file est retiré. **Réduire les animations** : fondu **0,01 s**. Pas de focus (pas de point) : pas de voile |
| **Ondes** | 4 anneaux, stagger **0,12 s**, rayon 2,1×cellule → scale 0,18, **0,34 s** |
| **Titre** | fade in + grow 20→40 pt, hold **0,18 s** |
| **Son** | `end` (déclenché avant overlay) |

### 9.2 Overlay (`presentGameOverOverlay`)

| Élément | Paramètre |
|---|---|
| Fond dim | Sombre : noir α **0,72** ; Clair : beige scène `#F5EEDF` α **0,94** |
| Score, citation, boutons | fade séquentiel |
| Blocs ambiants | spawn continu (voir §11) |
| Victoire PvP | `victory` |

### 9.3 Voile record / top 3 (`buildCelebrationOverlay`)

Au-dessus du game over (z 250). Même voile et mêmes textes de thème que §9.2. **OK** retire le voile et les paillettes.

| | |
|---|---|
| **Déclencheur** | Record personnel, ou ce score dans le top 3 (mondial Arcade / Zen / Five ; rang du jour en Défi). Un seul voile si les deux. |
| **Titre** | Place (**40 pt**, couleur skin, pop 0,2→1 en **0,40 s**) ou **Record personnel !** (**32 pt**) |
| **Légende** | **Record personnel** sous la place, seulement si les deux motifs |
| **Rang** | « classé #N » si record hors top 3, ou sous une place de Défi |
| **Arrivée** | fade du voile **0,20 s** |
| **Paillettes** | grains ronds, 6 couleurs du skin, burst continu jusqu’à OK. z sous le texte |
| **Feux** | à l’ouverture seulement : **3** éclatements, départs au hasard sur **1 s**, centres dans la **moitié haute**. Chacun : **200** paillettes skin, côté **3,2…6,8 pt**, disque de diamètre **1/3** de la hauteur en **0,60 s** (ease-out), puis pluie **2,1…3,1 s** (ease-in, −80…170 pt) : opaques la première moitié, fade-out sur la seconde |

---

## 10. Transitions et stages

### 10.1 Overlay transition (`showTransitionOverlay` / préparation PvP)

Pipeline unique pour **stage solo**, **intro Zen**, **tutoriel** (intro / fin) et **préparation PvP** : sticker orange + contour thématisé, **sans halo**, **sans voile**.

#### Rendu texte (toutes variantes)

| | |
|---|---|
| **Fond** | **Aucun** voile — jeu visible derrière |
| **Typo** | Police joueur (`BlomixTypography`) |
| **Rendu texte** | **Orange skin** (identique Sombre/Clair) + **contour** thématisé (`transitionOutlineColor`) — un seul `SKLabelNode` par ligne, sans rasterisation, **sans halo** |
| **Contour** | Épaisseur : ≥ 60 pt → **5 px** ; 30–59 pt → **3,5 px** ; &lt; 30 pt → **2,5 px**. Couleur : **blanc** (Sombre) / **gris foncé** (Clair) |
| **Son** | `transition` (stage / Zen / tuto via `showTransitionOverlay` ; pas dans le path connecting PvP) |

#### Arcade / Défi — slam (`isInStagedSoloMode`)

Stage 1 **conservé** (démarrage) + chaque palier. Copy glyphe, identique au badge HUD.

| | |
|---|---|
| **Titre** | `L1`…`L5` / `L★` (Ultime) — **92 pt** |
| **Stats** | une ligne `16s · ×2` (`stage.overlay.stats_format`) — **28 pt** |
| **Slam** | Scale **×2,4 → ×0,90** en **0,20 s** (`easeIn`), settle **×1,0** en **0,12 s** (`easeOut`) |
| **Impact** | `shakeScreen(2,3)` + `hapticHeavy` + burst (14 dots orange + 4 étoiles 4 branches) |
| **Stats** | tick après l’impact (**0,18 s**, 0 → ×1,08 → ×1) |
| **Pause** | **0,50 s** |
| **Fade out** | **0,32 s** |
| **Durée `isProcessing`** | ~**1,14 s** (0,32 + 0,50 + 0,32) |

#### Zen / tutoriel — pop poli

| | |
|---|---|
| **Pop-in** | Scale **0 → ×1,14 → ×0,94 → ×1,0** en **0,45 s** ; stagger **0,07 s** entre blocs de texte |
| **Pause** | **1,0 s** |
| **Fade out** | **0,35 s** |

#### Layouts

| Variante | Tailles | Structure |
|---|---|---|
| Arcade / Défi | titre **92 pt**, stats **28 pt** | `L1`…`L★` slam + 1 ligne |
| Zen | préfixe **34 pt**, titre **76 pt**, infos **26 pt** | Header groupé + 0–2 lignes, pop poli |
| Tutoriel | titre **48 pt**, sous-titre **26 pt** | 2 lignes pop-in (stagger) |
| PvP prep | titre **72 pt**, phrases **22 pt** | « Duel » + rotation l10n |

Implémentation : `makeTransitionPopInOutlinedLabel` / `makeTransitionSlamAction` / `setTransitionPopInOutlinedLabelText` dans `GameScene.swift`.

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

### 10.3 Badge LX (`hudStageBadge`)

Visible pendant tout l’overlay de stage (plus de hide). Horloge **slam** §10.1 Arcade (`StageOverlayTiming.slam*`).

| Phase overlay | Badge |
|---|---|
| Slam **0,20 s** | Scale **1,0 → 2,0** (`easeOut`), ancien chiffre |
| Impact | Texte → `L2`… / `L★` |
| Settle + pause **0,62 s** | Tient ×2 |
| Fade **0,32 s** | Scale **2,0 → 1,0** (`easeIn`) |

Stage 1 : `L1` déjà affiché, grow/settle sans swap. Pas de pulse après l’overlay. Couleur = `primaryTextSK` (rafraîchie).

---

## 11. UI et ambiance

### 11.1 Écran d'accueil

**Layout (haut → bas)**

| Zone | Contenu |
|---|---|
| Liens utilitaires | Rangée d’icônes SF en haut (Réglages, Tutoriel, thème, Partager, Crédits) |
| Carte joueur | Nom GC, 4 disques ARC. / MOY. / ZEN / DUEL |
| Branding | `BLOMIX` + tagline, de préférence **50 %** hauteur (clampé entre rangs et hero) |
| Zone de jeu | Bouton hero **Arcade** pleine largeur, puis **Duel** et **Zen** côte à côte |
| Tip | Ancré en bas (`10 %` hauteur) |

**Interactions**

- Disque → `LeaderboardViewController` (onglet Arc. / Moy. / Zen / Duel)
- Icônes → Réglages / Tutoriel (partie guidée) / thème / Partager / **Salon** / Crédits (`BlomixCreditsViewController`)

| Effet | Paramètres |
|---|---|
| Tips rotation | toutes les **5 s**, fade swap texte |
| Titre accueil (cold launch) | **~2,0 s** poinçon L→R : 0,20 s vide, B puis L à cadence régulière (~0,26 s), ensuite O-M-I-X légèrement accélérés (dernier impact inchangé ≈ 1,30 s). Squash **1,18 / 0,86**, settle 0,16 s easeOut. Son `place` + paillettes (14 éjections + 32 poussières, couleur blox du skin) à chaque impact. À `punchIntroChromeDelay` ≈ 1,58 s : tagline, hero (+0,08 s) et blox ambiants. Tenue **0,85 s**, puis le tableau. Retours ☰ / GO : hero d’abord (0,04 s), entrée courte, disques déjà visibles. |
| Wordmark BLOMIX | accueil **60 pt** / jeu 36 pt ; puits clipé sur Changa One |
| Boutons jeu | cold launch : hero avec le mot ; après la tenue, Défi +0,22 / +0,30 s, Duel / Zen / Five +0,40 / +0,48 / +0,56 s. Retour : hero 0,04 s, Défi 0,16 / 0,22, modes 0,28 / 0,34 / 0,40. Slide **14 pt**, scale 0→1,15→1, fade **0,12 s**. **Réduire les animations** : fondu 0,01 s, échelle 1, pas de slide |
| Disques et icônes | cold launch, après la tenue : disques stagger **0,07 s**, icônes **0,05 s**, fondu 0,20 s, scale 0,94→1. Retour : icônes dès 0,18 s ; disques inchangés. **Réduire les animations** : fondu 0,01 s ensemble, sans scale |
| Pastilles rang | chiffre (sans `#`, ×2) + libellé 3 lettres en **trou gouttière** (comme BLOMIX) ; cliquable ; chiffres **après** les 7 fetches, stagger L→R **0,07 s** (fade 0,16 s + scale 0,82→1, 0,18 s) — indépendant de l’entrée des disques |
| Blocs ambiants | démarrent avec le mot (voir §11.3) |
| Toast trophée | au **palier** (pas au retour accueil). Anneau + point (orange skin) + libellé Nunito, pas un chip chrome. Y = `height − safeTop − 92`, z **220**. Fade 0,22 / 3,6 / 0,28. Anneau scale 0,65→1 à l’entrée. **Réduire les animations** : fondu seul. Tap → Salon |
| Nouveautés / sondage | cold launch : après la tenue + 0,85 s (Nouveautés) et + 1,05 s (sondage), pour ne pas couvrir l’entrée. Retour : sondage 0,55 s, toujours bloqué si Nouveautés doit passer |

**Bouton Solo hero** (même puits que Duel/Zen ; se distingue par la taille)

| Propriété | Valeur |
|---|---|
| Empreinte | pleine largeur, hauteur × 1,22 vs secondaires |
| Puits | dégradé skin (`BlomixSkinGradient`) |
| Capsule | chrome `chipFill` |
| Texte | Changa One, ~12 % plus grand que Duel/Zen — **nom du mode** (`Arcade` / `Zen` / `Défi du jour`) |
| Caption save | Nunito 9 pt **Continuer** sous le titre (Arcade, Zen, Défi). Sans save : pas de caption |

### 11.2 Boutons (`BlomixSKButtonNode` / `BlomixUIButton`)

Puits (dégradé skin, `wellTimeScale` 0,035) immobile. Capsule chrome seule animée. Gouttière 6 pt (4 pt compact). Liseré haut + ombre bas sur la capsule ; ombre sous le rebord du puits et ombre de contact sous la capsule (alpha réduite à l’appui). Son `connectE`. Police Changa One.

Ombre de contact (`BlomixButtonRelief`) : Sombre **0,32** (appui **0,10**). Clair **0,11** (appui **0,04**). Décalage Y **2,5** pt. Le thème chrome ne change pas les skins.

| Phase | Durée | Détail |
|---|---|---|
| Press | `pressAnimDuration` (0,07 s) | capsule scale **0,90** (le puits ne bouge pas) |
| Release phase 1 | `releasePhase1Duration` (0,09 s) | capsule scale **1,04** |
| Settle | `releasePhase2Duration` (0,07 s) | scale 1,0 |
| UIKit | ressort | `CASpringAnimation` sur capsule + titre, pas sur le puits |

### 11.3 Blocs ambiants (`BlomixAmbientBlocksView` + SpriteKit)

- SpriteKit (accueil, Game Over) et UIKit (réglages, classements, lobby PvP, …)
- Montée bas → haut, courbe linéaire ; **pas** de rotation ni rebond
- Forme : carré plein (UIKit aligné SK : sans coins / bordure)
- Taille aléatoire **9…18** pt ; pas de plafond de présence
- z 0,5 SK (entre fond et contenu) ; UIKit en `insertSubview` index 0

**Accueil SK (hybride gouttières)** — `gutterReveal`

| | |
|---|---|
| Plaque | fantômes alpha **0,20** |
| Puits / wordmark / rangs | copie carrée clipée dans `blomixWell` / `blomixWordmarkWell`, alpha **0,90**, z **0,5** (entre fill et lèvre) |
| Spawn | **0,45…1,3** s |
| Vitesse | multi **1/3…1,6×** |
| Autres écrans | même fantôme α **0,20** ; pas de copies gouttière. Spawn SK `0…1` s, multi **1/3…3×** ; UIKit densité low/high inchangée |

### 11.4 Compteur LIGNE x/10

| Valeur | Couleur | Effet |
|---|---|---|
| 0–5 | gris `#A3A3A3` | — |
| 6–8 | orange `#F4A261` | — |
| 9–10 | rouge | shake ±**1** pt, cycle 0,05 s. **Réduire les animations** : le rouge reste, le shake non |

Five (période 5) : gris 0–2, orange 3, rouge 4–5. Le shake est sur le dernier cran (4/5), même amplitude.

### 11.5 Pile d’attaque Duel (`hudAttackPile`)

Indicateur **HUD uniquement** (Duel). À **droite du gros score** (écart 8 pt, largeur calée sur « 50 »). Arcade / Zen : absent.

| | |
|---|---|
| **Déclencheur** | Arrivée des `+N` (`applyDisplayedScoreIncrement`) — **même horloge** que le chiffre |
| **Visuel** | Puits **hauteur fixe** ; gouttière peau (`BlomixSkinGradient`, même matière que BLOMIX) clipée depuis le bas (`SKCropNode` masque, pas `yScale` du fill) |
| **Largeur** | ≈ un digit du gros score (`"0"` en Changa 52) ; pulse `xScale` **1,20** pendant le fill ; tick à chaque palier de 10 |
| **Couleur fill** | Shader peau (pas chrome Sombre/Clair). Flash couleur des `+N` : **chiffre seulement** |
| **Envoi** | Roll chiffre+barre → **50** en **0,22 s**, puis reste (ex. +80 → 50 puis 30) |
| **Réf. code** | `applyDuelHudMeter` / `applyAttackPileMeter` |

### 11.6 Modaux, planche Clair, air de gravité

**Modaux qui montent** (`RiseModalTransition`, `presentFullScreenModal`)

Salon, scores, réglages, guide, crédits, sondage, hub Défi. Depuis le bas, **0,25 s** easeOut ; sortie vers le bas, **0,25 s** easeIn. `.overFullScreen` : l’animateur ajoute la vue. **Réduire les animations** : **0,01 s**. Lobby PvP, Game Center et feuille de partage restent en fondu.

**Cases vides, thème Clair**

| | Sombre | Clair |
|---|---|---|
| Trou | blanc 0,12 | `#F0E6D2` |
| Barre haute | aucune | **2 pt** `#E4D8C2`, ancre en haut, z 0,2, **grille principale seulement** |
| Surbrillance visée | inchangée | `#E6DCC8` |

File upcoming, file d’attente et autres fonds vides prennent le trou plus chaud, sans la barre.

**Air de gravité** (`syncGravityAir`, préfixe `gravityAirGrain`)

En partie seulement. Enfants du conteneur de grille, z **0,4** (sur le trou, sous les blox z 1). Max **6** (avant 4). Spawn **1,1…2,2 s** (avant 1,6…3,2). Trajet bas → haut **4,5…7,5 s**, côté **2,2…3,6** pt, alpha **0,18…0,32**, couleur skin. Densité moyenne environ **3,5** grains au lieu de **2,5**. Ils ne scorent pas et ne sont pas retirés par `drawGrid`. Un grain sans action de montée (SCRUMBLX vide les actions de la grille ; retour au premier plan) repart, ou revient en bas s’il est déjà sorti. Accueil, fin de partie, **Réduire les animations** : rien.

---

## 12. Haptique et screen shake

**Core Haptics** (`FeelHaptic`, `CHHapticEngine`) pour la matière des coups. Si le téléphone n’a pas de Taptic Engine, repli `UIImpact` (pas le vocabulaire bombe / ligne). **Réduire les animations** ne coupe pas ces retours.

| Moment | Transient (intensité, netteté) | Repli |
|---|---|---|
| Pose isolée, Brix | 0,32 / 0,20 | `.light` 0,40 |
| Groupe de 2 | 0,42 / 0,36 | `.light` 0,55 |
| Groupe de 3 | 0,55 / 0,50 | `.medium` 0,50 |
| Groupe de 4 | 0,70 / 0,66 | `.medium` 0,75 |
| Magix | 0,60 / 0,55 | `.medium` 0,65 |
| Colonne pleine, une autre libre | 0,36 / 0,06 (sourd) | `.light` 0,35 |
| Début de chaîne | deux coups, 0 et 0,04 s : 0,48/0,40 puis 0,82/0,78 | deux `.light` |

| Fonction | Style UIKit | Usage inchangé |
|---|---|---|
| `hapticSoft()` | `.medium` | Démarrage, auto-drop |
| `hapticHeavy()` | `.heavy` | Bombe, ligne entrante, slam de stage, game over, défi reçu |

**Screen shake** (`shakeScreen`) :
- `CAKeyframeAnimation` position.x, durée **0,14 s**
- Valeurs : `[0, v, −v, 0,55v, −0,55v, 0,2v, −0,2v, 0]`
- Intensités courantes : cascade vague 2 **1,4**, vague 3+ **2,0** (au début de la dissolution), bombe/GO **2,5**

---

## Annexe — Enums de constantes (référence rapide)

```
LandingBounce          squash 0,09 | stretch 0,03 | settle 0,03
FlightStretch          x 0,82 | y 1,25
BrixLandingBounce      squash 0,07 | stretch 0,025 | settle 0,025
MagixLandingBurst      40–48 dots palette | r 1,0–1,8 | +24–52 pt | 0,34 s easeInEaseOut
Magix consume / morph  18–24 dots +12–28 pt / 0,22 s ; fade 0,18 ; mue pulse ×1,18
BrixFlightStretch      x 0,88 | y 1,16
BrixVanishFeedback     pop 0,07 + implode 0,13 | carrés 11–15 + 15 micro → score ~824 pt/s | 3 étoiles présence 0,64 s
CompactRiseAnimation   duration 0,20 | stagger 0,018 / col (budget 0,06, vol min 0,14)
NeighborNudge          pose 2 pt | compact 1 pt | 0,04 + 0,06 s | 8 voisins | même couleur vers l’arrivée, le reste loin | pas le sprite qui bounce
FeelHaptic             place / connect 2–4 / magix / refus / chaîne 2× à 40 ms
Reduce Motion          voisin + jitter/respiration de ligne + montée 2 pt + shake cascade/GO + slide/scale accueil + montée modale + grains + scale toast + tour de vol coupés | pose, chaîne, score, haptiques, rouge LIGNE, bande, anneaux GO gardés
FlightSpin             1 tour ±2π sur riseDuration | easeOut | Magix toujours | appui long ghost | pas tap court ni timer ≤ 2 s
StartScreenEntrance    tenue hero 0,85 | disques 0,07 | icônes 0,05 | hero cold t+0,08 | retour hero 0,04
RiseModalTransition    0,25 s montée easeOut / descente easeIn | Réduire les animations 0,01
GravityAir             max 6 | spawn 1,1–2,2 s | trajet 4,5–7,5 s | côté 2,2–3,6 | α 0,18–0,32 | z 0,4 | grain sans action relancé
ChainClearFeedback     dissolve 0,20+0,16+0,14 | stagger 0,04 / 0,028 / 0,020 | grains 2,0–3,5 / 2,6–4,4 / 3,2–5,2 | shake 1,4 puis 2,0 | sparkles → score ~820 pt/s | cascade 0,07
ChainCommentaryPopup   delay 0,72 | 40 pt | scale 0,55→1 en 0,36 | shrink 0,82 + fade 0,28 | pas de vol HUD
BrixLandingSparkles    éjection 6–8 carrés 1,5–2,5 pt (pose / compact) ; poudre ronde inchangée
PendingLinePreview     jitter X 1,6 Y 0,9 | cycle 0,85 | breath 1,08 / 0,21 s
IncomingLinePush       plateau +2 pt | 0,05 + 0,08 s | sprites attendent 0,08 s
ScorePopupFeedback     grow 0,58 + shatter burst 6–16 pt / 0,08 + vol ~824 pt/s + stagger 0,14 | dots 14–78 (×1,5) mix cases
GameOverFocus          total 1,38 | rings 4 | stagger 0,12 | voile α 0,46 | case fatale z 30
BombExplosionFeedback  shock 0,52×5 | flash 0,15 | block stagger 0,02
ghostHoldDelay         0,12
```

---

*Ce document doit être mis à jour à chaque modification des enums `*Feedback`, des sons `BlomixMatchSFX`, ou des effets Magix dans `GameScene.swift`.*
