'use client';

import { useActionState } from 'react';
import { login } from '../actions';

export default function LoginPage() {
  const [state, action, pending] = useActionState(login, null as { error?: string } | null);

  return (
    <main className="flex min-h-screen items-center justify-center px-6">
      <form action={action} className="w-full max-w-sm rounded-2xl border border-neutral-800 bg-surface p-8">
        <h1 className="mb-1 text-xl font-semibold">SelahBeat admin</h1>
        <p className="mb-6 text-sm text-neutral-500">Manage the shared song catalog.</p>

        <label className="mb-2 block text-sm text-neutral-400" htmlFor="password">
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoFocus
          className="mb-4 w-full rounded-lg border border-neutral-700 bg-ink px-3 py-2 outline-none focus:border-accent"
        />

        {state?.error && <p className="mb-4 text-sm text-red-400">{state.error}</p>}

        <button
          type="submit"
          disabled={pending}
          className="w-full rounded-lg bg-accent py-2.5 font-semibold text-black transition hover:brightness-110 disabled:opacity-50"
        >
          {pending ? 'Checking…' : 'Sign in'}
        </button>
      </form>
    </main>
  );
}
