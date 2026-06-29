use std::fmt::Display;

use Hydrogen as hydrogen;
use anyhow::Result;
use smithay::reexports::calloop::EventLoop;

fn main() -> Result<()> {
    init_logging();
    tracing::info!("Initialized profiler");

    let mut event_loop = EventLoop<State>::try_new()?;
    let display = Display<State>::new();

    let state = hydrogen::hydrogen::State::new(display.handle())?;
    tracing::info!("Initialized hydrogen state");

    Ok(())
}

fn init_logging() {
    if let Ok(env_filter) = tracing_subscriber::EnvFilter::try_from_default_env() {
        tracing_subscriber::fmt().with_env_filter(env_filter).init();
    } else {
        tracing_subscriber::fmt().init();
    }
    tracing_subscriber::registry()
        .with(tracing_tracy::TracyLayer::default())
        .init();
}
