# Nouveautés App Store (« What’s New »)

Source de vérité du champ **Nouveautés** d’App Store Connect. **Pas dans le bundle** : Apple ne lit jamais ce texte depuis l’IPA.

**Mode de travail** : à chaque version marketing, rédiger et traduire les **5** fichiers **dans le même lot** que `DOCS/CHANGELOG.md`. L’humain copie-colle ensuite dans ASC (le champ est vide à la création de version ; description et captures sont recopiées).

Limite Apple : **4000** caractères / langue. Puces courtes, bénéfice joueur — pas le changelog interne. Noms Magix **non traduits**. Même ordre et même nombre de puces dans les 5 fichiers.

Si un lot change encore le bénéfice joueur de **cette** version : rafraîchir les 5 fichiers tout de suite.

## Locales ASC ↔ langues BLOMIX

| Fichier | App Store Connect | `lproj` |
|---|---|---|
| `en-US.txt` | English (U.S.) | `en` |
| `fr-FR.txt` | French | `fr` |
| `de-DE.txt` | German | `de` |
| `es-ES.txt` | Spanish (Spain) | `es` |
| `it-IT.txt` | Italian | `it` |

## Release (humain)

1. Vérifier que les 5 fichiers correspondent à `MARKETING_VERSION`.
2. Créer la version dans App Store Connect.
3. Coller chaque `.txt` dans la locale correspondante.
4. Uploader le build comme d’habitude.

Procédure agents / l10n : `DOCS/LOCALIZATION.md`, `AGENTS.md` (volet 2b).

Le **texte promotionnel** (stable, 170 car.) n’est **pas** ici : voir `store/promotional-text/`.
