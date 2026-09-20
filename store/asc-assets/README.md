# Captures App Store (inbox)

Déposer ici les **fichiers bruts** (n’importe quelle taille / format). L’agent les recadre et les exporte pour App Store Connect. **Pas dans git** (`inbox/` et `out/` sont gitignorés).

Dossier d’arrivée : `store/asc-assets/inbox/`  
Export prêt à uploader : `store/asc-assets/out/`

BLOMIX = **iPhone portrait seulement** (pas d’iPad). Fastlane **ne pousse pas** les captures (`skip_screenshots: true`) : upload manuel dans ASC, fiche **7.0**.

## Captures d’écran

ASC a **un slot par taille d’écran**. Coller un PNG 6.9" dans le slot 6.5" (ou l’inverse) = refus.

| Slot ASC | Pixels portrait | Dossier d’export |
|---|---|---|
| iPhone **6.5"** (souvent déjà rempli, en haut de la liste) | **1284 × 2778** (ou 1242 × 2688) | `out/iphone-6.5/` |
| iPhone **6.9"** (recommandé ; Apple scale le reste) | **1320 × 2868** (ou 1290 × 2796 / 1260 × 2736) | `out/iphone-6.9/` |

PNG, sRGB, **sans transparence**. 1 à 10 par slot. Une capture iPhone réelle (1170×2532, etc.) suffit : scale vers le pixel exact.

## App Preview (vidéo)

| | |
|---|---|
| Cible ASC | iPhone 6.5" **et** 6.9" |
| Pixels | **886 × 1920** portrait (accepté des deux côtés) |
| Durée | **15–30 s** |
| Codec | H.264, ≤ 30 fps, AAC stéréo si audio |
| Conteneur | `.mp4` / `.mov` |

Jusqu’à 3 previews. Enregistrer en portrait ; pas de mains / hors-jeu.

## Nommage dans `inbox/`

```
01-accueil.png
02-partie.png
03-magix.png
preview-1.mp4
```

Puis : « les fichiers sont dans inbox, tu peux formater ».
