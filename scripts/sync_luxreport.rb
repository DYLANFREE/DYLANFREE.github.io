#!/usr/bin/env ruby
# Sync the canonical report HTML into this GitHub Pages repo.

require "fileutils"
require "json"
require "pathname"
require "uri"

SCRIPT_DIR = Pathname.new(__dir__).realpath
REPO = SCRIPT_DIR.parent.join("luxreport")
WORKSPACE = Pathname.new(ENV.fetch("WEBSITE_WORKSPACE", SCRIPT_DIR.parent.parent.to_s)).realpath
SOURCE = WORKSPACE.join("与AI同行/硅基智能体/产品/硅基智能体_完整版.html")
SOURCE_DIR = SOURCE.dirname
IMAGE_POOL_DIR = WORKSPACE.join("与AI同行/硅基智能体/素材库/图片")
INDEX = REPO.join("index.html")

def read(path)
  File.read(path, encoding: "UTF-8")
end

def local_url?(url)
  return false if url.nil? || url.empty?
  return false if url.start_with?("#", "data:", "mailto:", "tel:", "javascript:")
  return false if url.match?(%r{\A(?:https?:)?//}i)

  true
end

def split_url(url)
  path, rest = url.split(/([?#].*)/, 2)
  [URI.decode_www_form_component(path.to_s), rest.to_s]
end

def image_pool
  files = Dir.glob(IMAGE_POOL_DIR.join("**/*").to_s).select { |p| File.file?(p) }
  pool = {}
  files.each do |path|
    basename = File.basename(path)
    stem = File.basename(path, ".*")
    pool[basename] ||= path
    pool[stem] ||= path
  end
  pool
end

def rewrite_image_refs(html, pool, copied)
  html.gsub(/(<img\b[^>]*\bsrc=["'])([^"']+)(["'][^>]*>)/i) do
    prefix = Regexp.last_match(1)
    url = Regexp.last_match(2)
    suffix = Regexp.last_match(3)
    next Regexp.last_match(0) unless local_url?(url)

    clean, tail = split_url(url)
    basename = File.basename(clean)
    source_path = pool[basename]
    next Regexp.last_match(0) unless source_path

    dest_name = File.basename(source_path)
    dest_rel = File.join("images", dest_name)
    dest_path = REPO.join(dest_rel)
    FileUtils.mkdir_p(dest_path.dirname)
    FileUtils.cp(source_path, dest_path)
    copied << dest_rel
    "#{prefix}#{dest_rel}#{tail}#{suffix}"
  end
end

def remove_private_view(html)
  sanitized = html.dup
  patterns = [
    /#view-bot\.active\s*\{[^}]*\}\s*/m,
    %r{\s*<div class="top-bar-item" data-view="bot"[^>]*>.*?</div>\s*<div class="top-bar-sep"></div>}m,
    %r{\s*<div id="view-bot" class="view-panel">.*?</div>\s*}m
  ]

  patterns.each do |pattern|
    matches = sanitized.scan(pattern).length
    raise "Private view marker mismatch: expected 1, found #{matches}" unless matches == 1

    sanitized.sub!(pattern, "\n")
  end

  sanitized
end

def copy_local_html_deps(html, copied)
  html.scan(/(?:src|href)=["']([^"']+\.html)["']/i).flatten.uniq.each do |url|
    next unless local_url?(url)

    clean, = split_url(url)
    next if clean.start_with?("/")

    source_path = SOURCE_DIR.join(clean).cleanpath
    dest_path = REPO.join(clean).cleanpath
    next unless source_path.file?

    FileUtils.mkdir_p(dest_path.dirname)
    FileUtils.cp(source_path, dest_path)
    copied << clean
  end
end

def validate!(source_html, site_html)
  img_refs = site_html.scan(/<img\b[^>]*\bsrc=["']([^"']+)["']/i).flatten
  html_refs = site_html.scan(/(?:src|href)=["']([^"']+\.html(?:[?#][^"']*)?)["']/i).flatten
  bad_refs = img_refs.select { |ref| ref.start_with?("../", "/") }
  missing = img_refs.reject do |ref|
    next true unless local_url?(ref)

    clean, = split_url(ref)
    REPO.join(clean).file?
  end
  missing_html = html_refs.reject do |ref|
    next true unless local_url?(ref)

    clean, = split_url(ref)
    REPO.join(clean).file?
  end
  source_svg = source_html.scan("<svg").length
  site_svg = site_html.scan("<svg").length

  errors = []
  errors << "Private view remains in publish HTML" if site_html.match?(/data-view=["']bot["']|id=["']view-bot["']/)
  errors << "Found image refs outside repo: #{bad_refs.uniq.join(', ')}" unless bad_refs.empty?
  errors << "Missing local image files: #{missing.uniq.join(', ')}" unless missing.empty?
  errors << "Missing local HTML deps: #{missing_html.uniq.join(', ')}" unless missing_html.empty?
  errors << "SVG count changed: source=#{source_svg}, site=#{site_svg}" unless source_svg == site_svg
  raise errors.join("\n") unless errors.empty?

  { img_refs: img_refs.length, html_refs: html_refs.length, source_svg: source_svg, site_svg: site_svg }
end

source_html = read(SOURCE)
copied = []
site_html = remove_private_view(source_html)
site_html = rewrite_image_refs(site_html, image_pool, copied)
copy_local_html_deps(site_html, copied)
File.write(INDEX, site_html, mode: "w", encoding: "UTF-8")
result = validate!(source_html, site_html)

puts JSON.pretty_generate(
  source: SOURCE.relative_path_from(WORKSPACE).to_s,
  index: INDEX.relative_path_from(WORKSPACE).to_s,
  bytes: site_html.bytesize,
  copied: copied.uniq.sort,
  validation: result
)
