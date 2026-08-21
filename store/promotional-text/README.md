# Texte promotionnel App Store

Source de vérité du champ **Texte promotionnel** (Promotional Text) d’App Store Connect.

- **Pas dans le bundle**, **pas dans `whats-new/`** (ce dossier est réécrit à chaque version).
- Limite Apple : **170** caractères / langue (compter les espaces).
- Modifiable dans ASC **sans** nouvelle version ; chez BLOMIX on le traite comme **figé**.
- À la création d’une version : Fastlane re-pousse ces fichiers (`metadata` / `release`) si ASC les a vidés. **Ne pas** les régénérer avec le CHANGELOG.

## Locales

| Fichier | App Store Connect |
|---|---|
| `en-US.txt` | English (U.S.) |
| `fr-FR.txt` | French |
| `de-DE.txt` | German |
| `es-ES.txt` | Spanish (Spain) |
| `it-IT.txt` | Italian |

Les `.txt` sont le texte **exact** collé dans ASC (une ligne ou deux, sans titre de fichier).
