# BLOMIX — Pistes de modes

> **Version de référence** : 7.1 (local)  
> Recueil **2026-09**. Pistes de design, pas des règles. **Graine du jour** est passée en code : [DAILY_CHALLENGE.md](DAILY_CHALLENGE.md).  
> Magix (blocs) : [MAGIX.md](MAGIX.md). Règles en jeu : [RULES.md](RULES.md).

Noms de modes ici = **étiquettes de design**, pas des libellés magasin.

---

## Ce que les 3 modes occupent déjà

Même moteur : grille 8×8, gravité **vers le haut**, chaînes ≥ 5 en 8-connexité, Brix, bombes, ligne tous les 10 coups, juice / skins.

| Mode | Pression | Victoire / fin | Social | Magix |
|---|---|---|---|---|
| **Zen** | Aucune (pas de timer, pas de stages) | Game over (plus de place) ; score | Classement | Oui |
| **Arcade** | Timer + stages ×1…×6 + bombe qui grandit | Idem + rythme | Classement | Oui |
| **Duel** | Timer 10 s + **l’autre** (lignes à 50 pts) | L’un des deux top-out | 1v1, Elo, série | Non |

Le trou : un 4ᵉ mode qui n’est **ni** « Zen plus calme », **ni** « Arcade plus vite », **ni** « un autre 1v1 ». Idéalement il change **l’objectif** ou **le contrat**, pas la physique.

Hors piste (déjà écarté) : film / replay Duel (trop cher, deux grilles).

---

## Invariants à garder

- Pose, compactage haut, chaînes, Brix, bombes, file à 3, ligne des 10.
- Chrome Sombre/Clair + skins blox.
- Juice existant (atterrissage, dissolution, injection). Pas un nouveau moteur visuel.
- Magix **si solo** (comme aujourd’hui : jamais en Duel, jamais dans la ligne du bas) — sauf si le mode dit explicitement le contraire.

---

## Pistes (4ᵉ mode)

### 1. Contrats — « réussir » plutôt que « durer »

Une partie a un **objectif** et se **gagne** : vider la grille, chaîne ≥ 8, 3 couleurs en une cascade, survivre N coups, poser M Brix sans game over.

- **Nouveau :** fin positive (pas seulement le top-out).
- **Moteur :** compteurs déjà là (chaînes, vide +500, `moveCount`).
- **Magix :** SAINTX / COLORX deviennent des **outils de contrat**, pas seulement du chaos.
- **Risque :** se transformer en liste de quêtes. Une famille d’objectifs, une UI simple.
- **Effort :** moyen (HUD d’objectif + conditions de victoire). Pas de réseau.

### 2. Graine du jour — le même puzzle pour tout le monde

**Piste retenue, codée en 7.1** : [DAILY_CHALLENGE.md](DAILY_CHALLENGE.md).

Même seed **file + Magix (kind) + lignes des 10**. **Accélération Arcade** (timer, stages, bombe). Auto-drop **libre** (colonne différente OK). Social sans fil Duel. GO simple + rang du jour + board GC des **victoires** cumulées.

### 3. Marée — la ligne est l’ennemie, pas le timer

Pression **sans** chrono Arcade : lignes plus fréquentes, preview plus longue, ou le joueur **choisit** une contrainte (colonne d’entrée, couleur taxée). Survival lisible.

- **Nouveau :** Arcade presse par le **temps** ; ici par le **bas**.
- **Moteur :** `addRandomLine` / preview 9/10 existent.
- **Magix :** **HALTX** (piste) brille ici ; BOMBX / SAINTX = soupape.
- **Risque :** trop proche d’Arcade si on remet un timer. Tenir : **pas de timer de coup**.
- **Effort :** bas–moyen (constantes + HUD).

### 4. Poche Magix — la chance devient un choix

Les Magix ne tombent plus dans la file. Toutes les N poses : **3 cartes**, tu en glisses **une** dans la file (ou tu passes). Draft.

- **Nouveau :** Arcade/Zen = Magix **subis** ; ici Magix **armés**.
- **Moteur :** file P0/P1/P2 + catalogue Magix. Overlay choix (même chrome que le ☰).
- **Magix :** tout le catalogue existant + pistes PACKX / MERGEX comme « cartes rares ».
- **Risque :** UI de plus ; équilibrage (PACKX trop fort en poche).
- **Effort :** moyen. Identité forte, zero réseau.

### 5. Duo — une grille, deux joueurs, un téléphone

Hotseat : on se passe le iPhone. Même plateau, même ligne des 10, scores séparés ou **équipe** (vider ensemble / survivre N coups).

- **Nouveau :** social **local** sans GKMatch ni attaques.
- **Moteur :** un `GameScene`, un flag « tour ». Pas de bande Duel.
- **Magix :** oui (c’est du solo à deux).
- **Risque :** « à qui la faute » si on joue compétitif sur la même grille. Mieux en **coop** (contrat partagé).
- **Effort :** bas si coop + overlay « à toi ». Le plus simple des sociaux.

### 6. Atelier — puzzles posés, pas une run infinie

Grilles **préparées** (ou graine + N coups). But : vider / atteindre un score en **K** poses. Magix dans la file comme outils.

- **Nouveau :** contenu éditorial, parties **courtes**, rejouables.
- **Moteur :** save de grille existe ; il manque un format « niveau » (grille + file + objectif + budget).
- **Magix :** PACKX / VOIDX / MERGEX = clés de puzzle.
- **Risque :** usine à contenu. Commencer par 10 graines + contrats, pas un éditeur joueur.
- **Effort :** moyen (format + 10 niveaux), puis lourd si on veut un pack.

---

## Variantes (pas un 4ᵉ mode)

À ne pas vendre comme un mode à part :

| Variante | Pourquoi ce n’est pas un mode |
|---|---|
| Palette à 4 couleurs | Option Zen/Arcade, change la densité |
| File à 5 visible | Aide / accessibilité |
| Sans Magix | Déjà le Duel ; en solo = mutateur |
| Bombe 3×3 partout | C’est Zen |

---

## Accroches Magix (rappel)

Les pistes **PACKX / FLIPX / MERGEX / HALTX / VOIDX** ([MAGIX.md](MAGIX.md)) restent des **blocs**. Un 4ᵉ mode peut les **mettre en scène** (Poche, Atelier, Marée) sans les ajouter tout de suite à la table de spawn Arcade (déjà 9 Magix).

---

## Comment en choisir un

| Si on veut… | Piste | Effort | Distingue de |
|---|---|---|---|
| Du social sans le fil Duel | **Graine du jour** ou **Duo** | bas–moyen | Duel |
| Une victoire claire | **Contrats** | moyen | Zen/Arcade (survie) |
| Une autre pression que le timer | **Marée** | bas–moyen | Arcade |
| Faire briller les Magix | **Poche Magix** | moyen | la chance actuelle |
| Des parties de 2 min | **Atelier** | moyen puis contenu | les runs infinies |

Les plus « BLOMIX » (même feel, nouveau contrat) : **Contrats**, **Graine du jour**, **Poche Magix**.  
Les plus cheap à prototyper : **Graine du jour**, **Duo** hotseat, **Marée** (constantes).

Prochaine étape humaine : en retenir **une** pour un proto 7.x, ou combiner (ex. Graine du jour **+** un contrat).
