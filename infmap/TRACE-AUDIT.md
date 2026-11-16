# Revision 7 scope and regression checks

| Caller | Added chunk processing |
| --- | --- |
| ACF gun barrel and breech checks | Yes, including cached local functions. |
| ACF radar LOS | Yes, including its cached ACF.trace function. |
| ACF gun bullet flight / penetration | Yes when Bullet.Gun is an acf_gun. |
| HUD / Starfall million-unit aim rays | No. Original path. |
| Cameras, tools, autoloaders, crew scans, unrelated sensors | No. Original path. |
| Client traces | No. Original path. |

Only the gun/radar dispatch is new. InfMap and ACF already modify util traces;
this revision preserves their pre-patch behavior for the other callers above.
The v5 crew LOS callback modification has been removed.

Tests in work/test_v7.py (development workspace) exercise actual ACF.trace and
ACF's line-to-hull workaround with a mocked engine. They compile gun/radar/HUD
callers under their source paths to verify routing, then verify lifecycle through
the real receiver and custom EFFECT code. See TEST-RESULTS.txt.

The cache assumes a trace-config table belongs to a stable caller. Scoped gun
flight overrides the cached decision while active. More than 256 boundary planes
raises an error before the loop; gun combat scopes stop after 4096 native segments.
These guards do not control native engine cost, unrelated upstream loops, or
existing InfMap entity scans. Stats are counts, not CPU profiling.

Live retest: spawn/update the same contraption, fire repeatedly, check radar LOS
across chunks, check HUD behavior, and confirm that effect-limit warnings stop.
A full server restart and client reconnect are required to clear prior overrides
and effects. No live server test was possible in the development workspace.
