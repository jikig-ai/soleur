# Phase 0 — MEASURED proof (the one unproven link)

Claim under test: `docker login` with NO `--config` flag honors the `DOCKER_CONFIG`
env var as the config **directory**, persisting the credential to
`$DOCKER_CONFIG/config.json`. (EROFS + `/mnt/data`-writable are already proven from
prod telemetry + existing `/mnt/data/workspaces` writes — cited, not re-run.)

Environment: docker 29.4.3, throwaway local `registry:2`, no `--config` flag.

```
$ TMPCFG="$(mktemp -d)"                         # a DIRECTORY, not a file
$ docker run -d --name reg -p 5999:5000 registry:2
$ DOCKER_CONFIG="$TMPCFG" docker login localhost:5999 -u proofuser --password-stdin <<<"proofpass"
WARNING! Your credentials are stored unencrypted in '/tmp/tmp.H3tmnHwIZp/config.json'.
Login Succeeded                                  # rc=0
$ test -f "$TMPCFG/config.json" && echo HONORED
HONORED
$ grep -o '"localhost:5999"' "$TMPCFG/config.json"
"localhost:5999"                                 # auths entry persisted under $DOCKER_CONFIG
$ ls -la "$TMPCFG/config.json"
-rw------- 1 jean jean 86 ...                     # 0600, under $DOCKER_CONFIG, NOT ~/.docker
```

Conclusion: exporting `DOCKER_CONFIG=/mnt/data/deploy-docker` relocates the
credential-persist target (and, since no login site passes `--config`, ALL login
sites + the derived cosign mount) onto a ReadWritePath → the EROFS
credential-persist failure is eliminated.
