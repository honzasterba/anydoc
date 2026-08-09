//! Ruby bindings for anydoc.
//!
//! The Rust side is deliberately thin: it converts, builds the document model
//! out of the `Data` classes `lib/anydoc/document.rb` declares, and raises the
//! error classes `lib/anydoc/errors.rb` declares. Argument coercion, keyword
//! arguments, and file reading live in Ruby, on `Anydoc`.

use magnus::prelude::*;
use magnus::{
    Error, Exception, IntoValue, RClass, RModule, RObject, RString, Ruby, StaticSymbol, Symbol,
    TryConvert, Value, function,
};

mod document;
mod nogvl;

use nogvl::nogvl;

/// Format names, as the extension that identifies each format. Container
/// variants that share a parser (`.docm`, `.xlsm`, `.ppsx`, ...) map onto
/// these through `format_from_bytes` or `format_from_extension`.
const FORMATS: [(&str, anydoc::Format); 12] = [
    ("doc", anydoc::Format::Doc),
    ("docx", anydoc::Format::Docx),
    ("odt", anydoc::Format::Odt),
    ("pdf", anydoc::Format::Pdf),
    ("ppt", anydoc::Format::Ppt),
    ("pptx", anydoc::Format::Pptx),
    ("rtf", anydoc::Format::Rtf),
    ("epub", anydoc::Format::Epub),
    ("xlsx", anydoc::Format::Excel),
    ("ods", anydoc::Format::Ods),
    ("odp", anydoc::Format::Odp),
    ("csv", anydoc::Format::Csv),
];

/// The format a symbol names, or an `ArgumentError` listing the ones that
/// exist. `nil` asks for detection, which the conversion itself does.
fn parse_format(ruby: &Ruby, format: Option<Symbol>) -> Result<Option<anydoc::Format>, Error> {
    let Some(symbol) = format else {
        return Ok(None);
    };
    let name = symbol.name()?;
    FORMATS
        .iter()
        .find(|(candidate, _)| *candidate == name.as_ref())
        .map(|(_, format)| Some(*format))
        .ok_or_else(|| {
            let names: Vec<&str> = FORMATS.iter().map(|(name, _)| *name).collect();
            Error::new(
                ruby.exception_arg_error(),
                format!("unknown format :{name}; expected one of {}", names.join(", ")),
            )
        })
}

/// The symbol naming a format.
fn format_symbol(ruby: &Ruby, format: anydoc::Format) -> StaticSymbol {
    let name = FORMATS
        .iter()
        .find(|(_, candidate)| *candidate == format)
        .map(|(name, _)| *name)
        .expect("every format is named");
    ruby.sym_new(name)
}

/// The string's bytes, copied while the GVL is still held: the conversion runs
/// without it, where another thread could move or mutate the buffer.
fn bytes(data: RString) -> Vec<u8> {
    unsafe { data.as_slice() }.to_vec()
}

/// Run a conversion off the GVL and turn its failure into a Ruby exception.
fn convert<T>(
    ruby: &Ruby,
    conversion: impl FnOnce() -> Result<T, anydoc::ConvertError>,
) -> Result<T, Error> {
    match nogvl(conversion) {
        Ok(Ok(converted)) => Ok(converted),
        Ok(Err(error)) => Err(convert_error(ruby, error)),
        Err(_) => Err(Error::new(
            ruby.exception_runtime_error(),
            "anydoc panicked while converting; please report this at \
             https://github.com/firecrawl/anydoc/issues",
        )),
    }
}

/// Raise the subclass that names the failure, carrying the part or limit at
/// fault where the variant knows one. A variant added later raises the base
/// class until it is named here.
fn convert_error(ruby: &Ruby, error: anydoc::ConvertError) -> Error {
    let message = error.to_string();
    let (class, detail) = match &error {
        anydoc::ConvertError::Unsupported(_) => ("UnsupportedError", None),
        anydoc::ConvertError::Malformed { part, .. } => {
            ("MalformedError", Some(("@part", part.clone().into_value_with(ruby))))
        }
        anydoc::ConvertError::Encrypted => ("EncryptedError", None),
        anydoc::ConvertError::ResourceLimit { limit, .. } => {
            ("ResourceLimitError", Some(("@limit", ruby.sym_new(*limit).into_value_with(ruby))))
        }
        anydoc::ConvertError::MissingPart { part } => {
            ("MissingPartError", Some(("@part", part.clone().into_value_with(ruby))))
        }
        // Nothing here reads a file, so this is unreachable in practice.
        anydoc::ConvertError::Io(_) => return Error::new(ruby.exception_io_error(), message),
        _ => ("ConvertError", None),
    };
    build_error(ruby, class, message, detail).unwrap_or_else(|error| error)
}

fn build_error(
    ruby: &Ruby,
    class: &str,
    message: String,
    detail: Option<(&str, Value)>,
) -> Result<Error, Error> {
    let anydoc: RModule = ruby.class_object().const_get("Anydoc")?;
    let class: RClass = anydoc.const_get(class)?;
    // Built as an object so the detail can be set on it, then handed back as
    // the exception to raise.
    let exception: RObject = class.funcall("new", (message,))?;
    if let Some((name, value)) = detail {
        exception.ivar_set(name, value)?;
    }
    Ok(Error::from(Exception::try_convert(exception.as_value())?))
}

/// Detect the format from the content itself: the signature and identity each
/// container specification designates (PDF header, RTF open group, OLE stream
/// names, ZIP package mimetype/content types). Plain-text formats (CSV) carry
/// no signature and return `nil`; so does anything unrecognized.
fn format_from_bytes(ruby: &Ruby, data: RString) -> Option<StaticSymbol> {
    anydoc::Format::from_bytes(unsafe { data.as_slice() }).map(|format| format_symbol(ruby, format))
}

/// The format a bare extension names (no leading dot), matched
/// case-insensitively.
fn format_from_extension(ruby: &Ruby, extension: String) -> Option<StaticSymbol> {
    anydoc::Format::from_extension(&extension).map(|format| format_symbol(ruby, format))
}

/// Convert an in-memory document to Markdown. Without a format, it is
/// detected from the content, which signature-less formats (CSV) have to name
/// explicitly.
fn to_markdown_bytes(ruby: &Ruby, data: RString, format: Option<Symbol>) -> Result<String, Error> {
    let format = parse_format(ruby, format)?;
    let bytes = bytes(data);
    convert(ruby, || anydoc::to_markdown_bytes(&bytes, format))
}

/// Parse an in-memory document into the document model, which also carries the
/// embedded assets. Without a format, it is detected from the content.
fn to_document(ruby: &Ruby, data: RString, format: Option<Symbol>) -> Result<Value, Error> {
    let format = parse_format(ruby, format)?;
    let bytes = bytes(data);
    let parsed = convert(ruby, || anydoc::to_document(&bytes, format))?;
    document::build(ruby, parsed)
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let anydoc = ruby.define_module("Anydoc")?;

    let formats = ruby.ary_new_capa(FORMATS.len());
    for (name, _) in FORMATS {
        formats.push(ruby.sym_new(name))?;
    }
    formats.freeze();
    anydoc.const_set("FORMATS", formats)?;

    // The Ruby side wraps these: it takes keyword arguments, accepts strings
    // where a format symbol is wanted, and reads files.
    let native = anydoc.define_module("Native")?;
    native.define_singleton_method("format_from_bytes", function!(format_from_bytes, 1))?;
    native.define_singleton_method("format_from_extension", function!(format_from_extension, 1))?;
    native.define_singleton_method("to_markdown_bytes", function!(to_markdown_bytes, 2))?;
    native.define_singleton_method("to_document", function!(to_document, 2))?;

    Ok(())
}
