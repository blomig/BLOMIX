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
| `first_launch` | Une fois, au premier passage au premier plan après l’installation de cette mesure | `is_new_install` (voir plus bas). Absent sur les lots d’avant cette clé |
| `session_start` | Chaque retour au premier plan (`sceneDidEnterBackground` rouvre le compteur) | — |
| `game_end` | Fin Arcade, Zen, Five, Défi, tutoriel (`triggerGameOver`) ou Duel (écran de résultat) | `mode`, `durationSec` si une partie était suivie, `resumed` dans le même cas |
| `daily_played` | **Nouvelle** partie de défi (pas la reprise) | `mode`, `day` (jour UTC de la graine) |
| `tutorial_start` | Démarrage du tutoriel interactif | — |
| `tutorial_step` | Chaque étape atteinte, y compris la première | `step_index`, `step_id` |
| `tutorial_end` | Fin du script, bouton Passer, game over, ou processus tué pendant le tuto | `result` (`completed`, `skipped`, `abandoned`), `step_index`, `step_id` de l’étape atteinte |
| `first_guided_game_start` | Le bouton de fin du tuto lance la première Arcade sans chrono | — |
| `first_guided_game_end` | Fin de cette partie : game over, retour à l’accueil, ou processus tué après un passage en arrière-plan | — |

`tutorial_end` part aussi quand « FIN DU TUTO » ou « Passer » ramène à l’accueil. Avant, seul le game over du tuto émettait quelque chose (`game_end`, `mode` = `tutorial`). Ce `game_end` reste en plus, le jour où le tuto se termine par un game over.

`step_id` : `intro`, `chain_prompt`, `chain_celebration`, `awaiting_brix`, `brix_intro`, `brix_celebration`, `free_play`, `bomb_intro`, `bomb_celebration`, `magix_intro`. `step_index` est l’index stable de cette liste (0…9), pas l’ordre de visite : après la bombe le script passe par `magix_intro` (9) puis `bomb_celebration` (8).

Un abandon est : le game over pendant le tuto, ou le processus tué après un passage en arrière-plan (la dernière étape est relue au lancement suivant). Revenir au premier plan sans tuer l’app ne compte pas comme un abandon. Un force-quit qui ne passe pas par l’arrière-plan ne laisse pas d’événement.

`first_guided_game_end` suit la même règle de processus : la clé `blomix_telemetry_guided_pending_end_v1` est lue au prochain lancement si l’app a été tuée. Revenir au premier plan sans tuer l’app ne ferme pas la partie. Le bouton Passer, ou une sauvegarde déjà là, ne lance pas cette partie : pas d’événement. Une reprise plus tard de la sauvegarde est une Arcade normale, avec le chrono. Ce n’est pas un second `first_guided_game_start`.

### `is_new_install`

Vrai seulement au `first_launch`, et seulement s’il n’y a **aucune** trace locale de jeu antérieur au moment de ce premier passage au premier plan. Sert à séparer une installation neuve d’un joueur qui met à jour (son premier `first_launch` mesuré est le jour de la mise à jour).

Le booléen n’est **pas** réécrit plus tard. Un joueur qui a déjà émis `first_launch` en 8.9 n’aura jamais la clé : le rapport le classe « inconnu », pas « nouveau ».

Critère (`BlomixInstallCensus`) : faux dès qu’une de ces traces est présente.

- Tutoriel déjà vu : `BlomixHasSeenGameTutorial` ou `BlomixHasSeenInteractiveTutorial_v1`
- Un record local > 0 : Arcade, Zen, Five, moyenne (`BlomixAvgGameCount`), scores en attente Game Center, points ou score de Défi, matchs Elo en attente
- Une sauvegarde présente : Arcade, Zen, Five, Défi Arcade, Défi Five, ou un jour de Défi déjà fini
- Un trophée de jeu dans `blomix_trophies_v1` (valeur > 0). `theme_light` ne compte pas : il est posé au lancement en Clair, sans partie. Un JSON de trophées illisible compte comme une trace.

La lecture ne crée pas ces clés.

`mode` : `arcade`, `zen`, `five`, `daily_arcade`, `daily_five`, `duel`, `tutorial`.

`durationSec` est un entier : **temps de jeu actif**, pas l’horloge murale. Le chrono n’avance que si une partie est ouverte, l’app est au premier plan, et le jeu n’est pas en pause (menu ☰, modal ouvert depuis la partie, confirmation pour quitter). Il s’arrête en arrière-plan, en pause, et au retour au menu. Une partie neuve remet le compteur à zéro (`noteGameBegan`).

La reprise (`noteGameResumed(mode:activePlaySeconds:)`) restaure ce compteur. Elle n’émet ni début de partie ni `daily_played`. `resumed` vaut `true` si cette reprise a eu lieu au moins une fois. Les secondes vivent dans la sauvegarde de la partie, champ optionnel `activePlaySeconds` de `BlomixSoloGameSave` (défaut 0, pas de bump de version : les saves d’avant se relisent). Le Défi embarque la même struct. Le Duel n’a pas de reprise : le chrono reste en mémoire, `resumed` reste faux.

Une fin sans partie suivie envoie `game_end` **sans** `durationSec` ni `resumed` (clés absentes, comme avant). `session_start`, `first_launch` et `daily_played` n’ont pas ces clés non plus.

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

`eventsJSON` est un tableau JSON. Les dates (`at`) sont en ISO-8601. Exemple d’élément : `{"id":"…","kind":"game_end","mode":"zen","durationSec":420,"resumed":false,"at":"2026-11-13T18:00:00Z"}`. `day` n’est présent que pour `daily_played`. `resumed` n’est présent que pour un `game_end` dont la partie était suivie. `step_index`, `step_id` et `result` ne sont présents que pour le tutoriel. `is_new_install` n’est présent que pour un `first_launch` émis à partir de cette mesure. `first_guided_game_start` et `first_guided_game_end` n’ajoutent pas de clé. Une clé absente reste absente : un lot déjà en file se relit. Pas de nouveau champ sur le type CloudKit `TelemetryBatch`.

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
