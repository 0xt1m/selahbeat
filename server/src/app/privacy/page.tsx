import Link from 'next/link';

export const metadata = {
  title: 'Privacy Policy — SelahBeat',
  description: 'SelahBeat does not collect, store or share any personal data.',
};

const UPDATED = 'September 2026';

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <Link href="/" className="text-sm text-neutral-500 hover:text-neutral-300">
        ← SelahBeat
      </Link>

      <h1 className="mt-6 text-3xl font-bold tracking-tight">Privacy Policy</h1>
      <p className="mt-2 text-sm text-neutral-500">Last updated {UPDATED}</p>

      <div className="mt-10 space-y-8 text-[15px] leading-relaxed text-neutral-300">
        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">The short version</h2>
          <p>
            SelahBeat does not collect, store, transmit or sell any personal information.
            There are no accounts, no analytics, no advertising and no third-party tracking
            of any kind.
          </p>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">What stays on your device</h2>
          <p>
            Your services, songs, tempos, keys and settings are stored only on the device
            you created them on, in the app&apos;s own storage. They are never uploaded to us.
            If you delete the app, that data is deleted with it.
          </p>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">When the app talks to a server</h2>
          <p>SelahBeat makes network requests in exactly two situations:</p>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>
              <strong className="text-neutral-100">Song catalog sync.</strong> The app downloads
              our shared list of songs and tempos so you can look up a tempo you don&apos;t know.
              This is a one-way download. The request includes only the app version and the
              network information present in any web request, such as your IP address. We do
              not log which songs you search for, because the search runs entirely on your
              device against the downloaded copy.
            </li>
            <li>
              <strong className="text-neutral-100">Update checks.</strong> On launch, the macOS
              app asks GitHub whether a newer release exists. This is governed by{' '}
              <a
                href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement"
                className="text-accent underline underline-offset-2"
              >
                GitHub&apos;s privacy statement
              </a>
              .
            </li>
          </ul>
          <p className="mt-3">
            Both are optional in practice: the metronome, your services and your saved songs
            work with no network connection at all.
          </p>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">Microphone</h2>
          <p>
            SelahBeat does not use the microphone. Tap tempo works from your taps on the
            screen, not from listening.
          </p>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">Children</h2>
          <p>
            SelahBeat is safe for all ages and collects nothing from anyone, including
            children under 13.
          </p>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">Changes</h2>
          <p>
            If this policy ever changes — for example if accounts are introduced — the
            updated version will be posted here with a new date, and the app will not begin
            collecting anything without a clear, separate notice.
          </p>
        </section>

        <section>
          <h2 className="mb-2 text-lg font-semibold text-neutral-100">Contact</h2>
          <p>
            Questions about privacy: <span className="text-neutral-100">tym.matviiv@gmail.com</span>
          </p>
        </section>
      </div>
    </main>
  );
}
