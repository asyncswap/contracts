// Assemble the site's generated pages from the repository before `vocs dev` / `vocs build`:
//   - docs/*.md                          -> src/pages/protocol/
//   - audit/auditagent_report_1_status.md -> src/pages/audit/status.md
//   - `forge doc` (NatSpec in src/)       -> src/pages/reference/src/ + src/generated/reference-sidebar.ts
// docs/ and audit/ stay the source of truth; everything written here is git-ignored.
import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, posix, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const site = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const repo = resolve(site, '..')
const pages = join(site, 'src/pages')
const blob = 'https://github.com/asyncswap/contracts/blob/main/'

// Repository file -> site route, for every page the site publishes.
const routes = {
  'README.md': '/',
  'docs/protocol.md': '/protocol/overview',
  'docs/order-lifecycle.md': '/protocol/order-lifecycle',
  'docs/contract-call-sequences.md': '/protocol/contract-call-sequences',
  'docs/price-key-crossing.md': '/protocol/price-key-crossing',
  'docs/dynamic-fee-ordering.md': '/protocol/dynamic-fee-ordering',
  'docs/deployments.md': '/deployments',
  'audit/auditagent_report_1_status.md': '/audit/status',
}

// One-line summaries for the generated guides: vocs reads them from frontmatter into llms.txt.
const descriptions = {
  '/protocol/overview': 'Contracts, custody, fees and authorization of the Async Swap hook, in diagrams.',
  '/protocol/order-lifecycle': 'How an order is placed, matched, filled, repriced and cancelled, and how priority bids are paid.',
  '/protocol/contract-call-sequences': 'Step-by-step contract calls for placing, matching, filling and cancelling orders.',
  '/protocol/price-key-crossing': 'How limit prices map to price keys and when two orders cross.',
  '/protocol/dynamic-fee-ordering': 'The dynamic fee charged on pool fills that move the price back, split between LPs and the protocol.',
  '/deployments': 'Contract addresses on the four testnets (Unichain Sepolia, Sepolia, Robinhood Chain testnet, Arc testnet); no mainnet yet. Also at /deployments.json.',
  '/audit/status': 'Status of each finding from the first AuditAgent report.',
}

function reset(dir) {
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
}

/// Point relative links at site routes when the target is published, and at GitHub otherwise.
function rewriteLinks(markdown, source) {
  return markdown.replace(/(!?)\[([^\]]*)\]\(([^)\s]+)\)/g, (match, bang, text, target) => {
    if (/^(https?:|mailto:|#|\/)/.test(target)) return match
    const [path, anchor] = target.split('#')
    const file = posix.normalize(posix.join(posix.dirname(source), path))
    const hash = anchor ? `#${anchor}` : ''
    if (bang && file.startsWith('docs/assets/')) return `${bang}[${text}](/assets/${file.slice('docs/assets/'.length)})`
    if (routes[file]) return `[${text}](${routes[file]}${hash})`
    return `${bang}[${text}](${blob}${file}${hash})`
  })
}

/// Every network's registry (deployments/<chainId>/<chainId>.json) with its chains.json entry, for agents and apps.
function deployments() {
  const { chains } = JSON.parse(readFileSync(join(repo, 'script/config/chains.json'), 'utf8'))
  const byId = Object.fromEntries(Object.entries(chains).map(([key, chain]) => [chain.chainId, { key, ...chain }]))
  const dir = join(repo, 'deployments')
  return readdirSync(dir)
    .filter((id) => /^\d+$/.test(id) && existsSync(join(dir, id, `${id}.json`)) && byId[id]?.network !== 'local')
    .map((id) => {
      const record = JSON.parse(readFileSync(join(dir, id, `${id}.json`), 'utf8'))
      const chain = byId[id]
      return {
        chainId: record.chainId,
        name: chain?.name ?? null,
        network: chain?.network ?? null,
        explorerUrl: chain?.explorerUrl ?? null,
        numeraire: chain?.contracts?.usdc ?? null,
        contracts: record.contracts,
      }
    })
    .sort((a, b) => a.chainId - b.chainId)
}

function syncGuides() {
  reset(join(pages, 'protocol'))
  reset(join(pages, 'audit'))
  for (const [file, route] of Object.entries(routes)) {
    if (route === '/') continue // the home page is written by hand
    const out = join(pages, `${route.slice(1)}.md`)
    mkdirSync(dirname(out), { recursive: true })
    const front = descriptions[route] ? `---\ndescription: ${descriptions[route]}\n---\n\n` : ''
    writeFileSync(out, front + rewriteLinks(readFileSync(join(repo, file), 'utf8'), file))
  }
  writeFileSync(join(site, 'public/deployments.json'), JSON.stringify(deployments(), null, 2) + '\n')
  reset(join(site, 'public/assets'))
  cpSync(join(repo, 'docs/assets'), join(site, 'public/assets'), { recursive: true })
}

const groupNames = { src: 'Contracts', 'src/interfaces': 'Interfaces', 'src/libraries': 'Libraries', 'src/types': 'Types' }

// forge names pages `contract.Router`, `library.AsyncMatching`, ... The dot reads as a file extension
// to static hosts, so routes drop the kind: /reference/src/Router.
const kind = /(^|\/)(contract|abstract|interface|library|struct|enum|function|constants|type|error|event)\./
const route = (path) => path.replace(kind, '$1')

function syncReference() {
  const out = mkdtempSync(join(tmpdir(), 'forge-doc-'))
  try {
    // An explicit --out keeps forge from writing its scaffold into docs/.
    execFileSync('forge', ['doc', '--out', out], { cwd: repo, stdio: ['ignore', 'ignore', 'inherit'] })

    const target = join(pages, 'reference/src')
    reset(target)
    const relinkPage = (text) =>
      text.replace(/\]\(\/src\/([^)#]*)/g, (_, path) => `](/reference/src/${route(path)}`)
    const copy = (from, to) => {
      for (const name of readdirSync(from)) {
        const src = join(from, name)
        if (statSync(src).isDirectory()) {
          mkdirSync(join(to, name), { recursive: true })
          copy(src, join(to, name))
        } else if (name.endsWith('.mdx') || name.endsWith('.md')) {
          const dest = join(to, route(name))
          if (existsSync(dest)) throw new Error(`two reference pages map to ${relative(site, dest)}`)
          writeFileSync(dest, relinkPage(readFileSync(src, 'utf8')))
        }
      }
    }
    copy(join(out, 'src/pages/src'), target)

    // forge writes `export const sidebar = [...]` as plain object literals.
    const body = readFileSync(join(out, 'vocs.sidebar.ts'), 'utf8').replace(/^[\s\S]*?export const sidebar\s*=\s*/, '')
    const generated = new Function(`return ${body.replace(/;\s*$/, '')}`)()
    const relink = (item) => ({
      ...item,
      ...(item.link ? { link: `/reference${route(item.link)}` } : {}),
      ...(item.items ? { items: item.items.map(relink) } : {}),
    })
    const sidebar = generated.map((group) => ({ ...relink(group), text: groupNames[group.text] ?? group.text, collapsed: true }))
    mkdirSync(join(site, 'src/generated'), { recursive: true })
    writeFileSync(
      join(site, 'src/generated/reference-sidebar.ts'),
      `// Generated by scripts/sync.mjs from \`forge doc\`. Do not edit.\nexport const sidebar = ${JSON.stringify(sidebar, null, 2)}\n`,
    )
  } finally {
    rmSync(out, { recursive: true, force: true })
  }
}

syncGuides()
syncReference()
const count = (dir) => (existsSync(dir) ? readdirSync(dir, { recursive: true }).filter((f) => /\.mdx?$/.test(f)).length : 0)
console.log(
  `synced ${count(join(pages, 'protocol')) + count(join(pages, 'audit'))} guides and ${count(join(pages, 'reference/src'))} reference pages into ${relative(repo, pages)}`,
)
