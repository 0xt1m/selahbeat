import { cookies } from 'next/headers';
import crypto from 'node:crypto';

const COOKIE = 'selahbeat_admin';
const MAX_AGE = 60 * 60 * 24 * 14; // two weeks

function secret(): string {
  return process.env.SESSION_SECRET ?? 'insecure-development-secret';
}

function sign(payload: string): string {
  const mac = crypto.createHmac('sha256', secret()).update(payload).digest('hex');
  return `${payload}.${mac}`;
}

function verify(token: string): boolean {
  const index = token.lastIndexOf('.');
  if (index < 0) return false;
  const payload = token.slice(0, index);
  const expected = sign(payload);
  const a = Buffer.from(token);
  const b = Buffer.from(expected);
  // Constant-time compare so the cookie can't be brute-forced byte by byte.
  if (a.length !== b.length) return false;
  if (!crypto.timingSafeEqual(a, b)) return false;

  const expiry = Number(payload.split(':')[1]);
  return Number.isFinite(expiry) && expiry > Date.now();
}

export function checkPassword(candidate: string): boolean {
  const expected = process.env.ADMIN_PASSWORD;
  if (!expected) return false;
  const a = Buffer.from(candidate);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

export async function createSession() {
  const token = sign(`admin:${Date.now() + MAX_AGE * 1000}`);
  const jar = await cookies();
  jar.set(COOKIE, token, {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    maxAge: MAX_AGE,
  });
}

export async function destroySession() {
  const jar = await cookies();
  jar.delete(COOKIE);
}

export async function isAuthenticated(): Promise<boolean> {
  const jar = await cookies();
  const token = jar.get(COOKIE)?.value;
  return token ? verify(token) : false;
}
