// Strings.js: both languages complete, fallbacks, and every key the QML asks for exists.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const root = new URL("..", import.meta.url)
const read = (name) => readFileSync(new URL(name, root), "utf8")

// Strings.js is a QML JavaScript library; without the pragma it is plain JS.
const ctx = vm.createContext({})
vm.runInContext(read("Strings.js").replace(/^\.pragma library\s*$/m, ""), ctx)
const { table, tr } = ctx

test("vi and en define the same keys", () => {
  assert.deepEqual(Object.keys(table.vi).sort(), Object.keys(table.en).sort())
})

test("no string is empty", () => {
  for (const lang of ["vi", "en"])
    for (const [key, value] of Object.entries(table[lang]))
      assert.ok(typeof value === "string" && value.trim() !== "", `${lang}.${key} is empty`)
})

test("tr picks the language, falls back to vi, then en, then the key", () => {
  assert.equal(tr("en", "typing"), table.en.typing)
  assert.equal(tr("vi", "typing"), table.vi.typing)
  assert.equal(tr("fr", "typing"), table.vi.typing)
  assert.equal(tr("vi", "no-such-key"), "no-such-key")
  table.vi.__onlyEn = undefined
  table.en.__onlyEn = "english"
  try {
    assert.equal(tr("vi", "__onlyEn"), "english")
  } finally {
    delete table.vi.__onlyEn
    delete table.en.__onlyEn
  }
})

test("every key used in the QML exists in both languages", () => {
  const used = new Set()
  for (const file of ["BarWidget.qml", "Panel.qml"]) {
    // Matches tr("key") and tr(cond ? "a" : "b"); the tr(key) definitions have no quotes.
    for (const call of read(file).matchAll(/\btr\(([^)]*)\)/g))
      for (const lit of call[1].matchAll(/"([^"]+)"/g)) used.add(lit[1])
  }
  assert.ok(used.size > 10, `only found ${used.size} keys; did the tr() pattern change?`)
  for (const key of used) {
    assert.ok(key in table.vi, `missing vi.${key}`)
    assert.ok(key in table.en, `missing en.${key}`)
  }
})
