import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { JwtPayload } from '../../common/decorators/current-user.decorator';
import { UserRole } from '../users/user.entity';
import { ChatbotService } from './chatbot.service';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const UNAVAILABLE = 'แชทบอทไม่พร้อมใช้งานชั่วคราว กรุณาลองใหม่อีกครั้ง หรือโทร 081-598-1199';

const customer: JwtPayload = { sub: 'c1', email: 'c@x.th', role: UserRole.CUSTOMER };
const staff: JwtPayload = { sub: 's1', email: 's@x.th', role: UserRole.STAFF };
const admin: JwtPayload = { sub: 'a1', email: 'a@x.th', role: UserRole.ADMIN };

/** What the chatbot actually returns, debug fields included. */
const botReply = {
  session_id: 'sess-1',
  answer: 'มีห้องว่างค่ะ',
  answered: true,
  sources: [{ title: 'kb' }],
  confidence: 0.9,
  retrieval_score: 0.8,
  tools_used: ['search_rooms'],
  token_usage: { total: 123 },
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('ChatbotService', () => {
  const originalEnv = {
    CHATBOT_URL: process.env.CHATBOT_URL,
    CHATBOT_TIMEOUT_MS: process.env.CHATBOT_TIMEOUT_MS,
  };
  const realFetch = global.fetch;
  let fetchMock: jest.Mock;
  let warn: jest.SpyInstance;
  let service: ChatbotService;

  beforeEach(() => {
    process.env.CHATBOT_URL = 'http://bot.test:8000/';
    process.env.CHATBOT_TIMEOUT_MS = '50';
    fetchMock = jest.fn().mockResolvedValue(jsonResponse(botReply));
    global.fetch = fetchMock;
    warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    service = new ChatbotService();
  });

  afterEach(() => {
    global.fetch = realFetch;
    jest.restoreAllMocks();
  });

  afterAll(() => {
    for (const [key, value] of Object.entries(originalEnv)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  const sentRequest = () => {
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    return {
      url,
      init,
      headers: init.headers as Record<string, string>,
      body: JSON.parse(init.body as string),
    };
  };

  it('posts the snake_case contract body to the chatbot endpoint', async () => {
    await service.query(
      { message: 'ห้องว่างไหม', sessionId: 'sess-1', language: 'en' }, undefined, undefined,
    );
    const { url, init, body } = sentRequest();
    expect(url).toBe('http://bot.test:8000/api/v1/chatbot/query');
    expect(init.method).toBe('POST');
    expect(body).toEqual({ session_id: 'sess-1', message: 'ห้องว่างไหม', language: 'en' });
  });

  it('returns only sessionId, answer and answered — no debug fields', async () => {
    const reply = await service.query({ message: 'hi', sessionId: 'sess-1' }, undefined, undefined);
    expect(reply).toEqual({ sessionId: 'sess-1', answer: 'มีห้องว่างค่ะ', answered: true });
  });

  it('generates a session id when none is given and defaults language to th', async () => {
    fetchMock.mockImplementation(async (_url: string, init: RequestInit) => {
      const { session_id } = JSON.parse(init.body as string);
      return jsonResponse({ ...botReply, session_id });
    });
    const reply = await service.query({ message: 'hi' }, undefined, undefined);
    const { body } = sentRequest();
    expect(body.session_id).toMatch(UUID_RE);
    expect(body.language).toBe('th');
    expect(reply.sessionId).toBe(body.session_id);
  });

  it('forwards the bearer token for a customer', async () => {
    await service.query({ message: 'การจองของฉัน' }, customer, 'customer-token');
    expect(sentRequest().headers.Authorization).toBe('Bearer customer-token');
  });

  it.each([
    ['staff', staff],
    ['admin', admin],
  ])('does not forward a %s token', async (_label, user) => {
    await service.query({ message: 'hi' }, user, 'privileged-token');
    expect(sentRequest().headers).not.toHaveProperty('Authorization');
  });

  it('sends no Authorization header for an anonymous caller', async () => {
    await service.query({ message: 'hi' }, undefined, undefined);
    expect(sentRequest().headers).not.toHaveProperty('Authorization');
  });

  it('maps a connection failure to 503', async () => {
    fetchMock.mockRejectedValue(new TypeError('fetch failed'));
    await expect(service.query({ message: 'hi' }, undefined, undefined))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('maps a timeout to 503 using the configured timeout', async () => {
    fetchMock.mockImplementation((_url: string, init: RequestInit) =>
      new Promise((_resolve, reject) => {
        init.signal!.addEventListener('abort', () => reject(init.signal!.reason));
      }));
    await expect(service.query({ message: 'hi' }, undefined, undefined))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(JSON.stringify(warn.mock.calls)).toContain('TimeoutError');
  });

  it('maps a non-2xx response to 503 with the Thai message', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ detail: 'boom' }, 500));
    await expect(service.query({ message: 'hi' }, undefined, undefined))
      .rejects.toThrow(UNAVAILABLE);
  });

  it('maps a malformed response to 503', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ answer: 'no session id or answered flag' }));
    await expect(service.query({ message: 'hi' }, undefined, undefined))
      .rejects.toBeInstanceOf(ServiceUnavailableException);

    fetchMock.mockResolvedValue(new Response('<html>bad gateway</html>', { status: 200 }));
    await expect(service.query({ message: 'hi' }, undefined, undefined))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('never logs the token or the message', async () => {
    fetchMock.mockResolvedValue(jsonResponse({}, 502));
    await expect(service.query({ message: 'secret-question' }, customer, 'secret-token'))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
    const logged = JSON.stringify(warn.mock.calls);
    expect(logged).toContain('502');
    expect(logged).not.toContain('secret-token');
    expect(logged).not.toContain('secret-question');
  });
});
