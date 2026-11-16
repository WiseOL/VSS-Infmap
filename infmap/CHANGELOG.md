# Latest changes - v37

- Updated for upstream ACF-3 with the separate ACF-VSS-Extension; the old VSS fork is no longer required.
- Added chunk-aware volumetric armor discovery and corrected current ballistic penetration handling.
- Added selected ammo profile support to bullet visuals and impact data.
- Routed bullet visuals through the chunk-safe server channel while retaining server command-clock simulation.
- Added predicted-round processing to ballistic monitoring and cleanup.
- Removed the old fork-specific timer override, preserving current ACF reload pause/progress behavior.
- Added synthetic-water detection for the extension's crew oxygen logic and checked its crew G-force and naval waterjet methods.

Existing InfMap, rendering, Prop2Mesh, Wire, camera, water, and track-tool compatibility remains included. Packaging is simplified to the addon, this changelog, the README, and required license notices.
