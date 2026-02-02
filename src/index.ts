#!/usr/bin/env bun
import { defineCommand, runMain } from "citty"
import convert from "./commands/convert"
import install from "./commands/install"
import listCommand from "./commands/list"

const main = defineCommand({
  meta: {
    name: "compound-plugin",
    version: "0.1.0",
    description: "Convert Claude Code plugins into other agent formats",
  },
  subCommands: {
    convert: () => convert,
    install: () => install,
    list: () => listCommand,
  },
})

runMain(main)
