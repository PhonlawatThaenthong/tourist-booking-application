import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ThrottlerStorage } from '@nestjs/throttler';
import { InternalAwareThrottlerGuard } from './internal-aware-throttler.guard';

/** Exposes the protected hook under test. */
class TestableGuard extends InternalAwareThrottlerGuard {
  skip(context: ExecutionContext) {
    return this.shouldSkip(context);
  }
}

const SECRET = 'a'.repeat(64);

function contextFor(method: string, headers: Record<string, unknown>): ExecutionContext {
  const req = { method, headers };
  return { switchToHttp: () => ({ getRequest: () => req }) } as unknown as ExecutionContext;
}

describe('InternalAwareThrottlerGuard', () => {
  const original = process.env.CHATBOT_INTERNAL_KEY;
  let guard: TestableGuard;

  beforeEach(() => {
    process.env.CHATBOT_INTERNAL_KEY = SECRET;
    guard = new TestableGuard(
      { throttlers: [{ name: 'default', ttl: 60_000, limit: 120 }] },
      {} as ThrottlerStorage,
      new Reflector(),
    );
  });

  afterAll(() => {
    if (original === undefined) delete process.env.CHATBOT_INTERNAL_KEY;
    else process.env.CHATBOT_INTERNAL_KEY = original;
  });

  it('skips a GET carrying the correct key', async () => {
    await expect(guard.skip(contextFor('GET', { 'x-internal-key': SECRET }))).resolves.toBe(true);
  });

  it('counts a GET with the wrong key', async () => {
    const wrong = 'b'.repeat(64);
    await expect(guard.skip(contextFor('GET', { 'x-internal-key': wrong }))).resolves.toBe(false);
  });

  it('counts a GET with a key of a different length, without throwing', async () => {
    await expect(guard.skip(contextFor('GET', { 'x-internal-key': 'short' }))).resolves.toBe(false);
    await expect(
      guard.skip(contextFor('GET', { 'x-internal-key': SECRET + 'x' })),
    ).resolves.toBe(false);
  });

  it('counts a GET without the header', async () => {
    await expect(guard.skip(contextFor('GET', {}))).resolves.toBe(false);
  });

  it('counts a repeated header (array value)', async () => {
    await expect(
      guard.skip(contextFor('GET', { 'x-internal-key': [SECRET, SECRET] })),
    ).resolves.toBe(false);
  });

  it('exempts nobody when CHATBOT_INTERNAL_KEY is unset, even for an empty header', async () => {
    delete process.env.CHATBOT_INTERNAL_KEY;
    await expect(guard.skip(contextFor('GET', { 'x-internal-key': '' }))).resolves.toBe(false);
    process.env.CHATBOT_INTERNAL_KEY = '';
    await expect(guard.skip(contextFor('GET', { 'x-internal-key': '' }))).resolves.toBe(false);
  });

  it.each(['POST', 'PUT', 'PATCH', 'DELETE'])('counts a %s even with the correct key', async (method) => {
    await expect(guard.skip(contextFor(method, { 'x-internal-key': SECRET }))).resolves.toBe(false);
  });
});
