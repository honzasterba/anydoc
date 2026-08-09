# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "zlib"

require "anydoc"

# The fixtures the Rust test suite converts, shared by every binding.
FIXTURES = Pathname(__dir__).parent.parent / "tests" / "fixtures"
OUTLINE = FIXTURES / "docx" / "handmade-outline.docx"
RICH = FIXTURES / "docx" / "handmade-rich.docx"
CSV = FIXTURES / "csv" / "sheet.csv"
PDF = FIXTURES / "pdf" / "text.pdf"
ENCRYPTED = FIXTURES / "malformed" / "encrypted--errors.odt"
ZIPBOMB = FIXTURES / "abuse" / "zipbomb--errors.docx"
