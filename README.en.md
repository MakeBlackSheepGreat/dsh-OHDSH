# HDSH

HDSH is a HarmonyOS Next implementation of the DSH runtime. The `entry` module owns the application and device integration, while `ngf_framework` provides reusable native infrastructure.

## Current Status

The application can start the official DSH WebUI on HarmonyOS devices. `EntryAbility` loads `pages/hdsh/HdshWebPage`, prepares the DSH, busybox, and pnpm runtime inside the app sandbox, starts the local DSH service, and loads `http://127.0.0.1:3080` through ArkWeb.

Current verified delivery facts:

- Bundle name: `com.hdsh.agentic`
- Target and compatible SDK: HarmonyOS `6.1.0(23)`
- Declared device types: phone, tablet, 2in1, car, tv, wearable
- Device regression: visible home page, normal default window ratio, no PC breakpoint blank screen
- Filesystem search fallback: system grep is used when ripgrep is unavailable, with ERE regex semantics preserved
- Public sources contain no signing materials, credentials, or machine-local environment files

The current release focuses on the DSH WebUI runtime loop and device adaptation. The native ArkTS harness, settings, tools, and MCP work continue according to the [migration plan](docs/migration-plan.md).

## Repository Layout

```text
HDSH/
├── entry/                 # Application layer, Ability, ArkWeb page, and runtime bridge
├── ngf_framework/         # Reusable HarmonyOS framework
├── scripts/               # Runtime preparation and device regression scripts
├── docs/                  # Architecture, migration, build, and change records
├── .rules/                # Shared Agent engineering rules
├── .agent-rules/          # HDSH project rules and bug log
└── AGENTS.md              # Workspace collaboration rules
```

`entry/src/main/resources/rawfile/dsh/`, `busybox/`, `pnpm/`, and native runtime files are generated or downloaded by preparation scripts and are ignored by Git. This keeps large binaries, signing materials, and machine-specific data out of the public repository.

## Development

1. Open the repository in DevEco Studio.
2. Prepare the runtime files:

```bash
bash scripts/prepare-dsh-env.sh 0.1.0-rc.7
bash scripts/fetch-busybox.sh
bash scripts/fetch-pnpm.sh
HDSH_LIBNODE_URL=<approved-libnode-url> bash scripts/fetch-libnode.sh
```

3. Configure a local development signature in DevEco Studio. Keep signing files on the local machine.
4. Build the `entry` module with Hvigor and install it on a device.
5. Run the device regression script with an explicit target:

```bash
bash scripts/ui-test-phone.sh 1 <hdc-target>
```

The script intentionally requires an explicit device target so a device identifier is never embedded in the project.

## Documentation

- [Migration plan](docs/migration-plan.md)
- [busybox runtime](docs/dsh-busybox-linux-env.md)
- [NGF framework status](docs/NGF_FRAMEWORK_STATUS.md)
- [Change log](docs/CHANGELOG.md)
- [Agent collaboration rules](AGENTS.md)

## License

MIT, see [LICENSE](LICENSE).
