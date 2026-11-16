v37 targets upstream ACF-Team/ACF-3 plus optional PERSON00331/ACF-VSS-Extension. The VSS fork is no longer required. Read INSTALL.txt and UPSTREAM_V37.md; earlier notes below are historical.

v36: Tank Track Tool automatic/legacy compatibility included. Keep the track addon installed. See TANK_TRACKS_V36.txt.

v35: Shared entity rendering replaces class-specific checks. See UNIVERSAL_RENDER_V35.txt.

v34: Wire entity models now use live chunk rendering. See WIRE_RENDER_V34.txt.

v33: ACF entities now share live chunk rendering with props. See ACF_RENDER_V33.txt.

v32: Live native-frame rendering now also covers ordinary physics props. See PROP_RENDER_V32.txt.

REVISION 31: see V31-P2M-REPORT-CORRECTION.txt; P2M culling/draw pose agreement and native parent-local root composition. Addons layout; restart/reconnect.

REVISION 30: see V30-P2M-LIVE-POSE.txt; draw-time chunk offsets and explicit basic/split controller poses. Extract infmap into garrysmod/addons; full restart/reconnect.

REVISION 28: see V28-P2M-WIRE-FLIR.txt; stable render callbacks, complete cross-chunk P2M geometry and Wire FLIR integration. Full restart and client reconnect required.

REVISION 27: see V27-FIRING-PROFILER.txt; server/client firing captures for selecting measured performance optimizations.

REVISION 26: see V26-BULLET-EXPIRY.txt; default per-round age/range expiry and client metadata cleanup.

REVISION 25: see V25-HL2-VEHICLES.txt; airboat flotation adapter and HL2 wheel diagnostics. Wheel collision remains unresolved.

REVISION 24: see V24-NAVAL-DRAG.txt; lower adjustable horizontal naval resistance, independent of vertical buoyancy damping.

REVISION 23: see V23-COMPARTMENT-DAMPING.txt; buoyancy damping uses whole-craft mass and a shared compartment budget.

REVISION 22: see V22-E2-HOLOGRAMS.txt; original E2 holoPos scripts supported through an InfMap-side hologram positioning bridge.

REVISION 21: see V21-ALL-PROPS-AND-TOOL.txt for all-material prop buoyancy and Improved Buoyancy Tool support.

REVISION 20: see V20-WATER-AND-JETS.txt; restores original water material with client downloads/fallback, adds VSS jet water detection and stronger compartment damping.

REVISION 19: see V19-BUOYANCY.txt for displacement-based prop and VSS compartment water forces; supersedes v15 buoyancy.

REVISION 18: see V18-WATER-MATERIAL.txt; supersedes the v17 direct Hammer material assignment.

REVISION 17: see V17-BALLISTICS-MONITOR.txt for superadmin monitoring, opt-in ballistic resets and water material.

REVISION 16 - HEAVY-FIRING OVERHEAD
Replace the previous combined folder, restart fully and reconnect all clients.
See V16-FIRING-PERFORMANCE.txt.

REVISION 15 - CUSTOM WATER PROP BUOYANCY
See V15-WATER-FIX.txt. Replace the previous addon folder, restart fully and reconnect.

REVISION 14 - EXPLOSIVE IMPACT EFFECT DELIVERY
See V14-EXPLOSION-FIX.txt. Replace the previous addon folder, restart fully and reconnect.

REVISION 13 - PHYSGUN REGRESSION FIX
See V13-PHYSGUN-FIX.txt. Replace the previous addon folder, fully restart and reconnect.

Revision 12 adds WORLD-group terrain collision, batched collider cleanup,
redundant transition suppression, render-list compaction/deduplication and
Prop2Mesh parent-local transform/chunk syncing. See V12-CHANGES.md. All prior
compatibility fixes are included; v11 is retained as rollback. Live testing
remains necessary, especially collision behavior and high-speed P2M rendering.

Revision 11 adds InfMap-only crew point-velocity G-force measurement to avoid
position-differencing spikes at chunk transitions. Regular-map crew behavior
is unchanged. No vehicle force, speed limit or stamina balance setting changed.
See CREW-GFORCE-FIX.md. Revision 10 is retained as a rollback archive.

Revision 10 adds ACF controller / AI/O server camera aim traces and a targeted
coordinate bridge for the TFE/SafeNet camera system in the supplied dupe.
This supersedes earlier statements that all camera paths are untouched.
Client HUD, general Starfall traces and camera clipping remain unchanged.
See CAMERA-AIM-FIX.md for scope and live-server validation steps.

Revision 9 bundles the RAC timing repair and gates it on the active InfMap API.
It does not activate that repair on ordinary maps. Remove any standalone
acf_rac_timing_fix addon and restart after replacing the combined addon folder.
The original 30-round timing regression and patched interval checks are recorded
in RAC-TIMING-TEST-RESULTS.txt. No live server playtest was performed.

Revision 8 adds wheel-spin preservation across chunk teleports and corrects force-point conversion relative to the physics body. See MOBILITY-FIX.md for tests and limits. Gun/radar-only trace scope remains as described below.

# InfMap + ACF 3 compatibility, revision 7

The combined ZIP contains the gm_infmap map, original InfMap files/assets, and
this patch. ACF 3 and its dependencies remain separate.

## Replace, do not merge
Remove the old combined addon folder and standalone compatibility patches, then
extract the new infmap_acf3_combined folder into garrysmod/addons/. If your previous
folder was named infmap, replace that old folder too. Do not leave multiple copies.
The removed !infmap_acf_crew_los.lua file must not remain from a previous version.
Fully restart the server and reconnect all clients. This clears existing leaked
effects and cached functions; Lua refresh alone does not undo older overrides.

Select gm_infmap. Server console: acf_infmap_status.
Server console: acf_infmap_trace_stats reports only added chunk-trace work.

## Trace scope
Only server ACF gun and radar call sites opt into additional chunk segmentation.
Gun projectile flight and penetration opt in when Bullet.Gun is an acf_gun.
Locally cached gun/radar trace functions work through an early dispatcher.
The dispatcher resolves the source once per reused trace-config table using a
weak cache, then selects either the chunk tracer or the previous InfMap trace.
No per-entity stack scans or entity-list scans are added by the chunk tracer.

HUD, Starfall, cameras, tools, autoloaders, crew scans, and unrelated ACF/sensor
traces retain their previous paths. ACF.trace itself is not replaced. The crew
LOS callback alteration from v5/v6 is removed. ACF's global line-to-hull workaround
and original InfMap trace behavior remain in place for those unaffected callers.
No client util trace functions are changed by this patch.

Same-chunk gun/radar checks use one native trace. Cross-chunk rays preserve
output tables, masks, hull dimensions, filter/clone-parent mapping and fractions.
Non-finite rays and more than 256 boundary planes are rejected. Scoped gun flight
calls have a 4096-segment work limit with scope restoration after errors.

## Effect cleanup repair
Previously, every bullet update allocated a temporary Lua effect and older
projectile effects could refer to a new bullet that reused their index. Normal
server bullet removal also did not explicitly clean up the custom client effect.

V7 handles penetration/ricochet/end messages in place, ignores orphan updates,
notifies clients on server bullet removal, and only allows an effect to own the
exact matching bullet. Emitters are finished during cleanup. A housekeeping pass
also removes invalid or expired custom effects.

Custom projectile visuals have a 15-second wall-clock lifetime and a maximum of
256 active or pending custom projectile effects per client. Slots are reserved
before calling util.Effect, so delayed engine initialization cannot oversubscribe
the budget. Generation tags reject stale queued initializations after removal. When the visual budget is full,
additional tracer visuals are omitted; server ballistics/damage are unchanged.
Muzzle effects can use the engine slots freed by projectile cleanup. This does
not raise GMod's Lua effect limit or suppress its warning. Other addons can still
consume the shared effect pool. Non-ACF util effects retain their original path.

## Verification and limits
Mocked Lua integration tests pass for real ACF.trace barrel/radar calls, cached
gun traces, original HUD/tool paths, 10,000 same-chunk gun checks, 5,000 in-place
bullet updates without additional allocations, index reuse, explicit removal,
visual capacity and wall-clock expiration while the ACF clock is stopped.

There is no running GMod server here, so these are not live engine/performance
tests. Please retest firing and radar detection after replacing the folder and
restarting. Destination terrain colliders must already exist. Wide hulls touching
adjacent chunks without their centers crossing retain InfMap limitations.
The patch is based on ACF commit 6173764cadbe81df2d34be834d16ff24efb52332.

Original InfMap license is license.md in the combined addon. The custom bullet
effect is derived from ACF 3 under LICENSE-ACF.txt.
