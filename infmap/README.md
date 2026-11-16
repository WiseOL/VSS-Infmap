# InfMap with ACF 3 Compatibility

Infinite-map addon for Garry's Mod, supporting upstream [ACF-3](https://github.com/ACF-Team/ACF-3) and the separate [ACF-VSS-Extension](https://github.com/PERSON00331/ACF-VSS-Extension). Includes the `gm_infmap` map.

## Install

Place this folder in `garrysmod/addons/infmap`, replacing the previous version. Install ACF-3, Wiremod, and Contraption Framework separately. Install the VSS extension if used; remove the old VSS fork to avoid duplicate ACF installations.

Keep Prop2Mesh and Tank Track Tool installed separately if used. Restart the server, load `gm_infmap`, and reconnect clients. Run `acf_infmap_status` in the server console to check installation.

## Included

Chunk-aware ACF ballistics and effects, shared entity rendering, Prop2Mesh and Wire FLIR compatibility, camera aiming, crew G-force fixes, water/buoyancy support, naval waterjets, and Tank Track Tool rendering compatibility.

Bullet visuals on InfMap are server-authoritative; local predicted visuals are disabled. Server command-clock simulation is retained. Automatic ballistic overload resets are disabled by default; use `acf_infmap_ballistics status` to inspect performance.

## Latest version

See [CHANGELOG.md](CHANGELOG.md) for the latest changes.

Checked against ACF-3 `47b99b4` and ACF-VSS-Extension `c95d3f3`. Simulated regression checks passed; live multiplayer verification is still needed. Independently drawn addon effects can need additional adapters, and native HL2 vehicle wheel collision with generated terrain is not fully resolved.

## Credits

Based on [Mee12345/gmod-infinite-map](https://github.com/Mee12345/gmod-infinite-map), with compatibility for ACF and the addons listed above. Original license notices are retained in `LICENSE` and `LICENSE-ACF.txt`. Tank Track Tool remains a separate dependency; its installed source is adapted at runtime rather than bundled.
