import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'SelahBeat — a metronome built for worship drummers',
  description:
    'A fast, offline-first metronome for worship drummers. Build a set list, keep every tempo, and start the click the instant you need it.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
