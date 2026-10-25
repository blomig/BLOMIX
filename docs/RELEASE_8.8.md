# BLOMIX 8.8 — calendrier et actions

> **Figé le 21 oct. 2026.** (état **21 oct. soir** : 8.6 en vente ; GC Five + CK Production **actifs** ; TestFlight éditeurs **8.8 / 159** en ligne.)  
> Mise en vente visée : **mercredi 18 novembre 2026**.  
> Glissière (si review / badges / copie) : **mercredi 2 décembre 2026**.  
> Watch inchangé : **8.0 / 146**. Ne pas bumper avec l’iPhone.  
> **Pas de fiche 8.7** : le train 8.6 est fermé (Apple refuse un nouveau TF 8.6). Le TF éditeurs est déjà tamponné **8.8**. Ne **pas** `fastlane submit` avant le 11 nov.

Ce fichier est le **tableau de bord humain** du jalon. Cocher les cases. Éditer sur GitHub si une date bouge. Spec produit : [TROPHIES.md](TROPHIES.md), [TROPHY_COPY.md](TROPHY_COPY.md), [DAILY_CHALLENGE.md](DAILY_CHALLENGE.md), [CHANGELOG.md](CHANGELOG.md). Déploiement : [DEVELOPMENT.md](DEVELOPMENT.md) § Fastlane.

**8.8 = nouveau mode Five + Défi Five + Salon des trophées.** Pas un 8.6-bis (juice). Une seule nomination featuring pour l’année.

---

## Dates figées

| | Date | Rôle |
|---|---|---|
| Aujourd’hui | mer. 21 oct. | Fichier créé. **8.6 / 158** en vente. TF éditeurs **8.8 / 159**. |
| Nomination ASC | **avant dim. 26 oct.** | Featuring Nominations, type **App Enhancements**. |
| Copie trophées assez bonne | **mer. 4 nov.** | Ou décision : sortir avec les libellés d’aujourd’hui. |
| Tampon 8.8 + TestFlight 8.8 | **4–11 nov.** | Bump `MARKETING_VERSION` **seulement là**. |
| Envoi review | **mar. 11 – jeu. 13 nov.** | `fastlane release` puis `submit` (`automatic_release: true`). |
| **Mise en vente** | **mer. 18 nov.** | Cible. |
| Glissière | mer. 2 déc. | Si Apple râle (CK / GC) ou copie pas prête. **Éditer** la nomination, ne pas en créer une 2ᵉ. |

Fourchette à coller dans la nomination : **2026-11-18 → 2026-12-02**.

---

## Deux builds (ne pas confondre)

La nomination **n’est pas** l’upload magasin. Il y a **deux** binaires, à deux dates.

| | Quand | Tampon | Pour qui | Copie trophées |
|---|---|---|---|---|
| **A. TestFlight éditeurs** | **Fait 21 oct.** — `fastlane beta` | **8.8 / 159** (Apple a fermé le train 8.6) | Éditeurs : **jouer** Five ~10 min + ouvrir le Salon | **Non** — I/II/III suffisent |
| **B. Build magasin 8.8** (« le propre ») | **4–11 nov.** nouveau TF (160+) si copie/badges ont bougé → **11–13 nov.** review | **8.8 / 160+** (même train, pas 8.9) | App Review + joueurs le 18 nov. | **Oui si option A** : copie figée **avant** cet upload (deadline **4 nov.**). Option B = libellés actuels. |

- **Nomination dimanche 26** : formulaire + date + lien TF ci-dessus. **Ne pas** `fastlane submit` / « Envoyer à la review » : 8.8 n’est pas le build magasin.
- Premier TF **externe** 8.8 : Apple peut coller une **Beta App Review** (heures / 1–2 j.). Si le lien dit « build not available », attendre l’e-mail TestFlight, ne pas recréer de groupe.
- On reste sur le train **8.8** jusqu’au 18 nov. (builds 160+ si besoin). Pas de 8.7, pas de 8.9.

## Cette semaine (toi) — ordre

1. [x] **8.6 en vente** (21 oct.). Magasin 8.8 = review **11–13 nov.**, pas maintenant.
2. [x] **Nomination featuring** (**22 oct.**, import CSV) — `BLOMIX 8.8 — Five + Trophy Room`, type **App Enhancements**, plage 18 nov. – 2 déc. Id `ff8e6688-d23f-4222-a4ff-579274bd264e`. Sous Envoyées. Ne **pas** en créer une 2ᵉ.
3. [x] **Game Center** : `FiveMode` + `dailywin_five` déjà actifs (22 oct.).
4. [x] **CloudKit** : `FiveDailyScore` Production déjà actif (22 oct.).
5. [x] **TestFlight** : **8.8 (159)** le 21 oct. ; **8.8 (160)** le 24 oct. (groupe externe `Featuring`, Beta App Review). **8.8 (161)** le 25 oct. (interne seulement ; Featuring reste sur 160). Lien public : https://testflight.apple.com/join/4zA8hFqB — 160 avant d’apparaître sur le lien. **Pas** de `submit` magasin.
6. [ ] **`TROPHY_COPY.md`** — 20–30 min par soir. **Pas** avant la nomination. Deadline : **mer. 4 nov.**, **avant** l’upload du build magasin B. Voir § Copie.
7. [x] **CloudKit Production `PlayerSurvey`** — type + indexes déployés ; Query OK (23 oct.). Voir § CloudKit.

---

## Calendrier

Légende : **toi** = App Store Connect / copie / captures. **Agent** = code, l10n, Fastlane, Nouveautés. **Ensemble** = playtest.

### Semaine 0 — 21–26 oct. (ne rien attendre)

| | Action | Qui |
|---|---|---|
| [x] | 8.6 Ready for Sale (22 oct.) | toi |
| [x] | Nomination App Enhancements, plage 18 nov. – 2 déc. (CSV, 22 oct.) | toi |
| [x] | Boards GC Five + CK `FiveDailyScore` Production (22 oct.) | toi |
| [x] | TestFlight public **A** 8.8/159 — https://testflight.apple.com/join/4zA8hFqB (21 oct.) | agent |
| [ ] | Démarrer `TROPHY_COPY.md` (pas bloquant pour la nomination) | toi |
| | Peaufinage badges (cible, étoiles, fiche, toast) — **sans submit magasin** | agent |

### Semaine 1 — 27 oct. – 2 nov.

| | Action | Qui |
|---|---|---|
| [ ] | Playtest Five, Défi Five, salon, saves, Duel/Zen/Arcade **intacts** | ensemble |
| [ ] | Freeze **dessin** salon (plus de « encore une gouttière ») | ensemble |
| [ ] | Copie : murs + phrases + un nom par palier, **ou** décision B (libellés actuels en 8.8) | toi |
| | Continuer badges / toasts selon retours | agent |

### Semaine 2 — 3–9 nov.

| | Action | Qui |
|---|---|---|
| [ ] | **4 nov.** : *« implémente TROPHY_COPY »* **ou** « on sort avec les noms d’aujourd’hui » | toi → agent |
| [ ] | 6 langues (FR+EN min., DE/ES/IT/PT si exposé) | agent |
| [ ] | Captures brutes dans `store/asc-assets/inbox/` : **accueil 3 rangées**, **Five en jeu**, **salon** (portrait, iPhone) | toi |
| | Recadrage 6.5" / 6.9" → `out/` | agent |
| [ ] | `store/whats-new/` 6 langues (Five + salon, pas CONNECT) + CHANGELOG | agent |
| [ ] | Bump **8.8 / 159** (Watch **8.0 / 146**) + `fastlane beta` | agent, **après** freeze |
| [x] | CloudKit Production : type `PlayerSurvey` + indexes, Query OK (23 oct.) | toi |

### Semaine 3 — 10–16 nov.

| | Action | Qui |
|---|---|---|
| [ ] | Upload **manuel** captures ASC (Fastlane `skip_screenshots`) — slots 6.5" et 6.9", FR puis EN | toi |
| [ ] | Preview : **garder** la vidéo actuelle sauf plan Five 15–30 s prêt | toi |
| [ ] | Vérifier Nouveautés 6 locales après `fastlane metadata` / `release` | toi |
| [ ] | **11–13 nov.** `fastlane release` puis `submit` | ensemble |
| [ ] | Si la date de vente bouge : **éditer** la nomination (date seulement) | toi |

### Semaine 4 — 17–18 nov.

| | Action | Qui |
|---|---|---|
| [ ] | **18 nov.** 8.8 en vente (`automatic_release`) | Apple |
| [ ] | Contrôle fiche : Nouveautés, captures Five/salon, boards GC, CK | toi |
| [ ] | Silence éditorial = normal. Mail « promotional artwork » = répondre vite (Admin / App Manager / Marketing) | toi |

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
| Supplemental | 1) **https://testflight.apple.com/join/4zA8hFqB** (8.8 / 159)  2) éventuellement preview  3) cette page GitHub |

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

## Copie trophées — décision au 4 nov.

Fichier : [TROPHY_COPY.md](TROPHY_COPY.md) (pas lu par le jeu). Copie **en local**, plus d’édition GitHub web. Les `id` sont gelés. Un **nom** sous la cible (I / II / III) + un **maître** à 3 étoiles. Encore des `…`.

**Pas besoin** pour la nomination ni pour le TestFlight éditeurs (build A).

**Besoin** avant le build magasin (B), si les noms doivent être **dans** 8.8 : freeze copie **mer. 4 nov.** → *« implémente TROPHY_COPY »* → puis captures (le salon affiche les noms) → puis `fastlane beta` 8.8.

Si la copie arrive **après** l’upload 8.8, elle n’est plus dans cette version (sauf 8.8.1 / 8.9).

Au **4 novembre**, une des trois :

| | Quoi | Conséquence |
|---|---|---|
| **A (reco)** | Murs remplis + phrase + au moins un nom par palier | Agent implémente (`BlomixL10n` + 6 `.lproj`) dans le lot 8.8 |
| **B** | « On sort avec les libellés d’aujourd’hui » (Five, Arcade, I/II/III) | 8.8 part ; copie riche = plus tard |
| **C** | Copie pas prête, tu la veux dans 8.8 | On glisse au **2 déc.** et on édite la nomination |

Les **mots à la place de I/II/III** peuvent rester I/II/III en 8.8. Pas bloquant pour Apple.

Quand c’est assez bon : message **« implémente TROPHY_COPY »**. Pas avant.

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

- Push GitHub **sauf** demande (« commit et push », « mets-le sur GitHub »).
- Bump `MARKETING_VERSION` **avant** la semaine du 4 nov.
- Implémenter `TROPHY_COPY` sans le feu vert.
- Créer boards GC / déployer le schéma CK Production.
- Soumettre la nomination (ton login ASC).
- `fastlane submit` sans ton OK.

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
