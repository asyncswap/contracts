import { defineConfig } from 'vocs/config'
// Written by scripts/sync.mjs from `forge doc`; not committed.
import { sidebar as referenceSidebar } from './src/generated/reference-sidebar.ts'

export default defineConfig({
  title: 'AsyncSwap',
  description:
    'An on-chain order book and matching engine built as a Uniswap v4 hook: limit orders against USDC, matched by price, priority bid and time.',
  // vocs emits <base href={baseUrl}>, so it is set only for the published build (the docs workflow);
  // left unset, local `dev`/`preview` load everything from localhost.
  baseUrl: process.env.DOCS_BASE_URL,
  // Static HTML for every page, so the site is served from GitHub Pages.
  renderStrategy: 'full-static',
  iconUrl: '/favicon.svg',
  logoUrl: { light: '/logo-light.svg', dark: '/logo-dark.svg' },
  accentColor: 'light-dark(#ff7819, #ff9038)',
  topNav: [
    { text: 'Protocol', link: '/protocol/overview' },
    { text: 'Contracts', link: '/reference' },
    { text: 'App', link: 'https://app.asyncswap.org' },
  ],
  socials: [{ icon: 'github', link: 'https://github.com/asyncswap/contracts' }],
  sidebar: [
    { text: 'Introduction', link: '/' },
    {
      text: 'Protocol',
      items: [
        { text: 'Overview', link: '/protocol/overview' },
        { text: 'Order lifecycle and priority bids', link: '/protocol/order-lifecycle' },
        { text: 'Contract call sequences', link: '/protocol/contract-call-sequences' },
        { text: 'Price keys and crossing', link: '/protocol/price-key-crossing' },
      ],
    },
    {
      text: 'Security',
      items: [{ text: 'Audit status', link: '/audit/status' }],
    },
    {
      text: 'Contract reference',
      items: [{ text: 'Overview', link: '/reference' }, ...referenceSidebar],
    },
  ],
})
