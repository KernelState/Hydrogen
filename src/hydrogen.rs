use anyhow::Result;
use smithay::reexports::wayland_server::DisplayHandle;

use crate::backend::{Backend, winit::Winit};

pub struct Hydrogen {}

impl Hydrogen {
    pub fn new() -> Self {
        Self {}
    }
}

pub struct State {
    hydrogen: Hydrogen,
    backend: Backend,
}

impl State {
    pub fn new(dh: &DisplayHandle) -> Result<State> {
        Ok(State {
            hydrogen: Hydrogen::new(),
            backend: Self::init_backend(dh)?,
        })
    }
    pub fn init_backend(dh: &DisplayHandle) -> Result<Backend> {
        Ok(Backend::Winit(Winit::new(dh)?))
    }
}
