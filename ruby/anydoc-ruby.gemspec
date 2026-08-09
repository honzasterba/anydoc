# frozen_string_literal: true

require_relative "lib/anydoc/version"

Gem::Specification.new do |spec|
  # The distribution installs as `anydoc-ruby` (the bare `anydoc` name on
  # RubyGems is held by an unrelated package) and requires as `anydoc`.
  spec.name = "anydoc-ruby"
  spec.version = Anydoc::VERSION
  # Firecrawl is credited for the anydoc crate these bindings wrap; the gem
  # itself is maintained here.
  spec.authors = ["Jan Sterba", "Firecrawl"]
  spec.email = ["info@jansterba.com"]
  spec.license = "MIT"
  spec.summary = "Convert documents (doc, docx, odt, rtf, epub, pdf, presentations, " \
                 "spreadsheets, csv) to GitHub-Flavored Markdown"
  spec.description = "Ruby bindings for the anydoc Rust crate. Converts Word, PowerPoint, " \
                     "Excel, OpenDocument, RTF, EPUB, CSV, and PDF documents into clean " \
                     "GitHub-Flavored Markdown, with one consistent output no matter which " \
                     "format goes in."
  spec.homepage = "https://github.com/honzasterba/anydoc#readme"

  # 3.2 is the floor for Data, which the document model is built from.
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/honzasterba/anydoc/tree/main/ruby",
    "bug_tracker_uri" => "https://github.com/honzasterba/anydoc/issues",
    "changelog_uri" => "https://github.com/honzasterba/anydoc/releases",
    "documentation_uri" => "https://github.com/honzasterba/anydoc/blob/main/ruby/README.md",
    "rubygems_mfa_required" => "true"
  }

  # Globbed rather than read from git: the cross-compile containers build from
  # a mounted directory that is not a repository.
  spec.files = Dir[
    "lib/**/*.rb",
    # Cargo.toml at the root is the extension crate's workspace: it keeps an
    # installed gem's build from walking up out of the gem directory.
    "Cargo.toml",
    "ext/**/*.{rb,rs,toml}",
    "sig/**/*.rbs",
    "README.md",
    "LICENSE"
  ]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/anydoc/extconf.rb"]

  # Needed until RubyGems' own Rust extension support leaves beta: the source
  # gem carries its builder so `gem install` can compile the extension.
  spec.add_dependency "rb_sys", "~> 0.9.111"
end
