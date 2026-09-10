/** @type {import('next').NextConfig} */
const nextConfig = {
  // Standalone output keeps the Docker image small on EC2 — it bundles only
  // the server files actually needed at runtime.
  output: 'standalone',
  // better-sqlite3 is a native module; it must stay external to the bundle.
  serverExternalPackages: ['better-sqlite3'],
  // Public API lives at /v1/* (clean, versioned) while the handlers stay in
  // Next's /api convention.
  async rewrites() {
    return [{ source: '/v1/:path*', destination: '/api/v1/:path*' }];
  },
};

export default nextConfig;
