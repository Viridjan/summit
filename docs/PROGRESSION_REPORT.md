# Progression explorer

## From the World Editor

Select **Tools → Progression** in the desktop source version (Python 3 must be installed).
The current world layout is saved before analysis. A separate Python process
copies the world into a snapshot and analyzes that copy, allowing editing to
continue. Changes made after the snapshot require another run.

The interactive HTML viewer opens in your browser when ready. It is not embedded
in the Godot viewport. **Tools → Open progression report** reopens the latest completed
report during the session. Leaving the editor does not cancel the running job;
returning to it checks the result. Only one analysis runs at a time.

Results live in `user://progression/<run>/`: `index.html`, `snapshot/`,
`status.json`, and `analysis.log`. Failures appear in the editor status; the log
contains diagnostic details. This workflow requires the source scripts on disk
and is disabled in web builds.

## Using the report

- **Progression** shows ability and boss conditions. Equivalent condition sets
  share one station; colored paths show the action taken.
- **Route choices** independently groups physical routes by region and boss gates.
- Clicking an earlier progression step first reroutes through it while preserving
  the current map. Clicking it again shows that step on the map. Selecting a next
  step preserves the previous route wherever compatible.
- **Unplaced** hides conditions without pickups. **Unavailable** hides steps that
  cannot yet be reached. Missing upgrades become background assumptions, so
  placed, reachable bosses such as Ape and Guardian remain available. Both
  switches start off and apply only to Progression.
- Hover controls and stations for explanations. Expand **Key**, **Route**, or
  **Rooms** for details without crowding the map.

Reachability is an analysis of the world data and movement model, rather than a
recorded playthrough. Hidden assumptions are identified in the room details.

## Command line

```sh
python3 tools/progression.py
python3 tools/progression_job.py --world /absolute/world/directory --output /absolute/report/directory
```

The first command updates `reports/progression.html` for the default story world.
The second uses the same snapshot/status workflow as the editor. Full-world
analysis can take several minutes.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_progression_*.py'
godot --headless --path . res://tests/progression_editor.tscn
```

The editor test exercises duplicate-job rejection, completion and failure states,
reopening reports, and a real background Python run against a disposable world.
`tests/progression_browser_checks.js` supplies browser assertions for the generated
page, including navigation, filters, tabs, and escaped room titles.
