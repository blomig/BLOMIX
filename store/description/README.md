# Description App Store (hors bundle)

Champ ASC **Description** (≤ 4000 car.). **Pas** dans le bundle.

Les 5 locales historiques (FR/EN/DE/ES/IT) vivent déjà dans App Store Connect : Fastlane **ne les réécrit pas**.

| Fichier | Quand |
|---|---|
| `pt-BR.txt` | **Création** de la locale Portuguese (Brazil) — 8.4 |

Pour une **nouvelle** locale seulement : ajouter `store/description/<locale>.txt` (et éventuellement `store/keywords/<locale>.txt`). `generate_deliver_metadata!` n’écrit `description.txt` / `keywords.txt` que si le fichier existe.

Ne pas y coller les Nouveautés (`whats-new/`) ni le texte promo (`promotional-text/`).
