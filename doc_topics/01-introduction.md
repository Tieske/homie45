# 1. Introduction

A Homie v4 to Homie v5 bridge application. The v4 devices will be collected
and converted and published as v5 devices. Any values `set` on the v5 version
will be passed back to the v4 version.

The main application is the CLI script `homie45bridge`.

## 1.1 Caveats

Using a Eclipse Mosquitto mqtt server required changing the following setting:

```
#max_queued_messages 100
max_queued_messages 10000
```

When the bridge starts it will subscribe to all devices it finds, which can
create a huge queue. Hence this setting must be increased to prevent overrunning
the default value of 100.
