# Télémétrie anonyme (8.9)

Mesure locale + CloudKit, sans SDK tiers et sans IDFA. Le code est `BlomixTelemetry.swift`. Tant que le type n’est pas déployé dans la console, l’envoi échoue en silence : la file reste sur l’appareil, la partie ne change pas.

La Watch n’envoie rien. Seule l’app iPhone mesure.

## Pourquoi la base publique

La base **privée** n’est lisible que par le joueur. Le tableau de bord ne montre pas les records privés des autres comptes : Lomig ne pourrait pas en tirer une courbe. Les events partent donc dans la base **publique** du conteneur déjà utilisé (`iCloud.blomig.BLOMIX`), type **distinct** du sondage `PlayerSurvey`.

CloudKit ajoute tout seul le champ créateur (compte iCloud). Le développeur peut donc rattacher un lot à un utilisateur iCloud, même si l’app n’écrit ni nom, ni e-mail, ni identifiant Game Center. L’étiquette App Store doit le dire.

## Ce qui part

Identifiant : UUID aléatoire, clé `blomix_telemetry_install_id`. Créé une fois sur l’appareil. Pas l’IDFA. Pas le `gamePlayerID`.

| `kind` | Quand | Champs |
|---|---|---|
| `first_launch` | Une fois, au premier passage au premier plan après l’installation de cette mesure | — |
| `session_start` | Chaque retour au premier plan (`sceneDidEnterBackground` rouvre le compteur) | — |
| `game_end` | Fin Arcade, Zen, Five, Défi, tutoriel (`triggerGameOver`) ou Duel (écran de résultat) | `mode`, `durationSec` si le début a été vu |
| `daily_played` | **Nouvelle** partie de défi (pas la reprise) | `mode`, `day` (jour UTC de la graine) |

`mode` : `arcade`, `zen`, `five`, `daily_arcade`, `daily_five`, `duel`, `tutorial`.

La reprise d’une sauvegarde ne compte pas comme un début. Une fin sans début envoie `game_end` sans durée.

File locale `blomix_telemetry_queue_v1`, 200 événements max (les plus anciens sautent). Envoi par lots de 20. Succès : ces ids sortent de la file. Échec réseau : on réessaie plus tard. Autre erreur (schéma absent, compte refusé) : pause d’une heure, sans toucher au robinet public du Duel (`BlomixPublicCloudGate`). iCloud absent ou `accountStatus` différent de `.available` : on ne fait rien.

## Schéma à créer dans la console CloudKit

Conteneur : `iCloud.blomig.BLOMIX`. Base : **Public**. Type : `TelemetryBatch`.

| Champ | Type | Index |
|---|---|---|
| `installID` | String | Queryable (pour filtrer dans le tableau de bord) |
| `eventsJSON` | String | aucun |
| `appVersion` | String | Queryable, utile |
| `locale` | String | aucun |
| `sentAt` | Date/Time | Queryable, sortable |

`eventsJSON` est un tableau JSON. Les dates (`at`) sont en ISO-8601. Exemple d’élément : `{"id":"…","kind":"game_end","mode":"zen","durationSec":420,"at":"2026-11-13T18:00:00Z"}`. `day` n’est présent que pour `daily_played`.

Droits **avant** de déployer en Production :

| Rôle | Create | Read | Write |
|---|---|---|---|
| World | non | non | non |
| Authenticated | oui | non | non |
| Creator | non | non | non |

Ainsi un autre joueur ne lit pas les lots. Le tableau de bord, lui, les lit avec le compte développeur. Déployer le schéma Development, puis Production. Sans ce déploiement, chaque tentative échoue et la pause d’une heure s’applique.

Ne pas réutiliser `PlayerSurvey`.

## Étiquette de confidentialité App Store

À mettre à jour dans App Store Connect (App Privacy), en plus d’activer **App Analytics** (aucun code).

Cocher :

- **Product Interaction** (contenu de jeu : mode, durée, session, défi joué). Purpose : **Analytics**. Linked to the user’s identity : **Yes** (créateur CloudKit = compte iCloud). Used for tracking : **No**.
- **User ID** (l’UUID d’installation). Purpose : **Analytics**. Linked : **Yes**. Tracking : **No**.

Ne pas cocher Advertising Data, ni IDFA, ni Contact Info, ni Location.

Le texte de `docs/privacy-policy.html` (20 avril 2026 → 13 novembre 2026) décrit la même chose en anglais et en français. La page hébergée doit être republiee pour que la fiche pointe vers ce texte.
