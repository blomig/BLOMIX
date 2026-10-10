# Métadonnées App Store Connect

Textes **hors bundle** : Apple ne les lit jamais dans l’IPA. Source de vérité git ; Fastlane les pousse (`bundle exec fastlane metadata` ou `release`). Ne pas recopier toute la fiche magasin dans `fastlane/metadata/`.

| Dossier | Champ ASC | Quand |
|---|---|---|
| [`whats-new/`](whats-new/) | Nouveautés (≤ 4000 car.) | **Chaque** version marketing — réécrire les 6 langues |
| [`promotional-text/`](promotional-text/) | Texte promotionnel (≤ **170** car.) | **Stable** — ne pas réécrire à chaque 6.x ; le re-pousser (ASC le vide souvent) |
| [`name/`](name/) | Nom de fiche (≤ **30** car.) | **7.5** — pas l’icône iPhone (`BLOMIX`) |
| [`subtitle/`](subtitle/) | Sous-titre (≤ **30** car.) | **7.5** — chaînes de 5 + gratuit sans pub |
| [`description/`](description/) | Description (≤ 4000 car.) | **Nouvelle locale seulement** (pt-BR en 8.4) — ne pas réécrire FR/EN/DE/ES/IT |
| [`keywords/`](keywords/) | Mots-clés (≤ 100 car.) | Idem, nouvelle locale seulement |
| [`asc-assets/`](asc-assets/) | Captures (inbox → out) | Upload **manuel** ASC ; Fastlane `skip_screenshots: true` |

Locales : `en-US`, `fr-FR`, `de-DE`, `es-ES`, `it-IT`, `pt-BR`.

Validation locale (sans clé API) : `ruby scripts/validate-store-metadata.rb` ou `bundle exec fastlane validate`. Procédure : `DOCS/DEVELOPMENT.md` § Déploiement.
