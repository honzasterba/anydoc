# frozen_string_literal: true

module Anydoc
  # The document model {Anydoc.to_document} returns.
  #
  # Every class here is a +Data+, so instances are frozen, compare by value,
  # answer +to_h+, and destructure in +case/in+:
  #
  #   case block
  #   in Anydoc::Block[kind: :heading, level:, content:]
  #     ...
  #   end
  #
  # Variants (block kinds, link targets, ...) are a +kind+ symbol plus the
  # members that kind carries; members belonging to other kinds are +nil+.
  #
  # @!parse
  #   # Only fully resolved content lives in the model: style cascades,
  #   # numbering, and references are resolved before it is built.
  class Document < Data.define(
    # @return [Array<Block>] body content, in reading order.
    :blocks,
    # @return [Array<Note>] footnote and endnote bodies, referenced from text
    #   by a +:note_ref+ inline.
    :notes,
    # @return [Array<Asset>] every embedded asset, indexed by its +id+.
    :assets
  )
  end

  # One block-level piece of content.
  #
  # @!attribute [r] kind
  #   @return [Symbol] +:heading+, +:paragraph+, +:list+, +:table+,
  #     +:block_quote+, +:code_block+, +:rule+, or +:math+.
  # @!attribute [r] level
  #   @return [Integer, nil] heading: 1-6.
  # @!attribute [r] anchor
  #   @return [String, nil] heading: stable anchor id, when the document
  #     targets this heading.
  # @!attribute [r] content
  #   @return [Array<Inline>, nil] heading, paragraph.
  # @!attribute [r] list
  #   @return [List, nil]
  # @!attribute [r] table
  #   @return [Table, nil]
  # @!attribute [r] blocks
  #   @return [Array<Block>, nil] block_quote.
  # @!attribute [r] lang
  #   @return [String, nil] code_block.
  # @!attribute [r] text
  #   @return [String, nil] code_block, math (LaTeX source without
  #     delimiters).
  class Block < Data.define(
    :kind, :level, :anchor, :content, :list, :table, :blocks, :lang, :text
  )
  end

  # One inline-level piece of content.
  #
  # @!attribute [r] kind
  #   @return [Symbol] +:text+, +:link+, +:image+, +:anchor+ (a zero-width
  #     marker for an internal link target at this position), +:note_ref+,
  #     +:line_break+, +:math+, or +:checkbox+.
  # @!attribute [r] text
  #   @return [String, nil] text; math (LaTeX source without delimiters).
  # @!attribute [r] style
  #   @return [Style, nil] text.
  # @!attribute [r] content
  #   @return [Array<Inline>, nil] link.
  # @!attribute [r] target
  #   @return [LinkTarget, nil] link.
  # @!attribute [r] alt
  #   @return [String, nil] image.
  # @!attribute [r] source
  #   @return [ImageSource, nil] image.
  # @!attribute [r] anchor
  #   @return [String, nil] anchor: the anchor id.
  # @!attribute [r] note_id
  #   @return [String, nil] note_ref: the id of the note in
  #     {Document#notes}.
  # @!attribute [r] checked
  #   @return [Boolean, nil] checkbox: its state.
  class Inline < Data.define(
    :kind, :text, :style, :content, :target, :alt, :source, :anchor, :note_id,
    :checked
  )
  end

  # Fully resolved character style.
  #
  # @!attribute [r] bold
  #   @return [Boolean]
  # @!attribute [r] italic
  #   @return [Boolean]
  # @!attribute [r] strike
  #   @return [Boolean]
  # @!attribute [r] code
  #   @return [Boolean] monospace, from a code or teletype character style.
  class Style < Data.define(:bold, :italic, :strike, :code)
    # @return [Boolean] whether no toggle is set.
    def plain? = !(bold || italic || strike || code)
  end

  # Where a link points.
  #
  # @!attribute [r] kind
  #   @return [Symbol] +:external+ (absolute URL with a scheme), +:relative+
  #     (scheme-less reference, preserved as written), or +:anchor+ (an
  #     internal target: a heading anchor or an +:anchor+ inline).
  # @!attribute [r] value
  #   @return [String] the URL, relative reference, or anchor id.
  class LinkTarget < Data.define(:kind, :value)
  end

  # Where an image's bytes come from.
  #
  # @!attribute [r] kind
  #   @return [Symbol] +:external+ (absolute URL with a scheme), +:asset+
  #     (embedded, carried in {Document#assets}), or +:unavailable+ (the
  #     image's part is missing or unreadable and it has no URL, so only the
  #     alt text remains).
  # @!attribute [r] url
  #   @return [String, nil] external.
  # @!attribute [r] asset_id
  #   @return [Integer, nil] asset: index into {Document#assets}.
  class ImageSource < Data.define(:kind, :url, :asset_id)
  end

  # A list and the marker family the source document used for it.
  #
  # @!attribute [r] marker
  #   @return [Symbol] +:bullet+, +:decimal+, +:lower_alpha+, +:upper_alpha+,
  #     +:lower_roman+, or +:upper_roman+.
  # @!attribute [r] start
  #   @return [Integer] the ordinal the first item counts from.
  # @!attribute [r] items
  #   @return [Array<ListItem>]
  class List < Data.define(:marker, :start, :items)
    # @return [Boolean] whether the list is numbered.
    def ordered? = marker != :bullet
  end

  # One item of a {List}.
  #
  # @!attribute [r] blocks
  #   @return [Array<Block>]
  # @!attribute [r] marker_label
  #   @return [String, nil] literal marker text that overrides the list marker
  #     when the source number text cannot be reproduced from the marker and
  #     position alone (composite number text such as +1-a)+).
  class ListItem < Data.define(:blocks, :marker_label)
  end

  # A table as a canonical grid: every logical grid position appears exactly
  # once. Content and spans live on the origin slot, and each position a span
  # covers holds a +:covered+ slot pointing back at that origin.
  #
  # @!attribute [r] grid
  #   @return [Array<Array<CellSlot>>] rows of slots. Rows may differ in
  #     length when the source is ragged.
  # @!attribute [r] header_rows
  #   @return [Integer] number of leading rows that are header rows (0 = no
  #     header).
  # @!attribute [r] kind
  #   @return [Symbol] +:data+ for a real data table, +:layout+ for layout
  #     scaffolding (text boxes, positioning tables).
  class Table < Data.define(:grid, :header_rows, :kind)
  end

  # One position in a {Table#grid}: either a cell or the shadow of one.
  #
  # @!attribute [r] kind
  #   @return [Symbol] +:origin+ or +:covered+.
  # @!attribute [r] cell
  #   @return [Cell, nil] origin.
  # @!attribute [r] origin_row
  #   @return [Integer, nil] covered: row of the origin this position belongs
  #     to.
  # @!attribute [r] origin_col
  #   @return [Integer, nil] covered: column of the origin this position
  #     belongs to.
  class CellSlot < Data.define(:kind, :cell, :origin_row, :origin_col)
  end

  # A table cell and the extent it spans.
  #
  # @!attribute [r] blocks
  #   @return [Array<Block>]
  # @!attribute [r] col_span
  #   @return [Integer] columns covered, at least 1.
  # @!attribute [r] row_span
  #   @return [Integer] rows covered, at least 1.
  class Cell < Data.define(:blocks, :col_span, :row_span)
  end

  # A footnote or endnote body, referenced from text by a +:note_ref+ inline.
  #
  # @!attribute [r] id
  #   @return [String] the id the referencing inline carries.
  # @!attribute [r] kind
  #   @return [Symbol] +:footnote+ or +:endnote+, by where the source places
  #     the note.
  # @!attribute [r] blocks
  #   @return [Array<Block>] the note's own content.
  class Note < Data.define(:id, :kind, :blocks)
  end

  # An embedded binary asset (image, object payload). Bytes are always
  # retained, so a document stays self-contained.
  #
  # @!attribute [r] id
  #   @return [Integer] index into {Document#assets}, as referenced by an
  #     image source.
  # @!attribute [r] media_type
  #   @return [String] MIME type, e.g. +image/png+.
  # @!attribute [r] origin_part
  #   @return [String] package part or stream the asset came from, for
  #     provenance.
  # @!attribute [r] data
  #   @return [String] the payload, exactly as stored in the source, as a
  #     binary (ASCII-8BIT) string.
  class Asset < Data.define(:id, :media_type, :origin_part, :data)
  end
end
