#!/usr/bin/env ruby
# frozen_string_literal: true

# Valide store/whats-new + store/promotional-text (5 locales ASC)
# et les entitlements Debug/Release (aps-environment).
#
# Usage :
#   ruby scripts/validate-store-metadata.rb
#   ruby scripts/validate-store-metadata.rb --skip-store
#   ruby scripts/validate-store-metadata.rb --skip-entitlements
#
# Code de sortie : 0 si OK, 1 sinon. Aucune dépendance gem.

require "pathname"

ROOT = Pathname.new(__dir__).parent.expand_path
LOCALES = %w[en-US fr-FR de-DE es-ES it-IT].freeze
WHATS_NEW_MAX = 4000
PROMO_MAX = 170
PBX = ROOT.join("Blomix/Blomix.xcodeproj/project.pbxproj")
DEBUG_ENTITLEMENTS = ROOT.join("Blomix/Blomix/Blomix.entitlements")
RELEASE_ENTITLEMENTS = ROOT.join("Blomix/Blomix/BlomixRelease.entitlements")

skip_store = ARGV.include?("--skip-store")
skip_entitlements = ARGV.include?("--skip-entitlements")

errors = []
warnings = []

def grapheme_len(text)
  text.to_s.gsub("\r\n", "\n").strip.each_grapheme_cluster.count
end

def bullet_count(text)
  text.to_s.lines.map(&:strip).count { |line| line.start_with?("•", "* ", "- ") }
end

def read_utf8(path)
  raw = File.binread(path)
  errors = []
  errors << "#{path.relative_path_from(ROOT)} : BOM UTF-8 interdit (sauver sans BOM)" if raw.start_with?("\xEF\xBB\xBF".b)
  text = raw.force_encoding("UTF-8")
  errors << "#{path.relative_path_from(ROOT)} : pas de l’UTF-8 valide" unless text.valid_encoding?
  [text, errors]
end

def plist_string(path, key)
  text = File.read(path, encoding: "UTF-8")
  text[%r{<key>#{Regexp.escape(key)}</key>\s*<string>([^<]*)</string>}, 1]
end

def pbx_versions(key)
  File.read(PBX).scan(/#{Regexp.escape(key)} = ([^;]+);/).flatten.map(&:strip).uniq
end

def target_entitlements_by_config
  pbx = File.read(PBX)
  result = {}
  pbx.split("isa = XCBuildConfiguration;").each do |block|
    next unless block.include?("INFOPLIST_FILE")

    name = block[/name = (Debug|Release);/, 1]
    ent = block[/CODE_SIGN_ENTITLEMENTS = ([^;]+);/, 1]
    result[name] = ent.strip if name && ent
  end
  result
end

unless skip_store
  bullets = {}
  LOCALES.each do |locale|
    %w[whats-new promotional-text].each do |kind|
      path = ROOT.join("store", kind, "#{locale}.txt")
      unless path.file?
        errors << "manquant : store/#{kind}/#{locale}.txt"
        next
      end
      text, read_errors = read_utf8(path)
      errors.concat(read_errors)
      next unless text.valid_encoding?

      stripped = text.gsub("\r\n", "\n").strip
      if stripped.empty?
        errors << "store/#{kind}/#{locale}.txt est vide"
        next
      end

      len = grapheme_len(stripped)
      limit = kind == "whats-new" ? WHATS_NEW_MAX : PROMO_MAX
      if len > limit
        errors << "store/#{kind}/#{locale}.txt : #{len} car. > limite Apple #{limit}"
      end

      if kind == "whats-new"
        n = bullet_count(stripped)
        bullets[locale] = n
        warnings << "store/whats-new/#{locale}.txt : aucune puce • (vérifier le format joueur)" if n.zero?
      end
    end
  end

  unique_counts = bullets.values.uniq
  if bullets.size == LOCALES.size && unique_counts.size > 1
    detail = bullets.map { |loc, n| "#{loc}=#{n}" }.join(", ")
    errors << "nombre de puces Nouveautés différent selon la langue (#{detail})"
  end
end

unless skip_entitlements
  unless DEBUG_ENTITLEMENTS.file?
    errors << "manquant : #{DEBUG_ENTITLEMENTS.relative_path_from(ROOT)}"
  end
  unless RELEASE_ENTITLEMENTS.file?
    errors << "manquant : #{RELEASE_ENTITLEMENTS.relative_path_from(ROOT)}"
  end

  if DEBUG_ENTITLEMENTS.file?
    env = plist_string(DEBUG_ENTITLEMENTS, "aps-environment")
    unless env == "development"
      errors << "Blomix.entitlements : aps-environment=#{env.inspect} (attendu development)"
    end
  end
  if RELEASE_ENTITLEMENTS.file?
    env = plist_string(RELEASE_ENTITLEMENTS, "aps-environment")
    unless env == "production"
      errors << "BlomixRelease.entitlements : aps-environment=#{env.inspect} (attendu production)"
    end
  end

  if PBX.file?
    ents = target_entitlements_by_config
    debug_ent = ents["Debug"]
    release_ent = ents["Release"]
    unless debug_ent&.end_with?("Blomix.entitlements")
      errors << "pbxproj Debug CODE_SIGN_ENTITLEMENTS=#{debug_ent.inspect} (attendu Blomix/Blomix.entitlements)"
    end
    unless release_ent&.end_with?("BlomixRelease.entitlements")
      errors << "pbxproj Release CODE_SIGN_ENTITLEMENTS=#{release_ent.inspect} (attendu Blomix/BlomixRelease.entitlements)"
    end

    marketing = pbx_versions("MARKETING_VERSION")
    builds = pbx_versions("CURRENT_PROJECT_VERSION")
    if marketing.size > 1
      errors << "MARKETING_VERSION incohérent dans le pbxproj : #{marketing.join(', ')}"
    elsif marketing.empty?
      errors << "MARKETING_VERSION introuvable dans le pbxproj"
    end
    if builds.size > 1
      warnings << "CURRENT_PROJECT_VERSION incohérent : #{builds.join(', ')}"
    end
    puts "Version Xcode : #{marketing.first || '?'} (build #{builds.first || '?'})" if marketing.any?
  else
    errors << "manquant : #{PBX.relative_path_from(ROOT)}"
  end
end

warnings.each { |w| warn "AVERTISSEMENT : #{w}" }

if errors.empty?
  puts "OK — métadonnées store/ et entitlements valides."
  exit 0
end

warn "ERREURS :"
errors.each { |e| warn "  - #{e}" }
exit 1
