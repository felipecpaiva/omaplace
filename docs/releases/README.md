# Releases

Rule (same as omahop): every tag ships with a feature highlight. A release is not done until all of this exists.

| Item | Where |
|---|---|
| Release notes, written for users: one-line hook, what is new, what was fixed, how it was checked, known limits, how to install or update | `docs/releases/vX.Y.Z.md` (this is also the GitHub release body) |
| Feature GIFs for what the release adds (a short captioned GIF and MP4 per feature, recorded on a real screen), embedded in the notes and in the README | `branding/demo/<feature>.gif` |
| Highlight media of the headline feature: a screenshot (`.png`) or a short recording (`.gif` plus `.mp4`) made on a real screen, with made-up names and nothing private | `branding/highlights/vX.Y.Z-<feature>.png` or `.gif` |
| `manifest.json` version | `"version": "X.Y.Z"` |
| Settings app pin: the tag, file name and sha256 of the release package, so a reviewed commit names exactly one package. Order: create the release and its package first, `sha256sum` the downloaded asset, put the three values in `app/PINNED`, commit (this is the commit the marketplace request names). Never point it at `latest` | `app/PINNED` |
| The git tag, annotated | `git tag -a vX.Y.Z -m "..."`, pushed |
| The GitHub release for that tag, with the notes as body | `gh release create vX.Y.Z --notes-file docs/releases/vX.Y.Z.md` (only once the repo is public) |
| README status line and the live results | `README.md`, `docs/batch-log/` |

Order: finish the code and the live run, record the GIFs and the highlight, write the notes, run `bash tests/run-all.sh`
and `bash tests/scrub.sh`, commit and push, tag, push the tag, create the release. Never mention which tool made
anything in the notes. Posting about a release anywhere else (social, forum, marketplace) is Felipe's call; drafts live
in `docs/launch/`.

Media rules: no private content (window titles, scene names from real use, hostnames, paths, other apps open, real
notifications). Use made-up scene names and harmless apps (a terminal, Omacalc). Never create virtual monitors on a dev
machine: use an empty desktop. Before committing a recording, look at a contact sheet of its frames
(`ffmpeg -i branding/demo/<name>.mp4 -vf "fps=0.7,scale=400:-1,tile=4x4" -frames:v 1 sheet.png`).
