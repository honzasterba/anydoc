# frozen_string_literal: true

require "mkmf"
require "rb_sys/mkmf"

# Builds ext/anydoc into lib/anydoc/anydoc.<dlext>, whose Init_anydoc entry
# point is the #[magnus::init] function in src/lib.rs.
create_rust_makefile("anydoc/anydoc") do |ext|
  ext.profile = ENV.fetch("RB_SYS_CARGO_PROFILE", "release").to_sym
end
