# frozen_string_literal: true

module Anydoc
  # Base class for everything this gem raises. Unreadable files raise the
  # +Errno+ exception any other read of them would, and a format argument
  # naming no supported format raises +ArgumentError+.
  class Error < StandardError; end

  # Meaningful conversion was impossible. Rescue this to handle every kind of
  # failure at once, or one of its subclasses to single one out.
  #
  # Recoverable producer quirks never reach here: they are recovered or
  # skipped while conversion continues.
  class ConvertError < Error; end

  # The format is unknown, or cannot be converted at all: a scanned or
  # image-only PDF needs OCR, which anydoc does not do.
  class UnsupportedError < ConvertError; end

  # The document is structurally unusable: no meaningful content could be
  # extracted.
  class MalformedError < ConvertError
    # @return [String, nil] the package part or stream at fault, or +nil+ when
    #   no single part is.
    attr_reader :part
  end

  # The document is encrypted or password-protected.
  class EncryptedError < ConvertError; end

  # A fixed safety limit was crossed: decompression, nesting depth, node
  # count, repeat expansion, or retained asset bytes.
  class ResourceLimitError < ConvertError
    # @return [Symbol] the limit that was crossed, e.g. +:max_entry_bytes+.
    attr_reader :limit
  end

  # A part required for any meaningful output is absent.
  class MissingPartError < ConvertError
    # @return [String] the part or stream that is missing.
    attr_reader :part
  end
end
