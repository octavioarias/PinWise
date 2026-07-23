// Provider-agnostic chat interface. The Edge Function talks only to this shape, so swapping the
// underlying model (Anthropic today, another provider later) is a one-file change + an env var.

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

// A single event yielded by a provider stream.
//  - "delta": an incremental chunk of assistant text.
//  - "usage": final token accounting (may arrive once, near the end).
export type ChatEvent =
  | { type: "delta"; text: string }
  | { type: "usage"; inputTokens: number; outputTokens: number };

export interface ChatRequest {
  system: string;      // stable system prompt (the guardrails) — same for every user/turn
  context?: string;    // per-user data snapshot — stable within a conversation, varies per user
  messages: ChatMessage[];
  maxTokens?: number;
}

export interface ChatProvider {
  readonly name: string;
  // Streams the assistant response as ChatEvents. Throws on transport/HTTP errors.
  stream(req: ChatRequest): AsyncGenerator<ChatEvent>;
}
