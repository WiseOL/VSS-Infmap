# v37: Upstream ACF-3 + ACF-VSS-Extension

This release targets separate installations of ACF-Team/ACF-3 and PERSON00331/ACF-VSS-Extension. The old VSS fork is no longer required. The map BSP and all prior InfMap rendering, camera, water, P2M, track-tool, cleanup and diagnostic fixes remain included.

## Source revisions inspected

- ACF-3: `47b99b456904de86e2c680b30c135057b2e336cc`
- ACF-VSS-Extension: `c95d3f37c21fb2ba1c942767dfe12811a20f9113`

Source snapshots were downloaded on 2026-11-15. Later upstream changes may need another compatibility check.

## Changes

- Current ACF volumetric armor uses ents.FindAlongRay. Only inside ACF ballistic scopes, discovery is segmented into native chunks, wrong-chunk entities are excluded and clone/native references are deduplicated. Ray-plane and per-operation budgets prevent unbounded work. Ordinary addon discovery is unchanged.
- World penetration DigTrace accepts vectors, not a bullet table. It now receives its own scoped conversion. Current ResolveNextObstacle and BeginPenetration paths are included. This also covers ACF fragments through their shared obstacle resolution. HUD and unrelated Lua traces remain untouched.
- Bullet visual and orphan-impact data read the selected crate profile's suffixed network keys. Nonzero profiles retain the generic packet format; default shots and updates retain the existing compact path.
- Current predictable rounds continue to use their server command clock, but all InfMap bullet visuals are server-authoritative through the float-coordinate compatibility channel. Native local effect prediction is disabled on InfMap to avoid quantized origins and duplicate impacts. This trades immediate predicted visuals for waiting on the server packet; ordinary maps are unchanged.
- The monitor times both ACF_OnTick iteration and PlayerTick predicted iteration, including the registered hook. Expiry/reset cleanup also clears owner prediction registries.
- The old global VSS-fork augmented-timer replacement is retired. Current ACF's pause/blocked/progress behavior is retained.
- Existing crew point-velocity G-force and naval waterjet adapters were exercised with actual extension methods. Extension buoyancy retains the same capacity/ratio/type interfaces consumed by the existing water simulation; no thrust or mobility rebalance is included.
- The extension crew oxygen sampler alone gets native/synthetic water contents through a private function environment. Its oxygen-tank and drowning logic remain owned by the extension; util.PointContents is unchanged for other addons.

## Installation and diagnostics

See INSTALL.txt. Run acf_infmap_status in the server console. On this setup, expect Installed, volumetric ray=true, authoritative visuals=true, crew G-force=true, extension oxygen water=true and legacy timer override=false. Optional extension indicators may be false when only stock ACF is installed. Ballistic limits and profiling commands remain available.

## Verification limits

Tests execute current source functions in simulated Garry's Mod environments, including LuaJIT for the extension oxygen sampler. They are not a running Garry's Mod server or multiplayer verification. Existing native HL2 vehicle wheel collision limitations and arbitrary addon render-hook limitations are not newly solved by this release. Keep old ZIPs for rollback.
