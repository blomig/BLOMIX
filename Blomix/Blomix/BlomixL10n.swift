//
//  BlomixL10n.swift
//  Blomix
//
//  Chaînes UI : tables `en.lproj` / `fr.lproj` → Localizable.strings.
//

import Foundation

/// Points d’entrée pour `Localizable.strings` (clés dynamiques → `NSLocalizedString`, pas `String(localized:)` réservé aux littéraux).
enum BlomixL10n {

    private static func tr(_ key: String, comment: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: comment)
    }

    // MARK: - Commun

    static var close: String { tr("common.close", comment: "Dismiss full-screen modal") }
    static var cancel: String { tr("common.cancel", comment: "Cancel action (alerts)") }
    static var loading: String { tr("common.loading", comment: "Generic loading label") }

    static var quitConfirmTitle:   String { tr("quit_confirm.title",   comment: "Alert: quit solo game?") }
    static var quitConfirmMessage: String { tr("quit_confirm.message", comment: "Alert: game can be resumed from home") }
    /// Message de sortie Zen (même idée : reprise depuis l’accueil).
    static var quitConfirmMessageZen: String {
        tr("quit_confirm.message_zen", comment: "Alert: game can be resumed from home (Zen)")
    }
    static var quitConfirmQuit:    String { tr("quit_confirm.quit",    comment: "Alert: confirm quit button") }

    // MARK: - Accueil & jeu (SpriteKit)

    static var gameTagline: String { tr("game.tagline", comment: "Subtitle under BLOMIX title") }
    static var startButton: String { tr("start.button", comment: "Start game on welcome screen") }
    static var startContinue: String { tr("start.continue", comment: "Home hero — resume saved Arcade/Zen") }
    static var startDiscover: String { tr("start.discover", comment: "Home hero — first launch tutorial") }
    static var startNewGameLink: String { tr("start.new_game", comment: "Home — start a fresh game, wipes save") }
    static var startNewGameConfirmTitle: String { tr("start.new_game_confirm_title", comment: "Confirm wipe saved game") }
    static var startNewGameConfirmMessage: String { tr("start.new_game_confirm_message", comment: "Confirm wipe saved game body") }
    static var startAbandonSaveTitle: String { tr("start.abandon_save_title", comment: "Home — leave saved game for Zen/Duel") }
    static var startAbandonSaveMessage: String { tr("start.abandon_save_message", comment: "Home — confirm losing saved Arcade/Zen") }
    static var startAbandonSaveConfirm: String { tr("start.abandon_save_confirm", comment: "Home — proceed anyway") }
    static var startHeroModeArcade: String { tr("start.hero_mode_arcade", comment: "Tiny subtitle under Continuer") }
    static var startHeroModeZen: String { tr("start.hero_mode_zen", comment: "Tiny subtitle under Continuer") }
    static var homeIconSettings: String { tr("home.icon.settings", comment: "8pt caption under home settings icon") }
    static var homeIconTutorial: String { tr("home.icon.tutorial", comment: "8pt caption under home tutorial icon") }
    static var homeIconTheme: String { tr("home.icon.theme", comment: "8pt caption under home theme toggle") }
    static var homeIconShare: String { tr("home.icon.share", comment: "8pt caption under home share icon") }
    static var homeIconCredits: String { tr("home.icon.credits", comment: "8pt caption under home credits icon") }
    static var settings: String { tr("start.settings", comment: "Settings link on welcome") }
    static var credits: String { tr("start.credits", comment: "Credits link on welcome") }
    static var zenButton: String { tr("start.zen", comment: "Zen mode button on welcome screen") }
    static var startScreenPlayerUnknown: String { tr("start.player_unknown", comment: "Start screen fallback player name") }
    static func startScreenPlayerName(_ name: String) -> String {
        String(format: tr("start.player_name_format", comment: "Start screen player name; %@ = display name"), name)
    }
    static func startScreenPlayerElo(_ elo: Int) -> String {
        String(format: tr("start.player_elo_format", comment: "Start screen Elo; %lld = rating"), elo)
    }
    static var startScreenPlayerEloUnavailable: String { tr("start.player_elo_unavailable", comment: "Start screen Elo unavailable") }

    static var menuNewGame: String { tr("menu.new_game", comment: "Bottom bar during play") }
    static var menuScores: String { tr("menu.scores", comment: "Bottom bar — leaderboard") }
    static var menuRules: String { tr("menu.rules", comment: "Bottom bar") }
    static var menuSettings: String { tr("menu.settings", comment: "Bottom bar") }
    static var menuMultiplayer: String { tr("menu.multiplayer", comment: "Bottom bar placeholder") }

    static var gameOverTitle: String { tr("game_over.title", comment: "Game over heading") }
    static var gameOverFocusTitle: String { tr("game_over.focus_title", comment: "Animated Game Over title before overlay") }
    static func gameOverScore(_ score: Int) -> String {
        String(format: tr("game_over.score_format", comment: "Game over score line; %lld = points"), score)
    }
    static var gameOverRestart: String { tr("game_over.restart", comment: "Game over — back home") }
    static var gameOverReplay: String { tr("game_over.replay", comment: "Game over — play again same mode") }
    static var gameOverRecordTitle: String { tr("game_over.record_title", comment: "Personal best overlay title") }
    static func gameOverRecordScore(_ score: Int) -> String {
        String(format: tr("game_over.record_score_format", comment: "Personal best score; %lld = points"), score)
    }
    static func gameOverRecordRankSolo(_ rank: Int) -> String {
        String(format: tr("game_over.record_rank_solo_format", comment: "New solo rank; %lld = rank"), rank)
    }
    static func gameOverRecordRankZen(_ rank: Int) -> String {
        String(format: tr("game_over.record_rank_zen_format", comment: "New zen rank; %lld = rank"), rank)
    }
    static var gameOverLeaderboard: String { tr("game_over.leaderboard", comment: "Game over — open rankings") }
    static var gameOverPersonalBest: String { tr("game_over.personal_best", comment: "Shown when new high score") }
    static var gameOverOptimalityLabel: String { tr("game_over.optimality_label", comment: "Subtitle under placement-quality % on game over (justesse / placement)") }
    static var gameOverOptimalityExcludes: String { tr("game_over.optimality_excludes", comment: "Game over — optimality ignores Magix and bombs") }
    static func gameOverMoveStats(excellent: Int, mistakes: Int) -> String {
        String(format: tr("game_over.move_stats_format", comment: "%lld excellent, %lld mistakes"), excellent, mistakes)
    }
    static var gameOverViewWorstMove: String { tr("game_over.view_worst_move", comment: "Game over button to open worst-move overlay") }
    static var gameOverWorstMoveTitle: String { tr("game_over.worst_move_title", comment: "Worst-move overlay title") }
    static var gameOverTapToClose: String { tr("game_over.tap_to_close", comment: "Worst-move overlay dismiss hint") }
    static var gameOverBestMoveLegend: String { tr("game_over.best_move_legend", comment: "Worst-move overlay legend for star marker") }
    static var gameOverWorstMoveLegend: String { tr("game_over.worst_move_legend", comment: "Worst-move overlay legend for skull marker") }
    static var gameOverIncomingLineLabel: String { tr("game_over.incoming_line_label", comment: "Worst-move overlay pending line caption") }
    static var hudBestScoreTitle: String { tr("hud.best_score_title", comment: "HUD best score caption") }
    static var hudBonusTitle: String { tr("hud.bonus_title", comment: "HUD score multiplier caption (solo)") }
    static func hudBestScore(_ score: Int) -> String {
        String(format: tr("hud.best_score_format", comment: "HUD best score; %lld = score"), score)
    }

    static var hudNextBlox: String { tr("hud.next_blox", comment: "Queue caption above upcoming pieces") }
    static var hudNextLine: String { tr("hud.next_line", comment: "Progress HUD label") }
    static var hudNextBomb: String { tr("hud.next_bomb", comment: "Bomb progress HUD label") }
    static var hudTimeCaption: String { tr("hud.time_caption", comment: "HUD timer caption (solo stage / PvP)") }
    static var hudTimeAimingCaption: String { tr("hud.time_aiming_caption", comment: "HUD timer caption while bomb aim is active") }
    static var hudLineCaption: String { tr("hud.line_caption", comment: "HUD incoming-line counter caption") }
    static var hudAttackCaption: String { tr("hud.attack_caption", comment: "Duel HUD — 0…50 attack meter caption") }

    static var gcStatusChecking: String { tr("gc.status.checking", comment: "Game Center HUD before known state") }
    static var gcStatusOk: String { tr("gc.status.ok", comment: "Game Center authenticated") }
    static var gcStatusOff: String { tr("gc.status.off", comment: "Game Center not signed in") }

    static var skinDisplayPerso: String { tr("skin.display.perso", comment: "Custom skin row name") }
    static var skinDisplayPerso2: String { tr("skin.display.perso2", comment: "Second custom skin row name") }
    static var skinDisplayDefault: String { tr("skin.display.default", comment: "Built-in default skin name") }
    static var skinDisplayAlea: String { tr("skin.display.alea", comment: "Random-generated skin row name") }

    // MARK: - Règles / crédits (fallback si fichier txt absent)

    static var rulesMissingBody: String { tr("rules.missing_file", comment: "Placeholder when rules.txt empty") }
    static var creditsMissingBody: String { tr("credits.missing_file", comment: "Placeholder when credits.txt empty") }

    static var modalRulesTitle: String { tr("modal.rules_title", comment: "Rules screen title") }
    static var modalCreditsTitle: String { tr("modal.credits_title", comment: "Credits screen title") }

    /// Sous-titre header écran Crédits.
    static var creditsTagline: String {
        tr("credits.tagline", comment: "Credits header tagline under BLOMIX")
    }
    static func creditsVersionLine(marketing: String, build: String) -> String {
        String(
            format: tr("credits.version_format", comment: "Credits version; %@ marketing, %@ build"),
            marketing, build
        )
    }

    static var creditsReviewHint: String {
        tr("credits.review_hint", comment: "Credits — why a store review helps")
    }
    static var creditsReviewButton: String {
        tr("credits.review_button", comment: "Credits — open App Store write-review")
    }

    /// Sections structurées de l’écran Crédits (titres + lignes corps).
    static var creditsSections: [BlomixCreditsSection] {
        [
            BlomixCreditsSection(
                title: tr("credits.section.studio.title", comment: "Credits section — studio"),
                lines: bodyLines(tr("credits.section.studio.body", comment: "Credits section body — studio"))
            ),
            BlomixCreditsSection(
                title: tr("credits.section.code.title", comment: "Credits section — code"),
                lines: bodyLines(tr("credits.section.code.body", comment: "Credits section body — code"))
            ),
            BlomixCreditsSection(
                title: tr("credits.section.fonts.title", comment: "Credits section — fonts"),
                lines: bodyLines(tr("credits.section.fonts.body", comment: "Credits section body — fonts"))
            ),
            BlomixCreditsSection(
                title: tr("credits.section.sounds.title", comment: "Credits section — sounds"),
                lines: bodyLines(tr("credits.section.sounds.body", comment: "Credits section body — sounds"))
            ),
            BlomixCreditsSection(
                title: tr("credits.section.music.title", comment: "Credits section — music"),
                lines: bodyLines(tr("credits.section.music.body", comment: "Credits section body — music"))
            ),
            BlomixCreditsSection(
                title: tr("credits.section.palette.title", comment: "Credits section — palette"),
                lines: bodyLines(tr("credits.section.palette.body", comment: "Credits section body — palette"))
            ),
            BlomixCreditsSection(
                title: tr("credits.section.beta.title", comment: "Credits section — beta"),
                lines: bodyLines(tr("credits.section.beta.body", comment: "Credits section body — beta"))
            ),
        ]
    }

    /// Découpe un corps multiligne (`\n` dans Localizable.strings) en lignes non vides.
    private static func bodyLines(_ body: String) -> [String] {
        body
            .replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Classement (UIKit)

    static var leaderboardTitle: String { tr("leaderboard.title", comment: "Leaderboard screen title") }
    static var leaderboardSubtitle: String { tr("leaderboard.subtitle", comment: "Under title — leaderboard id") }
    static var leaderboardLoading: String { tr("leaderboard.loading", comment: "Status while fetching") }
    static var leaderboardGcSignIn: String { tr("leaderboard.gc_sign_in", comment: "Prompt when not authenticated") }
    static func leaderboardGcError(_ message: String) -> String {
        String(format: tr("leaderboard.gc_error_format", comment: "Error prefix; %@ = system message"), message)
    }
    static var leaderboardNotFound: String { tr("leaderboard.not_found", comment: "Leaderboard id missing") }
    static func leaderboardLoadError(_ message: String) -> String {
        String(format: tr("leaderboard.load_error_format", comment: "Load failure; %@ = message"), message)
    }
    static var leaderboardEmpty: String { tr("leaderboard.empty", comment: "No scores yet") }
    static func leaderboardTopCount(_ n: Int) -> String {
        String(format: tr("leaderboard.top_count_format", comment: "e.g. Top 12; %lld = count"), n)
    }
    static func leaderboardPoints(_ score: Int) -> String {
        String(format: tr("leaderboard.points_format", comment: "Row secondary; %lld = score"), score)
    }
    static func leaderboardElo(_ score: Int) -> String {
        String(format: tr("leaderboard.elo_format", comment: "Row secondary for Elo leaderboard; %lld = rating"), score)
    }
    static var leaderboardMainTab: String { tr("leaderboard.main_tab", comment: "Main score leaderboard tab") }
    static var leaderboardEloTab:  String { tr("leaderboard.elo_tab",  comment: "Elo leaderboard tab") }
    static var leaderboardAvgTab:  String { tr("leaderboard.avg_tab",  comment: "Average score leaderboard tab") }
    static var leaderboardZenTab:  String { tr("leaderboard.zen_tab",  comment: "Zen mode leaderboard tab") }
    static func leaderboardAverage(_ score: Int) -> String {
        String(format: tr("leaderboard.avg_format", comment: "Row secondary for avg leaderboard; %lld = avg score"), score)
    }
    static func leaderboardAvgGameCount(_ count: Int) -> String {
        String(format: tr("leaderboard.avg_game_count", comment: "Game count shown on avg leaderboard row; %lld = count"), count)
    }

    // MARK: - Réglages (UIKit)

    static var settingsTitle: String { tr("settings.title", comment: "Settings screen title") }
    static var settingsSoundSection: String         { tr("settings.section_sound",       comment: "Settings section heading") }
    static var settingsAppearanceSection: String     { tr("settings.section_appearance",  comment: "Settings section heading — chrome theme") }
    static var settingsAppearanceDark: String        { tr("settings.appearance.dark",     comment: "Dark chrome theme") }
    static var settingsAppearanceLight: String       { tr("settings.appearance.light",    comment: "Light chrome theme") }
    static var settingsFontSection: String           { tr("settings.section_font",        comment: "Settings section heading (legacy)") }
    static var settingsColorsSection: String         { tr("settings.section_colors",      comment: "Settings section heading") }
    static var settingsAdjustSounds: String          { tr("settings.adjust_sounds",       comment: "Settings button to open sound mix screen") }
    static var settingsSoundsSliderLabel: String     { tr("settings.sounds_slider_label", comment: "Label above the master SFX volume slider") }
    static var settingsMusicSliderLabel: String      { tr("settings.music_slider_label",  comment: "Label above the master music volume slider") }
    static var settingsSoundMixTitle: String { tr("settings.sound_mix_title", comment: "Sound mix screen title") }
    static var settingsFontPreview: String { tr("settings.font_preview", comment: "Font choice sample text") }
    static var settingsFontNameBitcount: String { tr("settings.font.bitcount", comment: "Font choice name") }
    static var settingsFontNameGoogleSans: String { tr("settings.font.google_sans", comment: "Font choice name") }
    static var settingsFontNameDynaPuff: String { tr("settings.font.dynapuff", comment: "Font choice name") }
    static var settingsFontNameAlfaSlabOne: String { tr("settings.font.alfa_slab_one", comment: "Font choice name") }
    static var settingsFontNameChangaOne: String   { tr("settings.font.changa_one",    comment: "Font choice name") }
    static func settingsSoundPercent(_ percent: Int) -> String {
        String(format: tr("settings.sound_percent_format", comment: "Sound relative volume percent; %lld = integer percent"), percent)
    }
    static func settingsSoundName(forSoundNamed soundName: String) -> String {
        switch soundName {
        case "Puzzle Game 2.mp3": return tr("settings.sound.music", comment: "Sound row label — background music")
        case "begin.wav": return tr("settings.sound.begin", comment: "Sound row label")
        case "place.wav": return tr("settings.sound.place", comment: "Sound row label")
        case "bomb.wav": return tr("settings.sound.bomb", comment: "Sound row label")
        case "connect_E.wav": return tr("settings.sound.connect_e", comment: "Sound row label")
        case "connect_F.wav": return tr("settings.sound.connect_f", comment: "Sound row label")
        case "connect_Gb.wav": return tr("settings.sound.connect_gb", comment: "Sound row label")
        case "chain_new.wav": return tr("settings.sound.chain_basic", comment: "Sound row label")
        case "chain_new-1.wav": return tr("settings.sound.chain_cascade_1", comment: "Sound row label")
        case "chain_new-2.wav": return tr("settings.sound.chain_cascade_2", comment: "Sound row label")
        case "line.mp3": return tr("settings.sound.line", comment: "Sound row label")
        case "end.wav": return tr("settings.sound.end", comment: "Sound row label")
        case "victory.mp3": return tr("settings.sound.victory", comment: "Sound row label")
        case "wrong.wav": return tr("settings.sound.wrong", comment: "Sound row label")
        case "empty_coll.wav": return tr("settings.sound.empty_column", comment: "Sound row label")
        case "5251__noisecollector__bloopa01.aiff": return tr("settings.sound.pending_line", comment: "Sound row label")
        case "prix.wav": return tr("settings.sound.priks_vanish", comment: "Sound row label")
        default: return soundName
        }
    }

    // MARK: - Tutoriel (overlay + règles)

    static var tutorialGotIt: String { tr("tutorial.got_it", comment: "Dismiss tutorial overlay") }
    static var tutorialDontShowAgain: String { tr("tutorial.dont_show_again", comment: "Next to switch on tutorial overlay") }
    static var tutorialHintScore: String { tr("tutorial.hint_score", comment: "Tutorial — score callout") }
    static var tutorialHintGrid: String { tr("tutorial.hint_grid", comment: "Tutorial — grid / chains") }
    static var tutorialHintBrix: String { tr("tutorial.hint_brix", comment: "Tutorial — special numbered brix block") }
    static var tutorialHintQueue: String { tr("tutorial.hint_queue", comment: "Tutorial — upcoming blocks + line every 10") }
    static var tutorialHintBomb: String { tr("tutorial.hint_bomb", comment: "Tutorial — bomb HUD") }
    static var rulesShowGuidesAtStart: String { tr("rules.show_guides_at_start", comment: "Rules screen — show tutorial toggle label") }

    static var tutorialPage1Title: String { tr("tutorial.page1_title", comment: "Tutorial page 1 heading") }
    static var tutorialPage1Body: String { tr("tutorial.page1_body", comment: "Tutorial page 1 main text") }
    static var tutorialPage1ChainCaption: String { tr("tutorial.page1_chain_caption", comment: "Tutorial page 1 chain visual caption") }
    static var tutorialPage2Title: String { tr("tutorial.page2_title", comment: "Tutorial page 2 heading") }
    static var tutorialPage2Body: String { tr("tutorial.page2_body", comment: "Tutorial page 2 main text") }
    static var tutorialPage3Title: String { tr("tutorial.page3_title", comment: "Tutorial page 3 heading") }
    static var tutorialPage3Body: String { tr("tutorial.page3_body", comment: "Tutorial page 3 main text") }

    // MARK: - Multijoueur PvP

    static var startPvPButton: String { tr("start.pvp", comment: "Start screen — Duel") }
    static var pvpLobbyTitle: String { tr("pvp.lobby_title", comment: "PvP lobby title") }
    static var pvpLobbyPlayFriend: String { tr("pvp.lobby_play_friend", comment: "PvP lobby — invite friend") }
    static var pvpLobbyInvitePlayers: String { tr("pvp.lobby_invite_players", comment: "PvP lobby — invite players") }
    static var pvpLobbyFindOpponent: String { tr("pvp.lobby_find_opponent", comment: "PvP lobby — automatch") }
    static var pvpLobbyFindOpponentPromptTitle: String { tr("pvp.lobby_find_opponent_prompt_title", comment: "PvP lobby — choose matchmaking mode") }
    static var pvpLobbyRandomOpponent: String { tr("pvp.lobby_random_opponent", comment: "PvP lobby — random opponent option") }
    static var pvpLobbyChooseFriendFromFind: String { tr("pvp.lobby_choose_friend_from_find", comment: "PvP lobby — pick a friend from find flow") }
    static var pvpLobbyPickFriendTitle: String { tr("pvp.lobby_pick_friend_title", comment: "PvP lobby — friend picker title") }
    static var pvpLobbyNoFriends: String { tr("pvp.lobby_no_friends", comment: "PvP lobby — empty friends list") }
    static var pvpLobbyStatusInvite: String { tr("pvp.lobby_status_invite", comment: "PvP lobby status — opening invite UI") }
    static var pvpLobbyStatusSearching: String { tr("pvp.lobby_status_searching", comment: "PvP lobby status — searching") }
    static var pvpLobbyStatusConnectingFriend: String { tr("pvp.lobby_status_connecting_friend", comment: "PvP lobby status — connecting to invited friend") }
    static var pvpLobbyPreparingBoards: String { tr("pvp.lobby_preparing_boards", comment: "PvP lobby status — preparing boards") }
    static var pvpLobbyMatchFailed: String { tr("pvp.lobby_match_failed", comment: "PvP lobby — no match") }
    static var pvpLobbyNoPlayersAvailable: String { tr("pvp.lobby_no_players_available", comment: "PvP lobby — nobody available") }
    static var pvpLobbyPreparationTimeout: String { tr("pvp.lobby_preparation_timeout", comment: "PvP lobby — boards preparation watchdog expired") }
    static var pvpAutoSearchActiveHint: String { tr("pvp.auto_search_active_hint", comment: "PvP lobby — auto search toggle is ON, hint text") }
    static var pvpModeQuickDesc: String { tr("pvp.mode_quick_desc", comment: "PvP lobby — quick match / random opponent button") }

    // MARK: - Partie rapide — Local / En ligne
    static var pvpQuickMatchTitle: String {
        tr("pvp.quick_match.title", comment: "Partie rapide — choose Local or Online")
    }
    static var pvpQuickMatchLocalTitle: String {
        tr("pvp.quick_match.local_title", comment: "Partie rapide — Local option title")
    }
    static var pvpQuickMatchLocalSubtitle: String {
        tr("pvp.quick_match.local_subtitle", comment: "Partie rapide — Local subtitle (Bluetooth / local Wi-Fi)")
    }
    static var pvpQuickMatchOnlineTitle: String {
        tr("pvp.quick_match.online_title", comment: "Partie rapide — Online option title")
    }
    static var pvpQuickMatchOnlineSubtitle: String {
        tr("pvp.quick_match.online_subtitle", comment: "Partie rapide — Online subtitle (Game Center)")
    }
    static var pvpLocalSearching: String {
        tr("pvp.local.searching", comment: "Local Multipeer — searching nearby")
    }
    static var pvpLocalConnecting: String {
        tr("pvp.local.connecting", comment: "Local Multipeer — connecting to peer")
    }
    static var pvpLocalTimeout: String {
        tr("pvp.local.timeout", comment: "Local Multipeer — no peer found")
    }
    static var pvpLocalConnectionFailed: String {
        tr("pvp.local.connection_failed", comment: "Local Multipeer — connection failed")
    }
    static var pvpLocalIdentityFailed: String {
        tr("pvp.local.identity_failed", comment: "Local Multipeer — identity exchange failed")
    }
    static var pvpLocalGCRequiredTitle: String {
        tr("pvp.local.gc_required_title", comment: "Local PvP — need prior Game Center sign-in")
    }
    static var pvpLocalGCRequiredMessage: String {
        tr("pvp.local.gc_required_message", comment: "Local PvP — explain one-time GC auth needed")
    }
    static var pvpLocalPickPeerTitle: String {
        tr("pvp.local.pick_peer_title", comment: "Local Multipeer — several peers nearby")
    }
    static var pvpLocalPickPeerMessage: String {
        tr("pvp.local.pick_peer_message", comment: "Local Multipeer — choose who to play")
    }

    static var pvpProtocolMismatchMessage: String {
        tr("pvp.protocol_mismatch.message", comment: "Shown when peer app protocol version mismatches")
    }
    static var pvpReconnectingMessage: String {
        tr("pvp.reconnecting.message", comment: "Brief overlay while waiting for peer reconnect mid-match")
    }
    static var pvpAvailableInviteAppOpenHint: String {
        tr("pvp.available_invite_app_open_hint", comment: "Mode A — invitation is in-app only, peer must have BLOMIX open")
    }
    static var pvpChallengeKeepAppOpen: String {
        tr("pvp.challenge_keep_app_open", comment: "Incoming challenge banner — stay in app, 60 s")
    }
    static func pvpLobbyActivePlayersHint(_ count: Int) -> String {
        String(format: tr("pvp.lobby_active_players_hint_format", comment: "PvP lobby — active player count hint"), count)
    }
    static var pvpUnknownOpponent: String { tr("pvp.unknown_opponent", comment: "Fallback opponent display name") }
    /// Overlay de lancement PvP affiché pendant le handshake et la fermeture du lobby.
    static var pvpMatchFoundLaunching: String { tr("pvp.match_found_launching", comment: "PvP connecting overlay — match found, launching") }

    /// Phrases affichées en rotation dans l'overlay de préparation PvP (attente du handshake).
    static var pvpWaitingPhrases: [String] {
        [
            tr("pvp.waiting_phrase_1", comment: "PvP prep overlay phrase 1"),
            tr("pvp.waiting_phrase_2", comment: "PvP prep overlay phrase 2"),
            tr("pvp.waiting_phrase_3", comment: "PvP prep overlay phrase 3"),
            tr("pvp.waiting_phrase_4", comment: "PvP prep overlay phrase 4"),
        ]
    }
    static var pvpRemoteFillLabelLine1: String { tr("pvp.remote_fill_label_line1", comment: "HUD fill indicator label — line 1") }
    static var pvpRemoteFillLabelLine2: String { tr("pvp.remote_fill_label_line2", comment: "HUD fill indicator label — line 2") }
    static func pvpLobbyOpponentFound(_ name: String) -> String {
        String(format: tr("pvp.lobby_opponent_found_format", comment: "PvP lobby — opponent found; %@ = display name"), name)
    }
    static var pvpLobbySearchHint: String { tr("pvp.lobby_search_hint", comment: "PvP search hint for Elo matchmaking") }
    static func pvpLobbyMatchmakingError(_ message: String) -> String {
        String(format: tr("pvp.lobby_matchmaking_error_format", comment: "PvP matchmaking error; %@ = message"), message)
    }

    static var pvpResultYouWon: String { tr("pvp.result_you_won", comment: "PvP result title win") }
    static var pvpResultYouLost: String { tr("pvp.result_you_lost", comment: "PvP result title lose") }
    static func pvpResultVictoryAgainst(_ name: String) -> String {
        String(format: tr("pvp.result_victory_against_format", comment: "PvP result title win; %@ = display name"), name)
    }
    static func pvpResultDefeatAgainst(_ name: String) -> String {
        String(format: tr("pvp.result_defeat_against_format", comment: "PvP result title loss; %@ = display name"), name)
    }
    static var pvpResultWinSubtitle: String { tr("pvp.result_win_subtitle", comment: "PvP result subtitle win") }
    static var pvpResultLoseSubtitle: String { tr("pvp.result_lose_subtitle", comment: "PvP result subtitle lose") }
    static var pvpResultEloLoading: String { tr("pvp.result_elo_loading", comment: "PvP result — Elo update in progress") }
    static var pvpResultEloUnavailable: String { tr("pvp.result_elo_unavailable", comment: "PvP result — Elo unavailable") }
    static func pvpResultEloCurrent(_ value: Int) -> String {
        String(format: tr("pvp.result_elo_current_format", comment: "PvP result — current Elo; %lld = value"), value)
    }
    static func pvpResultEloDelta(_ delta: Int) -> String {
        String(format: tr("pvp.result_elo_delta_format", comment: "PvP result — Elo delta; %+lld = value"), delta)
    }
    static func pvpResultEloNew(_ value: Int) -> String {
        String(format: tr("pvp.result_elo_new_format", comment: "PvP result — new Elo; %lld = value"), value)
    }
    // MARK: - Mode choice + Récents
    static var pvpModeChoiceHint: String { tr("pvp.mode_choice_hint", comment: "PvP mode selection subtitle") }
    static var pvpModeAutoDesc: String { tr("pvp.mode_auto_desc", comment: "PvP mode — random matchmaking button") }
    static var pvpModeRecentDesc: String { tr("pvp.mode_recent_desc", comment: "PvP mode — recent opponent button") }
    static var pvpRecentTitle: String { tr("pvp.recent_title", comment: "Recent opponents screen title") }
    static var pvpRecentNoPlayers: String { tr("pvp.recent_no_players", comment: "Recent opponents — empty state") }
    static var pvpRecentChallenge: String { tr("pvp.recent_challenge", comment: "Recent opponents — challenge button") }
    static var pvpRecentEloLoading: String { tr("pvp.recent_elo_loading", comment: "Recent opponents — Elo loading") }
    static var pvpRecentEloUnavailable: String { tr("pvp.recent_elo_unavailable", comment: "Recent opponents — Elo unavailable") }
    static func pvpRecentInviteSent(_ name: String) -> String {
        String(format: tr("pvp.recent_invite_sent_format", comment: "Recent opponents — invite sent; %@ = name"), name)
    }
    static var pvpRecentInviteHint: String { tr("pvp.recent_invite_hint", comment: "Recent opponents — waiting for response") }
    static var pvpRecentInviteFailed: String { tr("pvp.recent_invite_failed", comment: "Recent opponents — invite failed") }
    static func pvpInviteChallenge(_ name: String) -> String {
        String(format: tr("pvp.invite_challenge_format", comment: "In-app invite banner — challenger; %@ = name"), name)
    }
    static var pvpInviteAccept: String { tr("pvp.invite_accept", comment: "In-app invite banner — accept") }
    static var pvpInviteDecline: String { tr("pvp.invite_decline", comment: "In-app invite banner — decline") }

    static var pvpResultBackHome: String { tr("pvp.result_back_home", comment: "PvP result — back to home") }
    static var pvpResultRematchAsk: String { tr("pvp.result_rematch_ask", comment: "PvP result — rematch button initial state") }
    static var pvpResultRematchWaiting: String { tr("pvp.result_rematch_waiting", comment: "PvP result — waiting for opponent to confirm rematch") }
    static var pvpResultRematchOpponentReady: String { tr("pvp.result_rematch_opponent_ready", comment: "PvP result — opponent wants rematch, tap to confirm") }
    static var pvpResultRematchLaunching: String { tr("pvp.result_rematch_launching", comment: "PvP result — both confirmed, rematch launching") }
    static func pvpHudMatchAgainst(_ name: String) -> String {
        String(format: tr("pvp.hud_match_against_format", comment: "PvP HUD above timer; %@ = display name"), name)
    }

    /// HUD série revanches : préfixe local, wins local, wins remote, préfixe remote.
    static func pvpHudSeriesScore(localPrefix: String, localWins: Int, remoteWins: Int, remotePrefix: String) -> String {
        String(
            format: tr(
                "pvp.hud_series_score_format",
                comment: "PvP HUD series; %@ local prefix, %lld local wins, %lld remote wins, %@ remote prefix"
            ),
            localPrefix, localWins, remoteWins, remotePrefix
        )
    }

    static var pvpSeriesEndTitle: String {
        tr("pvp.series_end_title", comment: "PvP series end overlay title")
    }
    static var pvpSeriesEndYouLead: String {
        tr("pvp.series_end_you_lead", comment: "PvP series end — local ahead")
    }
    static var pvpSeriesEndYouTrail: String {
        tr("pvp.series_end_you_trail", comment: "PvP series end — local behind")
    }
    static var pvpSeriesEndTied: String {
        tr("pvp.series_end_tied", comment: "PvP series end — draw")
    }
    static func pvpSeriesEndGames(_ count: Int) -> String {
        String(format: tr("pvp.series_end_games_format", comment: "PvP series end — games played; %lld = count"), count)
    }
    static var pvpSeriesEndOK: String {
        tr("pvp.series_end_ok", comment: "PvP series end — dismiss button")
    }
    static var pvpSeriesEndSeriesCaption: String {
        tr("pvp.series_end_series_caption", comment: "PvP series end — label above session score")
    }
    static var pvpSeriesEndTotalCaption: String {
        tr("pvp.series_end_total_caption", comment: "PvP series end — label for all-time H2H (below OK)")
    }

    // MARK: - Start screen tip
    static var startScreenTipHeader: String { tr("start_screen.tip_header", comment: "Start screen — small header above the daily tip") }

    // MARK: - Apparence (Sombre / Clair)
    static var appearanceToggleAccessibility: String {
        tr("appearance.toggle_a11y", comment: "VoiceOver — appearance toggle on home screen")
    }
    static var appearanceDark: String { tr("appearance.dark", comment: "Dark appearance mode label") }
    static var appearanceLight: String { tr("appearance.light", comment: "Light appearance mode label") }

    // MARK: - Partage (accueil + game over)
    static var shareButton: String { tr("share.button", comment: "Share button label on home and game over") }
    static var shareAccessibility: String { tr("share.a11y", comment: "VoiceOver — share BLOMIX") }
    static var shareCardRecordBadge: String {
        tr("share.card.record_badge", comment: "Badge on game-over share card when personal best")
    }
    static func shareHomeScore(_ score: String) -> String {
        String(format: tr("share.home.score_format", comment: "Home share with Solo best; %@ = formatted score"), score)
    }
    static func shareHomeScoreZen(_ score: String) -> String {
        String(format: tr("share.home.score_zen_format", comment: "Home share with Zen best; %@ = formatted score"), score)
    }
    static var shareHomeNoScore: String {
        tr("share.home.noscore", comment: "Home share when player has no stored best score yet")
    }
    static func shareGameOverScore(_ score: String) -> String {
        String(format: tr("share.gameover.score_format", comment: "Game over share; %@ = run score"), score)
    }
    static func shareGameOverScoreZen(_ score: String) -> String {
        String(format: tr("share.gameover.score_zen_format", comment: "Game over Zen share; %@ = run score"), score)
    }
    static func shareGameOverRecord(_ score: String) -> String {
        String(format: tr("share.gameover.record_format", comment: "Game over new personal best share; %@ = score"), score)
    }
    static func shareGameOverRecordZen(_ score: String) -> String {
        String(format: tr("share.gameover.record_zen_format", comment: "Game over new Zen PB share; %@ = score"), score)
    }

    static var rankDiscSolo: String { tr("rank_disc.solo", comment: "Start screen rank disc — Arcade leaderboard") }
    static var rankDiscAvg: String { tr("rank_disc.avg", comment: "Start screen rank disc — average score") }
    static var rankDiscZen: String { tr("rank_disc.zen", comment: "Start screen rank disc — zen mode") }
    static var rankDiscDuel: String { tr("rank_disc.duel", comment: "Start screen rank disc — Duel / Elo") }

    // MARK: - Tutoriel interactif
    static var menuTutorial: String { tr("menu.tutorial", comment: "Tutorial button on home screen and overflow menu") }
    static var tutorialSkip: String { tr("tutorial.skip", comment: "Skip tutorial button (always visible)") }

    // Overlays contextuels
    static var tutorialIntroText: String      { tr("tutorial.intro_text",         comment: "Tuto step 1 — main text") }
    static var tutorialChainPrompt: String    { tr("tutorial.chain_prompt",        comment: "Tuto step 2 — main text") }
    static var tutorialChainHint: String      { tr("tutorial.chain_hint",          comment: "Tuto step 2 — hint text") }
    static var tutorialChainSuccess: String   { tr("tutorial.chain_success",       comment: "Tuto step 2b — celebration") }
    static var tutorialBrixPrompt: String     { tr("tutorial.brix_prompt",         comment: "Tuto step 3 — main text") }
    static var tutorialBrixHint: String       { tr("tutorial.brix_hint",           comment: "Tuto step 3 — hint text") }
    static var tutorialBrixSuccess: String    { tr("tutorial.brix_success",        comment: "Tuto step 3b — celebration") }
    static var tutorialBombPrompt: String     { tr("tutorial.bomb_prompt",         comment: "Tuto step 4 — main text") }
    static var tutorialBombHint: String       { tr("tutorial.bomb_hint",           comment: "Tuto step 4 — hint text") }
    static var tutorialBombSuccess: String    { tr("tutorial.bomb_success",        comment: "Tuto step 4b — final celebration") }
    static var tutorialMagixIntro: String     { tr("tutorial.magix_intro",         comment: "Tuto step 5 — Magix blocks intro before exit") }
    // NOTE: popup labels for Magix are defined in MagixRules.label(for:) directly in GameScene.
    static var tutorialLineArrival: String    { tr("tutorial.line_arrival",        comment: "Tuto informational — first bottom line push") }

    // MARK: - Music track picker
    static var musicPickerLabel: String { tr("settings.music_picker_label", comment: "Sound settings — music track picker label") }
    static var musicTrackPuzzleGame2: String { tr("settings.music_track_puzzle_game2", comment: "Music track name — Puzzle Game 2") }
    static var musicTrackCalm: String { tr("settings.music_track_calm", comment: "Music track name — Calm") }

    // MARK: - Leaderboard — invite
    /// Affiché quand GC refuse l'invitation car les joueurs n'ont pas récemment joué ensemble (code 5121).
    static var pvpLeaderboardInviteNotRecentPlayer: String {
        tr("pvp.leaderboard_invite_not_recent_player",
           comment: "Leaderboard challenge — GC error 5121: can only invite recent opponents")
    }

    // MARK: - App update banner
    static func updateBannerAvailable(_ version: String) -> String {
        String(format: tr("update.banner_available", comment: "In-app update banner — new version on App Store; %@ = version number"), version)
    }

    // MARK: - Transition overlays
    static var transitionLevelPrefix: String { tr("transition.level_prefix", comment: "Stage transition overlay — Level / Niveau") }
    static func stageOverlayTimerSeconds(_ seconds: Int) -> String {
        String(format: tr("stage.overlay.timer_format", comment: "%lld s per move"), seconds)
    }
    static func stageOverlayPointsMultiplier(_ multiplier: Int) -> String {
        String(format: tr("stage.overlay.multiplier_format", comment: "Points × multiplier"), multiplier)
    }
    static var zenOverlayLevelPrefix: String { tr("zen.overlay.level_prefix", comment: "Zen intro overlay small header") }
    static var zenOverlayStageText: String { tr("zen.overlay.stage_text", comment: "Zen intro overlay large text") }
    static var zenOverlayLine1: String { tr("zen.overlay.line1", comment: "Zen intro overlay tagline") }
    static var transitionTutorialTitle:    String { tr("transition.tutorial.title",    comment: "Tutorial intro transition line 1") }
    static var transitionTutorialSubtitle: String { tr("transition.tutorial.subtitle", comment: "Tutorial intro transition line 2") }
    static var transitionTutorialEndTitle:    String { tr("transition.tutorial_end.title",    comment: "Tutorial end transition line 1") }
    static var transitionTutorialEndSubtitle: String { tr("transition.tutorial_end.subtitle", comment: "Tutorial end transition line 2") }

    // MARK: - PvP invite error
    static var pvpInviteErrorTitle: String {
        tr("pvp.invite_error.title", comment: "Alert title when match(for:invite) fails")
    }
    static func pvpInviteErrorMessage(_ senderName: String) -> String {
        String(format: tr("pvp.invite_error.message", comment: "Alert message when invite match creation fails; %@ = player name"), senderName)
    }

    // MARK: - PvP disconnect dialog
    static var pvpDisconnectTitle: String {
        tr("pvp.disconnect.title", comment: "Overlay title when opponent disconnects during a match")
    }
    static var pvpDisconnectMessage: String {
        tr("pvp.disconnect.message", comment: "Overlay message when opponent disconnects — player wins")
    }
    static var pvpDisconnectNeutralMessage: String {
        tr("pvp.disconnect.neutral_message", comment: "Overlay when opponent leaves from result screen")
    }
    static var pvpConnectionFailedTitle: String {
        tr("pvp.connection_failed.title", comment: "Overlay title when PvP connection/handshake fails")
    }
    static var pvpConnectionFailedMessage: String {
        tr("pvp.connection_failed.message", comment: "Overlay message when PvP connection/handshake fails")
    }

    // MARK: - Joueurs disponibles (CloudKit)

    static var pvpModeAvailableDesc: String  { tr("pvp.mode_available_desc",  comment: "PvP lobby — available players button") }
    static var pvpAvailableToggleLabel: String { tr("pvp.available_toggle_label", comment: "PvP lobby — be-challenged toggle button") }
    static var pvpAvailableTitle: String     { tr("pvp.available_title",       comment: "Available players screen title") }
    static var pvpAvailableEmpty: String     { tr("pvp.available_empty",       comment: "Available players screen — empty state") }
    static var pvpAvailableEmptyHint: String { tr("pvp.available_empty_hint",  comment: "Available players — empty state hint") }
    static var pvpAvailableYouAreVisible: String    { tr("pvp.available_you_visible",     comment: "Available players — local player is visible badge") }
    static var pvpAvailableYouAreNotVisible: String { tr("pvp.available_you_not_visible", comment: "Available players — local player not visible badge") }
    static var pvpPlayerInMatch: String             { tr("pvp.player_in_match",           comment: "Available players — player currently in a PvP match") }
    static func pvpAvailableError(_ message: String) -> String {
        String(format: tr("pvp.available_error_format", comment: "Available players — load error; %@ = message"), message)
    }
    static func pvpCloudBusyRetry(_ seconds: Int) -> String {
        String(format: tr("pvp.cloud_busy_retry_format", comment: "CloudKit throttled; %d = seconds to wait"), seconds)
    }
    static var pvpGcNotConnected: String { tr("pvp.gc_not_connected", comment: "PvP lobby — Game Center not signed in") }
    static func pvpGcConnected(_ displayName: String) -> String {
        String(format: tr("pvp.gc_connected_format", comment: "PvP lobby — GC OK; %@ = display name"), displayName)
    }
    static var pvpAvailabilitySending: String { tr("pvp.availability_sending", comment: "PvP lobby — publishing availability to CloudKit") }
    static func pvpAvailabilityCloudKitError(_ message: String) -> String {
        String(format: tr("pvp.availability_cloudkit_error_format", comment: "CloudKit publish error; %@ = message"), message)
    }

    // MARK: - Guide règles (modal 6.4)

    static var guideTitle: String { tr("guide.title", comment: "Rules / Magix guide screen title") }
    static var guideReplayTutorial: String { tr("guide.replay_tutorial", comment: "Guide footer — replay interactive tutorial") }
    static var guideMagixIntro: String {
        tr("guide.section.magix.intro", comment: "Guide — Magix never in Duel or incoming lines")
    }
    static var guideSections: [BlomixCreditsSection] {
        [
            BlomixCreditsSection(
                title: tr("guide.section.blox.title", comment: "Guide section title"),
                lines: bodyLines(tr("guide.section.blox.body", comment: "Guide section body"))
            ),
            BlomixCreditsSection(
                title: tr("guide.section.brix.title", comment: "Guide section title"),
                lines: bodyLines(tr("guide.section.brix.body", comment: "Guide section body"))
            ),
            BlomixCreditsSection(
                title: tr("guide.section.line.title", comment: "Guide section title"),
                lines: bodyLines(tr("guide.section.line.body", comment: "Guide section body"))
            ),
            BlomixCreditsSection(
                title: tr("guide.section.bombs.title", comment: "Guide section title"),
                lines: bodyLines(tr("guide.section.bombs.body", comment: "Guide section body"))
            ),
            BlomixCreditsSection(
                title: tr("guide.section.magix.title", comment: "Guide section title"),
                lines: bodyLines(tr("guide.section.magix.body", comment: "Guide section body"))
            ),
            BlomixCreditsSection(
                title: tr("guide.section.score.title", comment: "Guide section title"),
                lines: bodyLines(tr("guide.section.score.body", comment: "Guide section body"))
            ),
            BlomixCreditsSection(
                title: tr("guide.section.duel.title", comment: "Guide section title"),
                lines: bodyLines(tr("guide.section.duel.body", comment: "Guide section body"))
            ),
        ]
    }

    // MARK: - What's new (accueil, après splash)

    static var whatsNewTitle: String { tr("whatsnew.title", comment: "Version changes dialog title on home") }
    static var whatsNewTwistx: String { tr("whatsnew.twistx", comment: "TWISTX new glyph §") }
    static var whatsNewSlashx: String { tr("whatsnew.slashx", comment: "SLASHX introduction") }
    static var whatsNewDontShow: String { tr("whatsnew.dont_show", comment: "Don't show this version dialog again") }

    // MARK: - Generic
    static var ok: String { tr("generic.ok", comment: "Generic OK button") }
}
