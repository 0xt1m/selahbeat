import { createAccount, deleteAccount, resetRecoveryCode } from '@/lib/accounts';
import { accountFor, unauthorised } from '@/lib/api-auth';

export const dynamic = 'force-dynamic';

/**
 * Mints an anonymous account plus the first device credential.
 *
 * No email, no password, nothing about a person: the app calls this once on
 * first launch and keeps what comes back in the Keychain.
 */
export async function POST() {
  const { account, deviceId, secret, recoveryCode } = createAccount();
  return Response.json({
    accountId: account.id,
    deviceId,
    secret,
    recoveryCode,
    token: `${deviceId}.${secret}`,
  });
}

/** A new recovery code, retiring the old one. */
export async function PATCH(request: Request) {
  const account = accountFor(request);
  if (!account) return unauthorised();
  return Response.json({ recoveryCode: resetRecoveryCode(account.id) });
}

/** Erases everything stored for this account, including shares it owns. */
export async function DELETE(request: Request) {
  const account = accountFor(request);
  if (!account) return unauthorised();
  deleteAccount(account.id);
  return Response.json({ deleted: true });
}
