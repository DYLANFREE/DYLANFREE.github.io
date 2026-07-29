#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "uri"

SCRIPT_DIR = Pathname.new(__dir__).realpath
REPO = SCRIPT_DIR.parent
WORKSPACE = REPO.parent
SITES_ROOT = REPO.join("sites")
LEGACY_LUX = WORKSPACE.join("luxreport")
LEGACY_AI = WORKSPACE.join("chinafactor-site")

SITE_COPY_RULES = {
  "luxreport" => {
    target: SITES_ROOT.join("luxreport"),
    source: LEGACY_LUX,
    include: %w[index.html images]
  },
  "ai-research" => {
    target: SITES_ROOT.join("ai-research"),
    source: LEGACY_AI,
    include: %w[index.html ai-supply-demand.html china-factor.html assets]
  },
  "waiting-for-overreaction" => {
    target: SITES_ROOT.join("waiting-for-overreaction"),
    source: LEGACY_AI.join("waiting-for-overreaction"),
    include: %w[index.html history-browser.js assets]
  }
}.freeze

SYNC_COMMANDS = [
  [REPO, "scripts/sync_luxreport.rb"],
  [REPO, "scripts/sync_ai_reports.rb"],
  [REPO, "scripts/sync_short_share.rb"]
].freeze

PRIVATE_MARKERS = [
  /data-view=["']bot["']/i,
  /id=["']view-bot["']/i,
  /潮汐：智能交易生命体002\.html/i
].freeze

def run_sync!(dir, script)
  command = [RbConfig.ruby, script]
  stdout, stderr, status = Open3.capture3(*command, chdir: dir.to_s)
  raise "#{dir.basename}/#{script} failed:\n#{stderr}\n#{stdout}" unless status.success?

  puts stdout
end

def safe_reset!(path)
  raise "Unsafe target: #{path}" unless path.parent.realpath == SITES_ROOT.realpath
  raise "Unsafe target name: #{path.basename}" unless SITE_COPY_RULES.key?(path.basename.to_s)

  FileUtils.rm_rf(path)
  FileUtils.mkdir_p(path)
end

def copy_site!(name, config)
  source = config.fetch(:source)
  target = config.fetch(:target)
  safe_reset!(target)

  config.fetch(:include).each do |entry|
    from = source.join(entry)
    raise "Missing publish artifact: #{from}" unless from.exist?

    FileUtils.cp_r(from, target.join(entry), preserve: true)
  end
end

def local_url?(url)
  return false if url.nil? || url.empty?
  return false if url.start_with?("#", "data:", "mailto:", "tel:", "javascript:")
  return false if url.match?(%r{\A(?:https?:)?//}i)

  true
end

def clean_url(url)
  path = url.split(/[?#]/, 2).first.to_s
  URI.decode_www_form_component(path)
end

def validate_html_refs!(file)
  html = file.read(encoding: "UTF-8")
  refs = []
  html.scan(/(?:src|href)=["']([^"']+)["']/i) { |match| refs << match[0] }
  html.scan(/url\(([^)]+)\)/i) do |match|
    refs << match[0].strip.gsub(/\A['"]|['"]\z/, "")
  end

  refs.uniq.select { |ref| local_url?(ref) }.each do |ref|
    clean = clean_url(ref)
    next if clean.empty?

    path = Pathname.new(clean)
    raise "#{file}: escaped local ref #{ref}" if path.absolute? || path.each_filename.any? { |part| part == ".." }

    resolved = file.dirname.join(path).cleanpath
    next if resolved.file?
    next if resolved.directory? && resolved.join("index.html").file?

    raise "#{file}: missing local ref #{ref}"
  end
end

def validate_public_tree!
  forbidden = Dir.glob(REPO.join("**/{.git,.gstack,.DS_Store}").to_s, File::FNM_DOTMATCH)
  forbidden.reject! { |path| path.start_with?(REPO.join(".git").to_s) }
  raise "Forbidden publish files: #{forbidden.join(', ')}" unless forbidden.empty?

  text_files = Dir.glob(REPO.join("**/*.{html,css,js,json,md}").to_s)
  text_files.each do |path|
    content = File.read(path, encoding: "UTF-8")
    raise "#{path}: contains an absolute local path" if content.include?("/Users/") || content.include?("file:")

    PRIVATE_MARKERS.each do |marker|
      raise "#{path}: contains private publish marker #{marker.inspect}" if content.match?(marker)
    end
  end

  Dir.glob(REPO.join("**/*.html").to_s).each do |path|
    validate_html_refs!(Pathname.new(path))
  end
end

if ARGV.include?("--refresh")
  SYNC_COMMANDS.each { |dir, script| run_sync!(dir, script) }
else
  SITE_COPY_RULES.each { |name, config| copy_site!(name, config) }
end
validate_public_tree!

puts JSON.pretty_generate(
  repository: REPO.basename.to_s,
  sites: SITE_COPY_RULES.keys,
  html_files: Dir.glob(REPO.join("**/*.html").to_s).length,
  assets: Dir.glob(REPO.join("**/*").to_s).count { |path| File.file?(path) }
)
