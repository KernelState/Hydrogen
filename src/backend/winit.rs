use anyhow::Result;
use smithay::{
    backend::{
        renderer::gles::GlesRenderer,
        winit::{self, WinitGraphicsBackend},
    },
    output::{self, Output}, reexports::{wayland_protocols::xdg::shell::client::xdg_toplevel::State, wayland_server::DisplayHandle},
};

pub struct Winit {
    output: Output,
    backend: WinitGraphicsBackend<GlesRenderer>,
}

impl Winit {
    pub fn new(dh: &DisplayHandle) -> Result<Self> {
        let (mut backend, winit) = winit::init().unwrap();
        let output = Output::new(
            "winit".to_string(),
            smithay::output::PhysicalProperties {
                size: (0, 0).into(),
                subpixel: smithay::output::Subpixel::Unknown,
                make: "Smithay".to_string(),
                model: "winit".to_string(),
            },
        );
        let _global = output.create_global::<State>(dh);
        let mode = output::Mode {
            size: backend.window_size(),
            refresh: 60,
        };
        output.change_current_state(
            Some(mode),
            Some(smithay::utils::Transform::_180),
            None,
            Some((0, 0).into()),
        );
        output.set_preferred(mode);

        Ok(Self {
            output: output,
            backend: backend,
        })
    }
}
