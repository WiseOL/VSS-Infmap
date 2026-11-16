# Camera aim repair - revision 10

ACF controller / AI/O: its server modules/camera.lua caches util.TraceLine and
uses a 99999-unit ray to calculate turret HitPos. That call site now uses the
existing bounded chunk splitter, returning a global hit position. Other
controller modules, client HUD rangefinders, and client camera collision
traces keep their existing behavior. No broad controller trace scope is used.

TFE/SafeNet: InfMap exposes client coordinates relative to the viewer chunk,
while server entity positions are global. Sending localDidhit.HitPos directly
therefore introduces an offset of 20000 units per crossed chunk. The client
Starfall compile hook recognizes this specific camera source pattern and wraps
its SafeNet Aim vector serialization to add the viewer chunk offset. SafeNet
already writes floats, so its server decoder and wire outputs stay unchanged.
Conversion occurs before SafeNet queues the payload. The addon changes neither
the saved dupe nor its embedded source. Relative-coordinate repaired scripts
are excluded to prevent double conversion. Other camera scripts or customized
message/variable names are not automatically recognized by this narrow bridge.

The bridge installs at StarfallPostInstanceCompile; restart/reconnect and
respawn existing chips. The client prints:
[ACF InfMap] TFE camera aim coordinate bridge installed.

Validation: mocked GMod runtime executed the actual VSS ACF server camera
module, checked global aim positions in positive, negative and distant chunks,
checked another-chunk target collision, verified unchanged HUD routing, and
checked TFE payloads across chunk changes and queued sends. Existing gun,
radar, bullet-effect and RAC timing regressions were also run.
No live Garry's Mod server was available for testing.

On the server, test AI/O and TFE separately: aim at a nearby fixed target, drive
across several chunk boundaries in both directions, then repeat aiming near a
boundary with the target across it. If the turret still freezes, capture Lua
errors and specify which camera system was active. This patch addresses the
identified coordinate/ray failures; unrelated slew or controller state faults
cannot be ruled out without a live reproduction.
