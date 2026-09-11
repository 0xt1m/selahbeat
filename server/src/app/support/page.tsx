import Link from 'next/link';

export const metadata = {
  title: 'Support — SelahBeat',
  description: 'Help and contact for SelahBeat, the metronome for worship drummers.',
};

const REPO = process.env.GITHUB_REPO ?? '0xt1m/selahbeat';

export default function SupportPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <Link href="/" className="text-sm text-neutral-500 hover:text-neutral-300">
        ← SelahBeat
      </Link>

      <h1 className="mt-6 text-3xl font-bold tracking-tight">Support</h1>

      <div className="mt-10 space-y-8 text-[15px] leading-relaxed text-neutral-300">
        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">Get in touch</h2>
          <p>
            Email <span className="text-neutral-100">tym.matviiv@gmail.com</span> and
            describe what happened. If it&apos;s a timing problem, the Diagnostics panel
            (Settings → Diagnostics) shows your sample rate, buffer size, output route and
            measured latency — including those numbers helps enormously.
          </p>
        </section>

        <section>
          <h2 className="mb-3 text-lg font-semibold text-neutral-100">Common questions</h2>

          <div className="space-y-5">
            <div>
              <h3 className="font-semibold text-neutral-100">The click feels late or loose</h3>
              <p className="mt-1">
                Almost always Bluetooth. AirPods and Bluetooth speakers add 150–300&nbsp;ms of
                delay that no app can remove — the audio is encoded, transmitted and decoded
                before you hear it. SelahBeat shows a warning when it detects a Bluetooth
                route. Use wired headphones or in-ears for anything you&apos;re playing to.
              </p>
            </div>

            <div>
              <h3 className="font-semibold text-neutral-100">The click stops when my phone locks</h3>
              <p className="mt-1">
                It shouldn&apos;t — SelahBeat keeps playing with the screen off. If it stops,
                check that iOS Low Power Mode isn&apos;t aggressively suspending it, and that
                no other app has taken over audio.
              </p>
            </div>

            <div>
              <h3 className="font-semibold text-neutral-100">Can I use it with backing tracks?</h3>
              <p className="mt-1">
                Yes. Turn on Settings → Sound → &ldquo;Allow other apps to play at the same
                time&rdquo; so SelahBeat mixes with your tracks instead of interrupting them.
              </p>
            </div>

            <div>
              <h3 className="font-semibold text-neutral-100">A song&apos;s tempo looks wrong</h3>
              <p className="mt-1">
                Catalog tempos are a starting point for common arrangements and may not match
                the version your team plays. Edit the song, or set a per-service tempo so the
                change applies only to that week. Tell us and we&apos;ll correct the catalog.
              </p>
            </div>

            <div>
              <h3 className="font-semibold text-neutral-100">Do I need an internet connection?</h3>
              <p className="mt-1">
                No. The metronome, your services and every song you&apos;ve saved work fully
                offline. A connection is only used to look up new songs and to check for
                updates.
              </p>
            </div>

            <div>
              <h3 className="font-semibold text-neutral-100">Where is my data?</h3>
              <p className="mt-1">
                On your device only. Nothing is uploaded — see the{' '}
                <Link href="/privacy" className="text-accent underline underline-offset-2">
                  privacy policy
                </Link>
                .
              </p>
            </div>
          </div>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">Developer</h2>
          <p className="mb-3">SelahBeat is built by Tymofii Matviiv.</p>
          <ul className="space-y-1.5">
            <li>
              <a href="https://0xt1m.com" className="text-accent underline underline-offset-2">
                0xt1m.com
              </a>
            </li>
            <li>
              <a
                href="https://www.linkedin.com/in/0xt1m/"
                rel="noopener noreferrer"
                target="_blank"
                className="text-accent underline underline-offset-2"
              >
                LinkedIn
              </a>
            </li>
            <li>
              <a
                href="https://github.com/0xt1m"
                rel="noopener noreferrer"
                target="_blank"
                className="text-accent underline underline-offset-2"
              >
                GitHub
              </a>
            </li>
          </ul>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">Report a bug</h2>
          <p>
            Issues and release notes live at{' '}
            <a
              href={`https://github.com/${REPO}`}
              className="text-accent underline underline-offset-2"
            >
              github.com/{REPO}
            </a>
            .
          </p>
        </section>
      </div>
    </main>
  );
}
