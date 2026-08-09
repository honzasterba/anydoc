# anydoc-ruby

[![Gem](https://img.shields.io/gem/v/anydoc-ruby.svg)](https://rubygems.org/gems/anydoc-ruby)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/honzasterba/anydoc/blob/main/LICENSE)

Convert Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV, and PDF files into clean GitHub-Flavored Markdown. Ruby bindings for the [anydoc](https://crates.io/crates/anydoc) Rust crate, which is built by [Firecrawl](https://firecrawl.dev).

Every format parses into one shared document model and renders through a single Markdown serializer, so headings, tables, lists, and footnotes come out the same no matter which format goes in. Conversion releases the GVL, so other threads keep running. RBS signatures ship with the gem.

```bash
bundle add anydoc-ruby
```

The gem installs as `anydoc-ruby` and requires as `anydoc`, so a Gemfile entry that Bundler auto-requires needs `gem "anydoc-ruby", require: "anydoc"`. Precompiled native gems cover Linux (glibc and musl), macOS, and Windows on Ruby 3.2+; anywhere else, `gem install` builds the extension from source, which needs a [Rust toolchain](https://rustup.rs).

## Supported formats

| Format           | Extensions                                                 |
| ---------------- | ---------------------------------------------------------- |
| Word             | `.doc`, `.docx`, `.docm`                                   |
| PowerPoint       | `.ppt`, `.pps`, `.pot`, `.pptx`, `.pptm`, `.ppsx`, `.ppsm` |
| Excel            | `.xls`, `.xlsx`, `.xlsm`, `.xlsb`                          |
| OpenDocument     | `.odt`, `.ods`, `.odp`                                     |
| Rich Text Format | `.rtf`                                                     |
| EPUB             | `.epub`                                                    |
| CSV              | `.csv`                                                     |
| PDF              | `.pdf`                                                     |

## Usage

```ruby
require "anydoc"

# From a file path:
markdown = Anydoc.to_markdown("report.docx")

# From bytes, with the format detected from the content:
markdown = Anydoc.to_markdown_bytes(data)

# Or name it, which signature-less formats (CSV) need:
markdown = Anydoc.to_markdown_bytes(data, format: :csv)

# Or stop at the document model, which also carries embedded assets:
document = Anydoc.to_document(data)
```

`to_markdown` takes anything path-like, including a `Pathname`. A format is named with a symbol from `Anydoc::FORMATS`; a string is accepted too.

## Errors

A conversion raises only when no meaningful Markdown could come out of the file. The exception class names what went wrong:

```ruby
begin
  Anydoc.to_markdown(path)
rescue Anydoc::EncryptedError, Anydoc::UnsupportedError => error
  # No document comes out of these, so record the file and take the next one.
  unconverted << [path, error.class]
  nil
end
```

| Exception                  | Raised when                                                         |
| -------------------------- | ------------------------------------------------------------------- |
| `Anydoc::UnsupportedError`   | Unknown format, or one that cannot be converted (an image-only PDF) |
| `Anydoc::MalformedError`     | Structurally unusable: no meaningful content could be extracted     |
| `Anydoc::EncryptedError`     | Encrypted or password-protected                                     |
| `Anydoc::ResourceLimitError` | Crossed a fixed safety limit (decompression, nesting, node count)   |
| `Anydoc::MissingPartError`   | A part required for any meaningful output is absent                 |
| `Errno::*`                   | The file could not be read, from `to_markdown` only                 |

The five conversion failures subclass `Anydoc::ConvertError`, so rescuing that handles all of them at once. `MalformedError#part` and `MissingPartError#part` name the package part at fault, `ResourceLimitError#limit` names the limit crossed as a symbol, and `#message` carries the whole message. A `format:` argument naming no supported format raises `ArgumentError`.

## Format detection

The format is read from the file content, using the marker its specification designates: the PDF header, the RTF open group, OLE stream names, the ZIP package mimetype and content types. CSV has no such marker, so detection returns `nil` for it and the extension, or an explicit format, names it instead.

```ruby
Anydoc.format_from_bytes(data)         # :docx, or nil when nothing matches
Anydoc.format_from_extension(".pptm")  # :pptx
Anydoc.format_from_path("report.odt")  # :odt
```

## The document model

`Anydoc.to_document` stops at the parsed model instead of rendering it. Every class in it is a `Data`, so instances are frozen, compare by value, answer `to_h`, and destructure in `case/in`:

```ruby
document = Anydoc.to_document(File.binread("report.docx"))

titles = document.blocks.filter_map do |block|
  case block
  in Anydoc::Block[kind: :heading, level: 1, content:]
    content.filter_map(&:text).join
  else
    nil
  end
end
```

Variants are a `kind` symbol plus the members that kind carries; members belonging to other kinds are `nil`. `Document#blocks` holds the body, `Document#notes` the footnote and endnote bodies that `:note_ref` inlines point at, and `Document#assets` the embedded bytes.

PDFs convert straight to Markdown and have no document-model form, so `to_document` raises `UnsupportedError` for them; use `to_markdown_bytes`.

## Images and embedded objects

Markdown cannot embed bytes, so an embedded image renders as its alt text while the bytes stay on `document.assets` as binary strings, tagged with a media type and the part they came from. Images that carry an external URL render as ordinary Markdown images.

```ruby
document.assets.each do |asset|
  File.binwrite("asset-#{asset.id}", asset.data) if asset.media_type.start_with?("image/")
end
```

Full behavior notes and benchmarks live in the [repository README](https://github.com/honzasterba/anydoc#readme).

## Development

From this directory, with a [Rust toolchain](https://rustup.rs) installed:

```bash
bundle install
bundle exec rake        # compile the extension, then run the tests
bundle exec rake compile
bundle exec rake test
```

Inside this repository the extension builds against the crate in the parent directory rather than the published one; `.cargo/config.toml` is what redirects it.

### Packaging

The source gem needs nothing but RubyGems:

```bash
bundle exec rake build          # pkg/anydoc-ruby-<version>.gem
```

The precompiled gems are cross-compiled in [rb-sys-dock](https://github.com/oxidize-rb/rb-sys) containers, so they need Docker running. Each one carries an extension per Ruby ABI:

```bash
bundle exec rake gems:x86_64-linux   # one platform
bundle exec rake gems:all            # the source gem and all seven platforms
```

Run these through Rake rather than calling `rb-sys-dock` from this directory: the container mounts the shell's working directory, and the build needs the crate one level above it, so the tasks run the CLI from the repository root with `--directory ruby`. The first build of each platform pulls a multi-gigabyte image.

### Releasing

The gem version tracks the version of the crate it wraps, so a release starts from a crate version bump:

1. Bump `lib/anydoc/version.rb` and the `anydoc` dependency in `ext/anydoc/Cargo.toml` to the crate's version.
2. `sh scripts/check-versions.sh` from the repository root, which fails unless all seven version locations agree.
3. Tag `ruby-v<version>` and push it.

The tag runs [`.github/workflows/release-ruby.yml`](../.github/workflows/release-ruby.yml), which cross-compiles every platform gem, installs and tests each one, pushes them through RubyGems trusted publishing, and attaches them to a GitHub release. A `workflow_dispatch` run does everything except publish.

Because the versions are locked together, a fix that touches only the bindings waits for the next crate release. Shipping one sooner means relaxing the version gate for that release.

## License

[MIT](https://github.com/honzasterba/anydoc/blob/main/LICENSE)
