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

### Version 0.4.0, released 15-Nov-2024

- feat: make the Homie device id configurable
- fix: upon a reconnect the bridge itself would not re-publish the $state, which
  would leave the device at "lost", which also applied to all children

### Version 0.3.0, released 27-Oct-2024

- fix: update node and property lists from arrays to objects
- feat: homie 4 devices deleted, are now also deleted on v5
- feat: the bridge is now a root device, and the bridged-devices are now children such that
  the overall status is reflected properly and the LWT for the root device works.

### Version 0.2.0, released 13-Oct-2024

- a fix to rate-limit subscriptions to prevent queue overrunning
- don't wait for ready-state to publish
- update homie5 topic to 'homie/5/'
- a change to log forwarded updates (debug level)

### Version 0.1.0, released 15-Jan-2023

- initial release
