# Revision 11 - crew G-force continuity

Problem: the VSS fork twice differentiates crew global position each sample.
A discontinuity or temporarily stale child transform during an InfMap rebase
can therefore be interpreted as acceleration. The reported live symptom is
crew G-force/strain increasing during crossings; that exact live failure has
not yet been captured or reproduced in Garry's Mod here.

The server-only patch identifies crew-owned trackers when EnforceGForces runs.
It calculates point velocity from the top parent's physics body using the raw
GetVelocityAtPoint API and explicitly composed local child transforms. This
includes rigid-body rotation. Relative crew/turret motion contributes its
local-position derivative, rotated into world axes. G-force is the velocity
difference divided by sample time and the fork's gravity magnitude. Source
coordinate rebasing cannot itself enter this velocity difference.

Only crew trackers on active InfMap use this path. Other ACF trackers delegate
to the original helper. The first successful sample and changes of physical
root prime the history. If no suitable body/native API exists, the original
helper is used. Existing tracker vector objects are updated in place.

This changes the acceleration measurement method for InfMap crew throughout
driving, not just on the transition tick. It does not discard a time window
around crossings, clear accumulated strain, change stamina recovery, alter
G-force thresholds, or apply any vehicle forces. Actual velocity impulses at a
boundary remain visible. The original tick/sample cadence is retained.

Tests in a mocked Lua/GMod API verified constant physical velocity across large
coordinate jumps gives no G spike; acceleration, braking and impacts at a
boundary still register; multi-tick samples use the correct interval; rigid
rotation and relative turret motion contribute acceleration; unrelated trackers
and ordinary maps retain original behavior. Other existing compatibility
regressions were rerun. A live-server crossing test remains required.

Install by replacing the combined addon folder, fully restarting the server,
and reconnecting. Use original dupes. The server prints:
[ACF InfMap] Crew G-force point-velocity tracking installed.

Compare the crew GForce and Stamina Wire outputs while crossing a boundary at
steady speed, then braking/turning on each side. False crossing-only spikes
should disappear while genuine maneuver G-forces remain. Do not expect recovery
of strain already accumulated before installing. Keep v10 as a rollback.
