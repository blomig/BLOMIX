# Nomination featuring 8.8

Fichier à uploader dans App Store Connect (pas dans l’IPA).

**Fichier :** [`BLOMIX-8.8-App-Enhancements.csv`](BLOMIX-8.8-App-Enhancements.csv)  
UTF-8, 16 colonnes Apple (ordre du rapport d’erreur : In-App Events **avant** Platforms). Ligne 1 = en-tête `* Nomination ID` (ignorée). Lignes 2–4 vides. **Données à la ligne 5** seulement — Apple traite toute ligne non vide comme une candidature.

L’import CSV **envoie tout de suite** (pas de brouillon). C’est voulu : le bouton Créer est bloqué chez nous (*limite de 50 brouillons* alors qu’il n’y en a aucun).

## Upload

1. App Store Connect → **Apps** → **BLOMIX** → barre gauche **Candidatures**.
2. **+** à côté de Candidatures → **Importer des candidatures**  
   (si tu ne vois que **Commencer** : Commencer → Importer, **pas** Créer).
3. Glisser ce CSV, ou **Choisir un fichier CSV**.
4. Si la validation est verte : **Envoyer**.
5. La ligne doit apparaître sous **Envoyées / Soumises** : `BLOMIX 8.8 — Five + Trophy Room`.

Ne **pas** ouvrir le fichier dans Excel puis réenregistrer (ça casse l’UTF-8 et les guillemets). Uploader tel quel. Aperçu : Numbers, ou TextEdit en lecture seule.

Premier import (oct. 2026) : Apple a lu nos lignes d’en-tête/hints comme 3 candidatures. La vraie ligne n’avait qu’une erreur : `iOS (iPhone)` était dans la colonne In-App Event. Corrigé. Ne pas remettre de ligne d’aide sous l’en-tête.

Ne pas archiver ni modifier « Lancement du Défi du jour » (autre type, déjà envoyée).

Textes source : [`docs/RELEASE_8.8.md`](../../docs/RELEASE_8.8.md) § Nomination. Helpful Details ramené à ≤ 500 car. pour le CSV.
