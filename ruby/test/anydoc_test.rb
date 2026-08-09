# frozen_string_literal: true

require_relative "test_helper"

# Smoke test: the extension loads and every entry point round-trips a fixture.
class AnydocTest < Minitest::Test
  def test_to_markdown_detects_the_format_from_the_file_content
    assert_match(/^# /, Anydoc.to_markdown(OUTLINE))
  end

  def test_to_markdown_takes_a_path_as_a_string_or_a_pathname
    assert_equal Anydoc.to_markdown(OUTLINE), Anydoc.to_markdown(OUTLINE.to_s)
  end

  def test_to_markdown_bytes_converts_in_memory
    assert_includes Anydoc.to_markdown_bytes(RICH.binread, format: :docx), "| Quarter | Widgets |"
  end

  def test_to_markdown_bytes_detects_the_format_when_none_is_named
    assert_includes Anydoc.to_markdown_bytes(RICH.binread), "| Quarter | Widgets |"

    # CSV carries no signature, so it has to be named.
    error = assert_raises(Anydoc::UnsupportedError) { Anydoc.to_markdown_bytes(CSV.binread) }
    assert_match(/unrecognized file content/, error.message)
    assert_includes Anydoc.to_markdown_bytes(CSV.binread, format: :csv), "| --- |"
  end

  def test_a_format_is_named_by_a_symbol_or_a_string
    assert_equal Anydoc.to_markdown_bytes(CSV.binread, format: :csv),
                 Anydoc.to_markdown_bytes(CSV.binread, format: "csv")
  end

  def test_pdfs_convert_to_markdown
    assert_instance_of String, Anydoc.to_markdown(PDF)
  end

  def test_to_document_exposes_the_document_model
    document = Anydoc.to_document(OUTLINE.binread, format: :docx)
    heading = document.blocks.find { |block| block.kind == :heading }

    assert_includes 1..6, heading.level
    assert_equal :text, heading.content.first.kind
    assert_instance_of String, heading.content.first.text
    assert_includes [true, false], heading.content.first.style.bold
  end

  def test_to_document_carries_embedded_assets_as_binary_strings
    document = Anydoc.to_document(RICH.binread)
    image = document.assets.find { |asset| asset.media_type == "image/png" }

    assert_equal Encoding::BINARY, image.data.encoding
    refute_empty image.data
    assert_equal document.assets.index(image), image.id
  end

  def test_to_document_is_unsupported_for_pdfs
    assert_raises(Anydoc::UnsupportedError) { Anydoc.to_document(PDF.binread) }
  end

  def test_format_detection_reads_content_extension_and_path
    assert_equal :docx, Anydoc.format_from_bytes(RICH.binread)
    # CSV carries no signature: only the extension names it.
    assert_nil Anydoc.format_from_bytes(CSV.binread)
    assert_equal :pptx, Anydoc.format_from_extension(".pptm")
    assert_equal :xlsx, Anydoc.format_from_extension("xls")
    assert_nil Anydoc.format_from_extension(".unknown")
    assert_equal :odt, Anydoc.format_from_path("report.odt")
    assert_equal :odt, Anydoc.format_from_path(Pathname("dir/report.ODT"))
    assert_nil Anydoc.format_from_path("report")
    assert_nil Anydoc.format_from_path("report.unknown")
  end

  def test_every_format_is_named_in_formats
    assert_equal %i[doc docx odt pdf ppt pptx rtf epub xlsx ods odp csv], Anydoc::FORMATS
    assert_predicate Anydoc::FORMATS, :frozen?
    Anydoc::FORMATS.each { |format| assert_equal format, Anydoc.format_from_extension(format) }
  end

  def test_conversion_errors_raise_the_class_that_names_the_failure
    error = assert_raises(Anydoc::MalformedError) do
      Anydoc.to_markdown_bytes("not a document", format: :docx)
    end
    # The base class still catches every one of them.
    assert_kind_of Anydoc::ConvertError, error
    # Nothing about these bytes is a package part.
    assert_nil error.part

    assert_raises(Anydoc::EncryptedError) { Anydoc.to_markdown_bytes(ENCRYPTED.binread) }

    error = assert_raises(Anydoc::ResourceLimitError) do
      Anydoc.to_markdown_bytes(ZIPBOMB.binread, format: :docx)
    end
    assert_equal :max_entry_bytes, error.limit
  end

  def test_a_package_missing_the_parts_it_is_made_of_names_the_part
    # A readable package carrying none of the parts a docx is made of.
    package = zip("[Content_Types].xml", "<Types/>")

    error = assert_raises(Anydoc::MissingPartError) do
      Anydoc.to_markdown_bytes(package, format: :docx)
    end
    assert_equal "word/document.xml", error.part
  end

  def test_unreadable_files_and_bad_arguments_raise_the_ruby_exception
    assert_raises(Errno::ENOENT) { Anydoc.to_markdown("no-such-file.docx") }
    assert_raises(ArgumentError) { Anydoc.to_markdown_bytes("", format: :wat) }
    assert_raises(ArgumentError) { Anydoc.to_markdown_bytes("", format: 42) }
    assert_raises(TypeError) { Anydoc.to_markdown_bytes(42) }
  end

  def test_conversions_run_concurrently
    # Conversion releases the GVL, so these really do overlap.
    expected = Anydoc.to_markdown(RICH)
    threads = 4.times.map { Thread.new { 10.times.map { Anydoc.to_markdown(RICH) }.uniq } }

    assert_equal [[expected]] * 4, threads.map(&:value)
  end

  private

  # A one-entry stored zip, built by hand because Ruby ships no zip writer.
  # Field order is the one APPNOTE.TXT lays out for the local header, the
  # central directory header, and the end-of-central-directory record.
  def zip(name, body)
    crc = Zlib.crc32(body)
    local = "PK\x03\x04".b + [20, 0, 0, 0, 0].pack("v5") +
            [crc, body.bytesize, body.bytesize].pack("V3") +
            [name.bytesize, 0].pack("v2") + name + body
    central = "PK\x01\x02".b + [20, 20, 0, 0, 0, 0].pack("v6") +
              [crc, body.bytesize, body.bytesize].pack("V3") +
              [name.bytesize, 0, 0, 0, 0].pack("v5") + [0, 0].pack("V2") + name
    eocd = "PK\x05\x06".b + [0, 0, 1, 1].pack("v4") +
           [central.bytesize, local.bytesize].pack("V2") + [0].pack("v")
    local + central + eocd
  end
end
