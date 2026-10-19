/** @type {import('next').NextConfig} */
const nextConfig = {
  // Standalone output keeps the Docker image small on EC2 — it bundles only
  // the server files actually needed at runtime.
  output: 'standalone',
  // better-sqlite3 is a native module; it must stay external to the bundle.
  serverExternalPackages: ['better-sqlite3'],
  // The image optimiser is disabled outright. This site has no next/image
  // anywhere, so the endpoint was nothing but attack surface - and it is what
  // was used to poison the response cache in October 2026: a crafted request
  // cached attacker-controlled bytes under a key ordinary visitors hit, which
  // served a fake CAPTCHA telling people to paste a command into Terminal.
  images: { unoptimized: true },

  // No in-memory response cache. Every page here is either dynamic or admin
  // only, so caching buys nothing and a cache is the thing that turns one bad
  // response into one served to everybody.
  cacheMaxMemorySize: 0,

  // Public API lives at /v1/* (clean, versioned) while the handlers stay in
  // Next's /api convention.
  async rewrites() {
    return [{ source: '/v1/:path*', destination: '/api/v1/:path*' }];
  },
};

export default nextConfig;
