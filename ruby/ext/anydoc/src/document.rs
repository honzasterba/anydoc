//! The document model, built eagerly out of the `Data` classes declared in
//! `lib/anydoc/document.rb`.
//!
//! Variant enums (block kinds, link targets, ...) surface as snake_case
//! symbols on a `kind` member, with the variant's payload on members that are
//! `nil` for every other kind - the same shape the Node and Python bindings
//! give them. Members are passed positionally, in the order the Ruby classes
//! declare them, which `test/document_test.rb` pins.

use magnus::prelude::*;
use magnus::{Error, RArray, RClass, RModule, Ruby, Value};

use anydoc::model;

/// Builds one document. The classes are looked up once per conversion rather
/// than once per node.
struct Build<'a> {
    ruby: &'a Ruby,
    classes: Classes,
}

struct Classes {
    document: RClass,
    block: RClass,
    inline: RClass,
    style: RClass,
    link_target: RClass,
    image_source: RClass,
    list: RClass,
    list_item: RClass,
    table: RClass,
    cell_slot: RClass,
    cell: RClass,
    note: RClass,
    asset: RClass,
}

impl Classes {
    fn new(ruby: &Ruby) -> Result<Self, Error> {
        let anydoc: RModule = ruby.class_object().const_get("Anydoc")?;
        Ok(Classes {
            document: anydoc.const_get("Document")?,
            block: anydoc.const_get("Block")?,
            inline: anydoc.const_get("Inline")?,
            style: anydoc.const_get("Style")?,
            link_target: anydoc.const_get("LinkTarget")?,
            image_source: anydoc.const_get("ImageSource")?,
            list: anydoc.const_get("List")?,
            list_item: anydoc.const_get("ListItem")?,
            table: anydoc.const_get("Table")?,
            cell_slot: anydoc.const_get("CellSlot")?,
            cell: anydoc.const_get("Cell")?,
            note: anydoc.const_get("Note")?,
            asset: anydoc.const_get("Asset")?,
        })
    }
}

/// Build `Anydoc::Document` from a parsed document.
pub fn build(ruby: &Ruby, document: model::Document) -> Result<Value, Error> {
    Build { ruby, classes: Classes::new(ruby)? }.document(document)
}

impl Build<'_> {
    fn document(&self, document: model::Document) -> Result<Value, Error> {
        let blocks = self.array(document.blocks, Self::block)?;
        let notes = self.array(document.notes, Self::note)?;
        let assets = self.array(document.assets, Self::asset)?;
        self.classes.document.funcall("new", (blocks, notes, assets))
    }

    fn block(&self, block: model::Block) -> Result<Value, Error> {
        let fields = match block {
            model::Block::Heading { level, anchor, content } => BlockFields {
                level: Some(level),
                anchor,
                content: Some(self.array(content, Self::inline)?),
                ..BlockFields::of("heading")
            },
            model::Block::Paragraph(content) => BlockFields {
                content: Some(self.array(content, Self::inline)?),
                ..BlockFields::of("paragraph")
            },
            model::Block::List(list) => {
                BlockFields { list: Some(self.list(list)?), ..BlockFields::of("list") }
            }
            model::Block::Table(table) => {
                BlockFields { table: Some(self.table(table)?), ..BlockFields::of("table") }
            }
            model::Block::BlockQuote(blocks) => BlockFields {
                blocks: Some(self.array(blocks, Self::block)?),
                ..BlockFields::of("block_quote")
            },
            model::Block::CodeBlock { lang, text } => {
                BlockFields { lang, text: Some(text), ..BlockFields::of("code_block") }
            }
            model::Block::Rule => BlockFields::of("rule"),
            model::Block::Math(tex) => BlockFields { text: Some(tex), ..BlockFields::of("math") },
        };
        self.classes.block.funcall(
            "new",
            (
                self.ruby.sym_new(fields.kind),
                fields.level,
                fields.anchor,
                fields.content,
                fields.list,
                fields.table,
                fields.blocks,
                fields.lang,
                fields.text,
            ),
        )
    }

    fn inline(&self, inline: model::Inline) -> Result<Value, Error> {
        let fields = match inline {
            model::Inline::Text { text, style } => InlineFields {
                text: Some(text),
                style: Some(self.style(style)?),
                ..InlineFields::of("text")
            },
            model::Inline::Link { content, target } => InlineFields {
                content: Some(self.array(content, Self::inline)?),
                target: Some(self.link_target(target)?),
                ..InlineFields::of("link")
            },
            model::Inline::Image { alt, source } => InlineFields {
                alt: Some(alt),
                source: Some(self.image_source(source)?),
                ..InlineFields::of("image")
            },
            model::Inline::Anchor(id) => {
                InlineFields { anchor: Some(id), ..InlineFields::of("anchor") }
            }
            model::Inline::NoteRef(id) => {
                InlineFields { note_id: Some(id), ..InlineFields::of("note_ref") }
            }
            model::Inline::LineBreak => InlineFields::of("line_break"),
            model::Inline::Math(tex) => {
                InlineFields { text: Some(tex), ..InlineFields::of("math") }
            }
        };
        self.classes.inline.funcall(
            "new",
            (
                self.ruby.sym_new(fields.kind),
                fields.text,
                fields.style,
                fields.content,
                fields.target,
                fields.alt,
                fields.source,
                fields.anchor,
                fields.note_id,
            ),
        )
    }

    fn style(&self, style: model::Style) -> Result<Value, Error> {
        self.classes.style.funcall("new", (style.bold, style.italic, style.strike, style.code))
    }

    fn link_target(&self, target: model::LinkTarget) -> Result<Value, Error> {
        let (kind, value) = match target {
            model::LinkTarget::External(value) => ("external", value),
            model::LinkTarget::Relative(value) => ("relative", value),
            model::LinkTarget::Anchor(value) => ("anchor", value),
        };
        self.classes.link_target.funcall("new", (self.ruby.sym_new(kind), value))
    }

    fn image_source(&self, source: model::ImageSource) -> Result<Value, Error> {
        let (kind, url, asset_id) = match source {
            model::ImageSource::External(url) => ("external", Some(url), None),
            model::ImageSource::Asset(id) => ("asset", None, Some(id.0)),
            model::ImageSource::Unavailable => ("unavailable", None, None),
        };
        self.classes.image_source.funcall("new", (self.ruby.sym_new(kind), url, asset_id))
    }

    fn list(&self, list: model::List) -> Result<Value, Error> {
        let marker = match list.marker {
            model::MarkerKind::Bullet => "bullet",
            model::MarkerKind::Decimal => "decimal",
            model::MarkerKind::LowerAlpha => "lower_alpha",
            model::MarkerKind::UpperAlpha => "upper_alpha",
            model::MarkerKind::LowerRoman => "lower_roman",
            model::MarkerKind::UpperRoman => "upper_roman",
        };
        let items = self.array(list.items, Self::list_item)?;
        self.classes.list.funcall("new", (self.ruby.sym_new(marker), list.start, items))
    }

    fn list_item(&self, item: model::ListItem) -> Result<Value, Error> {
        let blocks = self.array(item.blocks, Self::block)?;
        self.classes.list_item.funcall("new", (blocks, item.checked, item.marker_label))
    }

    fn table(&self, table: model::Table) -> Result<Value, Error> {
        let grid = self.ruby.ary_new_capa(table.grid.len());
        for row in table.grid {
            grid.push(self.array(row, Self::cell_slot)?)?;
        }
        let kind = match table.kind {
            model::TableKind::Data => "data",
            model::TableKind::Layout => "layout",
        };
        self.classes.table.funcall("new", (grid, table.header_rows, self.ruby.sym_new(kind)))
    }

    fn cell_slot(&self, slot: model::CellSlot) -> Result<Value, Error> {
        let (kind, cell, origin) = match slot {
            model::CellSlot::Origin(cell) => ("origin", Some(self.cell(cell)?), None),
            model::CellSlot::Covered { origin_row, origin_col } => {
                ("covered", None, Some((origin_row, origin_col)))
            }
        };
        self.classes.cell_slot.funcall(
            "new",
            (self.ruby.sym_new(kind), cell, origin.map(|(row, _)| row), origin.map(|(_, col)| col)),
        )
    }

    fn cell(&self, cell: model::Cell) -> Result<Value, Error> {
        let blocks = self.array(cell.blocks, Self::block)?;
        self.classes.cell.funcall("new", (blocks, cell.col_span, cell.row_span))
    }

    fn note(&self, note: model::Note) -> Result<Value, Error> {
        let kind = match note.kind {
            model::NoteKind::Footnote => "footnote",
            model::NoteKind::Endnote => "endnote",
        };
        let blocks = self.array(note.blocks, Self::block)?;
        self.classes.note.funcall("new", (note.id, self.ruby.sym_new(kind), blocks))
    }

    fn asset(&self, asset: model::Asset) -> Result<Value, Error> {
        // Binary string: asset bytes are payloads, not text.
        let data = self.ruby.str_from_slice(&asset.bytes);
        self.classes.asset.funcall("new", (asset.id.0, asset.media_type, asset.origin_part, data))
    }

    fn array<T>(
        &self,
        items: Vec<T>,
        build: fn(&Self, T) -> Result<Value, Error>,
    ) -> Result<RArray, Error> {
        let array = self.ruby.ary_new_capa(items.len());
        for item in items {
            array.push(build(self, item)?)?;
        }
        Ok(array)
    }
}

/// Every member of `Anydoc::Block`; a variant sets only the ones it carries.
struct BlockFields {
    kind: &'static str,
    level: Option<u8>,
    anchor: Option<String>,
    content: Option<RArray>,
    list: Option<Value>,
    table: Option<Value>,
    blocks: Option<RArray>,
    lang: Option<String>,
    text: Option<String>,
}

impl BlockFields {
    fn of(kind: &'static str) -> BlockFields {
        BlockFields {
            kind,
            level: None,
            anchor: None,
            content: None,
            list: None,
            table: None,
            blocks: None,
            lang: None,
            text: None,
        }
    }
}

/// Every member of `Anydoc::Inline`; a variant sets only the ones it carries.
struct InlineFields {
    kind: &'static str,
    text: Option<String>,
    style: Option<Value>,
    content: Option<RArray>,
    target: Option<Value>,
    alt: Option<String>,
    source: Option<Value>,
    anchor: Option<String>,
    note_id: Option<String>,
}

impl InlineFields {
    fn of(kind: &'static str) -> InlineFields {
        InlineFields {
            kind,
            text: None,
            style: None,
            content: None,
            target: None,
            alt: None,
            source: None,
            anchor: None,
            note_id: None,
        }
    }
}
