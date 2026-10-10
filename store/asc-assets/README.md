# Captures App Store (inbox)

Déposer ici les **fichiers bruts** (n’importe quelle taille / format). L’agent les recadre et les exporte pour App Store Connect. **Pas dans git** (`inbox/` et `out/` sont gitignorés).

Dossier d’arrivée : `store/asc-assets/inbox/`  
Export prêt à uploader : `store/asc-assets/out/`

BLOMIX = **iPhone portrait seulement** (pas d’iPad). Fastlane **ne pousse pas** les captures (`skip_screenshots: true`) : upload **manuel** dans ASC, fiche **7.5**.

## Upload 7.5 (quand la version ASC 7.5 existe)

Les PNG sont dans `out/` (gitignoré). **Ne pas** les coller dans le slot Watch.

### Français (locale par défaut, souvent « French »)

1. ASC → l’app BLOMIX → version **7.5** → onglet **iPhone**.
2. Slot **6.9"** (en premier si proposé) : coller **dans cet ordre** depuis `out/iphone-6.9/` :
   1. `01-chaines.png`
   2. `02-brix-magix.png`
   3. `03-modes.png`
   4. `04-gratuit.png`
3. Slot **6.5"** : les **mêmes 4**, même ordre, depuis `out/iphone-6.5/`.
4. Laisser l’**App Preview** vidéo actuelle (look & feel). Ne pas remplacer par ces PNG.
5. Ne **pas** remettre `01-accueil.png` / `02-reglages.png` en tête.

### English (U.S.)

1. Sélecteur de langue ASC → **English (U.S.)** (pas UK).
2. Même ordre, fichiers dans `out/en-US/iphone-6.9/` puis `out/en-US/iphone-6.5/`.
3. DE / ES / IT / PT : peuvent hériter du FR (PT : de l’EN si plus lisible) tant qu’on n’a pas d’overlays dédiés.

Si tu colles un 6.9" dans le slot 6.5" (ou l’inverse), Apple refuse. PNG sRGB, **sans** transparence.

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
