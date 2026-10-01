import { authenticate, type Account } from './accounts';

/** Pulls the account out of a request, or explains why it could not. */
export function accountFor(request: Request): Account | null {
  return authenticate(request.headers.get('authorization'));
}

export function unauthorised() {
  return Response.json({ error: 'Not authorised' }, { status: 401 });
}

export function badRequest(message: string) {
  return Response.json({ error: message }, { status: 400 });
}
