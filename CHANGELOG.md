# CHANGELOG

#### Releasing new versions

- create a release branch
- update the changelog below
- update version and copyright-years in `./LICENSE` and `./src/homie45/init.lua` (in doc-comments
  header, and in module constants)
- create a new rockspec and update the version inside the new rockspec:<br/>
  `cp homie45-scm-1.rockspec ./rockspecs/homie45-X.Y.Z-1.rockspec`
- test: run `make test` and `make lint`
- clean and render the docs: run `make clean` and `make docs`
- commit the changes as `release vX.Y.Z`
- push the commit, and create a release PR
- after merging tag the release commit with `vX.Y.Z`
- upload to LuaRocks:<br/>
  `luarocks upload ./rockspecs/homie45-X.Y.Z-1.rockspec --api-key=ABCDEFGH`
- test the newly created rock:<br/>
  `luarocks install homie45`

### Version 0.2.0, released 13-Oct-2024

- a fix to rate-limit subscriptions to prevent queue overrunning
- don't wait for ready-state to publish
- update homie5 topic to 'homie/5/'
- a change to log forwarded updates (debug level)

### Version 0.1.0, released 15-Jan-2023

- initial release
