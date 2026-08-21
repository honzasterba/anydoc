# frozen_string_literal: true

require_relative "test_helper"

# The extension builds every model object by passing its members positionally,
# so the order these classes declare them in is part of the contract between
# lib/anydoc/document.rb and ext/anydoc/src/document.rs.
class DocumentTest < Minitest::Test
  MEMBERS = {
    Anydoc::Document => %i[blocks notes assets],
    Anydoc::Block => %i[kind level anchor content list table blocks lang text],
    Anydoc::Inline => %i[kind text style content target alt source anchor note_id checked],
    Anydoc::Style => %i[bold italic strike code],
    Anydoc::LinkTarget => %i[kind value],
    Anydoc::ImageSource => %i[kind url asset_id],
    Anydoc::List => %i[marker start items],
    Anydoc::ListItem => %i[blocks marker_label],
    Anydoc::Table => %i[grid header_rows kind],
    Anydoc::CellSlot => %i[kind cell origin_row origin_col],
    Anydoc::Cell => %i[blocks col_span row_span],
    Anydoc::Note => %i[id kind blocks],
    Anydoc::Asset => %i[id media_type origin_part data]
  }.freeze

  def test_every_class_declares_its_members_in_the_order_the_extension_uses
    MEMBERS.each do |klass, members|
      assert_equal members, klass.members, "#{klass} members changed"
    end
  end

  def test_the_model_is_built_out_of_data_classes
    document = Anydoc.to_document(RICH.binread)

    assert_kind_of Data, document
    assert_predicate document, :frozen?
    assert_equal %i[blocks notes assets], document.to_h.keys
    assert_equal document, Anydoc.to_document(RICH.binread)
  end

  def test_blocks_destructure_by_kind
    document = Anydoc.to_document(OUTLINE.binread, format: :docx)
    levels = document.blocks.filter_map do |block|
      case block
      in Anydoc::Block[kind: :heading, level:]
        level
      else
        nil
      end
    end

    refute_empty levels
    assert(levels.all? { |level| (1..6).cover?(level) })
  end

  def test_tables_are_a_grid_of_origin_and_covered_slots
    table = find(Anydoc.to_document(RICH.binread).blocks, :table).table

    assert_equal :data, table.kind
    assert_equal 1, table.header_rows
    slot = table.grid.first.first

    assert_equal :origin, slot.kind
    assert_equal 1, slot.cell.col_span
    assert_nil slot.origin_row
    assert(table.grid.flatten.all? { |cell_slot| %i[origin covered].include?(cell_slot.kind) })
  end

  def test_lists_carry_their_marker_family
    list = find(Anydoc.to_document(RICH.binread).blocks, :list).list

    assert_includes %i[bullet decimal lower_alpha upper_alpha lower_roman upper_roman], list.marker
    assert_equal list.marker != :bullet, list.ordered?
    assert_operator list.start, :>=, 0
    assert_kind_of Anydoc::Block, list.items.first.blocks.first
  end

  def test_text_inlines_carry_a_resolved_style
    inline = find(Anydoc.to_document(OUTLINE.binread, format: :docx).blocks, :heading).content.first

    assert_equal :text, inline.kind
    assert_equal [false, false, false, false],
                 [inline.style.bold, inline.style.italic, inline.style.strike, inline.style.code]
    assert_predicate inline.style, :plain?
    refute_predicate Anydoc::Style.new(true, false, false, false), :plain?
  end

  def test_images_point_at_an_asset_or_a_url
    document = Anydoc.to_document(RICH.binread)
    images = inlines(document.blocks).select { |inline| inline.kind == :image }

    refute_empty images
    images.each do |image|
      assert_includes %i[external asset unavailable], image.source.kind
      next unless image.source.kind == :asset

      assert_equal image.source.asset_id, document.assets[image.source.asset_id].id
    end
  end

  private

  def find(blocks, kind)
    blocks.find { |block| block.kind == kind } || flunk("no #{kind} block in the fixture")
  end

  def inlines(blocks)
    blocks.flat_map do |block|
      (block.content || []) +
        inlines(block.blocks || []) +
        inlines(block.list&.items&.flat_map(&:blocks) || []) +
        inlines(block.table&.grid&.flatten&.filter_map { |slot| slot.cell }&.flat_map(&:blocks) || [])
    end
  end
end
