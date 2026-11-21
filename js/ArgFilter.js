.pragma library
// Drop program arguments that look like secrets before they are stored (design D12). Pure. When unsure, drop.
// filter(argv) returns { argv, dropped }: the kept arguments in order, and how many arguments were removed.
// A secret looking flag takes its value with it: `--token abc` removes both, `--token=abc` removes the one argument.

const SECRET_NAME = /(password|passwd|passphrase|pwd|token|secret|apikey|api-key|api_key|auth|credential|bearer|private-key|private_key|cookie|session)/i
const SECRET_PREFIX = /^(sk-|sk_|pk_live|rk_live|ghp_|gho_|ghs_|ghu_|ghr_|github_pat_|glpat-|xox[abprs]-|AKIA[0-9A-Z]{8}|AIza[0-9A-Za-z_-]{10}|eyJ[A-Za-z0-9_-]{8,}\.)/
const URL_WITH_PASSWORD = /[a-z][a-z0-9+.-]*:\/\/[^\/\s@]*:[^\/\s@]*@/i

function isSecretFlagName(flag) {
  const name = flag.replace(/^-+/, "").toLowerCase()
  if (name === "key" || /[-_]key$/.test(name) || /^key[-_]/.test(name)) return true
  return SECRET_NAME.test(name)
}

function entropy(s) {
  const counts = {}
  for (const ch of s) counts[ch] = (counts[ch] || 0) + 1
  let h = 0
  for (const k of Object.keys(counts)) { const p = counts[k] / s.length; h -= p * Math.log2(p) }
  return h
}

// A value that is long and random looking: 20 or more of base64 or hex characters, mixing letters and digits, high entropy.
function looksRandom(v) {
  if (v.length < 20 || !/^[A-Za-z0-9+\/=_-]+$/.test(v)) return false
  if (/^[\/.~]/.test(v)) return false // a path
  const letters = /[A-Za-z]/.test(v), digits = /\d/.test(v)
  const h = entropy(v)
  if (letters && digits && h >= 3.3) return true
  return v.length >= 32 && /[a-z]/.test(v) && /[A-Z]/.test(v) && h >= 4.0
}

function valueLooksSecret(v) {
  return SECRET_PREFIX.test(v) || URL_WITH_PASSWORD.test(v) || looksRandom(v)
}

function secretArg(a) {
  if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(a)) return true // NAME=value environment assignment
  if (valueLooksSecret(a)) return true
  const eq = a.indexOf("=")
  if (a.charAt(0) === "-" && eq !== -1) {
    if (isSecretFlagName(a.slice(0, eq))) return true
    if (valueLooksSecret(a.slice(eq + 1))) return true
  }
  return false
}

function filter(argv) {
  const out = []
  let dropped = 0
  const list = Array.isArray(argv) ? argv.map(String) : []
  for (let i = 0; i < list.length; i++) {
    const a = list[i]
    if (a.charAt(0) === "-" && a.indexOf("=") === -1 && isSecretFlagName(a)) {
      dropped++
      const next = list[i + 1]
      if (next !== undefined && next.charAt(0) !== "-") { dropped++; i++ }
      continue
    }
    if (secretArg(a)) { dropped++; continue }
    out.push(a)
  }
  return { argv: out, dropped }
}
