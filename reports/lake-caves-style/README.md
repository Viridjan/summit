# Lake Caves: applying the hand-edited Deep Lake style

The source was `c4_deep_lake.json`, edited in commit `dc4b89a`: height 23 → 12,
irregular ceiling/floor silhouettes, a stepped water basin and a shorter ladder.
That commit also replaced Lake Cave's solid barrier with a shaped breakwall cluster.

This pass applies the natural rock profiles to Roar Tunnel, Lake Cave,
Cave Teeth and Cove Tunnel. Small roof recesses and shallow outcrops break up
straight corridors; Cove Tunnel gains a shallow side shelf on its water basin.
Deep Lake is preserved byte-for-byte, as is the user's Lake Cave breakwall cluster.
Room widths/heights, world positions, every border tile, hazards, platforms,
spawns, notes and collectibles are preserved. Existing compact room sizes and
maze connections make further height reduction inappropriate in this pass.

`before.json` and `after.json` record the source data; `index.html` compares the
full room geometry. Runtime captures show actual Godot artwork. `capture.tscn`
recreates those captures with disposable user data. The overview colors are
geometry annotations, not replacement game artwork.

The initial pass exposed ceiling/ledge conflicts near Cove Tunnel's pool and
Cave Teeth's roof spikes. Those outcrops were removed after the cautious model
showed they blocked forward or return traversal. Water rectangles now span the
complete empty width at each depth, satisfying the real-engine pool checks.

Room JSON remains the authoring source for these editor-style changes. The
original generator explicitly warns that regenerating named rooms discards
manual edits; it was not run or expanded to overwrite those edits.
