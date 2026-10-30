import { defineConfig } from 'vocs/config'
// Written by scripts/sync.mjs from `forge doc`; not committed.
import { sidebar as referenceSidebar } from './src/generated/reference-sidebar.ts'

export default defineConfig({
  title: 'Async Swap',
  description:
    'An on-chain order book and matching engine built as a Uniswap v4 hook: limit orders against USDC, matched by price, priority bid and time.',
  // vocs emits <base href={baseUrl}>, so it is set only for the published build (the docs workflow);
  // left unset, local `dev`/`preview` load everything from localhost.
  baseUrl: process.env.DOCS_BASE_URL,
  // Static HTML for every page, so the site is served from GitHub Pages.
  renderStrategy: 'full-static',
  // Brand kit: octagonal mark + wordmark lockup, monochrome palette (Carbon #111111 / Paper #F2F2F2).
  iconUrl: '/favicon.ico',
  logoUrl: { light: '/logo-light.svg', dark: '/logo-dark.svg' },
  accentColor: 'light-dark(#111111, #F2F2F2)',
  ogImageUrl: `${process.env.DOCS_BASE_URL ?? ''}/brand/og.png`,
  head: {
    link: [
      { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/brand/icon-32.png' },
      { rel: 'apple-touch-icon', href: '/brand/apple-touch-icon.png' },
    ],
  },
  topNav: [
    { text: 'Protocol', link: '/protocol/overview' },
    { text: 'Contracts', link: '/reference' },
    { text: 'Deployments', link: '/deployments' },
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
        { text: 'Dynamic fee ordering', link: '/protocol/dynamic-fee-ordering' },
      ],
    },
    { text: 'Deployments', link: '/deployments' },
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
