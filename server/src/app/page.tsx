import Link from 'next/link';
import { stats } from '@/lib/catalog';

export const dynamic = 'force-dynamic';

type Release = {
  tag_name: string;
  html_url: string;
  published_at: string;
  assets: { name: string; browser_download_url: string; size: number }[];
};

/** Best-effort: the page must still render if GitHub is unreachable. */
async function latestRelease(): Promise<Release | null> {
  const repo = process.env.GITHUB_REPO ?? '0xt1m/selahbeat';
  try {
    const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
      next: { revalidate: 300 },
    });
    if (!response.ok) return null;
    return (await response.json()) as Release;
  } catch {
    return null;
  }
}

export default async function LandingPage() {
  const [release, catalog] = await Promise.all([latestRelease(), Promise.resolve(stats())]);
  const dmg = release?.assets.find((a) => a.name.endsWith('.dmg'));

  return (
    <main className="min-h-screen">
      <header className="mx-auto flex max-w-5xl items-center justify-between px-6 py-6">
        <div className="flex items-center gap-2">
          <span className="text-2xl">🥁</span>
          <span className="text-lg font-semibold tracking-tight">SelahBeat</span>
        </div>
        <nav className="flex items-center gap-6 text-sm text-neutral-400">
          <a href="#features" className="hover:text-neutral-100">Features</a>
          <a href="#catalog" className="hover:text-neutral-100">Catalog</a>
          <Link href="/admin" className="hover:text-neutral-100">Admin</Link>
        </nav>
      </header>

      <section className="mx-auto max-w-5xl px-6 pb-20 pt-16 text-center">
        <p className="mb-4 text-sm font-semibold uppercase tracking-[0.2em] text-accent">
          For worship drummers
        </p>
        <h1 className="mx-auto max-w-3xl text-5xl font-bold leading-tight tracking-tight sm:text-6xl">
          The click starts the moment you hit start.
        </h1>
        <p className="mx-auto mt-6 max-w-2xl text-lg text-neutral-400">
          Stop mid-song and start again without throwing the band off. Build your set list,
          keep a tempo for every song, and look up the ones you don&apos;t know — all of it
          working with no connection at all.
        </p>

        <div className="mt-10 flex flex-col items-center justify-center gap-3 sm:flex-row">
          {dmg ? (
            <a
              href={dmg.browser_download_url}
              className="rounded-xl bg-accent px-7 py-3.5 font-semibold text-black transition hover:brightness-110"
            >
              Download for macOS
            </a>
          ) : (
            <span className="rounded-xl border border-neutral-700 px-7 py-3.5 font-semibold text-neutral-400">
              macOS build coming soon
            </span>
          )}
          {release && (
            <a
              href={release.html_url}
              className="rounded-xl border border-neutral-700 px-7 py-3.5 font-semibold text-neutral-300 transition hover:border-neutral-500"
            >
              Release notes — {release.tag_name}
            </a>
          )}
        </div>
        <p className="mt-4 text-xs text-neutral-500">
          macOS 14 or later. iOS coming next. Updates install themselves.
        </p>
      </section>

      <section id="features" className="mx-auto max-w-5xl px-6 pb-24">
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <Feature
            title="Instant start"
            body="The audio engine runs from the moment the app opens, so pressing start costs nothing. The first click lands in a few milliseconds — every time, not on average."
          />
          <Feature
            title="Works with no signal"
            body="Your services, songs and the whole song catalog live on your device. Church wifi failing is not the app's problem."
          />
          <Feature
            title="Tap the tempo"
            body="Tap along and it locks on. A fumbled tap gets rejected instead of wrecking the estimate."
          />
          <Feature
            title="Build a service"
            body="Group songs into a service, drag them into order, and set the key your team is playing this week. Duplicate last week's set in one click."
          />
          <Feature
            title="Every meter"
            body="4/4, 3/4, 6/8 felt in two, 7/8 grouped 2+2+3 — and you can accent or mute any individual beat."
          />
          <Feature
            title="Six click sounds"
            body="Beep, woodblock, cowbell, stick, rim and a soft pulse that won't wear out your ears across a ninety-minute service."
          />
        </div>
      </section>

      <section id="catalog" className="border-t border-neutral-900 bg-surface/40">
        <div className="mx-auto max-w-5xl px-6 py-16 text-center">
          <h2 className="text-3xl font-bold tracking-tight">A shared tempo catalog</h2>
          <p className="mx-auto mt-4 max-w-xl text-neutral-400">
            {catalog.total} songs with tempos, meters and keys — searchable right inside the
            app, and cached on your device so it keeps working offline.
          </p>
          <div className="mt-8 flex justify-center gap-10 text-sm">
            <Stat label="Songs" value={String(catalog.total)} />
            <Stat label="Tempo verified" value={String(catalog.verified)} />
            <Stat label="Revision" value={String(catalog.revision)} />
          </div>
        </div>
      </section>

      <footer className="mx-auto max-w-5xl px-6 py-10 text-center text-sm text-neutral-600">
        SelahBeat — built for the people counting it in.
      </footer>
    </main>
  );
}

function Feature({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-2xl border border-neutral-900 bg-surface p-6 text-left">
      <h3 className="mb-2 font-semibold">{title}</h3>
      <p className="text-sm leading-relaxed text-neutral-400">{body}</p>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-3xl font-bold text-accent">{value}</div>
      <div className="mt-1 text-xs uppercase tracking-wider text-neutral-500">{label}</div>
    </div>
  );
}
