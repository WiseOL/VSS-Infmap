# Revision 12 - terrain no-collide, transitions, Prop2Mesh

## Terrain collision

InfMap now emulates COLLISION_GROUP_WORLD on active InfMap maps: the physical
engine group is normal, while a consistent custom collision rule ignores
ordinary entities and permits the terrain, planet and OBJ collider classes.
GetCollisionGroup still reports the requested WORLD group. Returning to a
normal group removes this behavior. Server flags are networked for the client;
collision rule changes are invalidated outside physics callbacks. Cross-chunk
entities remain excluded. Ordinary pairwise NoCollide constraints are untouched.
This does not forcibly re-enable collisions disabled via PhysObj:EnableCollisions,
SetNotSolid, or COLLISION_GROUP_IN_VEHICLE. Ordinary maps are untouched because
this module is loaded through InfMap's active-map loader.

## Transition work

Terrain and planet occupancy cleanup requests share one deferred scan per batch,
rather than scanning all entities per departing contraption part. Destination
colliders are still created synchronously. Cleanup checks current occupancy
when it runs so a chunk reoccupied in the same tick is retained. Filtered
collider removals do not recursively request another full occupancy scan.
Server prop_update_chunk skips unchanged chunk assignments, avoiding repeated
hooks, parent traversal, clone deletion and network writes. Collision rules are
invalidated on real changes. The moving-body candidate list uses linear array
construction in the original order rather than repeated table.remove shifts.

Client render-list refresh uses one entity snapshot and linear compaction;
remote entries are deduplicated. Terrain grid copying is skipped when the
visual megachunk has not changed. This reduces repeat work, but synchronous
physics-mesh construction on a newly visited chunk can still cause a spike.
No absolute performance percentage or spike elimination is claimed.

## Prop2Mesh

The supplied Prop2Mesh version creates clientside mesh children, parents them,
then places them using cached GetPos/SetPos calls. InfMap's GetPos is viewer-
relative, so that placement can introduce a whole-chunk offset into the child's
local transform. A PreRender bridge tracks sent_prop2mesh instances, restores
each controller's linkpos/linkang as local transforms, and resolves its chunk
from the actual linked entity's parent root. This avoids relying on delayed
chunk metadata on the P2M container. It refreshes offsets when the viewer or
physical parent changes chunk and preserves newly installed clipping handlers
without capturing an InfMap wrapper as the original draw function. P2M's custom
Draw function is retained for complex meshes in remote chunks.

Meshes, materials, clips, downloads and the Prop2Mesh files on disk are not
rebuilt or replaced. This bridge targets the supplied sent_prop2mesh/controller
API. Other P2M forks/classes have not been tested. Client interpolation and
network arrival delays still require live validation at high speed.

## Installation and validation

Replace the previous combined addon folder in garrysmod/addons. Do not install
v11 and v12 side by side. Fully restart the server and reconnect clients. Keep
v11.zip as the working rollback. The map and prior RAC/camera/crew fixes remain.
No changes to your vehicle/dupe or its steering/suspension are required.

Test a WORLD-group wheel/prop on terrain and on a planet: it should ignore
ordinary props but stay supported by InfMap ground. Pair-specific no-collides
should continue behaving as before. Test several high-speed crossings with a
large contraption and clipped/unclipped P2M controllers, including a controller
linked to a turret or other parent. Compare server frame-time spikes against
v11 with the same route and population. Keep HUD traces unchanged.

Mocked Lua regressions cover collision filtering and group restoration,
800-to-1 cleanup batching, retained/reoccupied chunks, 600 redundant network
updates, P2M local transforms and wrapper ownership, and client list filtering.
Prior gun/radar/effect, RAC, camera, mobility-preservation and crew G-force
regressions also passed. No live Garry's Mod test or frame-time benchmark was
available in this workspace.

Engine collision-group definitions and custom collision requirements:
https://wiki.facepunch.com/gmod/Enums/COLLISION_GROUP
https://wiki.facepunch.com/gmod/GM:ShouldCollide
