# BLOMIX 6.7 — Spec (chrome tactile)

> **Statut** : livré (soumission 6.7)  
> **Cible** : marketing **6.7**, build **127**  
> **Date** : septembre 2026  
> **Règles de jeu** : inchangées.

Cahier du chantier **puits + capsule**, wordmark trou, Magix ronds.

---

## 1. Objectif

Remplacer les chips plats (fill gris + hairline + ombre) par des objets en **creux coloré** (dégradé du skin joueur), sans changer les flux, hit-tests, libellés ni le gameplay.

## 2. Grammaire

1. **Table** — fond de scène (Sombre / Clair), inchangé.
2. **Puits** — creux arrondi, plancher = dégradé vivant de la palette blox (`BlomixSkinGradient`, `u_time * 0.035`, plus lent que Magix 0,09). Ne bouge pas à l’appui.
3. **Capsule** — chrome (`chipFill` / `chipTitle`), inset **6 pt** (4 pt si min(côté) < 48). Texte **Changa One**. Liseré lumineux haut + ombre bas. Le puits a une ombre sous le rebord haut et une ombre de contact sous la capsule.

Appui : seule la capsule scale à **0,90**, puis retour avec overshoot **1,04**. Son `connectE`. Haptique `.light`.

## 3. Périmètre

- Accueil : Arcade / Continuer / Découvrir, Duel, Zen, rangée d’icônes
- Menu ☰ + items
- Game Over, quit, skip tuto
- UIKit : `BlomixUIButton` (crédits, guide, classements, lobby / résultat Duel, dialogues, WhatsNew)

## 4. Hors scope

- Pastilles de rang accueil : **faites** (rondes, même charte boutons, sans halo/respiration)
- Grille, blox, Magix, HUD, save, PvP filaire
- Lien texte **Nouvelle partie**
- Conseil du jour / bannière MAJ

## 5. Constantes

| | |
|---|---|
| Radius puits | 14 pt |
| Gouttière | 6 pt (4 pt compact) |
| Press scale | 0,90 |
| Overshoot | 1,04 |
| Police boutons | Changa One (`BlomixTypography.display`) |
| Shader | `BlomixSkinGradient.wellTimeScale` = 0,035 |

## 6. Implémentation

- `BlomixSkinGradient.swift` — shader SK + bitmap UIKit partagé
- `BlomixSKButtonNode` — puits `SKCropNode` + capsule
- `BlomixUIButton` — `BlomixSkinGradientLayer` + `capsuleView`
- Plus d’`applyHeroAccent` visuel (hero = taille seule)
