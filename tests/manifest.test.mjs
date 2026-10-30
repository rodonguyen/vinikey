// manifest.json and the QML agree on the plugin id, and the repo passes the checks
// `omarchy plugin validate` makes (that tool only exists on Omarchy, not in CI).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync, lstatSync, existsSync } from "node:fs"
import { join } from "node:path"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("..", import.meta.url))
const read = (name) => readFileSync(join(root, name), "utf8")
const manifest = JSON.parse(read("manifest.json"))

test("required fields are present", () => {
  for (const field of ["id", "name", "version", "kinds", "entryPoints"])
    assert.ok(manifest[field], `manifest.${field} is missing`)
})

test("id is valid and not in the reserved omarchy.* namespace", () => {
  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
  assert.ok(!manifest.id.includes(".."))
  assert.ok(!manifest.id.startsWith("omarchy."))
})

test("version is semver", () => {
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/)
})

test("entry points exist", () => {
  for (const file of Object.values(manifest.entryPoints))
    assert.ok(existsSync(join(root, file)), `${file} is missing`)
})

test("QML module names and IPC targets use the manifest id", () => {
  const id = manifest.id
  const bar = read("BarWidget.qml")
  const panel = read("Panel.qml")
  assert.match(bar, new RegExp(`moduleName: "${id.replace(/\./g, "\\.")}"`))
  assert.match(bar, new RegExp(`target: "${id.replace(/\./g, "\\.")}"`))
  assert.match(panel, new RegExp(`moduleName: "${id.replace(/\./g, "\\.")}"`))
  assert.match(panel, new RegExp(`ipcTarget: "${id.replace(/\./g, "\\.")}"`))
})

test("README commands use the manifest id", () => {
  const readme = read("README.md")
  assert.ok(readme.includes(`omarchy plugin remove ${manifest.id}`))
  assert.ok(readme.includes(`omarchy bar move ${manifest.id}`))
})

test("no symlinks (the plugin validator rejects them)", () => {
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      if (name === ".git" || name === "node_modules") continue
      const path = join(dir, name)
      const st = lstatSync(path)
      assert.ok(!st.isSymbolicLink(), `${path} is a symlink`)
      if (st.isDirectory()) walk(path)
    }
  }
  walk(root)
})
