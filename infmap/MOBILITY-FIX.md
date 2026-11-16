# Revision 8: drivetrain physics repairs

Two defects were found in the supplied InfMap source:

1. Chunk teleport helpers save/restore linear velocity, but ordinary entities do
   not preserve angular velocity through SetPos and the subsequent SetAngles
   restoration. Losing wheel spin can change the gearbox's measured wheel RPM
   and requested engine load. The helpers now preserve both linear and angular
   velocity around those operations.
2. PhysObj.CalculateForceOffset wraps the application point independently using
   localize_vector. The native call instead needs the point relative to the
   physics body's chunk. These differ when the body and point straddle a boundary,
   which produces an incorrect lever arm and angular impulse. The conversion now
   subtracts the body's chunk offset, matching InfMap's ApplyForceOffset path.

These changes repair existing InfMap physics conversions; they do not replace
ACF torque curves, throttle, gearing, redline, engine timing, or angular direction
transforms. The gun/radar-only trace scope and effect cleanup from v7 remain.
No HUD/Starfall trace modifications are added.

## Checks performed

Actual extracted teleport helpers were run with mocked physics calls that reset
velocity during teleports. The original helpers lose wheel angular velocity in
that fixture; the patched helpers preserve spin and linear velocity through 100
teleports and angle restores. The actual patched CalculateForceOffset wrapper
was checked for positive, negative, zero and missing chunk offsets, and a force
point extending into a different chunk. Force vectors remain unchanged.

These checks establish the helper behavior, not a reproduction of your vehicle
in Source physics. No live GMod server was available. If RPM is incorrect with
the gearbox disconnected near spawn, that needs a separate engine/configuration
investigation; this revision does not claim to repair that unverified case.

## Install and retest

Replace the previous combined addon folder completely. Restart the server and
reconnect clients, then spawn a fresh copy of the contraption. Compare:

- Engine alone near spawn, with gearbox disconnected: idle/full-throttle RPM.
- Linked vehicle near spawn: RPM, wheel speed, and stability.
- The same vehicle crossing several positive/negative chunk boundaries.

If flipping continues, record whether it starts precisely at a boundary, whether
it also happens while coasting with the engine off, and any Lua/physics errors.
For a standalone RPM issue, provide engine model, throttle, displayed RPM and
expected RPM.

Relevant native API behavior: direction vectors are rotation-only, whereas
positions require a frame offset:
https://wiki.facepunch.com/gmod/PhysObj:LocalToWorldVector
