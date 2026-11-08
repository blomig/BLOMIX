# BLOMIX 8.8 — calendrier et actions

> **Mis à jour le 8 nov. 2026.** Code **gelé** pour la publication.  
> Mise en vente visée : **mercredi 18 novembre 2026**.  
> Glissière (si review) : **mercredi 2 décembre 2026**.  
> Watch : marketing **8.0**, build **147**. Le marketing ne suit pas l’iPhone. Le build Watch monte seulement quand le binaire Watch change : une IPA encore en 146 ne remplace pas la montre déjà installée. Le juice 8.8 voyage dans l’IPA iPhone.  
> Fiche 8.8 : `fastlane release` (binaire + Nouveautés). **Pas de `submit`** tant que les captures ne sont pas en place. `submit` reste irréversible (`automatic_release: true`).  
> Nomination déjà envoyée (`ff8e6688-d23f-4222-a4ff-579274bd264e`). **Ne pas en créer une 2ᵉ.** Si la date bouge : éditer la plage seulement.  
> Lien éditeurs : https://testflight.apple.com/join/4zA8hFqB — groupe **Featuring = build 160**. **161** et **162** sont internes. Ne pas lancer `tf_featuring` sans demande.

Ce fichier est le **tableau de bord humain** du jalon. Spec produit : [TROPHIES.md](TROPHIES.md), [TROPHY_COPY.md](TROPHY_COPY.md), [DAILY_CHALLENGE.md](DAILY_CHALLENGE.md), [CHANGELOG.md](CHANGELOG.md). Déploiement : [DEVELOPMENT.md](DEVELOPMENT.md) § Fastlane.

**8.8 = Five + Défi Five + Salon des trophées + voile record.** Pas un 8.6-bis. Une seule nomination featuring pour l’année.

---

## Dates

| | Date | Rôle |
|---|---|---|
| Nomination | **faite le 22 oct.** | App Enhancements, plage **18 nov. → 2 déc.** |
| Copie trophées | **faite** | Option A implémentée (`7ae5406`). Strike passé à **plus de 13** le 7 nov. |
| Code gelé | **dim. 8 nov.** | Plus de correctif avant publication. Binaire review = l’upload `release` de ce jour. |
| Envoi review | **après les captures** | `submit` seulement (`automatic_release: true`). Fenêtre visée : **11–13 nov.** |
| **Mise en vente** | **mer. 18 nov.** | Cible. |
| Glissière | mer. 2 déc. | Si Apple râle. **Éditer** la nomination, ne pas en créer une 2ᵉ. |

Fourchette déjà dans la nomination : **2026-11-18 → 2026-12-02**.

---

## Builds (ne pas confondre)

La nomination **n’est pas** l’upload magasin. Le magasin **8.6 / 158** est en vente. Il n’y a **pas** encore de fiche 8.8.

| Build | Date | Où | Contenu utile |
|---|---|---|---|
| **159** | 21 oct. | TF, ancien lien éditeurs | Five + salon, copie encore I/II/III |
| **160** | 24 oct. | Groupe externe **Featuring** (lien public) | Beta App Review. **C’est celui que les éditeurs ouvrent.** |
| **161** | 25 oct. | TF **interne** | Voile record (perso ou top 3) + feux d’artifice |
| **162** | 7 nov. | TF **interne** | Visée après arrière-plan, Strike > 13, filet gravité, salon sans debug |

Pas de 8.7, pas de 8.9. On reste sur **8.8**.

## Fait

1. [x] **8.6 en vente** (21 oct.).
2. [x] **Nomination** (22 oct.) — `BLOMIX 8.8 — Five + Trophy Room`. Id `ff8e6688-d23f-4222-a4ff-579274bd264e`.
3. [x] **Game Center** `FiveMode` + `dailywin_five` (22 oct.).
4. [x] **CloudKit** `FiveDailyScore` Production (22 oct.) et `PlayerSurvey` (23 oct.).
5. [x] **Copie trophées** dans le binaire (6 langues).
6. [x] **TestFlight** 159 / 160 (Featuring) / 161 interne / **162 interne** (7 nov.).

## Il reste — avant le 11 nov.

Ordre. Rien de ceci n’est le `submit`.

1. [ ] **Captures** dans `store/asc-assets/inbox/` : accueil 3 rangées, Five en jeu (LIGNE x/5), salon. Portrait iPhone. **Toi.**
2. [ ] Recadrage 6.5" / 6.9" → `out/`. **Agent**, dès que les PNG sont là.
3. [ ] Upload **manuel** ASC (Fastlane ne pousse pas les captures) — slots 6.5" et 6.9", FR puis EN. **Toi.**
4. [x] Réécrire `store/whats-new/` **6 langues** (Five, Défi Five, Salon, voile, Watch). **8 nov.**
5. [ ] Preview : **garder** la vidéo actuelle, sauf un plan Five 15–30 s prêt. **Toi.**
6. [ ] `fastlane release` : crée la fiche 8.8, envoie le binaire et les Nouveautés. **Pas** la review. Puis, captures en place, `submit`. **Ensemble.**
7. [ ] Si on veut que les éditeurs jouent **162** (visée, Strike, voile) : `tf_featuring` **sur demande**. Le lien public reste sur **160** tant que ce n’est pas fait.

### Semaine du 18 nov.

| | Action | Qui |
|---|---|---|
| [ ] | **18 nov.** 8.8 en vente, si la review est passée | Apple |
| [ ] | Contrôle fiche : Nouveautés, captures Five/salon, boards GC | toi |
| [ ] | Silence éditorial = normal. Mail « promotional artwork » = répondre vite | toi |

---

Le détail des semaines d’octobre est clos. La suite est **§ Il reste**.

---

## Nomination featuring (coller tel quel)

**Où :** App Store Connect → BLOMIX → barre latérale **Candidatures** → **+** → **Importer des candidatures** (pas Créer : le compte affiche une fausse limite de 50 brouillons). Fichier prêt : [`store/nominations/BLOMIX-8.8-App-Enhancements.csv`](../store/nominations/BLOMIX-8.8-App-Enhancements.csv). L’import **envoie** la candidature (pas de brouillon).

**Rôle requis :** Account Holder, Admin, App Manager ou Marketing.

| Champ | Valeur |
|---|---|
| Nom interne | `BLOMIX 8.8 — Five + Trophy Room` |
| Type | **App Enhancements** (pas App Launch, pas New Content) |
| Date | onglet **Range** : **2026-11-18** → **2026-12-02** |
| Platforms | iPhone |
| Countries | laisser les pays où l’app est en vente (FR, US, DE, ES, IT, BR, etc.) |
| Localizations | FR, EN, DE, ES, IT, PT |
| In-App Event | aucun (sauf si tu en crées un « lancement Five » — optionnel, pas bloquant) |
| Supplemental | 1) **https://testflight.apple.com/join/4zA8hFqB** (groupe Featuring = **8.8 / 160**)  2) éventuellement preview  3) cette page GitHub |

Une fois soumise : on **peut** changer la date ; on **ne peut plus** changer le type ni l’app liée.

### Description (≤ 1000 car., anglais — les éditeurs lisent ça)

```
BLOMIX 8.8 is a significant update: a new original mode (Five) plus a personal trophy room.

Five is a new untimed solo mode, distinct from Zen: incoming line every 5 moves (not 10), Magix count as a placement, bombs do not. Dedicated high score (Game Center FiveMode) and a separate daily (independent seed, CloudKit, dailywin_five). Home becomes Arcade; daily Arcade | daily Five; Duel | Zen | Five.

The Trophy Room is a cabinet of 63 targets on 8 walls covering every mode. Each trophy keeps counting, fills two rings to rank III, then lights 3 stars. Local progress, not Game Center Achievements.

iPhone puzzle, 6 languages (FR EN DE ES IT PT), Game Center, no ads, no IAP wall. Please play Five and open the trophy room from the TestFlight link.
```

### Helpful Details

```
Indie/solo studio (France). BLOMIX is a free 8×8 puzzle with inverted gravity, Brix, Magix, and no ads / no IAP wall. 8.2–8.6 were juice and rules patches; 8.8 is our one major 2026 moment (new mode + long-term collection).

Please play Five for about 10 minutes (line every 5, Magix as a move) and open the Trophy Room from home (6th icon, trophy). Daily Five uses a different seed from Arcade daily.

This is our only featuring nomination for the year. Priority: Games tab collection / list around the 18 Nov window. iPhone portrait only.

Localization: in-app and product page in FR EN DE ES IT PT-BR.
```

### Après envoi

- Pas de mail « non ». Le défaut est le silence.
- Un mail qui demande des **visuels promo** = le dossier a bougé. Specs : [App Store promotional artwork](https://help.apple.com/asc/appspromoart/).
- Notification ASC « featured on Today » = oui. Assets sociaux depuis l’app App Store Connect.
- Si 8.8 glisse : Nominations → la ligne soumise → changer la plage, resoumettre. **Pas** de 2ᵉ nomination 8.8.

Aide Apple : [Nominate your app](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/) · [Getting Featured](https://developer.apple.com/app-store/getting-featured/).

---

## Portes ASC / CloudKit (avant TestFlight externe)

Sans ça, Five marche en local et casse en TF / magasin.

### Game Center

ASC → BLOMIX → Game Center.

| Nom affiché | Vendor ID (celui du code) | Rôle |
|---|---|---|
| (carrière Five) | `FiveMode` | highscore mode Five |
| `DailyWin_five` | **`dailywin_five`** | carrière Défi Five (points podium) |

Arcade reste `dailywins_arc`. Ne pas « corriger » le Five en `dailywins_five`.

Quand la fiche **8.8** existera : rattacher ces boards à la version (comme les boards Arcade / Zen).

### CloudKit

Dashboard → `iCloud.blomig.BLOMIX` → **Production** (pas Development) :

- Type `FiveDailyScore` déployé.
- Champ jour : **`Day`** (majuscule, déjà le cas si créé à la main).
- Record name attendu : `five_{YYYY-MM-DD}_{gamePlayerID}`.

Arcade `DailyScore` / champ `day` : ne pas y toucher.

- Type **`PlayerSurvey`** (sondage 8.8) — **déployé Production** (23 oct.). Query Dashboard OK. Indexes : `recordName` Queryable (obligatoire pour lister), `campaign` Queryable, `gamePlayerID` Queryable, `recommend` Queryable + Sortable.

Même geste que `FiveDailyScore` / `BotEloEvent`. L’app tape la Public **Production** (entitlement), donc un type seulement en Development est invisible.

#### Étapes Dashboard

1. [CloudKit Console](https://icloud.developer.apple.com/dashboard) → team BLOMIX → conteneur **`iCloud.blomig.BLOMIX`**.
2. Environnement **Development**. Schema → **Record Types** → **+**.
3. Nom exact : **`PlayerSurvey`** (casse comprise, un mot). Créer.
4. Ajouter **uniquement** ces champs (casse exacte — pas de `DisplayName`, pas de `RecommendWhy` en PascalCase) :

| Champ | Type Dashboard | Index | Contenu |
|---|---|---|---|
| `campaign` | `String` | **Queryable** | `"8.8"` |
| `modes` | `String` | — | csv `arcade,zen,daily,duel,five` |
| `improve` | `String` | — | Q2, ≤ 200 car., peut être vide |
| `recommend` | `Int(64)` | **Queryable** + **Sortable** | 0…10 |
| `recommendWhy` | `String` | — | Q3 texte, ≤ 200 car., peut être vide |
| `locale` | `String` | — | `fr` / `en` / … |
| `appVersion` | `String` | — | ex. `8.8` |
| `gamePlayerID` | `String` | **Queryable** | Game Center, ou `anon_…` |

5. **Security / Permissions** : **laisser le défaut Public** (World read · Authenticated create · Creator write). Ne pas cocher Authenticated write sur les records des autres.
6. **Deploy Schema Changes…** → **Production**. Vérifier que `PlayerSurvey` est listé en prod avec les **mêmes** indexes.
7. **Aucun record à créer à la main.** Les réponses naissent à la soumission du sondage. Type vide = OK.

`recordName` (pas un champ) : `survey88_{gamePlayerID}`. Un joueur = un record, réécrit s’il resoumet (le client marque `done` donc en pratique une fois).

**Ne pas toucher** : `DailyScore`, `FiveDailyScore`, `AvailablePlayer`, `BotEloEvent`, `PvPH2HEvent`.

Contrôle : Schema **Production** → `PlayerSurvey` listé. Après un playtest : Data → Public → Query `PlayerSurvey` (filtre `campaign` == `8.8`).

Si tu ne déploies **pas** en prod : le joueur voit le merci, mais l’upload échoue (pending local, retry à chaque accueil). Console : `[Survey] upload : …`.

---

## Copie trophées

**Faite** (option A) : noms et phrases dans `BlomixL10n` + 6 langues (`7ae5406`). Strike : **plus de 13** Brix (7 nov.). Les rangs affichés restent I / II / III. Fichier source : [TROPHY_COPY.md](TROPHY_COPY.md). Une retouche de copie après le `submit` ne sera plus dans 8.8.

---

## Captures App Store (semaine 2–3)

Fastlane **ne pousse pas** les screenshots. Procédure : [store/asc-assets/README.md](../store/asc-assets/README.md).

La fiche actuelle (chaînes / Magix / modes / gratuit) **ne montre pas Five ni le salon**. Pour une nomination, il faut au minimum :

1. Accueil **3 rangées** (Arcade / Défis / Duel+Zen+Five)
2. Five **en jeu** (HUD LIGNE x/5 visible)
3. Salon des trophées (mur de cibles)

Déposer les PNG bruts dans `store/asc-assets/inbox/` (gitignoré). L’agent recadre 6.5" (1284×2778) et 6.9" (1320×2868). Upload **manuel** ASC, locales FR puis EN.

App Preview : **ne pas** remplacer tant qu’on n’a pas un plan Five 15–30 s.

---

## Ce que l’agent ne fait pas tout seul

- Push GitHub **sauf** demande.
- Créer la fiche magasin (`fastlane release`) ou `submit` avant le **11 nov.**, et jamais sans OK.
- `tf_featuring` (le lien public resterait collé sur un autre build).
- Créer une 2ᵉ nomination.
- Bumper la Watch ou `MARKETING_VERSION` (déjà **8.8**).
- Réécrire `store/whats-new/` avant le lot `release` (les fichiers actuels sont encore ceux du juice CONNECT).

---

## Rappel Fastlane (semaine 3)

```bash
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
bundle exec fastlane validate
bundle exec fastlane beta      # TestFlight 8.8
bundle exec fastlane release   # IPA + Nouveautés — pas la review
bundle exec fastlane submit    # review, automatic_release: true
```

`release` / `submit` **refusent** s’il reste une fiche éditable dont le numéro ≠ 8.8. D’où le check 8.6 Ready for Sale **cette semaine**.

---

*Mettre à jour ce fichier si la glissière 2 déc. est utilisée, ou si 8.6 n’est pas en vente à temps.*
