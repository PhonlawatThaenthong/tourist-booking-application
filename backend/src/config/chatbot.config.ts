/**
 * Where the chatbot service (separate FastAPI repo) lives. The API proxies
 * `/api/chatbot/query` to it; the chatbot's own port is never exposed to the app.
 *
 * Inside docker compose `CHATBOT_URL` is overridden to http://chatbot:8000.
 */
export interface ChatbotConfig {
  url: string;
  timeoutMs: number;
}

export function getChatbotConfig(): ChatbotConfig {
  return {
    url: (process.env.CHATBOT_URL ?? 'http://localhost:8000').replace(/\/+$/, ''),
    // One question can cost up to 4 LLM calls (3 tool rounds + the final
    // answer), each with a 30 s timeout on the chatbot side.
    timeoutMs: Number(process.env.CHATBOT_TIMEOUT_MS ?? 90_000),
  };
}
