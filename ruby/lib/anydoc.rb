# frozen_string_literal: true

require_relative "anydoc/version"
require_relative "anydoc/errors"
require_relative "anydoc/document"

# Precompiled gems carry one extension per Ruby ABI; a gem built from source
# puts its single extension straight into lib/anydoc.
begin
  RUBY_VERSION =~ /(\d+\.\d+)/
  require_relative "anydoc/#{Regexp.last_match(1)}/anydoc"
rescue LoadError
  require_relative "anydoc/anydoc"
end

# Convert documents (Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV,
# and PDF) to GitHub-Flavored Markdown.
#
#   Anydoc.to_markdown("report.docx")
#
# Every format parses into one shared document model and renders through a
# single Markdown serializer, so headings, tables, lists, and footnotes come
# out the same no matter which format goes in.
#
# @see FORMATS the formats that can be named explicitly.
module Anydoc
  # @!parse
  #   # Every format anydoc reads, named after the extension that identifies
  #   # it. Container variants that share a parser (+.docm+, +.xlsm+,
  #   # +.ppsx+, ...) map onto these through {format_from_bytes} or
  #   # {format_from_extension}.
  #   #
  #   # @return [Array<Symbol>]
  #   FORMATS = %i[doc docx odt pdf ppt pptx rtf epub xlsx ods odp csv].freeze

  class << self
    # Convert a document file to Markdown. The format is detected from the
    # file content; the extension is the fallback for signature-less formats
    # (CSV) and unrecognizable containers.
    #
    # @param path [String, Pathname] the file to convert.
    # @return [String] GitHub-Flavored Markdown.
    # @raise [ConvertError] if no meaningful Markdown could come out of it.
    # @raise [SystemCallError] if the file could not be read.
    def to_markdown(path)
      path = File.path(path)
      data = File.binread(path)
      format = format_from_bytes(data) || format_from_path(path)
      unless format
        raise UnsupportedError,
              "unsupported input: unrecognized file content and extension: #{path}"
      end

      to_markdown_bytes(data, format: format)
    end

    # Convert an in-memory document to Markdown.
    #
    # @param data [String] the document's bytes.
    # @param format [Symbol, String, nil] which format to parse it as. Left
    #   out, the format is detected from the content, which signature-less
    #   formats (CSV) have to name explicitly.
    # @return [String] GitHub-Flavored Markdown.
    # @raise [ConvertError] if no meaningful Markdown could come out of it.
    # @raise [ArgumentError] if +format+ names no supported format.
    def to_markdown_bytes(data, format: nil)
      Native.to_markdown_bytes(data, format_symbol(format))
    end

    # Parse an in-memory document into the document model, which also carries
    # the embedded assets.
    #
    # Unsupported for +:pdf+: PDF conversion produces Markdown directly and
    # has no document-model form; use {to_markdown_bytes}.
    #
    # @param data [String] the document's bytes.
    # @param format [Symbol, String, nil] which format to parse it as. Left
    #   out, the format is detected from the content.
    # @return [Document]
    # @raise [ConvertError] if the document could not be parsed.
    # @raise [ArgumentError] if +format+ names no supported format.
    def to_document(data, format: nil)
      Native.to_document(data, format_symbol(format))
    end

    # Detect the format from the content itself: the signature and identity
    # each container specification designates (PDF header, RTF open group, OLE
    # stream names, ZIP package mimetype/content types).
    #
    # @param data [String] the document's bytes.
    # @return [Symbol, nil] +nil+ for plain-text formats, which carry no
    #   signature, and for anything unrecognized.
    def format_from_bytes(data)
      Native.format_from_bytes(data)
    end

    # The format an extension names, with or without a leading dot, matched
    # case-insensitively.
    #
    # @param extension [String, Symbol] e.g. +".pptm"+.
    # @return [Symbol, nil] +nil+ for anything unrecognized.
    def format_from_extension(extension)
      Native.format_from_extension(extension.to_s.delete_prefix("."))
    end

    # The format a path's extension names.
    #
    # @param path [String, Pathname] the path to read the extension off.
    # @return [Symbol, nil] +nil+ when the path has no extension or names
    #   nothing recognized.
    def format_from_path(path)
      extension = File.extname(File.path(path))
      extension.empty? ? nil : format_from_extension(extension)
    end

    private

    # Format arguments are symbols; strings are accepted for convenience.
    def format_symbol(format)
      case format
      when nil, Symbol then format
      when String then format.to_sym
      else
        raise ArgumentError, "format must be a Symbol, a String, or nil, got #{format.class}"
      end
    end
  end
end
