//! Running a conversion with the GVL released.

use std::ffi::c_void;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr::null_mut;
use std::thread::Result;

/// Run `f` with the GVL released, so other Ruby threads keep running while a
/// document converts. `f` must not touch the Ruby VM in any way.
///
/// No unblocking function is registered: a conversion is a bounded CPU-bound
/// call with no handle to interrupt, so signals and `Thread#kill` are handled
/// once it returns.
///
/// A panic is caught here rather than left to unwind through the C frame,
/// which would abort the process; the caller turns it into a Ruby exception.
pub fn nogvl<F, R>(f: F) -> Result<R>
where
    F: FnOnce() -> R,
{
    unsafe extern "C" fn call<F, R>(arg: *mut c_void) -> *mut c_void
    where
        F: FnOnce() -> R,
    {
        // `arg` is the caller's `f` slot, which outlives this call. Ruby calls
        // the function exactly once, so the closure is there to take.
        let f = unsafe { &mut *arg.cast::<Option<F>>() }.take().expect("called once");
        Box::into_raw(Box::new(catch_unwind(AssertUnwindSafe(f)))).cast()
    }

    let mut f = Some(f);
    let result = unsafe {
        rb_sys::rb_thread_call_without_gvl(
            Some(call::<F, R>),
            (&raw mut f).cast(),
            None,
            null_mut(),
        )
    };
    // The callback boxed its result; take ownership of it back.
    *unsafe { Box::from_raw(result.cast::<Result<R>>()) }
}
