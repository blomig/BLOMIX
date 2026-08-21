# Fastlane — BLOMIX

Pipeline local vers App Store Connect. Procédure complète : [`DOCS/DEVELOPMENT.md`](../DOCS/DEVELOPMENT.md) § Déploiement.

| Lane | Effet |
|---|---|
| `validate` | `store/` (5 langues) + entitlements Release = production |
| `metadata` | PATCH Nouveautés + texte promo **uniquement** |
| `beta` | Archive Release → TestFlight |
| `release` | Archive + binaire + textes — **pas** de review |
| `submit` | Envoi à la review (`automatic_release: false`) |

```bash
cp .env.example .env   # clé API hors git
bundle install
bundle exec fastlane validate
```

Ne pas lancer `fastlane deliver init` : ça dupliquerait la fiche magasin et risque d’écraser description / captures.
