# Métadonnées App Store Connect

Textes **hors bundle** : Apple ne les lit jamais dans l’IPA. Source de vérité git ; Fastlane les pousse (`bundle exec fastlane metadata` ou `release`). Ne pas recopier toute la fiche magasin dans `fastlane/metadata/`.

| Dossier | Champ ASC | Quand |
|---|---|---|
| [`whats-new/`](whats-new/) | Nouveautés (≤ 4000 car.) | **Chaque** version marketing — réécrire les 5 langues |
| [`promotional-text/`](promotional-text/) | Texte promotionnel (≤ **170** car.) | **Stable** — ne pas réécrire à chaque 6.x ; le re-pousser (ASC le vide souvent) |

Locales : `en-US`, `fr-FR`, `de-DE`, `es-ES`, `it-IT`.

Validation locale (sans clé API) : `ruby scripts/validate-store-metadata.rb` ou `bundle exec fastlane validate`. Procédure : `DOCS/DEVELOPMENT.md` § Déploiement.
