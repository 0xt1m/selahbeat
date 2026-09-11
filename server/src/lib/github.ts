/**
 * GitHub Releases lookups for the landing page.
 *
 * Every call is best-effort: the page must still render if GitHub is slow,
 * rate-limited, or the repo is private. Failures return null rather than
 * throwing, and callers hide the affected UI instead of showing zeros.
 */

const REPO = process.env.GITHUB_REPO ?? '0xt1m/selahbeat';

export type ReleaseAsset = {
  name: string;
  browser_download_url: string;
  size: number;
  download_count: number;
};

export type Release = {
  tag_name: string;
  html_url: string;
  published_at: string;
  draft?: boolean;
  prerelease?: boolean;
  assets: ReleaseAsset[];
};

/** Unauthenticated unless a token is present; a private repo returns 404. */
function headers(): HeadersInit {
  const base: HeadersInit = { Accept: 'application/vnd.github+json' };
  const token = process.env.GITHUB_TOKEN;
  return token ? { ...base, Authorization: `Bearer ${token}` } : base;
}

export async function fetchLatestRelease(): Promise<Release | null> {
  try {
    const response = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: headers(),
      next: { revalidate: 300 },
    });
    if (!response.ok) return null;
    return (await response.json()) as Release;
  } catch {
    return null;
  }
}

/**
 * Assets that represent someone actually getting the app.
 *
 * `appcast.xml` is excluded deliberately: Sparkle fetches it on every launch of
 * every install, so counting it would inflate the number by orders of magnitude
 * and measure update checks rather than downloads.
 *
 * The .dmg is a person downloading from the site; the .zip is Sparkle
 * delivering an update to someone who already has it. Both are the app
 * reaching a machine, so both count.
 */
function isAppAsset(asset: ReleaseAsset): boolean {
  return asset.name.endsWith('.dmg') || asset.name.endsWith('.zip');
}

export type DownloadStats = {
  total: number;
  installs: number;   // .dmg — fresh downloads from the site
  updates: number;    // .zip — Sparkle updates
};

/** Summed across every published release, so it is a lifetime total. */
export async function fetchDownloadStats(): Promise<DownloadStats | null> {
  try {
    const response = await fetch(
      `https://api.github.com/repos/${REPO}/releases?per_page=100`,
      { headers: headers(), next: { revalidate: 600 } }
    );
    if (!response.ok) return null;

    const releases = (await response.json()) as Release[];
    if (!Array.isArray(releases)) return null;

    let installs = 0;
    let updates = 0;

    for (const release of releases) {
      if (release.draft) continue;
      for (const asset of release.assets ?? []) {
        if (!isAppAsset(asset)) continue;
        if (asset.name.endsWith('.dmg')) installs += asset.download_count ?? 0;
        else updates += asset.download_count ?? 0;
      }
    }

    return { total: installs + updates, installs, updates };
  } catch {
    return null;
  }
}

export { isAppAsset };
